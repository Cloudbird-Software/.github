#!/usr/bin/env bash
# test-metrics-groups.sh —— 四类指标聚合 + human-brief 渲染自测（W5-C4 AC-2/AC-4，ADR-0073）
#
# fixture 时间序列→p90/签署/率值/成本折算断言（零网络；实现=governance/metrics.py
# eval 子命令）。锁定口径：
#   p90 最近邻秩（10 样本 1..10h → 9h）· 可疑快速签署按 policy 阈值计数
#   误放行/误拒窗过滤（窗内外分离）· 演习 no-surface 不入分母
#   成本声明价折算 + 零 IR 不除零 · 用户结果 pending 不造数 · 渲染含归零标注
# 用法：bash governance/tests/test-metrics-groups.sh
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
jget() { "$PY" -c "import json,sys;d=json.loads(sys.argv[1]);print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null | tr -d '\r'; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
M="$GOV/metrics.py"

cat >"$TMP/in.json" <<'EOF'
{
  "now": "2026-08-22T00:00:00Z",
  "generated_at": "2026-08-22T00:00:00Z",
  "zero_touch_merges_7d": 8,
  "escape_rate_sustained": {"current": 0, "previous": 0},
  "revert_rate": {"num": 0, "denom": 8},
  "drill_red_rate": {"red": 3, "denom": 3},
  "false_allow": 0,
  "sign_durations_seconds": [30, 120, 3600, 7200],
  "sign_in_flight": 2,
  "needs_human_dwell_hours": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  "false_decision_lines": [
    {"date": "2026-08-10T00:00:00Z", "kind": "false-allow"},
    {"date": "2026-08-15T00:00:00Z", "kind": "false-deny"},
    {"date": "2026-05-01T00:00:00Z", "kind": "false-allow"},
    {"date": "2026-08-20T00:00:00Z", "kind": "infra"}
  ],
  "drill_records": [
    {"verdict": "red"}, {"verdict": "red"}, {"verdict": "green"}, {"verdict": "no-surface"}
  ],
  "actions_minutes_month": 100,
  "llm_tokens_month": 50000,
  "ir_count_month": 5,
  "user_metric_files": {"mutual": {"metric_key": "ndcg@5", "value": 0.41, "unit": "", "updated_at": "2026-08-21T00:00:00Z"}}
}
EOF

if ! OUT=$("$PY" "$M" eval --input "$TMP/in.json" --render 2>"$TMP/err.txt"); then
  echo "::error::metrics.py eval 失败：$(cat "$TMP/err.txt")"; exit 2
fi
JSON="${OUT%%====*}"

# --- 注意力会计：p50/p90 最近邻秩 + 可疑快速签署（阈值来自 policy=60s） ---
[[ $(jget "$JSON" "d['metrics']['attention']['sign_p50_seconds']") == 120 \
   && $(jget "$JSON" "d['metrics']['attention']['sign_p90_seconds']") == 7200 \
   && $(jget "$JSON" "d['metrics']['attention']['suspicious_fast_signs']") == 1 \
   && $(jget "$JSON" "d['metrics']['attention']['sign_in_flight']") == 2 ]] \
  && pass "签署 p50=120s/p90=7200s（最近邻秩），可疑快速签署 1 例（30s<60s 阈）" \
  || fail "签署统计断言失败"

# --- needs-human p90：10 样本 1..10h → p90=9h（未破 24h 停摆线） ---
[[ $(jget "$JSON" "d['metrics']['attention']['needs_human_p90_hours']") == 9 \
   && $(jget "$JSON" "d['metrics']['attention']['needs_human_p90_stop']") == False ]] \
  && pass "needs-human p90=9h（最近邻秩），停摆线未破" \
  || fail "needs-human p90 断言失败"

# --- 安全正确性：窗过滤（30 天窗：1 误放行+1 误拒；窗外与 infra 不计）+ 演习分母 ---
[[ $(jget "$JSON" "d['metrics']['security']['false_allow_window']") == 1 \
   && $(jget "$JSON" "d['metrics']['security']['false_deny_window']") == 1 \
   && $(jget "$JSON" "d['metrics']['security']['drill_red']") == 2 \
   && $(jget "$JSON" "d['metrics']['security']['drill_denom']") == 3 ]] \
  && pass "误放行/误拒窗内各 1（窗外与 infra 不计）；演习 2 红/3 可判定（no-surface 不入分母）" \
  || fail "安全正确性断言失败"

# --- 成本：声明价折算 (100*0.008 + 50*0.002)/5 = 0.18 美元/IR ---
[[ $(jget "$JSON" "d['metrics']['cost']['per_ir_usd']") == 0.18 ]] \
  && pass '单 IR $0.18 =（100min×$0.008 + 50k token×$0.002）/ 5 IR' \
  || fail "成本折算断言失败（期望 0.18）"

# --- 用户结果：声明仓 ok、其余 pending；配额空=未立 ---
[[ $(jget "$JSON" "d['metrics']['user_results']['products']['mutual']['status']") == ok \
   && $(jget "$JSON" "d['metrics']['user_results']['products']['mutual']['value']") == 0.41 \
   && $(jget "$JSON" "d['metrics']['user_results']['products']['Shorts_Director']['status']") == pending \
   && $(jget "$JSON" "len(d['metrics']['user_results']['quarterly_hard_quota']['entries'])") == 0 ]] \
  && pass "用户结果：mutual ok（0.41）、未声明仓 pending、配额记录位空=未立" \
  || fail "用户结果断言失败"

# --- 渲染（AC-1 同屏 + §8 人 30 秒）：北极星对在最顶，归零时含标注与 raw 保留 ---
BRIEF="${OUT#*====}"
if grep -q "^## 北极星对" <<<"$OUT" && grep -q "零接触合并数（近 7 天）：\*\*8\*\*" <<<"$BRIEF" \
   && grep -q "## 四类指标" <<<"$BRIEF" && grep -q "可疑快速签署（<60s）1 例" <<<"$BRIEF" \
   && grep -q "needs-human 10 张 p90 停留 9h" <<<"$BRIEF" && grep -q "误放行 1 · 误拒 1" <<<"$BRIEF" \
   && grep -q "单 IR \$0.18" <<<"$BRIEF" && grep -q "季度难测配额：本季未立" <<<"$BRIEF"; then
  pass "human-brief：北极星对置顶+四类指标一行一类+30 秒可读"
else fail "human-brief 渲染断言失败"; fi

# --- 渲染归零形态：护栏破线 → 顶部显示 0+原因+raw 保留（AC-1 呈现层断言） ---
# 路径经 argv 传递（MSYS 自动转换——嵌入代码字符串的 /tmp 路径原生 python 不识别）
"$PY" - "$TMP/in.json" "$TMP/red.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["drill_red_rate"] = {"red": 1, "denom": 3}   # 0.33 < 1.0 破线
d["drill_records"] = [{"verdict": "red"}, {"verdict": "green"}, {"verdict": "green"}]
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PYEOF
OUT2=$("$PY" "$M" eval --input "$TMP/red.json" --render 2>/dev/null) || { echo "::error::red eval 失败"; exit 2; }
JSON2="${OUT2%%====*}"; BRIEF2="${OUT2#*====}"
[[ $(jget "$JSON2" "d['north_star']['zero_touch_merges_7d']['display']") == 0 \
   && $(jget "$JSON2" "d['north_star']['zero_touch_merges_7d']['raw']") == 8 ]] \
  && grep -q "显示归零——护栏破线：drill_red_rate" <<<"$BRIEF2" \
  && grep -q "原始计数 8 保留" <<<"$BRIEF2" \
  && pass "渲染归零形态：0+破线路由标注+raw=8 保留（非数据删除）" \
  || fail "渲染归零形态断言失败"

# --- 诚实口径：零 IR 不除零 · 零签署样本 pending · 零 needs-human p90=None ---
"$PY" - "$TMP/in.json" "$TMP/zero.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d.update({"ir_count_month": 0, "sign_durations_seconds": [], "needs_human_dwell_hours": []})
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PYEOF
OUT3=$("$PY" "$M" eval --input "$TMP/zero.json" 2>/dev/null) || { echo "::error::zero eval 失败"; exit 2; }
[[ $(jget "$OUT3" "d['metrics']['cost']['per_ir_usd']") == None \
   && $(jget "$OUT3" "d['metrics']['attention']['sign_p90_seconds']") == None \
   && $(jget "$OUT3" "d['metrics']['attention']['needs_human_p90_hours']") == None \
   && $(jget "$OUT3" "d['metrics']['attention']['suspicious_fast_signs']") == 0 ]] \
  && pass "零 IR/零样本：null 不除零不出假值（可疑签署 0=真 0 非缺数据）" \
  || fail "零分母诚实口径断言失败"

# --- JSON schema：metrics 四组键全集（agent 消费契约） ---
"$PY" -c "
import json, sys
d = json.loads(sys.argv[1])
ms = d['metrics']
assert set(ms) == {'attention', 'security', 'cost', 'user_results'}, ms.keys()
assert {'sign_count','sign_p50_seconds','sign_p90_seconds','suspicious_fast_signs',
        'needs_human_count','needs_human_p90_hours','needs_human_p90_stop'} <= set(ms['attention'])
assert {'false_allow_window','false_deny_window','drill_red','drill_denom'} <= set(ms['security'])
assert {'per_ir_usd','actions_minutes_month','llm_tokens_month','butler_usd_week','patrol_yield'} <= set(ms['cost'])
assert {'products','quarterly_hard_quota'} == set(ms['user_results'])
assert d['generated_at'] == '2026-08-22T00:00:00Z'
" "$JSON" 2>/dev/null && pass "payload schema v2 键全集锁定" || fail "schema 断言失败"

echo "== test-metrics-groups: pass=$PASS fail=$FAIL =="
[[ $FAIL -eq 0 ]]
