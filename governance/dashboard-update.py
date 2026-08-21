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


class Infra(Exception):
    pass


def _req(url, body=None, method=None, ok_codes=(200, 201)):
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
    st, payload = _req(f"{GH_API}{path}", body, method, ok_codes)
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
                sl = [l["name"] for l in it.get("labels", []) if str(l.get("name", "")).startswith("state:")]
                if not sl:
                    continue
                cards.append({"repo": repo, "number": it["number"], "title": it["title"],
                              "state": sl[0][len("state:"):],
                              "assignee": (it.get("assignees") or [{}])[0].get("login", ""),
                              "url": it["html_url"], "updated_at": it.get("updated_at") or "",
                              "days_idle": max(0, (NOW - _iso(it.get("updated_at"))).days)})
            if len(batch) < 100:
                break
            page += 1
    return cards


def sli_automerge(repos):
    """近 7 天 merged PR 中 App 身份合并占比（proxy；零分母→null N/A，#98 T2）。"""
    since = NOW - _dt.timedelta(days=7)
    merged, auto = 0, 0
    for repo in repos:
        prs = get(f"/repos/{ORG}/{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=30")
        for pr in prs:
            if not pr.get("merged_at") or _iso(pr["merged_at"]) < since:
                continue
            merged += 1
            detail = get(f"/repos/{ORG}/{repo}/pulls/{pr['number']}")
            if (detail.get("merged_by") or {}).get("login") == APP_BOT:
                auto += 1
    if merged == 0:
        return None, 0
    return round(auto / merged, 4), merged


def sli_stuck(repos):
    """open PR 停留 >24h 数。"""
    cutoff = NOW - _dt.timedelta(hours=24)
    stuck = 0
    for repo in repos:
        prs = get(f"/repos/{ORG}/{repo}/pulls?state=open&per_page=100")
        stuck += sum(1 for pr in prs if _iso(pr.get("created_at")) < cutoff)
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
```json
{json.dumps(payload, ensure_ascii=False, indent=2)}
```

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
    """幂等找到/创建账本 issue；返回 (number, created)。"""
    found = None
    page = 1
    while True:
        batch = get(f"/repos/{ORG}/{HOME_REPO}/issues?state=open&per_page=100&page={page}")
        found = next((i for i in batch if i["title"] == ISSUE_TITLE), None)
        if found or len(batch) < 100:
            break
        page += 1
    if found:
        return found["number"], False
    # 幂等建 label（422=已存在，容忍）
    _req(f"{GH_API}/repos/{ORG}/{HOME_REPO}/labels",
         {"name": LABEL["name"], "color": LABEL["color"], "description": LABEL["description"]},
         "POST", ok_codes=(201, 422))
    if DRY_RUN:
        print(f"[dry-run] 将创建 dashboard 账本 issue「{ISSUE_TITLE}」")
        return None, True
    issue = send("POST", f"/repos/{ORG}/{HOME_REPO}/issues",
                 {"title": ISSUE_TITLE, "body": body, "labels": [LABEL["name"]]})
    return issue["number"], True


def project_url():
    """只读取 factory-floor 项目链接（board-sync 已建；失败不阻塞账本——置空）。"""
    try:
        st, payload = _req(f"{GH_API}/graphql", {
            "query": "query($o:String!){ organization(login:$o){ projectsV2(first:100){ nodes{ title url } } } }",
            "variables": {"o": ORG}}, "POST")
        if st == 200 and not payload.get("errors"):
            for p in payload["data"]["organization"]["projectsV2"]["nodes"]:
                if p["title"] == "factory-floor":
                    return p["url"]
    except Exception:
        pass
    return ""


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
            if (cur.get("body") or "").strip() == body.strip():
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
