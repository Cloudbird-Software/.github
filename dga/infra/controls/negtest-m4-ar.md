# NEGTEST-M4-AR · Action Registry / MCP 工具网关负面测试（M4 + SEL-13d）

- date: 2026-09-07（本机批次，UTC+8）
- script: `controls/negtest_m4_ar.sh`（可复跑；任何案例 FAIL 退出码非 0）
- 服务: action-registry @ http://127.0.0.1:8091 · OPA @ http://127.0.0.1:8181 · PG dga_control @5432
- 规范依据: DGA-INFRA-v1.0 R-POL-01/02/04、R-EVID-01/04、R-FLOW-03；ontology-research §2.3（未注册工具不存在调用路径）
- 结果: **PASS=8 FAIL=0**（附注探针 2 项亦符合预期：同键异参 409、OPA 停机 fail-closed 503）

## 被测对象

- 注册表 `ar_tools`（DDL/种子权威源 = `policies/action-registry.sql`，Git）：echo_public（scope=public）、run_eval_judgment（judicial=true，is_judgment=true）、write_customer_data（required_scope=customer_data，idempotency_key_required=true）
- OPA 谓词 `policies/action-authz.rego`（package dga.action）：tool_invoke / deny_reasons / decision
- 网关管线 `POST /invoke` 六级：①注册表→②schema→③OPA→④R-EVID-04 执法位→⑤幂等→⑥执行+证据+审计（四级失败均落 ar_audit 行）

## caller 声明（原型占位身份；EXEC 特意持有 run_eval_judgment 授权——证明案例③的拒绝来自角色判定隔离而非缺授权）

```json
EXEC  = {"person_id":"PSN-EXEC-01","roles":["execution"],"active_authorizations":["echo_public","write_customer_data","run_eval_judgment"]}
COORD = {"person_id":"PSN-COORD-01","roles":["coordination"],"active_authorizations":["echo_public","write_customer_data","run_eval_judgment"]}
NOAUTH= {"person_id":"PSN-NOAUTH-01","roles":["coordination"],"active_authorizations":["echo_public"]}
```

## 结果表

| # | 案例 | 期望 | 实际 | 判定 |
|---|---|---|---|---|
| ① | 未注册 magic_tool | 404 + 审计 unregistered 行 | 404 `TOOL-NOT-REGISTERED` + ARA-0001 decision=unregistered | PASS |
| ② | params 违反注册 schema | 422 | 422 `PARAMS-SCHEMA-VIOLATION`（message: 123 is not of type 'string'） | PASS |
| ③ | executor 调 run_eval_judgment（持授权） | 403 判定隔离 | 403 `R-POL-04-JUDICIAL-ISOLATION`（OPA 直查同因） | PASS |
| ④ | 无授权调 write_customer_data | 403 | 403 `R-POL-AUTHZ-MISSING` | PASS |
| ⑤ | parent_scope=public 调 write_customer_data | 403 越级 | 403 `R-POL-02-SCOPE-ESCALATION` | PASS |
| ⑥ | judgment 工具缺 judge_model（其余合法） | 422（R-EVID-04） | 422 `R-EVID-04-JUDGE-RECEIPT-INCOMPLETE`，missing 三要件全列 | PASS |
| ⑦ | 同 idempotency_key 二次调用 | 返回首次结果，副作用计数器不增 | 200 `idempotent_replay:true`，同 ARA-0007/EVD-0002/seq=1，exec_count 前后均 1 | PASS |
| ⑧ | 阳性：authorized echo_public | 200 + 审计 allowed + EvidenceEntity | 200 + ARA-0009 allowed + EVD-0003 + OPA decision_id 接线在位 | PASS |

## 实跑输出（逐字）

```
==== 前置：服务在位（幂等拉起）====
opa: already running (pid 9944 on 8181), skip
action-registry: 已在运行 (pid 561027)，跳过
healthz: {"status":"ok","service":"dga-action-registry","milestone":"M4","db_dsn_host":"localhost:5432","registered_tools":3,"opa":"http://127.0.0.1:8181"}

########## 案例① 未注册工具 magic_tool → 404 + 审计 unregistered 行（未注册不存在调用路径） ##########
HTTP 404
{"detail":{"decision":"unregistered","fail_reason":"TOOL-NOT-REGISTERED","stage":"1-registry","audit_id":"ARA-0001","caller":{"person_id":"PSN-COORD-01","roles":["coordination"],"active_authorizations":["echo_public","write_customer_data","run_eval_judgment"]}}}
--- 审计行（GET /audit?tool=magic_tool）---
[{"id":"ARA-0001","ts":"2026-09-07T01:33:00.023210+08:00","tool_name":"magic_tool","caller_person_id":"PSN-COORD-01","caller_roles":["coordination"],"decision":"unregistered","fail_reason":"TOOL-NOT-REGISTERED","opa_decision_id":null,"idempotency_key":null,"evidence_entity_id":null,"params_hash":"44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a","idempotent_replay":false,"detail":{"stage":"1-registry","caller":{"roles":["coordination"],"person_id":"PSN-COORD-01","active_authorizations":["echo_public","write_customer_data","run_eval_judgment"]}}}]
>>> [①magic_tool→404 且审计 unregistered 行在位] PASS

########## 案例② params 违反注册 schema（message 应为 string）→ 422 ##########
HTTP 422
{"detail":{"decision":"schema_fail","fail_reason":"PARAMS-SCHEMA-VIOLATION","stage":"2-params-schema","audit_id":"ARA-0002","schema_error":"['message']: 123 is not of type 'string'"}}
>>> [②schema 违规→422+PARAMS-SCHEMA-VIOLATION] PASS

########## 案例③ executor 调 run_eval_judgment → 403 判定隔离（R-POL-04；caller 持有该工具授权，拒绝只能来自角色隔离） ##########
HTTP 403
{"detail":{"decision":"denied","fail_reason":"R-POL-04-JUDICIAL-ISOLATION","stage":"3-opa","audit_id":"ARA-0003","opa_deny_reasons":["R-POL-04-JUDICIAL-ISOLATION"]}}
--- OPA 直查同输入（独立证明谓词行为）---
{"decision_id":"9a445b2b-1a25-49ce-a869-d0bb0d04e0e1","result":{"allow":false,"deny_reasons":["R-POL-04-JUDICIAL-ISOLATION"]}}

>>> [③executor×judicial→403+R-POL-04-JUDICIAL-ISOLATION] PASS

########## 案例④ 无授权调 write_customer_data → 403（R-POL-AUTHZ-MISSING；parent scope 含 customer_data 以隔离变量） ##########
HTTP 403
{"detail":{"decision":"denied","fail_reason":"R-POL-AUTHZ-MISSING","stage":"3-opa","audit_id":"ARA-0004","opa_deny_reasons":["R-POL-AUTHZ-MISSING"]}}
>>> [④无授权→403+R-POL-AUTHZ-MISSING] PASS

########## 案例⑤ parent_task_scope=public 调 write_customer_data → 403 子任务权限越级（R-POL-02；caller 已授权，隔离 scope 变量） ##########
HTTP 403
{"detail":{"decision":"denied","fail_reason":"R-POL-02-SCOPE-ESCALATION","stage":"3-opa","audit_id":"ARA-0005","opa_deny_reasons":["R-POL-02-SCOPE-ESCALATION"]}}
>>> [⑤parent_scope=public→403+R-POL-02-SCOPE-ESCALATION] PASS

########## 案例⑥ judgment 工具其余合法但缺 judge_model → 422 判定收据三要件不完整（R-EVID-04 执法位，先于执行） ##########
HTTP 422
{"detail":{"decision":"schema_fail","fail_reason":"R-EVID-04-JUDGE-RECEIPT-INCOMPLETE","stage":"4-evid04","audit_id":"ARA-0006","missing":["judge_model","judge_version","calibration_domain_id"]}}
>>> [⑥judgment缺judge_model→422+R-EVID-04] PASS

########## 案例⑦ 同 idempotency_key 二次调用 → 返回首次结果，不重复执行（副作用计数器不增，R-FLOW-03） ##########
--- 首调（expect 200 executed）---
HTTP 200
{"decision":"allowed","tool":"write_customer_data","caller":"PSN-COORD-01","audit_id":"ARA-0007","evidence_entity_id":"EVD-0002","opa_decision_id":"19abfa41-5a53-40d1-bce2-21d5ace203c0","params_hash":"4bc0efa679e86478801a2b68eaf8f468605e484c24f6b6855949364674ea50ff","result":{"executor":"mock","tool":"write_customer_data","echo":{"table":"customers","record":{"id":"C-9","note":"idempotency probe"}},"side_effects_decl":{"external":true,"description":"外部客户数据写入（mock 执行器；副作用观测点=ar_mock_effects 计数器）"},"execution_seq":1,"executed_at":"2026-09-06T17:33:03.522507+00:00"},"receipt":{"type":"EXECUTION_RECEIPT","tool":"write_customer_data","params_hash":"4bc0efa679e86478801a2b68eaf8f468605e484c24f6b6855949364674ea50ff","decision":"allowed","ts":"2026-09-06T17:33:03.522507+00:00","audit_id":"ARA-0007","evidence_entity_id":"EVD-0002","execution_seq":1,"caller":{"person_id":"PSN-COORD-01","roles":["coordination"]},"parent_task_scope":["public","customer_data"],"judge":null},"idempotent_replay":false}
首次: evidence/seq/audit = EVD-0002 1 ARA-0007
副作用计数器(首调后): {"tool_name":"write_customer_data","exec_count":1,"last_executed_at":"2026-09-07T01:33:03.522507+08:00"}
--- 同键重放（expect 200 + idempotent_replay=true + 同 evidence/seq）---
HTTP 200
{"tool":"write_customer_data","caller":"PSN-COORD-01","result":{"echo":{"table":"customers","record":{"id":"C-9","note":"idempotency probe"}},"tool":"write_customer_data","executor":"mock","executed_at":"2026-09-06T17:33:03.522507+00:00","execution_seq":1,"side_effects_decl":{"external":true,"description":"外部客户数据写入（mock 执行器；副作用观测点=ar_mock_effects 计数器）"}},"receipt":{"ts":"2026-09-06T17:33:03.522507+00:00","tool":"write_customer_data","type":"EXECUTION_RECEIPT","judge":null,"caller":{"roles":["coordination"],"person_id":"PSN-COORD-01"},"audit_id":"ARA-0007","decision":"allowed","params_hash":"4bc0efa679e86478801a2b68eaf8f468605e484c24f6b6855949364674ea50ff","execution_seq":1,"parent_task_scope":["public","customer_data"],"evidence_entity_id":"EVD-0002"},"audit_id":"ARA-0007","decision":"allowed","params_hash":"4bc0efa679e86478801a2b68eaf8f468605e484c24f6b6855949364674ea50ff","opa_decision_id":"19abfa41-5a53-40d1-bce2-21d5ace203c0","idempotent_replay":true,"evidence_entity_id":"EVD-0002","replay_audit_id":"ARA-0008"}
副作用计数器(重放后): {"tool_name":"write_customer_data","exec_count":1,"last_executed_at":"2026-09-07T01:33:03.522507+08:00"}
>>> [⑦同键重放返回首次结果且计数器不增] PASS

########## 案例⑧（阳性对照）authorized echo_public → 200 + 审计 allowed + EvidenceEntity 行 ##########
HTTP 200
{"decision":"allowed","tool":"echo_public","caller":"PSN-EXEC-01","audit_id":"ARA-0009","evidence_entity_id":"EVD-0003","opa_decision_id":"5164cc19-594b-4223-ac43-54ea3fe4c370","params_hash":"79691c37f58c4cbf0e073eba7478248dbe4d58803e6fe6e3a126e06f360907ae","result":{"executor":"mock","tool":"echo_public","echo":{"message":"hello M4"},"side_effects_decl":{"external":false,"description":"纯回显，无外部副作用"},"execution_seq":1,"executed_at":"2026-09-06T17:33:04.954729+00:00"},"receipt":{"type":"EXECUTION_RECEIPT","tool":"echo_public","params_hash":"79691c37f58c4cbf0e073eba7478248dbe4d58803e6fe6e3a126e06f360907ae","decision":"allowed","ts":"2026-09-06T17:33:04.954729+00:00","audit_id":"ARA-0009","evidence_entity_id":"EVD-0003","execution_seq":1,"caller":{"person_id":"PSN-EXEC-01","roles":["execution"]},"parent_task_scope":["public"],"judge":null},"idempotent_replay":false}
audit/evidence/opa_decision_id = ARA-0009 EVD-0003 5164cc19-594b-4223-ac43-54ea3fe4c370
--- 审计行 ---
{"id":"ARA-0009","ts":"2026-09-07T01:33:04.989404+08:00","tool_name":"echo_public","caller_person_id":"PSN-EXEC-01","caller_roles":["execution"],"decision":"allowed","fail_reason":null,"opa_decision_id":"5164cc19-594b-4223-ac43-54ea3fe4c370","idempotency_key":null,"evidence_entity_id":"EVD-0003","params_hash":"79691c37f58c4cbf0e073eba7478248dbe4d58803e6fe6e3a126e06f360907ae","idempotent_replay":false,"detail":{"stage":"6-executed","execution_seq":1}}
>>> [⑧阳性→200+audit_id+evidence_entity_id+opa_decision_id] PASS

########## 证据落盘抽查（PG 权威源；含全部新审计行 + 执行收据 + 幂等缓存 + 计数器） ##########
    id    |      tool_name      | caller_person_id |   decision   |            fail_reason             |  idempotency_key   | idempotent_replay | evidence_entity_id 
----------+---------------------+------------------+--------------+------------------------------------+--------------------+-------------------+--------------------
 ARA-0001 | magic_tool          | PSN-COORD-01     | unregistered | TOOL-NOT-REGISTERED                |                    | f                 | 
 ARA-0002 | echo_public         | PSN-EXEC-01      | schema_fail  | PARAMS-SCHEMA-VIOLATION            |                    | f                 | 
 ARA-0003 | run_eval_judgment   | PSN-EXEC-01      | denied       | R-POL-04-JUDICIAL-ISOLATION        |                    | f                 | 
 ARA-0004 | write_customer_data | PSN-NOAUTH-01    | denied       | R-POL-AUTHZ-MISSING                |                    | f                 | 
 ARA-0005 | write_customer_data | PSN-COORD-01     | denied       | R-POL-02-SCOPE-ESCALATION          |                    | f                 | 
 ARA-0006 | run_eval_judgment   | PSN-COORD-01     | schema_fail  | R-EVID-04-JUDGE-RECEIPT-INCOMPLETE |                    | f                 | 
 ARA-0007 | write_customer_data | PSN-COORD-01     | allowed      |                                    | m4-idem-1788715983 | f                 | EVD-0002
 ARA-0008 | write_customer_data | PSN-COORD-01     | allowed      |                                    | m4-idem-1788715983 | t                 | EVD-0002
 ARA-0009 | echo_public         | PSN-EXEC-01      | allowed      |                                    |                    | f                 | EVD-0003
(9 rows)

    id    |   evidence_type   |                          content_digest                          | judge_model | judge_version | calibration_domain_ref |               storage_uri               
----------+-------------------+------------------------------------------------------------------+-------------+---------------+------------------------+-----------------------------------------
 EVD-0001 | EXECUTION_RECEIPT | deadbeef                                                         |             |               |                        | b2://dga-evidence/m1/smoke-receipt.json
 EVD-0002 | EXECUTION_RECEIPT | 97c01c60f6f733737b557230d24262c66a6ccffca0bcd7fcc0c841a3bafcdf68 |             |               |                        | ar://execution-receipt/ARA-0007
 EVD-0003 | EXECUTION_RECEIPT | ce727b40af0c83b216d6fa88c1ec365648b7f3defe09eafdbb6672710dc5d12d |             |               |                        | ar://execution-receipt/ARA-0009
(3 rows)

  idempotency_key   |      tool_name      |                           params_hash                            | audit_id | evidence_entity_id 
--------------------+---------------------+------------------------------------------------------------------+----------+--------------------
 m4-idem-1788715983 | write_customer_data | 4bc0efa679e86478801a2b68eaf8f468605e484c24f6b6855949364674ea50ff | ARA-0007 | EVD-0002
(1 row)

      tool_name      | exec_count |       last_executed_at        
---------------------+------------+-------------------------------
 echo_public         |          1 | 2026-09-07 01:33:04.954729+08
 write_customer_data |          1 | 2026-09-07 01:33:03.522507+08
(2 rows)


########## 汇总 ##########
PASS=8 FAIL=0
NEGTEST-M4-AR: ALL PASS
```

## 附注探针（八案例之外，同日实测）

**A. 同键异参 → 409（R-FLOW-03 结果核对）**

```
{"detail":{"decision":"schema_fail","fail_reason":"IDEMPOTENCY-KEY-CONFLICT-SAME-KEY-DIFFERENT-REQUEST","stage":"5-idempotency-conflict","audit_id":"ARA-0011","first_tool":"write_customer_data"}}
HTTP 409
```

**B. OPA 停机 → fail-closed 503（不默认放行；OPA 已随即拉回）**

```
opa: killed pid 1880
{"detail":{"decision":"denied","fail_reason":"R-POL-OPA-UNREACHABLE-FAIL-CLOSED","stage":"3-opa","audit_id":"ARA-0012","opa_error":"[WinError 10061] 由于目标计算机积极拒绝，无法连接。"}}
HTTP 503
opa: launching (shell pid 560966)...
opa: up (http://127.0.0.1:8181)
```

**C. 启停幂等周期 start→stop→stop→start**（输出见 BUILD-LOG 同条）：pid/端口双守卫均生效，终点 healthz GREEN。

## 首轮迭代记录（harness 缺陷，已修复后重跑至全绿）

1. GET /audit 500：psycopg `IndeterminateDatatype`（`%s IS NULL OR col=%s` 参数类型不可推断）→ 改为条件拼装 WHERE。
2. judge_version schema 正则经 SQL→JSON 两层转义后失效（`\\d` 变字面反斜杠）→ 改用 `[0-9]+[.][0-9]+[.][0-9]+` 括号类写法，跨层零转义。
3. 管线序缺陷：幂等必需键检查原置于 OPA 之前，使案例④⑤⑥的 403 被 422 掩盖 → 按任务书六级重排（幂等=第⑤级，在 OPA/R-EVID-04 之后）。
4. 测试脚本 MSYS `/tmp` 路径 Windows python.exe 不可见 → 临时文件改 `controls/.tmp_negtest_m4`（Windows 路径）。

## 遗留缺口（诚实边界）

- caller 身份 = 请求声明占位（同控制面 X-S5-Person 缺口）；真实身份体系（R-SEC-01/02）待 M6+。active_authorizations 的权威源应在控制面 Authorization 表，原型由请求上下文携带——网关侧改为查控制面/OPA 侧数据文件前，不得延伸生产。
- MCP 协议适配：本原型为 HTTP 形态（POST /invoke / /tools），标准 MCP（tool discovery/stdio/SSE）接入登记服务器阶段。
- 执行器为 mock（echo + 副作用声明回显 + ar_mock_effects 计数器）；真实执行器与外部副作用收据（R-EVID-03 对象锁定）待 M5/M6。
- 证据实体落控制面 PG（object_locked=false 占位）；对象存储版本化+WORM 待 SEL-07/M6。
