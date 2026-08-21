#!/usr/bin/env bash
# deadman-trip.sh —— 缺席即停的执法核心（宪法 §6 / ADR-0057 / ADR-0074）
#
# 单一实现，两个入口共用（防双实现漂移，ADR-0074 决策 3）：
#   - .github/workflows/butler-deadman-trip.yml（事件入口：repository_dispatch
#     外部回调 + workflow_dispatch 演习）
#   - .github/workflows/butler-heartbeat-watch.yml（仓内陈旧度兜底：heartbeat
#     成功 run 超 stale 阈值即自动 trip——覆盖"Actions 活着但心跳工作流死了"）
#
# 动作（GOVERNANCE_TOKEN 凭据，由调用方在 env 里提供 GH_TOKEN）：
#   1) 置共用熔断变量 AUTO_MERGE_DISABLED=true（与 cost-check 共用——两套变量=
#      两套复位路径/两套旁路窗口）；2) 撤全部 active 仓 open PR auto-merge；
#   3) P0 issue（label deadman-tripped，幂等去重）。
# 退出码：0=已熔断完毕（=可见信号，调用方按需变红）| 2=infra（变量置位失败等）
# 用法: TRIGGER=<触发来源> SRC=<人类可读来源> [SIM=true|false] bash deadman-trip.sh
set -uo pipefail
ORG="${ORG:-Cloudbird-Software}"
GOV_REPO="$ORG/.github"
CB=AUTO_MERGE_DISABLED
TRIGGER="${TRIGGER:-manual}"
SRC="${SRC:-未知来源}"
SIM="${SIM:-false}"
INFRA=0

ok()   { echo "OK    $1"; }
act()  { echo "ACT   $1"; }
infra(){ echo "INFRA $1" >&2; INFRA=$((INFRA+1)); }

# 审计行（INV-12；与 butler-audit.sh 同格式，但本脚本可能被多种 trigger 调用，
# 单独实现轻量版避免 source 依赖环）
audit_line() { echo "AUDIT | butler=deadman-trip | trigger=$TRIGGER | run_id=${GITHUB_RUN_ID:-local} | repo=${GITHUB_REPOSITORY:-local} | started=$(date -u +%FT%TZ) | outcome=$1 | actions=$2"; }

if [[ -z "${GH_TOKEN:-}" ]]; then
  audit_line infra-fail '{"fatal":"GH_TOKEN missing (CI: org secret GOVERNANCE_TOKEN)"}'
  echo "::error::缺 GH_TOKEN（CI: org secret GOVERNANCE_TOKEN）——trip 无法执行缺席即停（fail-closed 变红）" >&2
  exit 2
fi
audit_line running '{"phase":"start","simulate":"'"$SIM"'","src":"'"$SRC"'"}'

# 1) 置共用熔断变量（PATCH 已有 / 404 时 POST 新建）
#    端点勘误（2026-08-21 首演 run 32481546304 实测）：POST 须打集合端点
#    /actions/variables（不带变量名，带名=404）；value 为字符串（-F 布尔=422）。
if ! gh api -X PATCH "orgs/$ORG/actions/variables/$CB" -f name="$CB" -f value=true >/dev/null 2>&1; then
  if ! gh api -X POST "orgs/$ORG/actions/variables" -f name="$CB" -f value=true -f visibility=all >/dev/null 2>&1; then
    infra "org 变量 $CB 置位失败（PATCH/POST 均败）"
  fi
fi
act "熔断变量 $CB=true 已置位（与 cost-check 共用——宪法 §6 缺席即停；$SRC）"

# 2) 撤全部 active 仓 open PR 的 auto-merge（模式同 cost-check.sh strip_all_automerge）
STRIPPED=0
REPOS=$(python3 -c 'import yaml; repos=yaml.safe_load(open("governance/REPOS.yaml", encoding="utf-8"))["repos"]; print(" ".join(r["name"] for r in repos if r.get("status") == "active"))' | tr -d '\r') || REPOS=""
if [[ -z "$REPOS" ]]; then
  infra "REPOS.yaml 解析失败——auto-merge 撤销清单不可得"
fi
for r in $REPOS; do
  while IFS=$'\t' read -r n am; do
    [[ "${am:-}" == "1" ]] || continue
    if gh api -X DELETE "repos/$ORG/$r/pulls/$n/auto-merge" >/dev/null 2>&1; then
      act "撤 auto-merge: $r#$n"
      STRIPPED=$((STRIPPED+1))
    fi
  done < <(gh pr list --repo "$ORG/$r" --state open --limit 200 \
    --json number,autoMergeRequest \
    --jq '.[] | [.number, (if .autoMergeRequest != null then "1" else "0" end)] | @tsv' 2>/dev/null)
done
ok "auto-merge 撤销完成：$STRIPPED 个 PR"

# 3) P0 issue（label deadman-tripped，幂等去重；同日已评论不重复——防回调重放灌水）
gh label create deadman-tripped --repo "$GOV_REPO" \
  --description "dead-man trip 缺席即停标记（勿手工使用）" --color b60205 >/dev/null 2>&1 || true
EXISTING=$(gh issue list --repo "$GOV_REPO" --state open --label deadman-tripped \
  --json number --jq '.[0].number' 2>/dev/null)
TODAY=$(date -u +%F)
BODY="P0：dead-man 心跳缺席即停已触发（宪法 §6；$SRC，运行 $(date -u +%FT%TZ)）。

- 已执行：org 变量 \`$CB\`=true（与 cost-check 共用熔断变量）；active 仓 open PR 的 auto-merge 已撤销（$STRIPPED 个）。
- 效果：agent 派发与 automerge 前置检查将拒绝启动（AGENTS.md）；auto-fix-limit 每轮机器执法撤销新 enable。
- 信号链（ADR-0074 双层）：butler-heartbeat 每 30min ping 外部 dead-man 服务；仓内 butler-heartbeat-watch 兜底检测陈旧度。

处置（仅 owner 人工，完整 runbook 见 docs/deadman-setup.md）：
1. 排查管家 cron 静默根因（Actions 故障 / workflow 被删改 / token 失效 / 外部服务误报）；
2. 复位：\`gh api -X PATCH orgs/$ORG/actions/variables/$CB -f name=$CB -f value=false\`（或 DELETE 该变量）；
3. 在本 issue 留复位评论后关闭（留痕）。"
if [[ -n "$EXISTING" ]]; then
  LAST=$(gh issue view "$EXISTING" --repo "$GOV_REPO" --json createdAt,comments \
    --jq '[.comments[].createdAt, .createdAt] | max' 2>/dev/null) || LAST=""
  if [[ "$LAST" == "$TODAY"* ]]; then
    ok "P0 已开（#$EXISTING）且今日已评论，跳过重复评论（防灌水）"
  else
    gh issue comment "$EXISTING" --repo "$GOV_REPO" --body "$BODY" >/dev/null 2>&1 || true
    act "P0 已开（#$EXISTING），已评论本次 trip"
  fi
else
  if ! gh issue create --repo "$GOV_REPO" \
    --title "P0 dead-man trip：管家缺席，自动合并已停（$CB=true）" \
    --body "$BODY" --label deadman-tripped >/dev/null 2>&1; then
    infra "P0 issue 开立失败"
  else
    act "P0 issue 已开立（label deadman-tripped）"
  fi
fi

if [[ $INFRA -gt 0 ]]; then
  audit_line infra-fail "{\"breaker\":\"partial\",\"automerge_stripped\":$STRIPPED,\"simulate\":\"$SIM\",\"infra_failures\":$INFRA}"
  exit 2
fi
audit_line tripped "{\"breaker\":\"set\",\"automerge_stripped\":$STRIPPED,\"simulate\":\"$SIM\"}"
exit 0
