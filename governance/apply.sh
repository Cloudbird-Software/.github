#!/usr/bin/env bash
# apply.sh —— 把 governance/ 落盘状态幂等应用到组织（写操作）
#
# 什么时候跑：
#   - drift-check 报漂移后，修复用
#   - 修改 governance/ 文件后，发布用
# 变更通过 PR 进入 governance/（main-protection 排除了本仓库，可直接合并），
# 合并后本地跑一次本脚本 = "基础设施即代码"的 apply。
#
# 用法: GH_TOKEN=<org admin token> bash apply.sh
set -euo pipefail

ORG="${ORG:-Cloudbird-Software}"
DIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED="$DIR/expected-state.json"

api() { curl -sS -H "Authorization: Bearer ${GH_TOKEN:?需要 org admin GH_TOKEN}" \
             -H "Accept: application/vnd.github+json" "$@"; }

echo "==> 1/5 Rulesets（存在则更新，不存在则创建）"
EXISTING=$(api "https://api.github.com/orgs/$ORG/rulesets?per_page=100")
for f in "$DIR"/rulesets/*.json; do
  name=$(jq -r .name "$f")
  rid=$(jq -r --arg n "$name" '.[] | select(.name == $n) | .id' <<<"$EXISTING" | head -1)
  if [[ -n "$rid" && "$rid" != "null" ]]; then
    code=$(api -o /dev/null -w '%{http_code}' -X PUT \
      "https://api.github.com/orgs/$ORG/rulesets/$rid" -d @"$f")
    echo "  $name: 更新 (HTTP $code)"
  else
    resp=$(api -X POST "https://api.github.com/orgs/$ORG/rulesets" -d @"$f")
    code_ok=$(jq -r 'if .id then "created id=" + (.id|tostring) else .message end' <<<"$resp")
    echo "  $name: $code_ok"
  fi
done

echo "==> 2/5 Actions 允许策略 + 白名单"
api -o /dev/null -X PUT "https://api.github.com/orgs/$ORG/actions/permissions" \
  -d '{"enabled": true, "allowed_actions": "selected"}'
api -o /dev/null -X PUT "https://api.github.com/orgs/$ORG/actions/permissions/selected-actions" \
  -d "$(jq -c '.actions_policy | {github_owned_allowed, verified_allowed, patterns_allowed}' "$EXPECTED")"
echo "  done"

echo "==> 3/5 默认 workflow 权限 = 只读"
api -o /dev/null -X PUT "https://api.github.com/orgs/$ORG/actions/permissions/workflow" \
  -d "$(jq -c '{default_workflow_permissions: .actions_policy.default_workflow_permissions, can_approve_pull_request_reviews: .actions_policy.default_workflow_permissions_can_approve}' "$EXPECTED")"
echo "  done"

echo "==> 4/5 Code Security 默认应用到新仓库"
CS=$(api "https://api.github.com/orgs/$ORG/code-security/configurations")
CSID=$(jq -r --arg n "$(jq -r .code_security.configuration_name "$EXPECTED")" \
  '.[] | select(.name == $n) | .id' <<<"$CS" | head -1)
if [[ -n "$CSID" && "$CSID" != "null" ]]; then
  code=$(api -o /dev/null -w '%{http_code}' -X PUT \
    "https://api.github.com/orgs/$ORG/code-security/configurations/$CSID/defaults" \
    -d "$(jq -c '{default_for_new_repos: .code_security.default_for_new_repos}' "$EXPECTED")")
  echo "  config#$CSID 设为新仓默认 (HTTP $code)"
else
  echo "  跳过：配置不存在，请先在网页创建 'GitHub recommended'"
fi

echo "==> 5/5 仓库基线（squash-only / 删分支）"
EXCLUDES=$(jq -c '.repo_baseline.exclude_repos // []' "$EXPECTED")
REPOS=$(api "https://api.github.com/orgs/$ORG/repos?per_page=100" | jq -r '.[].name')
for r in $REPOS; do
  jq -e --arg r "$r" 'index($r) != null' <<<"$EXCLUDES" >/dev/null && { echo "  $r: 跳过（exclude）"; continue; }
  api -o /dev/null -X PATCH "https://api.github.com/repos/$ORG/$r" \
    -d '{"allow_squash_merge": true, "allow_merge_commit": false, "allow_rebase_merge": false, "delete_branch_on_merge": true}'
  echo "  $r: 基线已应用"
done

echo
echo "完成。验证: bash $DIR/drift-check.sh"
