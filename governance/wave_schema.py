#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""wave_schema.py —— 卡波次 schema v1 解析/校验（IR-0006 W2-C3 / IFACE-03 / ADR-0103）

卡 issue body 的可选扩展块（wave-planner 产卡时按需附加；缺省=无预算约束）：

    ## budget（波次预算）
    usd: 5.0
    tokens: 200000
    wallclock_sec: 7200
    human_minutes: 120
    on_exceed: hard-stop

    ## capabilities（能力 allowlist）
    - org-secret:CNB_POOL_KEY
    - vault:secret/wave/w2c1

    ## evidence（证据要求）
    - gate.merge-verdict

约定：
- 块定位：任意标题层级（issue 表单产 h3，手写卡常用 h2）——`^#{2,6}\\s*(budget|
  capabilities|evidence)\\b` 起始，至下一 `#` 标题止。
- budget：四元组 usd/tokens/wallclock_sec/human_minutes（数值 ≥0，至少一项）；
  on_exceed ∈ {hard-stop, warn}（缺省 hard-stop——声明预算即默认硬停语义，
  BEH-07/ADR-0040 复位流程不变）。
- capabilities：allowlist 式引用，仅两形态——org-secret:<大写名>（org secret 侧）
  或 vault:<路径>（内网域 Vault，值不进 Git）。非 allowlist 引用=非法。
- evidence：action 词表引用列表（受控词表由发射器侧维护，此处只做非空断言）。

子命令：
  parse      --body-file F [--card owner/repo#n]   → stdout wave-meta JSON（缺块=空对象）
  validate   --body-file F                         → 只校验（0/3）
  wave-check --cards F --ledger-dir D              → 逐卡预算对账（cost-check 消费）：
              统一账本（shadow-evidence-*.jsonl，schema v1）按 subject.card 聚合
              cost.{usd,tokens,wall_sec}，对 budget 四元组比超（human_minutes 无
              账本源——只报告不判定）；输出 JSON 数组（stdout），任一 hard-stop 卡
              超限 → exit 4。

退出码：0=成功 | 2=参数/环境 | 3=块存在但非法（fail-closed）| 4=超限（wave-check）
"""
import argparse
import glob
import json
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

BUDGET_KEYS = ("usd", "tokens", "wallclock_sec", "human_minutes")
ON_EXCEED = ("hard-stop", "warn")
SECTION_RE = re.compile(r"^#{2,6}\s*(budget|capabilities|evidence)\b[^\n]*$",
                        re.MULTILINE)
CAP_RE = re.compile(r"^(org-secret:[A-Z0-9_]+|vault:[A-Za-z0-9/_.-]+)$")


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def parse_blocks(body: str) -> dict:
    """提取 budget/capabilities/evidence 三块（yaml 解析；缺块不含键）。"""
    out = {}
    for m in SECTION_RE.finditer(body or ""):
        name = m.group(1).lower()
        start = m.end()
        nxt = body.find("\n#", start)
        chunk = body[start:nxt if nxt != -1 else len(body)]
        if yaml is None:
            out[name] = {"_raw": chunk.strip()}
            continue
        try:
            val = yaml.safe_load(chunk) if chunk.strip() else None
        except yaml.YAMLError:
            val = {"_yaml_error": True}
        if val is not None:
            out[name] = val
    return out


def validate_blocks(blocks: dict) -> list:
    errs = []
    budget = blocks.get("budget")
    if budget is not None:
        if not isinstance(budget, dict) or "_yaml_error" in budget or "_raw" in budget:
            errs.append("budget 块须为 YAML 映射（键: 值）")
        else:
            extra = set(budget) - set(BUDGET_KEYS) - {"on_exceed"}
            if extra:
                errs.append(f"budget 含非法键 {sorted(extra)}（合法 {list(BUDGET_KEYS)}+on_exceed）")
            nums = [k for k in BUDGET_KEYS if k in budget]
            if not nums:
                errs.append("budget 四元组至少声明一项（usd/tokens/wallclock_sec/human_minutes）")
            for k in nums:
                v = budget[k]
                if not isinstance(v, (int, float)) or isinstance(v, bool) or v < 0:
                    errs.append(f"budget.{k} 须为非负数值: {v!r}")
            oe = budget.get("on_exceed", "hard-stop")
            if oe not in ON_EXCEED:
                errs.append(f"budget.on_exceed 非法: {oe!r}（合法 {list(ON_EXCEED)}；缺省 hard-stop）")
    caps = blocks.get("capabilities")
    if caps is not None:
        if not isinstance(caps, list) or not caps or not all(isinstance(c, str) for c in caps):
            errs.append("capabilities 须为非空列表（- org-secret:NAME / - vault:path）")
        else:
            for c in caps:
                if not CAP_RE.match(c.strip()):
                    errs.append(f"capabilities 条目非法: {c!r}（仅 org-secret:<大写名>/vault:<路径>）")
    ev = blocks.get("evidence")
    if ev is not None:
        if not isinstance(ev, list) or not ev or not all(isinstance(e, str) and e.strip() for e in ev):
            errs.append("evidence 须为非空字符串列表（action 词表引用）")
    return errs


def wave_meta(blocks: dict, card: str = None) -> dict:
    meta = {}
    if card:
        meta["card"] = card
    for k in ("budget", "capabilities", "evidence"):
        if k in blocks:
            v = blocks[k]
            if isinstance(v, dict) and "_raw" in v:  # 无 yaml：保留原块供人工/下游解析
                meta[k] = {"_raw": v["_raw"]}
            elif isinstance(v, dict) and "_yaml_error" in v:
                meta[k] = {"_yaml_error": True}
            else:
                meta[k] = v
    if isinstance(meta.get("budget"), dict) and "_raw" not in meta["budget"]:
        meta["budget"].setdefault("on_exceed", "hard-stop")  # 缺省语义物化（消费方零默认逻辑）
    return meta


def load_shadow_records(ledger_dir: str) -> list:
    """统一账本记录（shadow-evidence-*.jsonl）——聚合源（AC-9b）。"""
    recs = []
    for f in sorted(glob.glob(os.path.join(ledger_dir, "shadow-evidence-*.jsonl"))):
        with open(f, encoding="utf-8") as fh:
            for ln in (l.strip() for l in fh):
                if ln:
                    recs.append(json.loads(ln))
    return recs


def wave_check(cards_file: str, ledger_dir: str) -> tuple:
    """逐卡对账。返回 (rows, exceeded_any)。

    聚合口径：subject.card 精确匹配；tenant 归因分离（AC-9b 多租户计量分离）；
    cost.{usd,tokens,wall_sec} 求和（无 cost 字段记 0）。human_minutes 无账本源
    ——报告不判定（备注承载）。
    """
    with open(cards_file, encoding="utf-8") as f:
        cards = json.load(f)
    recs = load_shadow_records(ledger_dir) if os.path.isdir(ledger_dir) else []
    usage = {}  # card → tenant → {usd,tokens,wall_sec}
    for r in recs:
        subj = r.get("subject") or {}
        card = subj.get("card")
        if not card:
            continue
        tenant = subj.get("tenant") or "?"
        cost = r.get("cost") or {}
        u = usage.setdefault(card, {}).setdefault(tenant, {"usd": 0.0, "tokens": 0, "wall_sec": 0.0})
        u["usd"] += float(cost.get("usd") or 0)
        u["tokens"] += int(cost.get("tokens") or 0)
        u["wall_sec"] += float(cost.get("wall_sec") or 0)

    rows, exceeded = [], False
    for c in cards:
        number = c.get("number")
        body = c.get("body") or ""
        blocks = parse_blocks(body)
        errs = validate_blocks(blocks)
        if errs:
            rows.append({"card": f"Cloudbird-Software/.github#{number}", "error": errs[0]})
            continue
        budget = blocks.get("budget")
        if budget is None:
            continue  # 无预算块=无约束（缺省语义）
        card_ref = f"Cloudbird-Software/.github#{number}"
        ten = usage.get(card_ref, {})
        agg = {"usd": sum(t["usd"] for t in ten.values()),
               "tokens": sum(t["tokens"] for t in ten.values()),
               "wall_sec": sum(t["wall_sec"] for t in ten.values())}
        on_exceed = budget.get("on_exceed", "hard-stop")
        exceeded_dims = [k for k in BUDGET_KEYS[:3]
                         if k in budget and agg[k] > float(budget[k])]
        if exceeded_dims and on_exceed == "hard-stop":
            exceeded = True
        rows.append({"card": card_ref, "budget": budget, "usage_by_tenant": ten,
                     "usage_total": agg, "exceeded_dims": exceeded_dims,
                     "on_exceed": on_exceed})
    return rows, exceeded


def main():
    ap = argparse.ArgumentParser(prog="wave_schema.py", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("parse")
    p.add_argument("--body-file", required=True)
    p.add_argument("--card", default=None, help="owner/repo#n（wave-meta 回填 card 字段）")

    p = sub.add_parser("validate")
    p.add_argument("--body-file", required=True)

    p = sub.add_parser("wave-check")
    p.add_argument("--cards", required=True, help="卡清单 JSON（gh issue list --json number,body 形态）")
    p.add_argument("--ledger-dir", required=True, help="统一账本目录（shadow-evidence-*.jsonl）")

    a = ap.parse_args()
    if a.cmd in ("parse", "validate"):
        with open(a.body_file, encoding="utf-8") as f:
            body = f.read()
        blocks = parse_blocks(body)
        errs = validate_blocks(blocks)
        if errs:
            for e in errs:
                print(f"WAVE-SCHEMA {e}", file=sys.stderr)
            die(3, f"波次块非法：{len(errs)} 处（fail-closed——T7 拒绝就绪）")
        if a.cmd == "parse":
            print(json.dumps(wave_meta(blocks, a.card), ensure_ascii=False, sort_keys=True))
        else:
            has = [k for k in ("budget", "capabilities", "evidence") if k in blocks]
            print(f"OK {'/'.join(has) if has else '无波次块（缺省语义）'}")
    elif a.cmd == "wave-check":
        rows, exceeded = wave_check(a.cards, a.ledger_dir)
        print(json.dumps(rows, ensure_ascii=False, sort_keys=True))
        if exceeded:
            die(4, "存在 hard-stop 卡超限（BEH-07：熔断三件套）")


if __name__ == "__main__":
    main()
