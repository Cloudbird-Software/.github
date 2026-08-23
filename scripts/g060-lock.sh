#!/usr/bin/env bash
# g060-lock.sh —— g060 测试分片锁定（ADR-0061 语义扩展 / ISSUE-263 AC-18 / W2-C2 .github#274）
#
# 目标：specs/*/suite/** 按 IR 分片锁定。非 verifier-app/owner 身份修改测试时
# exit 2（阻断），并自动开 issue 路由 owner 裁决。这是"开发 agent 经既有 APP
# 改测试被拒"的机器执行层。
#
# 身份判定（fail-closed）：
#   - 允许： verifier-app[bot]（slug=verifier-app，contents:write 仅测试路径）
#   - 允许： owner 人类账号（org owner，由 G060_OWNER 变量指定）
#   - 拒绝： 其他一切身份（cloudbrid-agent[bot]、fork PAT、未知）→ exit 2
#
# 用法（在 CI 中由 g060-guard.yml 调用，或本地复现）：
#   bash scripts/g060-lock.sh \
#     --actor <actor-login> \
#     --changed-files <file1> [<file2> ...] \
#     [--repo Cloudbird-Software/.github] \
#     [--token $GITHUB_TOKEN]
#
# 退出码：
#   0 = 修改者已授权（verifier-app 或 owner）
#   1 = 无测试路径变更（无需锁定，跳过）
#   2 = 未授权修改测试（阻断）——已自动开 issue 路由裁决
#
# 依赖：bash、curl、jq 或 python3（任一）。
set -euo pipefail

ACTOR=""
REPO="Cloudbird-Software/.github"
TOKEN="${GITHUB_TOKEN:-}"
OWNER="${G060_OWNER:-randypanding}"
VERIFIER_SLUG="${G060_VERIFIER_SLUG:-verifier-app}"
CHANGED_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --actor)        ACTOR="${2:?}"; shift 2 ;;
    --repo)         REPO="${2:?}"; shift 2 ;;
    --token)        TOKEN="${2:?}"; shift 2 ;;
    --owner)        OWNER="${2:?}"; shift 2 ;;
    --verifier-slug) VERIFIER_SLUG="${2:?}"; shift 2 ;;
    --changed-files) shift; while [[ $# -gt 0 && "$1" != --* ]]; do CHANGED_FILES+=("$1"); shift; done ;;
    *) echo "未知参数 $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ACTOR" ]] || { echo "::error::需要 --actor" >&2; exit 2; }

# 测试路径匹配：specs/<ir>/suite/**
is_test_path() {
  [[ "$1" =~ ^specs/[^/]+/suite/ ]]
}

# 是否有测试路径变更
touched_test=0
for f in "${CHANGED_FILES[@]}"; do
  if is_test_path "$f"; then touched_test=1; break; fi
done
if [[ "$touched_test" -eq 0 ]]; then
  echo "无 specs/*/suite/** 变更，g060 跳过"
  exit 1
fi

# 身份判定
actor_lower="$(printf '%s' "$ACTOR" | tr '[:upper:]' '[:lower:]')"
verifier_bot="$(printf '%s' "${VERIFIER_SLUG}[bot]" | tr '[:upper:]' '[:lower:]')"
owner_lower="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"

if [[ "$actor_lower" == "$verifier_bot" || "$actor_lower" == "$owner_lower" ]]; then
  echo "g060 放行：actor=$ACTOR 为授权身份（verifier-app 或 owner）"
  exit 0
fi

# 未授权：阻断 + 自动开 issue
echo "::error::g060 阻断：actor=$ACTOR 未授权修改 specs/*/suite/**（仅 ${VERIFIER_SLUG}[bot] / ${OWNER}）"

if [[ -n "$TOKEN" ]]; then
  title="[g060] 未授权测试修改阻断：actor=${ACTOR}"
  body=$(cat <<EOF
g060 测试分片锁定（ADR-0061 / ISSUE-263 AC-18）触发阻断。

- **actor**: \`${ACTOR}\`
- **变更测试文件**:
$(printf '  - `%s`\n' "${CHANGED_FILES[@]}")
- **允许身份**: \`${VERIFIER_SLUG}[bot]\`、\`${OWNER}\`
- **时间**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

请 owner 裁决：
- **采纳**：actor 确属误判（如新授权身份），请评论 \`/g060-accept <actor>\` 并说明证据引用
- **驳回**：确认未授权修改，请评论 \`/g060-reject\` 并保持阻断

裁决 TTL：48h。逾期未决将触发 dead-man 提醒（见 scripts/g060-escalation.py）。
EOF
)
  # 开 issue（幂等：同标题同日不重复开——由 g060-escalation.py 兜底去重）
  # JSON 组装不依赖 jq（Windows Git Bash 默认无 jq，同 gh-app-token.sh 约定）
  _json="$body" _escaped_body="${_json//\\/\\\\}"
  _escaped_body="${_escaped_body//\"/\\\"}"
  _escaped_body="${_escaped_body//$'\n'/\\n}"
  payload="{\"title\":\"${title//\"/\\\"}\",\"body\":\"${_escaped_body}\",\"labels\":[\"g060-escalation\"]}"
  curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${REPO}/issues" \
    -d "$payload" \
    -o /dev/null -w "issue http=%{http_code}\n" >&2 || true
fi

exit 2
