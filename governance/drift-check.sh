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
# enabled_repositories 同检（ADR-0021）：apply §2 写该字段而 check 不验=修复回路盲区
[[ "$(jq -r .enabled_repositories <<<"$AP")" == "$(jq -r .actions_policy.enabled_repositories "$EXPECTED")" ]] \
  || drift "enabled_repositories=$(jq -r .enabled_repositories <<<"$AP") ≠ expected $(jq -r .actions_policy.enabled_repositories "$EXPECTED")"

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

# ---------- 4. 仓库基线（squash-only / 删分支 / auto-merge，ADR-0029）----------
EXCLUDES=$(jq -c '.repo_baseline.exclude_repos // []' "$EXPECTED")
# auto-merge 期望值（ADR-0029）：repo setting 不受 ruleset 管，静默漂移 = 自动合并
# 全链路静默失效。字段读不到（null——如凭据缺 administration 读权限的 fine-grained
# PAT）与 false 同判漂移——fail-closed：检测器失明不得伪装成无漂移
WANT_AUTO_MERGE=$(jq -r '.repo_baseline.allow_auto_merge // true' "$EXPECTED")
# 全分页拉取 org 仓库（评审项：单页 100 时 >100 仓的 org 会漏检后续仓库）；
# fail-closed：清单拉取失败/非数组/为空时 REPOS 为空会让后续全部循环静默跳过、
# 检测整体假绿——此处显式中止，检测器失明不得伪装成无漂移
REPOS_TMP=$(mktemp)
PAGE=1
while :; do
  CHUNK=$(api "https://api.github.com/orgs/$ORG/repos?per_page=100&page=$PAGE")
  if ! jq -e 'type == "array"' <<<"$CHUNK" >/dev/null 2>&1; then
    echo "FATAL: org 仓库清单拉取失败（$(jq -r '.message // "非数组"' <<<"$CHUNK" 2>/dev/null || echo 传输失败)），无法检测" >&2
    exit 2
  fi
  N=$(jq 'length' <<<"$CHUNK")
  [[ "$N" -eq 0 ]] && break
  jq -r '.[].name' <<<"$CHUNK" >>"$REPOS_TMP"
  [[ "$N" -lt 100 ]] && break
  PAGE=$((PAGE+1))
done
REPOS=$(cat "$REPOS_TMP")
rm -f "$REPOS_TMP"
if [[ -z "$REPOS" ]]; then
  echo "FATAL: org 仓库清单为空（org 至少应含本治理仓）——清单异常，无法检测" >&2
  exit 2
fi
for r in $REPOS; do
  jq -e --arg r "$r" '($r as $x | . | index($x)) != null' <<<"$EXCLUDES" >/dev/null && continue
  RR=$(api "https://api.github.com/repos/$ORG/$r")
  bad=""
  [[ "$(jq -r .allow_squash_merge <<<"$RR")" == "true" ]] || bad="$bad squash-off"
  [[ "$(jq -r .allow_merge_commit <<<"$RR")" == "false" ]] || bad="$bad merge-commit-on"
  [[ "$(jq -r .allow_rebase_merge <<<"$RR")" == "false" ]] || bad="$bad rebase-on"
  [[ "$(jq -r .delete_branch_on_merge <<<"$RR")" == "true" ]] || bad="$bad keep-branch"
  [[ "$(jq -r .allow_auto_merge <<<"$RR")" == "$WANT_AUTO_MERGE" ]] || bad="$bad auto-merge-off(got=$(jq -r .allow_auto_merge <<<"$RR"))"
  [[ -z "$bad" ]] && ok "repo baseline '$r'" || drift "repo '$r' 基线异常:$bad"
done

# ---------- 5. 必需 org secrets（只查存在性，值不可读）----------
SECRETS=$(api "https://api.github.com/orgs/$ORG/actions/secrets")
for s in $(jq -r '.org_secrets_required[]' "$EXPECTED"); do
  jq -e --arg s "$s" 'any(.secrets[]; .name == $s)' <<<"$SECRETS" >/dev/null \
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
    [[ "$want_vis" == "public" ]] || drift "repo '$r' 申报 visibility=$want_vis 违反全仓公开政策（ADR-0020）"
    ok "REPOS map '$r'"
  done < <(jq -r '.repos[] | select(.status=="active") | "\(.name)\t\(.visibility)"' <<<"$REPO_MAP")
  # 7b/7c. 线上全量仓合并遍历（每仓一次 API）：
  #   7b. 必须在图中申报（任何 status 均可，未申报即漂移）
  #   7c. 全仓公开政策（ADR-0020）：private 即漂移——不依赖申报完整性（未申报仓
  #       同样受检）；exempt 状态只豁免治理基线（repo_baseline），不豁免可见性
  for r in $REPOS; do
    jq -e --arg r "$r" '[.repos[].name] | index($r) != null' <<<"$REPO_MAP" >/dev/null \
      || drift "线上仓 '$r' 未在 governance/REPOS.yaml 申报（补申报，或标 exempt 注明原因）"
    VR=$(api "https://api.github.com/repos/$ORG/$r")
    [[ "$(jq -r 'if .private then "private" else "public" end' <<<"$VR")" == "public" ]] \
      || drift "repo '$r' 为 private，违反全仓公开政策（ADR-0020 改回 public，或新 ADR 推翻政策）"
  done
else
  echo "SKIP  REPOS.yaml 校验（环境缺 python3+pyyaml；GitHub runner 自带）"
fi

# ---------- 8. 直推检测（GM-2 破玻璃监控）----------
# flows.governance_change.policy_effective 之后，受治仓默认分支上的非 PR commit = 漂移。
# 唯一权威判据 = List pull requests associated with commit API（红队 #17-I + PR 评审项）：
#   不做消息后缀预筛——"(#N)" 后缀可伪造，直推挂个假后缀即可绕过预筛被报 clean；
#   窗口内每个 commit 都经关联 PR API 复核（真有关联 PR=合法形态放行，无=直推）。
# fail-closed（评审项）：关联 PR 查询本身失败（限流/权限/传输）= 无法验证 = 判漂移报错，
#   绝不静默放行——检测器失明比误报危险。
# 分页（评审项）：commit 列表全分页拉取，第 100 条之后的直推不可漏检；
#   超 MAX_COMMITS 上限时显式报漂移（fail loudly），不静默截断。
# 回填时限：commit 距今 >24h 且仍在直推状态 = 已超破玻璃回填时限（P0 级标记）。
SINCE=$(python3 - <<'EOF'
from datetime import datetime, timezone, timedelta
eff = datetime(2026, 8, 19, tzinfo=timezone.utc)          # policy_effective
lo = datetime.now(timezone.utc) - timedelta(days=7)        # 检测窗口
print(max(eff, lo).strftime("%Y-%m-%dT%H:%M:%SZ"))
EOF
)
NOW_EPOCH=$(date +%s)
MAX_COMMITS=300   # 窗口内单仓 commit 上限：治理仓日常量级为个位数；超限=异常，人工核查
for r in $REPOS; do
  jq -e --arg r "$r" '($r as $x | . | index($x)) != null' <<<"$EXCLUDES" >/dev/null && continue
  # 全分页拉取窗口内 commit（评审项：首页之后不可漏检）
  COMMITS_TMP=$(mktemp)
  TOTAL=0
  PAGE=1
  FETCH_ERR=0
  while :; do
    CHUNK=$(api "https://api.github.com/repos/$ORG/$r/commits?sha=main&since=$SINCE&per_page=100&page=$PAGE")
    if ! jq -e 'type == "array"' <<<"$CHUNK" >/dev/null 2>&1; then
      drift "repo '$r' commit 列表拉取失败，直推检测无法执行（fail-closed）: $(jq -r '.message // "非 JSON 响应"' <<<"$CHUNK" 2>/dev/null || echo 传输失败)"
      FETCH_ERR=1
      break
    fi
    N=$(jq 'length' <<<"$CHUNK")
    [[ "$N" -eq 0 ]] && break
    jq -c '.[] | {sha: .sha, date: (.commit.committer.date | sub("\\.[0-9]+Z$"; "Z"))}' <<<"$CHUNK" >>"$COMMITS_TMP"
    TOTAL=$((TOTAL+N))
    [[ "$N" -lt 100 ]] && break
    PAGE=$((PAGE+1))
  done
  if [[ $FETCH_ERR -eq 1 ]]; then rm -f "$COMMITS_TMP"; continue; fi
  if [[ $TOTAL -gt $MAX_COMMITS ]]; then
    drift "repo '$r' 窗口内 commit 数=$TOTAL 超上限 $MAX_COMMITS——为防静默截断漏检，须人工核查直推或调窗口"
    rm -f "$COMMITS_TMP"
    continue
  fi
  # §8 豁免清单（ADR-0016 附录机制：已经 ADR 追认回填的破玻璃直推——
  # expected-state.json direct_push_exemptions 逐 SHA 登记，事件定性见 ADR-0017；
  # 豁免须有 ADR 背书，不得口头/临时豁免）
  EXEMPT=$(jq -r --arg r "$r" '.direct_push_exemptions[$r] // [] | join(" ")' "$EXPECTED")
  DIRECT_FOUND=0
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    sha=$(jq -r .sha <<<"$row")
    cdate=$(jq -r .date <<<"$row")
    if grep -qF "$sha" <<<"$EXEMPT"; then
      ok "repo '$r' commit ${sha:0:8} 已回填破玻璃直推（§8 豁免清单，ADR-0017）"
      continue
    fi
    # 关联 PR 复核（全 SHA；响应须为数组——error 对象/传输失败均为无法验证）
    PRS=$(api "https://api.github.com/repos/$ORG/$r/commits/$sha/pulls?per_page=5" \
      | jq -r 'if type == "array" then (if length > 0 then "has-pr" else "none" end) else "error" end' 2>/dev/null || echo error)
    if [[ "$PRS" == "error" ]]; then
      drift "repo '$r' commit $sha 的关联 PR 查询失败，无法验证直推（fail-closed：限流/权限/传输故障不得静默放行）"
      DIRECT_FOUND=1
      continue
    fi
    if [[ "$PRS" == "none" ]]; then
      AGE=$(( NOW_EPOCH - $(date -u -d "$cdate" +%s) ))
      if [[ $AGE -gt 86400 ]]; then
        drift "repo '$r' 存在非 PR 直推 commit: ${sha:0:8}（已超 24h 回填时限=${AGE}s——P0：立即回填 ADR+PR，见 flows.governance_change）"
      else
        drift "repo '$r' 存在非 PR 直推 commit: ${sha:0:8}（破玻璃须 24h 内回填 ADR+PR，见 flows.governance_change）"
      fi
      DIRECT_FOUND=1
    fi
  done <"$COMMITS_TMP"
  rm -f "$COMMITS_TMP"
  [[ $DIRECT_FOUND -eq 0 ]] && ok "no-direct-push '$r' (since $SINCE, $TOTAL commits)"
done

# ---------- 9. vcs_admin 唯一性（ADR-0010：admin 全系统唯 owner）----------
# org 全部受治仓的 admin 数量必须 == 1 且为 owner；任何多出的 admin = P0 漂移
OWNER_LOGIN="${OWNER_LOGIN:-randypanding}"
for r in $REPOS; do
  jq -e --arg r "$r" '($r as $x | . | index($x)) != null' <<<"$EXCLUDES" >/dev/null && continue
  # 单次拉取全分页（>100 协作者时防漏——CodeRabbit #13）；ADMINS/COUNT 同源派生
  ADMIN_TMP=$(mktemp)
  PAGE=1
  while :; do
    CHUNK=$(api "https://api.github.com/repos/$ORG/$r/collaborators?permission=admin&per_page=100&page=$PAGE")
    N=$(jq 'length' <<<"$CHUNK")
    [[ "$N" -eq 0 ]] && break
    jq -c '.' <<<"$CHUNK" >>"$ADMIN_TMP"
    [[ "$N" -lt 100 ]] && break
    PAGE=$((PAGE+1))
  done
  ADMIN_DATA=$(jq -s 'add // []' "$ADMIN_TMP" 2>/dev/null || echo '[]')
  rm -f "$ADMIN_TMP"
  ADMINS=$(jq -r '[.[] | select(.permissions.admin == true) | .login] | unique | join(",")' <<<"$ADMIN_DATA")
  COUNT=$(jq '[.[] | select(.permissions.admin == true) | .login] | unique | length' <<<"$ADMIN_DATA")
  if [[ "$COUNT" != "1" ]]; then
    drift "repo '$r' admin 数量=$COUNT ($ADMINS)，必须唯一且为 $OWNER_LOGIN（ADR-0010 owner 伪原型不变量）"
  elif [[ "$ADMINS" != "$OWNER_LOGIN" ]]; then
    drift "repo '$r' admin=$ADMINS 非 owner $OWNER_LOGIN（ADR-0010）"
  else
    ok "vcs-admin-unique '$r'"
  fi
done

# ---------- 10. ADR 引用存在性+实体性后验（adr-required 的补充防线，评审项 + RB-D5）----------
# gate.yml 的 adr-required 在 PR 上下文只能做语法检查：agent-registry 是私有仓，
# PR 上下文的 GITHUB_TOKEN 无跨仓读权，注入 org secret 又会向 PR 控制的代码暴露
# 凭据。存在性在本节后验：窗口内合并 PR 的 ADR-NNNN 引用必须真实存在于
# agent-registry/decisions/——伪造/幽灵 ADR 最长 24h 内被检出（与 §8 直推检测
# 同为 post-hoc 防线；C1 的权威人类门禁仍是 owner-only review）。
ADR_RE='ADR-[0-9]{4}'
# 实体性判定（评审项：size 字节数可被空白/注释/填充绕过——100B 阈值挡不住
# RB-D5 意义上的空壳）：拉取被引 ADR 全文做结构校验，H1 编号行、status 行、
# 背景/决策章节齐备且决策节有正文才判"有实质决策记录"；同名多文件（ADR-0011
# 先例）任一满足即通过；读取失败 fail-closed。按编号缓存（同批多 PR 引用同一
# ADR 只拉一次）。
declare -A ADR_VERDICT_CACHE
adr_substantive() { # $1=四位编号 → stdout: missing|ok|shell|unreadable
  local num="$1" matches apath content decoded verdict
  [[ -n "${ADR_VERDICT_CACHE[$num]:-}" ]] && { echo "${ADR_VERDICT_CACHE[$num]}"; return; }
  matches=$(jq -r --arg p "ADR-${num}-" '.[] | select((.name | startswith($p)) and (.type == "file")) | .path' <<<"$ADR_DIR_LISTING")
  if [[ -z "$matches" ]]; then
    verdict="missing"
  else
    verdict="unreadable"
    while IFS= read -r apath; do
      [[ -n "$apath" ]] || continue
      content=$(api "https://api.github.com/repos/$ORG/agent-registry/contents/$apath" | jq -r '.content // empty')
      [[ -z "$content" ]] && continue
      decoded=$(base64 -d <<<"$content" 2>/dev/null || true)
      [[ -z "$decoded" ]] && continue
      if grep -qE "^#[[:space:]]*ADR-${num}([^0-9]|$)" <<<"$decoded" \
         && grep -qE "^-[[:space:]]*(status|状态):[[:space:]]*[^[:space:]]" <<<"$decoded" \
         && grep -qE "^##[[:space:]]*背景" <<<"$decoded" \
         && grep -qE "^##[[:space:]]*决策" <<<"$decoded" \
         && [[ -n "$(sed -n '/^##[[:space:]]*决策/,$p' <<<"$decoded" | tail -n +2 | sed 's/[[:space:]#*-]//g')" ]]; then
        verdict="ok"; break
      fi
      [[ "$verdict" == "unreadable" ]] && verdict="shell"
    done <<<"$matches"
  fi
  ADR_VERDICT_CACHE[$num]="$verdict"
  echo "$verdict"
}
# 独立 7 天窗口（不用 §8 的 SINCE——那是 policy_effective 起算的直推检测窗口，
# 而 ADR 引用后验须覆盖 policy 生效前已合并、引用了伪造 ADR 的 PR）
ADR_SINCE=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)
ADR_DIR_LISTING=$(api "https://api.github.com/repos/$ORG/agent-registry/contents/decisions")
if ! jq -e 'type == "array"' <<<"$ADR_DIR_LISTING" >/dev/null 2>&1; then
  drift "ADR 真源 agent-registry/decisions 读取失败，引用存在性无法后验（fail-closed）: $(jq -r '.message // "非数组"' <<<"$ADR_DIR_LISTING" 2>/dev/null || echo 传输失败)"
else
  ADR_FILES=$(jq -r '.[].name' <<<"$ADR_DIR_LISTING")
  GHOST=0
  for r in $REPOS; do
    jq -e --arg r "$r" '($r as $x | . | index($x)) != null' <<<"$EXCLUDES" >/dev/null && continue
    PRSLIST=$(api "https://api.github.com/repos/$ORG/$r/pulls?state=closed&sort=updated&direction=desc&per_page=30")
    if ! jq -e 'type == "array"' <<<"$PRSLIST" >/dev/null 2>&1; then
      drift "repo '$r' PR 列表拉取失败，ADR 引用后验跳过（fail-closed）"
      GHOST=1
      continue
    fi
    while IFS=$'\t' read -r pnum title body; do
      [[ -n "$pnum" ]] || continue
      for ref in $(printf '%s\n%s\n' "$title" "$body" | grep -oE "$ADR_RE" | sort -u); do
        num="${ref#ADR-}"
        case "$(adr_substantive "$num")" in
          ok) : ;;
          missing)
            drift "repo '$r' PR#$pnum 引用幽灵 ADR ${ref}（agent-registry/decisions/ 无 ADR-${num}-*.md——C1 变更的决策背书不成立）"
            GHOST=1 ;;
          shell)
            drift "repo '$r' PR#$pnum 引用空壳 ADR ${ref}（文件存在但缺实质结构：H1 编号行/status/背景/决策章节须齐备且决策节有正文——红队 RB-D5：字节数填充不再能绕过）"
            GHOST=1 ;;
          unreadable)
            drift "repo '$r' PR#$pnum 引用的 ADR ${ref} 全部同名文件内容读取失败，实体性无法判定（fail-closed）"
            GHOST=1 ;;
        esac
      done
    done < <(jq -r --arg since "$ADR_SINCE" \
      '.[] | select(.merged_at != null and .merged_at >= $since) | [(.number|tostring), (.title // ""), (.body // "")] | @tsv' <<<"$PRSLIST")
  done
  [[ $GHOST -eq 0 ]] && ok "adr-reference-substantive（窗口内合并 PR 的 ADR 引用全部真实且有实质决策结构）"
fi

# ---------- 11. CI-Workflows 大版本指针完整性（供应链，红队 #6-A / ADR-0016 决策 3）----------
# 全部业务仓 gate 引用 CI-Workflows@v1 浮动指针；release-tags ruleset 的 admin bypass
# 使指针可被强移（改变所有业务仓实际执行的 CI 内容）。声明不变式（CI-Workflows README
# 版本策略）：vN 恒指向最高 vN.x.y 的 commit。本节每日校验——admin 强移指针 24h 内检出，
# 不可见通道变可检测。附注 tag 指向 tag 对象（非 commit），须解引用后比对。
# 凭据说明（评审项）：本节与 §1-§10 共用 GOVERNANCE_TOKEN——AGENTS.md 声明的
# drift-check 接口即 "GH_TOKEN=<org admin> bash governance/drift-check.sh"（组织级
# 检测 rulesets/admin/PR 清单本就需要 org 权限，token 已在 job 内）；本节只读公开仓
# CI-Workflows 的 refs，复用不扩大暴露面。工作流仅 schedule/dispatch 于可信 main
# 运行，脚本不受 PR 控制（与 gate.yml 不向 PR 上下文注入 org secret 同一威胁模型）。
# 分页聚合（评审项：单页请求在 tag 数超页容量后会拿旧集合比较出假绿）：
# 逐页拉取并验证每页均为数组，任一页失败即 fail-closed，不用部分结果继续比较。
CW_REFS="[]"
CW_PAGE_FAIL=0
CW_PAGE=1
while :; do
  CW_PAGE=$(api "https://api.github.com/repos/$ORG/CI-Workflows/git/matching-refs/tags/?per_page=100&page=$CW_PAGE")
  if ! jq -e 'type == "array"' <<<"$CW_PAGE" >/dev/null 2>&1; then
    CW_PAGE_FAIL=1
    break
  fi
  CW_REFS=$(jq --argjson acc "$CW_REFS" '. as $p | $acc + $p' <<<"$CW_PAGE")
  [[ "$(jq 'length' <<<"$CW_PAGE")" -lt 100 ]] && break
  CW_PAGE=$((CW_PAGE+1))
  [[ $CW_PAGE -gt 50 ]] && { CW_PAGE_FAIL=1; break; }   # >5000 tag 视为异常，fail-closed
done
if [[ $CW_PAGE_FAIL -ne 0 ]]; then
  drift "CI-Workflows tag refs 分页拉取失败（第 $CW_PAGE 页非数组/超界），大版本指针完整性无法校验（fail-closed，不用部分结果比较）"
else
  # 解引用到 commit SHA（轻量 tag 直指 commit 零额外请求；附注 tag 走 tag 对象一跳）
  cw_commit_sha() { # $1=tag 名（ refs/tags/<name> 去前缀）
    local row obj type sha
    row=$(jq -c --arg r "refs/tags/$1" '.[] | select(.ref == $r)' <<<"$CW_REFS")
    [[ -z "$row" || "$row" == "null" ]] && { echo ""; return; }
    obj=$(jq -c '.object' <<<"$row")
    type=$(jq -r '.type' <<<"$obj"); sha=$(jq -r '.sha' <<<"$obj")
    if [[ "$type" == "tag" ]]; then
      api "https://api.github.com/repos/$ORG/CI-Workflows/git/tags/$sha" | jq -r '.object.sha // empty'
    else
      echo "$sha"
    fi
  }
  CW_NAMES=$(jq -r '.[].ref | sub("^refs/tags/"; "")' <<<"$CW_REFS")
  while IFS= read -r ptr; do
    [[ -n "$ptr" ]] || continue
    N="${ptr#v}"
    HIGHEST=$(grep -E "^v${N}\.[0-9]+\.[0-9]+$" <<<"$CW_NAMES" | sort -V | tail -1)
    PTR_SHA=$(cw_commit_sha "$ptr")
    if [[ -z "$HIGHEST" ]]; then
      drift "CI-Workflows 指针 tag '$ptr' 存在但无任何 v${N}.x.y 具体版本 tag——指针失去锚点（发布流程漏步，README 版本策略）"
    elif [[ -z "$PTR_SHA" ]]; then
      drift "CI-Workflows 指针 '$ptr' 解引用失败（fail-closed）"
    else
      HIGH_SHA=$(cw_commit_sha "$HIGHEST")
      if [[ "$PTR_SHA" == "$HIGH_SHA" ]]; then
        ok "CI-Workflows 指针 '$ptr' == $HIGHEST（${PTR_SHA:0:7}）"
      else
        drift "CI-Workflows 指针 '$ptr'（${PTR_SHA:0:7}）≠ 最高版本 $HIGHEST（${HIGH_SHA:0:7}）——指针被强移或发布流程漏步（不变式 vN==最高 vN.x.y，红队 #6-A）"
      fi
    fi
  done < <(grep -E '^v[0-9]+$' <<<"$CW_NAMES" | sort -V)
  # 必需指针存在性（评审项：删除 v1 ≠ "无指针即不适用"——v1 是全部业务仓 gate 的
  # 供应链入口（REPOS.yaml CI-Workflows role："业务仓引用 @v1"），指针被删=
  # admin bypass 绕过发布流程，必须报漂移。v2+ 指针出现后由上方循环自动纳入
  # 锚点/一致性校验；必需集合当前只声明 v1——v2 落地时随 ADR 扩充此常量。）
  CW_REQUIRED_POINTERS="v1"
  REQ_MISSING=0
  for req in $CW_REQUIRED_POINTERS; do
    if ! grep -qx "$req" <<<"$CW_NAMES"; then
      drift "CI-Workflows 必需大版本指针 '$req' 缺失（业务仓 @v1 供应链入口被删——红队 #6-A：release-tags ruleset admin bypass 通道）"
      REQ_MISSING=1
    fi
  done
  [[ $REQ_MISSING -eq 0 ]] && ok "CI-Workflows 必需大版本指针存在（$CW_REQUIRED_POINTERS）"
fi

# ---------- 12. required check 活体存在性（P1-4，ADR-0034；in-flight 防误报修订）----------
# 文本对账 ≠ 生效验证：ruleset JSON 完全正确的同时，required check 字符串精确
# 匹配可能实际为空（job 改名 / workflow 重构）→ "零 required check" → PR 裸奔。
# 判据：每个受管仓最近更新的至多 3 个已合并/打开 PR 的 head 上，必须存在每个
# required check 名（从 rulesets/*.json 派生——单一真源）的 check run 且
# conclusion 非空；无 PR 活动时退化为默认分支 HEAD。修订（2026-08-20 实测误报
# mutual：三连新开 PR 的 CI 起飞窗口内 gate 尚未报 conclusion，被误判缺失）：
#   - CI 未完结（任一 check run 非 completed）的 head 不构成任何证据——既不算
#     "缺 gate"也不算"有 gate"（防起飞窗口误报）；全部候选 in-flight 时显式
#     SKIP（非漂移，下轮复核）
#   - 关闭未合并的 PR 不采样（废弃实验分支的残缺 CI 不构成证据）
#   - 已完结 CI 的 PR head 缺 gate 仍照报（PR 群体缺 required check = CI 结构性
#     异常或改名注入——T1 的检测对象；main HEAD 仅在无 PR 活动时作退化载体，
#     不作为豁免来源）。查询失败维持 fail-closed。
REQ_CHECKS=$(jq -rs '[.[].rules[]? | select(.type == "required_status_checks")
                      | .parameters.required_status_checks[].context] | unique | .[]' "$DIR"/rulesets/*.json)
[[ -n "$REQ_CHECKS" ]] || { echo "FATAL: rulesets 未声明任何 required check——§12 活体验证失去判据"; exit 2; }
epoch_of() { date -u -d "$1" +%s; }   # ISO8601 → epoch（runner GNU date）
for r in $REPOS; do
  jq -e --arg r "$r" '($r as $x | . | index($x)) != null' <<<"$EXCLUDES" >/dev/null && continue
  PRS_RECENT=$(api "https://api.github.com/repos/$ORG/$r/pulls?state=all&sort=updated&direction=desc&per_page=20")
  if jq -e 'type == "array"' <<<"$PRS_RECENT" >/dev/null 2>&1; then
    HEADS=$(jq -r '[.[] | select(.state == "open" or .merged_at != null) | .head.sha][0:3] | .[]' <<<"$PRS_RECENT")
    if [[ -z "$HEADS" ]]; then
      # 无（已合并/打开的）PR 活动 → 退化为默认分支 HEAD
      DBR=$(api "https://api.github.com/repos/$ORG/$r" | jq -r '.default_branch // "main"')
      HEADS=$(api "https://api.github.com/repos/$ORG/$r/git/ref/heads/$DBR" | jq -r '.object.sha // empty')
      [[ -n "$HEADS" ]] || { drift "repo '$r' 无 PR 活动且默认分支 HEAD 不可读，活体验证无载体（fail-closed）"; continue; }
    fi
  else
    drift "repo '$r' PR 清单拉取失败，required check 活体验证无法执行（fail-closed）"
    continue
  fi
  LIVE_MISS=0; QUERY_FAIL=0; ALL_INFLIGHT=1
  for ctx in $REQ_CHECKS; do
    FOUND=0
    while IFS= read -r sha; do
      [[ -n "$sha" ]] || continue
      CRS=$(api "https://api.github.com/repos/$ORG/$r/commits/$sha/check-runs?per_page=100")
      if ! jq -e 'type == "object" and has("check_runs")' <<<"$CRS" >/dev/null 2>&1; then
        QUERY_FAIL=1; continue
      fi
      TOTAL=$(jq -r '.total_count // 0' <<<"$CRS")
      [[ "$TOTAL" -eq 0 ]] && continue
      # CI 未完结的 head：不构成证据（防起飞窗口误报——gate job 在依赖图末端，
      # 新开 PR 的前几分钟 conclusion 必为 null，此时判"缺失"全是误报）
      jq -e '[.check_runs[] | select(.status != "completed")] | length > 0' <<<"$CRS" >/dev/null 2>&1 && continue
      ALL_INFLIGHT=0
      if jq -e --arg c "$ctx" '[.check_runs[] | select(.name == $c and .conclusion != null)] | length > 0' <<<"$CRS" >/dev/null 2>&1; then
        FOUND=1; break
      fi
    done <<<"$HEADS"
    if [[ $FOUND -ne 1 ]]; then
      if [[ $QUERY_FAIL -eq 1 && $ALL_INFLIGHT -eq 1 ]]; then
        drift "repo '$r' check-runs 查询失败，required check '$ctx' 活体无法验证（fail-closed）"
        LIVE_MISS=1
      elif [[ $ALL_INFLIGHT -eq 1 ]]; then
        echo "SKIP  required-check-live '$r'（候选 head 全部 CI in-flight，本轮无法判定——非漂移，下轮复核）"
      else
        drift "repo '$r' required check '$ctx' 活体缺失：已完结 CI 的候选 head 均无该 check run——job 改名或 workflow 重构？裸奔窗口已开启（ADR-0034 §12）"
        LIVE_MISS=1
      fi
    fi
  done
  [[ $LIVE_MISS -eq 0 && $ALL_INFLIGHT -eq 0 ]] && ok "required-check-live '$r'（required check 在已完结候选 head 上齐备）"
done

# ---------- 13. PR liveness 侦测（P1-4，ADR-0034）----------
# 治理不漂移但流水线死了的三类形态（#81 §6——无人值守下卡死 PR 是最隐形的
# 人类瓶颈）：(a) auto-merge 已设置但 > 阈值无进展；(b) check 停留 queued/
# in_progress 超 > 阈值；(c) PR 创建超阈值且 head 上零 check run（应有而无）。
# 命中即走 GM-1 既有漂移 issue 通道。阈值：expected-state pr_liveness_hours，
# 环境变量 PR_LIVENESS_HOURS 可覆盖（dispatch input liveness_hours 透传，注入测试用）。
LIVENESS_H="${PR_LIVENESS_HOURS:-$(jq -r '.pr_liveness_hours // 4' "$EXPECTED")}"
LIVENESS_S=$(( LIVENESS_H * 3600 ))
STUCK_TOTAL=0
for r in $REPOS; do
  jq -e --arg r "$r" '($r as $x | . | index($x)) != null' <<<"$EXCLUDES" >/dev/null && continue
  OPEN_PRS=$(api "https://api.github.com/repos/$ORG/$r/pulls?state=open&per_page=30")
  jq -e 'type == "array"' <<<"$OPEN_PRS" >/dev/null 2>&1 \
    || { drift "repo '$r' open PR 清单拉取失败，liveness 侦测无法执行（fail-closed）"; continue; }
  STUCK=0
  while IFS=$'\t' read -r pnum created updated headsha has_am; do
    [[ -n "$pnum" ]] || continue
    AGE_UPD=$(( NOW_EPOCH - $(epoch_of "$updated") ))
    AGE_CRE=$(( NOW_EPOCH - $(epoch_of "$created") ))
    if [[ "$has_am" == "true" && $AGE_UPD -gt $LIVENESS_S ]]; then
      drift "repo '$r' PR#$pnum auto-merge 已开启但 ${LIVENESS_H}h 无进展（updated ${AGE_UPD}s 前）——卡死侦测 (a)：查 required check 状态/分支冲突（ADR-0034 §13）"
      STUCK=1; continue
    fi
    CRS=$(api "https://api.github.com/repos/$ORG/$r/commits/$headsha/check-runs?per_page=100")
    if ! jq -e 'type == "object" and has("check_runs")' <<<"$CRS" >/dev/null 2>&1; then
      drift "repo '$r' PR#$pnum head check-runs 查询失败，liveness 无法验证（fail-closed）"
      STUCK=1; continue
    fi
    N_RUNS=$(jq '.check_runs | length' <<<"$CRS")
    if [[ "$N_RUNS" -eq 0 && $AGE_CRE -gt $LIVENESS_S ]]; then
      drift "repo '$r' PR#$pnum 创建 ${AGE_CRE}s 且 head 零 check run——卡死侦测 (c)：应有而无（workflow 未触发/被改名，ADR-0034 §13）"
      STUCK=1; continue
    fi
    # pending 超龄判定（b）：shell 循环做日期运算（jq 无日期运算）
    while IFS=$'\t' read -r crname crstatus crstart; do
      [[ -n "$crname" ]] || continue
      [[ "$crstatus" == "queued" || "$crstatus" == "in_progress" ]] || continue
      [[ -n "$crstart" ]] || continue
      AGE_PEND=$(( NOW_EPOCH - $(epoch_of "$crstart") ))
      if [[ $AGE_PEND -gt $LIVENESS_S ]]; then
        drift "repo '$r' PR#$pnum check '$crname' 停留 $crstatus 已 ${AGE_PEND}s——卡死侦测 (b)：永久 pending（ADR-0034 §13）"
        STUCK=1
      fi
    done < <(jq -r '.check_runs[] | [.name, .status, (.started_at // "")] | @tsv' <<<"$CRS")
  done < <(jq -r '.[] | [(.number|tostring), .created_at, .updated_at, .head.sha, (.auto_merge != null | tostring)] | @tsv' <<<"$OPEN_PRS")
  STUCK_TOTAL=$((STUCK_TOTAL+STUCK))
done
[[ $STUCK_TOTAL -eq 0 ]] && ok "pr-liveness（全部受管仓 open PR 无卡死，阈值 ${LIVENESS_H}h）"

# ---------- 14. merge queue 对账（P2-7，ADR-0042；repo 级 ruleset）----------
# org rulesets API 不支持 merge_queue 规则类型（实测 422）——merge queue 只能以
# repo 级 ruleset 存在（须与 pull_request/required_status_checks 同集）。期望状态
# expected-state.json#merge_queue 声明仓清单与参数；REST 读 repo ruleset 可见
# merge_queue 规则（读支持，写须 GraphQL——apply.sh step6）。
MQ_REPOS=$(jq -r '.merge_queue.repos // [] | .[]' "$EXPECTED")
for r in $MQ_REPOS; do
  RS=$(api "https://api.github.com/repos/$ORG/$r/rulesets?per_page=100")
  if ! jq -e 'type == "array"' <<<"$RS" >/dev/null 2>&1; then
    drift "repo '$r' rulesets 清单拉取失败，merge queue 对账无法执行（fail-closed）"; continue
  fi
  row=$(jq -c --arg n "merge-queue" '.[] | select(.name == $n)' <<<"$RS")
  if [[ -z "$row" || "$row" == "null" ]]; then
    drift "repo '$r' 期望启用 merge queue（ADR-0042）但无 'merge-queue' ruleset"; continue
  fi
  rid=$(jq -r .id <<<"$row")
  detail=$(api "https://api.github.com/repos/$ORG/$r/rulesets/$rid")
  want_p=$(jq -c '.merge_queue.params' "$EXPECTED")
  got_p=$(jq -c '.rules[] | select(.type == "merge_queue") | .parameters
    | {merge_method, check_response_timeout_minutes, max_entries_to_build,
       min_entries_to_merge, max_entries_to_merge, min_entries_to_merge_wait_minutes,
       grouping_strategy}' <<<"$detail")
  [[ "$got_p" == "$want_p" ]] || drift "repo '$r' merge-queue 参数漂移: got=$got_p 期望=$want_p"
  ok "merge-queue '$r'（参数与期望一致）"
done
# 未声明仓不得私自开队列（期望清单外的仓出现 merge-queue ruleset = 漂移）
for r in $REPOS; do
  jq -e --arg r "$r" '.merge_queue.repos // [] | index($r) != null' "$EXPECTED" >/dev/null && continue
  RS=$(api "https://api.github.com/repos/$ORG/$r/rulesets?per_page=100")
  jq -e 'type == "array"' <<<"$RS" >/dev/null 2>&1 || continue
  jq -e '.[] | select(.name == "merge-queue")' <<<"$RS" >/dev/null 2>&1     && drift "repo '$r' 存在未声明的 merge-queue ruleset（expected-state.merge_queue.repos 未列——扩围须修订 ADR-0042）"
done

echo "----------------------------------------"
if [[ $DRIFTS -gt 0 ]]; then
  echo "结果: $DRIFTS 项漂移。修复: bash governance/apply.sh 或手动改回"
  exit 1
fi
echo "结果: 无漂移，组织配置与 governance/ 落盘一致"