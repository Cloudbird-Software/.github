#!/usr/bin/env python3
"""dashboard-update.py —— 管家账本 dashboard issue 刷新（宪法 §12 投影二 / ADR-0055 决策 8）

幂等找到/创建 .github 仓 issue「管家账本 dashboard（factory-floor）」（label
`dashboard` 幂等创建）；body 两区：
- 机器可读区：`<!-- dashboard-json -->` 标记后 fenced JSON（generated_at、cards[]、
  sli{automerge_rate, human_touch_per_pr, escape_rate, stuck_prs, false_red_rate,
  entropy_delta}——字段名与 .github#98 SLI 口径对齐；v1 能算的算，算不了的置 null
  并在 sli_pending 标 "W5-C3"）
- 人类一屏摘要区：数字+链接
更新=issue edit 覆盖 body（内容相同则跳过写）；历史靠 issue 编辑历史天然留痕。
API 失败 exit 2（fail-closed）。驱动：butler-ledger.yml 每 15min；board-sync.yml 演习面。

v1 SLI 口径（诚实标注，#98 T2 分母陷阱：零分母→null+N/A，不除零不出 100%）：
- automerge_rate：近 7 天 merged PR 中 merged_by==cloudbrid-agent[bot] 占比
 （proxy：App 身份执行合并；timeline 级 auto-merge 事件归 W5-C3）
- stuck_prs：open PR 停留 >24h 数（跨 active 仓求和）
- 其余四项（human_touch_per_pr / escape_rate / false_red_rate / entropy_delta）：
  需要 timeline/revert/flaky/熵事件流——置 null + pending W5-C3
"""
import datetime as _dt
import json
import os
import re
import sys
import urllib.error
import urllib.request

try:
    import yaml
except ImportError:  # pragma: no cover
    print("FATAL 缺少 PyYAML（CI 预装；本地 pip install pyyaml）", file=sys.stderr)
    raise SystemExit(2)

ORG = "Cloudbird-Software"
HOME_REPO = ".github"
ISSUE_TITLE = "管家账本 dashboard（factory-floor）"
LABEL = {"name": "dashboard", "color": "F9D0C4",
         "description": "管家账本投影二（宪法 §12，机器可读 JSON+一屏摘要）"}
GH_API = "https://api.github.com"
DRY_RUN = "--dry-run" in sys.argv or os.environ.get("DASHBOARD_DRY_RUN") == "1"
TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GOVERNANCE_TOKEN") or ""
DIR = os.path.dirname(os.path.abspath(__file__))
NOW = _dt.datetime.now(_dt.timezone.utc)
TRIGGER = os.environ.get("BUTLER_TRIGGER") or "manual"
APP_BOT = "cloudbrid-agent[bot]"
JSON_MARK = "<!-- dashboard-json -->"
FENCE = "`" * 8  # 长于任何合理用户输入的 fence（标题可含 ```——防截断机器可读区）


def _safe_text(s):
    """剥离用户可控文本里可破坏 fence / 伪造区标记的字面量（标题进 body 的必经清洗）。"""
    return (str(s or "").replace("`", "'")
            .replace("<!--", "<! --").replace("-->", "-- >"))


class Infra(Exception):
    pass


def _req(url, body=None, method=None):  # 状态码判定归调用方（send/显式检查）——不设 ok_codes 形参以免“声明了却不用”
    headers = {"Authorization": f"Bearer {TOKEN}", "User-Agent": "dashboard-update",
               "Accept": "application/vnd.github+json"}
    data = json.dumps(body).encode() if body is not None else None
    if data:
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
    except Exception as e:
        raise Infra(f"请求失败 {url}: {e}") from e


def get(path):
    st, payload = _req(f"{GH_API}{path}")
    if st != 200:
        raise Infra(f"GET {path} HTTP {st}: {str(payload.get('message'))[:120]}")
    return payload


def send(method, path, body, ok_codes=(200, 201)):
    st, payload = _req(f"{GH_API}{path}", body, method)
    if st not in ok_codes:
        raise Infra(f"{method} {path} HTTP {st}: {str(payload.get('message'))[:160]}")
    return payload


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


def _iso(s):
    return _dt.datetime.fromisoformat((s or NOW.isoformat()).replace("Z", "+00:00"))


def scan_cards(repos):
    """与 board-sync.py 同判据的独立轻量扫描（自包含；真相源=issue label）。"""
    cards = []
    for repo in repos:
        page = 1
        while True:
            batch = get(f"/repos/{ORG}/{repo}/issues?state=open&per_page=100&page={page}")
            for it in batch:
                if "pull_request" in it:
                    continue
                sl = sorted(l["name"] for l in it.get("labels", [])
                            if str(l.get("name", "")).startswith("state:"))
                if not sl:
                    continue
                if len(sl) > 1:  # 真相源唯一性被破坏（宪法 §12）——排序取首保证两投影一致
                    print(f"WARN multi-state {repo}#{it['number']}: {sl}"
                          f"——多 state 标签并存，本轮取 {sl[0]}，请修标签")
                cards.append({"repo": repo, "number": it["number"], "title": _safe_text(it["title"]),
                              "state": sl[0][len("state:"):],
                              "assignee": (it.get("assignees") or [{}])[0].get("login", ""),
                              "url": it["html_url"], "updated_at": it.get("updated_at") or "",
                              "days_idle": max(0, (NOW - _iso(it.get("updated_at"))).days)})
            if len(batch) < 100:
                break
            page += 1
    return cards


Q_MERGED_PRS = """query($o:String!,$r:String!,$cur:String){
  repository(owner:$o,name:$r){
    pullRequests(states:MERGED, first:100, after:$cur,
                 orderBy:{field:UPDATED_AT,direction:DESC}){
      pageInfo{ hasNextPage endCursor }
      nodes{ mergedAt updatedAt mergedBy{ login } } } } }"""


def sli_automerge(repos):
    """近 7 天 merged PR 中 App 身份合并占比（proxy；零分母→null N/A，#98 T2）。

    GraphQL 批量取 mergedBy（REST 列表端点不含该字段、逐 PR detail 在 15min
    节奏下配额浪费——ADR-0055 决策 8 的诚实轻量实现）。
    """
    since = NOW - _dt.timedelta(days=7)
    merged, auto = 0, 0
    for repo in repos:
        cur = None
        while True:
            body = {"query": Q_MERGED_PRS,
                    "variables": {"o": ORG, "r": repo, "cur": cur}}
            st, payload = _req(f"{GH_API}/graphql", body, "POST")
            if st != 200 or payload.get("errors"):
                raise Infra(f"GraphQL merged PRs {repo} HTTP {st}: "
                            + json.dumps(payload.get("errors", payload), ensure_ascii=False)[:200])
            conn = payload["data"]["repository"]["pullRequests"]
            page_min_updated = min((_iso(n["updatedAt"]) for n in conn["nodes"]),
                                   default=_dt.datetime(1970, 1, 1, tzinfo=_dt.timezone.utc))
            for n in conn["nodes"]:
                if not n.get("mergedAt") or _iso(n["mergedAt"]) < since:
                    continue
                merged += 1
                if (n.get("mergedBy") or {}).get("login") == APP_BOT:
                    auto += 1
            # 按 UPDATED_AT 倒序翻页：页内最小 updatedAt 已出窗即止——后续页
            # updatedAt 更旧，而 mergedAt<=updatedAt，不可能再有 7 天内合并
            if page_min_updated < since or not conn["pageInfo"]["hasNextPage"]:
                break
            cur = conn["pageInfo"]["endCursor"]
    if merged == 0:
        return None, 0
    return round(auto / merged, 4), merged


def sli_stuck(repos):
    """open PR 停留 >24h 数。"""
    cutoff = NOW - _dt.timedelta(hours=24)
    stuck = 0
    for repo in repos:
        page = 1  # 分页拉全量（>100 open PR 单页漏计——与 scan_cards 同教训）
        while True:
            prs = get(f"/repos/{ORG}/{repo}/pulls?state=open&per_page=100&page={page}")
            stuck += sum(1 for pr in prs if _iso(pr.get("created_at")) < cutoff)
            if len(prs) < 100:
                break
            page += 1
    return stuck


def build_payload(repos, cards, purl=""):
    rate, denom = sli_automerge(repos)
    sli = {"automerge_rate": rate, "human_touch_per_pr": None, "escape_rate": None,
           "stuck_prs": sli_stuck(repos), "false_red_rate": None, "entropy_delta": None}
    pending = {"human_touch_per_pr": "W5-C3", "escape_rate": "W5-C3",
               "false_red_rate": "W5-C3", "entropy_delta": "W5-C3"}
    if rate is None:
        pending["automerge_rate"] = "N/A（近 7 天零 merged PR——分母陷阱 #98 T2，不造数）"
    return {
        "generated_at": NOW.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "schema": "dashboard-json v1（ADR-0055；#98 SLI 字段名兼容）",
        "project": {"title": "factory-floor", "url": purl},
        "cards": cards,
        "sli": sli,
        "sli_pending": pending,
        "sli_meta": {
            "automerge_rate": f"近7天 merged PR 中 merged_by=={APP_BOT} 占比（proxy，W5-C3 换 timeline 事件）",
            "automerge_denominator_7d": denom,
            "stuck_prs": "open PR 停留>24h（active 仓求和）",
        },
    }


def render_body(payload):
    cards = payload["cards"]
    by_state = {}
    for c in cards:
        by_state.setdefault(c["state"], []).append(c)
    state_lines = "\n".join(
        f"- {s}: {len(v)} 张（" + " ".join(f"[{c['repo']}#{c['number']}]({c['url']})" for c in v[:8])
        + ("…" if len(v) > 8 else "") + "）" for s, v in sorted(by_state.items())) or "- （队列空）"
    sli, meta = payload["sli"], payload["sli_meta"]
    rate_txt = f"{sli['automerge_rate']*100:.0f}%（分母 {meta['automerge_denominator_7d']}）" \
        if sli["automerge_rate"] is not None else "N/A（零分母）"
    human = f"""# 管家账本 dashboard（factory-floor 投影二，宪法 §12 / ADR-0055）

## 机器可读区（agent 一次读取全局；历史留痕=本 issue 编辑历史）

{JSON_MARK}
{FENCE}json
{json.dumps(payload, ensure_ascii=False, indent=2)}
{FENCE}

## 人类一屏摘要

- 在制卡：**{len(cards)}** 张（active 仓 open+state:*）
{state_lines}
- factory-floor 板：{payload["project"]["url"] or "（board-sync 首轮后回填链接）"}
- SLI（#98 口径，v1 子集）：自动合并率 {rate_txt} · 卡死 PR（>24h）{sli['stuck_prs']}
- 待补（W5-C3）：人类触碰/PR · 门禁逃逸率 · 假红率 · 熵增——见 sli_pending
- 刷新节奏：butler-ledger 每 15min（唤醒矩阵行 2）；手动：workflow_dispatch board-sync
"""
    return human


def ensure_issue(body):
    """幂等找到/创建账本 issue；返回 (number, created)。

    查找范围 state=all（含已关闭：账本被人工关闭后复用之，不得重复创建——
    否则账本分裂、编辑历史散落）；/issues 端点混入 PR，须按 "pull_request"
    键排除后再匹配标题。
    """
    found = None
    page = 1
    while True:
        batch = get(f"/repos/{ORG}/{HOME_REPO}/issues?state=all&per_page=100&page={page}")
        found = next((i for i in batch
                      if "pull_request" not in i and i["title"] == ISSUE_TITLE), None)
        if found or len(batch) < 100:
            break
        page += 1
    if found:
        return found["number"], False
    # 幂等建 label（201=新建，422=已存在；其余=真故障——fail-closed 不静默）
    st, payload = _req(f"{GH_API}/repos/{ORG}/{HOME_REPO}/labels",
                       {"name": LABEL["name"], "color": LABEL["color"],
                        "description": LABEL["description"]}, "POST")
    if st not in (201, 422):
        raise Infra(f"POST labels HTTP {st}: {str(payload.get('message'))[:160]}")
    if DRY_RUN:
        print(f"[dry-run] 将创建 dashboard 账本 issue「{ISSUE_TITLE}」")
        return None, True
    issue = send("POST", f"/repos/{ORG}/{HOME_REPO}/issues",
                 {"title": ISSUE_TITLE, "body": body, "labels": [LABEL["name"]]})
    return issue["number"], True


def project_url():
    """只读取 factory-floor 项目链接（board-sync 已建；失败不阻塞账本——置空）。

    projectsV2 游标翻页（与 board-sync.ensure_project 同判据）：org 项目 >100 时
    目标不在首页，不翻页会把“存在”误判为“不存在”。
    """
    try:
        cur = None
        while True:
            st, payload = _req(f"{GH_API}/graphql", {
                "query": "query($o:String!,$cur:String){ organization(login:$o){"
                         " projectsV2(first:100, after:$cur){ nodes{ title url }"
                         " pageInfo{ hasNextPage endCursor } } } }",
                "variables": {"o": ORG, "cur": cur}}, "POST")
            if st != 200 or payload.get("errors"):
                break
            conn = payload["data"]["organization"]["projectsV2"]
            for p in conn["nodes"]:
                if p["title"] == "factory-floor":
                    return p["url"]
            if not conn["pageInfo"]["hasNextPage"]:
                break
            cur = conn["pageInfo"]["endCursor"]
    except Exception:
        pass
    return ""


def _stable(body):
    """剥离每轮必变的时间戳再比对（generated_at 精度到秒——不剥离则“内容相同
    跳过写”永不生效，每 15min 一条无意义编辑淹没 issue 历史）。"""
    return re.sub(r'"generated_at":\s*"[^"]*"', '"generated_at":"-"', body).strip()


def main():
    if not TOKEN:
        print("FATAL 需要环境变量 GH_TOKEN=GOVERNANCE_TOKEN", file=sys.stderr)
        return 2
    stats = {"cards": 0, "issue": None, "created": 0, "edited": 0, "unchanged": 0}
    try:
        repos = active_repos()
        cards = scan_cards(repos)
        stats["cards"] = len(cards)
        payload = build_payload(repos, cards, project_url())
        body = render_body(payload)
        num, created = ensure_issue(body)
        stats["created"] = 1 if created else 0
        stats["issue"] = num
        if num is None:  # dry-run 新建路径
            print(f"AUDIT | butler=dashboard-update | trigger={TRIGGER} | outcome=ok | "
                  f"dry-run=1 | actions={json.dumps(stats, ensure_ascii=False)}")
            return 0
        if not created:
            cur = get(f"/repos/{ORG}/{HOME_REPO}/issues/{num}")
            if _stable(cur.get("body") or "") == _stable(body):
                stats["unchanged"] = 1
            elif DRY_RUN:
                print(f"[dry-run] 将编辑 issue #{num} body（{len(body)} 字节）")
                stats["edited"] = 1
            else:
                send("PATCH", f"/repos/{ORG}/{HOME_REPO}/issues/{num}", {"body": body})
                stats["edited"] = 1
    except Infra as e:
        print(f"AUDIT | butler=dashboard-update | trigger={TRIGGER} | outcome=infra-fail | "
              f"actions={json.dumps(stats, ensure_ascii=False)} | error={e}", flush=True)
        print(f"FATAL {e}", file=sys.stderr)
        return 2
    print(f"AUDIT | butler=dashboard-update | trigger={TRIGGER} | outcome=ok | "
          f"dry-run={1 if DRY_RUN else 0} | "
          f"actions={json.dumps(stats, ensure_ascii=False)}")
    print(f"issue: https://github.com/{ORG}/{HOME_REPO}/issues/{stats['issue']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
