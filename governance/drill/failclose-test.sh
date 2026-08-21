#!/usr/bin/env bash
# failclose-test.sh —— 缺席 fail-closed 演练（宪法 §6 / ADR-0069 决策 6 / .github#223 AC-3）
#
# 回归 #180 先例（管家缺席 → dead-man trip → 自动合并停）：模拟"审计包/心跳
# 缺席超时"，断言 AUTO_MERGE_DISABLED 置位路径真的会触发。三层：
#   1) 谓词单测（无网络）：心跳新鲜→不 trip / 缺席超时→trip——注入时间戳断言，
#      与 butler-heartbeat-watch 同一判据（age > deadman_stale_hours）；
#   2) 真源检查（只读）：当前真实心跳新鲜度 + 阈值（butler.yaml），只报告不动状态；
#   3) 置位路径实演（FAILCLOSE_DRY_RUN=0 时）：
#      PATCH org 变量 AUTO_MERGE_DISABLED=true → GET 读回断言 → **立即复位** →
#      GET 读回断言 false，输出置位/复位时戳与窗口时长（记录进演练台账）。
#      复位用 trap 保证异常退出也尝试——真置位不复位=打断线上自动合并（不可留）。
#      端点勘误与 deadman-trip.sh 一致：POST 须打集合端点 /actions/variables。
# 凭据不足时默认 FAILCLOSE_DRY_RUN=1：只输出"将要置位"的判定与精确 API 调用
# 作为证据，不动真变量（不打断线上自动合并）。
# 用法: [FAILCLOSE_DRY_RUN=1|0] [FAILCLOSE_STALE_HOURS=N] bash failclose-test.sh
# 退出码: 0=演练通过（含 dry-run 断言通过）| 1=断言失败 | 2=infra（API 不可达等）
set -uo pipefail

ORG="${DRILL_ORG:-Cloudbird-Software}"
CB=AUTO_MERGE_DISABLED
DRY_RUN="${FAILCLOSE_DRY_RUN:-1}"
THRESH_H="${FAILCLOSE_STALE_HOURS:-}"
# python3 解析（CI 恒有 python3；本地 python3 可能是商店 stub——实测可用性而非 command -v）
pick_py() {
  local c
  for c in "${PYTHON:-}" python3 python py -3; do
    [[ -n "$c" ]] || continue
    "$c" -c 'import sys, yaml; print("ok")' >/dev/null 2>&1 || continue
    echo "$c"; return 0
  done
  return 1
}
PY3="$(pick_py)" || { echo "::error::无可用 python（含 pyyaml）——阈值真源不可读" >&2; exit 2; }
DIR="$(cd "$(dirname "$0")/.." && pwd)"
NOW() { date -u +%FT%TZ; }
INFRA=0
SET_AT=""; RESET_AT=""

ok()   { echo "OK    $1"; }
act()  { echo "ACT   $1"; }
infra(){ echo "INFRA $1" >&2; INFRA=$((INFRA+1)); }
audit(){ echo "AUDIT | butler=failclose-drill | run_id=${GITHUB_RUN_ID:-local} | ts=$(NOW) | outcome=$1 | actions=$2"; }

# ---------- 1) 谓词单测（无网络；注入时间戳——BUTLER_DRY_RUN 类 env 注入模式） ----------
# 谓词与 butler-heartbeat-watch 完全同式: AGE_S > THRESH_H*3600 → trip
trip_if_stale() { # $1=last_success_epoch $2=threshold_hours → echo trip|no-trip
  local age=$(( $(date -u +%s) - $1 ))
  if (( age > $2 * 3600 )); then echo "trip"; else echo "no-trip"; fi
}
predicate_selftest() {
  local pass=0 fail=0
  # 新鲜心跳（30 分钟前）→ 不 trip
  r=$(trip_if_stale "$(( $(date -u +%s) - 1800 ))" "${THRESH_H:-3}")
  [[ "$r" == "no-trip" ]] && { ok "谓词: 心跳 30min 前且阈值 ${THRESH_H:-3}h → no-trip"; pass=$((pass+1)); } \
    || { echo "::error::谓词失败: 新鲜心跳被判 $r"; fail=$((fail+1)); }
  # 缺席超时（365 天前）→ trip（模拟审计包/心跳缺席超时）
  r=$(trip_if_stale "$(( $(date -u +%s) - 31536000 ))" "${THRESH_H:-3}")
  [[ "$r" == "trip" ]] && { ok "谓词: 心跳缺席 365d > 阈值 ${THRESH_H:-3}h → trip（缺席即停判定在）"; pass=$((pass+1)); } \
    || { echo "::error::谓词失败: 缺席超时被判 $r——fail-closed 判定缺失"; fail=$((fail+1)); }
  # 边界: 恰好等于阈值 → 不 trip（严格大于才停，与 heartbeat-watch 一致）
  r=$(trip_if_stale "$(( $(date -u +%s) - $(( ${THRESH_H:-3} * 3600 )) ))" "${THRESH_H:-3}")
  [[ "$r" == "no-trip" ]] && { ok "谓词: 恰在阈值=边界（严格>才 trip）"; pass=$((pass+1)); } \
    || { echo "::error::谓词失败: 边界语义漂移"; fail=$((fail+1)); }
  echo "PREDICATE pass=$pass fail=$fail"
  [[ $fail -eq 0 ]]
}

# ---------- 2) 真源检查（只读） ----------
threshold_from_butler() {
  if [[ -z "$THRESH_H" ]]; then
    # 经 stdin 喂文件（本地 Windows python 解析不了 MSYS 路径；CI Linux 同样适用）
    THRESH_H=$("$PY3" -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["thresholds"]["deadman_stale_hours"])' \
      < "$DIR/policy/butler.yaml" | tr -d '\r') || {
      echo "::error::butler.yaml thresholds.deadman_stale_hours 读取失败" >&2; return 2; }
  fi
  [[ "$THRESH_H" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "::error::阈值非数值: $THRESH_H" >&2; return 2; }
}
probe_live_heartbeat() { # 只读：当前真实心跳新鲜度（不动任何状态）
  if [[ -z "${GH_TOKEN:-}" ]]; then
    ok "真实心跳: 无 GH_TOKEN，跳过只读探针（谓词单测已覆盖判定；真置位模式另行强制凭据）"
    return 0
  fi
  local last age
  last=$(gh api "repos/$ORG/.github/actions/workflows/butler-heartbeat.yml/runs?status=success&per_page=1" \
    --jq '.workflow_runs[0].updated_at // empty' 2>/dev/null) || { infra "heartbeat runs 查询失败"; return 0; }
  if [[ -z "$last" ]]; then
    ok "真实心跳: 无成功 run（若长期如此，watch 层会 trip——本演练不动状态）"
  else
    age=$(( ( $(date -u +%s) - $(date -u -d "$last" +%s) ) / 60 ))
    ok "真实心跳: 最近成功 ${age}min 前（阈值 ${THRESH_H}h）——只读探针，无动作"
  fi
}

# ---------- 3) 置位路径实演 ----------
var_get() { gh api "orgs/$ORG/actions/variables/$CB" --jq .value 2>/dev/null || echo "ABSENT"; }
var_set() { # $1=true|false —— 与 deadman-trip.sh 同端点（POST 打集合端点）
  if ! gh api -X PATCH "orgs/$ORG/actions/variables/$CB" -f name="$CB" -f value="$1" >/dev/null 2>&1; then
    gh api -X POST "orgs/$ORG/actions/variables" -f name="$CB" -f value="$1" -f visibility=all >/dev/null 2>&1
  fi
}
reset_trap() { # 异常退出也复位（真置位不可留——宪法 §6 停机须人工确认后人工复位，
  # 但**演练**置位必须在演练内复位并留时戳；此 trap 只兜异常，正常路径下方显式复位）
  if [[ -n "$SET_AT" && -z "$RESET_AT" ]]; then
    var_set false && infra "异常退出兜底复位已执行（详见台账）"
  fi
}
drill_set_reset() {
  if [[ "$DRY_RUN" != "0" ]]; then
    ok "DRY-RUN 演练: 缺席超时谓词已判 trip，**将要执行** 置位: gh api -X PATCH orgs/$ORG/actions/variables/$CB -f name=$CB -f value=true"
    ok "DRY-RUN 证据: 判定输出（上方谓词行）即 fail-closed 触发链的置位前一刻证据；未动真实变量"
    audit dry-run-pass '{"breaker":"would-set","variable":"'"$CB"'"}'
    return 0
  fi
  [[ -n "${GH_TOKEN:-}" ]] || { echo "::error::真置位需 GH_TOKEN（org admin 写变量）" >&2; return 2; }
  trap reset_trap EXIT
  act "实演置位: $CB=true（$(NOW)）"
  SET_AT=$(NOW)
  var_set true
  local v; v=$(var_get)
  [[ "$v" == "true" ]] || { echo "::error::置位后读回=$v（期望 true）——置位路径失效"; audit real-fail '{"breaker":"set-readback-mismatch"}'; return 1; }
  ok "置位路径验证: 读回=true（缺席即停路径触发，#180 先例回归通过）"
  act "立即复位: $CB=false（$(NOW)）"
  var_set false
  RESET_AT=$(NOW)
  v=$(var_get)
  [[ "$v" == "false" ]] || { echo "::error::复位后读回=$v（期望 false）——必须人工立即复位: gh api -X PATCH orgs/$ORG/actions/variables/$CB -f name=$CB -f value=false" >&2; audit real-fail '{"breaker":"reset-readback-mismatch"}'; return 1; }
  ok "复位验证: 读回=false（复位时戳 $RESET_AT，置位窗口已闭合，线上自动合并不受影响）"
  audit real-pass '{"breaker":"set-and-reset","set_at":"'"$SET_AT"'","reset_at":"'"$RESET_AT"'"}'
  trap - EXIT
}

main() {
  audit running '{"phase":"start","dry_run":"'"$DRY_RUN"'"}'
  threshold_from_butler || exit 2 # 阈值先验证后使用（注入值/真源值同一条路径）
  predicate_selftest || { audit predicate-fail '{"phase":"predicate"}'; exit 1; }
  probe_live_heartbeat
  drill_set_reset; rc=$?
  if [[ $INFRA -gt 0 ]]; then audit infra-fail "{\"infra_failures\":$INFRA}"; exit 2; fi
  exit $rc
}
main
