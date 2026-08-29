#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""conformance-corpus.py —— conformance 语料库种子工具（IR-0006 W6-M1 / AC-1b）

回放语料三元组（每条已完成卡）：
  initial_snapshot  卡开启时的快照：title + body digest + created_at
  goal              目标：任务节（## 任务）digest + AC 清单（id 提取）
  sealed_acceptance 密封验收：closed_at + state:done 收口评论 digest（密封=
                    digest 锚——验收内容不改样，改了 digest 必红）

机械校验（validate，fail-closed）：三元组结构/digest 形状/AC 非空/
done 评论 digest 在位——结构非法=红（AC-1b"结构可机械校验"）。

子命令：
  harvest  --cards-file <issues.json> --comments-dir <dir> --out corpus.jsonl
           （issues.json = gh api 拉的卡 issue 数组；comments-dir/<n>.json =
            该卡评论数组——离线 fixture 同形状，CI 在线拉取）
  validate --corpus corpus.jsonl [--min N]（N=最低条数，缺省 30）
退出码：0=绿 | 1=结构红 | 2=infra。
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

SCHEMA = "conformance-corpus/v1"
AC_RE = re.compile(r"\b(AC-[0-9]+[a-z]?)\b")
PARENT_RE = re.compile(r"父意图[:：]\s*#(\d+)")
TASK_RE = re.compile(r"##\s*任务\s*\n(.*?)(?=\n##|\Z)", re.S)
ACSEC_RE = re.compile(r"##\s*AC[^\n]*\n(.*?)(?=\n##|\Z)", re.S)
# 收口评论惯用语四种形态：state:done（T8 机器语）/ 收口 / T8 谓词 / 验收完成
DONE_COMMENT_RE = re.compile(r"state:done|收口|T8|验收完成")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def die2(msg: str) -> None:
    print(f"FATAL conformance-corpus: {msg}", file=sys.stderr)
    sys.exit(2)


def sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def extract_task(body: str) -> str:
    m = TASK_RE.search(body or "")
    return (m.group(1) if m else (body or "")).strip()


def build_entry(issue: dict, comments: list) -> dict:
    body = issue.get("body") or ""
    done_comments = [c for c in comments
                     if DONE_COMMENT_RE.search(c.get("body") or "")]
    seal = sha256_text(done_comments[-1]["body"]) if done_comments else ""
    labels = [l["name"] if isinstance(l, dict) else l for l in issue.get("labels", [])]
    parent = PARENT_RE.search(body)
    acs = sorted(set(AC_RE.findall(body)))
    ac_m = ACSEC_RE.search(body)
    ac_sec = ac_m.group(1).strip() if ac_m else ""
    ac_count = sum(1 for ln in ac_sec.splitlines() if ln.strip().startswith(("-", "*")))
    entry = {
        "schema": SCHEMA,
        "card": f"Cloudbird-Software/.github#{issue['number']}",
        "ir": f"Cloudbird-Software/.github#{parent.group(1)}" if parent else None,
        "triple": {
            "initial_snapshot": {
                "created_at": issue.get("created_at"),
                "title": issue.get("title"),
                "body_sha256": sha256_text(body),
            },
            "goal": {
                "task_sha256": sha256_text(extract_task(body)),
                "ac_ids": acs,
                "ac_section_sha256": sha256_text(ac_sec),
                "ac_count": ac_count,
                "labels_final": sorted(labels),
            },
            "sealed_acceptance": {
                "closed_at": issue.get("closed_at"),
                "done_comment_sha256": seal,
                "done_comment_sha8": seal[:8],
            },
        },
    }
    return entry


def validate_entry(e: dict) -> str | None:
    if e.get("schema") != SCHEMA:
        return "schema 非 conformance-corpus/v1"
    t = e.get("triple")
    if not isinstance(t, dict) or set(t) != {"initial_snapshot", "goal", "sealed_acceptance"}:
        return "triple 须且仅含三元组三键"
    snap, goal, seal = t["initial_snapshot"], t["goal"], t["sealed_acceptance"]
    if not snap.get("created_at") or not str(snap.get("title") or "").strip():
        return "initial_snapshot 缺 created_at/title"
    if not HEX64.match(str(snap.get("body_sha256"))):
        return "initial_snapshot.body_sha256 非 64hex"
    if not HEX64.match(str(goal.get("task_sha256"))):
        return "goal.task_sha256 非 64hex"
    # 验收判据双形态：AC id 列表（新形态）或 AC 节非空（旧卡朴素 bullet 形态）
    if not goal.get("ac_ids") and not (goal.get("ac_count", 0) >= 1
                                       and HEX64.match(str(goal.get("ac_section_sha256")))):
        return "goal 无验收判据（ac_ids 空且 AC 节空=不可回放）"
    if not seal.get("closed_at"):
        return "sealed_acceptance.closed_at 缺"
    dg = str(seal.get("done_comment_sha256"))
    if not HEX64.match(dg) or seal.get("done_comment_sha8") != dg[:8]:
        return "sealed_acceptance 密封 digest 形状非法（须 64hex+sha8 一致）"
    return None


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]

    if cmd == "harvest":
        cards_f = sys.argv[sys.argv.index("--cards-file") + 1]
        cdir = Path(sys.argv[sys.argv.index("--comments-dir") + 1])
        out_f = sys.argv[sys.argv.index("--out") + 1]
        try:
            cards = json.loads(Path(cards_f).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            die2(f"cards-file 不可读: {e}")
        if not isinstance(cards, list) or not cards:
            die2("cards-file 须为非空数组")
        entries, bad = [], 0
        for it in cards:
            num = it.get("number")
            cpath = cdir / f"{num}.json"
            try:
                comments = json.loads(cpath.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                comments = []
            e = build_entry(it, comments)
            err = validate_entry(e)
            if err:
                bad += 1
                print(f"SKIP  #{num}: {err}", file=sys.stderr)
                continue
            entries.append(e)
        Path(out_f).write_text(
            "".join(json.dumps(e, ensure_ascii=False, separators=(",", ":")) + "\n" for e in entries),
            encoding="utf-8")
        print(f"OK    语料 {len(entries)} 条落盘 {out_f}（跳过 {bad} 条结构非法）")
        return 0 if entries else 1

    if cmd == "validate":
        corpus_f = sys.argv[sys.argv.index("--corpus") + 1]
        min_n = 30
        if "--min" in sys.argv:
            min_n = int(sys.argv[sys.argv.index("--min") + 1])
        try:
            lines = [ln for ln in Path(corpus_f).read_text(encoding="utf-8").splitlines() if ln.strip()]
        except OSError as e:
            die2(f"corpus 不可读: {e}")
        errs = 0
        for i, ln in enumerate(lines, 1):
            try:
                e = json.loads(ln)
            except json.JSONDecodeError as ex:
                print(f"REJECT 第 {i} 行 JSON 非法: {ex}")
                errs += 1
                continue
            err = validate_entry(e)
            if err:
                print(f"REJECT 第 {i} 行（{e.get('card', '?')}）: {err}")
                errs += 1
        if len(lines) < min_n:
            print(f"REJECT 语料条数 {len(lines)} < 最低 {min_n}（AC-1b：30-50 张已完成卡）")
            errs += 1
        if errs:
            return 1
        print(f"OK    conformance 语料结构绿（{len(lines)} 条三元组可机械校验）")
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
