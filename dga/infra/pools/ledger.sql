-- ledger.sql — DGA-INFRA 池账本（M2 资源池 v0）
-- 规范依据：DGA-INFRA-v1.0 3.1 池对象模型（Provider/Account/LogicalEndpoint/RoutingPolicy 全字段）；
--           3.2 信任标签；3.4 TOS；3.5 降级链；3.6 成本熔断。权威源=控制面 DB（第 1 章权威源表）。
--           凭据引用格式 openbao://kv/dga/pool/<alias>（SEL-06 默认引用格式；明文仅存 OpenBao，R-SEC-02）。
--
-- 本体映射登记（诚实边界）：
--   schemas/generated/dga-ontology.sql 已含 LinkML 生成的 "PoolAccount"/"LogicalEndpoint"/"RoutingPolicy"
--   表，但不直接复用，原因：(a) 列类型 DATETIME 为生成器通用型，PostgreSQL 16 无此类型，DDL 不能直接
--   装载；(b) quota_state/health 被生成器拆成标量表（QuotaState/HealthSnapshot）而非本任务要求的 JSON
--   值对象列；(c) 无降级链数组列（fallback_chain 在本体中是 multivalued string，生成物拆表）。
--   故本文件按 M2 任务建 pool_* 权威表，字段与本体类一一对应（ID 前缀 PRV/ACC/EPL/RTP 不变）；
--   本体生成物与权威表的投影同步待名词运行时落位（S5-PENDING-DEFAULTS 追加项 B）后处理。
--
-- 种子纪律：全部 mock（provider mode=mock_response），零真实密钥；credential_ref 为 OpenBao 引用占位，
--   本机 OpenBao dev 模式 inmem，未写入对应 secret（登记为缺口：M3+ 凭据落库后回填）。

-- ============ 3.1 Provider ============
CREATE TABLE IF NOT EXISTS pool_providers (
  id                        TEXT PRIMARY KEY CHECK (id ~ '^PRV-[0-9]{4,}$'),
  name                      TEXT NOT NULL,
  mode                      TEXT NOT NULL DEFAULT 'mock_response'
                            CHECK (mode IN ('mock_response', 'live')),
  tos_risk_matrix_ref       TEXT,
  data_usage_terms_summary  TEXT,
  notes                     TEXT,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  retired_at                TIMESTAMPTZ
);

-- ============ 3.1 Account ============
CREATE TABLE IF NOT EXISTS pool_accounts (
  id                TEXT PRIMARY KEY CHECK (id ~ '^ACC-[0-9]{4,}$'),
  name              TEXT NOT NULL,
  provider          TEXT NOT NULL REFERENCES pool_providers(id),
  credential_ref    TEXT NOT NULL
                    CHECK (credential_ref ~ '^openbao://kv/dga/pool/[a-z0-9][a-z0-9-]*$'),
  cost_tier         TEXT NOT NULL CHECK (cost_tier IN ('free', 'low-paid', 'high-paid', 'enterprise')),
  trust_label       TEXT NOT NULL CHECK (trust_label IN ('T0', 'T1', 'T2')),
  tos_risk          TEXT CHECK (tos_risk IN ('clear', 'grey-zone', 'high-risk')),
  quota_state       JSONB NOT NULL DEFAULT '{}'::jsonb,  -- RPM/TPM/日额/月额/信用池余量/observed_at（本体 QuotaState 内嵌化）
  health            JSONB NOT NULL DEFAULT '{}'::jsonb,  -- availability/latency_ms_p95/error_rate/last_failure_at/last_check_at（本体 HealthSnapshot 内嵌化）
  accountable_person TEXT,                               -- 具名责任人（资产目录要件）；v0 引用角色槽，PSN 登记待本体轨道
  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  retired_at        TIMESTAMPTZ,
  -- R-POOL-COMPLIANCE（3.4）：灰区/高风险账号一律强制 T0 标签，DB 约束层钉死
  CONSTRAINT grey_zone_forced_t0
    CHECK (NOT (tos_risk IN ('grey-zone', 'high-risk') AND trust_label <> 'T0'))
);

-- ============ 3.1 RoutingPolicy ============
CREATE TABLE IF NOT EXISTS pool_routing_policies (
  id                    TEXT PRIMARY KEY CHECK (id ~ '^RTP-[0-9]{4,}$'),
  name                  TEXT NOT NULL,
  target_capability     TEXT,
  allowed_cost_tiers    TEXT[] NOT NULL DEFAULT '{}',   -- S5 批准的成本等级白名单（3.5：禁止自动跳未批准等级）
  min_trust_level       TEXT CHECK (min_trust_level IN ('T0', 'T1', 'T2')),
  max_data_sensitivity  TEXT CHECK (max_data_sensitivity IN ('public', 'internal', 'customer_sensitive')),
  quota_constraints     JSONB,
  calibration_domain_ref TEXT,                          -- R-POOL-CALIB：关联校准域 CAL-xxxx（v0 未建，留引用位）
  fallback_chain        TEXT[] NOT NULL DEFAULT '{}',   -- 降级链（有序，3.5）；权威定义在 pools/degradation.yaml
  budget_cap            JSONB,                          -- R-POOL-BUDGET：闭环级预算上限
  virtual_key_isolated  BOOLEAN NOT NULL DEFAULT true,  -- R-POL-03：每执行单元独立虚拟 key 限额
  suspension_on_timespan_expiry BOOLEAN NOT NULL DEFAULT true,  -- 3.5/MET-01：决断时距耗尽⇒挂起
  approval_ref          TEXT,
  accountable_person    TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ 3.1 LogicalEndpoint ============
CREATE TABLE IF NOT EXISTS pool_endpoints (
  id                 TEXT PRIMARY KEY CHECK (id ~ '^EPL-[0-9]{4,}$'),
  endpoint_name      TEXT NOT NULL UNIQUE,
  trust_label        TEXT NOT NULL CHECK (trust_label IN ('T0', 'T1', 'T2')),
  bound_account_ids  TEXT[] NOT NULL DEFAULT '{}',      -- 绑定账号集合（ACC-xxxx）
  routing_policy_id  TEXT REFERENCES pool_routing_policies(id),
  litellm_model      TEXT,                              -- LiteLLM 投影 model_name（SEL-05 §3.7：控制面权威→LiteLLM 投影）
  accountable_person TEXT,
  notes              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  retired_at         TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_pool_endpoints_trust ON pool_endpoints (trust_label);
CREATE INDEX IF NOT EXISTS ix_pool_accounts_provider ON pool_accounts (provider);

-- ============ 种子数据（全 mock，零真实密钥） ============
BEGIN;

INSERT INTO pool_providers (id, name, mode, tos_risk_matrix_ref, data_usage_terms_summary, notes) VALUES
  ('PRV-0001', 'mock-freelayer', 'mock_response',
   'gov-infra-repo/pools/README.md#tos-风险矩阵-v0',
   '模拟免费层条款：供应商可能用提交数据训练、产能无保障（INFRA 3.2 T0 定级依据的 mock 语义）',
   'v0 纯 mock：不发出任何真实上游调用'),
  ('PRV-0002', 'mock-paidlayer', 'mock_response',
   'gov-infra-repo/pools/README.md#tos-风险矩阵-v0',
   '模拟付费层条款：合同明确数据不用途、产能有 SLA（INFRA 3.2 T1 定级依据的 mock 语义）',
   'v0 纯 mock：不发出任何真实上游调用')
ON CONFLICT (id) DO NOTHING;

INSERT INTO pool_accounts
  (id, name, provider, credential_ref, cost_tier, trust_label, tos_risk,
   quota_state, health, accountable_person, notes) VALUES
  ('ACC-0001', 'mock-free-01', 'PRV-0001', 'openbao://kv/dga/pool/mock-free-01',
   'free', 'T0', 'clear',
   '{"rpm_limit": 60, "tpm_limit": 10000, "daily_quota": 100.0, "monthly_quota": 1000.0, "credit_balance": 0, "observed_at": "2026-09-06T00:00:00Z"}'::jsonb,
   '{"available": true, "latency_ms_p95": 50, "error_rate": 0.0, "last_failure_at": null, "last_check_at": "2026-09-06T00:00:00Z"}'::jsonb,
   'S5(角色引用；具名PSN待本体轨道登记)',
   '免费层模拟账号。T0 定级：TOS 下数据可能用于训练（mock 语义）'),
  ('ACC-0002', 'mock-paid-01', 'PRV-0002', 'openbao://kv/dga/pool/mock-paid-01',
   'low-paid', 'T1', 'clear',
   '{"rpm_limit": 300, "tpm_limit": 90000, "daily_quota": 5.0, "monthly_quota": 50.0, "credit_balance": 20.0, "observed_at": "2026-09-06T00:00:00Z"}'::jsonb,
   '{"available": true, "latency_ms_p95": 200, "error_rate": 0.0, "last_failure_at": null, "last_check_at": "2026-09-06T00:00:00Z"}'::jsonb,
   'S5(角色引用；具名PSN待本体轨道登记)',
   '付费层模拟账号。T1 定级：模拟合同明确数据不用途+SLA'),
  ('ACC-0003', 'mock-gray-01', 'PRV-0001', 'openbao://kv/dga/pool/mock-gray-01',
   'free', 'T0', 'grey-zone',
   '{"rpm_limit": 30, "tpm_limit": 5000, "daily_quota": 50.0, "monthly_quota": 500.0, "credit_balance": 0, "observed_at": "2026-09-06T00:00:00Z"}'::jsonb,
   '{"available": true, "latency_ms_p95": 80, "error_rate": 0.0, "last_failure_at": null, "last_check_at": "2026-09-06T00:00:00Z"}'::jsonb,
   'S5(角色引用；具名PSN待本体轨道登记)',
   '条款灰区账号（多账号轮换条款未明确——3.4 场景的 mock 复现）。灰区可否使用由 S5 裁决，agent 发现灰区即升级，不得自行判定；DB 约束强制 T0。仅供隔离端点 gray-probe 做负面测试')
ON CONFLICT (id) DO NOTHING;

INSERT INTO pool_routing_policies
  (id, name, target_capability, allowed_cost_tiers, min_trust_level, max_data_sensitivity,
   quota_constraints, calibration_domain_ref, fallback_chain, budget_cap,
   virtual_key_isolated, suspension_on_timespan_expiry, approval_ref, accountable_person) VALUES
  ('RTP-0001', 'pool-v0-default', 'chat-completion',
   ARRAY['free', 'low-paid'],
   'T0', 'customer_sensitive',
   '{"shared_daily_usd": 1.0, "note": "v0 mock 配额，仅演示账本结构"}'::jsonb,
   NULL,
   -- 降级链（3.5 语义，权威定义与解释见 pools/degradation.yaml）：
   --   T1 主力 → T1 备用(未接入) → 低成本付费(未接入) → 队列/挂起 → 升级 S5
   --   T0（free-workhorse）不在本链内：免费层不作任何客户链路的降级终点（钉死，见 degradation.yaml）
   ARRAY['paid-judge', 't1-backup:未接入', 'low-cost-paid:未接入', 'QUEUE/SUSPEND', 'ESCALATE-S5'],
   '{"max_budget_usd": 1.0, "budget_duration": "30d", "note": "v0 mock 上限，本机占位非真实预算"}'::jsonb,
   true, true, 'S5-PENDING-DEFAULTS 默认方案先行，待追认', 'S5(角色引用；具名PSN待本体轨道登记)')
ON CONFLICT (id) DO NOTHING;

INSERT INTO pool_endpoints
  (id, endpoint_name, trust_label, bound_account_ids, routing_policy_id, litellm_model,
   accountable_person, notes) VALUES
  ('EPL-0001', 'free-workhorse', 'T0', ARRAY['ACC-0001'], 'RTP-0001', 'mock-free',
   'S5(角色引用；具名PSN待本体轨道登记)',
   '免费层作业端点：仅公开数据/内部低敏/合成测试数据（3.2 T0 白名单）'),
  ('EPL-0002', 'paid-judge', 'T1', ARRAY['ACC-0002'], 'RTP-0001', 'mock-paid',
   'S5(角色引用；具名PSN待本体轨道登记)',
   '付费判定端点：一般客户业务数据（3.2 T1）；客户链路降级链主力起点'),
  ('EPL-0003', 'gray-probe', 'T0', ARRAY['ACC-0003'], 'RTP-0001', 'mock-free',
   'S5(角色引用；具名PSN待本体轨道登记)',
   '灰区隔离端点：仅负面测试/合规演示用（负面测试③），禁止承接生产流量（3.4；任务种子只列两个端点，本端点为测试③所需而新增，已登记）')
ON CONFLICT (id) DO NOTHING;

COMMIT;
