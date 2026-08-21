#!/usr/bin/env python3
"""metrics.py —— 度量计算库（W5-C4 .github#227，ADR-0073；宪法 §8/§12）

纯计算库：输入=采集层（dashboard-update.py / board-sync.py）拿到的原始数据结构，
输出=dashboard JSON 状态块 + human-brief 摘要。零网络、零时钟旁路（now 一律
注入）——全部口径可离线 fixture 复算（owner 周审计独立复算权，宪法 §7）。

北极星对互锁（AC-1 / ADR-0073 决策 1，宪法级）：
  零接触合并数 × 质量护栏是**一个指标对**。合并数单独上屏，Goodhart 定律保证
  系统会牺牲质量刷合并数。互锁规则：
  - 任一护栏 red → 合并数 display=0（呈现层显式归零 + 原因标注；raw 保留在 JSON
    ——非数据删除，护栏回绿自动恢复显示）
  - 护栏 pending（数据源未落/零分母）≠ 劣化，不触发归零，但独立显示盲区
    （决策 7：缺数据不得渲染成好数据，也不得渲染成坏数据）
  - 演习红率目标 ≈100%（<阈值=关卡漏检=质量劣化，ADR-0069）

阈值唯一来源 governance/policy/metrics.yaml（本库不内嵌任何阈值）。
"""
import argparse
import json
import math
import os
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    print("FATAL 缺少 PyYAML（CI 预装；本地 pip install pyyaml）", file=sys.stderr)
    raise SystemExit(2)

DIR = os.path.dirname(os.path.abspath(__file__))

# 护栏渲染序（同屏呈现顺序=后果严重度：逃逸>回滚>演习>误放行>泄漏>通过率差）
GUARD_ORDER = ("escape_rate_sustained", "revert_rate", "drill_red_rate",
               "false_allow", "state_change_leak", "holdout_gap")


def load_policy(path=None):
    p = path or os.path.join(DIR, "policy", "metrics.yaml")
    with open(p, encoding="utf-8") as f:
        return yaml.safe_load(f)


def percentile(values, q):
    """最近邻秩百分位（values 空→None：零分母诚实口径，不除零不出假值）。"""
    if not values:
        return None
    s = sorted(values)
    idx = max(0, min(len(s) - 1, math.ceil(q * len(s)) - 1))
    return s[idx]


def _guard_status(name, inp, policy):
    """单护栏三值判定：green/red/pending（缺输入或零分母=pending，不造数）。"""
    g = (policy.get("north_star") or {}).get("guardrails") or {}
    if name == "escape_rate_sustained":
        # 逃逸>0 持续=当前窗与上一窗均>0（事件时戳直算双窗，无跨轮状态残留）
        if not isinstance(inp, dict) or "current" not in inp or "previous" not in inp:
            return "pending", "数据源未接入"
        cur, prev = inp["current"], inp["previous"]
        val = {"current": cur, "previous": prev}
        if cur > 0 and prev > 0:
            return "red", f"逃逸持续：上一窗 {prev} + 本窗 {cur}（[auto-revert]+post-merge P0）"
        return "green", f"双窗逃逸 {prev}/{cur}"
    if name == "revert_rate":
        if not isinstance(inp, dict) or not inp.get("denom"):
            return "pending", "零分母（窗口内无 merged PR——不除零，#98 T2）"
        rate = inp["num"] / inp["denom"]
        thr = g["revert_rate"]["red_when_gt"]
        return ("red" if rate > thr else "green"), f"{inp['num']}/{inp['denom']}={rate:.3f}（阈 {thr}）"
    if name == "drill_red_rate":
        if not isinstance(inp, dict) or not inp.get("denom"):
            return "pending", "零可判定演习（红率不造 100%）"
        rate = inp["red"] / inp["denom"]
        thr = g["drill_red_rate"]["red_when_lt"]
        return ("red" if rate < thr else "green"), f"红 {inp['red']}/{inp['denom']}={rate:.2f}（目标 ≈100%，阈 {thr}）"
    if name == "false_allow":
        if inp is None:
            return "pending", "arbiter 台账不可读（盲区独立显示，不冒充 0）"
        return ("red" if inp > g["false_allow"]["red_when_gt"] else "green"), f"窗口内误放行 {inp} 例"
    if name in ("state_change_leak", "holdout_gap"):
        return "pending", f"数据源 pending（{g[name].get('data_source')}）——盲区独立显示"
    return "pending", f"未知护栏 {name}"


def north_star(data, policy):
    """北极星对同屏互锁（AC-1）。data 键：zero_touch_merges_7d:int|None + 各护栏输入。"""
    raw = data.get("zero_touch_merges_7d")
    guards, reasons = {}, []
    for name in GUARD_ORDER:
        status, detail = _guard_status(name, data.get(name), policy)
        guards[name] = {"status": status, "detail": detail}
        if status == "red":
            reasons.append(name)
    zeroed = bool(reasons)  # 呈现层归零=仅护栏 red；pending/零合并周不标注归零
    display = 0 if zeroed else (raw if raw is not None else 0)
    return {
        "zero_touch_merges_7d": {
            "raw": raw,  # 原始计数永不删除（归零只在呈现层）
            "display": display, "zeroed": zeroed,
            "zeroed_reasons": reasons,
            "note": ("护栏破线期间的产出计数无意义——显示归零+原因标注；"
                     "raw 保留（ADR-0073 决策 1：呈现层归零，非数据删除）"
                     if zeroed else ("零接触合并周（分母为 0 的如实 0）" if raw == 0 else "护栏全绿——如实显示")),
        },
        "guardrails": guards,
        "interlocked_zeroed": zeroed,
        "pending_blind_zones": [n for n in GUARD_ORDER if guards[n]["status"] == "pending"],
    }


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("northstar", help="北极星互锁判定（fixture 输入→JSON 输出）")
    a.add_argument("--input", required=True, help="JSON 文件：{zero_touch_merges_7d, escape_rate_sustained, ...}")
    a.add_argument("--policy", default=None)
    a.add_argument("--now", default=None, help="注入时钟（ISO）——离线复算用")
    args = ap.parse_args(argv)
    policy = load_policy(args.policy)
    with open(args.input, encoding="utf-8") as f:
        data = json.load(f)
    if args.now:  # 显式注入优先（owner 复算可复现；缺省取系统钟）
        os.environ["METRICS_NOW"] = args.now
    print(json.dumps(north_star(data, policy), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
