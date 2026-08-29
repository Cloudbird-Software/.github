#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""eval-gate.py —— 非劣性 eval gate 家族判定器（IR-0006 W5-E1 / AC-10b / BEH-08 / INV-01）

机械判定（零 LLM、零自报采信）：消费 baseline/candidate 两份指标报告 +
policy/eval-gates.yaml 阈值声明，逐家族谓词求值：
  non_inferiority —— 逐指标：higher 方向 candidate ≥ baseline−δ；
                      lower 方向 candidate ≤ baseline+δ（恰达边界=过）
  cost / latency  —— 回归上界 ratio（candidate ≤ baseline × ratio_max）
  contamination   —— baseline 数据集 digest 不得出现在优化输入面（substring 扫描）

fail-closed（AC-10b）：报告缺 policy 声明指标 / 缺 cost/latency / 污染命中 /
报告不可解析 = 红；policy 结构非法 = infra（exit 2）。无默认绿。

报告 schema（baseline.json / candidate.json）：
  {"metrics": {"<name>": <number>, …}, "cost_usd": <number>,
   "latency_ms": <number>, "provenance": "<run/fixture 声明>"}

事件输出（--event-out，写入器外部落账）：kind=gate / action=eval-noninferiority
/ verdict=green|red / subject.card+tenant / payload=指标摘要（4KB 内，INV-06）——
链字段（seq/prev_hash/hash）由 write_evidence 独占，本工具不自带。

用法：
  eval-gate.py --policy <eval-gates.yaml> --baseline <b.json> --candidate <c.json> \
               --card <owner/repo#n> --tenant <t> [--dataset-digest <64hex>] \
               [--inputs <优化输入清单文件>] [--event-out <ev.json>]
退出码：0=全家族绿 | 1=红（任一族不过）| 2=infra（policy/报告/参数坏）。
"""
from __future__ import annotations

import argparse
import json
import sys

import yaml


def die2(msg: str) -> None:
    print(f"FATAL eval-gate: {msg}", file=sys.stderr)
    sys.exit(2)


class Red(Exception):
    pass


def load_report(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        die2(f"报告不可读: {path}: {e}")
    if not isinstance(data, dict) or not isinstance(data.get("metrics"), dict):
        die2(f"报告结构非法（须含 metrics 对象）: {path}")
    return data


def num(v) -> float:
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise Red(f"指标值非数值: {v!r}")
    return float(v)


def check_policy(p: dict) -> None:
    fam = p.get("family") or {}
    metrics = p.get("metrics") or {}
    reg = p.get("regressions") or {}
    if not isinstance(fam.get("required"), list) or not fam.get("required"):
        die2("policy.family.required 缺失或为空")
    if not str(fam.get("baseline_ref") or "").strip():
        die2("policy.family.baseline_ref 缺失（holdout id@sha8）")
    if not metrics:
        die2("policy.metrics 为空（无指标可执法）")
    for name, spec in metrics.items():
        if not isinstance(spec, dict) or spec.get("direction") not in ("higher", "lower"):
            die2(f"policy.metrics.{name}.direction 非法（须 higher|lower）")
        d = spec.get("delta")
        if isinstance(d, bool) or not isinstance(d, (int, float)) or d < 0:
            die2(f"policy.metrics.{name}.delta 非法（须 ≥0 数值）")
    for k in ("cost_ratio_max", "latency_ratio_max"):
        v = reg.get(k)
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v < 1:
            die2(f"policy.regressions.{k} 非法（须 ≥1 数值）")


def main() -> int:
    ap = argparse.ArgumentParser(description="非劣性 eval gate 家族判定（机械，fail-closed）")
    ap.add_argument("--policy", required=True)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--card", required=True, help="owner/repo#n（事件 join key）")
    ap.add_argument("--tenant", required=True)
    ap.add_argument("--dataset-digest", default=None, help="baseline 数据集 sha256（64hex，污染检查锚）")
    ap.add_argument("--inputs", default=None, help="优化输入面清单文件（污染检查：digest 不得出现）")
    ap.add_argument("--event-out", default=None, help="判定事件 JSON 输出（外部经 write_evidence 落账）")
    args = ap.parse_args()

    try:
        with open(args.policy, encoding="utf-8") as f:
            policy = yaml.safe_load(f)
    except (OSError, yaml.YAMLError) as e:
        die2(f"policy 不可读: {e}")
    if not isinstance(policy, dict):
        die2("policy 顶层须为映射")
    check_policy(policy)

    base = load_report(args.baseline)
    cand = load_report(args.candidate)
    required = policy["family"]["required"]
    failures: list[str] = []

    # ---- non_inferiority：逐指标（缺声明指标=红，防少报躲门槛）----
    if "non_inferiority" in required:
        for name, spec in policy["metrics"].items():
            for side in ("baseline", "candidate"):
                if name not in base["metrics"] or name not in cand["metrics"]:
                    failures.append(f"non_inferiority: {side} 报告缺声明指标 {name}（fail-closed）")
                    continue
            if name not in base["metrics"] or name not in cand["metrics"]:
                continue
            try:
                b, c = num(base["metrics"][name]), num(cand["metrics"][name])
            except Red as e:
                failures.append(f"non_inferiority: {name}: {e}")
                continue
            d = float(spec["delta"])
            if spec["direction"] == "higher" and c < b - d:
                failures.append(f"non_inferiority: {name} 劣化超 δ（baseline={b} candidate={c} δ={d}，higher 方向）")
            if spec["direction"] == "lower" and c > b + d:
                failures.append(f"non_inferiority: {name} 劣化超 δ（baseline={b} candidate={c} δ={d}，lower 方向）")

    # ---- cost / latency 回归上界（缺失=红：无默认绿）----
    for fam, key, ratio_key in (("cost", "cost_usd", "cost_ratio_max"),
                                ("latency", "latency_ms", "latency_ratio_max")):
        if fam not in required:
            continue
        if key not in base or key not in cand:
            failures.append(f"{fam}: 报告缺 {key}（fail-closed——回归上界无从执法）")
            continue
        try:
            b, c = num(base[key]), num(cand[key])
        except Red as e:
            failures.append(f"{fam}: {key}: {e}")
            continue
        ratio = float(policy["regressions"][ratio_key])
        if c > b * ratio:
            failures.append(f"{fam}: 回归超上界（baseline={b} candidate={c} ratio_max={ratio}）")

    # ---- contamination：数据集 digest 不得进优化输入面 ----
    if "contamination" in required:
        dg = (args.dataset_digest or "").strip()
        if not dg:
            die2("required 含 contamination 但 --dataset-digest 缺失（无从执法=fail-closed）")
        if not args.inputs:
            die2("required 含 contamination 但 --inputs 缺失（无从执法=fail-closed）")
        try:
            with open(args.inputs, encoding="utf-8") as f:
                inputs_text = f.read()
        except OSError as e:
            die2(f"inputs 文件不可读: {e}")
        probes = {dg, dg[:16]}
        hit = next((p for p in probes if p and p in inputs_text), None)
        if hit:
            failures.append(f"contamination: baseline 数据集 digest（{hit[:16]}…）出现在优化输入面——对考卷过拟合，红")

    verdict = "green" if not failures else "red"
    for m in failures:
        print(f"REJECT {m}")
    print(f"{verdict.upper():5} 非劣性 eval gate 家族裁决（required={required}，"
          f"指标 {len(policy['metrics'])} 项，违 {len(failures)}）")

    if args.event_out:
        event = {
            "kind": "gate",
            "action": "eval-noninferiority",
            "verdict": "green" if verdict == "green" else "red",
            "subject": {
                "wave": "W5",
                "card": args.card,
                "tenant": args.tenant,
            },
            "actor": {"identity": "eval-gate-bot", "role": "bot", "model": None},
            "payload": json.dumps({
                "baseline_ref": policy["family"]["baseline_ref"],
                "required": required,
                "metrics": {k: {"baseline": base["metrics"].get(k), "candidate": cand["metrics"].get(k)}
                            for k in policy["metrics"]},
                "cost_usd": [base.get("cost_usd"), cand.get("cost_usd")],
                "latency_ms": [base.get("latency_ms"), cand.get("latency_ms")],
                "violations": len(failures),
            }, ensure_ascii=False, separators=(",", ":")),
        }
        with open(args.event_out, "w", encoding="utf-8") as f:
            json.dump(event, f, ensure_ascii=False, indent=1)
    return 0 if verdict == "green" else 1


if __name__ == "__main__":
    sys.exit(main())
