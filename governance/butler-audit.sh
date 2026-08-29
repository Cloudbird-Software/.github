#!/usr/bin/env bash
# butler-audit.sh —— 管家统一审计行生成器（ADR-0057，W1-C5 .github#168；宪法 §11/INV-12）
#
# INV-12：管家每次运行必须有明确触发器且产出审计条目（谁唤醒/干了什么/花了多少）。
# 本脚本是唯一的审计行形态来源，两种用法：
#   1) CLI（一次性输出一行）:
#        bash butler-audit.sh <butler名> <trigger> <outcome> <动作JSON> [更多JSON...]
#        （兼容省略 outcome 的三参形态：bash butler-audit.sh <名> <trigger> <JSON...> → outcome=ok）
#   2) source（长运行过程多点审计；各 workflow / butler-reconcile.sh / cost-check.sh 用此形态）:
#        source governance/butler-audit.sh
#        audit_emit <butler名> <trigger> <outcome> <动作JSON>...    # 可多次调用
# 输出（stdout + append 到 $GITHUB_STEP_SUMMARY）：
#   AUDIT | butler=<名> | trigger=<触发器> | run_id=<id> | repo=<repo> | started=<ISO> |
#          duration_s=<秒> | outcome=<结果> | actions=<JSON>
#
# 口径说明：
#   - duration：审计起点（BUTLER_AUDIT_T0，epoch 秒）到当前。T0 优先外部注入（跨步骤
#     统计整轮时长）；CI（GITHUB_RUN_STARTED_AT 存在）取 run 开始时刻——等效于用 SECONDS
#     度量整个 workflow 的耗时口径；本地 source 无注入时=source 时刻。
#   - 多个动作 JSON 参数合并为 JSON 数组；JSON 非法时拒绝输出（return 2，绝不输出
#     畸形审计行——宁红勿假），调用方按 infra 故障处置（fail-closed）。
#   - 审计条目只进运行日志与 step summary，刻意不 commit 回 main：管家 commit main 会
#     制造 §8（直推漂移）执法面上的噪音；Actions 运行日志是带 run_id 的不可变第三方
#     台账（ADR-0057 决策 2）。
#   - actions JSON 为 SLI 字段（#98 口径：auto_merge_rate / check_latency / revert_count）
#     预留键位——账本 JSON 状态块由 W1-C3 dashboard 脚本负责，本行结构已兼容（机器可
#     grep '^AUDIT' 提取后 json.loads 尾段）。
#
# 影子双写（IR-0006 W1-B2 / BEH-03，ADR-0103）：audit_emit 在输出 AUDIT 行（原层，
# 只增不改）的同时，按证据 schema v1 追加影子记录到
#   ${BUTLER_SHADOW_FILE:-<本脚本同目录>/butler/shadow-evidence.jsonl}
# （kind=gate / action=butler-<名> / verdict=<outcome>；card 哨兵 .github#0，tenant
# 缺省 cloudbird-internal——env BUTLER_CARD/BUTLER_TENANT 可注入）。影子写入失败
# =fail-closed（return 2，BEH-01：双写不一致必须当场可见）。影子账本由
# butler-reconcile 每 6h 落盘 butler-ledger 分支（governance/evidence_shadow.py
# relink 同款链执法）；其他 workflow 的本地影子随 runner 销毁（丢弃层友海——
# 持久化优先级在 reconcile 主循环）。

_butler_audit_cli=0
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then _butler_audit_cli=1; fi

# ---------- JSON 工具（python3 → python；探测实跑防 Windows 商店 stub；均无则降级不校验） ----------
_BUTLER_PY=""
for _c in python3 python; do
  if command -v "$_c" >/dev/null 2>&1 && "$_c" -c 'print(1)' >/dev/null 2>&1; then
    _BUTLER_PY="$_c"; break
  fi
done
unset _c

_butler_now_epoch() { date -u +%s; }

_butler_iso2epoch() {  # <ISO8601Z> → epoch 秒（解析失败输出空串）
  local iso="$1"
  if [[ -n "$_BUTLER_PY" ]]; then
    "$_BUTLER_PY" -c 'import sys,datetime
try:
    print(int(datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))
except Exception:
    sys.exit(1)' "$iso" 2>/dev/null | tr -d '\r'
  else
    date -u -d "$iso" +%s 2>/dev/null || true
  fi
}

# ---------- 审计起点（source / 首次 CLI 调用时确定） ----------
if [[ -z "${BUTLER_AUDIT_T0:-}" ]]; then
  BUTLER_AUDIT_T0=""
  if [[ -n "${GITHUB_RUN_STARTED_AT:-}" ]]; then
    BUTLER_AUDIT_T0=$(_butler_iso2epoch "$GITHUB_RUN_STARTED_AT")
  fi
  [[ -n "$BUTLER_AUDIT_T0" ]] || BUTLER_AUDIT_T0=$(_butler_now_epoch)
fi
BUTLER_AUDIT_STARTED="${BUTLER_AUDIT_STARTED:-${GITHUB_RUN_STARTED_AT:-$(date -u +%FT%TZ)}}"
readonly BUTLER_AUDIT_T0 BUTLER_AUDIT_STARTED 2>/dev/null || true

# 动作 JSON 合并/校验：多个参数合并为数组；非法 → return 2（不输出畸形行）
_actions_json() {
  local out rc
  if [[ -n "$_BUTLER_PY" ]]; then
    out=$("$_BUTLER_PY" -c 'import json,sys
try:
    objs = [json.loads(a) for a in sys.argv[1:]]
except Exception as e:
    sys.exit(f"illegal JSON: {e}")
print(json.dumps(objs[0] if len(objs) == 1 else objs, ensure_ascii=False))' "$@" 2>&1)
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "FATAL: actions JSON 非法（$out）——拒绝输出畸形审计行" >&2
      return 2
    fi
    printf '%s' "$out" | tr -d '\r'
  elif [[ $# -eq 1 ]]; then
    printf '%s' "$1"   # 无 python 环境：单参直通（CI/本地均有 python，此分支仅极端降级）
  else
    printf '[%s]' "$(printf '%s,' "$@" | sed 's/,$//')"
  fi
}

# 审计行输出（唯一入口）：audit_emit <butler> <trigger> <outcome> <动作JSON>...
audit_emit() {
  [[ $# -ge 4 ]] || { echo "FATAL: audit_emit 用法: audit_emit <butler> <trigger> <outcome> <动作JSON>..." >&2; return 2; }
  local butler="$1" trigger="$2" outcome="$3"; shift 3
  local actions dur line
  actions=$(_actions_json "$@") || return 2
  dur=$(( $(_butler_now_epoch) - BUTLER_AUDIT_T0 ))
  [[ $dur -ge 0 ]] || dur=0
  line="AUDIT | butler=$butler | trigger=$trigger | run_id=${GITHUB_RUN_ID:-local} | repo=${GITHUB_REPOSITORY:-local} | started=$BUTLER_AUDIT_STARTED | duration_s=$dur | outcome=$outcome | actions=$actions"
  echo "$line"
  # step summary（CI）：首次写入带头部标记，便于 owner 免翻日志看全轮审计
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    if [[ ! -f "$GITHUB_STEP_SUMMARY" ]] || ! grep -q '管家审计日志' "$GITHUB_STEP_SUMMARY" 2>/dev/null; then
      printf '## 管家审计日志（AUDIT，INV-12——宪法 §11）\n' >> "$GITHUB_STEP_SUMMARY" || return 0
    fi
    printf '%s\n' "$line" >> "$GITHUB_STEP_SUMMARY" || return 0
  fi
  _shadow_emit "$butler" "$outcome" "$actions" || return 2
}

# 影子双写（BEH-03）：schema v1 判定记录落本地影子账本（链式 hash，写入器独占）
# 注：临时文件清理用显式 rm 不用 RETURN trap——bash 5.2 实测 RETURN trap 会穿透
# 到调用方函数返回（traps 不随函数作用域恢复），set -u 环境下 $evf 越界即炸
# （W2-C3 全脚本单测抓出；trap 版曾在 cost-check set -u 下必现 abort）。
_shadow_emit() {
  [[ -n "$_BUTLER_PY" ]] || return 0   # 无 python 环境：影子无法成链——原层照常（极端降级）
  local butler="$1" outcome="$2" actions="$3"
  local here shadow evf ev_rc=0
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  shadow="${BUTLER_SHADOW_FILE:-$here/butler/shadow-evidence.jsonl}"
  evf="$(mktemp)"
  # BUTLER_SHADOW_PAYLOAD（可选，feishu-sync）：动作明细进影子 payload（≤4KB，
  # evidence_shadow append 执法 INV-06 超限拒写）；缺省=无 payload（原行为不变）
  "$_BUTLER_PY" - "$evf" "$butler" "$outcome" "${BUTLER_SHADOW_PAYLOAD:-}" <<'PYEOF' || ev_rc=$?
import datetime, json, sys
ev = {
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "kind": "gate", "action": f"butler-{sys.argv[2]}", "verdict": sys.argv[3],
    "subject": {"card": __import__("os").environ.get("BUTLER_CARD", "Cloudbird-Software/.github#0"),
                "tenant": __import__("os").environ.get("BUTLER_TENANT", "cloudbird-internal")},
    "actor": {"identity": sys.argv[2], "role": "bot", "model": None},
}
if len(sys.argv) > 4 and sys.argv[4]:
    ev["payload"] = sys.argv[4]
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(ev, ensure_ascii=False))
PYEOF
  if [[ $ev_rc -ne 0 ]]; then
    rm -f "$evf"
    echo "FATAL: 影子事件构造失败" >&2; return 2
  fi
  if ! "$_BUTLER_PY" "$here/evidence_shadow.py" append --file "$shadow" --event-file "$evf" >/dev/null; then
    rm -f "$evf"
    echo "FATAL: 影子账本写入失败（$shadow）——fail-closed（BEH-01 双写不一致当场可见）" >&2
    return 2
  fi
  rm -f "$evf"
}

# ---------- CLI 模式（bash butler-audit.sh ...；source 时不执行） ----------
if [[ $_butler_audit_cli -eq 1 ]]; then
  # 三参形态（省略 outcome）：第 3 参是 JSON 对象/数组字面量 → 补 outcome=ok
  if [[ $# -ge 3 && ( "$3" == \{* || "$3" == \[* ) ]]; then
    set -- "$1" "$2" "ok" "${@:3}"
  fi
  if [[ $# -lt 4 ]]; then
    echo "用法: bash butler-audit.sh <butler名> <trigger> <outcome> <动作JSON> [更多JSON...]" >&2
    echo "  （或三参形态: bash butler-audit.sh <butler名> <trigger> <动作JSON> → outcome=ok）" >&2
    exit 2
  fi
  audit_emit "$@" || exit 2
fi
