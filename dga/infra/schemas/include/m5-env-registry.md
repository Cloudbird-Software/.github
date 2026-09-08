# M5 多环境注册表 schema 扩展草案

> **工作层草案，进治理仓须 C1 路径（PR + ADR + owner review）。**
> 本文档为 DGA-INFRA M5 执行环境注册表的 LinkML 扩展草案，非治理仓正本。
> 起草日期：2026-09-08。

---

## 1. 目标与范围

### 1.1 来源锚点

- **M5 验收要点**（DGA-INFRA §6 里程碑表 M5 行）：执行单元多环境：Harness 接池 + ≥2 个执行环境 + 检查点外置；换执行环境不丢业务状态；虚拟 key 限额生效。
- **架构锚点**（DGA-INFRA §1 总体架构图）：资源池层「LiteLLM（LLM 路由 + 虚拟 key）· 计算调度（多执行环境路由）」；隔离执行单元层「Harness + MCP 适配器 + 判定探针（无本地状态，检查点外置）」。
- **漂移锚点**（DGA-INFRA §3.8 R-POOL-CALIB）：每份 eval 校准必须声明其校准域（覆盖的模型集合 + Spec/Harness 版本 + 观察窗口）；池组成变化 ⇒ 触发相关闭环的漂移重估工作流。
- **M7 验收要点**（DGA-INFRA §6 里程碑表 M7 行）：池治理完善——池组成变更 → 漂移重估工作流；成本熔断；时距到期自动挂起。
- **接口边界锚点**：`plans/2026-09-09-m5-harness-spec-draft.md` §5（多环境注册表 schema 扩展）已定义 `ExecutionEnvironment` 类与 `IsolationLevel` 枚举初稿。本草案承接其接口边界，补完字段语义、与池层 schema 对齐、与 M7 漂移重估的联动机制、以及可判定验收谓词。

### 1.2 本草案覆盖

| 件 | 定位 | 本文件处理方式 |
|----|------|----------------|
| ExecutionEnvironment 实体 | 核心 | §2 全文详述 |
| IsolationLevel 枚举 | 核心 | §3 全文详述 |
| 与池层现有 schema 对齐 | 接口边界 | §4 对齐表 |
| 与 M7 漂移重估的关系 | 接口边界 | §5 联动机制 |
| 注册表查询接口 | 接口边界 | §6 接口定义 |
| 验收谓词与负面测试 | 验收 | §7 全文 |

### 1.3 不覆盖

- 实现代码、Harness 路由层逻辑、部署脚本（属于第二波）。
- LangGraph 选型定案（CMP-14 仍为按需候选）。
- 对象存储具体选型（SEL-07 输出，本草案仅消费其接口语义）。

---

## 2. ExecutionEnvironment 实体（LinkML 扩展草案）

### 2.1 类定义

```yaml
classes:
  ExecutionEnvironment:
    class_uri: dga:ExecutionEnvironment
    mixins:
      - SecurityMark
    slots:
      - id
      - env_name
      - trust_label
      - isolation_level
      - health
      - quota
      - endpoint_ref
      - accountable_person
      - harness_version
      - last_checkpoint_at
    slot_usage:
      id:
        pattern: "^ENV-[0-9]{4,}$"
    attributes:
      env_id:
        range: string
        required: true
        identifier: true
        description: >
          执行环境唯一 ID（ENV-xxxx）。与 LogicalEndpoint 并行，不等价；
          一个 endpoint 可映射到多个物理环境，一个物理环境也可承载多个 endpoint 的租
          约隔离。

      env_name:
        range: string
        required: true
        description: >
          人类可读名称（如 windev-01-wsl1 / linux-vm-01 / customer-edge-01）。
          名称不参与路由判定，仅用于运维与审计投影。

      trust_label:
        range: TrustLevel
        required: true
        description: >
          环境信任等级（T0/T1/T2）。对齐 DGA-INFRA 3.2 R-POOL-TRUST：
          任务 sensitivity ≤ 环境 trust_label。环境 trust_label 下调属于敏感变更，
          必须留审计迹并触发漂移重估候选（§5）。

      isolation_level:
        range: IsolationLevel
        required: true
        description: >
          隔离等级（process / container / vm / bare-metal）。
          决定环境可承接的任务最高 sensitivity（对齐 R-POOL-DATA）：
          bare-metal ≥ vm ≥ container ≥ process。隔离降级恢复必须经授权
          （R-POL-02：恢复检查点须重验当前授权）。

      health:
        range: HealthSnapshot
        inlined: true
        description: >
          健康快照值对象。复用 `schemas/include/pools.yaml` 已有定义
          （availability_pct / latency_ms_p95 / error_rate / last_failure_at /
          last_check_at）。对齐 DGA-INFRA 3.9 R-POOL-EVID：健康度量进入治理度量
          体系与公示仪表。

      quota:
        range: QuotaState
        inlined: true
        description: >
          配额状态值对象。复用 `schemas/include/pools.yaml` 已有定义
          （rpm_limit / tpm_limit / daily_quota / monthly_quota / credit_balance /
          observed_at）。对齐 DGA-INFRA 3.1 Account.quota_state 与 3.7
          R-POOL-QUOTA：账本 vs 供应商面板定期抽查，误差超阈值报警。

      endpoint_ref:
        range: string
        description: >
          关联的 LogicalEndpoint ID（EPL-xxxx，DGA-INFRA 3.1）。
          多个 ENV 可复用同一 endpoint 路由策略；endpoint 退役时，
          关联 ENV 不得承接新任务（R-POOL-DATA 数据红线延伸）。

      accountable_person:
        range: Person
        description: >
          具名责任人（DGA-INFRA 3.1：每个池对象是资产目录中的正式资产；
          对齐 CMP-01 / R-GOV-03 责任守恒律）。

      harness_version:
        range: SemVer
        description: >
          当前部署的 Harness 版本（对齐 `CalibrationDomain.harness_version`，
          `schemas/include/core.yaml` 已有定义）。换环境恢复检查点时，
          Harness 版本变化必须触发 `CalibrationDomain` 漂移重估候选（§5）。

      last_checkpoint_at:
        range: datetime
        description: >
          最近一次外置检查点创建时间（DGA-INFRA §1「检查点外置」；
          M5 验收要点「换执行环境不丢业务状态」的观测锚点）。
```

### 2.2 字段来源与对齐

| 新增字段 | 对齐的现有 schema / DGA-INFRA 条目 | 说明 |
|----------|-------------------------------------|------|
| `trust_label` | `LogicalEndpoint.trust_level`（`schemas/include/pools.yaml`）；DGA-INFRA 3.2 R-POOL-TRUST | 复用 `TrustLevel` 枚举，不做二次解释 |
| `isolation_level` | 新增 `IsolationLevel` 枚举（§3）；M5 验收要点「≥2 个执行环境 / 多信任域」 | 隔离等级决定可承接的任务最高 sensitivity |
| `health` | `PoolAccount.health` → `HealthSnapshot`（`schemas/include/pools.yaml`）；DGA-INFRA 3.9 R-POOL-EVID | 内嵌值对象复用 |
| `quota` | `PoolAccount.quota_state` → `QuotaState`（`schemas/include/pools.yaml`）；DGA-INFRA 3.1 / 3.7 R-POOL-QUOTA | 内嵌值对象复用 |
| `endpoint_ref` | `LogicalEndpoint.id`（`schemas/include/pools.yaml`）；DGA-INFRA 3.1 | 执行环境到路由策略的映射 |
| `harness_version` | `CalibrationDomain.harness_version`（`schemas/include/core.yaml`）；DGA-INFRA 3.8 R-POOL-CALIB | 换环境恢复时的校准域输入 |
| `accountable_person` | `Person`（`schemas/include/core.yaml`）；DGA-INFRA 3.1 / R-GOV-03 | 责任锚点复用 |

**不臆造**：`ExecutionEnvironment` 类不在当前 `schemas/include/core.yaml`、`schemas/include/pools.yaml`、`schemas/include/enums.yaml` 中（2026-09-08 检索确认）。本草案以「扩展草案」形式提出，进入治理仓须经 LinkML 变更评审（C1）。

---

## 3. IsolationLevel 枚举（LinkML 扩展草案）

```yaml
enums:
  IsolationLevel:
    description: >
      执行环境隔离等级（M5 新增；Harness 路由层与判定探针挂载的依据）。
      等级越高，可承接的任务 sensitivity 上限越高；隔离降级必须经授权
      （R-POL-02）。
    permissible_values:
      process:
        description: >
          进程级隔离（WSL1 / namespace）。适合 T0 / 开发门禁（CMP-17）。
          禁止承接 D_CUSTOMER_SENSITIVE 数据任务（R-POOL-DATA）。
      container:
        description: >
          容器级隔离（Docker / Podman）。适合 T1 / 标准执行。
          可承接一般客户业务数据任务。
      vm:
        description: >
          虚拟机级隔离。适合 T1 / T2 敏感任务。
          网络与存储可独立命名空间。
      bare-metal:
        description: >
          物理机隔离。适合 T2 / 客户本地部署（[DER-11]）。
          最高隔离等级，仅 T2 敏感任务或客户指定端点使用。
```

### 3.1 与现有敏感度标签的映射（接口边界）

| IsolationLevel | 允许的最高 SensitivityLevel | 说明 |
|----------------|------------------------------|------|
| process | S0_PUBLIC / S1_INTERNAL | 对齐 CMP-17 开发门禁；禁止进客户敏感数据 |
| container | S0_PUBLIC / S1_INTERNAL / S2_CUSTOMER_SENSITIVE | 标准执行环境 |
| vm | S0_PUBLIC / S1_INTERNAL / S2_CUSTOMER_SENSITIVE | 高敏感任务备用 |
| bare-metal | S2_CUSTOMER_SENSITIVE | 客户本地或零信任域 |

映射强制在 OPA 层（R-POL-01）；schema 只保证两端字段在位（M0 诚实边界登记）。

---

## 4. 与池层现有 schema 的对齐

| 新增字段 / 枚举 | 对齐的池层字段 | 来源 |
|-----------------|----------------|------|
| `ExecutionEnvironment.trust_label` | `LogicalEndpoint.trust_level`（`schemas/include/pools.yaml`） | CMP-05 / R-POOL-TRUST |
| `ExecutionEnvironment.health` | `PoolAccount.health` → `HealthSnapshot`（`schemas/include/pools.yaml`） | R-POOL-EVID |
| `ExecutionEnvironment.quota` | `PoolAccount.quota_state` → `QuotaState`（`schemas/include/pools.yaml`） | R-POOL-QUOTA |
| `ExecutionEnvironment.endpoint_ref` | `LogicalEndpoint.id`（`schemas/include/pools.yaml`） | CMP-05 |
| `ExecutionEnvironment.accountable_person` | `Person`（`schemas/include/core.yaml`） | R-GOV-03 |
| `ExecutionEnvironment.harness_version` | `CalibrationDomain.harness_version`（`schemas/include/core.yaml`） | R-POOL-CALIB |
| `IsolationLevel` | 无直接对应（现有 `SensitivityLevel` 为任务侧标签，非环境侧隔离等级） | M5 新增 |

**诚实边界**：本草案不改变现有 `LogicalEndpoint`、`PoolAccount`、`RoutingPolicy` 的字段定义；`ExecutionEnvironment` 是独立实体，与池对象是「路由策略 → 端点 → 物理环境」的层级关系，不是等价替换。

---

## 5. 与环境漂移重估（M7）的关系

### 5.1 设计意图

DGA-INFRA §3.8 R-POOL-CALIB 明确：「池组成变化（新增/移除/权重调整被校准域覆盖的模型）⇒ 触发相关闭环的漂移重估工作流」。M7 验收要点进一步要求「池组成变更 → 漂移重估工作流」。

本草案将「池组成」概念从模型集合（Provider / Account / LogicalEndpoint）延伸到计算调度层：**执行环境是池组成在物理/虚拟资源侧的映射**。ExecutionEnvironment 的以下属性变更属于池组成变化的补充信号：

| 属性 | 漂移语义 | 触发条件 |
|------|----------|----------|
| `trust_label` | 环境可处理的数据敏感度上限变化 | 从 T1 下调至 T0，或从 T2 下调至 T1 |
| `isolation_level` | 环境安全边界收缩 | 从 vm 降级至 container / process |
| `health` | 环境可靠性分布参数变化 | `availability_pct` 低于阈值 / `error_rate` 突增 / `last_failure_at` 刷新 |
| `quota` | 环境产能分布参数变化 | `rpm_limit` / `daily_quota` 下调超过阈值 |
| `harness_version` | 执行语义版本变化 | 主版本或次版本升级（补丁版本不触发） |

### 5.2 联动机制（接口边界）

```text
ExecutionEnvironment 属性变更事件
           │
           ▼
  注册表审计日志（旧值 / 新值 / 时间戳 / 操作者）
           │
           ▼
  漂移检测器消费（若 CalibrationDomain 已将该 env_id 纳入观测窗口）
           │
           ▼
  ┌───────────────┐    是    ┌───────────────┐
  变化属性在覆盖范围？ ├────────▶ 触发漂移重估工作流（M7）
  └───────────────┘          └───────────────┘
           │
           否
           ▼
  仅更新注册表快照，不触发重估
```

### 5.3 与 CalibrationDomain 的字段联动

| ExecutionEnvironment 字段 | CalibrationDomain 对应 / 关联字段 | 联动说明 |
|----------------------------|-----------------------------------|----------|
| `trust_label` | `model_set_snapshot`（池组成快照文本可包含 env trust 分布） | 环境信任级变化 ⇒ 池组成快照变化 ⇒ 漂移重估候选 |
| `isolation_level` | `spec_version`（Spec 对隔离等级的声明版本） | 隔离等级变化若超出 Spec 声明范围 ⇒ 触发重估 |
| `health` | 无直接字段（属观测层） | 健康恶化导致路由策略自动避开该环境 ⇒ 池组成实际分布变化 ⇒ 漂移候选 |
| `quota` | `observation_window`（配额观测窗口） | 配额变化超出历史观测窗口的统计分布 ⇒ 漂移候选 |
| `harness_version` | `harness_version`（已有字段） | 版本变化 ⇒ 已校准判定的 Harness 前提失效 ⇒ 漂移重估（DGA-INFRA 3.8） |

**不臆造**：DGA-INFRA 3.8 原文只明确「池组成变化 ⇒ 触发相关闭环的漂移重估工作流」。本草案将执行环境属性归入池组成的计算调度维度，属于合规扩展；具体哪些属性变化触发重估、阈值是多少，须在 ADR 中记录并经过 owner review。

### 5.4 本体漂移触发线

将 `ExecutionEnvironment` 类新增进 `schemas/dga-ontology.yaml` 属于本体变更。根据 `CalibrationDomain.ontology_commit` 字段说明（human v1.1 §5.7 第三触发线）：「本体变更 ⇒ 已校准判定的有效性存疑 ⇒ 触发重估」。因此，**本次 schema 扩展一旦合入治理仓，所有已有 CalibrationDomain 的 `ontology_commit` 必须更新，否则判定结果自动进入漂移待核实状态**。

---

## 6. 注册表查询接口（接口边界）

### 6.1 查询接口

```text
GET /v1/registry/environments
```

**查询参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `trust_label` | TrustLevel | 否 | 按信任等级过滤（T0/T1/T2） |
| `isolation_level` | IsolationLevel | 否 | 按隔离等级过滤（process/container/vm/bare-metal） |
| `endpoint_ref` | string | 否 | 按 LogicalEndpoint ID 过滤（EPL-xxxx） |
| `healthy_only` | boolean | 否 | 仅返回 health.availability_pct ≥ 阈值的环境 |

**响应字段**：返回 `ExecutionEnvironment` 列表，字段由 §2 类定义约束。

### 6.2 路由层消费约束

- Harness 路由层（`plans/2026-09-09-m5-harness-spec-draft.md` §2.2）消费此接口，不直接访问池账本表。
- 路由决策必须同时满足：
  - `task.sensitivity ≤ env.trust_label`（R-POOL-TRUST）
  - `task.required_isolation ≤ env.isolation_level`（接口边界映射）
  - `env.health.availability_pct ≥ 阈值`（R-POOL-EVID）
  - `env.quota` 余量充足（R-POOL-QUOTA）

---

## 7. 验收谓词与负面测试方向

### 7.1 验收谓词

每条谓词均为可判定条件（true/false），不依赖模糊描述。

| 编号 | 谓词 | 测试方向 | 对齐原文 |
|------|------|----------|----------|
| AEP-01 | `ExecutionEnvironment` 类 schema 可通过 LinkML 生成器（`gen-python` / `gen-json-schema` / `gen-sqlddl`）无错误产出，且生成的 Python dataclass / JSON Schema / SQL DDL 可通过反向校验 | 正向生成 | M0 验收要点「六元组 schema、权威源表、S5 裁决清单可评审」；进治理仓路径 |
| AEP-02 | `ExecutionEnvironment.isolation_level=process` 的环境，拒绝承接 `required_isolation=container` 以上的任务 | 负面路由 | M5「多信任域」；隔离降级；R-POOL-DATA |
| AEP-03 | `ExecutionEnvironment.trust_label` 下调至低于任务 `sensitivity` 后，Harness 路由层必须拒绝该环境 | 负面路由 | R-POOL-TRUST（DGA-INFRA 3.2：任务 sensitivity ≤ 端点 trust） |
| AEP-04 | `ExecutionEnvironment.health.availability_pct` 连续 3 次探测低于阈值（如 < 50%）后，注册表必须标记为不可用，Harness 路由层不再分配新 `exec_id` | 健康熔断 | DGA-INFRA 3.9 R-POOL-EVID；R-POOL-DEGRADE |
| AEP-05 | 注册表审计日志必须记录 `trust_label` / `isolation_level` / `quota` 的每次变更（含旧值 / 新值 / 时间戳 / 操作者）；篡改这些字段且未留审计迹 = 治理异常（R-EVID-05），漂移检测器不得采信 | 篡改检测 | R-EVID-05；DGA-INFRA 3.8 R-POOL-CALIB |
| AEP-06 | 同一 `env_id` 在注册表中出现两条记录时，注册表启动时必须拒绝启动并返回冲突错误，防止路由层 ambiguous | 幂等 / 唯一性 | 执行环境 = 资产目录正式资产（DGA-INFRA 3.1） |
| AEP-07 | `ExecutionEnvironment.endpoint_ref` 指向的 `LogicalEndpoint` 已退役（`retired_at` 非空）时，注册表必须拒绝将该环境分配给新任务 | 退役隔离 | DGA-INFRA 3.1 LogicalEndpoint 生命周期；R-POOL-DATA |
| AEP-08 | `CalibrationDomain.ontology_commit` 变更后（即 `ExecutionEnvironment` 类新增进本体），原有 `CalibrationDomain` 的判定结果必须重新评估，不得直接沿用 | 本体漂移 | human v1.1 §5.7 第三触发线（本体漂移）；DGA-INFRA 3.8 |

### 7.2 负面测试不覆盖项（待 Linux 常驻机）

- 真实执行环境进程崩溃后的外置检查点恢复（需 Linux 服务化部署）。
- 跨云区域执行环境的实际网络延迟注入与降级链验证（需真实拓扑）。
- `ExecutionEnvironment` 物理迁移（如从 vm 迁至 bare-metal）后的端到端漂移重估工作流（需 M7 Temporal workflow 到位）。

---

## 8. 与既有 M0–M4 的关系

| 里程碑 | 本草案的依赖 | 说明 |
|--------|--------------|------|
| M0 | schemas 框架、ID 前缀体系、`TrustLevel` / `SensitivityLevel` / `HealthSnapshot` / `QuotaState` / `Person` 类 | `ExecutionEnvironment` 扩展需遵循 M0 定的 ID 规则（ENV-xxxx）与现有值对象复用 |
| M1 | 控制面 DB、六元组 schema | 执行环境注册表查询接口由控制面承载；`accountable_person` 关联 `Person` 表 |
| M2 | 池账本、LiteLLM 虚拟 key、路由谓词 | Harness 路由层消费注册表，结合池账本 `quota_state` 做限额扣减 |
| M3 | Temporal 流程定义 | 漂移重估工作流（M7）由 Temporal 承载，执行环境属性变更事件是触发源之一 |
| M4 | Action Registry 网关、OPA decision log、幂等键 | 路由层隔离降级 / trust 下调的判定由 OPA 强制（R-POL-01），Harness 不重复授权检查 |

---

## 9. 治理与变更路径

### 9.1 工作层限制

本文档为工作层草案，不具备治理仓正本效力。

### 9.2 进治理仓路径

进治理仓须 C1 路径（PR + ADR + owner review）：

1. **PR**：提交至 `gov-infra-repo`（或 DGA-INFRA 正本仓）的 `schemas/include/enums.yaml`（新增 `IsolationLevel`）与 `schemas/include/core.yaml`（新增 `ExecutionEnvironment` 类）。
2. **ADR**：记录执行环境隔离等级默认值选择（process / container / vm）、M7 漂移属性阈值（`availability_pct` / `error_rate` / `quota` 变化百分比）、以及 `ExecutionEnvironment` 与 `LogicalEndpoint` 的 1:N 关系定案。
3. **owner review**：由 gov-infra repo owner（当前为 S5 指定负责人）评审 schema 扩展与接口边界。
4. **LinkML 生成验证**：schema 变更通过 `gen-python` / `gen-json-schema` / `gen-sqlddl` 生成验证后，方可合入。

### 9.3 与 SEL 的联动

- SEL-05（LiteLLM 核实）：虚拟 key 限额端到端验证依赖于本草案定义的 `quota` 字段与接口。
- SEL-07（对象存储核实）：检查点外置接口（harness spec §4）与 `last_checkpoint_at` 字段共同构成执行环境状态投影。
- SEL-09（客户门户与客服）：执行环境健康状态（`health`）可暴露给客户门户作为 SLA 投影，但属 M9 范围。

---

## 10. 引用溯源

| 引用编号 | 来源文件 | 章节/位置 | 说明 |
|----------|----------|-----------|------|
| M5 验收要点 | DGA-INFRA §6 里程碑表 | M5 行 | Harness 接池 + ≥2 个执行环境 + 检查点外置 |
| M7 验收要点 | DGA-INFRA §6 里程碑表 | M7 行 | 池组成变更 → 漂移重估工作流 |
| CMP-17 | DGA-INFRA §2 组件表 | CMP-17 | 现有 Harness 保留，单次执行与开发门禁 |
| CMP-14 | DGA-INFRA §2 组件表 | CMP-14 | LangGraph，按需候选，Harness 内部图式协作 |
| CMP-05 | DGA-INFRA §2 组件表 | CMP-05 | LiteLLM Proxy，虚拟 key / 预算 / 路由 |
| CMP-09 | DGA-INFRA §2 组件表 | CMP-09 | 对象存储，版本 + 锁定（WORM） |
| CMP-01 | DGA-INFRA §2 组件表 | CMP-01 | DGA 控制面（自研），核心资产是连接关系 |
| R-POOL-TRUST | DGA-INFRA §3.2 | R-POOL-TRUST | 信任标签路由（T0/T1/T2） |
| R-POOL-DATA | DGA-INFRA §3.3 | R-POOL-DATA | 数据红线 |
| R-POOL-DEGRADE | DGA-INFRA §3.5 | R-POOL-DEGRADE | 降级链 |
| R-POOL-BUDGET | DGA-INFRA §3.6 | R-POOL-BUDGET | 成本熔断 |
| R-POOL-QUOTA | DGA-INFRA §3.7 | R-POOL-QUOTA | 配额账本校准 |
| R-POOL-CALIB | DGA-INFRA §3.8 | R-POOL-CALIB | 校准域声明制；池组成变化 ⇒ 漂移重估 |
| R-POOL-EVID | DGA-INFRA §3.9 | R-POOL-EVID | 池健康证据 |
| R-EVID-01 | DGA-INFRA §5 | R-EVID-01 | 证据契约独立定义 |
| R-EVID-03 | DGA-INFRA §5 | R-EVID-03 | 对象版本 + 内容摘要 + 独立写入权限 + 对象锁定 |
| R-EVID-04 | DGA-INFRA §5 | R-EVID-04 | 判定证据必须含判定器模型+版本+校准域 ID |
| R-EVID-05 | DGA-INFRA §5 | R-EVID-05 | 证据缺失是治理异常 |
| R-POL-01 | DGA-INFRA §5 | R-POL-01 | 权限检查在工具网关/服务端强制执行 |
| R-POL-02 | DGA-INFRA §5 | R-POL-02 | 子任务权限 ≤ 父任务；恢复检查点须重验当前授权 |
| R-POL-03 | DGA-INFRA §5 | R-POL-03 | 池路由虚拟 key 限额落实子任务权限不放大 |
| R-POL-05 | DGA-INFRA §5 | R-POL-05 | OPA decision log 入证据流 |
| R-SEC-02 | DGA-INFRA §5 | R-SEC-02 | 凭证明文仅存凭据库 |
| R-GOV-03 | DGA-INFRA §5 | R-GOV-03 | 新闭环缺具名责任人 ⇒ 拒绝生产执行资格 |
| LogicalEndpoint | `schemas/include/pools.yaml` | §LogicalEndpoint | 逻辑端点（绑定 Account 集合+路由策略） |
| PoolAccount.health | `schemas/include/pools.yaml` | §HealthSnapshot | 健康快照值对象 |
| PoolAccount.quota_state | `schemas/include/pools.yaml` | §QuotaState | 配额状态值对象 |
| TrustLevel | `schemas/include/enums.yaml` | §TrustLevel | 信任标签枚举（T0/T1/T2） |
| SensitivityLevel | `schemas/include/enums.yaml` | §SensitivityLevel | 任务敏感度标签（S0/S1/S2） |
| CalibrationDomain.harness_version | `schemas/include/core.yaml` | §CalibrationDomain | 校准时依据的 Harness 版本 |
| CalibrationDomain.ontology_commit | `schemas/include/core.yaml` | §CalibrationDomain | 本体 schema 的 Git commit（第三触发线） |
| `plans/2026-09-09-m5-harness-spec-draft.md` | `plans/` | §5 | ExecutionEnvironment 类初稿与 IsolationLevel 枚举初稿；接口边界段 |
| Person | `schemas/include/core.yaml` | §Person | 具名责任人 |
