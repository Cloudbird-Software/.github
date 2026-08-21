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
        # 报 message+problems，不回显 input value（含 id 等噪音）
        msgs = []
        for e in (payload.get("errors") or [payload])[:3]:
            m = e.get("message", str(e))[:200]
            probs = "; ".join(f"{p.get('path')}: {p.get('explanation')}" for p in (e.get("extensions") or {}).get("problems") or [])
            msgs.append(m + (f" [{probs}]" if probs else ""))
        raise Infra(f"GraphQL HTTP {st}: " + " | ".join(msgs))
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

def _hex_to_option_color(hexs):
    """expected-state 的 label hex → ProjectV2 单选选项颜色枚举（仅 8 色）。

    确定性映射（HSV 色相分桶 + 低饱和→GRAY）——真源仍是 expected-state.json，
    板选项颜色是其最近似展示，不参与任何判定。
    """
    try:
        h = hexs.lstrip("#")
        r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except Exception:
        return "GRAY"
    mx, mn = max(r, g, b), min(r, g, b)
    if mx <= 0:  # 黑就近 GRAY（枚举无黑）
        return "GRAY"
    d = mx - mn
    s = 0 if mx == 0 else d / mx
    if s < 0.10:  # 阈值须放过淡彩（BFD4F2 类 pastel 蓝 s≈0.21）
        return "GRAY"
    if mx == r:
        hue = 60 * ((g - b) / d) % 360
    elif mx == g:
        hue = 60 * ((b - r) / d) + 120
    else:
        hue = 60 * ((r - g) / d) + 240
    if hue < 15 or hue >= 345:
        return "RED"
    if hue < 45:
        return "ORANGE"
    if hue < 70:
        return "YELLOW"
    if hue < 170:
        return "GREEN"
    if hue < 250:
        return "BLUE"
    return "PURPLE"


def load_states():
    try:
        with open(os.path.join(DIR, "expected-state.json"), encoding="utf-8") as f:
            items = json.load(f)["labels"]["items"]
    except Exception as e:
        raise Infra(f"expected-state.json 读取失败: {e}") from e
    states = [{
        "name": it["name"][len("state:"):],
        "color": _hex_to_option_color(str(it.get("color", ""))),
        "description": str(it.get("description") or it["name"][len("state:"):])[:256],
    } for it in items if it.get("name", "").startswith("state:")]
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

# @w5c4-board-pure-begin —— 板字段纯函数区（governance/tests/test-board-fields.sh
# 按标记对提取本块离线单测——不复制实现，防"测试测影子"；标记对缺失=测试红）

# PR body 卡元数据行（入口协议 v1：body 必带 Card: Cloudbird-Software/<repo>#<n>）
CARD_REF_RE = re.compile(r"Card:\s*Cloudbird-Software/([A-Za-z0-9_.\-]+)#(\d+)")


def pr_refs_from_prs(prs):
    """open PR 列表（含 body）→ {(卡 repo, 卡号): head_sha}——卡↔PR 关联唯一判据。"""
    out = {}
    for pr in prs or []:
        m = CARD_REF_RE.search(str(pr.get("body") or ""))
        if not m:
            continue
        out[(m.group(1), int(m.group(2)))] = pr.get("head", {}).get("sha")
    return out


# check-runs 结论 → 关卡状态文案（fail-closed 方向：任一失败即红，未完成不算绿）
_GATE_RED = ("failure", "timed_out", "startup_failure", "cancelled")


def gate_status_text(check_runs):
    """head sha 的 check-runs → 绿/红/等待/无 CI（W5-C4 AC-3 字段：关卡状态）。

    判序：红 > 等待 > 绿（一个失败即红，其余绿不遮红；completed 无 conclusion
    的畸形态归等待——不冒充绿）；零 run=无 CI（区分"还没跑"与"跑挂了"）。
    """
    runs = list(check_runs or [])
    if not runs:
        return "无 CI"
    for r in runs:
        if str(r.get("conclusion") or "").lower() in _GATE_RED:
            return "红"
    for r in runs:
        if r.get("status") != "completed" or not r.get("conclusion"):
            return "等待"
    return "绿"


# 漂移报警面=人工可在板上改的字段（宪法 §12：人工改动将被纠正+报警）；
# 停留天数/卡号是每轮必变的派生刷新（日增/不变），进漂移面=每天误报淹没信号
BOARD_DRIFT_FIELDS = ("State", "认领者", "AC 进度", "关卡状态", "谓词状态")


def board_drift_fields(have, want):
    """板当前值 vs label/派生期望值 → 漂移字段名列表（空值与未设等价——GitHub
    空文本不落值，board-sync v1 同归一）。"""
    drifted = []
    for k in BOARD_DRIFT_FIELDS:
        hv, wv = have.get(k), want.get(k)
        if hv is None and (wv == "" or wv is None):
            continue
        if hv != wv:
            drifted.append(k)
    return drifted
# @w5c4-board-pure-end


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
                sl = sorted(l["name"] for l in it.get("labels", [])
                            if str(l.get("name", "")).startswith("state:"))
                if not sl:
                    continue
                if len(sl) > 1:  # 真相源唯一性被破坏（宪法 §12）——排序取首保证两投影一致
                    print(f"WARN multi-state {repo}#{it['number']}: {sl}"
                          f"——多 state 标签并存，本轮取 {sl[0]}，请修标签")
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


def load_predicate_pending():
    """谓词状态 pending 标注（policy/metrics.yaml board 节——W5-C2 信任门未落，
    字段占位≠造数）。policy 缺失→内置同值（板字段不因 policy 读取失败而缺席）。"""
    try:
        with open(os.path.join(DIR, "policy", "metrics.yaml"), encoding="utf-8") as f:
            v = yaml.safe_load(f).get("board", {}).get("predicate_status_pending")
        if v:
            return str(v)
    except Exception:
        pass
    return "pending(W5-C2)"


def enrich_cards(cards, repos):
    """W5-C4 AC-3：卡补 关卡状态（卡 PR 的 head check-runs）与 谓词状态（pending）。

    卡↔PR 关联=PR body 的 Card: 元数据行（入口协议 v1）；无 PR 的卡=「无 PR」。
    check-runs 拉取失败→「未知」并 WARN（fail-closed 方向：未知≠绿）。
    """
    prs = []
    for repo in repos:
        page = 1
        while True:
            batch = api_get(f"/repos/{ORG}/{repo}/pulls?state=open&per_page=100&page={page}")
            prs.extend(batch)
            if len(batch) < 100:
                break
            page += 1
    refs = pr_refs_from_prs(prs)
    predicate = load_predicate_pending()
    for c in cards:
        sha = refs.get((c["repo"], c["number"]))
        if not sha:
            c["gate_status"] = "无 PR"
        else:
            try:
                cr = api_get(f"/repos/{ORG}/{c['repo']}/commits/{sha}/check-runs")
                c["gate_status"] = gate_status_text(cr.get("check_runs") or [])
            except Infra as e:
                print(f"WARN gate-status {c['repo']}#{c['number']}: check-runs 拉取失败 {e}"
                      f"——关卡状态=未知（不冒充绿）")
                c["gate_status"] = "未知"
        c["predicate_status"] = predicate
    return cards


# ---------- Project(v2) 幂等准备 ----------

Q_ORG = """query($org:String!,$cur:String){ organization(login:$org){
  id projectsV2(first:100, after:$cur){ nodes{ id title url }
  pageInfo{ hasNextPage endCursor } } } }"""
Q_FIELDS = """query($pid:ID!){ node(id:$pid){ ... on ProjectV2 {
  fields(first:50){ nodes{ __typename
    ... on ProjectV2Field{ id name dataType }
    ... on ProjectV2SingleSelectField{ id name options{ id name } } } } } } }"""
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
  createProjectV2Field(input:$i){ projectV2Field{
    ... on ProjectV2Field{ id } ... on ProjectV2SingleSelectField{ id } } } }"""
M_UPDATE_FIELD = """mutation($i:UpdateProjectV2FieldInput!){
  updateProjectV2Field(input:$i){ projectV2Field{
    ... on ProjectV2Field{ id } ... on ProjectV2SingleSelectField{ id } } } }"""
M_ADD_ITEM = """mutation($i:AddProjectV2ItemByIdInput!){
  addProjectV2ItemById(input:$i){ item{ id } } }"""  # 本 API 版本无 ByContentId 变体（键 projectId/contentId）
M_SET_VALUE = """mutation($i:UpdateProjectV2ItemFieldValueInput!){
  updateProjectV2ItemFieldValue(input:$i){ projectV2Item{ id } } }"""  # 输入键=projectId/itemId/fieldId

FIELD_SPEC = [  # (字段名, 类型)——State 单选（选项=state 全集）；中文仓/认领者避开
    # GitHub 保留名（"Repo"/"Assignee" 会撞内建 Repository/Assignees → reserved 拒绝）
    ("State", "SINGLE_SELECT"), ("仓", "TEXT"), ("认领者", "TEXT"),
    ("卡号", "NUMBER"), ("停留天数", "NUMBER"), ("AC 进度", "TEXT"),
    # W5-C4 AC-3（宪法 §12 字段清单）：关卡状态=卡 PR head check-runs 投影；
    # 谓词状态=硬谓词信任门（ADR-0071 W5-C2 进行中）——pending 标注不造数
    ("关卡状态", "TEXT"), ("谓词状态", "TEXT"),
]


def ensure_project():
    org = gql(Q_ORG, {"org": ORG, "cur": None})["organization"]
    if org is None:
        raise Infra(f"organization {ORG} 不可见（GOVERNANCE_TOKEN 权限？）")
    # 游标翻页遍历全量后再判“不存在”（org 项目 >100 时不翻页会重复建同名板）
    while True:
        conn = (org.get("projectsV2") or {})
        for p in conn.get("nodes") or []:
            if p.get("title") == PROJECT_TITLE:
                return p["id"], p.get("url") or ""
        if not conn.get("pageInfo", {}).get("hasNextPage"):
            break
        cur = conn["pageInfo"]["endCursor"]
        org = gql(Q_ORG, {"org": ORG, "cur": cur})["organization"]
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
            inp = {"projectId": pid, "name": name, "dataType": dtype}
            if dtype == "SINGLE_SELECT":
                # 选项 color=枚举（8 色）+description 必填（均来自 expected-state）
                inp["singleSelectOptions"] = [
                    {"name": s["name"], "color": s["color"], "description": s["description"]}
                    for s in states]
            f = gql(M_CREATE_FIELD, {"i": inp})["createProjectV2Field"]["projectV2Field"]
        elif dtype == "SINGLE_SELECT" and f.get("__typename") != "ProjectV2SingleSelectField":
            raise Infra(f"字段 {name} 已存在但类型={f.get('__typename')}（期望单选）——人工核板")
        elif dtype != "SINGLE_SELECT" and f.get("dataType") != dtype:
            raise Infra(f"字段 {name} 已存在但 dataType={f.get('dataType')}（期望 {dtype}）——人工核板")
        if dtype == "SINGLE_SELECT":
            have = {o["name"]: o["id"] for o in f.get("options") or []}
            missing = [s for s in states if s["name"] not in have]
            if missing:
                # updateProjectV2Field 的 options 输入按名字匹配保留既有选项（不删
                # 不重置），仅补缺失项；既有项 description/color 须回填（必填字段）
                desc = {s["name"]: s["description"] for s in states}
                color = {s["name"]: s["color"] for s in states}
                merged = [{"name": n, "description": desc.get(n, n), "color": color.get(n, "GRAY")}
                          for n in have] + [
                    {"name": s["name"], "color": s["color"], "description": s["description"]}
                    for s in missing]
                if not DRY_RUN:
                    gql(M_UPDATE_FIELD, {"i": {"projectId": pid, "fieldId": f["id"],
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
        gql(M_SET_VALUE, {"i": {"projectId": pid, "itemId": item_id,
                                "fieldId": field_id, "value": val}})


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
        cards = enrich_cards(scan_cards(repos), repos)
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
                      f"不在 expected-state 全集——State 无对应单选选项，将跳过 State 写入（报警留观），请修标签")
            entry = board.get(key)
            preexisting = entry is not None  # 报警面只认"板上有旧值"的漂移（新增不算）
            if entry is None:
                if DRY_RUN:
                    print(f"[dry-run] 将新增条目 {c['repo']}#{c['number']} "
                          f"State={c['state']} assignee={c['assignee'] or '-'}")
                    stats["added"] += 1
                    continue
                item = gql(M_ADD_ITEM, {"i": {"projectId": pid, "contentId": c["node_id"]}})\
                    ["addProjectV2ItemById"]["item"]
                entry = {"item_id": item["id"], "fields": {}}
                stats["added"] += 1
            want = {"仓": c["repo"], "认领者": c["assignee"] or "",
                    "卡号": c["number"], "停留天数": c["days_idle"],
                    "AC 进度": c["ac_progress"],
                    "关卡状态": c["gate_status"], "谓词状态": c["predicate_status"]}
            have = entry["fields"]
            # 漂移报警面（宪法 §12 人工改动将被纠正+报警；W5-C4 AC-3 扩到全部
            # 人工可改字段——State 之外认领者/AC 进度/关卡状态/谓词状态同报）；
            # 仅对板上既有条目报警——新增条目无旧值，不算人工改动。
            # State 只在可写选项内参与比对（未知态写不进单选——比对了也纠正不了）
            if preexisting:
                drift_want = {**want}
                if c["state"] in opt_ids:
                    drift_want["State"] = c["state"]
                drifted = board_drift_fields(have, drift_want)
                if "State" in drifted:
                    print(f"WARN board-drift {c['repo']}#{c['number']}: "
                          f"State board={have.get('State')} label={c['state']}"
                          f"（人工改动将被纠正，宪法 §12）")
                for f in drifted:
                    if f != "State":
                        print(f"WARN board-drift {c['repo']}#{c['number']}: "
                              f"{f} board={have.get(f)!r} 期望={want[f]!r}"
                              f"（label/派生真源将被写回，宪法 §12）")
                if drifted:
                    stats["warned"] += 1
                    stats["corrected"] += 1
            # State 写入（单选；未知态兜底在下方）
                if c["state"] in opt_ids:
                    set_field(pid, entry["item_id"], fields["State"],
                              "singleSelectOptionId", opt_ids[c["state"]])
                else:  # 未知态兜底：文本写不进单选——报警留观，不 crash
                    print(f"WARN unknown-state {c['repo']}#{c['number']}: "
                          f"{c['state']} 无单选选项，跳过 State 写入")
            # 空值归一：板上未设(None/键缺失)与期望空串等价（空文本 GitHub 不落值）
            diff = []
            for k, v in want.items():
                hv = have.get(k)
                if hv is None and v == "":
                    continue
                if hv != v:
                    diff.append(k)
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
            # 与 scan_cards 同判据：排序取首（closed 多标签时两投影确定性一致）
            final = next((n[len("state:"):] for n in sorted(entry["labels"])
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
