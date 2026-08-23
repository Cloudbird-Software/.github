#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""g060-escalation.py —— g060 裁决闭环（W2-C2 .github#274，ADR-0061 / ISSUE-263 AC-18）

读取 g060-lock.sh 阻断后自动开的 g060-escalation issue 的裁决结果，执行终态：
  - 终态机器可核：采纳（/g060-accept）= 白卷放行该 actor；驳回（/g060-reject）= 维持阻断
  - TTL 内处置 + dead-man 提醒（逾期未决自动提醒 owner）
  - 裁决结果写回 issue comment + 标签（resolved / rejected / expired）

用法：
  python3 scripts/g060-escalation.py \
      --repo Cloudbird-Software/.github \
      [--token $GITHUB_TOKEN] \
      [--ttl-hours 48] [--dry-run]

退出码：0=处理完成 | 2=配置/环境异常
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

G060_LABEL = "g060-escalation"
ACCEPT_CMD_RE = re.compile(r"/g060-accept\b", re.IGNORECASE)
REJECT_CMD_RE = re.compile(r"/g060-reject\b", re.IGNORECASE)
TTL_DEFAULT_HOURS = 48


def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def die(code: int, msg: str) -> None:
    print(("::error::" if os.environ.get("CI") else "FATAL: ") + msg, file=sys.stderr)
    sys.exit(code)


def api(token: str, method: str, url: str, data: dict | None = None) -> tuple[int, dict]:
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(
        url, data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", errors="replace")[:500]
        return e.code, {"_http_error": text}
    except Exception as e:
        return 0, {"_transport_error": str(e)}


def list_open_g060_issues(token: str, repo: str) -> list[dict]:
    code, data = api(token, "GET",
                     f"https://api.github.com/repos/{repo}/issues?"
                     f"labels={G060_LABEL}&state=open&per_page=100")
    if code != 200:
        die(2, f"列出 g060 issue 失败: {code} {data}")
    return [i for i in data if not i.get("pull_request")]


def comment_issue(token: str, repo: str, number: int, body: str) -> None:
    code, _ = api(token, "POST",
                  f"https://api.github.com/repos/{repo}/issues/{number}/comments",
                  {"body": body})
    if code != 201:
        print(f"::warning::评论 issue #{number} 失败: {code}", file=sys.stderr)


def close_issue(token: str, repo: str, number: int) -> None:
    code, _ = api(token, "PATCH",
                  f"https://api.github.com/repos/{repo}/issues/{number}",
                  {"state": "closed"})
    if code != 200:
        print(f"::warning::关闭 issue #{number} 失败: {code}", file=sys.stderr)


def add_labels(token: str, repo: str, number: int, labels: list[str]) -> None:
    api(token, "POST",
        f"https://api.github.com/repos/{repo}/issues/{number}/labels",
        {"labels": labels})


def process_issue(issue: dict, token: str, repo: str, ttl_hours: int, dry_run: bool) -> str:
    number = issue["number"]
    created = dt.datetime.strptime(issue["created_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
    age_hours = (now_utc() - created).total_seconds() / 3600.0
    actor = re.search(r"actor=(\S+)", issue.get("body") or "")
    actor_name = actor.group(1) if actor else "unknown"

    # 拉取评论
    code, comments = api(token, "GET",
                         f"https://api.github.com/repos/{repo}/issues/{number}/comments?per_page=100")
    if code != 200:
        return f"issue #{number}: 拉取评论失败 {code}"

    verdict = None
    for c in sorted(comments, key=lambda x: x.get("created_at", "")):
        body = c.get("body", "") or ""
        if ACCEPT_CMD_RE.search(body):
            verdict = "accepted"
            break
        if REJECT_CMD_RE.search(body):
            verdict = "rejected"
            break

    if verdict == "accepted":
        msg = (f"**g060 裁决：采纳** ✅\n\n"
               f"actor `{actor_name}` 经 owner 裁决为误判，白名单放行。\n"
               f"本次阻断解除；如需持久豁免请走 C1 更新 CODEOWNERS。")
        if not dry_run:
            comment_issue(token, repo, number, msg)
            add_labels(token, repo, number, ["g060-resolved"])
            close_issue(token, repo, number)
        return f"issue #{number}: accepted actor={actor_name}"

    if verdict == "rejected":
        msg = (f"**g060 裁决：驳回** ❌\n\n"
               f"actor `{actor_name}` 维持阻断，测试路径修改仍被拒绝。")
        if not dry_run:
            comment_issue(token, repo, number, msg)
            add_labels(token, repo, number, ["g060-rejected"])
            close_issue(token, repo, number)
        return f"issue #{number}: rejected actor={actor_name}"

    # 无裁决：TTL 检查
    if age_hours >= ttl_hours:
        msg = (f"**g060 dead-man 提醒** ⏰\n\n"
               f"issue 已开放 {age_hours:.1f}h（TTL={ttl_hours}h），尚未裁决。\n"
               f"actor `{actor_name}` 的阻断仍在生效。请 owner 尽快裁决：\n"
               f"- `/g060-accept` 放行  |  `/g060-reject` 维持阻断")
        if not dry_run:
            comment_issue(token, repo, number, msg)
            add_labels(token, repo, number, ["g060-expired"])
        return f"issue #{number}: dead-man reminder actor={actor_name} age={age_hours:.1f}h"

    return f"issue #{number}: pending actor={actor_name} age={age_hours:.1f}h"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="g060-escalation.py", description="g060 裁决闭环 + dead-man 提醒")
    ap.add_argument("--repo", default="Cloudbird-Software/.github")
    ap.add_argument("--token", default=os.environ.get("GITHUB_TOKEN", ""))
    ap.add_argument("--ttl-hours", type=int, default=TTL_DEFAULT_HOURS)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    if not args.token:
        die(2, "需要 --token 或 GITHUB_TOKEN")

    issues = list_open_g060_issues(args.token, args.repo)
    if not issues:
        print("无开放 g060-escalation issue")
        return 0

    for issue in issues:
        result = process_issue(issue, args.token, args.repo, args.ttl_hours, args.dry_run)
        print(result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
