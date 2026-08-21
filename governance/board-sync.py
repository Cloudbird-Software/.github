#!/usr/bin/env python3
"""board-sync.py —— label→Project 投影板单向同步（宪法 §12 投影一 / ADR-0055 决策 7）

真相源唯一 = issue label；org Project(v2)「factory-floor」是只读投影：
- 幂等确保项目与字段存在（State 单选=state 全集，颜色取 expected-state.json#labels）
- 对 REPOS.yaml 全部 active 仓的 open 且带 state:* 标签的卡：加/更新项目条目字段=当前 label 态
- 覆盖前比对：board 字段与 label 不一致 → WARN board-drift + 照 label 纠正（人工改动
  将被纠正并报警，宪法 §12；纠正本身是设计行为不是故障）
- 已 closed 的条目：v1 状态字段照实设（issue 最终 label 态），不删条目
- 每 run 输出 AUDIT 行（同步数/纠正数/报警数）；任何 API 失败 exit 2（fail-closed：
  投影失明不得伪装成功——butler-ledger 按 infra 处置）

驱动：butler-ledger.yml 每 15min（唤醒矩阵行 2）；board-sync.yml 仅 dispatch 演习面。
凭据：GH_TOKEN=GOVERNANCE_TOKEN（org admin PAT——GITHUB_TOKEN 无 org project 权限）。
用法：python3 governance/board-sync.py [--dry-run]（dry-run=只读对账+打印计划写，不落任何写）
"""
import datetime as _dt
import json
import os
import re
import sys
import urllib.error
import urllib.request

try:  # REPOS.yaml 解析（CI ubuntu 与治理仓 gate 环境均预装 PyYAML；本地须自备）
    import yaml
except ImportError:  # pragma: no cover
    print("FATAL 缺少 PyYAML（CI 预装；本地 pip install pyyaml）", file=sys.stderr)
    raise SystemExit(2)

ORG = "Cloudbird-Software"
PROJECT_TITLE = "factory-floor"
GH_API = "https://api.github.com"
DRY_RUN = "--dry-run" in sys.argv or os.environ.get("BOARD_SYNC_DRY_RUN") == "1"
TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GOVERNANCE_TOKEN") or ""
DIR = os.path.dirname(os.path.abspath(__file__))
NOW = _dt.datetime.now(_dt.timezone.utc)
TRIGGER = os.environ.get("BUTLER_TRIGGER") or "manual"


class Infra(Exception):
    """API/数据面故障——fail-closed exit 2，不降级继续。"""


def _req(url, body=None, method=None, graphql=False):
    headers = {"Authorization": f"Bearer {TOKEN}", "User-Agent": "board-sync",
               "Accept": "application/vnd.github+json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"message": raw}
    except Exception as e:  # 传输层失败同样 fail-closed
        raise Infra(f"请求失败 {url}: {e}") from e


def gql(query, variables):
    st, payload = _req(f"{GH_API}/graphql", {"query": query, "variables": variables}, "POST")
    if st != 200 or payload.get("errors"):
        raise Infra(f"GraphQL HTTP {st}: {json.dumps(payload.get('errors', payload), ensure_ascii=False)[:300]}")
    return payload["data"]


def api_get(path):
    st, payload = _req(f"{GH_API}{path}")
    if st != 200:
        raise Infra(f"GET {path} HTTP {st}: {str(payload.get('message'))[:120]}")
    return payload


def api_send(method, path, body, ok_codes=(200, 201)):
    st, payload = _req(f"{GH_API}{path}", body, method)
    if st not in ok_codes:
        raise Infra(f"{method} {path} HTTP {st}: {str(payload.get('message'))[:160]}")
    return payload


# ---------- 期望状态（state 全集与颜色唯一来源：expected-state.json#labels.items） ----------

def load_states():
    try:
        with open(os.path.join(DIR, "expected-state.json"), encoding="utf-8") as f:
            items = json.load(f)["labels"]["items"]
    except Exception as e:
        raise Infra(f"expected-state.json 读取失败: {e}") from e
    states = [{"name": it["name"][len("state:"):], "color": "#" + it["color"]}
              for it in items if it.get("name", "").startswith("state:")]
    if not states:
        raise Infra("expected-state.json 无 state:* 标签——期望状态缺失（fail-closed，同 drift §16）")
    return states


def active_repos():
    try:
        with open(os.path.join(DIR, "REPOS.yaml"), encoding="utf-8") as f:
            repos = yaml.safe_load(f)["repos"]
    except Exception as e:
        raise Infra(f"REPOS.yaml 读取失败: {e}") from e
    names = [r["name"] for r in repos if r.get("status") == "active"]
    if not names:
        raise Infra("REPOS.yaml 无 active 仓")
    return names


# ---------- 卡扫描（REST，真相源=issue label） ----------

def scan_cards(repos):
    """全部 active 仓 open issue 且带 state:* 标签 → 卡列表（label 是唯一判据）。"""
    cards = []
    for repo in repos:
        page = 1
        while True:
            batch = api_get(f"/repos/{ORG}/{repo}/issues?state=open&per_page=100&page={page}")
            for it in batch:
                if "pull_request" in it:  # issues 端点混入 PR——不是卡
                    continue
                sl = [l["name"] for l in it.get("labels", []) if str(l.get("name", "")).startswith("state:")]
                if not sl:
                    continue
                body = it.get("body") or ""
                boxes = re.findall(r"^\s*[-*]\s+\[( |x|X)\]", body, re.M)
                cards.append({
                    "node_id": it["node_id"], "repo": repo, "number": it["number"],
                    "title": it["title"], "state": sl[0][len("state:"):],
                    "assignee": (it.get("assignees") or [{}])[0].get("login", ""),
                    "url": it["html_url"], "updated_at": it.get("updated_at") or "",
                    "days_idle": max(0, (NOW - _dt.datetime.fromisoformat(
                        (it.get("updated_at") or NOW.isoformat()).replace("Z", "+00:00"))).days),
                    "ac_progress": (f"{sum(1 for b in boxes if b.strip())}/{len(boxes)}" if boxes else ""),
                })
            if len(batch) < 100:
                break
            page += 1
    return cards


# ---------- Project(v2) 幂等准备 ----------

Q_ORG = """query($org:String!){ organization(login:$org){
  id projectsV2(first:100){ nodes{ id title url } } } }"""
Q_FIELDS = """query($pid:ID!){ node(id:$pid){ ... on ProjectV2 {
  fields(first:50){ nodes{ __typename id name
    ... on ProjectV2SingleSelectField{ options{ id name } } } } } } }"""
Q_ITEMS = """query($pid:ID!,$cur:String){ node(id:$pid){ ... on ProjectV2 {
  items(first:100, after:$cur){ pageInfo{ hasNextPage endCursor } nodes{
    id content{ __typename ... on Issue{ id number url state updatedAt
      repository{ name } labels(first:20){ nodes{ name } } } }
    fieldValues(first:30){ nodes{ __typename
      ... on ProjectV2ItemFieldTextValue{ text field{ ...on ProjectV2FieldCommon{ name } } }
      ... on ProjectV2ItemFieldNumberValue{ number field{ ...on ProjectV2FieldCommon{ name } } }
      ... on ProjectV2ItemFieldSingleSelectValue{ name field{ ...on ProjectV2FieldCommon{ name } } }
    } } } } } } }"""
M_CREATE_PROJECT = """mutation($i:CreateProjectV2Input!){
  createProjectV2(input:$i){ projectV2{ id url } } }"""
M_CREATE_FIELD = """mutation($i:CreateProjectV2FieldInput!){
  createProjectV2Field(input:$i){ projectV2Field{ id } } }"""
M_UPDATE_FIELD = """mutation($i:UpdateProjectV2FieldInput!){
  updateProjectV2Field(input:$i){ projectV2Field{ id } } }"""
M_ADD_ITEM = """mutation($i:AddProjectV2ItemByContentIdInput!){
  addProjectV2ItemByContentId(input:$i){ item{ id } } }"""
M_SET_VALUE = """mutation($i:UpdateProjectV2ItemFieldValueInput!){
  updateProjectV2ItemFieldValue(input:$i){ projectV2Item{ id } } }"""

FIELD_SPEC = [  # (字段名, 类型)——State 特殊（单选，选项=state 全集）
    ("State", "SINGLE_SELECT"), ("Repo", "TEXT"), ("Assignee", "TEXT"),
    ("卡号", "NUMBER"), ("停留天数", "NUMBER"), ("AC 进度", "TEXT"),
]


def ensure_project():
    org = gql(Q_ORG, {"org": ORG})["organization"]
    if org is None:
        raise Infra(f"organization {ORG} 不可见（GOVERNANCE_TOKEN 权限？）")
    for p in (org.get("projectsV2") or {}).get("nodes") or []:
        if p.get("title") == PROJECT_TITLE:
            return p["id"], p.get("url") or ""
    if DRY_RUN:
        print(f"[dry-run] 将创建 org Project(v2)「{PROJECT_TITLE}」")
        return None, ""
    node = gql(M_CREATE_PROJECT, {"i": {"ownerId": org["id"], "title": PROJECT_TITLE}})\
        ["createProjectV2"]["projectV2"]
    return node["id"], node.get("url") or ""


def ensure_fields(pid, states):
    """返回 {字段名: field_id}；State 单选补齐缺失选项（只增不删——保留既有 item 值）。"""
    nodes = gql(Q_FIELDS, {"pid": pid})["node"]["fields"]["nodes"]
    by_name = {n["name"]: n for n in nodes if n.get("name")}
    out = {}
    for name, dtype in FIELD_SPEC:
        f = by_name.get(name)
        if f is None:
            if DRY_RUN:
                print(f"[dry-run] 将创建字段 {name}({dtype})")
                out[name] = None
                continue
            inp = {"projectID": pid, "name": name, "dataType": dtype}
            if dtype == "SINGLE_SELECT":
                inp["singleSelectOptions"] = [
                    {"name": s["name"], "color": s["color"]} for s in states]
            f = gql(M_CREATE_FIELD, {"i": inp})["createProjectV2Field"]["projectV2Field"]
        elif dtype == "SINGLE_SELECT":
            have = {o["name"]: o["id"] for o in f.get("options") or []}
            missing = [s for s in states if s["name"] not in have]
            if missing:
                merged = [{"name": n, "id": i} for n, i in have.items()] + [
                    {"name": s["name"], "color": s["color"]} for s in missing]
                if not DRY_RUN:
                    gql(M_UPDATE_FIELD, {"i": {"projectID": pid, "fieldID": f["id"],
                                               "singleSelectOptions": merged}})
                else:
                    print(f"[dry-run] State 单选补选项: {[s['name'] for s in missing]}")
        out[name] = f["id"]
    return out


def fetch_items(pid):
    """board 现有条目：{(repo, number): {item_id, fields:{名: 当前值}}}。"""
    items, cur = {}, None
    while True:
        node = gql(Q_ITEMS, {"pid": pid, "cur": cur})["node"]["items"]
        for it in node["nodes"]:
            content = it.get("content") or {}
            if content.get("__typename") != "Issue" or not content.get("repository"):
                continue  # 非 issue 条目（草稿/PR）不参与对账
            vals = {}
            for fv in (it.get("fieldValues") or {}).get("nodes") or []:
                fname = ((fv.get("field") or {}).get("name"))
                if not fname:
                    continue
                if fv["__typename"] == "ProjectV2ItemFieldSingleSelectValue":
                    vals[fname] = fv.get("name", "")
                elif fv["__typename"] in ("ProjectV2ItemFieldTextValue", "ProjectV2ItemFieldNumberValue"):
                    vals[fname] = fv.get("text", fv.get("number"))
            closed_labels = [l["name"] for l in (content.get("labels") or {}).get("nodes") or []]
            items[(content["repository"]["name"], content["number"])] = {
                "item_id": it["id"], "fields": vals,
                "issue_state": content.get("state", ""),
                "labels": closed_labels, "url": content.get("url", ""),
            }
        if not node["pageInfo"]["hasNextPage"]:
            return items
        cur = node["pageInfo"]["endCursor"]


def set_field(pid, item_id, field_id, kind, value):
    """单字段写入；value 形态按 kind：text/number/singleSelectOptionId。"""
    val = {kind: value}
    if not DRY_RUN:
        gql(M_SET_VALUE, {"i": {"projectID": pid, "itemID": item_id,
                                "fieldID": field_id, "value": val}})


def main():
    if not TOKEN:
        print("FATAL 需要环境变量 GH_TOKEN=GOVERNANCE_TOKEN（org project 权限）", file=sys.stderr)
        return 2
    stats = {"repos": 0, "cards": 0, "added": 0, "updated": 0,
             "corrected": 0, "warned": 0, "closed_set": 0, "noop": 0}
    try:
        states = load_states()
        state_names = {s["name"] for s in states}
        repos = active_repos()
        stats["repos"] = len(repos)
        cards = scan_cards(repos)
        stats["cards"] = len(cards)
        pid, purl = ensure_project()
        if pid is None:  # dry-run 且项目尚不存在——计划已打印，无从对账
            print(f"AUDIT | butler=board-sync | trigger={TRIGGER} | outcome=ok | dry-run=1 | "
                  f"actions={json.dumps(stats, ensure_ascii=False)}")
            return 0
        fields = ensure_fields(pid, states)
        # State 单选选项名→id 映射（用于写入 singleSelectOptionId）
        q = gql(Q_FIELDS, {"pid": pid})["node"]["fields"]["nodes"]
        state_field = next((n for n in q if n.get("name") == "State"), None)
        opt_ids = {o["name"]: o["id"] for o in (state_field or {}).get("options") or []}
        board = fetch_items(pid)
        for c in cards:
            key = (c["repo"], c["number"])
            if c["state"] not in state_names:
                print(f"WARN unknown-state {c['repo']}#{c['number']}: label 态 {c['state']} "
                      f"不在 expected-state 全集——字段照设为文本态名，请修标签")
            entry = board.get(key)
            if entry is None:
                if DRY_RUN:
                    print(f"[dry-run] 将新增条目 {c['repo']}#{c['number']} "
                          f"State={c['state']} assignee={c['assignee'] or '-'}")
                    stats["added"] += 1
                    continue
                item = gql(M_ADD_ITEM, {"i": {"projectID": pid, "contentID": c["node_id"]}})\
                    ["addProjectV2ItemByContentId"]["item"]
                entry = {"item_id": item["id"], "fields": {}}
                stats["added"] += 1
            want = {"Repo": c["repo"], "Assignee": c["assignee"] or "",
                    "卡号": c["number"], "停留天数": c["days_idle"],
                    "AC 进度": c["ac_progress"]}
            have = entry["fields"]
            # State 先比对（漂移报警面 = 宪法 §12 人工改动将被纠正）
            if have.get("State") != c["state"]:
                print(f"WARN board-drift {c['repo']}#{c['number']}: "
                      f"board={have.get('State')} label={c['state']}"
                      f"（人工改动将被纠正，宪法 §12）")
                stats["warned"] += 1
                stats["corrected"] += 1
                if c["state"] in opt_ids:
                    set_field(pid, entry["item_id"], fields["State"],
                              "singleSelectOptionId", opt_ids[c["state"]])
                else:  # 未知态兜底：文本写不进单选——报警留观，不 crash
                    print(f"WARN unknown-state {c['repo']}#{c['number']}: "
                          f"{c['state']} 无单选选项，跳过 State 写入")
            diff = [k for k, v in want.items() if have.get(k) != v]
            for k in diff:
                kind = "number" if k in ("卡号", "停留天数") else "text"
                set_field(pid, entry["item_id"], fields[k], kind, want[k])
                stats["updated"] += 1
            if not diff and have.get("State") == c["state"]:
                stats["noop"] += 1
        # 已 closed 的条目：状态照实设（最终 label 态），不删（ADR-0055 决策 7 v1）
        card_keys = {(c["repo"], c["number"]) for c in cards}
        for key, entry in board.items():
            if key in card_keys or entry.get("issue_state") != "CLOSED":
                continue
            final = next((n[len("state:"):] for n in entry["labels"]
                          if n.startswith("state:")), None)
            if final and entry["fields"].get("State") != final and final in opt_ids:
                if DRY_RUN:
                    print(f"[dry-run] closed 条目照实设 State={final}: {key}")
                else:
                    set_field(pid, entry["item_id"], fields["State"],
                              "singleSelectOptionId", opt_ids[final])
                stats["closed_set"] += 1
    except Infra as e:
        print(f"AUDIT | butler=board-sync | trigger={TRIGGER} | outcome=infra-fail | "
              f"actions={json.dumps(stats, ensure_ascii=False)} | error={e}", flush=True)
        print(f"FATAL {e}", file=sys.stderr)
        return 2
    print(f"AUDIT | butler=board-sync | trigger={TRIGGER} | outcome=ok | "
          f"dry-run={1 if DRY_RUN else 0} | project={purl} | "
          f"actions={json.dumps(stats, ensure_ascii=False)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
