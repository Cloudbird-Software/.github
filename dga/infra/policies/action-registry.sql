-- action-registry.sql — DGA-INFRA M4 Action Registry v0（MCP 工具网关）
-- 规范依据：
--   DGA-INFRA-v1.0 R-POL-01（权限在工具网关强制）/ R-POL-02（子任务权限 ≤ 父任务）/
--   R-POL-04（判定隔离）/ R-POL-05（OPA decision log 入证据流）/
--   R-EVID-01（执行收据证据契约）/ R-EVID-04（判定证据三要件）/
--   R-FLOW-03（幂等键 + 结果核对）/ ontology-research §2.3（Action Registry：未注册工具不存在调用路径）。
-- 纪律：
--   * 只建新表（ar_* 前缀），不改动既有 43 表的结构；对既有 "ActionType" 仅 INSERT 种子行（ACT-0002..0004，
--     ON CONFLICT DO NOTHING——任务要求 ar_tools.action_type_id 外键本体 ActionType 表，数据行非结构改动）。
--   * 幂等：CREATE TABLE IF NOT EXISTS + INSERT .. ON CONFLICT；可重复执行。
--   * 本文件位于 policies/ 目录：OPA 1.20.2 目录加载忽略非 .rego/.json/.yaml 文件
--     （2026-09-07 实测 .sql 在位时目录加载正常，pool 谓词可查）。
--   * 运行时投影登记（action_type_id / permission_* / required_scope / judicial）的权威源 = Git 本文件；
--     服务运行期经 POST /tools 的注册会覆盖运行时行，但下次 start 脚本重放本文件即恢复 Git 权威版本。

-- ---------------------------------------------------------------------------
-- 1. ar_tools · 注册表（每注册工具 = 本体 ActionType 的运行时投影 + 网关强制点声明）
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ar_tools (
    tool_name                text PRIMARY KEY,
    action_type_id           text NOT NULL REFERENCES "ActionType"(id),
    params_json_schema       jsonb NOT NULL,                 -- 按工具独立提交（ontology-research §2.3：注册时提交 params schema）
    permission_package       text NOT NULL DEFAULT 'dga.action',
    permission_path          text NOT NULL DEFAULT 'tool_invoke',
    audit_requirements       jsonb NOT NULL,                 -- 必产证据类型数组（EvidenceType 枚举）
    side_effects             jsonb NOT NULL,                 -- 副作用声明（external bool + description）
    idempotency_key_required boolean NOT NULL DEFAULT false, -- R-FLOW-03
    judicial                 boolean NOT NULL DEFAULT false, -- R-POL-04 判定隔离标记：执行者角色不可调用
    is_judgment              boolean NOT NULL DEFAULT false, -- R-EVID-04：判定类工具，执行收据必须带判定三要件
    required_scope           text NOT NULL
        CHECK (required_scope IN ('public', 'internal', 'customer_data')), -- R-POL-02 范围词表
    enabled                  boolean NOT NULL DEFAULT true,  -- 未注册/停用工具不存在调用路径（网关 404+审计）
    registered_at            timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2. ar_audit · 网关审计行（每次调用一行，含被拒/未注册调用——审计与放行解耦）
--    decision 枚举 = 任务书四值；R-EVID-04 判定收据不完整归入 schema_fail（fail_reason 显名 R-EVID-04）。
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ar_audit (
    id                 text PRIMARY KEY,                     -- ARA-xxxx（审计行自有 ID 体系，原型不入本体 22 前缀）
    ts                 timestamptz NOT NULL DEFAULT now(),
    tool_name          text,                                 -- 未注册调用时 = 调用方声称的工具名（无 FK）
    caller_person_id   text,                                 -- 原型占位身份（同控制面 X-S5-Person 缺口，真实身份体系待 M6+）
    caller_roles       jsonb,
    decision           text NOT NULL
        CHECK (decision IN ('allowed', 'denied', 'schema_fail', 'unregistered')),
    fail_reason        text,                                 -- deny 原因（OPA deny_reasons / 管线阶段原因码）
    opa_decision_id    text,                                 -- R-POL-05：OPA decision log ID（原型未接线，登记缺口）
    idempotency_key    text,
    evidence_entity_id text,                                 -- 允许调用的执行收据（EvidenceEntity.id）
    params_hash        text,                                 -- sha256(canonical(params))
    idempotent_replay  boolean NOT NULL DEFAULT false,       -- R-FLOW-03：同键重放行（不执行、不产新证据）
    detail             jsonb
);
CREATE INDEX IF NOT EXISTS ix_ar_audit_tool_ts ON ar_audit (tool_name, ts);
CREATE INDEX IF NOT EXISTS ix_ar_audit_decision ON ar_audit (decision);

-- ---------------------------------------------------------------------------
-- 3. ar_idempotency · 幂等缓存行（R-FLOW-03：幂等键 + 结果核对；PG 唯一约束 = 主键）
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ar_idempotency (
    idempotency_key    text PRIMARY KEY,
    tool_name          text NOT NULL,
    params_hash        text NOT NULL,                        -- 结果核对：同键不同参数 → 409 冲突，不返回缓存
    response           jsonb NOT NULL,                       -- 首次完整响应（重放返回体）
    audit_id           text NOT NULL,                        -- 首次调用的审计行
    evidence_entity_id text,                                 -- 首次调用的执行收据
    created_at         timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 4. ar_mock_effects · mock 执行器副作用计数器（负面测试⑦"副作用计数器不增"的观测点；
--    真实执行器接入后此表由真实副作用收据替代——原型诚实边界）
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ar_mock_effects (
    tool_name       text PRIMARY KEY,
    exec_count      integer NOT NULL DEFAULT 0,
    last_executed_at timestamptz
);

-- ---------------------------------------------------------------------------
-- 5. 种子 A：本体 ActionType 行（数据行；ar_tools.action_type_id 的 FK 目标）
--    params_schema_ref 指向注册表运行时投影；permission_predicate_ref 指向 OPA 谓词文件。
-- ---------------------------------------------------------------------------
INSERT INTO "ActionType"
    (id, name, created_at, params_schema_ref, permission_predicate_ref,
     required_evidence_type, failure_semantics)
VALUES
    ('ACT-0002', 'echo_public',
     now(), 'action-registry://ar_tools/echo_public#params',
     'policies/action-authz.rego#dga.action.tool_invoke', 'EXECUTION_RECEIPT', 'RETRY_SAFE'),
    ('ACT-0003', 'run_eval_judgment',
     now(), 'action-registry://ar_tools/run_eval_judgment#params',
     'policies/action-authz.rego#dga.action.tool_invoke', 'EXECUTION_RECEIPT', 'MARK_UNVERIFIED'),
    ('ACT-0004', 'write_customer_data',
     now(), 'action-registry://ar_tools/write_customer_data#params',
     'policies/action-authz.rego#dga.action.tool_invoke', 'EXECUTION_RECEIPT', 'COMPENSATE')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 6. 种子 B：三个注册工具（任务书点名；ON CONFLICT DO UPDATE = Git 为权威源，重放即收敛）
--    ① echo_public        scope=public        judicial=false  判定类=false  纯回显
--    ② run_eval_judgment  scope=internal      judicial=true   判定类=true   R-POL-04/R-EVID-04 演示位
--    ③ write_customer_data scope=customer_data judicial=false  判定类=false  R-POL-02/R-FLOW-03 演示位
--    说明：run_eval_judgment 的 params schema 不把 judge 三要件设为 required——
--    R-EVID-04 是证据契约执法位（网关管线独立阶段），与参数 schema 校验（阶段②）分开，
--    使负面测试⑥可单独证明 R-EVID-04 被强制执行而非被 schema 顺带拦截。
-- ---------------------------------------------------------------------------
INSERT INTO ar_tools
    (tool_name, action_type_id, params_json_schema, permission_package, permission_path,
     audit_requirements, side_effects, idempotency_key_required, judicial, is_judgment, required_scope)
VALUES
    ('echo_public', 'ACT-0002',
     '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["message"],"properties":{"message":{"type":"string","minLength":1}}}'::jsonb,
     'dga.action', 'tool_invoke',
     '["EXECUTION_RECEIPT"]'::jsonb,
     '{"external": false, "description": "纯回显，无外部副作用"}'::jsonb,
     false, false, false, 'public'),
    ('run_eval_judgment', 'ACT-0003',
     '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["dataset_ref"],"properties":{"dataset_ref":{"type":"string","minLength":1},"judge_model":{"type":"string","minLength":1},"judge_version":{"type":"string","pattern":"^[0-9]+[.][0-9]+[.][0-9]+([-][0-9A-Za-z.]+)?$"},"calibration_domain_id":{"type":"string","minLength":1}}}'::jsonb,
     'dga.action', 'tool_invoke',
     '["EXECUTION_RECEIPT"]'::jsonb,
     '{"external": true, "description": "产生校准判定记录（mock 执行器，不触真实 eval 基础设施）"}'::jsonb,
     true, true, true, 'internal'),
    ('write_customer_data', 'ACT-0004',
     '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"required":["table","record"],"properties":{"table":{"type":"string","minLength":1},"record":{"type":"object","minProperties":1}}}'::jsonb,
     'dga.action', 'tool_invoke',
     '["EXECUTION_RECEIPT"]'::jsonb,
     '{"external": true, "description": "外部客户数据写入（mock 执行器；副作用观测点=ar_mock_effects 计数器）"}'::jsonb,
     true, false, false, 'customer_data')
ON CONFLICT (tool_name) DO UPDATE SET
    action_type_id           = EXCLUDED.action_type_id,
    params_json_schema       = EXCLUDED.params_json_schema,
    permission_package       = EXCLUDED.permission_package,
    permission_path          = EXCLUDED.permission_path,
    audit_requirements       = EXCLUDED.audit_requirements,
    side_effects             = EXCLUDED.side_effects,
    idempotency_key_required = EXCLUDED.idempotency_key_required,
    judicial                 = EXCLUDED.judicial,
    is_judgment              = EXCLUDED.is_judgment,
    required_scope           = EXCLUDED.required_scope,
    enabled                  = EXCLUDED.enabled;
