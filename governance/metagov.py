#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""metagov.py —— 门禁元治理四列指标评审+胜出实践晋级（IR-0006 W6-M1 / AC-1c）

四列（policy/metrics.yaml gate_metagovernance.four_columns 声明）：
  gate        门禁锚（<workflow>:<job>——须真实存在于 .github/workflows/*.yml，
              声明与实现漂移=红，机械对账全仓 job 清单）
  judge       判定语义（mechanical=机械谓词 / pending=声明位未落——ADR-0073
              决策 7：缺数据不渲染成好数据）
  data_source 真源（文件/账本路径）
  red_line    红线记录（fail-closed 生效锚——负向断言在位=红线可执法，
              带 run 引用=红线已活体触发过）

胜出实践晋级（promote）：append-only 账本 conformance/promotions.jsonl
（hash 链，公式同 write_evidence——改历史必断链，verify 随时巡检）。
记录字段：practice/goal/evidence（≥1 条引用）/promoted_by/ts——
胜出=有证据支撑的实践胜出（评审产出），晋级=进政策/流程的留痕。

子命令：
  review   --policy metrics.yaml --workflows-dir <.github/workflows> --out review.json
  promote  --registry promotions.jsonl --record rec.json
  verify   --registry promotions.jsonl
退出码：0=绿 | 1=红（漂移/结构/断链）| 2=infra。
"""
from __future__ import annotations

import datetime
import hashlib
import json
import sys
from pathlib import Path

import yaml

FOUR_COLUMNS = ["gate", "judge", "data_source", "red_line"]
JUDGES = {"mechanical", "pending"}


def die2(msg: str) -> None:
    print(f"FATAL metagov: {msg}", file=sys.stderr)
    sys.exit(2)


def canon(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def content_hash(rec: dict) -> str:
    return hashlib.sha256(canon({k: v for k, v in rec.items() if k != "hash"}).encode("utf-8")).hexdigest()


def now_utc() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_policy(path: str) -> dict:
    try:
        p = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as e:
        die2(f"metrics.yaml 不可读: {e}")
    mg = (p or {}).get("gate_metagovernance")
    if not isinstance(mg, dict):
        die2("metrics.yaml 缺 gate_metagovernance 节（W6-M1 metrics 扩展）")
    if mg.get("four_columns") != FOUR_COLUMNS:
        die2(f"gate_metagovernance.four_columns 须为 {FOUR_COLUMNS}")
    gates = mg.get("gates")
    if not isinstance(gates, list) or not gates:
        die2("gate_metagovernance.gates 缺失或为空")
    for g in gates:
        if set(g) != set(FOUR_COLUMNS):
            die2(f"门禁行须且仅含四列 {FOUR_COLUMNS}: {sorted(g)}")
        if g["judge"] not in JUDGES:
            die2(f"gate {g['gate']}: judge 须 mechanical|pending")
        if not str(g["data_source"] or "").strip() or not str(g["red_line"] or "").strip():
            die2(f"gate {g['gate']}: data_source/red_line 不得为空")
    return mg


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]

    if cmd == "review":
        pol = sys.argv[sys.argv.index("--policy") + 1]
        wdir = Path(sys.argv[sys.argv.index("--workflows-dir") + 1])
        out = sys.argv[sys.argv.index("--out") + 1]
        mg = load_policy(pol)
        # 全仓 job 清单（<workflow>:<job>）——机械对账面
        anchors = set()
        for wf in sorted(wdir.glob("*.yml")):
            try:
                jobs = yaml.safe_load(wf.read_text(encoding="utf-8"))["jobs"]
            except (yaml.YAMLError, KeyError, TypeError):
                die2(f"workflow 不可解析: {wf.name}")
            for j in jobs:
                anchors.add(f"{wf.stem}:{j}")
        ghosts = [g["gate"] for g in mg["gates"] if g["gate"] not in anchors]
        if ghosts:
            print(f"REJECT 声明门禁不在 workflows job 清单（漂移）: {ghosts}")
            return 1
        review = {
            "schema": "gate-metagovernance-review/v1",
            "generated_at": now_utc(),
            "four_columns": FOUR_COLUMNS,
            "gates": mg["gates"],
            "workflow_jobs_total": len(anchors),
            "declared_total": len(mg["gates"]),
        }
        Path(out).write_text(json.dumps(review, ensure_ascii=False, indent=1), encoding="utf-8")
        pend = sum(1 for g in mg["gates"] if g["judge"] == "pending")
        print(f"OK    四列评审产出 {out}（{len(mg['gates'])} 门禁全对账在册/"
              f"全仓 {len(anchors)} job；pending {pend} 诚实不造数）")
        return 0

    if cmd == "promote":
        reg = sys.argv[sys.argv.index("--registry") + 1]
        rec_f = sys.argv[sys.argv.index("--record") + 1]
        try:
            rec = json.loads(Path(rec_f).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            die2(f"record 不可读: {e}")
        if {"practice", "goal", "evidence", "promoted_by"} - set(rec):
            die2("晋级记录缺必填（practice/goal/evidence/promoted_by）")
        if not isinstance(rec.get("evidence"), list) or not rec["evidence"]:
            die2("evidence 须为非空数组（胜出=有证据——空证据晋级=自封）")
        if any(k in rec for k in ("seq", "prev_hash", "hash")):
            die2("链字段由本工具独占计算，记录不得自带")
        lines = []
        rp = Path(reg)
        if rp.exists():
            lines = [ln for ln in rp.read_text(encoding="utf-8").splitlines() if ln.strip()]
            # 追加前先验既有链（append-only 的前提=旧链完好）
            rc = _verify_lines(lines)
            if rc:
                return rc
        rec["ts"] = rec.get("ts") or now_utc()
        rec["seq"] = len(lines) + 1
        rec["prev_hash"] = json.loads(lines[-1])["hash"] if lines else None
        rec["hash"] = content_hash(rec)
        with open(reg, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(f"OK    晋级记录 #{rec['seq']} 已追加（hash 尾={rec['hash'][-12:]}）")
        return 0

    if cmd == "verify":
        reg = sys.argv[sys.argv.index("--registry") + 1]
        try:
            lines = [ln for ln in Path(reg).read_text(encoding="utf-8").splitlines() if ln.strip()]
        except OSError as e:
            die2(f"registry 不可读: {e}")
        return _verify_lines(lines)

    print(__doc__)
    return 2


def _verify_lines(lines: list) -> int:
    prev = None
    for i, ln in enumerate(lines, 1):
        try:
            rec = json.loads(ln)
        except json.JSONDecodeError as e:
            print(f"REJECT 第 {i} 行 JSON 非法: {e}")
            return 1
        if rec.get("seq") != i:
            print(f"REJECT 第 {i} 行 seq={rec.get('seq')}（应 {i}）")
            return 1
        if rec.get("prev_hash") != prev:
            print(f"REJECT 第 {i} 行 prev_hash 断链")
            return 1
        if content_hash(rec) != rec.get("hash"):
            print(f"REJECT 第 {i} 行 hash 不符（改历史必断链）")
            return 1
        if not rec.get("evidence"):
            print(f"REJECT 第 {i} 行 evidence 空")
            return 1
        prev = rec["hash"]
    print(f"OK    晋级账本链完整（{len(lines)} 条）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
