#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""escalate-test-issue.py —— agent 发现验收测试/AC 语义有误时结构化上报 issue（W2-C4 .github#276 / AC-18）

合法上报通道：实现 agent 发现测试/AC 语义有误时，经本脚本结构化上报 issue，
  - 引用 test/AC 编号；
  - 路由 owner 裁决（TTL 内 + dead-man 提醒）；
  - 裁决前暂停该卡相关合并（label:test-issue-pending 标记待裁卡，conductor/verdict
    路径应在裁决前阻断该卡合并——本脚本仅产出 issue 与暂停标记，阻断由 verdict 接线落地）。

与 g060-escalation.py（W2-C2）同模式：TTL 内未裁决 → dead-man 提醒 + 终态 expired。
本脚本是「发现错误」的合法上报通道，与防篡改阻断（g060）互补。

用法：
  python3 scripts/escalate-test-issue.py --card <owner/repo#n> \
      --test-ref <test-or-AC-ref> --reason <text> \
      [--ttl-hours 72] [--owner <login>] [--repo <owner/repo>]
  环境变量：GH_TOKEN / GITHUB_TOKEN（须对目标仓 issues:read + issues:write）

退出码：0=issue 已开出/已闭环 | 1=参数错误 | 2=issue 不存在/无权限/API 失败
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
from pathlib import Path
from typing import Any

TTL_HOURS = 72
ADOPT_RE = re.compile(r"/test-ac-adopt\b", re.IGNORECASE)
REJECT_RE = re.compile(r"/test-ac-reject\b", re.IGNORECASE)
PENDING_LABEL = "test-issue-pending"


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def gh_api(token: str, path: str, method: str = "GET", data: dict | None = None) -> Any:
    api = os.environ.get("CB_GITHUB_API", "https://api.github.com")
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(
        f"{api}{path}", data=body,
        headers={
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "cloudbrid-agent",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")[:500]
        print(f"API {method} {path} 失败 rc={e.code}: {err}", file=sys.stderr)
        raise


def main() -> int:
    ap = argparse.ArgumentParser(prog="escalate-test-issue.py",
                                 description="agent 发现测试/AC 语义有误时结构化上报 issue（AC-18）")
    ap.add_argument("--card", required=True, help="卡坐标 owner/repo#n")
    ap.add_argument("--test-ref", required=True, help="有误的测试/AC 引用（如 AC-3 或 tests/test_x.py::test_y）")
    ap.add_argument("--reason", required=True, help="错误原因（结构化描述）")
    ap.add_argument("--evidence", default="", help="证据引用（file:line 或链接）")
    ap.add_argument("--agent", default=os.environ.get("AGENT_NAME", "cloudbrid-agent"),
                    help="上报 agent 身份")
    ap.add_argument("--ttl-hours", type=int, default=TTL_HOURS, help="TTL 小时数")
    ap.add_argument("--owner", default=os.environ.get("ORG_OWNER", "randypanding"), help="人类 owner login")
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "Cloudbird-Software/.github"),
                    help="上报目标仓")
    ap.add_argument("--final-dir", default=".artescalate", help="终态落盘目录")
    ap.add_argument("--reconcile", action="store_true",
                    help="仅做裁决闭环（读取已有 issue 的 owner 评论，不新开 issue）")
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print("错误：GH_TOKEN / GITHUB_TOKEN 未设置", file=sys.stderr)
        return 1

    card = args.card
    test_ref = args.test_ref
    evidence_str = args.evidence if args.evidence else "（无）"

    # ---- 模式二：仅闭环裁决（不新开 issue）----
    if args.reconcile:
        return _reconcile(args, token)

    # ---- 模式一：开 issue ----
    title = f"[test-issue] {card} 实现 agent 发现 {test_ref} 语义有误"
    body = (
        f"## agent 结构化上报（AC-18 合法上报通道，与 g060 防篡改阻断互补）\n\n"
        f"- **卡**：`{card}`\n"
        f"- **有误引用**：`{test_ref}`\n"
        f"- **上报 agent**：`{args.agent}`\n"
        f"- **时间**：{now_iso()}\n\n"
        f"## 原因\n{args.reason}\n\n"
        f"## 证据\n{evidence_str}\n\n"
        f"## 裁决（owner）\n"
        f"- 评论 `/test-ac-adopt` = 确认测试/AC 有误，进入修复\n"
        f"- 评论 `/test-ac-reject` = 驳回（测试/AC 无误，agent 误判）\n"
        f"- **TTL {args.ttl_hours}h** 内未裁决 → dead-man 提醒 → 终态 expired（驳回）\n\n"
        f"## 合并暂停\n"
        f"本 issue 开出后，卡 `{card}` 标记 `{PENDING_LABEL}`；"
        f"裁决前该卡相关合并应暂停（verdict 接线落地）。\n\n"
        f"上报通道：`scripts/escalate-test-issue.py`（W2-C4 / AC-18）"
    )

    labels = ["test-issue", PENDING_LABEL, "triage"]
    try:
        issue = gh_api(token, f"/repos/{args.repo}/issues", "POST", {
            "title": title,
            "body": body,
            "labels": labels,
            "assignees": [args.owner],
        })
    except Exception:
        print(f"错误：开 issue 失败（{args.repo}）", file=sys.stderr)
        return 2

    issue_num = issue.get("number", "?")
    print(f"已开 issue #{issue_num} → {issue.get('html_url')}")

    # 终态落盘（初始 = pending）
    final_dir = Path(args.final_dir)
    final_dir.mkdir(parents=True, exist_ok=True)
    final_path = final_dir / f"{issue_num}.json"
    if not final_path.is_file():
        final = {
            "schema": "test-issue-final-state/v1",
            "issue": issue_num,
            "card": card,
            "test_ref": test_ref,
            "status": "pending",
            "ttl_hours": args.ttl_hours,
            "opened_at": now_iso(),
            "evidence": args.evidence,
        }
        final_path.write_text(json.dumps(final, ensure_ascii=False, indent=2),
                              encoding="utf-8", newline="\n")
        print(f"终态落盘 {final_path}: status=pending")
    return 0


def _reconcile(args, token: str) -> int:
    """裁决闭环：拉取所有 open test-issue，解析 owner 评论 + TTL。"""
    try:
        issues = gh_api(token, f"/repos/{args.repo}/issues?state=open&labels=test-issue&per_page=100")
    except Exception:
        return 2
    if not isinstance(issues, list):
        return 2
    closed_any = False
    for iss in issues:
        num = iss.get("number")
        title = iss.get("title", "")
        if "test-issue" not in title and "[test-issue]" not in title:
            continue
        final_dir = Path(args.final_dir)
        final_path = final_dir / f"{num}.json"
        created_at = iss.get("created_at", "")

        # 已闭环则跳过
        if final_path.is_file():
            existing = json.loads(final_path.read_text(encoding="utf-8"))
            if existing.get("status") in ("adopted", "rejected", "expired"):
                continue

        verdict = None
        evidence_body = None
        try:
            comments = gh_api(token, f"/repos/{args.repo}/issues/{num}/comments?per_page=100")
        except Exception:
            comments = []
        if isinstance(comments, list):
            for c in comments:
                author = (c.get("user") or {}).get("login", "")
                if author != args.owner:
                    continue
                body = c.get("body") or ""
                if ADOPT_RE.search(body):
                    verdict = "adopted"
                    evidence_body = body
                    break
                if REJECT_RE.search(body):
                    verdict = "rejected"
                    evidence_body = body
                    break

        if verdict is None and created_at:
            try:
                created = dt.datetime.strptime(created_at, "%Y-%m-%dT%H:%M:%SZ").replace(
                    tzinfo=dt.timezone.utc)
                deadline = created + dt.timedelta(hours=args.ttl_hours)
                if dt.datetime.now(dt.timezone.utc) > deadline:
                    verdict = "expired"
            except ValueError:
                pass

        if verdict is None:
            continue

        rec = {
            "schema": "test-issue-final-state/v1",
            "issue": num,
            "card": _extract_card(title),
            "status": verdict,
            "ttl_hours": args.ttl_hours,
            "resolved_at": now_iso(),
            "evidence": evidence_body,
        }
        final_path.write_text(json.dumps(rec, ensure_ascii=False, indent=2),
                              encoding="utf-8", newline="\n")
        print(f"issue #{num} 闭环: status={verdict} → {final_path}")
        closed_any = True

        if verdict == "expired":
            try:
                gh_api(token, f"/repos/{args.repo}/issues/{num}/comments", "POST", {
                    "body": (
                        f"@${args.owner} 测试/AC 上报 TTL {args.ttl_hours}h 已过，无裁决 → "
                        f"终态 **expired**（驳回处理）。如需变更请重新提交并联系 owner 裁决。\n"
                        f"dead-man 提醒时间：{now_iso()}"
                    ),
                })
                print(f"  dead-man 提醒已追加到 issue #{num}")
            except Exception as e:
                print(f"  dead-man 评论失败（终态已落盘，不阻断）: {e}", file=sys.stderr)

    if not closed_any:
        print("无待闭环 test-issue")
    return 0


def _extract_card(title: str) -> str:
    m = re.search(r"([\w.\-]+/[\w.\-]+#\d+)", title)
    return m.group(1) if m else title


if __name__ == "__main__":
    sys.exit(main())
