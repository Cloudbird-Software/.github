#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""escalate-test-issue.py —— 实现 agent 发现测试/AC 有误时结构化上报 issue（W2-C4 .github#276 / AC-18）

当实现 agent 发现验收测试/AC 语义有误（测试本身写错、AC 理解偏差、断言与 spec 不一致），
经本脚本结构化上报 issue：
  - 引用 test/AC 编号（机器可追溯）；
  - 路由 owner 裁决（TTL 内 + dead-man 提醒）；
  - 裁决前暂停该卡相关合并（防错误测试放行实现）。

这是"发现错误"的合法上报通道，与 g060 防篡改阻断互补：
  - g060 防的是"开发 agent 篡改测试以通过"（阻断+开 issue）；
  - 本脚本是"agent 发现测试本身有误"（上报+暂停合并+等裁决）。

终态落盘：.artest/<issue_number>.json（machine-verifiable final state）
  status: adopted | rejected | expired
  evidence: 上报评论 body + 引用的 test/AC 编号
  ttl_hours: 48（裁决窗口，短于 g060 的 72h——测试错误阻塞实现，须更快响应）

用法：
  python3 scripts/escalate-test-issue.py create \
      --card ISSUE-263 --repo Cloudbird-Software/.github \
      --test-ref "specs/ISSUE-263/suite/test_tax.py::test_brackets" \
      --ac-ref AC-3 \
      --reason "断言期望值与 spec §AC-3 不一致（spec 要求 ≥0.7，断言写 0.5）" \
      --actor cloudbrid-agent
  python3 scripts/escalate-test-issue.py resolve --issue <n> --repo <owner/repo> [--owner <login>]

退出码：0=已闭环/已创建 | 1=参数错误 | 2=issue 不存在/无权限
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

TTL_HOURS = 48
ADOPT_RE = re.compile(r"/test-adopt\b", re.IGNORECASE)
REJECT_RE = re.compile(r"/test-reject\b", re.IGNORECASE)
COMMENT_RE = re.compile(r"/test-comment\b", re.IGNORECASE)


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def gh_api(token: str, path: str, method: str = "GET", data: dict | None = None):
    api = os.environ.get("CB_GITHUB_API", "https://api.github.com")
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(
        f"{api}{path}", data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "User-Agent": "cloudbrid-agent",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")[:500]
        print(f"API {method} {path} 失败 rc={e.code}: {err}", file=sys.stderr)
        raise


def create_issue(token: str, repo: str, card: str, test_ref: str, ac_ref: str,
                 reason: str, actor: str) -> int:
    """创建结构化上报 issue，返回 issue number。"""
    title = f"[test-ac-error] {card} 测试/AC 语义有误（{ac_ref}）"
    body = (
        f"## 测试/AC 语义有误上报（AC-18 正向上报通道）\n\n"
        f"- **卡**：`{card}`\n"
        f"- **引用测试**：`{test_ref}`\n"
        f"- **引用 AC**：`{ac_ref}`\n"
        f"- **上报者**：`{actor}`\n"
        f"- **上报时间**：{now_iso()}\n\n"
        f"### 问题描述\n{reason}\n\n"
        f"### 影响与处置\n"
        f"- 裁决前该卡相关合并暂停（防错误测试放行实现）\n"
        f"- owner 请在 TTL {TTL_HOURS}h 内裁决：\n"
        f"  - `/test-adopt` — 确认测试有误，接受修复方案\n"
        f"  - `/test-reject` — 驳回（测试正确，实现须符合现有测试）\n"
        f"  - `/test-comment <内容>` — 补充信息\n"
        f"- TTL 无裁决 → dead-man 提醒 + 终态=expired（维持暂停）\n\n"
        f"---\n"
        f"*本 issue 由 agent 经 escalate-test-issue.py 自动创建（W2-C4 / AC-18）。"
        f"与 g060 防篡改阻断互补：本通道是"发现错误"的合法上报，非篡改测试。*"
    )
    status, data = gh_api(token, f"/repos/{repo}/issues", "POST", {
        "title": title,
        "body": body,
        "labels": ["test-ac-error", f"card:{card}"],
    })
    if status not in (200, 201):
        print(f"创建 issue 失败 rc={status}: {data}", file=sys.stderr)
        sys.exit(2)
    number = data.get("number", 0)
    print(f"已创建上报 issue #{number}（{repo}）")
    return number


def resolve_issue(token: str, repo: str, issue: int, owner: str, final_dir: str) -> int:
    """读取 issue 评论，解析 owner 裁决指令，写终态。"""
    try:
        iss, _ = gh_api(token, f"/repos/{repo}/issues/{issue}")
    except Exception:
        print(f"错误：无法读取 issue #{issue}", file=sys.stderr)
        return 2

    title = iss.get("title", "")
    if "test-ac-error" not in title:
        print(f"警告：issue #{issue} 标题不含 'test-ac-error'，仍尝试处理", file=sys.stderr)

    final_path = Path(final_dir) / f"{issue}.json"
    final_path.parent.mkdir(parents=True, exist_ok=True)

    # 已落盘则幂等返回
    if final_path.is_file():
        existing = json.loads(final_path.read_text(encoding="utf-8"))
        print(f"终态已落盘 {final_path}: status={existing.get('status')}")
        return 0

    verdict: str | None = None
    evidence: dict | None = None
    try:
        status, comments = gh_api(token, f"/repos/{repo}/issues/{issue}/comments?per_page=100")
        comments = comments if isinstance(comments, list) else []
    except Exception:
        comments = []

    for c in comments:
        author = (c.get("user") or {}).get("login", "")
        if author != owner:
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
    created_at = iss.get("created_at", "")
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
        print(f"issue #{issue} 尚未裁决且 TTL 未过 → 待决（退出 0，等待下次轮询）")
        return 0

    final = {
        "schema": "test-ac-error-final-state/v1",
        "issue": issue,
        "repo": repo,
        "status": verdict,
        "evidence": evidence,
        "ttl_hours": TTL_HOURS,
        "resolved_at": now_iso(),
    }
    final_path.write_text(json.dumps(final, ensure_ascii=False, indent=2),
                          encoding="utf-8", newline="\n")
    print(f"终态落盘 {final_path}: status={verdict}")

    if verdict == "expired":
        try:
            gh_api(token, f"/repos/{repo}/issues/{issue}/comments", "POST", {
                "body": (
                    f"@${owner} 测试/AC 错误上报 TTL {TTL_HOURS}h 已过，无裁决 → "
                    f"终态 **expired**（维持合并暂停）。请尽快裁决："
                    f"`/test-adopt` 或 `/test-reject`。\ndead-man 提醒时间：{now_iso()}"
                ),
            })
            print("已追加 dead-man 提醒评论")
        except Exception as e:
            print(f"追加 dead-man 评论失败（终态已落盘，不阻断）: {e}", file=sys.stderr)

    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="escalate-test-issue.py",
                                 description="agent 发现测试/AC 有误时结构化上报")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_create = sub.add_parser("create", help="创建测试/AC 错误上报 issue")
    p_create.add_argument("--card", required=True, help="卡 ID")
    p_create.add_argument("--repo", required=True, help="owner/repo")
    p_create.add_argument("--test-ref", required=True, help="引用测试（文件::用例）")
    p_create.add_argument("--ac-ref", required=True, help="引用 AC 编号")
    p_create.add_argument("--reason", required=True, help="问题描述")
    p_create.add_argument("--actor", default="cloudbrid-agent", help="上报者")

    p_resolve = sub.add_parser("resolve", help="解析 owner 裁决，写终态")
    p_resolve.add_argument("--issue", required=True, type=int)
    p_resolve.add_argument("--repo", required=True)
    p_resolve.add_argument("--owner", default="randypanding")
    p_resolve.add_argument("--final-dir", default=".artest")

    args = ap.parse_args()
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print("错误：GH_TOKEN / GITHUB_TOKEN 未设置", file=sys.stderr)
        return 1

    if args.cmd == "create":
        num = create_issue(token, args.repo, args.card, args.test_ref, args.ac_ref,
                           args.reason, args.actor)
        print(json.dumps({"issue": num, "repo": args.repo, "card": args.card}, ensure_ascii=False))
        return 0
    return resolve_issue(token, args.repo, args.issue, args.owner, args.final_dir)


if __name__ == "__main__":
    sys.exit(main())
