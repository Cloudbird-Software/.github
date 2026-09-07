-- SEL-01-ddl-patch.sql · gen-sqlddl 产物 → PostgreSQL 16.9 最小兼容补丁（登记件）
-- 日期：2026-09-06 | 轨道：控制面 M1 | 产物：schemas/generated/dga-ontology.sql（66,995B，38 CREATE TABLE）
--
-- == 重建序列（从零复现） ==
--   1. linkml gen-sqlddl 重新生成 schemas/generated/dga-ontology.sql
--   2. 应用下方【预载变换】两处（机械 sed，逐字命令已登记）
--   3. psql -U dga -d dga_control -f schemas/generated/dga-ontology.sql
--   4. psql -U dga -d dga_control -f catalog/sel/SEL-01-ddl-patch.sql   ← 本文件可执行部分
--
-- == 预载变换（已对生成物就地修正，原因如下） ==
-- [T1] DATETIME → TIMESTAMP（39 处）
--      原因：gen-sqlddl 输出 SQLAlchemy 泛型类型 DATETIME，PostgreSQL 无此类型名
--      （CREATE TABLE 直接报 type "datetime" does not exist）。机械替换，语义等价。
--      sed -i 's/DATETIME/TIMESTAMP/g' dga-ontology.sql
-- [T2] 删除 ClosureUnit 建表块内两行前向 FK：
--        FOREIGN KEY(intent_id) REFERENCES "Intent" (id),
--        FOREIGN KEY(accountability_id) REFERENCES "AccountabilityLink" (id)
--      原因：生成器按类名字序排表，Intent（第 17 张）/AccountabilityLink（第 8 张）
--      晚于 ClosureUnit（第 7 张）建表；PostgreSQL 在 CREATE TABLE 时即解析 FK 目标，
--      前向引用报 relation does not exist（SQLite 不即时解析故生成器未暴露）。
--      两约束由本文件可执行部分以 DEFERRABLE 重建（见 [F1]）。
--      sed -i '/^\tFOREIGN KEY(intent_id) REFERENCES "Intent" (id),$/d; /^\tFOREIGN KEY(accountability_id) REFERENCES "AccountabilityLink" (id)$/d' dga-ontology.sql
--      ⚠ 删除后 CapabilityEntity/parent 两条 FK 尾逗号残留 → 语法错误，须连带修正（[T3]）：
--      sed -i 's/\tFOREIGN KEY(parent) REFERENCES "ClosureUnit" (id),/\tFOREIGN KEY(parent) REFERENCES "ClosureUnit" (id)/' dga-ontology.sql
-- [T3] 即上条 ⚠：FOREIGN KEY(parent) REFERENCES "ClosureUnit" (id), 行尾逗号删除。
--      原因：T2 删掉块内最后两行使前一行的逗号成为 `)` 前悬空逗号（首载实测报
--      syntax error at or near ")"，ON_ERROR_STOP 中断，已清场重载验证通过）。
--
-- == 未修正项（核实过、非问题，登记防复检） ==
-- [N1] 任务书预警的"type 字段名冲突"：本版 DDL 无裸列名 type（仅 asset_type/executor_type/
--      evidence_type 等复合名），未触发；如后续本体加裸 type 列需再评（PG 中 type 非保留字）。
-- [N2] SecurityMark/Budget/QuotaState/HealthSnapshot/DecisionOption 的 id 为 INTEGER PK：
--      LinkML mixin/内联类的整型主键，PG 合法；控制面 v0 API 侧自行供应序列值。
-- [N3] 已存在的 4 张 snake_case 池表（pool_accounts 等）为先期轨道遗留，与本体 CamelCase
--      引号表名无冲突，保留不动。
-- [N4] NOTICE: identifier "...OriginalProjection_id" will be truncated：PG 标识符 63 字节上限，
--      长索引名被截断（首载实测 1 处）。截断后仍唯一可建，不修正；生成器可考虑缩短 ix_ 前缀。
--
-- == 可执行部分：延迟约束重建 ==

-- [F1] 重建 ClosureUnit 两条外键（T2 删除项）。声明为 DEFERRABLE INITIALLY DEFERRED：
--      ClosureUnit.accountability_id ↔ AccountabilityLink.closure 是真环（互指），
--      控制面 API 登记闭环需在同一事务先插 AccountabilityLink 再插 ClosureUnit，
--      立即校验下无论谁先都违反对方 FK；延迟到 COMMIT 统一校验即两全。
--      这是 R-GOV-03 双层校验的 DB 侧成立前提（NOT NULL 仍即时强制，不受延迟影响）。
--      （DROP IF EXISTS + ADD = 本文件可重复执行，重建序列第 4 步可安全重放）
ALTER TABLE "ClosureUnit" DROP CONSTRAINT IF EXISTS fk_ClosureUnit_intent_id;
ALTER TABLE "ClosureUnit"
    ADD CONSTRAINT fk_ClosureUnit_intent_id
    FOREIGN KEY (intent_id) REFERENCES "Intent" (id)
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE "ClosureUnit" DROP CONSTRAINT IF EXISTS fk_ClosureUnit_accountability_id;
ALTER TABLE "ClosureUnit"
    ADD CONSTRAINT fk_ClosureUnit_accountability_id
    FOREIGN KEY (accountability_id) REFERENCES "AccountabilityLink" (id)
    DEFERRABLE INITIALLY DEFERRED;

-- [F2] AccountabilityLink.closure 的内联 FK（生成物自动命名 AccountabilityLink_closure_fkey）
--      改为 DEFERRABLE INITIALLY DEFERRED，与 [F1] 配对成完整延迟环。
ALTER TABLE "AccountabilityLink" DROP CONSTRAINT IF EXISTS "AccountabilityLink_closure_fkey";
ALTER TABLE "AccountabilityLink" DROP CONSTRAINT IF EXISTS fk_AccountabilityLink_closure;
ALTER TABLE "AccountabilityLink"
    ADD CONSTRAINT fk_AccountabilityLink_closure
    FOREIGN KEY (closure) REFERENCES "ClosureUnit" (id)
    DEFERRABLE INITIALLY DEFERRED;

-- [F3] 控制面运行时扩展表（cp_ 前缀 = 控制面自有，非本体类，gen-sqlddl 不产出）：
--      S5DecisionCard 无 addressee 槽位，而 R-SEC-04 最小形态（错人 resolve → 403）必须
--      知道"卡片发给谁"。本体加槽属 S5 裁决，v0 先落控制面自有表，待本体升级后迁移。
CREATE TABLE IF NOT EXISTS cp_decision_addressee (
    card_id TEXT PRIMARY KEY REFERENCES "S5DecisionCard" (id),
    addressee TEXT NOT NULL REFERENCES "Person" (id),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
