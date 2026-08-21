#!/usr/bin/env bash
# test-metrics-northstar.sh —— 北极星对互锁归零触发自测（W5-C4 AC-1，ADR-0073 决策 1）
#
# fixture 时间序列→护栏判定→显示层断言（零网络；实现=governance/metrics.py
# northstar 子命令——测试跑真实现不跑影子）。断言面：
#   互锁触发：任一护栏 red → display=0 + zeroed_reasons 标注 + raw 保留（非数据删除）
#   诚实 pending：零分母/数据源未落 → pending 不归零、不冒充 0 也不冒充绿
#   恢复：护栏回绿 → display 恢复 raw
# 用法：bash governance/tests/test-metrics-northstar.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GOV="$(cd "$HERE/.." && pwd)"

PY=""
for c in "${PYTHON:-}" python3 python py -3; do
  [[ -n "$c" ]] || continue
  "$c" -c 'import sys, yaml; print("ok")' >/dev/null 2>&1 || continue
  PY="$c"; break
done
[[ -n "$PY" ]] || { echo "::error::无可用 python（含 pyyaml）"; exit 2; }

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
M="$GOV/metrics.py"
run_case() {  # run_case <名> <输入JSON> → $OUT（stdout JSON）
  local name="$1" input="$2"
  if ! OUT=$("$PY" "$M" northstar --input "$input" 2>"$TMP/err.txt"); then
    fail "$name：metrics.py 退出非零（$(cat "$TMP/err.txt")）"; OUT="{}"; return 1
  fi
}
jget() {  # jget <json> <pyexpr over d>（eval 白名单=本测试内联表达式，无外部输入）
  "$PY" -c "import json,sys;d=json.loads(sys.argv[1]);print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null | tr -d '\r'
}

mkinput() { printf '%s' "$1" >"$TMP/in.json"; }

# --- 基线：全护栏绿 → display=raw，未归零 ---
mkinput '{"zero_touch_merges_7d":12,"escape_rate_sustained":{"current":0,"previous":0},"revert_rate":{"num":0,"denom":12},"drill_red_rate":{"red":4,"denom":4},"false_allow":0}'
run_case "全绿" "$TMP/in.json" && {
  [[ $(jget "$OUT" "d['zero_touch_merges_7d']['display']") == 12 \
     && $(jget "$OUT" "d['zero_touch_merges_7d']['zeroed']") == False \
     && $(jget "$OUT" "d['interlocked_zeroed']") == False ]] \
    && pass "全绿：display=12 未归零" || fail "全绿断言失败：$OUT"
}

# --- 归零触发 1：逃逸持续（双窗>0）→ display=0 + 原因标注 + raw 保留 ---
mkinput '{"zero_touch_merges_7d":12,"escape_rate_sustained":{"current":2,"previous":1},"revert_rate":{"num":0,"denom":12},"drill_red_rate":{"red":4,"denom":4},"false_allow":0}'
run_case "逃逸持续" "$TMP/in.json" && {
  [[ $(jget "$OUT" "d['zero_touch_merges_7d']['display']") == 0 \
     && $(jget "$OUT" "d['zero_touch_merges_7d']['raw']") == 12 \
     && $(jget "$OUT" "d['zero_touch_merges_7d']['zeroed']") == True \
     && $(jget "$OUT" "'escape_rate_sustained' in d['zero_touch_merges_7d']['zeroed_reasons']") == True \
     && $(jget "$OUT" "d['guardrails']['escape_rate_sustained']['status']") == red ]] \
    && pass "逃逸持续：显示归零+原因标注+raw=12 保留（呈现层归零非数据删除）" \
    || fail "逃逸持续断言失败：$OUT"
}

# --- 逃逸单窗>0（未持续）不归零——持续条件是互锁触发边界 ---
mkinput '{"zero_touch_merges_7d":9,"escape_rate_sustained":{"current":1,"previous":0},"revert_rate":{"num":0,"denom":9},"drill_red_rate":{"red":4,"denom":4},"false_allow":0}'
run_case "逃逸单窗" "$TMP/in.json" && {
  [[ $(jget "$OUT" "d['zero_touch_merges_7d']['display']") == 9 \
     && $(jget "$OUT" "d['guardrails']['escape_rate_sustained']['status']") == green ]] \
    && pass "逃逸单窗（未持续）：护栏绿不归零" || fail "逃逸单窗断言失败：$OUT"
}

# --- 归零触发 2：演习红率破线（0.75<1.0——关卡漏检=质量劣化） ---
mkinput '{"zero_touch_merges_7d":12,"escape_rate_sustained":{"current":0,"previous":0},"revert_rate":{"num":0,"denom":12},"drill_red_rate":{"red":3,"denom":4},"false_allow":0}'
run_case "演习红率破线" "$TMP/in.json" && {
  [[ $(jget "$OUT" "d['zero_touch_merges_7d']['display']") == 0 \
     && $(jget "$OUT" "d['zero_touch_merges_7d']['zeroed_reasons'].count('drill_red_rate')") == 1 ]] \
    && pass "演习红率 0.75 破线：显示归零" || fail "演习红率断言失败：$OUT"
}

# --- 归零触发 3：误放行 1 例即破线（一票否决） ---
mkinput '{"zero_touch_merges_7d":12,"escape_rate_sustained":{"current":0,"previous":0},"revert_rate":{"num":0,"denom":12},"drill_red_rate":{"red":4,"denom":4},"false_allow":1}'
run_case "误放行" "$TMP/in.json" && {
  [[ $(jget "$OUT" "d['zero_touch_merges_7d']['display']") == 0 \
     && $(jget "$OUT" "d['guardrails']['false_allow']['status']") == red ]] \
    && pass "误放行 1 例：显示归零（一票即破线）" || fail "误放行断言失败：$OUT"
}

# --- 归零触发 4：回滚率超阈（2/12>5%） ---
mkinput '{"zero_touch_merges_7d":12,"escape_rate_sustained":{"current":0,"previous":0},"revert_rate":{"num":2,"denom":12},"drill_red_rate":{"red":4,"denom":4},"false_allow":0}'
run_case "回滚率超阈" "$TMP/in.json" && {
  [[ $(jget "$OUT" "d['zero_touch_merges_7d']['display']") == 0 \
     && $(jget "$OUT" "d['guardrails']['revert_rate']['status']") == red ]] \
    && pass "回滚率 0.167 超阈：显示归零" || fail "回滚率断言失败：$OUT"
}

# --- 诚实 pending：零分母/数据源未落 → pending 不归零（缺数据≠劣化，决策 7） ---
mkinput '{"zero_touch_merges_7d":7,"escape_rate_sustained":{"current":0,"previous":0},"revert_rate":{"num":0,"denom":0},"drill_red_rate":{"red":0,"denom":0}}'
run_case "零分母周" "$TMP/in.json" && {
  [[ $(jget "$OUT" "d['zero_touch_merges_7d']['display']") == 7 \
     && $(jget "$OUT" "d['interlocked_zeroed']") == False \
     && $(jget "$OUT" "'revert_rate' in d['pending_blind_zones']") == True \
     && $(jget "$OUT" "'drill_red_rate' in d['pending_blind_zones']") == True \
     && $(jget "$OUT" "'holdout_gap' in d['pending_blind_zones']") == True ]] \
    && pass "零分母/未落数据源：pending 盲区可见但不归零" || fail "零分母断言失败：$OUT"
}

# --- 误放行台账不可读 → pending 不冒充 0（fail-closed 呈现） ---
mkinput '{"zero_touch_merges_7d":5,"escape_rate_sustained":{"current":0,"previous":0},"revert_rate":{"num":0,"denom":5},"drill_red_rate":{"red":4,"denom":4}}'
run_case "台账不可读" "$TMP/in.json" && {
  [[ $(jget "$OUT" "d['guardrails']['false_allow']['status']") == pending \
     && $(jget "$OUT" "d['zero_touch_merges_7d']['display']") == 5 ]] \
    && pass "误放行数据缺失：pending（不冒充 0 也不触发归零）" || fail "台账缺失断言失败：$OUT"
}

# --- 零合并周 + 护栏破线：display=0 且 zeroed=True（归零标注仍须给出原因） ---
mkinput '{"zero_touch_merges_7d":0,"escape_rate_sustained":{"current":0,"previous":0},"revert_rate":{"num":0,"denom":0},"drill_red_rate":{"red":1,"denom":4},"false_allow":0}'
run_case "零合并破线周" "$TMP/in.json" && {
  [[ $(jget "$OUT" "d['zero_touch_merges_7d']['display']") == 0 \
     && $(jget "$OUT" "d['zero_touch_merges_7d']['zeroed']") == True \
     && $(jget "$OUT" "d['zero_touch_merges_7d']['raw']") == 0 ]] \
    && pass "零合并周破线：归零标注与原因照给（raw=0 如实）" || fail "零合并破线断言失败：$OUT"
}

# --- JSON 输出 schema：键全集（agent 消费契约，schema v2 一部分） ---
mkinput '{"zero_touch_merges_7d":3,"escape_rate_sustained":{"current":0,"previous":0},"revert_rate":{"num":0,"denom":3},"drill_red_rate":{"red":4,"denom":4},"false_allow":0}'
run_case "schema" "$TMP/in.json" && {
  "$PY" -c "
import json,sys
d=json.loads(sys.argv[1])
ns=d['zero_touch_merges_7d']
assert set(ns)=={'raw','display','zeroed','zeroed_reasons','note'}, ns.keys()
assert set(d)=={'zero_touch_merges_7d','guardrails','interlocked_zeroed','pending_blind_zones'}, d.keys()
assert set(d['guardrails'])=={'escape_rate_sustained','revert_rate','drill_red_rate','false_allow','state_change_leak','holdout_gap'}
assert all(set(g)=={'status','detail'} for g in d['guardrails'].values())
" "$OUT" 2>/dev/null && pass "north_star JSON schema 键全集锁定" || fail "schema 断言失败：$OUT"
}

echo "== test-metrics-northstar: pass=$PASS fail=$FAIL =="
[[ $FAIL -eq 0 ]]
