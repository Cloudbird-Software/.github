# M7 成本熔断策略 spec 草案

> **工作层草案，进治理仓须 C1 路径（PR + ADR + owner review）。**
> 本文档为 DGA-INFRA M7 成本熔断策略的完整 spec，非治理仓正本。
> 起草日期：2026-09-08。
> 对齐 `.github` 仓 cost-check 预算四元组硬停传统（`governance/cost-check.sh` + `governance/wave_schema.py` + `governance/policy/automation-limits.yaml`），并严格引用 DGA-INFRA v1.0 原文编号。

---

## 1. 目标与范围

### 1.1 来源锚点

- **DGA-INFRA §3.6 R-POOL-BUDGET**：闭环级预算上限（capability policy 声明）；全司日熔断 / 月熔断（超限自动全局降级或挂起，通知 S5）；熔断事件本身入证据流——成本维度的爆炸半径控制。
- **DGA-INFRA §3.7 R-POOL-QUOTA**：账本记录的用量 vs 供应商面板实际用量，定期抽查，误差超阈值报警。池自身是一个六元组闭环单元：有 spec（路由策略）、eval（配额准确性 / 故障转移时延 / 错误率）、证据（调度日志）、责任人（S5）。
- **DGA-INFRA §3.5 R-POOL-DEGRADE**：T1 主力付费 → T1 备用付费 → 低成本付费 → [队列等待 / 任务挂起] → 升级 S5。免费层（T0）只承接 T0 任务，不作为任何客户链路的降级终点。禁止自动跳到 S5 未批准的成本等级。等待超过闭环授权的决断时距 ⇒ 挂起 [MET-01]。
- **DGA-INFRA §3.8 R-POOL-CALIB**：每份 eval 校准必须声明其校准域：覆盖的模型集合（池组成快照）+ Spec/Harness 版本 + 观察窗口。池组成变化（新增 / 移除 / 权重调整被校准域覆盖的模型）⇒ 触发相关闭环的漂移重估工作流。
- **DGA-INFRA §3.9 R-POOL-EVID**：故障转移时延、端点错误率、配额误差、熔断触发次数——池的运行度量进入狗狗公示仪表（[RULE-05] 的资产展示）。
- **DGA-INFRA §6 里程碑表 M7 行**：池治理完善——池组成变更 → 漂移重估工作流；成本熔断；时距到期自动挂起。人为注入池变更触发重估；注入超预算触发熔断。
- **DGA-INFRA §5 R-POL-02 / R-POL-03**：子任务权限 ≤ 父任务；拆十个 agent 不获得十倍预算；重建 Run 不得延长无人复核期限；恢复检查点须重验当前授权。池路由的虚拟 key 限额落实 R-POL-02（每个执行单元独立限额 key）。
- **DGA-INFRA §5 R-EVID-05**：证据缺失是治理异常，与业务失败 / 结果不确定 / 判定器失效区分登记；没有失败证据 ≠ 成功。
- **DGA-INFRA 第 1 章 权威源表**：资源池账本（账号、配额、健康、信任标签） = 控制面 DB。
- **cost-check 预算四元组硬停传统**：
  - `governance/wave_schema.py` L24：budget 块四元组 `usd` / `tokens` / `wallclock_sec` / `human_minutes`（数值 ≥0，至少一项）；`on_exceed ∈ {hard-stop, warn}`（缺省 hard-stop——声明预算即默认硬停语义，BEH-07 / ADR-0040 复位流程不变）。
  - `governance/cost-check.sh` L71-78：Actions 分钟 / LLM token 通道各自承载 `quota_per_month` / `warn_pct` / `hardstop_pct` / `data_source` 四元组；硬停档触发时执行同一硬停三件套（置 `AUTO_MERGE_DISABLED` 变量 + 撤全部 auto-merge + P0 issue，label `cost-circuit-breaker`）。
  - `governance/cost-check.sh` L202-257：波次预算通道（W2-C3 .github#414，BEH-07 / ADR-0103）对 budget 四元组执行统一账本 subject 聚合；hard-stop 卡超限 → 与 Actions / LLM 同一硬停档三件套执法。
  - `governance/cost-check.sh` L438-456：复位仅人工（owner PATCH/DELETE 变量 + P0 issue 留评论）；cost-check 观察到"变量已复位且用量 <100%"后自动关闭 P0 issue。
  - `governance/cost-check.sh` L459-474：INFRA 故障通道（exit 2）——fail-closed，未盲置熔断，假熔断要求人工复位，会停摆整条流水线（ADR-0040 决策 5）。

### 1.2 本草案覆盖

| 件 | 定位 | 本文件处理方式 |
|----|------|----------------|
| 池组成变更 schema（`PoolCompositionChange`） | 核心 | §2 全文详述 |
| 成本熔断策略（通道 / 阈值 / 状态机 / 执法动作 / fail-closed） | 核心 | §3 全文详述 |
| 池健康 schema 扩展（`PoolHealthSnapshot`） | 核心 | §4 全文详述 |
| 故障演练方向 | 接口边界 | §5 全文详述 |
| 与 M5/M6 术语对齐 | 接口边界 | §6 全文详述 |
| 验收谓词与负面测试 | 验收 | §7 全文 |

### 1.3 不覆盖

- 实现代码、控制面 API 路由层实现、Temporal workflow 实现代码（属于第二波）。
- 供应商面板实际用量拉取脚本（`governance/cost-check.sh` 已为 .github 仓实现，本草案只抽象其策略语义到 DGA 池层）。
- 对象存储具体选型与 WORM 桶配置（SEL-07）。

---

## 2. 池组成变更 schema（`PoolCompositionChange`）

### 2.1 设计意图

DGA-INFRA §3.8 R-POOL-CALIB 明确：「池组成变化（新增 / 移除 / 权重调整被校准域覆盖的模型）⇒ 触发相关闭环的漂移重估工作流」。M7 验收要点进一步要求「池组成变更 → 漂移重估工作流」。

当前 `pools.yaml` 已有 `PoolAccount`（ACC-xxxx）、`LogicalEndpoint`（EPL-xxxx）、`RoutingPolicy`（RTP-xxxx）、M5 草案已有 `ExecutionEnvironment`（ENV-xxxx）。池组成变更事件横跨上述四类实体，本草案以 `PoolCompositionChange` 统一承载，确保每次变更可审计、可追溯、可触发漂移重估。

### 2.2 类定义（LinkML 扩展草案）

```yaml
classes:
  PoolCompositionChange:
    class_uri: dga:PoolCompositionChange
    mixins:
      - SecurityMark
    slots:
      - id
      - change_type
      - target_type
      - target_id
      - snapshot_before
      - snapshot_after
      - triggered_by
      - observed_at
      - calibration_domain_ref
      - evidence_ref
    slot_usage:
      id:
        pattern: "^PCC-[0-9]{4,}$"
    attributes:
      change_id:
        range: string
        required: true
        identifier: true
        description: >
          池组成变更唯一 ID（PCC-xxxx）。变更事件本身的身份标识，
          与触发漂移重估的 CalibrationDomain id 不同源。

      change_type:
        range: ChangeType
        required: true
        description: >
          变更类型（ADD / REMOVE / WEIGHT_ADJUST / TRUST_ADJUST /
          ISOLATION_CHANGE / HEALTH_DEGRADE / QUOTA_DOWNGRADE / RETIRE）。
          每种类型对应不同的漂移重估触发语义（见 2.4 表）。

      target_type:
        range: PoolTargetType
        required: true
        description: >
          变更作用的目标实体类型（PROVIDER / ACCOUNT / ENDPOINT /
          ROUTING_POLICY / EXECUTION_ENVIRONMENT）。
          与 target_id 联合定位池组成中的具体对象。

      target_id:
        range: string
        required: true
        description: >
          目标实体 ID（PRV-xxxx / ACC-xxxx / EPL-xxxx / RTP-xxxx / ENV-xxxx）。
          必须存在于控制面 DB 资产目录且 retired_at 为空（除 RETIRE 类型）。

      snapshot_before:
        range: string
        required: true
        description: >
          变更前池组成快照（JSON 文本；至少包含目标实体受影响字段的旧值）。
          对齐 DGA-INFRA 3.8 CalibrationDomain.model_set_snapshot 的"池组成快照"语义。

      snapshot_after:
        range: string
        required: true
        description: >
          变更后池组成快照（JSON 文本；至少包含目标实体受影响字段的新值）。

      triggered_by:
        range: string
        required: true
        description: >
          触发源（human / admin / automation / drift-reassessor）。
          对齐 DGA-INFRA 3.1 每个池对象是资产目录中的正式资产；具名责任人制度（R-GOV-03）。

      observed_at:
        range: datetime
        required: true
        description: >
          变更被观测到的时间（由控制面 DB 或采集器写入，非操作者本地时钟）。

      calibration_domain_ref:
        range: string
        required: true
        description: >
          关联的校准域 ID（CAL-xxxx，DGA-INFRA 3.8 R-POOL-CALIB）。
          漂移检测器消费本字段，将变更事件映射到受影响的 CalibrationDomain。

      evidence_ref:
        range: string
        description: >
          关联的证据记录 ID（EVD-xxxx；DGA-INFRA 5 R-EVID-01）。
          变更事件本身须入证据流（EvidenceEntity.evidence_type = POLICY_DECISION 或新增 COST_EVENT）。
```

### 2.3 枚举扩展草案

```yaml
enums:
  ChangeType:
    description: 池组成变更类型（M7 新增；漂移重估触发源分类）。
    permissible_values:
      ADD:
        description: 新增实体（新账号 / 新端点 / 新路由策略）。
      REMOVE:
        description: 移除实体（退役账号 / 下线端点）。
      WEIGHT_ADJUST:
        description: 权重调整（如 endpoint bound_accounts 列表变更、fallback_chain 顺序变更）。
      TRUST_ADJUST:
        description: 信任标签调整（如 trust_label T1→T2 或 T2→T1；R-POOL-TRUST 敏感变更）。
      ISOLATION_CHANGE:
        description: 隔离等级变化（如 ExecutionEnvironment.isolation_level vm→container；R-POOL-DATA）。
      HEALTH_DEGRADE:
        description: 健康恶化（如 availability_pct 连续低于阈值；R-POOL-EVID）。
      QUOTA_DOWNGRADE:
        description: 配额下调（如 rpm_limit / daily_quota / monthly_quota 下调超过阈值；R-POOL-QUOTA）。
      RETIRE:
        description: 实体退役（retired_at 置位；退役前须完成检查点清理与路由摘除）。

  PoolTargetType:
    description: 池组成变更作用的目标实体类型。
    permissible_values:
      PROVIDER:
        description: 供应商（PRV-xxxx）。
      ACCOUNT:
        description: 池账号（ACC-xxxx）。
      ENDPOINT:
        description: 逻辑端点（EPL-xxxx）。
      ROUTING_POLICY:
        description: 路由策略（RTP-xxxx）。
      EXECUTION_ENVIRONMENT:
        description: 执行环境（ENV-xxxx；M5 新增实体）。
```

### 2.4 变更类型与漂移重估触发映射

| ChangeType | 漂移语义 | 触发漂移重估条件 |
|------------|----------|------------------|
| ADD | 池组成新增元素，校准域覆盖范围扩大 | 新增实体被任意 CalibrationDomain.model_set_snapshot 覆盖 |
| REMOVE | 池组成元素移除，校准域覆盖范围缩小 | 被移除实体曾出现在 CalibrationDomain.model_set_snapshot 中 |
| WEIGHT_ADJUST | 池组成分布参数变化 | 调整对象为 LogicalEndpoint.bound_accounts 或 RoutingPolicy.fallback_chain 且变化幅度超过阈值（阈值由 ADR 定案） |
| TRUST_ADJUST | 环境可处理的数据敏感度上限变化 | trust_label 下调（如 T2→T1）或上调超过一个等级（如 T0→T2 需 S5 批准）；R-POOL-TRUST |
| ISOLATION_CHANGE | 环境安全边界收缩 | isolation_level 降级（如 vm→container→process）；R-POOL-DATA |
| HEALTH_DEGRADE | 环境可靠性分布参数变化 | availability_pct 低于阈值（如 <50%）或 error_rate 突增超过阈值 |
| QUOTA_DOWNGRADE | 环境产能分布参数变化 | rpm_limit / daily_quota / monthly_quota 下调超过历史观测窗口统计分布 |
| RETIRE | 实体永久退出池组成 | retired_at 置位前必须完成检查点清理与路由摘除（R-POOL-DATA 延伸）；退役事件本身入证据流 |

### 2.5 与 M5 执行环境注册表的联动

M5 `env-registry-draft.md` §5 已定义 `ExecutionEnvironment` 属性变更与漂移重估的联动机制。本节的 `PoolCompositionChange` 将 M5 表 5.1 的「漂移语义」提升为正式事件对象：

- `ExecutionEnvironment.trust_label` 变更 → `ChangeType.TRUST_ADJUST`
- `ExecutionEnvironment.isolation_level` 变更 → `ChangeType.ISOLATION_CHANGE`
- `ExecutionEnvironment.health` 恶化 → `ChangeType.HEALTH_DEGRADE`
- `ExecutionEnvironment.quota_state` 下调 → `ChangeType.QUOTA_DOWNGRADE`

联动机制保持不变：`ExecutionEnvironment` 属性变更事件 → 注册表审计日志 → 漂移检测器消费 `calibration_domain_ref` → 若变化属性在覆盖范围内 → 触发漂移重估工作流（M7 Temporal defs/activities 文字级 mock）。

### 2.6 与 M6 证据契约的衔接

- `PoolCompositionChange.evidence_ref` 指向 `EvidenceEntity.id`（EVD-xxxx，M6 已有定义）。
- 变更事件入证据流时，`EvidenceEntity.evidence_type` 建议扩展枚举值为 `POOL_COMPOSITION_CHANGE`（进治理仓须登记 `enums.yaml`）。
- 证据记录必须携带 `calibration_domain_ref`（R-EVID-04 / R-POOL-CALIB），确保漂移重估工作流可溯源。

---

## 3. 成本熔断策略

### 3.1 设计意图

DGA-INFRA §3.6 R-POOL-BUDGET 定义成本熔断为「闭环级预算上限（capability policy 声明）；全司日熔断 / 月熔断（超限自动全局降级或挂起，通知 S5）；熔断事件本身入证据流」。本策略将 `.github` 仓 `cost-check.sh` 的预算四元组硬停传统（Actions 分钟 / LLM token / 波次预算三通道，各承载 quota / warn / hardstop / data_source 四元组；硬停三件套；fail-closed 语义）提升为 DGA 控制面池治理层的正式策略。

### 3.2 预算四元组统一 schema

```yaml
classes:
  BudgetQuadruple:
    class_uri: dga:BudgetQuadruple
    description: >
      成本预算四元组（对齐 cost-check wave_schema.py 预算四元组传统 +
      automation-limits.yaml cost 通道声明）。一个 BudgetQuadruple 可挂接在
      RoutingPolicy.budget_cap（闭环级）或全司级全局预算声明上。
    attributes:
      usd_cap:
        range: float
        description: 美元预算上限（wave 预算四元组第一元；DGA-INFRA §1 权威源表：已接受承诺、有效授权、判定状态、闭环登记 = 控制面 DB）。
      tokens_cap:
        range: integer
        description: token 预算上限（wave 预算四元组第二元）。
      wallclock_sec_cap:
        range: float
        description: 墙钟秒数上限（wave 预算四元组第三元）。
      human_minutes_cap:
        range: float
        description: 人工分钟上限（wave 预算四元组第四元；当前无账本源，只声明不判定——对齐 wave_schema.py UNENFORCED_KEYS human_minutes 语义）。
      on_exceed:
        range: OnExceed
        description: 超限处置（hard-stop / warn；缺省 hard-stop——声明预算即默认硬停语义，BEH-07 / ADR-0040 复位流程不变）。

  CostBudgetChannel:
    class_uri: dga:CostBudgetChannel
    description: >
      成本预算通道（对齐 cost-check.sh 三通道：Actions 分钟 / LLM token / 波次预算）。
      每个闭环（RoutingPolicy）可声明自身适用的通道子集；未声明通道 = 不受该通道预算约束。
    attributes:
      channel_type:
        range: CostChannelType
        required: true
        description: 通道类型（ACTIONS_MINUTES / LLM_TOKENS / WAVE_BUDGET）。
      quota_per_month:
        range: float
        required: true
        description: 月预算额度（cost-check automation-limits.yaml cost.actions_minutes.quota_per_month）。
      warn_pct:
        range: float
        required: true
        description: 告警百分比阈值（如 80；cost-check automation-limits.yaml cost.*.warn_pct）。
      hardstop_pct:
        range: float
        required: true
        description: 硬停百分比阈值（如 100；cost-check automation-limits.yaml cost.*.hardstop_pct）。
      data_source:
        range: CostDataSource
        description: 用量数据源（BILLING_API / CIW_METERING / PENDING）。
        required: true
      metering_repo:
        range: string
        description: 计量账本仓（data_source=CIW_METERING 时必填；对齐 automation-limits.yaml cost.llm_tokens.metering.repo）。
      metering_branch:
        range: string
        description: 计量账本分支（如 metering-ledger）。
      metering_code_path:
        range: string
        description: 归账引擎路径（如 pipeline/metering/metering.py）。
      verifier_deviation_pct:
        range: float
        description: verifier 档相对偏差阈值（%）；超出则该 run 判定作废转人工（automation-limits.yaml cost.llm_tokens.verifier.deviation_pct）。
      verifier_deviation_abs:
        range: integer
        description: verifier 档绝对偏差阈值（tokens）；超出则作废（automation-limits.yaml cost.llm_tokens.verifier.deviation_abs）。

enums:
  OnExceed:
    description: 超限处置（wave_schema.py ON_EXCEED；缺省 hard-stop = 声明预算即默认硬停语义）。
    permissible_values:
      HARD_STOP:
        description: 硬停（cost-check 硬停档执法）。
      WARN:
        description: 仅告警（cost-check 告警档执法）。

  CostChannelType:
    description: 成本预算通道类型（M7 新增；对齐 cost-check.sh 三通道）。
    permissible_values:
      ACTIONS_MINUTES:
        description: Actions 分钟用量通道（billing API 拉取）。
      LLM_TOKENS:
        description: LLM token 用量通道（ciw-metering 计量账本归账，ADR-0062）。
      WAVE_BUDGET:
        description: 波次预算通道（open type:card body budget 四元组对账，BEH-07 / ADR-0103）。

  CostDataSource:
    description: 用量数据源（M7 新增；对齐 cost-check.sh data_source 分支）。
    permissible_values:
      BILLING_API:
        description: GitHub billing API 直接拉取。
      CIW_METERING:
        description: CI-Workflows 仓 metering-ledger 分支 JSONL 记录经 metering.py aggregate 归账。
      PENDING:
        description: 数据源未就绪回滚形态（automation-limits.yaml 注释：回滚值；仅声明不告警）。
```

### 3.3 熔断状态机

本策略定义五态有限状态机，严格对齐 `cost-check.sh` 的告警档 / 硬停档 / 复位确认 / INFRA 故障四区间行为：

```text
                    ┌──────────┐
                    │ CLOSED   │  ← 正常调度态
                    └────┬─────┘
                         │ 任一通道 usage >= warn_pct
                         ▼
                    ┌──────────┐
                    │ WARNING  │  ← 告警态（开 cost-budget-warning 级 issue；不限制调度）
                    └────┬─────┘
                         │ 任一通道 usage >= hardstop_pct
                         │ 或任一 wave hard-stop 卡超限
                         ▼
                    ┌──────────┐
          ┌─────────│  OPEN    │◄────────┐
          │         └──────────┘          │
          │              │                │
          │              │ 复位确认        │
          │              ▼                │
          │         ┌──────────┐          │
          │         │ HALF_OPEN│──────────┘
          │         └──────────┘  一个完整检查周期用量 < hardstop_pct
          │              │
          │              ▼
          │         ┌──────────┐
          └─────────│ CLOSED   │
                     └──────────┘

任何态 → INFRA_FAIL：
  计量链断 / billing API 不可达 / 账本验链失败 / 配置解析异常
  → fail-closed（exit 2 语义）；不盲置熔断；不静默归零
```

**状态语义与执法动作**：

| 状态 | 调度影响 | 证据动作 | 告警 / 升级 | 对齐原文 |
|------|----------|----------|-------------|----------|
| `CLOSED` | 正常按 RoutingPolicy.allowed_cost_tiers 调度 | 无特殊 | 无 | cost-check.sh else 分支 |
| `WARNING` | 正常调度；不引入降级链 | 产出 `EvidenceEntity`（`evidence_type = POLICY_DECISION`，`content_digest` 含当前 usage_pct） | 开 / 更新 `cost-budget-warning` issue（label `cost-budget-warning`；同日去重）；通知 S5 仪表 | cost-check.sh L412-428 |
| `OPEN` | 冻结新任务派发；已在进行任务不受影响，但不得启动同闭环新 exec_id（等效 strip auto-merge） | 产出 `EvidenceEntity`（`evidence_type = COST_BREAKER_TRIP`，建议新增枚举值；`content_digest` 含超限通道、用量、阈值、calibration_domain_ref） | 置控制面 DB 全局熔断标志（等效 org 变量 `AUTO_MERGE_DISABLED=true`）；开 P0 issue（label `cost-circuit-breaker`）；路由层仅允许 `allowed_cost_tiers` 白名单内端点（R-POOL-DEGRADE） | cost-check.sh L373-410；DGA-INFRA §3.6 / §3.5 |
| `HALF_OPEN` | 限制性调度：仅允许 `allowed_cost_tiers` 白名单内端点；新 wave 卡需额外审批 | 持续记录 usage_pct 到 `PoolHealthSnapshot` | P0 issue 持续挂起，提醒复位 | cost-check.sh L438-447（熔断持续中） |
| `INFRA_FAIL` | 冻结依赖外部用量的调度决策（fail-closed 保守策略） | 产出 `EvidenceEntity`（`evidence_type = COST_INFRA_FAIL`） | 开 `cost-infra` issue（label `cost-infra`）；S5 仪表显示 INFRA 红 | cost-check.sh L459-474；R-EVID-05 |

### 3.4 预算四元组硬停执法细节

本策略继承 `cost-check.sh` 的「硬停档（任一指标 ≥hardstop_pct，或 wave hard-stop 卡超限）→ 同一硬停三件套」传统，并将执法主体从 GitHub org 变量提升为 DGA 控制面：

1. **置全局熔断标志**：控制面 DB `pool_breaker_state` 表写入 `OPEN`（字段 `breaker_id`、`breaker_state`、`tripped_at`、`tripped_channels`、`tripped_by`、`calibration_domain_ref`、`evidence_ref`）。等效于 `cost-check.sh` 的 `set_breaker()`（PATCH/POST org 变量）。
2. **冻结新派发**：Harness 路由层 / Action Registry 网关在派发前置检查读取 `breaker_state`；`OPEN` / `HALF_OPEN` 态拒绝新 `exec_id` 分配（等效 `strip_all_automerge`）。
3. **降级链收紧**：`OPEN` 态下，RoutingPolicy 路由谓词额外约束 `allowed_cost_tiers` 白名单（DGA-INFRA §3.5 R-POOL-DEGRADE：禁止自动跳到 S5 未批准的成本等级）。
4. **熔断事件入证据流**：`EvidenceEntity` 记录必须包含 `judge_model` / `judge_version` / `calibration_domain_id`（R-EVID-04 / R-POOL-CALIB）；`content_digest` 计算方式对齐 M5 `checkpoint-ext-draft.md` §4（键排序、无空格、NFC）。
5. **复位仅人工**：S5 / owner 通过控制面 API `POST /v1/pool/breaker/reset` 复位（需携带 approval_ref 授权引用，R-POL-02）。复位动作本身须留痕（`EvidenceEntity.evidence_type = COST_BREAKER_RESET`，`content_digest` 含复位操作者、时间戳、复位前 state）。控制面观察到 `breaker_state = CLOSED` 且所有通道 `usage_pct < hardstop_pct` 后，自动关闭 P0 级 S5 决策卡（等效 `cost-check.sh` L448-456 自动关 P0 issue）。

### 3.5 fail-closed 语义（对齐 cost-check INFRA 通道）

| 故障场景 | 策略行为 | 治理异常编码 | 对齐原文 |
|----------|----------|--------------|----------|
| billing API 不可达（Actions 分钟通道） | 该通道进入 `DATA_SOURCE_UNKNOWN`；usage_pct 置空；不参与硬停判定；记录 INFRA | `CB-INFRA-01` | cost-check.sh L139-143；automation-limits.yaml L87-89 |
| ciw-metering 账本拉取失败 / 解包失败 | 该通道进入 `DATA_SOURCE_UNKNOWN`；usage_pct 置空；不参与硬停判定；记录 INFRA | `CB-INFRA-02` | cost-check.sh L161-179；ADR-0062 |
| metering.py aggregate 链断 / 验链失败 | 该通道进入 `DATA_SOURCE_UNKNOWN`；usage_pct 置空；不参与硬停判定；记录 INFRA | `CB-INFRA-03` | cost-check.sh L193-194 |
| wave_schema.py 块非法 / 解析异常 | 该 wave 卡进入 `BUDGET_BLOCK_INVALID`；不参与硬停判定；记录 INFRA | `CB-INFRA-04` | wave_schema.py L237-243 |
| verifier 档偏差超阈值（相对>5% 或绝对>50 tokens） | 该 run 判定作废转人工；不调整 usage_pct；不触发熔断 | `CB-VERIFIER-01` | automation-limits.yaml cost.llm_tokens.verifier |
| 控制面 DB 写入失败 | 本轮熔断状态机保持在上一已知态；下一轮重试前不派发新任务（保守 fail-closed） | `CB-INFRA-05` | R-EVID-05 |

**禁止项（与 cost-check.sh 同纪律）**：
- 不静默归零（billing API 失败时 usage 不自动置 0）。
- 不盲熔断（INFRA 故障时不置 `OPEN`，避免假熔断导致整条流水线停摆）。
- 不采样 / 不截断用量记录（R-OBS-03：验证比计量固定口径；Goodhart 防护）。

### 3.6 与 M5 执行环境 / 虚拟 key 限额的联动

- M5 `ExecutionEnvironment.quota_state`（`env-registry-draft.md` §2.1 `quota_state` 字段）承载环境级配额摘要（rpm_limit / tpm_limit / daily_quota / monthly_quota / credit_balance）。
- `PoolCompositionChange.ChangeType.QUOTA_DOWNGRADE` 触发漂移重估候选（§2.4）。
- 成本熔断 `OPEN` 态与 M5 虚拟 key 限额双重执法：Harness 路由层先过 `breaker_state`，再过 `virtual_key` 限额扣减（R-POL-02 / R-POL-03）。
- 熔断复位后，虚拟 key 限额不自动恢复上月未使用额度（reset_by 人工只复位 breaker 标志，不清零历史用量累计）。

### 3.7 与 M6 证据契约的联动

- 熔断事件 `EvidenceEntity` 的 `evidence_type` 建议扩展：
  - `COST_BREAKER_TRIP`（熔断触发）
  - `COST_BREAKER_RESET`（熔断复位）
  - `COST_INFRA_FAIL`（基础设施故障）
  - `BUDGET_EXCEEDED`（wave 预算超限）
- `EvidenceEntity` 必须携带 `calibration_domain_ref`（R-EVID-04 / R-POOL-CALIB）和 `card_ref`（M6 `evidence-contract-draft.md` §2 `card_ref` 字段，格式 `owner/repo#issue`），确保 wave 预算超限卡可 join 到卡级 usage。
- `PoolHealthSnapshot` 中 `last_tripped_at` / `trip_count` 进入治理度量体系（R-OBS-02），狗粮公示仪表展示。

---

## 4. 池健康 schema 扩展（`PoolHealthSnapshot`）

### 4.1 设计意图

DGA-INFRA §3.9 R-POOL-EVID 要求「故障转移时延、端点错误率、配额误差、熔断触发次数——池的运行度量进入狗狗公示仪表」。M5 `env-registry-draft.md` §2.1 已有 `HealthSnapshot` 定义（availability_pct / latency_ms_p95 / error_rate / last_failure_at / last_check_at）。本草案在 `HealthSnapshot` 基础上增加成本熔断相关度量，形成 `PoolHealthSnapshot`。

### 4.2 扩展定义（LinkML 扩展草案）

```yaml
classes:
  PoolHealthSnapshot:
    class_uri: dga:PoolHealthSnapshot
    is_a: HealthSnapshot
    description: >
      池健康快照扩展（DGA-INFRA 3.9 R-POOL-EVID）。
      在既有 HealthSnapshot 基础上增加成本维度和熔断器状态，
      使池健康度量可直接驱动公示仪表与成本熔断状态机。
    attributes:
      # ---- 既有字段（pools.yaml HealthSnapshot，保持不变）----
      availability_pct:
        range: float
        description: 可用性（百分比 0-100）。
      latency_ms_p95:
        range: integer
        description: P95 延迟（毫秒）。
      error_rate:
        range: float
        description: 错误率（0-1）。
      last_failure_at:
        range: datetime
        description: 最近故障时间。
      last_check_at:
        range: datetime
        description: 最近健康检查时间（验证时间——资产目录要件）。

      # ---- M7 成本健康扩展 ----
      budget_utilization_pct:
        range: float
        description: >
          当前预算使用率（0-100；按最严格的通道 usage_pct 取值）。
          驱动 WARNING / OPEN 状态转换。
      quota_accuracy_pct:
        range: float
        description: >
          配额准确率（R-POOL-QUOTA：账本 vs 供应商面板定期抽查，误差超阈值报警）。
          100 = 账本与面板完全一致；<100 表示供应商面板用量 > 账本记录。
      metering_deviation_pct:
        range: float
        description: >
          计量偏差率（LLM token 账本 vs LLM response usage 字段）。
          超出 verifier.deviation_pct / deviation_abs 阈值 → 该 run 判定作废（automation-limits.yaml verifier 档）。
      circuit_breaker_state:
        range: BreakerState
        description: 当前熔断器状态（CLOSED / WARNING / OPEN / HALF_OPEN / INFRA_FAIL）。
      circuit_breaker_trips_mtd:
        range: integer
        description: 本月熔断触发次数（MTD = month-to-date；R-POOL-EVID）。
      last_tripped_at:
        range: datetime
        description: 最近一次熔断触发时间（OPEN 态写入；复位时清零）。
      last_reset_at:
        range: datetime
        description: 最近一次人工复位时间（HALF_OPEN → CLOSED 或 owner 主动复位）。
      current_usage_by_channel:
        range: string
        description: JSON 对象，键为 CostChannelType（ACTIONS_MINUTES / LLM_TOKENS / WAVE_BUDGET），值为 usage_pct（float）。无账本通道省略。
```

### 4.3 与现有 schema 的对齐

| 新增字段 | 对齐的现有 schema / DGA-INFRA 条目 | 说明 |
|----------|-------------------------------------|------|
| `budget_utilization_pct` | `RoutingPolicy.budget_cap`（`pools.yaml` L230）；DGA-INFRA 3.6 R-POOL-BUDGET | 最严格通道使用率，驱动状态机 |
| `quota_accuracy_pct` | `PoolAccount.quota_state`（`pools.yaml` L126）；DGA-INFRA 3.7 R-POOL-QUOTA | 账本 vs 面板抽查准确率 |
| `metering_deviation_pct` | `automation-limits.yaml` cost.llm_tokens.verifier | verifier 档偏差率 |
| `circuit_breaker_state` | `cost-check.sh` 硬停档 / 告警档 / INFRA 分支；DGA-INFRA 3.6 | 熔断器五态 |
| `circuit_breaker_trips_mtd` | DGA-INFRA 3.9 R-POOL-EVID「熔断触发次数」 | 运行度量 |
| `last_tripped_at` / `last_reset_at` | `cost-check.sh` L439-456 复位确认逻辑 | 时间锚点 |
| `current_usage_by_channel` | `automation-limits.yaml` cost 三通道 | 分通道使用率 |

**不臆造**：`PoolHealthSnapshot` 类不在当前 `schemas/include/pools.yaml` 中；本草案以「扩展草案」形式提出，进入治理仓须经 LinkML 变更评审（C1）。

---

## 5. 故障演练方向

DGA-INFRA §7 验收矩阵「池化七项」与 M8 验收套件要求「五类演练通过——撤权 / 崩溃 / 证据缺失 / S5 离线 / 池故障」。成本熔断策略的故障演练方向聚焦「池故障」与「成本维度的爆炸半径控制」两条主线。

### 5.1 演练矩阵

| 演练 ID | 演练名称 | 注入动作 | 预期判定 | 对齐原文 | 证据收据路径 |
|---------|----------|----------|----------|----------|--------------|
| DR-01 | 池组成变更触发漂移重估 | 人为注入 `PoolCompositionChange`（`ChangeType.TRUST_ADJUST` / `ISOLATION_CHANGE` / `HEALTH_DEGRADE`） | 漂移检测器消费 `calibration_domain_ref`，触发 `DriftReassessmentWorkflow`，产出 `EvidenceEntity.evidence_type = CALIBRATION_EVENT` | DGA-INFRA §3.8 R-POOL-CALIB；M7 验收要点 | `EVD-xxxx`，`content_digest` 含 change_id |
| DR-02 | Actions 分钟硬停 | 注入 `COST_USAGE_MINUTES_OVERRIDE = quota_per_month`（100%） | `OPEN` 态；控制面 DB `pool_breaker_state` 写入 `OPEN`；Harness 路由层拒绝新 exec_id；P0 issue（label `cost-circuit-breaker`）开立 | cost-check.sh L373-385；DGA-INFRA §3.6 | `EVD-xxxx`，`evidence_type = COST_BREAKER_TRIP` |
| DR-03 | LLM token 硬停 | 注入 `COST_LLM_TOKENS_USED_OVERRIDE = quota_per_month`（100%） | `OPEN` 态；与 DR-02 同档三件套执法；路由层收紧 `allowed_cost_tiers` | cost-check.sh L290-293；DGA-INFRA §3.5 R-POOL-DEGRADE | `EVD-xxxx` |
| DR-04 | Wave 预算 hard-stop 卡超限 | 在 open type:card body 注入 budget 块 `on_exceed: hard-stop`，用量 > 四元组阈值 | `OPEN` 态；与 DR-02 同一硬停档（BEH-07） | wave_schema.py L202-257；cost-check.sh L300-304 | `EVD-xxxx`，`card_ref = owner/repo#issue` |
| DR-05 | INFRA 故障 fail-closed | 中断 billing API / 删除 metering-ledger 分支 / 破坏 wave_schema.py 环境 | `INFRA_FAIL` 态；本轮 exit 2 变红；不盲置熔断；`cost-infra` issue 开立 | cost-check.sh L459-474；R-EVID-05 | `EVD-xxxx`，`evidence_type = COST_INFRA_FAIL` |
| DR-06 | 人工复位流程 | S5 owner 执行 `POST /v1/pool/breaker/reset`（携带 approval_ref） | `HALF_OPEN` → `CLOSED`；一个完整检查周期用量 < hardstop_pct；P0 issue 自动关闭；`EvidenceEntity.evidence_type = COST_BREAKER_RESET` | cost-check.sh L448-456；ADR-0040 复位流程 | `EVD-xxxx` |
| DR-07 | 并发多通道超限 | 同时注入 Actions = 100% + Wave hard-stop 卡超限 | 单次 `COST_BREAKER_TRIP` 事件；`tripped_channels = [ACTIONS_MINUTES, WAVE_BUDGET]`；不双倍计数 trip_count | cost-check.sh L373 任一指标 ≥100% 即触发 | `EVD-xxxx` |
| DR-08 | 配额准确率漂移 | 篡改控制面 DB `pool_accounts.quota_state`，使账本用量 < 供应商面板实际用量 > quota_accuracy_pct 阈值 | `PoolHealthSnapshot.quota_accuracy_pct` 低于阈值；`COST_BUDGET_WARNING` 事件；不触发 `OPEN`（只报不判） | DGA-INFRA §3.7 R-POOL-QUOTA | `EVD-xxxx` |
| DR-09 | verifier 档偏差超限 | 修改 LLM response usage 字段，使账本 token 数与 response usage 偏差 > verifier.deviation_pct | 该 run 判定作废转人工；`EvidenceEntity.failure_reason_code = calibration_invalid`（M6 evidence-contract-draft.md §2 failure_reason_code 枚举已有值）；不触发熔断 | automation-limits.yaml verifier 档 | `EVD-xxxx` |
| DR-10 | 熔断状态持久化与恢复 | `OPEN` 态下重启控制面 / Temporal worker | `pool_breaker_state` 从 DB 恢复；保持 `OPEN`；P0 issue 不因重启消失；新任务继续被拒绝 | DGA-INFRA §1 权威源表：资源池账本 = 控制面 DB | `EVD-xxxx` |

### 5.2 负面测试不覆盖项（待 Linux 常驻机 + SEL-07 落地）

- 真实供应商面板 API 的配额准确率端到端对账（需真实云账号 + IAM）。
- 真实对象存储 WORM 策略下的 `EvidenceEntity` 删除尝试（需 MinIO / S3 生产 IAM + bucket 策略）。
- Temporal `DriftReassessmentWorkflow` 在长期背压（>24h）下的 `approval_wait` 超时行为（需 M3 生产拓扑）。

---

## 6. 与 M5/M6 术语对齐

本策略严格复用 M5/M6 第一波四件草案（`env-registry-draft.md` / `harness-spec-draft.md` / `checkpoint-ext-draft.md` / `decision-log-pipeline-draft.md` / `evidence-contract-draft.md`）定义的术语，不做二次解释或别名：

| 术语 | 来源 | 本策略用法 |
|------|------|------------|
| `EvidenceEntity` | M4 `code/action-registry/gateway.py` / M6 evidence-contract §2 | 熔断事件入证据流的标准载体 |
| `EvidenceType` | M6 evidence-contract §2 | 建议扩展 `COST_BREAKER_TRIP` / `COST_BREAKER_RESET` / `COST_INFRA_FAIL` / `BUDGET_EXCEEDED` / `POOL_COMPOSITION_CHANGE` |
| `calibration_domain_ref` | M6 evidence-contract §2 | 熔断证据的校准域溯源三要件之一（R-EVID-04 / R-POOL-CALIB） |
| `judge_model` / `judge_version` | M6 evidence-contract §2 / R-EVID-04 | 熔断判定证据的判定器模型与版本（若熔断由 OPA 判定触发） |
| `content_digest` | M6 evidence-contract §2 | 熔断事件证据内容摘要（R-EVID-03） |
| `storage_uri` | M5 checkpoint-ext §2 / M6 evidence-contract §2 | 熔断事件证据对象存储路径 |
| `ExecutionEnvironment` | M5 env-registry §2 | `PoolCompositionChange.target_type = EXECUTION_ENVIRONMENT` 的变更目标 |
| `IsolationLevel` | M5 env-registry §3 | `ChangeType.ISOLATION_CHANGE` 的隔离等级枚举 |
| `TrustLevel` | pools.yaml / M5 env-registry §2 | `ChangeType.TRUST_ADJUST` 的信任等级枚举 |
| `virtual_key_ref` | M5 checkpoint-ext §2 | 熔断状态下虚拟 key 限额双重执法（R-POL-03） |
| `PoolAccount.quota_state` | pools.yaml `QuotaState` | `PoolHealthSnapshot.quota_accuracy_pct` 的账本侧输入 |
| `PoolAccount.health` | pools.yaml `HealthSnapshot` | `PoolHealthSnapshot` 继承的既有字段 |
| `RoutingPolicy.budget_cap` | pools.yaml L230 | 闭环级预算上限声明（R-POOL-BUDGET） |
| `RoutingPolicy.allowed_cost_tiers` | pools.yaml L202-205 | `OPEN` 态下收紧路由的成本等级白名单（R-POOL-DEGRADE） |
| `RoutingPolicy.fallback_chain` | pools.yaml L222-228 | 降级链定义；熔断态下不得自动跳到 S5 未批准等级 |
| `CalibrationDomain` | core.yaml L189-235 | `PoolCompositionChange.calibration_domain_ref` 指向对象；池组成变化 ⇒ validity_status = false ⇒ 漂移重估 |
| `Budget` | core.yaml L237-251 | 闭环级预算上限声明（R-POOL-BUDGET）；本草案扩展 `BudgetQuadruple` 对齐 wave_schema.py 四元组 |
| `card_ref` | M6 evidence-contract §2 | wave 预算超限证据的 join key（`owner/repo#issue`） |
| `failure_reason_code` | M6 evidence-contract §2 | verifier 档偏差超限时的 run 作废编码（`calibration_invalid` 已有枚举值） |
| `pipeline_stage_version` | M6 decision-log-pipeline §2 | 证据管道版本；熔断事件证据必须携带 |
| `BreakerState` | 本草案 §3.3 新增枚举 | `PoolHealthSnapshot.circuit_breaker_state` 取值 |

---

## 7. 验收谓词与负面测试方向

每条谓词均为可判定条件（true / false），不依赖模糊描述。

### 7.1 验收谓词

| 编号 | 谓词 | 测试方向 | 对齐原文 |
|------|------|----------|----------|
| CB-01 | `PoolCompositionChange` 类 schema 可通过 LinkML 生成器（`gen-python` / `gen-json-schema` / `gen-sqlddl`）无错误产出，且生成的 Python dataclass / JSON Schema / SQL DDL 可通过反向校验 | 正向生成 | M0 验收要点「六元组 schema、权威源表、S5 裁决清单可评审」；进治理仓路径 |
| CB-02 | `PoolCompositionChange`（`ChangeType.TRUST_ADJUST`，trust_label 下调至低于任务 sensitivity）被记录后，Harness 路由层必须拒绝该环境承接原任务等级 | 负面路由 | R-POOL-TRUST（DGA-INFRA §3.2：任务 sensitivity ≤ 端点 trust） |
| CB-03 | `PoolCompositionChange`（`ChangeType.ISOLATION_CHANGE`，isolation_level 从 vm 降级至 container）被记录后，原允许 `required_isolation=vm` 的任务必须被路由层拒绝 | 负面路由 | R-POOL-DATA（DGA-INFRA §3.3） |
| CB-04 | `PoolCompositionChange`（`ChangeType.QUOTA_DOWNGRADE`，quota 下调超过阈值）事件产生后，漂移检测器必须在 1 个完整检查周期内将关联 `CalibrationDomain.validity_status` 置为 false，并触发 `DriftReassessmentWorkflow` | 漂移触发 | DGA-INFRA §3.8 R-POOL-CALIB；M7 验收要点 |
| CB-05 | 任一 `CostBudgetChannel.usage_pct >= hardstop_pct` 或 wave `on_exceed=hard-stop` 卡超限后，控制面 DB `pool_breaker_state` 必须在 1 个检查周期内从 `CLOSED` 转为 `OPEN`，且 Harness 路由层拒绝新 exec_id 分配 | 硬停触发 | DGA-INFRA §3.6 R-POOL-BUDGET；cost-check.sh 硬停档 |
| CB-06 | `breaker_state = OPEN` 时，`RoutingPolicy.allowed_cost_tiers` 白名单外的端点不得被路由层选中（即使 `trust_label` 与 `sensitivity` 满足 R-POOL-TRUST） | 降级链约束 | DGA-INFRA §3.5 R-POOL-DEGRADE：禁止自动跳到 S5 未批准的成本等级 |
| CB-07 | `breaker_state = OPEN` 时，已在进行任务的 `virtual_key` 限额不受影响；新任务的虚拟 key 申请被拒绝（R-POL-02 子任务权限不放大） | 限额隔离 | R-POL-02 / R-POL-03；cost-check.sh strip auto-merge 语义 |
| CB-08 | 熔断触发后，`EvidenceEntity` 的 `evidence_type = COST_BREAKER_TRIP`，且 `content_digest` 可复算，`storage_uri` 可访问，`object_locked = true`（WORM） | 证据闭环 | R-EVID-03 / R-EVID-04 / R-POOL-BUDGET（熔断事件入证据流） |
| CB-09 | billing API 不可达（Actions 分钟通道）或 ciw-metering 账本拉取失败（LLM token 通道）时，`breaker_state` 保持上一已知态，不自动转为 `OPEN`，且 `EvidenceEntity.evidence_type = COST_INFRA_FAIL` | fail-closed | cost-check.sh L459-474 INFRA 通道；R-EVID-05；ADR-0040 决策 5 |
| CB-10 | S5 owner 执行复位（携带 approval_ref）且所有通道 `usage_pct < hardstop_pct` 后，控制面 DB `pool_breaker_state` 转为 `CLOSED`，P0 issue 自动关闭，Harness 路由层恢复新 exec_id 分配 | 复位流程 | cost-check.sh L448-456 复位确认；DGA-INFRA §3.6 |
| CB-11 | `PoolHealthSnapshot.circuit_breaker_state` 与 `pool_breaker_state.breaker_state` 在控制面 DB 同一检查周期内始终一致（读已提交事务快照） | 状态一致性 | DGA-INFRA §1 权威源表：资源池账本 = 控制面 DB |
| CB-12 | `PoolHealthSnapshot.quota_accuracy_pct` 连续 3 次探测低于阈值（如 < 95%）后，控制面必须产出 `EvidenceEntity`（`evidence_type = QUOTA_DRIFT`），并触发 `PoolCompositionChange`（`ChangeType.QUOTA_DOWNGRADE`）候选 | 配额漂移 | DGA-INFRA §3.7 R-POOL-QUOTA |
| CB-13 | `PoolCompositionChange` 的 `snapshot_before` / `snapshot_after` 中任一侧缺失或 JSON 解析失败时，漂移检测器不得触发漂移重估工作流，事件进入 quarantine | 数据完整性 | R-EVID-05；cost-check.sh 链断不盲熔断纪律 |
| CB-14 | wave `budget` 块 `human_minutes_cap` 超限时，系统只报告 `unenforced_dims`，不触发 `OPEN`，不写入 `EvidenceEntity.evidence_type = BUDGET_EXCEEDED` | 未执法维度可见 | wave_schema.py UNENFORCED_KEYS human_minutes；R-OBS-03 Goodhart 防护 |
| CB-15 | `CalibrationDomain.validity_status` 因 `PoolCompositionChange` 置为 false 后，所有基于该域的已判定 `EvidenceEntity` 必须标记 `stale = true`，不得直接用于客户验收 | 校准失效 | DGA-INFRA §3.8 R-POOL-CALIB |

### 7.2 负面测试不覆盖项（待 Linux 常驻机 + SEL-07/SEL-08 落地）

- 真实 Actions 分钟 / LLM token 端到端扣费 + 熔断时延（需 GitHub 生产 org + LiteLLM 生产拓扑 + 多并发）。
- 真实对象存储 WORM 策略下 `COST_BREAKER_TRIP` 证据对象的提前解锁尝试（需 MinIO / S3 生产 IAM + bucket 策略）。
- Temporal `DriftReassessmentWorkflow` 在长期背压（>24h）下的 `approval_wait` 超时行为（需 M3 生产拓扑）。

---

## 8. 与既有 M0–M4 的关系

| 里程碑 | 本策略的依赖 | 说明 |
|--------|--------------|------|
| M0 | schemas 框架、ID 前缀体系（PCC-xxxx / CAL-xxxx / EVD-xxxx）、`Budget` / `HealthSnapshot` / `RoutingPolicy` 类 | `PoolCompositionChange` / `PoolHealthSnapshot` / `BudgetQuadruple` 扩展需遵循 M0 定的 ID 规则与现有值对象复用 |
| M1 | 控制面 DB `pool_breaker_state` 表、`RoutingPolicy` 表 | 熔断状态机持久化；`allowed_cost_tiers` 白名单消费 |
| M2 | 池账本 `PoolAccount.quota_state` / `HealthSnapshot`、LiteLLM 虚拟 key、`RoutingPolicy.fallback_chain` | 成本通道用量拉取；熔断态下路由降级链收紧；配额准确率对账 |
| M3 | Temporal 流程定义 | `DriftReassessmentWorkflow` 由 Temporal 承载；熔断复位后的 `HALF_OPEN` 等待语义可复用时距挂起 mixin |
| M4 | Action Registry 网关、OPA decision log、`EvidenceEntity` | 熔断执法在网关派发前置检查实现；decision log 入证据流（R-POL-05） |

---

## 9. 治理与变更路径

### 9.1 工作层限制

本文档为工作层草案，不具备治理仓正本效力。

### 9.2 进治理仓路径

进治理仓须 C1 路径（PR + ADR + owner review）：

1. **PR**：提交至 `gov-infra-repo` 的以下文件：
   - `schemas/include/core.yaml`：新增 `PoolCompositionChange` / `BudgetQuadruple` / `CostBudgetChannel` / `PoolHealthSnapshot` 类及 `ChangeType` / `PoolTargetType` / `OnExceed` / `CostChannelType` / `CostDataSource` / `BreakerState` 枚举。
   - `schemas/include/pools.yaml`：`RoutingPolicy.budget_cap` 类型从 `Budget` 扩展为可挂接 `BudgetQuadruple`；`PoolAccount.health` 类型从 `HealthSnapshot` 扩展为 `PoolHealthSnapshot`。
   - `policies/pool-routing.rego`：新增 `breaker_state` 路由谓词（`OPEN` / `HALF_OPEN` 态下 `allowed_cost_tiers` 白名单强制）。
2. **ADR**：记录以下定案：
   - 预算四元组 wave 卡 `human_minutes` 当前无账本源，只声明不判定的 ADR 定案。
   - 熔断五态状态机的 `HALF_OPEN` 持续检查周期时长（建议 1 个 `butler.yaml` budget-check cadence，即 1h）。
   - `PoolCompositionChange` 各 `ChangeType` 触发漂移重估的量化阈值（如 `QUOTA_DOWNGRADE` 下调百分比阈值）。
   - verifier 档偏差阈值（相对 5% / 绝对 50 tokens）的 ADR 定案（automation-limits.yaml 已有默认值，须升格为正式 ADR）。
3. **owner review**：由 gov-infra repo owner（当前为 S5 指定负责人）评审：
   - `PoolCompositionChange` 事件粒度是否过粗（是否拆分为多表事件流）。
   - `BudgetQuadruple` 与现有 `Budget` 类的兼容性（不臆造：`Budget` 类已有 `amount_cap` / `currency` / `period`；本草案的 `usd_cap` / `tokens_cap` / `wallclock_sec_cap` 是 wave 预算四元组扩展，须在 ADR 中明确二者映射）。
   - fail-closed 语义是否覆盖 R-EVID-05 全部子场景（INFRA 故障不盲熔断、不静默归零）。
4. **验证**：schema 通过 `gen-python` / `gen-json-schema` / `gen-sqlddl` 生成验证；状态机转换通过 M7 negtest 设计文档（`controls/negtest-m7-design.md`）断言覆盖。

### 9.3 与 SEL 的联动

- **SEL-05**（LiteLLM 核实）：`CostBudgetChannel.data_source = CIW_METERING` 的归账引擎可用性依赖 SEL-05 对 LiteLLM `SpendLogs` 表结构与 `usage` 字段输出格式的核实结论。
- **SEL-07**（对象存储核实）：熔断事件 `EvidenceEntity` 的 `storage_uri` / WORM / 版本化 / 对象锁定均依赖 SEL-07 选型输出。
- **SEL-08**（Langfuse 核实）：`PoolHealthSnapshot` 进入公示仪表与 Langfuse Dashboard 的度量口径对齐依赖 SEL-08 落地。
- **SEL-12**（池产品化预研）：`BudgetQuadruple` 与 `CostBudgetChannel` 的 schema 设计为池能力对外产品化预留接口（DGA-INFRA §3.10）。

---

## 10. 引用溯源

| 引用编号 | 来源文件 | 章节 / 位置 | 说明 |
|----------|----------|-------------|------|
| R-POOL-BUDGET | DGA-INFRA v1.0 §3.6 | 全文 | 成本熔断：闭环级预算上限；全司日熔断/月熔断；熔断事件入证据流 |
| R-POOL-QUOTA | DGA-INFRA v1.0 §3.7 | 全文 | 配额账本校准：账本 vs 供应商面板定期抽查，误差超阈值报警 |
| R-POOL-DEGRADE | DGA-INFRA v1.0 §3.5 | 全文 | 降级链：T1→T1→低成本→队列/挂起→S5；禁止自动跳级 |
| R-POOL-CALIB | DGA-INFRA v1.0 §3.8 | 全文 | 校准域声明制：池组成变化 ⇒ 触发漂移重估工作流 |
| R-POOL-EVID | DGA-INFRA v1.0 §3.9 | 全文 | 池健康证据：熔断触发次数进入狗狗公示仪表 |
| R-POL-02 | DGA-INFRA v1.0 §5 | R-POL-02 | 子任务权限 ≤ 父任务；拆十个 agent 不获得十倍预算 |
| R-POL-03 | DGA-INFRA v1.0 §5 | R-POL-03 | 池路由的虚拟 key 限额落实 R-POL-02 |
| R-EVID-04 | DGA-INFRA v1.0 §5 | R-EVID-04 | 判定证据必须含判定器模型 + 版本 + 校准域 ID |
| R-EVID-05 | DGA-INFRA v1.0 §5 | R-EVID-05 | 证据缺失是治理异常 |
| R-OBS-02 | DGA-INFRA v1.0 §5 | R-OBS-02 | 治理度量自动化进公示仪表 |
| R-OBS-03 | DGA-INFRA v1.0 §5 | R-OBS-03 | 验证比计量固定口径；Goodhart 防护 |
| M7 验收要点 | DGA-INFRA v1.0 §6 | M7 行 | 池组成变更 → 漂移重估；成本熔断；时距到期自动挂起 |
| cost-check 硬停传统 | `governance/cost-check.sh` | L1-7, L71-78, L202-257, L373-410, L438-456, L459-474 | 预算四元组三通道；硬停三件套；复位仅人工；INFRA fail-closed |
| wave_schema.py 四元组 | `governance/wave_schema.py` | L24, L54, L202-257 | budget 块 usd/tokens/wallclock_sec/human_minutes；on_exceed；ENFORCEABLE/UNENFORCED_KEYS |
| automation-limits.yaml | `governance/policy/automation-limits.yaml` | L28-77 | cost 通道 quota/warn/hardstop；verifier 档；circuit_breaker 变量与复位责任人 |
| Budget | `schemas/include/core.yaml` | L237-251 | 闭环级预算上限声明载体（现有类） |
| CalibrationDomain | `schemas/include/core.yaml` | L189-235 | 校准域：model_set_snapshot / validity_status / ontology_commit |
| HealthSnapshot | `schemas/include/pools.yaml` | L50-70 | 现有池健康快照值对象 |
| PoolAccount | `schemas/include/pools.yaml` | L98-148 | 池账号：quota_state / health / trust_label / cost_tier |
| LogicalEndpoint | `schemas/include/pools.yaml` | L150-185 | 逻辑端点：trust_level / bound_accounts / routing_policy_ref |
| RoutingPolicy | `schemas/include/pools.yaml` | L187-248 | 路由策略：allowed_cost_tiers / budget_cap / fallback_chain / suspension_on_timespan_expiry |
| CostTier | `schemas/include/enums.yaml` | L69-83 | 成本分层枚举（free/low-paid/high-paid/enterprise） |
| EvidenceEntity | M6 `evidence-contract-draft.md` | §2 | M6 扩展字段：restored_from_checkpoint_id / failure_reason_code / checkpoint_event_type / payload_ref / tenant_id / card_ref |
| EvidenceType | M6 `evidence-contract-draft.md` | §2 | M0 定稿证据类型枚举；本草案建议扩展值 |
| ExecutionEnvironment | M5 `env-registry-draft.md` | §2 | M5 新增执行环境实体；trust_label / isolation_level / health / quota_state |
| IsolationLevel | M5 `env-registry-draft.md` | §3 | M5 新增隔离等级枚举 |
| Harness 路由层 | M5 `harness-spec-draft.md` | §2.2, §2.5 | 执行环境路由 / 虚拟 key 限额绑定 / 与 Action Registry 协议边界 |
| checkpoint-ext | M5 `checkpoint-ext-draft.md` | §2, §4 | content_hash 规范序列化；calibration_domain_id / harness_version 必填 |
| decision-log-pipeline | M6 `decision-log-pipeline-draft.md` | §2-§4 | Stage 3 Evidence Extraction / Stage 4 Object Storage Ingestion / Stage 5 Ledger Registration |
| pool-routing.rego | `policies/pool-routing.rego` | L1-73 | 现有池路由谓词：R-POOL-TRUST / R-POOL-DATA / R-POOL-COMPLIANCE；本草案新增 breaker_state 谓词 |
