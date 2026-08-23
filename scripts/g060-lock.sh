#!/usr/bin/env bash
# g060-lock.sh —— ADR-0061 g060 语义扩展至治理仓（ISSUE-263 W2-C2）
#
# 锁定范围：specs/*/suite/**（按 IR 分片的测试/验收路径）。
# 合法写身份：owner 人类账号 + verifier-app[bot]；其余身份修改 → exit 2，
# 并自动开 issue 路由 owner 裁决（裁决闭环由 scripts/g060-escalation.py 承接）。
#
# 用法：
#   bash scripts/g060-lock.sh [--actor <actor>] [--pr <number>] [--base <ref>]
#                             [--owner <owner>] [--verifier <app-slug>]
#                             [--paths <csv>]
#   环境变量（CI 自动注入优先）：
#     GH_REPO / GITHUB_REPOSITORY, GITHUB_ACTOR, GITHUB_EVENT_PATH,
#     GITHUB_BASE_REF, GH_TOKEN / GITHUB_TOKEN, G060_PATHS
#
# 退出码：0=放行 / 2=阻断（g060 非法修改）/ 1=脚本自身异常

set -euo pipefail

REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
ACTOR="${G060_ACTOR:-${GITHUB_ACTOR:-}}"
OWNER="${G060_OWNER:-randypanding}"
VERIFIER_SLUG="${G060_VERIFIER:-verifier-app}"
VERIFIER_ACTOR="${VERIFIER_SLUG}[bot]"
LOCK_PATTERN='specs/*/suite/*'
IR_CARD="Cloudbird-Software/.github#274"

PR_NUMBER=""
BASE_REF="${GITHUB_BASE_REF:-main}"
HEAD_REF="${GITHUB_HEAD_REF:-HEAD}"
G060_PATHS="${G060_PATHS:-}"
SHOW_HELP=0

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]
  --actor <actor>      触发者 GitHub login（默认：\$GITHUB_ACTOR）
  --pr <number>        PR 编号；未提供时尝试从 \$GITHUB_EVENT_PATH 解析
  --base <ref>         diff base ref（默认：\$GITHUB_BASE_REF / main）
  --head <ref>         diff head ref（默认：\$GITHUB_HEAD_REF / HEAD）
  --paths <csv>        直接传入变更路径（逗号分隔），用于测试/桥接
  --owner <owner>      人类 owner（默认：randypanding）
  --verifier <slug>    验证者 App slug（默认：verifier-app）
  -h, --help           显示本帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --actor) ACTOR="$2"; shift 2 ;;
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --base) BASE_REF="$2"; shift 2 ;;
    --head) HEAD_REF="$2"; shift 2 ;;
    --paths) G060_PATHS="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --verifier) VERIFIER_SLUG="$2"; VERIFIER_ACTOR="${VERIFIER_SLUG}[bot]"; shift 2 ;;
    -h|--help) SHOW_HELP=1; shift ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ $SHOW_HELP -eq 1 ]] && { usage; exit 0; }

if [[ -z "$ACTOR" ]]; then
  echo "错误：无法确定触发者身份（--actor 或 \$GITHUB_ACTOR）" >&2
  exit 1
fi

is_authorized() {
  local actor="$1"
  [[ "$actor" == "$OWNER" || "$actor" == "$VERIFIER_ACTOR" ]]
}

# ---------- 变更文件探测 ----------
# 优先级：--paths/G060_PATHS > --pr > GITHUB_EVENT_PATH > git diff base..head
find_changed_files() {
  if [[ -n "$G060_PATHS" ]]; then
    printf '%s\n' "$G060_PATHS" | tr ',' '\n'
    return
  fi
  local files=""
  if [[ -n "$PR_NUMBER" ]]; then
    files=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json files --jq '.files[].path' 2>/dev/null || true)
  elif [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
    PR_NUMBER=$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)
    if [[ -n "$PR_NUMBER" ]]; then
      files=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json files --jq '.files[].path' 2>/dev/null || true)
    fi
  fi
  if [[ -z "$files" ]]; then
    # 本地/非 PR 场景：用 git diff；尽力拉取 base
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git fetch origin "$BASE_REF" >/dev/null 2>&1 || true
      files=$(git diff --name-only "origin/${BASE_REF}...${HEAD_REF}" 2>/dev/null || true)
    fi
  fi
  printf '%s\n' "$files"
}

matches_lock_pattern() {
  local path="$1"
  # 只匹配 specs/<ir>/suite/ 下任意文件（单层 IR 分片）
  case "$path" in
    specs/*/suite/*) return 0 ;;
    *) return 1 ;;
  esac
}

LOCKED_FILES=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if matches_lock_pattern "$f"; then
    LOCKED_FILES+=("$f")
  fi
done < <(find_changed_files)

if [[ ${#LOCKED_FILES[@]} -eq 0 ]]; then
  echo "g060-lock: 未涉及 specs/*/suite/**，无需锁定检查"
  exit 0
fi

if is_authorized "$ACTOR"; then
  echo "g060-lock: 触发者 $ACTOR 为授权身份（owner/verifier-app），放行以下锁定路径："
  printf '  - %s\n' "${LOCKED_FILES[@]}"
  exit 0
fi

# ---------- 非法修改：开 issue 路由 owner 裁决 ----------
echo "::error::g060-lock: 触发者 $ACTOR 非授权身份，修改了锁定路径："
printf '  - %s\n' "${LOCKED_FILES[@]}" >&2

PR_URL=""
if [[ -n "$PR_NUMBER" ]]; then
  PR_URL="https://github.com/${REPO}/pull/${PR_NUMBER}"
fi

ISSUE_BODY=$(cat <<EOF
> 由 g060-lock.sh 自动生成 | ADR-0061 g060 扩展 | 卡：${IR_CARD}

触发者 \`$ACTOR\` 尝试修改以下按 IR 分片的锁定测试路径，但非 owner / verifier-app 授权身份：
$(printf '%s\n' "${LOCKED_FILES[@]}" | sed 's/^/- `/; s/$/`/')

${PR_URL:+关联 PR：$PR_URL}

## 请 owner 裁决
- \`/g060-adopt <证据引用>\`：采纳变更（终态机器可核）。
- \`/g060-reject <证据引用>\`：驳回变更（终态机器可核）。
- 无裁决且超过 TTL（72h）将触发 dead-man 提醒。

裁决须附带证据引用（file:line 或 PR 行级链接），由 scripts/g060-escalation.py 做机器可核的终态校验。
EOF
)

ISSUE_TITLE="g060 blocked: unauthorized change to specs/*/suite/** by ${ACTOR}"

# 标签仅使用治理标签集中已存在的 state:needs-human；避免依赖可能不存在的 g060 专用标签
if gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body "$ISSUE_BODY" --assignee "$OWNER" --label state:needs-human >/dev/null 2>&1; then
  echo "::error::已创建裁决 issue 并 assign 给 $OWNER"
else
  # 标签不存在时降级为无标签创建
  if gh issue create --repo "$REPO" --title "$ISSUE_TITLE" --body "$ISSUE_BODY" --assignee "$OWNER" >/dev/null 2>&1; then
    echo "::warning::已创建裁决 issue（无 state:needs-human 标签），assign 给 $OWNER" >&2
  else
    echo "::error::g060-lock: 创建裁决 issue 失败" >&2
  fi
fi

exit 2
