-- ddl.sql · DGA-INFRA M3 首条流程副作用证据表（幂等 DDL，可重复执行）
-- 规则锚点：R-FLOW-03（幂等键）/ R-FLOW-04（崩溃恢复已发生|未发生|不确定可区分）
-- 纪律：PG 新表独立前缀 wf_，不与本体 CamelCase 表、pool_/cp_ 表混用。
-- 数据库：dga_control @ 127.0.0.1:5432（user dga）

-- 1) 段事件表：每个 activity 对每 (workflow_id, activity) 至多一行副作用证据。
--    status: pending=已执行未确认（进行中或中断，"不确定"态）| done=已发生已确认 | suspended=挂起（MET-01 时距到期）
--    UNIQUE(workflow_id, activity) 是"每段只 1 行"的硬保证：重试/重放/二次 start 都走 ON CONFLICT DO NOTHING。
CREATE TABLE IF NOT EXISTS wf_run_events (
  id          BIGSERIAL PRIMARY KEY,
  workflow_id TEXT NOT NULL,
  activity    TEXT NOT NULL,
  segment_no  INT  NOT NULL DEFAULT 0,           -- 0 = 审批等待标记（approval_wait），1..6 = 六段
  title       TEXT NOT NULL DEFAULT '',
  status      TEXT NOT NULL CHECK (status IN ('pending', 'done', 'suspended')),
  detail      JSONB NOT NULL DEFAULT '{}'::jsonb,
  run_id      TEXT NOT NULL DEFAULT '',           -- 首次写入该行的 Temporal run_id
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT wf_run_events_wf_act_unique UNIQUE (workflow_id, activity)
);

-- 2) 幂等表：每个 activity 的重试去重权威源（workflow_id + activity 名唯一键）。
--    status: running=已领取副作用未完成（中断后由恢复路径做结果核对）| done=副作用已完成，重入直接跳过
CREATE TABLE IF NOT EXISTS wf_activity_idem (
  workflow_id TEXT NOT NULL,
  activity    TEXT NOT NULL,
  status      TEXT NOT NULL CHECK (status IN ('running', 'done')),
  result      JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT wf_activity_idem_wf_act_unique UNIQUE (workflow_id, activity)
);

CREATE INDEX IF NOT EXISTS wf_run_events_wf_idx    ON wf_run_events (workflow_id);
CREATE INDEX IF NOT EXISTS wf_activity_idem_wf_idx ON wf_activity_idem (workflow_id);
