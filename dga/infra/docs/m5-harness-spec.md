# M5 Harness 架构 spec 草案

> **工作层草案，进治理仓须 C1 路径（PR + ADR + owner review）。**
> 本文档为 DGA-INFRA M5 第一顺位设计件，非治理仓正本。
> 起草日期：2026-09-08。

---

## 1. 目标与范围

### 1.1 来源锚点

- **M5 验收要点**（DGA-INFRA §6 里程碑表 M5 行）：Harness 接池 + ≥2 个执行环境 + 检查点外置；换执行环境不丢业务状态；虚拟 key 限额生效。
- **架构锚点**（DGA-INFRA §1 总体架构图）：「隔离执行单元（多信任域：公司云 ×N · 客户本地）— Harness + MCP 适配器 + 判定探针（无本地状态，检查点外置）」。
- **组件定位**：CMP-17（现有 Harness 保留，单次执行与开发门禁，接入池层与控制面）；CMP-14（LangGraph，按需候选，Harness 内部图式协作；不让框架内存成为公司唯一状态）；CMP-05（LiteLLM，虚拟 key 限额）。
- **策略锚点**：R-POL-03（池路由的虚拟 key 限额落实子任务权限不放大）；R-POL-02（重建 Run 须重验当前授权）；R-EVID-04（判定证据必须含判定器模型+版本+校准域 ID）；R-EVID-01（证据契约独立定义）。

### 1.2 本草案覆盖

| 件 | 定位 | 本文件处理方式 |
|----|------|----------------|
| Harness 架构 | 核心 | 全文详述（§2–§4） |
| MCP 适配器协议 | 接口边界 | §5 接口边界段落 |
| 检查点外置接口 | 接口边界 | §6 接口边界段落 |
| 多环境注册表 schema 扩展 | 接口边界 | §7 接口边界段落 |

### 1.3 不覆盖

- 实现代码、部署脚本、服务启动配置（属于第二波 Linux 常驻机到位后）。
- LangGraph 选型定案（CMP-14 仍为按需候选，本文档仅预留集成位）。
- 对象存储具体选型（SEL-07 输出，本文档仅消费其接口语义）。

---

## 2. Harness 架构详述

### 2.1 在 DGA-INFRA 总体架构中的位置

```
资源池层     LiteLLM（LLM 路由 + 虚拟key）· 计算调度（多执行环境路由）
────────────────────────────────────────────
隔离执行单元（多信任域：公司云 ×N · 客户本地）
  Harness + MCP 适配器 + 判定探针（无本地状态，检查点外置）
────────────────────────────────────────────
证据与判定层   证据契约 · 对象存储（版本+锁定）· 校准与漂移 · 治理度量 · 公示
```

Harness 是执行单元层的编排核心：接收来自 Action Registry 网关的已授权执行请求，在指定执行环境中运行 MCP 工具，产出执行收据（EvidenceEntity），并将检查点外置到对象存储。

### 2.2 核心职责

1. **执行环境路由**：根据任务的 sensitivity / trust_label / isolation 要求，将执行调度到匹配的执行环境（≥2 个环境，不同信任域），对齐 R-POOL-TRUST（DGA-INFRA 3.2）。
2. **虚拟 key 限额绑定**：每个执行单元从池层获取独立的 LiteLLM virtual key（CMP-05），落实 R-POL-03（子任务权限 ≤ 父任务；拆十个 agent 不获得十倍预算）。
3. **检查点外置**：执行中间状态（checkpoint）写入对象存储（CMP-09），不依赖 Harness 进程本地存储。换环境时从外置检查点恢复，不丢业务状态，对齐 DGA-INFRA §1「检查点外置」表述。
4. **MCP 工具调用**：通过 MCP 适配器协议（§5）与 MCP tool server 交互，支持 stdio / SSE / HTTP 传输。
5. **判定探针集成**：预留探针挂载位，用于执行过程中的判定能力注入（探针定义由 M6 证据层具体化）。
6. **执行收据产出**：每次执行产出 EvidenceEntity（对齐 R-EVID-01 结构），包含 judge_model / judge_version / calibration_domain_id（R-EVID-04 / R-POOL-CALIB）。

### 2.3 与已有 M0–M4 组件的关系

| 组件 | 关系 | 引用 |
|------|------|------|
| Action Registry 网关（`code/action-registry/gateway.py`） | 上游：Harness 仅接收已通过网关六级管线（注册表→jsonschema→OPA→R-EVID-04→幂等→mock 执行器）的请求 | M4 产出 |
| OPA（`policies/action-authz.rego`） | 策略执法已在网关层完成；Harness 不重复授权检查 | R-POL-01 |
| Temporal（`code/workflows/`） | 流程层：Harness 的执行由 Temporal workflow 调用，Harness 不承载等待语义 | R-FLOW-01 |
| 池账本（`pools/ledger.sql`） | Harness 从池层获取虚拟 key 与路由信息，不直接管理池账本 | M2/CMP-05 |
| 对象存储（CMP-09） | Harness 写入检查点与执行收据；不依赖特定存储实现 | SEL-07 |
| 现有 Harness（CMP-17） | 保留为单次执行与开发门禁；新 Harness 是其在多环境场景下的泛化 | CMP-17 |

### 2.4 状态机

```text
                    ┌──────────┐
                    │ RECEIVED │  ← 从 Action Registry 网关接收已授权请求
                    └────┬─────┘
                         │
                    ┌────▼─────┐
                    │ ROUTING  │  ← 选择执行环境（env_id / trust_label 匹配）
                    └────┬─────┘
                         │
              ┌──────────▼──────────┐
              │ CHECKPOINT_RESTORE  │  ← 若有 checkpoint_id，从对象存储恢复
              └──────────┬──────────┘
                         │
                    ┌────▼─────┐
                    │ RUNNING  │  ← 执行 MCP 工具调用
                    └────┬─────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
     ┌────▼────┐   ┌─────▼──────┐  ┌────▼────┐
     │ SUCCESS │   │ CHECKPOINT │  │ FAILED  │
     └────┬────┘   │ (PAUSED)   │  └────┬────┘
          │        └─────┬──────┘       │
          │              │              │
     ┌────▼────┐         │         ┌────▼────┐
     │ RECEIPT │◄────────┘         │ RECEIPT │
     │  + FREE │                   │  + FREE │
     └─────────┘                   └─────────┘
```

**状态语义**：

- **RECEIVED**：请求已进入 Harness，未分配环境。
- **ROUTING**：根据 env_id / trust_label / isolation_level 选择执行环境；路由失败直接进入 FAILED。
- **CHECKPOINT_RESTORE**：恢复外置检查点；若恢复失败，进入 FAILED 并保留失败收据（R-EVID-05：证据缺失是治理异常）。
- **RUNNING**：实际执行阶段，本地不持久化业务状态。
- **CHECKPOINT**：主动暂停并外置当前状态；用于跨环境迁移或长流程挂起（R-FLOW-01 要求等待进 Temporal，此处 CHECKPOINT 仅用于执行上下文保存）。
- **SUCCESS / FAILED**：执行终止；产出 EvidenceEntity，释放虚拟 key 限额，释放环境租约。
- **FREE**：环境租约释放，可被下一个任务路由。

### 2.5 与 Action Registry 网关的协议边界

```
┌─────────────────┐     已授权执行请求       ┌─────────────────┐
│ Action Registry │ ──────────────────────▶ │   Harness       │
│    Gateway      │ ◀────────────────────── │  ( orchestrator)│
│ (M4 六级管线)   │   执行收据 + 检查点 URI  └────────┬────────┘
└─────────────────┘                                 │
                                              ┌──────┴──────┐
                                              │ 执行环境 ×N  │
                                              │ (MCP tools)  │
                                              └─────────────┘
```

Harness 不执行授权检查（R-POL-01）；所有策略判定必须在网关层完成。Harness 对网关只暴露：

- `POST /v1/harness/run`：启动执行
- `POST /v1/harness/checkpoint/{exec_id}`：外置检查点
- `POST /v1/harness/receipt/{exec_id}`：上报执行收据
- `GET /v1/harness/status/{exec_id}`：查询执行状态

接口字段定义与现有 `code/action-registry/gateway.py` 的 EvidenceEntity / ExecutionContext 对齐，不新增网关策略语义。

---

## 3. MCP 适配器协议（接口边界）

### 3.1 设计意图

DGA-INFRA §1 明确列出「Harness + MCP 适配器 + 判定探针」。MCP 适配器是 Harness 与 MCP tool server 之间的翻译层，负责工具发现、传输适配和生命周期管理。本文档仅定义协议边界与状态转换，不绑定具体传输实现（stdio / SSE / HTTP）。

### 3.2 适配器职责边界

| 职责 | 归属 | 说明 |
|------|------|------|
| MCP tool discovery / schema 拉取 | Harness 初始化阶段 | 从 MCP server 拉取 tool list，转换为 Harness 内部可执行 schema；缓存于对象存储（checkpoint 同级目录） |
| 传输会话管理 | MCP 适配器 | 维护与 MCP server 的连接生命周期；Harness 不感知传输细节 |
| 工具调用重试与幂等 | Harness | 基于 Action Registry 网关下发的幂等键（M4）执行重试；适配器不重试 |
| 判定探针注入 | Harness | 探针以 sidecar 形式挂载到适配器调用链；探针本身不改变 MCP 协议 |
| 虚拟 key 限额扣减 | Harness（池层） | 适配器只消费现成限额，不感知配额逻辑 |

### 3.3 传输模式 transition（接口边界）

基于 `code/workflows/activities.py` 当前 mock 执行器签名，定义 MCP tool discovery / stdio / SSE 的 transition 方案（不改代码，只写 spec）：

- **stdio**：本地进程 / 开发门禁（CMP-17）保留模式；Harness 以子进程启动 MCP server，通过 stdin/stdout 交互。适合单机开发与现有 Harness 迁移。
- **SSE**：远程 MCP server 标准模式；Harness 以 SSE client 接入，适配器负责重连与事件分发。适合多环境（公司云 / 客户本地）场景。
- **HTTP**：未来扩展；当 MCP server 提供 HTTP 端点时，适配器仅增加 transport factory，不改变 Harness 核心状态机。

### 3.4 接口约束

- MCP 适配器必须无本地状态（对齐 DGA-INFRA §1「无本地状态」）；所有会话上下文必须能从检查点外置接口恢复。
- 适配器不持有凭证明文；MCP server 的认证凭据通过池层虚拟 key 或 OIDC 短期凭证注入（R-SEC-01）。
- 适配器的 decision log 不直接入证据流；所有判定记录必须经过 Action Registry 网关（R-POL-05），由网关统一写入证据层。

---

## 4. 检查点外置接口（接口边界）

### 4.1 设计意图

DGA-INFRA §1 明确「检查点外置」；M5 验收要点要求「换执行环境不丢业务状态」。检查点外置接口是 Harness 实现无本地状态的核心机制。

### 4.2 检查点对象 schema（接口边界）

```yaml
Checkpoint:
  checkpoint_id: string          # 全局唯一（CHK-xxxx），与 exec_id 绑定
  exec_id: string                # 关联的执行实例 ID
  env_id: string                 # 产生检查点的执行环境
  created_at: datetime           # 检查点创建时间
  content_hash: string           # 执行上下文内容摘要（SHA-256）
  storage_uri: string            # 对象存储路径（s3:// / oss:// / cos://）
  version: SemVer                # 检查点 schema 版本
  harness_version: SemVer        # 产生检查点的 Harness 版本（对齐 CalibrationDomain.harness_version）
  calibration_domain_id: string  # 关联的校准域 ID（R-EVID-04 / R-POOL-CALIB）
  isolation_level: string        # 执行环境隔离等级（process / container / vm）
  virtual_key_ref: string        # 本次执行使用的虚拟 key 引用（不存明文）
  tool_state:                    # MCP 工具调用中间状态（不落地本地）
    pending_calls: list[string]  # 待调用 tool_call_id 列表
    completed_calls: list[string]# 已完成 tool_call_id 列表
    results_uri: string          # 工具调用结果的对象存储 URI（大结果外置）
  resume_token: string           # 恢复执行所需的一次性令牌（防重放）
```

**字段来源与对齐**：

- `harness_version`：对齐现有 `CalibrationDomain.harness_version`（`schemas/include/core.yaml` 已有定义，范围 SemVer，必填，描述为「校准时依据的 Harness 版本」）。
- `calibration_domain_id`：对齐 R-EVID-04 / R-POOL-CALIB；每次执行必须携带校准域 ID，确保判定可溯源（DGA-INFRA 3.8）。
- `virtual_key_ref`：对齐 CMP-05 LiteLLM 虚拟 key 机制；检查点只存引用，不存明文（R-SEC-02）。
- `storage_uri`：对齐 CMP-09 对象存储；不绑定具体实现（SEL-07），但必须支持版本化 + 对象锁定（WORM）（R-EVID-03）。

### 4.3 外置接口操作

| 操作 | 方法 | 说明 |
|------|------|------|
| WriteCheckpoint | `PUT /v1/checkpoint/{checkpoint_id}` | 将检查点写入对象存储；幂等（同一 checkpoint_id 覆盖视为版本更新，保留历史版本） |
| ReadCheckpoint | `GET /v1/checkpoint/{checkpoint_id}?version=<SemVer>` | 从对象存储读取指定版本；未指定 version 则读最新 |
| DeleteCheckpoint | `DELETE /v1/checkpoint/{checkpoint_id}` | 仅在执行收据闭环后允许删除；删除前须验证对象锁定已释放（R-EVID-03） |

### 4.4 跨环境恢复流程

```text
环境 A（RUNNING）        对象存储          环境 B（COLD）
      │                      │                  │
      │  WriteCheckpoint     │                  │
      │─────────────────────▶│                  │
      │                      │                  │
      │ 环境 A 释放           │                  │
      │─────────────────────▶│                  │
      │                      │                  │
      │               ReadCheckpoint              │
      │◀─────────────────────────────────────────│
      │                      │                  │
      │  ResumeToken 验证     │                  │
      │──────────────────────┴──────────────────▶│
      │                      │                  │
      │              RUNNING（环境 B）            │
```

**恢复不丢业务状态**的判定条件：

- 检查点 `content_hash` 与执行上下文摘要一致（防静默篡改）。
- `resume_token` 未过期且未被使用（一次性，防重放）。
- 环境 B 的 `trust_label ≥ 任务 sensitivity`（R-POOL-TRUST）；若环境 B 等级不足，路由层拒绝恢复请求，升级 S5。

---

## 5. 多环境注册表 schema 扩展（接口边界）

### 5.1 设计意图

M5 验收要点要求「≥2 个执行环境」。当前 `schemas/dga-ontology.yaml` 在 `_repos/.github/dga/infra/schemas/include/` 中无 `ExecutionEnvironment` 类（2026-09-08 检索确认）。本草案定义扩展 schema，对齐池层 `LogicalEndpoint`（DGA-INFRA 3.1）与 `PoolAccount.health`（DGA-INFRA 3.9）。

### 5.2 扩展类定义（LinkML 草案）

```yaml
classes:
  ExecutionEnvironment:
    class_uri: dga:ExecutionEnvironment
    slots:
      - env_id
      - env_name
      - trust_label
      - isolation_level
      - health
      - quota
      - endpoint_ref
      - accountable_person
    attributes:
      env_id:
        pattern: "^ENV-[0-9]{4,}$"
        required: true
        description: 执行环境唯一 ID（与 LogicalEndpoint 并行，不等价；一个 endpoint 可映射到多个物理环境）。
      env_name:
        range: string
        required: true
        description: 人类可读名称（如 windev-01-wsl1 / linux-vm-01 / customer-edge-01）。
      trust_label:
        range: TrustLevel
        required: true
        description: 环境信任等级（T0/T1/T2，对齐 DGA-INFRA 3.2 R-POOL-TRUST；任务 sensitivity ≤ 环境 trust）。
      isolation_level:
        range: IsolationLevel
        required: true
        description: 隔离等级（process / container / vm / bare-metal）；决定可承接的任务最高 sensitivity。
      health:
        range: string
        description: 健康状态摘要（对齐 PoolAccount.health，DGA-INFRA 3.9；availability / latency / error_rate / last_failure_at）。
      quota:
        range: string
        description: 环境级配额摘要（并发上限 / 日执行次数 / 存储限额）；与池账本联动。
      endpoint_ref:
        range: string
        description: 关联的 LogicalEndpoint ID（DGA-INFRA 3.1；多个 ENV 可复用同一 endpoint 路由策略）。
      accountable_person:
        range: Person
        description: 具名责任人（对齐 CMP-01 / R-GOV-03）。
```

### 5.3 枚举扩展草案

```yaml
enums:
  IsolationLevel:
    description: 执行环境隔离等级（M5 新增）。
    permissible_values:
      process:
        description: 进程级隔离（WSL1 / namespace）；适合 T0 / 开发门禁（CMP-17）。
      container:
        description: 容器级隔离（Docker / Podman）；适合 T1 / 标准执行。
      vm:
        description: 虚拟机级隔离；适合 T1 / T2 敏感任务。
      bare-metal:
        description: 物理机隔离；适合 T2 / 客户本地部署（[DER-11]）。
```

### 5.4 与池层现有 schema 的对齐

| 新增字段 | 对齐的池层字段 | 来源 |
|----------|----------------|------|
| `trust_label` | `LogicalEndpoint.trust_level`（DGA-INFRA 3.1 / `schemas/include/pools.yaml` 已有 `TrustLevel` 枚举） | CMP-05 / R-POOL-TRUST |
| `health` | `PoolAccount.health`（DGA-INFRA 3.9 描述为 availability / latency / error_rate / last_failure_at） | R-POOL-EVID |
| `quota` | `PoolAccount.quota_state`（DGA-INFRA 3.1：RPM / TPM / 日额 / 月额 / 信用池余量） | R-POOL-QUOTA |
| `endpoint_ref` | `LogicalEndpoint.id`（DGA-INFRA 3.1：绑定 Account 集合 + 路由策略） | CMP-05 |

**不臆造**：`ExecutionEnvironment` 类不在当前 `_repos/.github/dga/infra/schemas/include/core.yaml`、`pools.yaml`、`enums.yaml` 中，本草案以「扩展草案」形式提出，进入治理仓须经 LinkML 变更评审（C1）。

### 5.5 注册表查询接口（接口边界）

```text
GET /v1/registry/environments?trust_label=T1&isolation_level=container
```

返回 `ExecutionEnvironment` 列表，字段由上述 schema 定义。Harness 路由层消费此接口，不直接访问池账本表。

---

## 6. 负面测试方向（验收谓词节）

### 6.1 验收谓词

每条谓词均为可判定条件（true/false），不依赖模糊描述。

| 编号 | 谓词 | 测试方向 | 对齐原文 |
|------|------|----------|----------|
| ACP-01 | Harness 接收已授权请求后，必须在 2 个以上 trust_label 不同的执行环境中成功路由 | 正向路由 | M5 验收要点「≥2 个执行环境」 |
| ACP-02 | 将执行环境 trust_label 下调至低于任务 sensitivity 后，路由层必须拒绝该环境 | 负面路由 | R-POOL-TRUST（DGA-INFRA 3.2：任务 sensitivity ≤ 端点 trust） |
| ACP-03 | 执行过程中 Harness 进程崩溃重启后，从外置检查点恢复的执行必须产出与正常路径一致的 EvidenceEntity（judge_model / judge_version / calibration_domain_id 完整） | 崩溃恢复 | DGA-INFRA §1「检查点外置」；R-EVID-04 |
| ACP-04 | 篡改对象存储中检查点的 `content_hash` 后，Harness 恢复流程必须拒绝并进入 FAILED，保留失败收据 | 篡改检测 | R-EVID-03（证据防篡改） |
| ACP-05 | 使用已使用过的 `resume_token` 尝试恢复检查点，必须被拒绝 | 重放防护 | 接口安全基线 |
| ACP-06 | 执行环境被标记 `isolation_level=process` 的任务，尝试在 `isolation_level=container` 以下环境恢复时，必须被路由层拒绝 | 隔离降级 | M5「多信任域」；R-POOL-DATA |
| ACP-07 | 虚拟 key 达到限额后，Harness 收到的 429 响应必须触发自动降级链路（T1→T1备用→低成本付费→队列等待），不得路由至 T0 | 熔断降级 | R-POOL-DEGRADE（DGA-INFRA 3.5）；CMP-05 |
| ACP-08 | 跨环境迁移时，源环境的检查点未删除前，目标环境不得启动同一 exec_id 的第二实例 | 幂等 | M5「换执行环境不丢业务状态」不意味着并发双实例 |
| ACP-09 | 检查点删除前，执行收据中的 `storage_uri` 必须仍可访问（对象锁定未释放） | 证据完整性 | R-EVID-03 / M6 依赖 |
| ACP-10 | MCP 适配器断开连接 30 秒后重连失败，Harness 必须进入 CHECKPOINT（PAUSED）而非无限重试 | 超时保护 | R-FLOW-02（唯一重试责任方；结果不明进待核实） |

### 6.2 负面测试不覆盖项（待 Linux 常驻机）

- 真实 ≥2 隔离执行环境的进程崩溃（需 Linux 服务化部署）。
- 对象存储 WORM 策略下的删除验证（需真实 bucket + IAM）。
- 虚拟 key 端到端扣费 + 熔断时延（需 LiteLLM 生产拓扑 + 多并发）。

---

## 7. 与既有 M0–M4 的关系

| 里程碑 | 本草案的依赖 | 说明 |
|--------|--------------|------|
| M0 | schemas 框架、ID 前缀体系 | ExecutionEnvironment 扩展需遵循 M0 定的 ID 规则（ENV-xxxx） |
| M1 | 控制面 DB、六元组 schema | Harness 执行收据最终落入控制面 EvidenceEntity 表 |
| M2 | 池账本、LiteLLM 虚拟 key、路由谓词 | Harness 路由层消费池账本 trust_label / quota_state |
| M3 | Temporal 流程定义 | Harness 执行单元由 Temporal workflow 调用，不承载等待 |
| M4 | Action Registry 网关、OPA decision log、幂等键 | Harness 只接受 M4 六级管线后的请求；decision log 入证据流由网关完成（R-POL-05） |

---

## 8. 治理与变更路径

### 8.1 工作层限制

本文档为工作层草案，不具备治理仓正本效力。

### 8.2 进治理仓路径

进治理仓须 C1 路径（PR + ADR + owner review）：

1. **PR**：提交至 `gov-infra-repo`（或 DGA-INFRA 正本仓）的 `docs/` 或 `schemas/` 目录。
2. **ADR**：记录 Harness 架构选型（进程级 vs 容器级 vs 虚拟机级默认隔离等级；MCP 适配器传输模式默认值；检查点 schema 版本策略）。
3. **owner review**：由 gov-infra repo owner（当前为 S5 指定负责人）评审 schema 扩展与接口边界。
4. **LinkML 生成验证**：schema 变更通过 `gen-python` / `gen-json-schema` / `gen-sqlddl` 生成验证后，方可合入。

### 8.3 与 SEL 的联动

- SEL-05（LiteLLM 核实）：虚拟 key 限额端到端验证依赖于本草案定义的限额绑定接口。
- SEL-07（对象存储核实）：检查点外置接口依赖于本草案定义的 storage_uri / version / 对象锁定语义。
- SEL-09（客户门户与客服）：不直接相关；Harness 状态查询可暴露给客户门户，但属 M9 范围。

---

## 9. 引用溯源

| 引用编号 | 来源文件 | 章节/位置 | 说明 |
|----------|----------|-----------|------|
| M5 验收要点 | DGA-INFRA §6 里程碑表 | M5 行 | Harness 接池 + ≥2 个执行环境 + 检查点外置 |
| CMP-17 | DGA-INFRA §2 组件表 | CMP-17 | 现有 Harness 保留，接入池层与控制面 |
| CMP-14 | DGA-INFRA §2 组件表 | CMP-14 | LangGraph，按需候选，Harness 内部图式协作 |
| CMP-05 | DGA-INFRA §2 组件表 | CMP-05 | LiteLLM Proxy，虚拟 key / 预算 / 路由 |
| R-POL-03 | DGA-INFRA §5 建设要求总表 | R-POL-03 | 池路由虚拟 key 限额落实子任务权限不放大 |
| R-POL-02 | DGA-INFRA §5 | R-POL-02 | 重建 Run 不得延长无人复核期限 |
| R-POL-01 | DGA-INFRA §5 | R-POL-01 | 权限检查在工具网关/服务端强制执行 |
| R-EVID-04 | DGA-INFRA §5 | R-EVID-04 | 判定证据必须含判定器模型+版本+校准域 ID |
| R-EVID-01 | DGA-INFRA §5 | R-EVID-01 | 证据契约独立定义 |
| R-EVID-03 | DGA-INFRA §5 | R-EVID-03 | 对象版本 + 内容摘要 + 独立写入权限 + 对象锁定 |
| R-EVID-05 | DGA-INFRA §5 | R-EVID-05 | 证据缺失是治理异常 |
| R-POOL-TRUST | DGA-INFRA §3.2 | R-POOL-TRUST | 信任标签路由（T0/T1/T2） |
| R-POOL-DATA | DGA-INFRA §3.3 | R-POOL-DATA | 数据红线 |
| R-POOL-DEGRADE | DGA-INFRA §3.5 | R-POOL-DEGRADE | 降级链 |
| R-POOL-QUOTA | DGA-INFRA §3.7 | R-POOL-QUOTA | 配额账本校准 |
| R-POOL-EVID | DGA-INFRA §3.9 | R-POOL-EVID | 池健康证据 |
| R-FLOW-01 | DGA-INFRA §5 | R-FLOW-01 | 跨系统流程进 Temporal；Agent 会话不承载等待 |
| R-FLOW-02 | DGA-INFRA §5 | R-FLOW-02 | 唯一重试责任方；结果不明进待核实 |
| R-SEC-01 | DGA-INFRA §5 | R-SEC-01 | Agent 接 GitHub 用应用身份 |
| R-SEC-02 | DGA-INFRA §5 | R-SEC-02 | 凭证明文仅存凭据库 |
| CalibrationDomain.harness_version | `schemas/include/core.yaml` | §CalibrationDomain | 校准时依据的 Harness 版本（已有字段） |
| LogicalEndpoint | `schemas/include/pools.yaml` | §LogicalEndpoint | 逻辑端点（绑定 Account 集合+路由策略） |
