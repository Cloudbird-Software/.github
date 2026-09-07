#!/usr/bin/env bash
# negtest_m4_ar.sh — DGA-INFRA M4 Action Registry / MCP 工具网关负面测试（八案例，证据驱动）
# 规范依据：DGA-INFRA-v1.0 R-POL-01/02/04（网关强制/子任务权限≤父/判定隔离）、
#           R-EVID-01/04（执行收据/判定收据三要件）、R-FLOW-03（幂等键+结果核对）、
#           ontology-research §2.3（未注册工具不存在调用路径）。
# 用法：bash controls/negtest_m4_ar.sh；任何案例 FAIL 则退出码非 0。
# 纪律：全 mock 执行器，零真实密钥；caller 身份为请求声明占位（真实身份体系待 M6+，已登记缺口）。
# 说明：文件名沿用本仓库约定（md 连字符 / sh 下划线，同 negtest-m2.md + negtest_m2.sh）。
set -u
AR="http://127.0.0.1:8091"
OPA="http://127.0.0.1:8181"
PY="/d/Projects/dga-infra/.venv/Scripts/python.exe"
PSQL_BIN="/d/Projects/dga-infra/services/postgres/pgsql/bin"
# 注意：临时文件须用 Windows 可见路径（venv python.exe 不识别 MSYS /tmp）
TMP="D:/Projects/dga-infra/gov-infra-repo/controls/.tmp_negtest_m4"
rm -rf "$TMP"; mkdir -p "$TMP"
PASS=0; FAIL=0

note() { echo; echo "########## $1 ##########"; }
expect() { # expect <描述> <条件退出码bool>
  if [ "$2" = "0" ]; then echo ">>> [$1] PASS"; PASS=$((PASS+1)); else echo ">>> [$1] FAIL"; FAIL=$((FAIL+1)); fi
}
code() { # code <body-file> <curl args...> → 打印 HTTP 状态码，响应体落 body-file
  local f="$1"; shift
  curl -s -o "$f" -w "%{http_code}" "$@"
}

echo "==== 前置：服务在位（幂等拉起）===="
bash /d/Projects/dga-infra/services/opa/start.sh
bash /d/Projects/dga-infra/services/scripts/start-action-registry.sh
echo "healthz: $(curl -s $AR/healthz)"

# caller 声明（原型占位身份；EXEC 特意含 run_eval_judgment 授权——证明案例③拒绝来自角色判定隔离而非缺授权）
EXEC='{"person_id":"PSN-EXEC-01","roles":["execution"],"active_authorizations":["echo_public","write_customer_data","run_eval_judgment"]}'
COORD='{"person_id":"PSN-COORD-01","roles":["coordination"],"active_authorizations":["echo_public","write_customer_data","run_eval_judgment"]}'
NOAUTH='{"person_id":"PSN-NOAUTH-01","roles":["coordination"],"active_authorizations":["echo_public"]}'

note "案例① 未注册工具 magic_tool → 404 + 审计 unregistered 行（未注册不存在调用路径）"
C1=$(code "$TMP/c1.json" -X POST "$AR/invoke" -H "Content-Type: application/json" \
  -d "{\"tool\":\"magic_tool\",\"params\":{},\"context\":{\"caller\":$COORD,\"parent_task_scope\":[\"public\"]}}")
echo "HTTP $C1"; cat "$TMP/c1.json"; echo
echo "--- 审计行（GET /audit?tool=magic_tool）---"
A1=$(curl -s "$AR/audit?tool=magic_tool")
echo "$A1"
[ "$C1" = "404" ] && echo "$A1" | grep -q '"decision":"unregistered"'
expect "①magic_tool→404 且审计 unregistered 行在位" $?

note "案例② params 违反注册 schema（message 应为 string）→ 422"
C2=$(code "$TMP/c2.json" -X POST "$AR/invoke" -H "Content-Type: application/json" \
  -d "{\"tool\":\"echo_public\",\"params\":{\"message\":123},\"context\":{\"caller\":$EXEC,\"parent_task_scope\":[\"public\"]}}")
echo "HTTP $C2"; cat "$TMP/c2.json"; echo
[ "$C2" = "422" ] && grep -q 'PARAMS-SCHEMA-VIOLATION' "$TMP/c2.json"
expect "②schema 违规→422+PARAMS-SCHEMA-VIOLATION" $?

note "案例③ executor 调 run_eval_judgment → 403 判定隔离（R-POL-04；caller 持有该工具授权，拒绝只能来自角色隔离）"
C3=$(code "$TMP/c3.json" -X POST "$AR/invoke" -H "Content-Type: application/json" \
  -d "{\"tool\":\"run_eval_judgment\",\"params\":{\"dataset_ref\":\"ds-42\",\"judge_model\":\"mock-judge\",\"judge_version\":\"1.0.0\",\"calibration_domain_id\":\"CAL-0001\"},\"context\":{\"caller\":$EXEC,\"parent_task_scope\":[\"internal\"]}}")
echo "HTTP $C3"; cat "$TMP/c3.json"; echo
echo "--- OPA 直查同输入（独立证明谓词行为）---"
curl -s -X POST "$OPA/v1/data/dga/action/decision" -d "{\"input\":{\"tool\":\"run_eval_judgment\",\"params\":{},\"caller\":$EXEC,\"parent_task_scope\":[\"internal\"],\"tool_decl\":{\"required_scope\":\"internal\",\"judicial\":true,\"idempotency_key_required\":true}}}"; echo
[ "$C3" = "403" ] && grep -q 'R-POL-04-JUDICIAL-ISOLATION' "$TMP/c3.json"
expect "③executor×judicial→403+R-POL-04-JUDICIAL-ISOLATION" $?

note "案例④ 无授权调 write_customer_data → 403（R-POL-AUTHZ-MISSING；parent scope 含 customer_data 以隔离变量）"
C4=$(code "$TMP/c4.json" -X POST "$AR/invoke" -H "Content-Type: application/json" \
  -d "{\"tool\":\"write_customer_data\",\"params\":{\"table\":\"customers\",\"record\":{\"id\":\"C-1\"}},\"context\":{\"caller\":$NOAUTH,\"parent_task_scope\":[\"customer_data\"]}}")
echo "HTTP $C4"; cat "$TMP/c4.json"; echo
[ "$C4" = "403" ] && grep -q 'R-POL-AUTHZ-MISSING' "$TMP/c4.json"
expect "④无授权→403+R-POL-AUTHZ-MISSING" $?

note "案例⑤ parent_task_scope=public 调 write_customer_data → 403 子任务权限越级（R-POL-02；caller 已授权，隔离 scope 变量）"
C5=$(code "$TMP/c5.json" -X POST "$AR/invoke" -H "Content-Type: application/json" \
  -d "{\"tool\":\"write_customer_data\",\"params\":{\"table\":\"customers\",\"record\":{\"id\":\"C-2\"}},\"context\":{\"caller\":$COORD,\"parent_task_scope\":[\"public\"]}}")
echo "HTTP $C5"; cat "$TMP/c5.json"; echo
[ "$C5" = "403" ] && grep -q 'R-POL-02-SCOPE-ESCALATION' "$TMP/c5.json"
expect "⑤parent_scope=public→403+R-POL-02-SCOPE-ESCALATION" $?

note "案例⑥ judgment 工具其余合法但缺 judge_model → 422 判定收据三要件不完整（R-EVID-04 执法位，先于执行）"
C6=$(code "$TMP/c6.json" -X POST "$AR/invoke" -H "Content-Type: application/json" \
  -d "{\"tool\":\"run_eval_judgment\",\"params\":{\"dataset_ref\":\"ds-42\"},\"context\":{\"caller\":$COORD,\"parent_task_scope\":[\"internal\"]}}")
echo "HTTP $C6"; cat "$TMP/c6.json"; echo
[ "$C6" = "422" ] && grep -q 'R-EVID-04-JUDGE-RECEIPT-INCOMPLETE' "$TMP/c6.json"
expect "⑥judgment缺judge_model→422+R-EVID-04" $?

note "案例⑦ 同 idempotency_key 二次调用 → 返回首次结果，不重复执行（副作用计数器不增，R-FLOW-03）"
IDEM_KEY="m4-idem-$(date +%s)"
IDEM_BODY="{\"tool\":\"write_customer_data\",\"params\":{\"table\":\"customers\",\"record\":{\"id\":\"C-9\",\"note\":\"idempotency probe\"}},\"idempotency_key\":\"$IDEM_KEY\",\"context\":{\"caller\":$COORD,\"parent_task_scope\":[\"public\",\"customer_data\"]}}"
echo "--- 首调（expect 200 executed）---"
C7a=$(code "$TMP/c7a.json" -X POST "$AR/invoke" -H "Content-Type: application/json" -d "$IDEM_BODY")
echo "HTTP $C7a"; cat "$TMP/c7a.json"; echo
EV1=$("$PY" -c "import json;d=json.load(open('$TMP/c7a.json'));print(d['evidence_entity_id'],d['result']['execution_seq'],d['audit_id'])")
echo "首次: evidence/seq/audit = $EV1"
EF1=$(curl -s "$AR/tools/write_customer_data/effects"); echo "副作用计数器(首调后): $EF1"
echo "--- 同键重放（expect 200 + idempotent_replay=true + 同 evidence/seq）---"
C7b=$(code "$TMP/c7b.json" -X POST "$AR/invoke" -H "Content-Type: application/json" -d "$IDEM_BODY")
echo "HTTP $C7b"; cat "$TMP/c7b.json"; echo
EF2=$(curl -s "$AR/tools/write_customer_data/effects"); echo "副作用计数器(重放后): $EF2"
[ "$C7a" = "200" ] && [ "$C7b" = "200" ] \
  && grep -q '"idempotent_replay":true' "$TMP/c7b.json" \
  && [ "$EV1" = "$("$PY" -c "import json;d=json.load(open('$TMP/c7b.json'));print(d['evidence_entity_id'],d['result']['execution_seq'],d['audit_id'])")" ] \
  && [ "$EF1" = "$EF2" ]
expect "⑦同键重放返回首次结果且计数器不增" $?

note "案例⑧（阳性对照）authorized echo_public → 200 + 审计 allowed + EvidenceEntity 行"
C8=$(code "$TMP/c8.json" -X POST "$AR/invoke" -H "Content-Type: application/json" \
  -d "{\"tool\":\"echo_public\",\"params\":{\"message\":\"hello M4\"},\"context\":{\"caller\":$EXEC,\"parent_task_scope\":[\"public\"]}}")
echo "HTTP $C8"; cat "$TMP/c8.json"; echo
A8=$("$PY" -c "import json;d=json.load(open('$TMP/c8.json'));print(d['audit_id'],d['evidence_entity_id'],d['opa_decision_id'])")
echo "audit/evidence/opa_decision_id = $A8"
AUD_ID=$(echo "$A8" | cut -d' ' -f1); EVD_ID=$(echo "$A8" | cut -d' ' -f2)
echo "--- 审计行 ---"; curl -s "$AR/audit/$AUD_ID"; echo
C8CHK=1
[ "$C8" = "200" ] && [ -n "$EVD_ID" ] && [ "$AUD_ID" != "None" ] \
  && curl -s "$AR/audit/$AUD_ID" | grep -q '"decision":"allowed"' && C8CHK=0
expect "⑧阳性→200+audit_id+evidence_entity_id+opa_decision_id" $C8CHK

note "证据落盘抽查（PG 权威源；含全部新审计行 + 执行收据 + 幂等缓存 + 计数器）"
export PATH="$PSQL_BIN:$PATH"
psql -U dga -h localhost -d dga_control -c \
  "SELECT id, tool_name, caller_person_id, decision, fail_reason, idempotency_key, idempotent_replay, evidence_entity_id FROM ar_audit ORDER BY id" \
  -c "SELECT id, evidence_type, content_digest, judge_model, judge_version, calibration_domain_ref, storage_uri FROM \"EvidenceEntity\" WHERE id LIKE 'EVD-%' ORDER BY id" \
  -c "SELECT idempotency_key, tool_name, params_hash, audit_id, evidence_entity_id FROM ar_idempotency" \
  -c "SELECT * FROM ar_mock_effects ORDER BY tool_name"

note "汇总"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ] && echo "NEGTEST-M4-AR: ALL PASS" || echo "NEGTEST-M4-AR: HAS FAILURES"
exit $([ "$FAIL" = "0" ] && echo 0 || echo 1)
