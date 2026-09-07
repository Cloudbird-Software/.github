#!/usr/bin/env bash
# negtest_m1.sh · M1 控制面负面测试（可复跑）
# 前置：控制面 GREEN（先跑 services/scripts/start-control-plane.sh）；PG 运行中。
# 依据：DGA-INFRA 第 5 章 R-GOV-03 / R-GOV-04 / R-SEC-04；实测输出全文见 negtest-m1.md
set -uo pipefail

ROOT="D:/Projects/dga-infra"
BASE="http://127.0.0.1:8090"
PSQL="$ROOT/services/postgres/pgsql/bin/psql.exe"
PY="$ROOT/.venv/Scripts/python.exe"

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }
q()   { "$PSQL" -U dga -d dga_control -At -c "$1"; }
cu_count() { q 'SELECT count(*) FROM "ClosureUnit"'; }

echo "== 0. 前置：healthz + 主数据幂等 seed =="
health=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/healthz")
if [ "$health" != "200" ]; then
  echo "控制面未就绪（healthz=$health）。先执行：services/scripts/start-control-plane.sh"; exit 1
fi
"$PSQL" -U dga -d dga_control -q -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO "Person" (id, created_at, full_name, org_role) VALUES
 ('PSN-0001', now(), 'S5（公司所有者）', 'S5 所有者/裁决者'),
 ('PSN-0002', now(), '执行轨道 agent', '执行 agent')
ON CONFLICT (id) DO NOTHING;
INSERT INTO "Intent" (id, created_at, statement, closure_type, desired_outcome, holder) VALUES
 ('INT-0001', now(), '验证 M1 控制面闭环登记链路', '开发', '负面测试四案例全绿', 'PSN-0001')
ON CONFLICT (id) DO NOTHING;
INSERT INTO "CapabilityEntity" (id, created_at, executor_type, capability_version) VALUES
 ('CAP-0001', now(), 'AGENT', 'v0.1') ON CONFLICT (id) DO NOTHING;
INSERT INTO "ContextAsset" (id, created_at, asset_type, uri, version, authority_source) VALUES
 ('CTX-0001', now(), 'SPEC', 'git://gov-infra-repo/schemas/dga-ontology.yaml', '1.0', 'Git')
ON CONFLICT (id) DO NOTHING;
INSERT INTO "ActionType" (id, created_at, params_schema_ref, permission_predicate_ref, required_evidence_type, failure_semantics) VALUES
 ('ACT-0001', now(), 'schemas/generated/dga-ontology.schema.json#/$defs/ActionType',
  'policies/allow_m1_smoke.rego', 'EXECUTION_RECEIPT', 'RETRY_SAFE') ON CONFLICT (id) DO NOTHING;
INSERT INTO "EvidenceEntity" (id, created_at, evidence_type, storage_uri, content_digest) VALUES
 ('EVD-0001', now(), 'EXECUTION_RECEIPT', 'b2://dga-evidence/m1/smoke-receipt.json', 'deadbeef')
ON CONFLICT (id) DO NOTHING;
SQL
echo "  healthz=200，seed 完成（ClosureUnit 现有 $(cu_count) 行）"

# ---------------------------------------------------------------
echo "== 案例① 缺 accountability 的 closure → HTTP 422 且 DB 无新增行（R-GOV-03）=="
before=$(cu_count)
echo '  $ curl -s -X POST /closures -d {无 accountability 的六元组}'
resp=$(curl -s -w $'\n%{http_code}' -X POST "$BASE/closures" -H "Content-Type: application/json" -d '{
  "intent_id":"INT-0001","capability_id":"CAP-0001","context_asset_id":"CTX-0001",
  "action_type_ids":["ACT-0001"],"evidence_ids":["EVD-0001"],
  "state":"DRAFT","decision_timespan":"PT8H"}')
code=$(echo "$resp" | tail -n1); body=$(echo "$resp" | sed '$d')
after=$(cu_count)
echo "  HTTP $code"; echo "  $body" | head -c 400; echo
if [ "$code" = "422" ] && [ "$before" = "$after" ]; then
  ok "案例① HTTP 422 且 ClosureUnit 行数不变（$before → $after）"
else
  bad "案例① code=$code 行数 $before → $after"
fi

# ---------------------------------------------------------------
echo "== 案例② 决策卡缺任一必填字段 → HTTP 422（R-GOV-04 六字段 + addressee 逐字段 7 例）=="
for f in object evidence options recommendation deadline consequences addressee; do
  body=$("$PY" - "$f" <<'PYEOF'
import json, sys
full = {"object":"裁决对象占位","evidence":["EVD-0001"],
        "options":[{"label":"方案A"},{"label":"方案B"}],
        "recommendation":"推荐A","deadline":"2026-09-13T00:00:00Z",
        "consequences":"批准后果占位","addressee":"PSN-0001"}
full.pop(sys.argv[1])
print(json.dumps(full, ensure_ascii=False))
PYEOF
)
  code=$(curl -s -o /tmp/negtest_m1_case2.out -w "%{http_code}" \
    -X POST "$BASE/decisions" -H "Content-Type: application/json" -d "$body")
  echo "  缺 [$f] → HTTP $code"
  if [ "$code" = "422" ]; then pass=$((pass+1)); else bad "案例② 缺 [$f] 得到 $code"; fail=$((fail+1)); fi
done
echo "  PASS: 案例② 7/7 皆 422（若上列无 FAIL）" 

# ---------------------------------------------------------------
echo "== 案例③ resolve 时 X-S5-Person 错人/缺失 → HTTP 403（R-SEC-04 代签防护）=="
resp=$(curl -s -X POST "$BASE/decisions" -H "Content-Type: application/json" -d '{
  "object":"negtest③ 裁决对象","evidence":["EVD-0001"],
  "options":[{"label":"方案A"}],"recommendation":"推荐A",
  "deadline":"2026-09-13T00:00:00Z","consequences":"批准后果占位","addressee":"PSN-0001"}')
card=$(echo "$resp" | "$PY" -c 'import sys,json;print(json.load(sys.stdin)["id"])')
echo "  待裁决卡片: $card（addressee=PSN-0001）"

echo '  $ curl -X POST /decisions/'"$card"'/resolve -H "X-S5-Person: PSN-0002"（错人）'
r3=$(curl -s -w $'\n%{http_code}' -X POST "$BASE/decisions/$card/resolve" \
  -H "Content-Type: application/json" -H "X-S5-Person: PSN-0002" \
  -d '{"decision":"approved","decided_by":"PSN-0002"}')
c3=$(echo "$r3" | tail -n1); b3=$(echo "$r3" | sed '$d')
echo "  HTTP $c3"; echo "  $b3"

echo '  $ curl -X POST /decisions/'"$card"'/resolve（无 X-S5-Person 头）'
c3b=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/decisions/$card/resolve" \
  -H "Content-Type: application/json" -d '{"decision":"approved","decided_by":"PSN-0002"}')
echo "  HTTP $c3b"

pending=$(q "SELECT count(*) FROM \"S5DecisionCard\" WHERE id='$card' AND decided_by IS NULL")
if [ "$c3" = "403" ] && [ "$c3b" = "403" ] && [ "$pending" = "1" ]; then
  ok "案例③ 错人 403 + 缺头 403 + 卡片保持 pending"
else
  bad "案例③ c3=$c3 c3b=$c3b pending=$pending"
fi
echo "  对照：正确人 resolve → $(curl -s -X POST "$BASE/decisions/$card/resolve" -H "Content-Type: application/json" -H "X-S5-Person: PSN-0001" -d '{"decision":"approved","decided_by":"PSN-0001"}')"

# ---------------------------------------------------------------
echo "== 案例④ 阳性对照：合法六元组闭环 → 201 且可查询、DB +1 =="
before=$(cu_count)
r4=$(curl -s -w $'\n%{http_code}' -X POST "$BASE/closures" -H "Content-Type: application/json" -d '{
  "intent_id":"INT-0001","capability_id":"CAP-0001","context_asset_id":"CTX-0001",
  "action_type_ids":["ACT-0001"],"evidence_ids":["EVD-0001"],
  "accountability":{"responsible_person_id":"PSN-0001","role":"ACCOUNTABLE"},
  "state":"REGISTERED","decision_timespan":"P1D","name":"negtest④ 合法闭环",
  "trust_level":"T1","data_class":"D_内部","boundary":"company-cloud"}')
code=$(echo "$r4" | tail -n1); body=$(echo "$r4" | sed '$d')
echo "  HTTP $code"; echo "  $body"
cu_id=$(echo "$body" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null || echo "")
get_code=$(curl -s -o /tmp/negtest_m1_case4_get.json -w "%{http_code}" "$BASE/closures/$cu_id")
after=$(cu_count)
echo "  GET /closures/$cu_id → HTTP $get_code"
echo "  $(cat /tmp/negtest_m1_case4_get.json | head -c 300)"
if [ "$code" = "201" ] && [ "$get_code" = "200" ] && [ "$after" -eq $((before+1)) ]; then
  ok "案例④ 201 + GET 200 + 行数 $before → $after"
else
  bad "案例④ post=$code get=$get_code 行数 $before → $after"
fi

# ---------------------------------------------------------------
echo "== 结果：PASS=$pass FAIL=$fail =="
[ "$fail" = "0" ] && echo "negtest-m1: ALL GREEN" || echo "negtest-m1: RED"
exit "$fail"
