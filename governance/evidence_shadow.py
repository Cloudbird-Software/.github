#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""evidence_shadow.py —— .github 侧证据账本 schema v1 影子双写（IR-0006 W1-B2 / ADR-0103）

BEH-03 三源渐进对齐（butler/drill 侧）：新事件在写原载体（AUDIT 行 / drill
history.jsonl——均只增不改、冻结只读过渡）的同时，按统一证据 schema v1
（standards/evidence/record.schema.yaml，cloudbird/evidence-standard/record@1）
双写影子账本（单文件链，append-only + prev_hash/hash 链式 hash）。

与 CI-Workflows 侧 pipeline/metering/shadow_evidence.py 同款执法（周片→单文件
唯一差异）：tenant/card 必填、payload ≤4096B 拒写（INV-06）、链字段写入器独占、
验链 fail-closed。

子命令：
  append   事件文件 → 校验 + 链式追加（drill.py record / butler-audit.sh 双写调用）
  verify   验链：seq 连续 / prev_hash 链 / hash 重算 / tenant·card 复检
  relink   本地影子续接远端基链（butler-ledger / drill-ledger 落盘前合并用）

card 约定：卡绑定 owner/repo#issue（join key，AC-4）；无卡上下文的基建事件用
哨兵 <repo>#0——#0=未绑定卡，不参与卡聚合。
退出码：0=成功 | 2=参数/环境 | 3=记录/链无效（fail-closed）
"""
import argparse
import hashlib
import json
import os
import re
import sys

PAYLOAD_LIMIT = 4096
KINDS = {"gate", "cost", "approval", "decision"}
ROLES = {"owner", "agent", "bot", "human"}
CARD_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$")


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def canonical(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def content_hash(rec):
    return hashlib.sha256(
        canonical({k: v for k, v in rec.items() if k != "hash"}).encode("utf-8")).hexdigest()


def read_lines(path: str):
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [ln for ln in (l.strip() for l in f) if ln]


def validate_event(ev: dict):
    if {"seq", "prev_hash", "hash"} & set(ev):
        die(3, "影子事件不得自带 seq/prev_hash/hash（链字段由写入器独占）")
    if ev.get("kind") not in KINDS:
        die(3, f"kind 非法: {ev.get('kind')!r}（合法 {sorted(KINDS)}）")
    for k in ("ts", "action", "verdict"):
        if not str(ev.get(k) or "").strip():
            die(3, f"{k} 必填")
    subject = ev.get("subject")
    if not isinstance(subject, dict):
        die(3, "subject 必填（对象）")
    if not str(subject.get("tenant") or "").strip():
        die(3, "subject.tenant 必填（宪法 §14a / AC-4c）")
    if not CARD_RE.fullmatch(str(subject.get("card") or "")):
        die(3, "subject.card 必填且形如 owner/repo#issue（AC-4 join key）")
    actor = ev.get("actor")
    if not isinstance(actor, dict) or not str(actor.get("identity") or "").strip() \
            or actor.get("role") not in ROLES:
        die(3, "actor 四元不齐（identity/role 必填，role ∈ owner/agent/bot/human）")
    payload = ev.get("payload", None)
    if payload is not None:
        if not isinstance(payload, str):
            die(3, "payload 须为字符串或 null")
        if len(payload.encode("utf-8")) > PAYLOAD_LIMIT:
            die(3, f"payload {len(payload.encode('utf-8'))}B > {PAYLOAD_LIMIT}B（INV-06：超限拒写）")


def append(file_: str, ev: dict) -> dict:
    validate_event(ev)
    lines = read_lines(file_)
    rec = {k: v for k, v in ev.items() if v is not None}
    rec["seq"] = len(lines) + 1
    rec["prev_hash"] = json.loads(lines[-1])["hash"] if lines else None
    rec["hash"] = content_hash(rec)
    os.makedirs(os.path.dirname(os.path.abspath(file_)), exist_ok=True)
    with open(file_, "a", encoding="utf-8", newline="\n") as f:
        f.write(canonical(rec) + "\n")
    return rec


def verify_file(path: str) -> list:
    errs, prev = [], None
    for i, ln in enumerate(read_lines(path), 1):
        try:
            rec = json.loads(ln)
        except json.JSONDecodeError as e:
            errs.append(f"{path} 第 {i} 行 JSON 畸形: {e}")
            break
        if rec.get("seq") != i:
            errs.append(f"{path} 第 {i} 行 seq={rec.get('seq')} 断号")
        if rec.get("prev_hash") != prev:
            errs.append(f"{path} 第 {i} 行 prev_hash 断链")
        if rec.get("hash") != content_hash(rec):
            errs.append(f"{path} 第 {i} 行 hash 重算不符（篡改）")
        if not str((rec.get("subject") or {}).get("tenant") or "").strip():
            errs.append(f"{path} 第 {i} 行 tenant 缺失（AC-4c）")
        if not CARD_RE.fullmatch(str((rec.get("subject") or {}).get("card") or "")):
            errs.append(f"{path} 第 {i} 行 card 缺失/非法（AC-4）")
        payload = rec.get("payload", None)
        if isinstance(payload, str) and len(payload.encode("utf-8")) > PAYLOAD_LIMIT:
            errs.append(f"{path} 第 {i} 行 payload 超限（执法缺口）")
        prev = rec.get("hash")
    return errs


def main():
    ap = argparse.ArgumentParser(prog="evidence_shadow.py", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("append")
    p.add_argument("--file", required=True, help="影子账本 jsonl（单文件链）")
    p.add_argument("--event-file", required=True)

    p = sub.add_parser("verify")
    p.add_argument("--file", required=True)

    p = sub.add_parser("relink")
    p.add_argument("--base", required=True, help="远端基链（不存在=创世续接）")
    p.add_argument("--local", required=True)
    p.add_argument("--out", required=True)
    args = ap.parse_args()

    if args.cmd == "append":
        with open(args.event_file, encoding="utf-8") as f:
            ev = json.load(f)
        rec = append(args.file, ev)
        print(canonical(rec))
    elif args.cmd == "verify":
        errs = verify_file(args.file)
        if errs:
            for e in errs:
                print(f"CHAIN {e}", file=sys.stderr)
            die(3, f"影子验链失败：{len(errs)} 处")
        print(f"OK {args.file}: {len(read_lines(args.file))} 条，链完整")
    elif args.cmd == "relink":
        errs, base_recs = [], []
        if os.path.isfile(args.base):
            errs.extend(verify_file(args.base))
            base_recs = [json.loads(l) for l in read_lines(args.base)]
        errs.extend(verify_file(args.local))
        if errs:
            for e in errs[:10]:
                print(f"CHAIN {e}", file=sys.stderr)
            die(3, "基链或本地影子片验链失败——拒绝合并（防覆盖掩盖篡改）")
        merged = list(base_recs)
        for rec in [json.loads(l) for l in read_lines(args.local)]:
            rec = dict(rec)
            rec["seq"] = len(merged) + 1
            rec["prev_hash"] = merged[-1]["hash"] if merged else None
            rec["hash"] = content_hash(rec)
            merged.append(rec)
        with open(args.out, "w", encoding="utf-8", newline="\n") as f:
            for rec in merged:
                f.write(canonical(rec) + "\n")
        print(f"relink → {args.out}（base {len(base_recs)} + local {len(merged) - len(base_recs)} 条）")


if __name__ == "__main__":
    main()
