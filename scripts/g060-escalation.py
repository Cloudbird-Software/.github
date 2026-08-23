#!/usr/bin/env python3
"""
g060-escalation.py —— ADR-0061 g060 裁决闭环（ISSUE-263 W2-C2）

读取 g060-lock.sh 创建的裁决 issue，解析 owner 终态指令：
  /g060-adopt  <证据引用>   → 采纳
  /g060-reject <证据引用>   → 驳回

输出机器可核的终态 JSON，并在超 TTL 时自动追加 dead-man 提醒评论。

用法：
  python3 g060-escalation.py --issue <number> [--repo owner/repo]
  python3 g060-escalation.py --all [--repo owner/repo]

退出码：
  0 = 处理完成（无论终态/待决）
  1 = 环境/参数/工具错误
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

DEFAULT_OWNER = "randypanding"
DEFAULT_TTL_HOURS = 72
DEFAULT_DEADMAN_INTERVAL_HOURS = 24
DEADMAN_MARKER = "<!-- g060-deadman-reminder -->"
TITLE_PREFIX = "g060 blocked:"


def parse_args(argv=None):
    p = argparse.ArgumentParser(description="g060 裁决闭环")
    p.add_argument("--issue", type=int, help="单个裁决 issue 编号")
    p.add_argument("--repo", default=os.getenv("GH_REPO", os.getenv("GITHUB_REPOSITORY", "")),
                   help="目标仓库（默认 GH_REPO/GITHUB_REPOSITORY）")
    p.add_argument("--owner", default=DEFAULT_OWNER, help="owner GitHub login")
    p.add_argument("--ttl-hours", type=int, default=DEFAULT_TTL_HOURS, help="裁决 TTL（小时）")
    p.add_argument("--deadman-interval-hours", type=int, default=DEFAULT_DEADMAN_INTERVAL_HOURS,
                   help="dead-man 提醒间隔（小时）")
    p.add_argument("--all", action="store_true", help="处理所有打开的 g060 裁决 issue")
    p.add_argument("--dry-run", action="store_true", help="只输出，不实际评论")
    return p.parse_args(argv)


def utcnow():
    return datetime.now(timezone.utc)


def parse_iso(value: str) -> datetime:
    # GitHub REST 返回 ISO8601Z，如 2026-08-22T14:41:36Z
    value = value.replace("Z", "+00:00")
    return datetime.fromisoformat(value)


def gh_json(args: list) -> dict | list:
    cmd = ["gh"] + args + ["--json", "*"]
    repo = os.environ.get("GH_REPO") or os.environ.get("GITHUB_REPOSITORY")
    if repo and "--repo" not in args:
        cmd += ["--repo", repo]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"gh 调用失败：{' '.join(cmd)}\n{proc.stderr}")
    return json.loads(proc.stdout)


def list_open_blocked_issues(repo: str):
    """列出标题含 g060 blocked: 的 open issue。"""
    cmd = [
        "issue", "list", "--state", "open",
        "--search", f"{TITLE_PREFIX} in:title",
        "--limit", "100",
    ]
    if repo:
        cmd += ["--repo", repo]
    return gh_json(cmd)


def fetch_issue(repo: str, number: int):
    cmd = ["issue", "view", str(number)]
    if repo:
        cmd += ["--repo", repo]
    return gh_json(cmd)


def post_comment(repo: str, number: int, body: str, dry_run: bool):
    print(f"[issue #{number}] 准备追加 dead-man 提醒")
    if dry_run:
        print("DRY-RUN，跳过评论")
        return
    cmd = ["issue", "comment", str(number), "--body", body]
    if repo:
        cmd += ["--repo", repo]
    proc = subprocess.run(["gh"] + cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"评论失败 #{number}: {proc.stderr}")
    print(f"[issue #{number}] 已追加 dead-man 提醒")


def parse_resolution(comments: list, owner: str):
    """
    从评论中解析 owner 终态指令。
    返回 (state, evidence, resolver_login, resolved_at) 或 (None, [], None, None)。
    """
    # 按时间顺序遍历评论
    for c in comments:
        login = (c.get("author", {}) or {}).get("login", "")
        body = c.get("body", "") or ""
        created = c.get("createdAt", "")
        if not body or not created:
            continue
        # 仅 owner 或 assignee 的指令视为有效；为简化，仅信任 owner login
        if login != owner:
            continue
        for line in body.splitlines():
            line = line.strip()
            m = re.match(r"^/(g060-(?:adopt|reject))\b\s*(.*)$", line, re.IGNORECASE)
            if not m:
                continue
            state = "adopted" if m.group(1).lower() == "g060-adopt" else "rejected"
            evidence = [x.strip() for x in m.group(2).split(",") if x.strip()]
            # 也收集后续非空行作为证据，直到空行
            return state, evidence, login, created
    return None, [], None, None


def process_issue(repo: str, issue_number: int, owner: str, ttl_hours: int,
                  deadman_interval_hours: int, dry_run: bool):
    data = fetch_issue(repo, issue_number)
    title = data.get("title", "")
    state = data.get("state", "")
    created_at = parse_iso(data.get("createdAt", ""))
    comments = data.get("comments", []) or []

    result = {
        "issue": issue_number,
        "title": title,
        "state": state,
        "created_at": data.get("createdAt"),
        "resolver": None,
        "resolved_at": None,
        "final_state": None,
        "evidence": [],
        "evidence_valid": False,
        "ttl_hours": ttl_hours,
        "ttl_expired": False,
        "deadman_reminder_posted": False,
    }

    final, evidence, resolver_login, resolved_at = parse_resolution(comments, owner)
    if final:
        result["final_state"] = final
        result["evidence"] = evidence
        result["resolver"] = resolver_login
        result["resolved_at"] = resolved_at
        # 终态必须带证据引用，否则机器可核判为无效
        result["evidence_valid"] = len(evidence) > 0
        return result

    # 未裁决：检查 TTL 与 dead-man
    age_hours = (utcnow() - created_at).total_seconds() / 3600
    result["ttl_expired"] = age_hours > ttl_hours

    if age_hours > ttl_hours:
        # 避免重复提醒：检查是否已有 dead-man marker
        already = any(DEADMAN_MARKER in (c.get("body", "") or "") for c in comments)
        if not already:
            body = (
                f"{DEADMAN_MARKER}\n"
                f"@:{owner} 该 g060 阻断 issue 已超 {ttl_hours}h 未裁决，"
                f"请于 {deadman_interval_hours}h 内给出 `/g060-adopt <证据>` 或 "
                f"`/g060-reject <证据>` 终态指令。"
            )
            post_comment(repo, issue_number, body, dry_run)
            result["deadman_reminder_posted"] = True

    return result


def main(argv=None):
    args = parse_args(argv)
    if not args.repo:
        print("错误：--repo 或 GH_REPO/GITHUB_REPOSITORY 未设置", file=sys.stderr)
        return 1
    if not args.issue and not args.all:
        print("错误：--issue 或 --all 必须指定一个", file=sys.stderr)
        return 1

    issues = []
    if args.issue:
        issues = [{"number": args.issue}]
    else:
        try:
            raw = list_open_blocked_issues(args.repo)
        except RuntimeError as e:
            print(f"错误：列出 g060 issue 失败：{e}", file=sys.stderr)
            return 1
        issues = raw

    if not issues:
        print(json.dumps({"repo": args.repo, "processed": [], "message": "无待处理 g060 裁决 issue"},
                         ensure_ascii=False, indent=2))
        return 0

    processed = []
    for it in issues:
        number = it.get("number")
        if not number:
            continue
        try:
            result = process_issue(args.repo, number, args.owner, args.ttl_hours,
                                   args.deadman_interval_hours, args.dry_run)
            processed.append(result)
        except Exception as e:
            processed.append({"issue": number, "error": str(e)})

    summary = {
        "repo": args.repo,
        "processed": processed,
        "pending_count": sum(1 for r in processed if r.get("final_state") is None and "error" not in r),
        "resolved_count": sum(1 for r in processed if r.get("final_state") is not None),
        "ttl_expired_count": sum(1 for r in processed if r.get("ttl_expired")),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
