#!/usr/bin/env bash
# apply.sh —— 把 governance/ 落盘状态幂等应用到组织（写操作）
#
# 什么时候跑：
#   - drift-check 报漂移后，修复用
#   - 修改 governance/ 文件后，发布用
# 变更按 flows.governance_change 分级走 PR 进入 governance/（C1 须附 ADR），
# 合并后本地跑一次本脚本 = "基础设施即代码"的 apply。
#
# 覆盖范围（红队 #17-H 显式声明：哪些漂移类别本脚本不可修，须人工路径）：
#   可自动修复：§1 rulesets、§2 actions 策略、§3 workflow 权限、
#               §4 code-security 默认、§5 仓库基线（对应 drift-check §1-§4）
#   人工修复（本脚本故意不碰）：
#     §5 org secrets      —— 值不可读/不可由脚本写入，admin 在网页设置
#     §6 GitHub App 权限  —— App 权限无公开写 API，须 App 设置页
#     §7 REPOS.yaml 未申报 —— 数据判断（新仓角色/层级），人工补申报
#     §8 直推 commit      —— 历史事实，只能 24h 内回填 ADR+PR（人工）
#     §9 admin 数量异常   —— 自动移除 admin 属不可逆高危操作，须 owner 手工处置
#
# 失败语义（红队 #18-15：apply 静默失败=检测→修复死循环）：
#   任何步骤 HTTP 非 2xx 或 API 报错 → FAIL 计数 + 结尾汇总，exit 1（loud failure）。
#
# 用法: GH_TOKEN=<org admin token> bash apply.sh
set -uo pipefail

ORG="${ORG:-Cloudbird-Software}"
DIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED="$DIR/expected-state.json"
FAILS=0

api() { curl -sS -H "Authorization: Bearer ${GH_TOKEN:?需要 org admin GH_TOKEN}" \
             -H "Accept: application/vnd.github+json" "$@"; }

# loud-failure 辅助：HTTP 状态码非 2xx 即计 FAIL（幂等脚本重跑安全）
expect_ok() { # $1=描述 $2=http_code
  if [[ "$2" =~ ^2 ]]; then
    echo "  $1: OK (HTTP $2)"
  else
    echo "  $1: FAIL (HTTP $2)" >&2
    FAILS=$((FAILS+1))
  fi
}

echo "==> 1/5 Rulesets（存在则更新，不存在则创建）"
EXISTING=$(api "https://api.github.com/orgs/$ORG/rulesets?per_page=100")
# 前置 GET 参与失败计数（评审项）：清单拉取失败时 EXISTING 为空会静默走
# "创建"分支或全部跳过——违反 loud-failure 契约，此处显式计 FAIL 并跳过本节
if ! jq -e 'type == "array"' <<<"$EXISTING" >/dev/null 2>&1; then
  echo "  FAIL：ruleset 清单拉取失败（$(jq -r '.message // "非数组"' <<<"$EXISTING" 2>/dev/null || echo 传输失败)），跳过 §1" >&2
  FAILS=$((FAILS+1))
  EXISTING='[]'
fi
for f in "$DIR"/rulesets/*.json; do
  name=$(jq -r .name "$f")
  rid=$(jq -r --arg n "$name" '.[] | select(.name == $n) | .id' <<<"$EXISTING" | head -1)
  if [[ -n "$rid" && "$rid" != "null" ]]; then
    code=$(api -o /dev/null -w '%{http_code}' -X PUT \
      "https://api.github.com/orgs/$ORG/rulesets/$rid" -d @"$f")
    expect_ok "ruleset '$name' 更新" "$code"
  else
    resp=$(api -X POST "https://api.github.com/orgs/$ORG/rulesets" -d @"$f")
    if jq -e '.id' >/dev/null 2>&1 <<<"$resp"; then
      echo "  ruleset '$name': created id=$(jq -r .id <<<"$resp")"
    else
      echo "  ruleset '$name': FAIL $(jq -r .message <<<"$resp")" >&2
      FAILS=$((FAILS+1))
    fi
  fi
done

echo "==> 2/5 Actions 允许策略 + 白名单"
code=$(api -o /dev/null -w '%{http_code}' -X PUT "https://api.github.com/orgs/$ORG/actions/permissions" \
  -d '{"enabled": true, "allowed_actions": "selected"}')
expect_ok "actions permissions" "$code"
code=$(api -o /dev/null -w '%{http_code}' -X PUT "https://api.github.com/orgs/$ORG/actions/permissions/selected-actions" \
  -d "$(jq -c '.actions_policy | {github_owned_allowed, verified_allowed, patterns_allowed}' "$EXPECTED")")
expect_ok "selected-actions 白名单" "$code"

echo "==> 3/5 默认 workflow 权限 = 只读"
code=$(api -o /dev/null -w '%{http_code}' -X PUT "https://api.github.com/orgs/$ORG/actions/permissions/workflow" \
  -d "$(jq -c '{default_workflow_permissions: .actions_policy.default_workflow_permissions, can_approve_pull_request_reviews: .actions_policy.default_workflow_permissions_can_approve}' "$EXPECTED")")
expect_ok "default workflow permissions" "$code"

echo "==> 4/5 Code Security 默认应用到新仓库"
CS=$(api "https://api.github.com/orgs/$ORG/code-security/configurations")
if ! jq -e 'type == "array"' <<<"$CS" >/dev/null 2>&1; then
  echo "  FAIL：code security 配置清单拉取失败（$(jq -r '.message // "非数组"' <<<"$CS" 2>/dev/null || echo 传输失败)），跳过 §4" >&2
  FAILS=$((FAILS+1))
  CS='[]'
fi
CSID=$(jq -r --arg n "$(jq -r .code_security.configuration_name "$EXPECTED")" \
  '.[] | select(.name == $n) | .id' <<<"$CS" | head -1)
if [[ -n "$CSID" && "$CSID" != "null" ]]; then
  code=$(api -o /dev/null -w '%{http_code}' -X PUT \
    "https://api.github.com/orgs/$ORG/code-security/configurations/$CSID/defaults" \
    -d "$(jq -c '{default_for_new_repos: .code_security.default_for_new_repos}' "$EXPECTED")")
  expect_ok "code-security config#$CSID 设新仓默认" "$code"
else
  echo "  FAIL：code security 配置不存在，请先在网页创建 'GitHub recommended'" >&2
  FAILS=$((FAILS+1))
fi

echo "==> 5/5 仓库基线（squash-only / 删分支）"
EXCLUDES=$(jq -c '.repo_baseline.exclude_repos // []' "$EXPECTED")
# 全分页拉取 org 仓库（评审项：单页 100 时 >100 仓的 org 会漏掉后续仓库的基线应用）
REPOS_TMP=$(mktemp)
PAGE=1
REPOS_ERR=0
while :; do
  CHUNK=$(api "https://api.github.com/orgs/$ORG/repos?per_page=100&page=$PAGE")
  if ! jq -e 'type == "array"' <<<"$CHUNK" >/dev/null 2>&1; then
    echo "  FAIL：org 仓库清单拉取失败（$(jq -r '.message // "非数组"' <<<"$CHUNK" 2>/dev/null || echo 传输失败)），仓库基线未应用" >&2
    FAILS=$((FAILS+1))
    REPOS_ERR=1
    break
  fi
  N=$(jq 'length' <<<"$CHUNK")
  [[ "$N" -eq 0 ]] && break
  jq -r '.[].name' <<<"$CHUNK" >>"$REPOS_TMP"
  [[ "$N" -lt 100 ]] && break
  PAGE=$((PAGE+1))
done
if [[ $REPOS_ERR -eq 1 ]]; then
  rm -f "$REPOS_TMP"
  REPOS=""
else
  REPOS=$(cat "$REPOS_TMP")
  rm -f "$REPOS_TMP"
  if [[ -z "$REPOS" ]]; then
    echo "  FAIL：org 仓库清单为空（org 至少应含本治理仓）——清单异常，仓库基线未应用" >&2
    FAILS=$((FAILS+1))
  fi
fi
for r in $REPOS; do
  jq -e --arg r "$r" 'index($r) != null' <<<"$EXCLUDES" >/dev/null && { echo "  $r: 跳过（exclude）"; continue; }
  code=$(api -o /dev/null -w '%{http_code}' -X PATCH "https://api.github.com/repos/$ORG/$r" \
    -d '{"allow_squash_merge": true, "allow_merge_commit": false, "allow_rebase_merge": false, "delete_branch_on_merge": true}')
  expect_ok "repo '$r' 基线" "$code"
done

echo "----------------------------------------"
if [[ $FAILS -gt 0 ]]; then
  echo "结果: $FAILS 项 FAIL（见上方 stderr）。部分应用——修复后重跑本脚本（幂等）。验证: bash $DIR/drift-check.sh" >&2
  exit 1
fi
echo "完成。验证: bash $DIR/drift-check.sh"
