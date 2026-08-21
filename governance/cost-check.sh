#!/usr/bin/env bash
# cost-check.sh —— 额度/成本熔断（ADR-0040，P2-8 .github#93）
#
# 当月 Actions 分钟用量（GET /orgs/{org}/settings/billing/usage —— 旧 /settings/billing/actions
# 端点 2025 迁移后 410）vs governance/policy/automation-limits.yaml 声明预算：
#   ≥ warn_pct（80）  → 告警 issue（.github 仓，label cost-budget-warning，同日去重，不硬停）
#   ≥ hardstop_pct（100）→ org Actions 变量 AUTO_MERGE_DISABLED=true + 撤全部 open PR 的
#                        auto-merge + P0 issue（label cost-circuit-breaker）
# 熔断消费点：agent 派发/automerge 前置检查（AGENTS.md 行为契约）+ auto-fix-limit.sh
# 每轮机器执法撤 auto-merge。复位仅人工（owner PATCH/DELETE 变量 + P0 issue 留评论）；
# 本脚本观察到"变量已复位且用量 <100%"后自动关闭 P0 issue（复位留痕=issue 评论历史）。
#
# 用法: GH_TOKEN=<org admin token> bash cost-check.sh
# 注入（T2，不依赖真实超支）: COST_USAGE_MINUTES_OVERRIDE / COST_QUOTA_MINUTES_OVERRIDE /
#   COST_LLM_TOKENS_USED_OVERRIDE / COST_LLM_TOKENS_QUOTA_OVERRIDE / COST_DRY_RUN=1（只报告不写）
# 退出码: 0=未达阈值 | 1=触发告警/熔断（运行变红=可见信号）| 2=基础设施故障（fail-closed）
set -uo pipefail

ORG="${ORG:-Cloudbird-Software}"
DIR="$(cd "$(dirname "$0")" && pwd)"
GOV_REPO="$ORG/.github"
GH="${GH:-gh}"
DRY_RUN="${COST_DRY_RUN:-0}"
INFRA=0
TRIPPED=0
TODAY=$(date -u +%F)

ok()    { echo "OK    $1"; }
act()   { echo "ACT   $1"; }
infra() { echo "INFRA $1" >&2; INFRA=$((INFRA+1)); }

# ---------- AUDIT（ADR-0057，INV-12：宪法 §11 行 3 预算检查的审计条目） ----------
# 本脚本纳入管家唤醒矩阵（cron 6h→1h）。trigger 由 workflow 注入 COST_TRIGGER
# （${{ github.event_name }}：schedule/workflow_dispatch——"谁唤醒"）；头行=running，
# 尾行由 EXIT 陷阱按实际退出码落（0=ok 1=tripped 2=infra-fail）——多出口脚本无需
# 逐出口插行，判定逻辑零改动。duration 由 butler-audit.sh 的审计起点口径计算
# （source 时刻起算，等效脚本内 SECONDS）。
source "$DIR/butler-audit.sh" || { echo "FATAL: butler-audit.sh 加载失败" >&2; exit 2; }
audit_emit cost-check "${COST_TRIGGER:-local}" running '{"phase":"start"}' \
  || infra "AUDIT 头行输出失败（INV-12 完整性受损）"
cost_audit_final() {
  local rc=$1 oc=ok
  [[ "$rc" == "1" ]] && oc=tripped
  [[ "$rc" == "2" ]] && oc=infra-fail
  audit_emit cost-check "${COST_TRIGGER:-local}" "$oc" '{"phase":"done"}' || true
}
trap 'cost_audit_final "$?"' EXIT

[[ -n "${GH_TOKEN:-}" ]] || { echo "FATAL: GH_TOKEN 未设置（需 org admin token）" >&2; exit 2; }

# 数值校验（fail-closed，须在父 shell 调用——子 shell 里 infra 计数会丢失）：
# 非数值 → infra 通道 + 置 0，不参与判定（不 fail-open）
check_num() {  # <varname> <what>
  local __v="__dummy"
  eval "__v=\$${1:?}"
  if [[ "$__v" =~ ^[0-9]+([.][0-9]+)?$ ]]; then return 0; fi
  infra "非数值（$2）: '$__v'——判定输入无效"
  eval "$1=0"
}

# ---------- policy 读取（逐行 KEY=value，无 eval——C1 内容也不执行；tr 去 CR 兼容 Windows python） ----------
POLICY_ENV=$(python3 - "$DIR/policy/automation-limits.yaml" <<'PYEOF' | tr -d '\r'
import sys, yaml
try:
    c = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
    am, lt, cb = c["cost"]["actions_minutes"], c["cost"]["llm_tokens"], c["circuit_breaker"]
    rows = [("AM_QUOTA", am["quota_per_month"]), ("AM_WARN", am["warn_pct"]), ("AM_STOP", am["hardstop_pct"]),
            ("LT_QUOTA", lt["quota_per_month"]), ("LT_WARN", lt["warn_pct"]), ("LT_STOP", lt["hardstop_pct"]),
            ("LT_SOURCE", lt["data_source"]), ("CB_VARIABLE", cb["variable"]), ("CB_RESET_BY", cb["reset_by"])]
    for kk, vv in rows:
        vv = str(vv)
        assert "=" not in vv and "\n" not in vv, f"policy 值含非法字符: {kk}"
        print(f"{kk}={vv}")
except Exception as e:
    sys.exit(f"policy 解析失败: {e}")
PYEOF
) || { echo "FATAL: policy/automation-limits.yaml 解析失败" >&2; exit 2; }
while IFS='=' read -r key val; do declare "$key=$val"; done <<< "$POLICY_ENV"
for v in AM_QUOTA AM_WARN AM_STOP LT_QUOTA LT_WARN LT_STOP LT_SOURCE CB_VARIABLE CB_RESET_BY; do
  [[ -n "${!v:-}" ]] || { echo "FATAL: policy 缺 $v" >&2; exit 2; }
done
# 环境注入优先（T2 注入式测试通道）
AM_QUOTA="${COST_QUOTA_MINUTES_OVERRIDE:-$AM_QUOTA}"
LT_QUOTA="${COST_LLM_TOKENS_QUOTA_OVERRIDE:-$LT_QUOTA}"
check_num AM_QUOTA "Actions 月预算"; check_num AM_WARN "Actions 告警阈值"; check_num AM_STOP "Actions 硬停阈值"
check_num LT_QUOTA "LLM 月预算";     check_num LT_WARN "LLM 告警阈值";     check_num LT_STOP "LLM 硬停阈值"

mutate() {
  if [[ "$DRY_RUN" == "1" ]]; then echo "DRY   (skip) $*"; else "$@"; fi
}
label_ensure() {
  mutate "$GH" label create "$2" --repo "$1" \
    --description "cost-check 熔断标记（勿手工使用）" --color "$3" >/dev/null 2>&1 || true
}
gov_open_issues() {  # <label> → "number<TAB>title" 行
  "$GH" issue list --repo "$GOV_REPO" --state open --label "$1" --limit 100 \
    --json number,title --jq '.[] | "\(.number)\t\(.title)"' 2>/dev/null
}
# 当日已有评论/创建则跳过评论（防 4-6h cron 重复灌水）
issue_silent_today() {  # <number>
  local last
  last=$("$GH" issue view "$1" --repo "$GOV_REPO" --json createdAt,comments \
    --jq '[.comments[].createdAt, .createdAt] | max' 2>/dev/null) || return 1
  [[ "$last" == "$TODAY"* ]]
}
# pct/ge：python -c 经 sys.argv 取值，代码零内嵌引号——兼容 MSYS→Windows 原生 python 的参数传递
pct() {  # <used> <quota> → 百分比（1 位小数）
  python3 -c "import sys; print(round(float(sys.argv[1])*100/float(sys.argv[2]), 1))" "$1" "$2" | tr -d '\r'
}
ge() {  # <a> <b> → True/False
  python3 -c "import sys; print(float(sys.argv[1]) >= float(sys.argv[2]))" "$1" "$2" | tr -d '\r'
}

# ---------- 用量获取 ----------
YEAR=$(date -u +%Y); MONTH=$(date -u +%-m)
if [[ -n "${COST_USAGE_MINUTES_OVERRIDE:-}" ]]; then
  USED_MIN="$COST_USAGE_MINUTES_OVERRIDE"; SRC_MIN="注入"
else
  if ! USED_MIN=$("$GH" api "orgs/$ORG/settings/billing/usage?year=$YEAR&month=$MONTH" \
      --jq '[.usageItems[] | select(.product == "actions" and .unitType == "Minutes") | .quantity] | add // 0' 2>/dev/null); then
    infra "billing usage 拉取失败（orgs/$ORG/settings/billing/usage）——用量不可知，fail-closed 出口 2（不盲置熔断）"
  fi
  USED_MIN="${USED_MIN:-0}"; SRC_MIN="billing API"
fi
check_num USED_MIN "当月 Actions 分钟"
PCT_MIN=$(pct "$USED_MIN" "$AM_QUOTA")
check_num PCT_MIN "Actions 用量百分比"
ok "Actions 分钟（$YEAR-$MONTH）: $USED_MIN / $AM_QUOTA = ${PCT_MIN}%（$SRC_MIN）"

# LLM token：data_source=pending 时仅注入通道可测，不触发真实告警（ADR-0040 决策 6）
PCT_TOK=""
if [[ -n "${COST_LLM_TOKENS_USED_OVERRIDE:-}" ]]; then
  PCT_TOK=$(pct "$COST_LLM_TOKENS_USED_OVERRIDE" "$LT_QUOTA")
  check_num PCT_TOK "LLM 用量百分比"
  ok "LLM token: $COST_LLM_TOKENS_USED_OVERRIDE / $LT_QUOTA = ${PCT_TOK}%（注入——pending 数据源的注入测试通道）"
elif [[ "$LT_SOURCE" == "pending" ]]; then
  ok "LLM token: 数据源 pending（llm-gateway usage 端点未就绪）——仅声明，不参与告警"
fi

# ---------- 熔断当前状态 ----------
BREAKER_SET=0
VERR=$("$GH" api "orgs/$ORG/actions/variables/$CB_VARIABLE" --jq .value 2>&1) || true
if [[ "$VERR" == *"true"* && "$VERR" != *"Not Found"* ]]; then
  BREAKER_SET=1
elif grep -q "Not Found" <<<"$VERR"; then
  :
else
  infra "org 变量 $CB_VARIABLE 读取失败（非 404）——熔断状态未知"
fi

# ---------- tier 判定 ----------
STOP_MIN=$(ge "$PCT_MIN" "$AM_STOP")
WARN_MIN=$(ge "$PCT_MIN" "$AM_WARN")
STOP_TOK=False; WARN_TOK=False
if [[ -n "$PCT_TOK" ]]; then
  STOP_TOK=$(ge "$PCT_TOK" "$LT_STOP")
  WARN_TOK=$(ge "$PCT_TOK" "$LT_WARN")
fi

strip_all_automerge() {  # 硬停执法：撤全部受管仓 open PR 的 auto-merge（不分作者）
  local repos
  repos=$(python3 - "$DIR/REPOS.yaml" <<'PYEOF' | tr -d '\r'
import sys, yaml
try:
    repos = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["repos"]
    print(" ".join(r["name"] for r in repos if r.get("status") == "active"))
except Exception as e:
    sys.exit(f"REPOS.yaml 解析失败: {e}")
PYEOF
) || { infra "REPOS.yaml 解析失败——auto-merge 撤销清单不可得"; return; }
  local r n am
  for r in $repos; do
    while IFS=$'\t' read -r n am; do
      [[ "${am:-}" == "1" ]] || continue
      if mutate "$GH" api -X DELETE "repos/$ORG/$r/pulls/$n/auto-merge" >/dev/null 2>&1; then
        act "熔断执法: 撤销 $r#$n 的 auto-merge"
      fi
    done < <("$GH" pr list --repo "$ORG/$r" --state open --limit 200 \
      --json number,autoMergeRequest \
      --jq '.[] | [.number, (if .autoMergeRequest != null then "1" else "0" end)] | @tsv' 2>/dev/null)
  done
}

set_breaker() {  # PATCH 已有 / POST 新建（404 时）
  if ! mutate "$GH" api -X PATCH "orgs/$ORG/actions/variables/$CB_VARIABLE" \
       -f name="$CB_VARIABLE" -F value=true >/dev/null 2>&1; then
    mutate "$GH" api -X POST "orgs/$ORG/actions/variables/$CB_VARIABLE" \
      -f name="$CB_VARIABLE" -F value=true -f visibility=all >/dev/null 2>&1 \
      || infra "org 变量 $CB_VARIABLE 置位失败"
  fi
}

# ---------- 硬停档（任一指标 ≥100%） ----------
if [[ "$STOP_MIN" == "True" || "$STOP_TOK" == "True" ]]; then
  TRIPPED=1
  act "硬停档触发（Actions=${PCT_MIN}% LLM=${PCT_TOK:--}%）——置 $CB_VARIABLE + 撤 auto-merge + P0"
  set_breaker
  strip_all_automerge
  label_ensure "$GOV_REPO" cost-circuit-breaker b60205
  P0_EXISTING=$(gov_open_issues cost-circuit-breaker | grep -m1 "成本熔断" | cut -f1)
  P0_BODY="P0：额度/成本熔断已置位（ADR-0040，运行 $(date -u +%FT%TZ)）。

- Actions 分钟（$YEAR-$MONTH）: $USED_MIN / $AM_QUOTA = ${PCT_MIN}%（阈值 $AM_STOP%）${PCT_TOK:+
- LLM token: $COST_LLM_TOKENS_USED_OVERRIDE / $LT_QUOTA = ${PCT_TOK}%（阈值 $LT_STOP%，注入通道）}
- 已执行：org 变量 \`$CB_VARIABLE\`=true；全部 open PR 的 auto-merge 已撤销。
- 效果：agent 派发与 automerge 前置检查将拒绝启动（AGENTS.md）；auto-fix-limit 每轮机器执法撤销新 enable。

处置（仅 $CB_RESET_BY，人工）：
1. 排查用量根因（失控循环查 auto-fix-limit 的 issue 历史）；
2. 复位：\`gh api -X PATCH orgs/$ORG/actions/variables/$CB_VARIABLE -f name=$CB_VARIABLE -F value=false\`（或 DELETE 该变量）；
3. 在本 issue 留复位评论（留痕）；cost-check 确认变量复位且用量 <${AM_STOP}% 后自动关闭本 issue。"
  if [[ -n "$P0_EXISTING" ]]; then
    if ! issue_silent_today "$P0_EXISTING"; then
      mutate "$GH" issue comment "$P0_EXISTING" --repo "$GOV_REPO" --body "$P0_BODY" >/dev/null 2>&1 || true
    fi
  else
    mutate "$GH" issue create --repo "$GOV_REPO" \
      --title "P0 成本熔断：Actions 分钟 ${PCT_MIN}% 达硬停档（$CB_VARIABLE 已置位）" \
      --body "$P0_BODY" --label cost-circuit-breaker >/dev/null 2>&1 \
      || infra "P0 issue 开立失败"
  fi
  # 告警档 issue（若开着）升级关闭
  for row in $(gov_open_issues cost-budget-warning | cut -f1); do
    mutate "$GH" issue close "$row" --repo "$GOV_REPO" --comment "用量已达硬停档，本告警升级为熔断 P0 issue。" >/dev/null 2>&1 || true
  done
# ---------- 告警档（≥80%，未达硬停） ----------
elif [[ "$WARN_MIN" == "True" || "$WARN_TOK" == "True" ]]; then
  TRIPPED=1
  label_ensure "$GOV_REPO" cost-budget-warning fbca04
  W_TITLE="成本告警：Actions 分钟 $YEAR-$MONTH 用量 ${PCT_MIN}%（阈值 $AM_WARN%）"
  W_EXISTING=$(gov_open_issues cost-budget-warning | grep -m1 "$YEAR-$MONTH" | cut -f1)
  W_BODY="额度告警（ADR-0040，$(date -u +%FT%TZ)）：Actions 分钟（$YEAR-$MONTH）$USED_MIN / $AM_QUOTA = ${PCT_MIN}%，达 ${AM_WARN}% 告警档——未硬停；达 ${AM_STOP}% 将置 \`$CB_VARIABLE\` 熔断并撤全部 auto-merge。"
  if [[ -n "$W_EXISTING" ]]; then
    if ! issue_silent_today "$W_EXISTING"; then
      mutate "$GH" issue comment "$W_EXISTING" --repo "$GOV_REPO" --body "$W_BODY" >/dev/null 2>&1 || true
    fi
  else
    mutate "$GH" issue create --repo "$GOV_REPO" --title "$W_TITLE" \
      --body "$W_BODY" --label cost-budget-warning >/dev/null 2>&1 || infra "告警 issue 开立失败"
  fi
  act "告警档触发: Actions ${PCT_MIN}% ≥ ${AM_WARN}%（issue 已开/更新）"
else
  # 用量回落：关闭过期的告警 issue（月度滚动或已回落）
  for row in $(gov_open_issues cost-budget-warning | cut -f1); do
    mutate "$GH" issue close "$row" --repo "$GOV_REPO" \
      --comment "用量回落（${PCT_MIN}% < ${AM_WARN}%）或月度滚动——自动关闭；再达阈值会重新开启。" >/dev/null 2>&1 || true
  done
  ok "未达告警档（${PCT_MIN}% < ${AM_WARN}%）"
fi

# ---------- 熔断持续/复位检测（复位仅人工——ADR-0040 决策 4） ----------
if [[ $BREAKER_SET -eq 1 && "$STOP_MIN" != "True" ]]; then
  # 熔断仍在但本轮用量未达硬停（月初滚动或注入回落）：保持置位，P0 issue 提醒（同日去重）
  P0_EXISTING=$(gov_open_issues cost-circuit-breaker | grep -m1 "成本熔断" | cut -f1)
  if [[ -n "$P0_EXISTING" ]] && ! issue_silent_today "$P0_EXISTING"; then
    mutate "$GH" issue comment "$P0_EXISTING" --repo "$GOV_REPO" --body \
      "熔断持续中（$CB_VARIABLE=true，本轮用量 ${PCT_MIN}%）。复位仅人工（$CB_RESET_BY）：PATCH 变量后在本 issue 留评论。" \
      >/dev/null 2>&1 || true
  fi
  act "熔断保持置位（用量 ${PCT_MIN}% < ${AM_STOP}%——不自动复位）"
elif [[ $BREAKER_SET -eq 0 ]]; then
  # 复位确认：变量未置位 + 用量 < 硬停档 + P0 issue 开着 → 自动关闭（人工复位已发生且留痕在评论）
  for row in $(gov_open_issues cost-circuit-breaker | cut -f1); do
    mutate "$GH" issue close "$row" --repo "$GOV_REPO" --comment \
      "复位确认：$CB_VARIABLE 已未置位且用量 ${PCT_MIN}% < ${AM_STOP}%——全流程恢复（agent 派发/automerge 前置检查放行）。自动关闭。" \
      >/dev/null 2>&1 || true
    act "复位确认，关闭 P0 issue #$row"
  done
fi

# ---------- 基础设施故障通道 ----------
if [[ $INFRA -gt 0 ]]; then
  label_ensure "$GOV_REPO" cost-infra 9a6700
  I_EXISTING=$(gov_open_issues cost-infra | grep -m1 "cost-check" | cut -f1)
  I_BODY="cost-check 出现基础设施故障（$INFRA 处，$(date -u +%FT%TZ)）——用量/熔断状态不可知。
fail-closed：本次运行 exit 2 变红；未盲置熔断（假熔断要求人工复位，会停摆整条流水线——ADR-0040 决策 5）。
agent 侧补盲（AGENTS.md）：派发前须确认无未决本 label issue。"
  if [[ -n "$I_EXISTING" ]]; then
    if ! issue_silent_today "$I_EXISTING"; then
      mutate "$GH" issue comment "$I_EXISTING" --repo "$GOV_REPO" --body "$I_BODY" >/dev/null 2>&1 || true
    fi
  else
    mutate "$GH" issue create --repo "$GOV_REPO" --title "cost-check 基础设施故障（用量不可知）" \
      --body "$I_BODY" --label cost-infra >/dev/null 2>&1 || true
  fi
  exit 2
fi

[[ $TRIPPED -eq 1 ]] && exit 1
exit 0
