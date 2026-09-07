#!/usr/bin/env bash
# negtest_m2.sh — DGA-INFRA M2 资源池 v0 负面测试（五案例，证据驱动）
# 规范依据：DGA-INFRA-v1.0 3.2/3.3/3.4/3.5（R-POOL-TRUST/DATA/COMPLIANCE/DEGRADE）、
#           R-POL-03（虚拟 key+限额+消费入账三证据）。
# 用法：bash controls/negtest_m2.sh；任何案例 FAIL 则退出码非 0。
# 纪律：全 mock，零真实密钥；master key sk-dga-local-dev 为本机占位非凭据。
set -u
REPO="/d/Projects/dga-infra/gov-infra-repo"
PY="/d/Projects/dga-infra/.venv/Scripts/python.exe"
ROUTER="$REPO/pools/route_check.py"
MK="sk-dga-local-dev"
OPA="http://127.0.0.1:8181"
PROXY="http://127.0.0.1:4000"
PASS=0; FAIL=0

note() { echo; echo "########## $1 ##########"; }
expect() { # expect <描述> <条件退出码bool>
  if [ "$2" = "0" ]; then echo ">>> [$1] PASS"; PASS=$((PASS+1)); else echo ">>> [$1] FAIL"; FAIL=$((FAIL+1)); fi
}

echo "==== 前置：服务在位（幂等拉起）===="
bash /d/Projects/dga-infra/services/opa/start.sh
bash /d/Projects/dga-infra/services/scripts/start-litellm.sh

note "案例① sensitivity=customer_sensitive → T0/全端点被 OPA deny（路由器拒绝+原因）"
OUT1=$("$PY" "$ROUTER" --task-id NT-0001 --sensitivity customer_sensitive); RC1=$?
echo "$OUT1"; echo "route_check exit=$RC1"
echo "$OUT1" | grep -q '"decision": "denied"' && echo "$OUT1" | grep -q 'R-POOL-DATA'
expect "①customer_sensitive→denied 且含 R-POOL-DATA" $?

note "案例② sensitivity=internal → T0 deny、T1 allow（先 OPA 直查两态，再路由器全程）"
echo "--- OPA 直查 internal×T0 (expect allow=false) ---"
curl -s -X POST "$OPA/v1/data/dga/pool/decision" -d '{"input":{"task":{"task_id":"NT-0002","sensitivity":"internal"},"endpoint":{"endpoint_name":"free-workhorse","trust_label":"T0","tos_risk":"clear"}}}'; echo
OPA_T0=$(curl -s -X POST "$OPA/v1/data/dga/pool/allow" -d '{"input":{"task":{"task_id":"NT-0002","sensitivity":"internal"},"endpoint":{"endpoint_name":"free-workhorse","trust_label":"T0","tos_risk":"clear"}}}')
echo "$OPA_T0" | grep -q '"result":false'; expect "②a OPA internal×T0 deny" $?
echo "--- OPA 直查 internal×T1 (expect allow=true) ---"
OPA_T1=$(curl -s -X POST "$OPA/v1/data/dga/pool/allow" -d '{"input":{"task":{"task_id":"NT-0002","sensitivity":"internal"},"endpoint":{"endpoint_name":"paid-judge","trust_label":"T1","tos_risk":"clear"}}}')
echo "$OPA_T1"; echo "$OPA_T1" | grep -q '"result":true'; expect "②b OPA internal×T1 allow" $?
echo "--- 路由器全程（应先拒两个 T0 再落 paid-judge）---"
OUT2=$("$PY" "$ROUTER" --task-id NT-0002 --sensitivity internal); echo "$OUT2"
echo "$OUT2" | grep -q '"endpoint": "paid-judge"' && echo "$OUT2" | grep -q 'R-POOL-TRUST'
expect "②c 路由器 internal→routed=paid-judge 且 T0 被拒留痕" $?

note "案例③ tos_risk=grey-zone 账号端点承接 internal → deny（R-POOL-COMPLIANCE）"
echo "--- 路由器 evaluated 中 gray-probe 的拒绝留痕 ---"
OUT3=$("$PY" "$ROUTER" --task-id NT-0003 --sensitivity internal); echo "$OUT3"
echo "$OUT3" | grep -q 'R-POOL-COMPLIANCE'; expect "③a 路由器留痕含 R-POOL-COMPLIANCE" $?
echo "--- OPA 直查：灰区端点即使被误标 T1 也须 deny（灰区规则独立于信任级）---"
O3=$(curl -s -X POST "$OPA/v1/data/dga/pool/decision" -d '{"input":{"task":{"task_id":"NT-0003","sensitivity":"internal"},"endpoint":{"endpoint_name":"gray-probe","trust_label":"T1","tos_risk":"grey-zone"}}}')
echo "$O3"
echo "$O3" | grep -q '"allow":false' && echo "$O3" | grep -q 'R-POOL-COMPLIANCE'
expect "③b 灰区误标T1仍deny（仅R-POOL-COMPLIANCE）" $?

note "案例④（阳性对照）sensitivity=public → T0 allow"
OUT4=$("$PY" "$ROUTER" --task-id NT-0004 --sensitivity public); RC4=$?
echo "$OUT4"; echo "route_check exit=$RC4"
echo "$OUT4" | grep -q '"endpoint": "free-workhorse"' && echo "$OUT4" | grep -q '"decision": "routed"'
expect "④public→routed=free-workhorse" $?

note "案例⑤ virtual key 超 max_budget 后调用被拒（预算执法，R-POL-03）"
TS=$(date +%s)
RESP=$(curl -s -X POST "$PROXY/key/generate" -H "Authorization: Bearer $MK" -H "Content-Type: application/json" \
  -d "{\"key_alias\":\"m2-negtest-$TS\",\"max_budget\":0.001}")
echo "key/generate(截取): $(echo "$RESP" | head -c 200)..."
VK=$(echo "$RESP" | "$PY" -c "import sys,json;print(json.load(sys.stdin)['key'])")
echo "virtual key prefix: ${VK:0:10}..."
echo "--- 调用 1（expect 200；spend 0.03 > max_budget 0.001 在调用后记账）---"
C1=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PROXY/v1/chat/completions" \
  -H "Authorization: Bearer $VK" -H "Content-Type: application/json" \
  -d '{"model":"mock-free","messages":[{"role":"user","content":"budget probe one"}]}')
echo "call#1 HTTP $C1"
[ "$C1" = "200" ]; expect "⑤a 未超限前调用 200" $?
echo "--- 轮询调用至预算拦截（spend 异步入账，最多 6 次×3s）---"
CODE=200; BODY=""
for i in 1 2 3 4 5 6; do
  sleep 3
  CODE=$(curl -s -o /tmp/negtest_m2_body.json -w "%{http_code}" -X POST "$PROXY/v1/chat/completions" \
    -H "Authorization: Bearer $VK" -H "Content-Type: application/json" \
    -d '{"model":"mock-free","messages":[{"role":"user","content":"budget probe over"}]}')
  echo "attempt $i: HTTP $CODE"
  [ "$CODE" != "200" ] && BODY=$(cat /tmp/negtest_m2_body.json) && break
done
echo "$BODY"
echo "$BODY" | grep -q "budget_exceeded"; expect "⑤b 超限调用被拒（budget_exceeded）" $?
echo "--- 消费入账证据（LiteLLM_SpendLogs 计数与最近行）---"
export PATH="/d/Projects/dga-infra/services/postgres/pgsql/bin:$PATH"
psql -U dga -h localhost -d dga_litellm -c "SELECT count(*) AS spend_rows FROM \"LiteLLM_SpendLogs\""
psql -U dga -h localhost -d dga_litellm -c "SELECT model, spend, prompt_tokens, completion_tokens, total_tokens FROM \"LiteLLM_SpendLogs\" ORDER BY \"endTime\" DESC LIMIT 4"

note "汇总"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ] && echo "NEGTEST-M2: ALL PASS" || echo "NEGTEST-M2: HAS FAILURES"
exit $([ "$FAIL" = "0" ] && echo 0 || echo 1)
