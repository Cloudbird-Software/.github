#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""feedback-edge.py —— R3→R1 反馈边：运行信号→候选 spec backlog（IR-0006 W6-M2 / 卡 #424）

宪法 §11 三面分离的回边：R3 运行信号（错误/用量/SLO）越反馈阈值 → 自动生成
候选 spec（type:intent + state:ir-draft issue）入 backlog。**生成侧**（AC-8g）：
只产候选不开工；签署门禁不豁免（AC-8h）——owner 签署→spec→红队照走，本工具
永不置 state:ir-signed（INV-01 判定锚点机械 / BEH-01 生成≠判定）。

- 信号源：管家账本 dashboard issue（§12 投影二）机器可读 JSON（ADR-0073；
  --dashboard-file 注入离线 fixture——本地/测试同口径）
- 规则真源：governance/policy/feedback.yaml（feedback-edge/v1；阈值/路径全
  声明侧，本工具零内嵌阈值——宪法 §4A 同源纪律）
- 值判定（三值，同 metrics.py 口径）：crossed / ok / pending（值缺失/None/
  pending 字串=诚实 SKIP，不造数——ADR-0073 决策 7）
- 去重（RB-B2 同款）：open issue 带 label feedback:<key> 即 DUPLICATE 跳过
  （反馈边不得对同一信号重复刷卡；owner 关掉候选后信号仍越阈=复现证据，允许
  重开——去重只看 open 面）
- 审计（INV-12）：每轮经 butler-audit.sh 发射 AUDIT 行+schema v1 影子
  （BUTLER_SHADOW_FILE 可注入；持久化 feedback-ledger 分支=workflow 面）

fail-closed：policy 非法 / dashboard 拉取失败 / 参数矛盾 = exit 2（无默认绿）。
信号越阈=生成成功非故障（exit 0——上屏绿；候选卡是产出不是报警）。

用法:
  python3 governance/feedback-edge.py                     # 在线：拉 dashboard+开卡
  python3 governance/feedback-edge.py --dry-run           # 只打印候选（零 gh 调用）
  python3 governance/feedback-edge.py --dashboard-file F  # 信号 fixture（测试注入）
  python3 governance/feedback-edge.py --existing-file F   # 去重面 fixture（open issues JSON）
env:
  GH_TOKEN     在线模式必填（拉 dashboard issue / 开候选卡）
  BUTLER_TRIGGER / BUTLER_CARD / BUTLER_TENANT   审计 subject
退出码: 0=轮次完成（含候选产出）| 2=infra/policy fail-closed
"""
import argparse
import datetime as _dt
import json
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    print("FATAL 缺少 PyYAML（CI 预装）", file=sys.stderr)
    raise SystemExit(2)

DIR = os.path.dirname(os.path.abspath(__file__))
POLICY = os.path.join(DIR, "policy", "feedback.yaml")
TRIGGER = os.environ.get("BUTLER_TRIGGER") or "manual"
OPS = {"gt", "lt", "ge", "le", "eq", "ne"}
CLASSES = {"error", "usage", "slo"}
DASH_MARK = "<!-- dashboard-json -->"
FENCE_RE = re.compile(r"^(`{3,})(json)?\s*$")

sys.path.insert(0, DIR)


def die2(msg):
    print(f"FATAL {msg}", file=sys.stderr)
    raise SystemExit(2)


# ---------- dashboard 信号源 ----------

def parse_dashboard(text):
    """issue body / 纯 JSON → dashboard dict（机器可读区提取，ADR-0073 形态）。

    兼容两形态：带 ``dashboard-json`` 标记+围栏（dashboard-update.py 写入形态，
    围栏可为 3+ 任意长反引号）；纯 JSON 文本（fixture 直给）。两者皆失败=红。
    """
    if DASH_MARK in text:
        lines = text.splitlines()
        i = lines.index(next(l for l in lines if DASH_MARK in l))
        fence_len = None
        buf = []
        for ln in lines[i + 1:]:
            if fence_len is None:
                m = FENCE_RE.match(ln)
                if m:  # 开栏（含可选 json 标注）
                    fence_len = len(m.group(1))
                continue
            if re.match(r"^`{%d}\s*$" % fence_len, ln):
                break
            buf.append(ln)
        text = "\n".join(buf)
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        die2(f"dashboard JSON 不可解析: {e}")


def fetch_dashboard(repo, label):
    """在线拉管家账本 dashboard issue body（缺失=infra 红——信号源断了无绿可言）。"""
    r = subprocess.run(
        ["gh", "issue", "list", "--repo", repo, "--state", "open",
         "--label", label, "--json", "number,body", "--jq", ".[0]"],
        capture_output=True, text=True, env={**os.environ})
    if r.returncode != 0:
        die2(f"dashboard issue 拉取失败: {r.stderr.strip()[:200]}")
    try:
        item = json.loads(r.stdout)
    except json.JSONDecodeError:
        die2("dashboard issue 查询输出非法")
    if not item or not item.get("body"):
        die2(f"open dashboard issue（label={label}）不存在或 body 缺失——信号源断")
    return item["number"], parse_dashboard(item["body"])


def resolve_path(doc, path):
    """点路径取值（缺任一级=None——调用方按 pending 处理，不造数）。"""
    cur = doc
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def is_pending(value):
    """pending 判定：None / 'pending…' 标注字串（ADR-0073 决策 7 盲区口径）。"""
    if value is None:
        return True
    return isinstance(value, str) and value.strip().startswith("pending")


def crossed(value, op, threshold):
    """阈值判定（三值：True/False/None——None=不可比=待判诚实跳过）。"""
    numeric = op in ("gt", "lt", "ge", "le")
    if numeric:
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            return None
        if not isinstance(threshold, (int, float)) or isinstance(threshold, bool):
            return None
    elif not (isinstance(value, str) and isinstance(threshold, str)):
        return None
    return {"gt": value > threshold, "lt": value < threshold,
            "ge": value >= threshold, "le": value <= threshold,
            "eq": value == threshold, "ne": value != threshold}[op]


# ---------- 规则装载（机械校验 fail-closed） ----------

def load_policy(path):
    with open(path, encoding="utf-8") as f:
        p = yaml.safe_load(f) or {}
    if p.get("schema") != "feedback-edge/v1":
        die2("feedback.yaml schema 头须为 feedback-edge/v1")
    repo = str(p.get("backlog_repo") or "").strip()
    if "/" not in repo:
        die2("backlog_repo 须为 owner/repo 形态")
    di = p.get("dashboard_issue") or {}
    if not (di.get("repo") and di.get("label")):
        die2("dashboard_issue 须声明 repo+label（信号源真源）")
    signals = p.get("signals")
    if not isinstance(signals, list) or not signals:
        die2("signals 缺失或为空")
    seen = set()
    for s in signals:
        for k in ("key", "class", "description", "metric_path", "op", "spec_title"):
            if not str(s.get(k) or "").strip():
                die2(f"信号 {s.get('key') or '?'} 缺 {k}")
        if s["key"] in seen:
            die2(f"信号 key 重复: {s['key']}")
        seen.add(s["key"])
        if s["class"] not in CLASSES:
            die2(f"信号 {s['key']}: class 须 error|usage|slo")
        if s["op"] not in OPS:
            die2(f"信号 {s['key']}: op 须 {'/'.join(sorted(OPS))}")
        has_t = "threshold" in s
        has_tp = bool(str(s.get("threshold_path") or "").strip())
        if has_t == has_tp:  # 须且仅须其一（双写=口径漂移面，全拒）
            die2(f"信号 {s['key']}: threshold/threshold_path 须且仅须其一")
    return p


# ---------- 候选 spec 生成（R1 门形态——type:intent / state:ir-draft） ----------

def spec_body(key, cls, desc, value, op, threshold, dash_num, generated_at):
    """候选 spec body（AC-8g 证据面 + AC-8h 门声明——无自动签署旁路）。"""
    return f"""## 意图（R3→R1 反馈边自动生成）

运行信号越反馈阈值，自动生成候选 spec 入 backlog（宪法 §11 回边 / AC-8g）。

- **信号**：`{key}`（{cls}）
- **语义**：{desc}
- **判定**：观测值 `{value}` {op} 反馈阈值 `{threshold}` → 越阈
- **数据源**：管家账本 dashboard issue #{dash_num}（generated_at {generated_at}；机器可读 JSON，ADR-0073 口径）
- **规则真源**：governance/policy/feedback.yaml（feedback-edge/v1）

## 门（AC-8h——签署门禁不豁免）

本 issue 仅是**候选**：反馈边是生成侧，仍须走 R1 完整门——owner 签署
（state:ir-draft → state:ir-signed）→ spec PR（测试设计+红队审计）→ 才可开卡。
反馈边永不自动签署、永不置 state:ir-signed（INV-01 / BEH-01）。

处置：owner 按意图裁决——签署进 R1 门 / 关闭（wontfix 须给理由，信号复现即重开证据）。

<!-- feedback-signal: key={key} value={value} op={op} threshold={threshold} generated={generated_at} -->
"""


def create_candidate(repo, key, title, body):
    """开候选卡（labels: type:intent + state:ir-draft + feedback:<key>）。

    state:ir-draft 是唯一合法初始态（ADR-0095 角色路由）——ir-signed 属 owner
    签署动作，本函数结构性不可产生（labels 硬编码，无参数面）。
    """
    for lb in (f"feedback:{key}",):
        subprocess.run(["gh", "label", "create", lb, "--repo", repo,
                        "--description", f"反馈边信号 {key}（自动）",
                        "--color", "0e8a16"],
                       capture_output=True, text=True, env={**os.environ})
    r = subprocess.run(
        ["gh", "issue", "create", "--repo", repo, "--title", title,
         "--body", body, "--label", "type:intent", "--label", "state:ir-draft",
         "--label", f"feedback:{key}"],
        capture_output=True, text=True, env={**os.environ})
    if r.returncode != 0:
        die2(f"候选 spec 创建失败（{key}）: {r.stderr.strip()[:200]}")
    m = re.search(r"/issues/(\d+)", r.stdout)
    return int(m.group(1)) if m else None


def existing_open_issues(repo, key, existing_file):
    """去重面：open issues 带 feedback:<key>（--existing-file 注入=离线测试）。"""
    if existing_file:
        with open(existing_file, encoding="utf-8") as f:
            items = json.load(f)
        return [it["number"] for it in items
                if f"feedback:{key}" in it.get("labels", [])]
    r = subprocess.run(
        ["gh", "issue", "list", "--repo", repo, "--state", "open",
         "--label", f"feedback:{key}", "--json", "number"],
        capture_output=True, text=True, env={**os.environ})
    if r.returncode != 0:
        die2(f"去重查询失败（{key}）: {r.stderr.strip()[:200]}")
    return [it["number"] for it in json.loads(r.stdout)]


def _audit(outcome, actions):
    """审计代发（butler-audit.sh CLI：AUDIT 行+影子；同 env-drift 模式）。"""
    shadow = os.environ.get("BUTLER_SHADOW_FILE") \
        or os.path.join(DIR, "feedback", "shadow-evidence.jsonl")
    os.makedirs(os.path.dirname(shadow), exist_ok=True)
    payload = json.dumps(actions, ensure_ascii=False)
    if len(payload.encode("utf-8")) > 4096:  # INV-06：超限拒写——降级只记计数
        payload = json.dumps({"crossed": actions.get("crossed"),
                              "created": actions.get("created"),
                              "duplicates": actions.get("duplicates")},
                             ensure_ascii=False)
    subprocess.run(["bash", os.path.join(DIR, "butler-audit.sh"),
                    "feedback-edge", TRIGGER, outcome,
                    json.dumps(actions, ensure_ascii=False)],
                   env={**os.environ, "BUTLER_SHADOW_FILE": shadow,
                        "BUTLER_SHADOW_PAYLOAD": payload}, check=False)


def main():
    ap = argparse.ArgumentParser(description="R3→R1 反馈边：运行信号→候选 spec")
    ap.add_argument("--policy", default=POLICY)
    ap.add_argument("--dashboard-file", help="dashboard 信号 fixture（离线注入）")
    ap.add_argument("--existing-file", help="open issues 去重面 fixture（离线注入）")
    ap.add_argument("--dry-run", action="store_true",
                    help="只打印候选（零 gh 写调用）")
    args = ap.parse_args()

    policy = load_policy(args.policy)
    repo = policy["backlog_repo"]
    di = policy["dashboard_issue"]

    if args.dashboard_file:
        with open(args.dashboard_file, encoding="utf-8") as f:
            dash_num, doc = 0, parse_dashboard(f.read())
    else:
        if args.dry_run and not os.environ.get("GH_TOKEN"):
            die2("--dry-run 离线模式须配 --dashboard-file（信号源不可缺——无默认绿）")
        dash_num, doc = fetch_dashboard(di["repo"], di["label"])
    generated_at = doc.get("generated_at") or "unknown"

    crossed_list, pending_list, created, duplicates = [], [], [], []
    for s in policy["signals"]:
        key, op = s["key"], s["op"]
        value = resolve_path(doc, s["metric_path"])
        threshold = (resolve_path(doc, s["threshold_path"])
                     if str(s.get("threshold_path") or "").strip()
                     else s.get("threshold"))
        if is_pending(value) or is_pending(threshold):
            reason = "观测值 pending（数据源盲区）" if is_pending(value) else "阈值源 pending"
            pending_list.append(key)
            print(f"PENDING {key} {reason}——诚实跳过（不造数）")
            continue
        res = crossed(value, op, threshold)
        if res is None:
            pending_list.append(key)
            print(f"PENDING {key} 值/阈值类型不可比（value={value!r} {op} {threshold!r}）")
            continue
        if not res:
            print(f"OK     {key} value={value} {op} {threshold}（阈内）")
            continue
        crossed_list.append(key)
        print(f"SIGNAL {key} value={value} {op} {threshold} → 越阈（{s['class']}）")
        # 去重（dry-run 无 gh 面：existing-file 注入或直接报候选）
        existing = (existing_open_issues(repo, key, args.existing_file)
                    if (not args.dry_run or args.existing_file)
                    and (os.environ.get("GH_TOKEN") or args.existing_file)
                    else [])
        if existing:
            duplicates.append(key)
            print(f"DUPLICATE {key} open 候选已存在 #{existing[0]}——跳过（RB-B2）")
            continue
        body = spec_body(key, s["class"], s["description"], value, op,
                         threshold, dash_num, generated_at)
        if args.dry_run:
            # labels 行=AC-8h 可断言锚（结构性硬编码：仅 ir-draft，无签署旁路；
            # body 文本合法提及"owner 签署→ir-signed"门描述，不作红线判定面）
            print(f"CANDIDATE {key} labels=type:intent+state:ir-draft →（dry-run 不开卡）")
            print(body)
            continue
        num = create_candidate(repo, key, s["spec_title"], body)
        created.append(key)
        print(f"CANDIDATE {key} → #{num}（type:intent+state:ir-draft——入 backlog）")

    summary = {"dashboard_issue": dash_num, "generated_at": generated_at,
               "signals_total": len(policy["signals"]),
               "crossed": crossed_list, "created": created,
               "duplicates": duplicates, "pending": pending_list,
               "dry_run": args.dry_run}
    _audit("ok", summary)
    print(f"SUMMARY crossed={len(crossed_list)} created={len(created)} "
          f"duplicates={len(duplicates)} pending={len(pending_list)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
