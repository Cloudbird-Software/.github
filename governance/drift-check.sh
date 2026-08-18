#!/usr/bin/env bash
# drift-check.sh —— 治理飘移检测（只读）
#
# 对比 governance/expected-state.json + rulesets/*.json 与线上实际配置。
# 输出 OK/DRIFT 逐项结果；发现任何漂移 exit 1。
#
# 用法: GH_TOKEN=<org admin token> bash drift-check.sh
# CI 中由 .github/workflows/governance-drift.yml 调用，凭据来自 secret GOVERNANCE_TOKEN。
set -uo pipefail

ORG="${ORG:-Cloudbird-Software}"
DIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED="$DIR/expected-state.json"
DRIFTS=0

ok()   { echo "OK    $1"; }
drift(){ echo "DRIFT $1"; DRIFTS=$((DRIFTS+1)); }

api() { curl -sS -H "Authorization: Bearer ${GH_TOKEN:?需要 org admin GH_TOKEN}" \
             -H "Accept: application/vnd.github+json" "$@"; }

[[ -n "${GH_TOKEN:-}" ]] || { echo "FATAL: GH_TOKEN 未设置"; exit 2; }

# ---------- 1. Rulesets：存在性 / enforcement / 核心规则 ----------
ACTUAL_RULESETS=$(api "https://api.github.com/orgs/$ORG/rulesets?per_page=100")
for f in "$DIR"/rulesets/*.json; do
  name=$(jq -r .name "$f")
  want_enf=$(jq -r .enforcement "$f")
  want_rules=$(jq -c '[.rules[].type] | sort' "$f")
  row=$(jq -c --arg n "$name" '.[] | select(.name == $n)' <<<"$ACTUAL_RULESETS")
  if [[ -z "$row" || "$row" == "null" ]]; then
    drift "ruleset '$name' 不存在（定义文件 $f）"; continue
  fi
  got_enf=$(jq -r .enforcement <<<"$row")
  [[ "$got_enf" == "$want_enf" ]] || drift "ruleset '$name' enforcement=$got_enf 期望=$want_enf"
  # 线上完整定义（含 id）对比规则集
  rid=$(jq -r .id <<<"$row")
  detail=$(api "https://api.github.com/orgs/$ORG/rulesets/$rid")
  got_rules=$(jq -c '[.rules[].type] | sort' <<<"$detail")
  [[ "$got_rules" == "$want_rules" ]] || drift "ruleset '$name' 规则集变动: $got_rules 期望=$want_rules"
  # 精确 diff：把线上定义裁剪成与落盘文件同构后比较（剔除 API 自动填充的空字段）
  got_norm=$(jq -S 'del(.rules[].parameters.required_reviewers? | select(. == [])) | {name,target,enforcement,conditions,bypass_actors,rules}' <<<"$detail")
  want_norm=$(jq -S '{name,target,enforcement,conditions,bypass_actors,rules}' "$f")
  [[ "$got_norm" == "$want_norm" ]] \
    || drift "ruleset '$name' 定义与落盘不一致: $(diff <(echo "$want_norm") <(echo "$got_norm") | head -10)"
  ok "ruleset '$name'"
done
EXTRA=$(jq -c --argjson known "$(jq -s '[.[].name]' "$DIR"/rulesets/*.json)" \
  '[.[].name] - $known' <<<"$ACTUAL_RULESETS")
[[ "$EXTRA" == "[]" ]] || drift "线上存在未落盘的 ruleset: $EXTRA（落盘或删除）"

# ---------- 2. Actions 策略 ----------
AP=$(api "https://api.github.com/orgs/$ORG/actions/permissions")
[[ "$(jq -r .allowed_actions <<<"$AP")" == "$(jq -r .actions_policy.allowed_actions "$EXPECTED")" ]] \
  || drift "allowed_actions=$(jq -r .allowed_actions <<<"$AP")"

SA=$(api "https://api.github.com/orgs/$ORG/actions/permissions/selected-actions")
[[ "$(jq -c '{github_owned_allowed, verified_allowed, patterns_allowed}' <<<"$SA")" == \
   "$(jq -c '.actions_policy | {github_owned_allowed, verified_allowed, patterns_allowed}' "$EXPECTED")" ]] \
  || drift "allowed actions 白名单不一致: $(jq -c .patterns_allowed <<<"$SA")"

WF=$(api "https://api.github.com/orgs/$ORG/actions/permissions/workflow")
[[ "$(jq -r .default_workflow_permissions <<<"$WF")" == "$(jq -r .actions_policy.default_workflow_permissions "$EXPECTED")" ]] \
  || drift "default_workflow_permissions=$(jq -r .default_workflow_permissions <<<"$WF")"
ok "actions 策略（含白名单）"

# ---------- 3. Code Security 默认配置 ----------
CS=$(api "https://api.github.com/orgs/$ORG/code-security/configurations")
want_cs=$(jq -r .code_security.configuration_name "$EXPECTED")
csrow=$(jq -c --arg n "$want_cs" '.[] | select(.name == $n)' <<<"$CS")
if [[ -z "$csrow" || "$csrow" == "null" ]]; then
  drift "code security 配置 '$want_cs' 不存在"
else
  # 注意：default_for_new_repos 是只写 API（PUT .../defaults），GitHub 不提供读取端点，
  # 无法只读验证。由 apply.sh 的幂等 PUT 保证，drift-check 只验证配置本体存在。
  ok "code security '$want_cs'（default_for_new_repos 由 apply 保证，API 无读取端点）"
fi

# ---------- 4. 仓库基线（squash-only / 删分支）----------
EXCLUDES=$(jq -c '.repo_baseline.exclude_repos // []' "$EXPECTED")
REPOS=$(api "https://api.github.com/orgs/$ORG/repos?per_page=100" | jq -r '.[].name')
for r in $REPOS; do
  jq -e --arg r "$r" '($r as $x | . | index($x)) != null' <<<"$EXCLUDES" >/dev/null && continue
  RR=$(api "https://api.github.com/repos/$ORG/$r")
  bad=""
  [[ "$(jq -r .allow_squash_merge <<<"$RR")" == "true" ]] || bad="$bad squash-off"
  [[ "$(jq -r .allow_merge_commit <<<"$RR")" == "false" ]] || bad="$bad merge-commit-on"
  [[ "$(jq -r .allow_rebase_merge <<<"$RR")" == "false" ]] || bad="$bad rebase-on"
  [[ "$(jq -r .delete_branch_on_merge <<<"$RR")" == "true" ]] || bad="$bad keep-branch"
  [[ -z "$bad" ]] && ok "repo baseline '$r'" || drift "repo '$r' 基线异常:$bad"
done

# ---------- 5. 必需 org secrets（只查存在性，值不可读）----------
SECRETS=$(api "https://api.github.com/orgs/$ORG/actions/secrets")
for s in $(jq -r '.org_secrets_required[]' "$EXPECTED"); do
  jq -e --arg s "$s" '.secrets[].name == $s' <<<"$SECRETS" >/dev/null \
    && ok "org secret '$s'" || drift "org secret '$s' 缺失"
done

# ---------- 6. GitHub App 权限形状 ----------
APP=$(api "https://api.github.com/apps/$(jq -r .github_app.name "$EXPECTED")")
if [[ "$(jq -r .id <<<"$APP" 2>/dev/null)" == "$(jq -r .github_app.id "$EXPECTED")" ]]; then
  for p in $(jq -r '.github_app.permissions | to_entries[] | "\(.key)=\(.value)"' "$EXPECTED"); do
    k=${p%%=*}; v=${p##*=}
    [[ "$(jq -r .permissions.$k <<<"$APP")" == "$v" ]] || drift "App 权限 $k 变动"
  done
  for p in $(jq -r '.github_app.must_not_have[]' "$EXPECTED"); do
    jq -e --arg p "$p" '.permissions | has($p)' <<<"$APP" >/dev/null \
      && drift "App 出现禁用权限 '$p'（应立即在 App 设置页移除）"
  done
  ok "github app '$(jq -r .github_app.name "$EXPECTED")'"
else
  drift "github app '$(jq -r .github_app.name "$EXPECTED")' 不存在或 id 不符"
fi

# ---------- 7. 组织地图（REPOS.yaml）：存在性 / visibility / 未申报仓 ----------
if python3 -c 'import yaml' 2>/dev/null; then
  REPO_MAP=$(python3 -c 'import yaml,json,sys;print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$DIR/REPOS.yaml")
  # 7a. active 仓：必须存在且 visibility 一致
  while IFS=$'\t' read -r r want_vis; do
    [[ -n "$r" ]] || continue
    RR=$(api "https://api.github.com/repos/$ORG/$r")
    if [[ "$(jq -r 'if .message then .message else "" end' <<<"$RR")" == "Not Found" ]]; then
      drift "REPOS.yaml 申报的 active 仓 '$r' 不存在"; continue
    fi
    got_vis=$(jq -r 'if .private then "private" else "public" end' <<<"$RR")
    [[ "$got_vis" == "$want_vis" ]] || drift "repo '$r' visibility=$got_vis 期望=$want_vis"
    ok "REPOS map '$r'"
  done < <(jq -r '.repos[] | select(.status=="active") | "\(.name)\t\(.visibility)"' <<<"$REPO_MAP")
  # 7b. 线上仓必须在图中申报（任何 status 均可，未申报即漂移）
  for r in $REPOS; do
    jq -e --arg r "$r" '[.repos[].name] | index($r) != null' <<<"$REPO_MAP" >/dev/null \
      || drift "线上仓 '$r' 未在 governance/REPOS.yaml 申报（补申报，或标 exempt 注明原因）"
  done
else
  echo "SKIP  REPOS.yaml 校验（环境缺 python3+pyyaml；GitHub runner 自带）"
fi

echo "----------------------------------------"
if [[ $DRIFTS -gt 0 ]]; then
  echo "结果: $DRIFTS 项漂移。修复: bash governance/apply.sh 或手动改回"
  exit 1
fi
echo "结果: 无漂移，组织配置与 governance/ 落盘一致"
