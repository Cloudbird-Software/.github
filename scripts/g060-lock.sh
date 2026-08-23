#!/usr/bin/env bash
# g060-lock.sh —— g060 落地治理仓（ISSUE-263 W2-C2 / ADR-0061 / ADR-0081）
#
# 对 specs/*/suite/** 按 IR 分片锁定；非验证者 APP/owner 改测试 exit 2，
# 并自动开 issue 路由 owner 裁决（终态机器可核 + TTL + dead-man）。
#
# 用法：
#   bash scripts/g060-lock.sh [--pr <number>] [--repo <owner/repo>] \
#                             [--actor <actor>] [--owner <owner>] \
#                             [--verifier <app-slug>] [--base <sha>] [--head <sha>]
# 环境变量：GH_TOKEN / GITHUB_TOKEN（须对目标仓 issues:write + pull_requests:read）
#
# 退出码：0=无锁定路径变更 或 授权身份 | 1=参数错误 | 2=非授权改测试（阻断 + 开 issue）
set -euo pipefail

REPO="${G060_REPO:-${GITHUB_REPOSITORY:-Cloudbird-Software/.github}}"
PR_NUMBER="${G060_PR:-}"
ACTOR="${G060_ACTOR:-${GITHUB_ACTOR:-}}"
OWNER="${G060_OWNER:-randypanding}"
VERIFIER_SLUG="${G060_VERIFIER:-verifier-app}"
BASE_SHA="${G060_BASE:-}"
HEAD_SHA="${G060_HEAD:-}"
DRY_RUN=0

VERIFIER_ACTOR="${VERIFIER_SLUG}[bot]"
IR_CARD="Cloudbird-Software/.github#274"
TTL_HOURS=72

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]
  --pr <number>               PR 编号（与 --base/--head 二选一）
  --repo <owner/repo>         目标仓（默认：$GITHUB_REPOSITORY）
  --actor <actor>             触发者 GitHub login（默认：\$GITHUB_ACTOR）
  --owner <owner>             人类 owner（默认：randypanding）
  --verifier <slug>           验证者 App slug（默认：verifier-app）
  --base <sha>                对比基准 SHA（无 --pr 时使用）
  --head <sha>                对比目标 SHA（无 --pr 时使用）
  --dry-run                   仅报告，不开 issue / 不 exit 2
  -h, --help                  显示本帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --actor) ACTOR="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --verifier) VERIFIER_SLUG="$2"; VERIFIER_ACTOR="${VERIFIER_SLUG}[bot]"; shift 2 ;;
    --base) BASE_SHA="$2"; shift 2 ;;
    --head) HEAD_SHA="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$ACTOR" ]]; then
  echo "错误：--actor 或 \$GITHUB_ACTOR 未设置" >&2; exit 1
fi

is_authorized() {
  [[ "$1" == "$OWNER" || "$1" == "$VERIFIER_ACTOR" ]]
}

# ---------- 收集变更文件 ----------
FILES=()
if [[ -n "$PR_NUMBER" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES+=("$f")
  done < <(gh pr diff "$PR_NUMBER" --repo "$REPO" --name-only 2>/dev/null || true)
elif [[ -n "$BASE_SHA" && -n "$HEAD_SHA" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES+=("$f")
  done < <(gh api "repos/$REPO/compare/$BASE_SHA...$HEAD_SHA" --jq '.files[].filename' 2>/dev/null || true)
else
  # 回退：工作树 diff HEAD
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES+=("$f")
  done < <(git diff --name-only HEAD 2>/dev/null || true)
fi

LOCKED_FILES=()
for f in "${FILES[@]}"; do
  case "$f" in
    specs/*/suite/*) LOCKED_FILES+=("$f") ;;
  esac
done

if [[ ${#LOCKED_FILES[@]} -eq 0 ]]; then
  echo "g060: 未涉及 specs/*/suite/** 变更，放行。"
  exit 0
fi

echo "g060: 检测到 specs/*/suite/** 变更 ${#LOCKED_FILES[@]} 个文件："
printf '  - %s\n' "${LOCKED_FILES[@]}" >&2

if is_authorized "$ACTOR"; then
  echo "g060: 触发者 $ACTOR 为授权身份（owner=$OWNER 或 verifier=$VERIFIER_ACTOR），放行。"
  exit 0
fi

echo "::error::g060: 触发者 $ACTOR 非授权身份，修改了 specs/*/suite/** （ADR-0061 g060 扩展）："
printf '  - %s\n' "${LOCKED_FILES[@]}" >&2

# ---------- 开裁决 issue ----------
PR_URL="${PR_NUMBER:+"https://github.com/${REPO}/pull/${PR_NUMBER}"}"
PR_REF="${PR_URL:-"base=${BASE_SHA} head=${HEAD_SHA}"}"

ISSUE_BODY=$(cat <<EOF
> 由 .github/scripts/g060-lock.sh 自动生成 | ADR-0061 g060 扩展 | 卡：${IR_CARD}

触发者 \`$ACTOR\` 在 ${REPO} 修改了以下按 IR 分片的锁定测试路径：
$(printf '%s\n' "${LOCKED_FILES[@]}" | sed 's/^/- `/; s/$/`/')

关联：${PR_REF}

## 请 owner 裁决（终态机器可核）
- \`/g060-adopt <证据引用>\`：采纳变更（owner 评论即写入终态）。
- \`/g060-reject <证据引用>\`：驳回变更（owner 评论即写入终态）。
- TTL ${TTL_HOURS}h 内无裁决将触发 dead-man 提醒（butler-deadman-trip）。
- 裁决前该卡相关合并暂停（conductor 侧经 state:needs-human 锁卡）。
EOF
)

ISSUE_TITLE="g060 blocked: unauthorized change to specs/*/suite/** by ${ACTOR} on ${REPO}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "::warning::[dry-run] 将开裁决 issue：$ISSUE_TITLE"
  echo "$ISSUE_BODY"
  exit 2
fi

ISSUE_URL=""
if gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body "$ISSUE_BODY" \
   --assignee "$OWNER" --label state:needs-human >/dev/null 2>&1; then
  ISSUE_URL="（state:needs-human 标签已加）"
elif gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body "$ISSUE_BODY" \
   --assignee "$OWNER" >/dev/null 2>&1; then
  ISSUE_URL="（无 state:needs-human 标签）"
else
  echo "::error::g060: 在 ${REPO} 创建裁决 issue 失败（仍 exit 2 阻断）" >&2
fi

echo "::error::g060: 已阻断并开裁决 issue ${ISSUE_URL}，assign 给 $OWNER，TTL ${TTL_HOURS}h" >&2
exit 2
