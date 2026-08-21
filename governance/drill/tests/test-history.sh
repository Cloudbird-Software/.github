#!/usr/bin/env bash
# test-history.sh —— 台账 append-only + 红率/难度趋势聚合自测（W4-C4 AC-4）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
PYTHON="$(pick_py)" || { echo "::error::无可用 python（含 pyyaml）"; exit 2; }
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
H="$TMP/history.jsonl"
D="$ROOT/drill.py"

rec() { printf '%s' "$1"; }

echo "== 1) record 追加 + append-only 破坏被拒"
"$PYTHON" "$D" record --history "$H" --json '{"ts":"2026-08-22T04:23:11Z","kind":"seed-drill","run_id":"r1","sample_id":"hygiene-gitleaks-aws-key","difficulty":"easy","gate":"org-hygiene","target_repo":".github","branch":"drill/seed-20260822","head_sha":"aaa","surface":"draft-pr","verdict":"red"}' >/dev/null
[[ $(wc -l < "$H") -eq 1 ]] && { PASS=$((PASS+1)); echo "ok   首条追加"; } || { FAIL=$((FAIL+1)); echo "FAIL 首条追加"; }
"$PYTHON" "$D" record --history "$H" --json '{"ts":"2026-08-22T05:00:00Z","kind":"seed-drill","run_id":"r2","sample_id":"gate-yaml-parse-corrupt","difficulty":"medium","gate":"gate","target_repo":".github","verdict":"red"}' >/dev/null
[[ $(wc -l < "$H") -eq 2 ]] && { PASS=$((PASS+1)); echo "ok   顺序追加"; } || { FAIL=$((FAIL+1)); echo "FAIL 顺序追加"; }
"$PYTHON" "$D" record --history "$H" --json '{"ts":"2026-08-21T00:00:00Z","kind":"seed-drill","run_id":"r3"}' >/dev/null 2>&1
[[ $? -ne 0 ]] && { PASS=$((PASS+1)); echo "ok   时间戳回拨被拒（append-only）"; } || { FAIL=$((FAIL+1)); echo "FAIL 回拨被放行"; }
"$PYTHON" "$D" record --history "$H" --json '{"ts":"2026-08-22T06:00:00Z","kind":"seed-drill","run_id":"r1"}' >/dev/null 2>&1
[[ $? -ne 0 ]] && { PASS=$((PASS+1)); echo "ok   同 run 重复记录被拒"; } || { FAIL=$((FAIL+1)); echo "FAIL 重复 run 被放行"; }
"$PYTHON" "$D" record --history "$H" --json 'not-json' >/dev/null 2>&1
[[ $? -ne 0 ]] && { PASS=$((PASS+1)); echo "ok   畸形 JSON 被拒"; } || { FAIL=$((FAIL+1)); echo "FAIL 畸形被放行"; }
PRE=$(head -1 "$H")
"$PYTHON" "$D" record --history "$H" --json '{"ts":"2026-08-22T07:00:00Z","kind":"seed-drill","run_id":"r4","difficulty":"hard","gate":"gate","verdict":"red"}' >/dev/null
[[ "$(head -1 "$H")" == "$PRE" ]] && { PASS=$((PASS+1)); echo "ok   追加不改写既有行"; } || { FAIL=$((FAIL+1)); echo "FAIL 既有行被改写"; }

echo "== 2) redrate 聚合（红率 + 难度趋势 + 零分母诚实口径 + 告警出口）"
OUT=$("$PYTHON" "$D" redrate --history "$H")
echo "$OUT" | "$PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert d["seed_drills"] == 3, d
assert d["verdicts"] == {"red": 3}, d
assert d["red_rate"] == 1.0, d
day = d["difficulty_trend_by_day"]["2026-08-22"]
assert day.get("easy") == 1 and day.get("medium") == 1 and day.get("hard") == 1, day
' && { PASS=$((PASS+1)); echo "ok   红=3/3 rate=1.0 且难度分布可见"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 聚合口径: $OUT"; }
printf '%s\n' '{"ts":"2026-08-29T04:23:11Z","kind":"seed-drill","run_id":"r5","difficulty":"easy","gate":"org-hygiene","verdict":"green"}' >> "$H"
OUT=$("$PYTHON" "$D" redrate --history "$H")
echo "$OUT" | "$PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert d["red_rate"] == 0.75, d  # 3红/4可判定（no-surface 不入分母）
' && { PASS=$((PASS+1)); echo "ok   green 入账拉低红率（0.75）"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 红率计算: $OUT"; }
"$PYTHON" "$D" redrate --history "$H" --fail-unhealthy >/dev/null 2>&1
[[ $? -ne 0 ]] && { PASS=$((PASS+1)); echo "ok   红率<100% 触发告警退出（AC-4 告警出口）"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 告警出口未触发"; }
H2="$TMP/empty.jsonl"; : > "$H2"
OUT=$("$PYTHON" "$D" redrate --history "$H2")
echo "$OUT" | grep -q '"red_rate": null' && { PASS=$((PASS+1)); echo "ok   零分母→null（不除零不出假 100%）"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 零分母口径: $OUT"; }

echo "台账自测: pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
