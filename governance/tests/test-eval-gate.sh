#!/usr/bin/env bash
# test-eval-gate.sh —— W5-E1（#421）AC-10b 非劣性 eval gate 家族自测
#
# 离线自足：fixture policy/报告/输入清单全部临时生成，零 holdout/CIW 依赖。
# 断言：全家族绿 / 逐族红（非劣性超 δ 双方向、恰达边界=绿、缺指标 fail-closed、
# cost/latency 回归、污染命中）/ policy 非法=infra（exit 2）/ 事件 schema 契约
# （write_evidence 可直接消费：card/tenant join key+payload 指标摘要）。
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
GATE="$DIR/governance/eval-gate.py"

# ---- fixture：policy（与真源同结构）+ 双报告 + 输入面 ----
cat > "$TMP/policy.yaml" <<'EOF'
family:
  id: non-inferiority
  required: [non_inferiority, cost, latency, contamination]
  baseline_ref: HO-TEST@deadbeef
metrics:
  precision: {direction: higher, delta: 0.05}
  drop_rate: {direction: lower, delta: 0.10}
regressions:
  cost_ratio_max: 1.25
  latency_ratio_max: 1.30
EOF
cat > "$TMP/base.json" <<'EOF'
{"metrics": {"precision": 0.80, "drop_rate": 0.50},
 "cost_usd": 1.00, "latency_ms": 1000, "provenance": "fixture-baseline"}
EOF
cat > "$TMP/inputs.txt" <<'EOF'
opt-input rules.yaml sha256:1111111111111111111111111111111111111111111111111111111111111111
opt-input prompt-v2 sha256:2222222222222222222222222222222222222222222222222222222222222222
EOF
mk_cand() { # $1=precision $2=drop_rate $3=cost $4=latency
  printf '{"metrics": {"precision": %s, "drop_rate": %s}, "cost_usd": %s, "latency_ms": %s, "provenance": "fixture-candidate"}\n' \
    "$1" "$2" "$3" "$4"
}
run() { python3 "$GATE" --policy "$TMP/policy.yaml" --baseline "$TMP/base.json" \
  --candidate "$TMP/cand.json" --card Cloudbird-Software/.github#421 --tenant cloudbird-internal \
  --dataset-digest 3333333333333333333333333333333333333333333333333333333333333333 \
  --inputs "$TMP/inputs.txt" "$@" >/dev/null 2>&1; }

# ---- 正向：全家族绿 ----
mk_cand 0.78 0.55 1.20 1200 > "$TMP/cand.json"
run --event-out "$TMP/ev.json"; RC=$?
[[ $RC -eq 0 ]] && ok "全家族绿（非劣性+cost+latency+污染全过）" || bad "全家族绿（rc=$RC）"

# 事件 schema 契约（write_evidence 消费面：join key+tenant+payload 摘要+无链字段）
jq -e '.kind=="gate" and .action=="eval-noninferiority" and .verdict=="green"
  and (.ts|test("^20[0-9]{2}-[0-9]{2}-[0-9]{2}T")) and .subject.card=="Cloudbird-Software/.github#421" and .subject.tenant=="cloudbird-internal"
  and (.actor.role=="bot") and (.payload|length>0) and (.payload|fromjson|.metrics.precision|keys|length==2)
  and (has("seq")|not) and (has("hash")|not)' "$TMP/ev.json" >/dev/null \
  && ok "事件契约字段齐（join key+tenant+payload 指标摘要，链字段归 write_evidence）" || bad "事件契约缺"

# ---- 边界：恰达 δ=绿（higher: 0.80−0.05=0.75；lower: 0.50+0.10=0.60）----
mk_cand 0.75 0.60 1.00 1000 > "$TMP/cand.json"
run; RC=$?
[[ $RC -eq 0 ]] && ok "恰达 δ 边界=绿（含边界，非严格劣化）" || bad "边界误红（rc=$RC）"

# ---- 非劣性红：higher 超 δ ----
mk_cand 0.74 0.50 1.00 1000 > "$TMP/cand.json"
run; RC=$?
[[ $RC -eq 1 ]] && ok "precision 劣化超 δ → 红（higher 方向执法）" || bad "higher 漏检（rc=$RC）"

# ---- 非劣性红：lower 超 δ ----
mk_cand 0.80 0.61 1.00 1000 > "$TMP/cand.json"
run; RC=$?
[[ $RC -eq 1 ]] && ok "drop_rate 劣化超 δ → 红（lower 方向执法）" || bad "lower 漏检（rc=$RC）"

# ---- 缺声明指标 fail-closed：candidate 少报 → 红 ----
printf '{"metrics": {"precision": 0.80}, "cost_usd": 1.0, "latency_ms": 1000}\n' > "$TMP/cand.json"
run; RC=$?
[[ $RC -eq 1 ]] && ok "candidate 缺声明指标 → 红（少报躲门槛 fail-closed）" || bad "缺指标漏检（rc=$RC）"

# ---- cost 回归红 ----
mk_cand 0.80 0.50 1.26 1000 > "$TMP/cand.json"
run; RC=$?
[[ $RC -eq 1 ]] && ok "cost 超 ratio 上界 → 红（回归执法）" || bad "cost 漏检（rc=$RC）"

# ---- latency 回归红（cost 缺失也红——fail-closed 无默认绿）----
mk_cand 0.80 0.50 1.00 1301 > "$TMP/cand.json"
run; RC=$?
[[ $RC -eq 1 ]] && ok "latency 超 ratio 上界 → 红（回归执法）" || bad "latency 漏检（rc=$RC）"
printf '{"metrics": {"precision": 0.80, "drop_rate": 0.50}, "latency_ms": 1000}\n' > "$TMP/cand.json"
run; RC=$?
[[ $RC -eq 1 ]] && ok "cost 缺报 → 红（回归上界无从执法=红，无默认绿）" || bad "cost 缺报漏检（rc=$RC）"

# ---- 污染命中红：数据集 digest（及前 16hex 形态）进输入面 ----
mk_cand 0.80 0.50 1.00 1000 > "$TMP/cand.json"
cat >> "$TMP/inputs.txt" <<'EOF'
opt-input eval-dataset-leak sha256:3333333333333333333333333333333333333333333333333333333333333333
EOF
run; RC=$?
[[ $RC -eq 1 ]] && ok "污染命中 → 红（数据集 digest 进优化输入面）" || bad "污染漏检（rc=$RC）"
sed -i '/eval-dataset-leak/d' "$TMP/inputs.txt"
echo "opt-input eval-dataset-shortref 3333333333333333" >> "$TMP/inputs.txt"
run; RC=$?
[[ $RC -eq 1 ]] && ok "污染命中（前 16hex 短引用形态）→ 红" || bad "短引用污染漏检（rc=$RC）"
sed -i '/eval-dataset-shortref/d' "$TMP/inputs.txt"

# ---- infra：policy 非法（负 δ / 坏 direction / 空 required）----
mk_cand 0.80 0.50 1.00 1000 > "$TMP/cand.json"
for bad_policy in "metrics: {m: {direction: up, delta: 0.1}}" "metrics: {m: {direction: higher, delta: -1}}"; do
  printf 'family:\n  required: [non_inferiority]\n  baseline_ref: HO-TEST@deadbeef\n%s\nregressions: {cost_ratio_max: 1.2, latency_ratio_max: 1.3}\n' "$bad_policy" > "$TMP/pbad.yaml"
  python3 "$GATE" --policy "$TMP/pbad.yaml" --baseline "$TMP/base.json" --candidate "$TMP/cand.json" \
    --card Cloudbird-Software/.github#421 --tenant t >/dev/null 2>&1; RC=$?
  [[ $RC -eq 2 ]] || { bad "policy 非法未 exit 2（rc=$RC: $bad_policy）"; }
done
ok "policy 非法（坏 direction/负 δ）→ exit 2 infra"

# ---- infra：required 含污染但缺 --dataset-digest / 缺 --inputs ----
python3 "$GATE" --policy "$TMP/policy.yaml" --baseline "$TMP/base.json" --candidate "$TMP/cand.json" \
  --card Cloudbird-Software/.github#421 --tenant t --inputs "$TMP/inputs.txt" >/dev/null 2>&1; RC=$?
[[ $RC -eq 2 ]] && ok "污染执法缺 digest → exit 2（无从执法=fail-closed）" || bad "缺 digest 未 infra（rc=$RC）"

# ---- 真源一致性：policy/eval-gates.yaml 结构合法 + baseline_ref=id@sha8 形态 ----
python3 - "$DIR/governance/policy/eval-gates.yaml" <<'PY' && ok "真源 policy 结构合法（baseline_ref=id@sha8 引用形态）" || bad "真源 policy 非法"
import re, sys, yaml
p = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert p["family"]["required"] and p["family"]["baseline_ref"]
assert re.fullmatch(r"HO-[0-9]{4}@[0-9a-f]{8}", p["family"]["baseline_ref"]), "baseline_ref 非 id@sha8"
for k, s in p["metrics"].items():
    assert s["direction"] in ("higher", "lower") and float(s["delta"]) >= 0
for k in ("cost_ratio_max", "latency_ratio_max"):
    assert float(p["regressions"][k]) >= 1
PY

# ---- W5-E2：波次注册表（waves.yaml——optimization 波次 exit gate 绑定）----
python3 - "$DIR/governance/policy/waves.yaml" <<'PY' && ok "W5-OPT-1 波次注册合法（kind=optimization+exit_gate fail-closed 绑定）" || bad "waves.yaml 非法"
import re, sys, yaml
w = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert w["schema"] == "governance-waves/v1"
v = next(x for x in w["waves"] if x["id"] == "W5-OPT-1")
assert v["kind"] == "optimization"
assert re.fullmatch(r"HO-[0-9]{4}@[0-9a-f]{8}", v["baseline_quad"])
assert re.fullmatch(r"[0-9a-f]{40}", v["optimized"]["baseline_commit"])
assert v["exit_gate"]["verdict_required"] == "green"   # fail-closed：红不得收口
assert v["exit_gate"]["policy"] == "governance/policy/eval-gates.yaml"
PY

echo "----------------------------------------"
echo "test-eval-gate: $([[ $FAIL -eq 0 ]] && echo PASS || echo "FAIL（$FAIL）")"
exit $([[ $FAIL -eq 0 ]] && echo 0 || echo 1)
