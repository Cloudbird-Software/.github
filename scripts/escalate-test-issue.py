#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""escalate-test-issue.py —— agent 发现测试/AC 有误时结构化上报 issue（W2-C4 .github#276，AC-18）

实现 agent 发现验收测试/AC 语义有误时经结构化上报 issue（引用 test/AC 编号）
路由 owner，TTL 内裁决（dead-man 提醒），裁决前暂停该卡相关合并——这是"发现
错误"的合法上报通道，与防篡改阻断互补。

上报结构（JSON schema: escalation-issue/v1）：
  - card_ref: 卡编号（如 Cloudbird-Software/.github#276）
  - test_ref: 有误的测试/AC 编号（如 AC-17、specs/ISSUE-263/suite/test_holdout.py）
  - finding_type: test-error / ac-error / false-positive / false-negative
  - evidence: 证据描述（引用 file:line）
  - ttl_hours: 裁决 TTL（默认 72h）
  - pause_merge: 是否暂停该卡相关合并（默认 true）

用法:
  python escalate-test-issue.py --card <repo#n> --test-ref <ref> \
      --finding <type> --evidence <text> [--ttl <hours>] \
      [--pause/--no-pause] [--output <path>] [--create-issue]
  环境变量：GH_TOKEN / APP_TOKEN

退出码: 0=上报成功/结构化记录已生成
        1=参数错误
        2=infra 错误（API 调用失败）
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.request
from typing import Any

DEFAULT_TTL_HOURS = 72


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ttl_deadline(ttl_hours: int) -> str:
    return (dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=ttl_hours)).strftime("%Y-%m-%dT%H:%M:%SZ")


def err(msg: str) -> None:
    prefix = "::error::" if os.environ.get("CI") else "FATAL: "
    print(prefix + msg, file=sys.stderr)


def die(code: int, msg: str) -> None:
    err(msg)
    sys.exit(code)


# ---------------------------------------------------------------------------
# 结构化上报记录
# ---------------------------------------------------------------------------

def build_escalation_record(card_ref: str, test_ref: str, finding_type: str,
                            evidence: str, ttl_hours: int,
                            pause_merge: bool) -> dict:
    """构建 escalation-issue/v1 结构化记录。"""
    now = now_iso()
    deadline = ttl_deadline(ttl_hours)
    return {
        "schema": "escalation-issue/v1",
        "card_ref": card_ref,
        "test_ref": test_ref,
        "finding_type": finding_type,
        "evidence": evidence,
        "reported_at": now,
        "ttl_hours": ttl_hours,
        "deadline": deadline,
        "pause_merge": pause_merge,
        "status": "open",
        "resolution": None,
        "resolved_at": None,
        "resolution_actor": None,
    }


def format_issue_body(record: dict) -> str:
    """将结构化记录格式化为 issue body。"""
    lines = [
        "## 测试/AC 语义有误上报（W2-C4 / AC-18）",
        "",
        f"- **卡编号**: {record['card_ref']}",
        f"- **有误的测试/AC**: {record['test_ref']}",
        f"- **发现类型**: {record['finding_type']}",
        f"- **证据**: {record['evidence']}",
        f"- **上报时间**: {record['reported_at']}",
        f"- **裁决 TTL**: {record['ttl_hours']}h（截止 {record['deadline']}）",
        f"- **暂停合并**: {'是' if record['pause_merge'] else '否'}",
        "",
        "### 裁决闭环（机器可核）",
        "",
        "终态：采纳 / 驳回 + 证据引用。",
        "TTL 内未处置 → dead-man 提醒（conductor 转介 arbiter / owner 通知）。",
        "裁决前该卡相关合并暂停（与防篡改阻断互补——这是'发现错误'的合法上报通道）。",
        "",
        f"<!-- escalation-meta: {json.dumps({'card': record['card_ref'], 'test': record['test_ref'], 'deadline': record['deadline']})} -->",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# GitHub API：创建 issue
# ---------------------------------------------------------------------------

def create_issue(token: str, repo: str, title: str, body: str,
                 labels: list[str] | None = None) -> dict:
    """经 GitHub API 创建 issue。"""
    data = {"title": title, "body": body}
    if labels:
        data["labels"] = labels
    req_body = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/issues",
        data=req_body,
        headers={"Authorization": f"Bearer {token}",
                 "Accept": "application/vnd.github+json",
                 "User-Agent": "escalate-test-issue"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")[:500]
        die(2, f"创建 issue 失败 HTTP {e.code}: {err_body}")
    except Exception as e:  # noqa: BLE001
        die(2, f"创建 issue 异常: {e}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(prog="escalate-test-issue.py", description="agent 发现测试/AC 有误时结构化上报 issue（W2-C4 / AC-18）")
    ap.add_argument("--card", required=True, help="卡编号（如 Cloudbird-Software/.github#276）")
    ap.add_argument("--test-ref", required=True, help="有误的测试/AC 编号")
    ap.add_argument("--finding", required=True,
                    choices=["test-error", "ac-error", "false-positive", "false-negative", "other"],
                    help="发现类型")
    ap.add_argument("--evidence", required=True, help="证据描述（引用 file:line）")
    ap.add_argument("--ttl", type=int, default=DEFAULT_TTL_HOURS, help=f"裁决 TTL 小时（默认 {DEFAULT_TTL_HOURS}）")
    ap.add_argument("--pause", dest="pause", action="store_true", default=True, help="暂停该卡相关合并（默认开启）")
    ap.add_argument("--no-pause", dest="pause", action="store_false", help="不暂停合并")
    ap.add_argument("--output", default=None, help="结构化记录输出路径（JSON）")
    ap.add_argument("--create-issue", action="store_true", help="经 GitHub API 创建 issue（需 GH_TOKEN）")
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "Cloudbird-Software/.github"),
                    help="issue 目标仓库")
    a = ap.parse_args()

    record = build_escalation_record(
        card_ref=a.card,
        test_ref=a.test_ref,
        finding_type=a.finding,
        evidence=a.evidence,
        ttl_hours=a.ttl,
        pause_merge=a.pause,
    )

    body = format_issue_body(record)
    print("== 测试/AC 语义有误上报（W2-C4 / AC-18）==")
    print(f"卡编号: {record['card_ref']}")
    print(f"有误的测试/AC: {record['test_ref']}")
    print(f"发现类型: {record['finding_type']}")
    print(f"证据: {record['evidence']}")
    print(f"TTL: {record['ttl_hours']}h（截止 {record['deadline']}）")
    print(f"暂停合并: {record['pause_merge']}")

    # 结构化记录落盘
    if a.output:
        with open(a.output, "w", encoding="utf-8", newline="\n") as f:
            json.dump(record, f, ensure_ascii=False, indent=2)
        print(f"结构化记录已写入: {a.output}")

    # 创建 issue
    if a.create_issue:
        token = os.environ.get("GH_TOKEN") or os.environ.get("APP_TOKEN") or ""
        if not token:
            die(2, "创建 issue 需要 GH_TOKEN 或 APP_TOKEN")
        title = f"[test-issue] {a.card} {a.test_ref} {a.finding}"
        labels = ["test-issue", "needs-human", f"finding:{a.finding}"]
        try:
            issue = create_issue(token, a.repo, title, body, labels)
            print(f"Issue 已创建: #{issue.get('number')} {issue.get('html_url')}")
            record["issue_number"] = issue.get("number")
            record["issue_url"] = issue.get("html_url")
            if a.output:
                with open(a.output, "w", encoding="utf-8", newline="\n") as f:
                    json.dump(record, f, ensure_ascii=False, indent=2)
        except SystemExit:
            raise

    return 0


if __name__ == "__main__":
    sys.exit(main())
