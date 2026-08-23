#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""g060-escalation.py —— g060 裁决闭环（ISSUE-263 W2-C2 / ADR-0061 / ADR-0081）

读取 g060 裁决 issue 的 owner 评论，解析 /g060-adopt 与 /g060-reject 指令，
写入终态（机器可核：终态 JSON 含 issue/裁决人/裁决时间/证据引用/终态值），
并执行 TTL + dead-man 提醒。

终态落盘：.artg060/<issue_number>.json（machine-verifiable final state）
  status: adopted | rejected | expired
  evidence: 裁决评论的 body + created_at（字符串级核对基准）
  ttl_hours: 72（TTL 内未裁决 → dead-man 提醒；仍无裁决 → 终态=expired + 升级）

用法：
  python3 scripts/g060-escalation.py --issue <n> --repo <owner/repo> [--owner <owner>]
  环境变量：GH_TOKEN / GITHUB_TOKEN（须对目标仓 issues:read + issues:write）

退出码：0=已闭环（adopted/rejected/expired 已落盘） | 1=参数错误 | 2=issue 不存在/无权限
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

TTL_HOURS = 72
ADOPT_RE = re.compile(r"/g060-adopt\b", re.IGNORECASE)
REJECT_RE = re.compile(r"/g060-reject\b", re.IGNORECASE)


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def gh_api(token: str, path: str, method: str = "GET", data: dict | None = None) -> dict | list:
    api = os.environ.get("CB_GITHUB_API", "https://api.github.com")
    body = json.dumps(data).encode("utf-8") if data else None
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
    ap = argparse.ArgumentParser()
    ap.add_argument("--issue", required=True, type=int, help="裁决 issue 编号")
    ap.add_argument("--repo", required=True, help="owner/repo")
    ap.add_argument("--owner", default="randypanding", help="人类 owner login")
    ap.add_argument("--final-dir", default=".artg060", help="终态落盘目录")
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print("错误：GH_TOKEN / GITHUB_TOKEN 未设置", file=sys.stderr)
        return 1

    # 读取 issue 详情
    try:
        issue = gh_api(token, f"/repos/{args.repo}/issues/{args.issue}")
    except Exception:
        print(f"错误：无法读取 issue #{args.issue}（{args.repo}）", file=sys.stderr)
        return 2

    title = issue.get("title", "")
    if "g060 blocked" not in title:
        print(f"警告：issue #{args.issue} 标题不含 'g060 blocked'，仍尝试处理", file=sys.stderr)

    created_at = issue.get("created_at", "")
    state = issue.get("state", "")

    final_dir = Path(args.final_dir)
    final_dir.mkdir(parents=True, exist_ok=True)
    final_path = final_dir / f"{args.issue}.json"

    # 已落盘则幂等返回
    if final_path.is_file():
        existing = json.loads(final_path.read_text(encoding="utf-8"))
        print(f"终态已落盘 {final_path}: status={existing.get('status')}")
        return 0

    # 拉取评论，找 owner 的 adopt/reject 指令
    verdict: str | None = None
    evidence: dict | None = None
    try:
        comments = gh_api(token, f"/repos/{args.repo}/issues/{args.issue}/comments?per_page=100")
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
                evidence = {"comment_body": body, "created_at": c.get("created_at", ""), "author": author}
                break
            if REJECT_RE.search(body):
                verdict = "rejected"
                evidence = {"comment_body": body, "created_at": c.get("created_at", ""), "author": author}
                break

    # TTL 判定
    if verdict is None and created_at:
        try:
            created = dt.datetime.strptime(created_at, "%Y-%m-%dT%H:%M:%SZ").replace(
                tzinfo=dt.timezone.utc)
            deadline = created + dt.timedelta(hours=TTL_HOURS)
            if dt.datetime.now(dt.timezone.utc) > deadline:
                verdict = "expired"
                evidence = {"reason": f"TTL {TTL_HOURS}h 已过", "created_at": created_at,
                            "deadline": deadline.strftime("%Y-%m-%dT%H:%M:%SZ"),
                            "dead_man": True}
        except ValueError:
            pass

    if verdict is None:
        print(f"issue #{args.issue} 尚未裁决且 TTL 未过 → 待决（退出 0，等待下次轮询）")
        return 0

    # 写终态
    final = {
        "schema": "g060-final-state/v1",
        "issue": args.issue,
        "repo": args.repo,
        "status": verdict,
        "evidence": evidence,
        "ttl_hours": TTL_HOURS,
        "resolved_at": now_iso(),
    }
    if state == "closed":
        final["issue_state"] = "closed"
    final_path.write_text(json.dumps(final, ensure_ascii=False, indent=2),
                          encoding="utf-8", newline="\n")
    print(f"终态落盘 {final_path}: status={verdict}")
    print(json.dumps(final, ensure_ascii=False, indent=2))

    # expired → 提醒（评论提醒 owner）
    if verdict == "expired":
        try:
            gh_api(token, f"/repos/{args.repo}/issues/{args.issue}/comments", "POST", {
                "body": (
                    f"@${args.owner} g060 裁决 TTL {TTL_HOURS}h 已过，无裁决 → 终态 "
                    f"**expired**（驳回处理）。如需变更请重新提交并联系 owner 裁决。\n"
                    f"dead-man 提醒时间：{now_iso()}"
                ),
            })
            print("已追加 dead-man 提醒评论")
        except Exception as e:
            print(f"追加 dead-man 评论失败（终态已落盘，不阻断）: {e}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
