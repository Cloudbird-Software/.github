# MCP 适配器协议 spec 草案

> **工作层草案，进治理仓须 C1 路径（PR + ADR + owner review）。**
> 本文档为 DGA-INFRA M5 第一顺位设计件，非治理仓正本。
> 起草日期：2026-09-08。

---

## 1. 目标与范围

### 1.1 来源锚点

- **M5 验收要点**（DGA-INFRA §6 里程碑表 M5 行）：Harness 接池 + ≥2 个执行环境 + 检查点外置；换执行环境不丢业务状态；虚拟 key 限额生效。
- **架构锚点**（DGA-INFRA §1 总体架构图）：「隔离执行单元（多信任域：公司云 ×N · 客户本地）— Harness + MCP 适配器 + 判定探针（无本地状态，检查点外置）」。
- **SEL-04 锚点**（`_repos/.github/dga/infra/catalog/sel/SEL-04.md` §4 / §5）：推荐集成 `agent-protocol`（MCP/A2A 对接面）作为工具网关/OPA 执行点的对接面；集成前提 = 所有工具调用经 OPA 网关（负面测试项）；纪律："不让 openJiuwen 的内部状态成为公司唯一状态"。
- **策略锚点**：R-POL-01（权限检查在工具网关/服务端强制执行）、R-POL-05（OPA decision log 入证据流）、R-EVID-04（判定证据必须含判定器模型+版本+校准域 ID）。

### 1.2 本草案覆盖

| 件 | 定位 | 本文件处理方式 |
|----|------|----------------|
| MCP 适配器协议 | 接口边界 | 全文详述（§2–§4） |
| A2A 对接面 | 预留 | §5 预留段落 |
| OPA 网关集成 | 负面测试项 | §3 集成段落 + §6 负面测试 |
| 检查点与状态恢复 | 依赖接口 | §4 接口边界段落 |

### 1.3 不覆盖

- MCP server 的具体实现（stdio / SSE / HTTP 传输实现属于第二波 Linux 常驻机到位后）。
- A2A 协议的具体 schema（当前 M5 仅展开 MCP；A2A 在 SEL-04 PoC 通过后按里程碑插槽纳入）。
- openJiuwen jiuwenswarm 应用层的多 agent 协同（SEL-04 明确不集成 jiuwenswarm）。

---

## 2. 适配器在 DGA-INFRA 总体架构中的位置

```
资源池层     LiteLLM（LLM 路由 + 虚拟key）· 计算调度（多执行环境路由）
────────────────────────────────────────────
隔离执行单元（多信任域：公司云 ×N · 客户本地）
  Harness + MCP 适配器 + 判定探针（无本地状态，检查点外置）
  ┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
  │ MCP Server  │◀───▶│ MCP 适配器协议    │◀───▶│  Harness    │
  │ (工具面)    │     │ (协议翻译/会话)   │     │ (编排核心)   │
  └─────────────┘     └────────▲─────────┘     └──────┬──────┘
                                │                     │
                                │              ┌──────┴──────┐
                                │              │ OPA 网关     │
                                │              │ (策略执法)    │
                                │              └─────────────┘
                                │
                    ┌───────────┴─────────────┐
                    │ 检查点外置（对象存储）    │
                    │ CMP-09 / R-EVID-03      │
                    └─────────────────────────┘
```

**权威源分工**（关键字段唯一主写者，允许多入口）：

| 信息 | 权威源 |
|------|--------|
| 工具调用授权 | OPA 网关（R-POL-01） |
| 执行上下文 / 检查点 | 对象存储（CMP-09 / R-EVID-03） |
| 虚拟 key 限额 | 池账本（CMP-05 / R-POL-03） |
| 判定证据 | 证据层（R-EVID-01 / R-EVID-04） |
| MCP 适配器会话状态 | 无本地状态；全部可从检查点外置接口恢复（DGA-INFRA §1） |

---

## 3. 适配器职责边界与协议约束

### 3.1 适配器职责边界

| 职责 | 归属 | 说明 | 对齐原文 |
|------|------|------|----------|
| MCP tool discovery / schema 拉取 | Harness 初始化阶段 | 从 MCP server 拉取 tool list，转换为 Harness 内部可执行 schema；缓存于对象存储（checkpoint 同级目录） | DGA-INFRA §1 |
| 传输会话管理 | MCP 适配器 | 维护与 MCP server 的连接生命周期；Harness 不感知传输细节 | 本草案 §3.3 |
| 工具调用重试与幂等 | Harness | 基于 Action Registry 网关下发的幂等键（M4）执行重试；适配器不重试 | R-FLOW-03 |
| 判定探针注入 | Harness | 探针以 sidecar 形式挂载到适配器调用链；探针本身不改变 MCP 协议 | DGA-INFRA §1 |
| 虚拟 key 限额扣减 | Harness（池层） | 适配器只消费现成限额，不感知配额逻辑 | CMP-05 / R-POOL-QUOTA |
| OPA 策略拦截 | OPA 网关 | 每个工具调用在网关层强制执行；适配器不绕过 | R-POL-01 / SEL-04 |
| OPA decision log 入证据 | OPA 网关 | 适配器不直接写证据流；decision log 由网关统一写入 | R-POL-05 |

### 3.2 MCP 协议版本协商

适配器在会话建立阶段必须完成 MCP 协议版本协商，流程如下：

1. `initialize` 请求携带 `protocolVersion`、`capabilities`、`clientInfo`。
2. MCP server 返回 `result.capabilities` 与 `result.instructions`。
3. 双方确认 `protocolVersion` 交集；若 server 不支持 client 声明的最低版本，适配器必须上报 `FAILED` 并进入检查点。
4. 版本协商结果写入检查点 `tool_state.version_handshake`，供跨环境恢复时使用。

**不臆造**：MCP 协议版本号当前以 `2025-03-26` 规格为基线（`modelcontextprotocol/specification` 仓库，截至 2026-09-06 未发现更新声明）。若后续版本更新，须经 C1 路径（PR + ADR + owner review）纳入本草案。

### 3.3 传输模式 transition（接口边界）

基于 `code/workflows/activities.py` 当前 mock 执行器签名，定义 MCP tool discovery / stdio / SSE 的 transition 方案（不改代码，只写 spec）：

- **stdio**：本地进程 / 开发门禁（CMP-17）保留模式；Harness 以子进程启动 MCP server，通过 stdin/stdout 交互。适合单机开发与现有 Harness 迁移。
- **SSE**：远程 MCP server 标准模式；Harness 以 SSE client 接入，适配器负责重连与事件分发。适合多环境（公司云 / 客户本地）场景。
- **HTTP**：未来扩展；当 MCP server 提供 HTTP 端点时，适配器仅增加 transport factory，不改变 Harness 核心状态机。

传输模式由 Harness 路由层根据 `ExecutionEnvironment.isolation_level` 与 `trust_label` 选择，适配器不自主选择传输模式。

### 3.4 工具 schema 转换格式

MCP server 返回的 `tools/list` 结果中的 `ToolSchema` 必须转换为 Harness 内部可执行 schema，转换规则如下：

```yaml
ToolSchema:
  name: string              # 原样保留（MCP server 工具名）
  description: string       # 原样保留
  inputSchema:              # 转换为 Harness 内部可执行 schema
    type: object
    properties: map[string, JsonSchema]
    required: list[string]
  outputSchema:             # Harness 内部约定
    type: object
    properties:
      content: list[ContentBlock]
      isError: boolean
  mcp_transport: string     # stdio / sse / http（由路由层注入）
  server_ref: string        # MCP server 标识（env_id + server_name）
```

转换后的 schema 缓存于对象存储，路径模式：

```
s3://<bucket>/checkpoints/{exec_id}/schemas/{tool_name}.json
```

恢复执行时，Harness 从对象存储读取 schema 版本，若与当前 MCP server 返回的 schema 不一致，触发 `SCHEMA_DRIFT` 事件并上报 FAILED。

### 3.5 会话生命周期与状态机

```text
                    ┌──────────┐
                    │ INIT     │  ← 版本协商 + 凭据注入
                    └────┬─────┘
                         │
                    ┌────▼─────┐
                    │ READY    │  ← tool discovery 完成，schema 缓存就绪
                    └────┬─────┘
                         │
              ┌──────────▼──────────┐
              │ TOOL_CALL           │  ← Harness 下发已授权工具调用（经 OPA 网关）
              └──────────┬──────────┘
                         │
              ┌──────────▼──────────┐
              │ RESULT_CAPTURE      │  ← 捕获工具返回；大结果外置到对象存储
              └──────────┬──────────┘
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

- **INIT**：适配器与 MCP server 建立连接，完成协议版本协商与凭据注入。
- **READY**：tool discovery 完成，schema 已缓存；等待 Harness 下发工具调用。
- **TOOL_CALL**：工具执行中；适配器将 MCP server 的响应流式回传 Harness。
- **RESULT_CAPTURE**：工具执行完成；结果若超过阈值（默认 1MB），外置到对象存储并返回 `results_uri`。
- **CHECKPOINT（PAUSED）**：主动暂停；当前会话上下文外置到检查点，等待跨环境恢复。
- **SUCCESS / FAILED**：执行终止；产出 EvidenceEntity，释放虚拟 key 限额，释放环境租约。

### 3.6 接口约束

- MCP 适配器必须无本地状态（对齐 DGA-INFRA §1「无本地状态，检查点外置」）；所有会话上下文必须能从检查点外置接口恢复。
- 适配器不持有凭证明文；MCP server 的认证凭据通过池层虚拟 key 或 OIDC 短期凭证注入（R-SEC-01）。
- 适配器的 decision log 不直接入证据流；所有判定记录必须经过 Action Registry 网关（R-POL-05），由网关统一写入证据层。
- 适配器禁止缓存超出当前 `exec_id` 生命周期的凭据或会话令牌；执行收据闭环后必须销毁（R-SEC-02）。

---

## 4. OPA 网关集成协议（接口边界）

### 4.1 设计意图

SEL-04 明确：「agent-protocol 的 MCP SDK 使 openJiuwen 生态的工具面可接我们的 OPA 工具网关」；「集成前提 = 所有工具调用经 OPA 网关，此为负面测试项」。

本草案将此纪律从 openJiuwen 语境提升为 MCP 适配器协议的通用约束：**一切工具调用必须经过 OPA 网关，无论工具来源是 MCP server 还是 Harness 内部 mock 执行器**。

### 4.2 OPA 网关拦截点

```text
Harness (编排)
    │
    │ 1. 下发工具调用请求（含 tool_name / arguments / exec_id / virtual_key_ref）
    ▼
OPA 网关（策略执法）
    │
    │ 2. 策略判定：权限 / 预算 / 信任标签 / 幂等键
    │
    ├── ALLOW → 3. 下发到 MCP 适配器
    │              │
    │              ▼
    │         MCP Adapter → MCP Server
    │              │
    │              ▼
    │         返回工具结果
    │
    └── DENY → 3. 返回拒绝信号给 Harness
                  │
                  ▼
             FAILED（保留失败收据）
```

**关键约束**：

- Harness 不得在 OPA 网关之前执行任何工具调用（R-POL-01："提示词级不算权限控制"）。
- OPA 网关返回 `DENY` 时，MCP 适配器不得收到任何工具调用请求。
- OPA decision log 必须包含 `tool_name`、`arguments_hash`、`exec_id`、`virtual_key_ref`、`judgment`（allow/deny）、`policy_id`，由网关写入证据流（R-POL-05）。

### 4.3 适配器在 OPA 拦截后的行为

| OPA 判定 | 适配器行为 | Harness 状态机动作 |
|----------|------------|-------------------|
| ALLOW | 正常执行 MCP tool call | 继续 RUNNING |
| DENY | 不执行；返回 `OPA_DENIED` 错误码 | 进入 FAILED，产出失败收据（R-EVID-05） |
| ERROR（OPA 不可达） | 不执行；返回 `OPA_UNAVAILABLE` | 进入 CHECKPOINT（PAUSED），等待 OPA 恢复或超时升级 |

---

## 5. A2A 对接面预留

### 5.1 预留说明

SEL-04 将 `agent-protocol` 定位为「MCP SDK / A2A SDK / A2X Registry（C++）」。当前 M5 验收要点与 DGA-INFRA v1.0 体系内未出现 A2A 协议条目，因此：

- **M5 范围**：仅展开 MCP 适配器协议；A2A SDK 与 A2X Registry 不纳入本里程碑。
- **预留位**：在 MCP 适配器协议的 transport factory 层保留 A2A transport adapter 插件位，后续里程碑可按 SEL-04 PoC 结果启用。
- **不变约束**：无论 A2A 还是 MCP，一切工具调用必须经过 OPA 网关（R-POL-01）；此约束对 agent-protocol 全系列生效。

### 5.2 A2A 纳入条件

A2A 对接面纳入 M5 或 M6 须满足以下条件（可判定）：

1. `_repos/.github/dga/infra/catalog/sel/SEL-04.md` PoC 阶段产出 A2A 可执行样例（含 OPA 网关拦截验证）。
2. DGA-INFRA 或 DGA-CORE 新增 A2A 对应条目（当前无原文编号，不臆造）。
3. 经过 C1 路径（PR + ADR + owner review）批准适配器协议扩展。

---

## 6. 检查点与状态恢复（接口边界）

### 6.1 检查点对象 schema 扩展（MCP 适配器部分）

```yaml
Checkpoint:
  checkpoint_id: string          # 全局唯一（CHK-xxxx），与 exec_id 绑定
  exec_id: string                # 关联的执行实例 ID
  env_id: string                 # 产生检查点的执行环境
  created_at: datetime           # 检查点创建时间
  content_hash: string           # 执行上下文内容摘要（SHA-256）
  storage_uri: string            # 对象存储路径（s3:// / oss:// / cos://）
  version: SemVer                # 检查点 schema 版本
  harness_version: SemVer        # 产生检查点的 Harness 版本
  calibration_domain_id: string  # 关联的校准域 ID（R-EVID-04 / R-POOL-CALIB）
  isolation_level: string        # 执行环境隔离等级（process / container / vm）
  virtual_key_ref: string        # 本次执行使用的虚拟 key 引用（不存明文）
  tool_state:                    # MCP 工具调用中间状态（不落地本地）
    pending_calls: list[string]  # 待调用 tool_call_id 列表
    completed_calls: list[string]# 已完成 tool_call_id 列表
    results_uri: string          # 工具调用结果的对象存储 URI（大结果外置）
    mcp_session_context: string  # MCP 会话上下文（会话 ID / 版本握手结果 / 重连令牌）
  resume_token: string           # 恢复执行所需的一次性令牌（防重放）
```

**字段来源与对齐**：

- `harness_version`：对齐现有 `CalibrationDomain.harness_version`（`schemas/include/core.yaml` 已有定义，范围 SemVer，必填）。
- `calibration_domain_id`：对齐 R-EVID-04 / R-POOL-CALIB；每次执行必须携带校准域 ID，确保判定可溯源（DGA-INFRA 3.8）。
- `virtual_key_ref`：对齐 CMP-05 LiteLLM 虚拟 key 机制；检查点只存引用，不存明文（R-SEC-02）。
- `mcp_session_context`：本草案新增；MCP 适配器恢复时必须能从检查点重建会话上下文，不得重新执行已完成工具调用。

### 6.2 跨环境恢复流程

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
      │  OPA 策略重验         │                  │
      │─────────────────────────────────────────▶│
      │                      │                  │
      │              RUNNING（环境 B）            │
```

**恢复不丢业务状态**的判定条件：

- 检查点 `content_hash` 与执行上下文摘要一致（防静默篡改）（R-EVID-03）。
- `resume_token` 未过期且未被使用（一次性，防重放）。
- `mcp_session_context` 完整；恢复后的适配器状态与暂停前一致（pending_calls / completed_calls）。
- 环境 B 的 `trust_label ≥ 任务 sensitivity`（R-POOL-TRUST）；若环境 B 等级不足，路由层拒绝恢复请求，升级 S5。
- OPA 网关对恢复后的待调用工具列表重新进行策略判定（R-POL-02：「恢复检查点须重验当前授权」）。

---

## 7. 与既有 M0–M4 的关系

| 里程碑 | 本草案的依赖 | 说明 |
|--------|--------------|------|
| M0 | schemas 框架、ID 前缀体系 | 检查点 schema 遵循 M0 定的 ID 规则（CHK-xxxx） |
| M1 | 控制面 DB、六元组 schema | Harness 执行收据最终落入控制面 EvidenceEntity 表 |
| M2 | 池账本、LiteLLM 虚拟 key、路由谓词 | Harness 路由层消费池账本 trust_label / quota_state；适配器消费虚拟 key |
| M3 | Temporal 流程定义 | Harness 执行单元由 Temporal workflow 调用，不承载等待 |
| M4 | Action Registry 网关、OPA decision log、幂等键 | Harness 只接受 M4 六级管线后的请求；所有工具调用经 OPA 网关（R-POL-01 / SEL-04） |

---

## 8. 负面测试方向（验收谓词节）

### 8.1 验收谓词

每条谓词均为可判定条件（true/false），不依赖模糊描述。

| 编号 | 谓词 | 测试方向 | 对齐原文 |
|------|------|----------|----------|
| MCP-ACP-01 | MCP 适配器在 stdio / SSE / HTTP 三种传输模式下，对同一工具调用的返回结果必须一致（schema 层可比较） | 传输无关性 | DGA-INFRA §1；本草案 §3.3 |
| MCP-ACP-02 | MCP server 返回 `initialize` 不支持 client 声明的最低协议版本时，适配器必须上报 `FAILED` 并不建立会话 | 版本协商 | 本草案 §3.2 |
| MCP-ACP-03 | 工具调用 schema 与对象存储缓存 schema 不一致时，适配器必须触发 `SCHEMA_DRIFT` 并上报 FAILED | 漂移检测 | 本草案 §3.4 |
| MCP-ACP-04 | OPA 网关对某工具调用返回 DENY 时，MCP 适配器不得执行该工具调用，且 Harness 必须产出含 `OPA_DENIED` 标记的失败收据 | **一切工具调用经 OPA 网关** | R-POL-01 / SEL-04 |
| MCP-ACP-05 | 模拟网络攻击者绕过 OPA 网关直连 MCP server 时，连接必须被网络策略阻断（egress 白名单），事件入证据流 | **绕过网关直连=负面测试项** | SEL-04 §5；R-POL-01 |
| MCP-ACP-06 | 执行过程中 MCP server 崩溃重启后，适配器必须能从检查点恢复会话上下文，且不重放已成功完成的工具调用 | 崩溃恢复 | 本草案 §6.1；DGA-INFRA §1 |
| MCP-ACP-07 | `resume_token` 被使用两次时，第二次恢复请求必须被拒绝 | 重放防护 | 本草案 §6.1 |
| MCP-ACP-08 | 跨环境恢复时，目标环境的 `trust_label < 任务 sensitivity`，路由层必须拒绝恢复 | 信任标签路由 | R-POOL-TRUST（DGA-INFRA 3.2） |
| MCP-ACP-09 | 工具调用结果超过 1MB 阈值时，适配器必须外置到对象存储并返回 `results_uri`，不得在会话内存中保留 | 大结果外置 | CMP-09 / R-EVID-03 |
| MCP-ACP-10 | 适配器会话建立后，本地内存中不得留存 MCP server 的认证凭证明文；执行收据闭环后必须确认销毁 | 凭据管理 | R-SEC-02 |
| MCP-ACP-11 | OPA 网关不可达时，适配器必须进入 `OPA_UNAVAILABLE` 状态并触发 CHECKPOINT，不得在策略缺失时继续执行 | 策略缺失保护 | R-POL-01 |

### 8.2 负面测试不覆盖项（待 Linux 常驻机）

- 真实远程 MCP server 的 SSE 长连接抖动与重连（需 Linux 服务化部署）。
- 多并发 MCP 会话共享同一池账号时的限额争用（需 LiteLLM 生产拓扑）。
- A2A 协议的实际对接与 OPA 拦截验证（需 SEL-04 PoC 通过后）。

---

## 9. 与 openJiuwen agent-protocol 的对齐

### 9.1 SEL-04 对齐声明

- **集成候选**：`agent-protocol`（MCP SDK / A2A SDK），不集成 `jiuwenswarm`（应用而非框架）、禁用 `deepsearch`（无 LICENSE）。
- **协议面**：MCP SDK 对接 OPA 工具网关，不改变 DGA 现有六级管线（注册表→jsonschema→OPA→R-EVID-04→幂等→mock 执行器）。
- **纪律**：openJiuwen 内部状态（runtime 会话、Studio 配置）不承载权威状态；权威源 = 控制面 DB 与 Git（SEL-04 §4）。
- **负面测试项**：所有 agent-protocol 工具调用必须经 OPA 网关，此为 SEL-04 明确声明的集成前提。

### 9.2 PoC 对接点

| PoC 项 | 本草案接口 | 验证方式 |
|--------|------------|----------|
| agent-core pip 安装 + 样例跑通 | 工具调用路径（Harness → OPA → 适配器 → MCP） | 本机 Python 环境 |
| agent-protocol MCP SDK 示例工具 | MCP 适配器协议 §3 tool schema 转换 | OPA sidecar 网关之后 |
| OTel trace 导出 | 适配器 OTel span 命名约定 | 与 OTel/Langfuse 管道联调 |

---

## 10. 治理与变更路径

### 10.1 工作层限制

本文档为工作层草案，不具备治理仓正本效力。

### 10.2 进治理仓路径

进治理仓须 C1 路径（PR + ADR + owner review）：

1. **PR**：提交至 `gov-infra-repo`（或 DGA-INFRA 正本仓）的 `docs/` 或 `schemas/` 目录。
2. **ADR**：记录 MCP 适配器传输模式默认值（stdio / SSE）、A2A 纳入时间点、schema 版本策略。
3. **owner review**：由 gov-infra repo owner（当前为 S5 指定负责人）评审协议边界与负面测试项。
4. **openJiuwen 版本钉死**：PoC 期 commit-level pin + 供应商镜像留存，缓解 <1.0 上游漂移（SEL-04 §7）。

### 10.3 与 SEL 的联动

- **SEL-04**：本草案是 SEL-04 推荐集成位（agent-protocol MCP/A2A 对接面）的协议层落地；SEL-04 PoC 结果决定 A2A 纳入时间。
- **SEL-05**：虚拟 key 限额端到端验证依赖于本草案定义的限额绑定接口。
- **SEL-07**：检查点外置接口依赖于本草案定义的 storage_uri / version / 对象锁定语义。

---

## 11. 引用溯源

| 引用编号 | 来源文件 | 章节/位置 | 说明 |
|----------|----------|-----------|------|
| M5 验收要点 | DGA-INFRA §6 里程碑表 | M5 行 | Harness 接池 + ≥2 个执行环境 + 检查点外置 |
| DGA-INFRA §1 总体架构图 | DGA-INFRA §1 | 架构图 | 「Harness + MCP 适配器 + 判定探针（无本地状态，检查点外置）」 |
| CMP-14 | DGA-INFRA §2 组件表 | CMP-14 | LangGraph，按需候选，Harness 内部图式协作 |
| CMP-17 | DGA-INFRA §2 组件表 | CMP-17 | 现有 Harness 保留，接入池层与控制面 |
| CMP-05 | DGA-INFRA §2 组件表 | CMP-05 | LiteLLM Proxy，虚拟 key / 预算 / 路由 |
| CMP-09 | DGA-INFRA §2 组件表 | CMP-09 | 对象存储，证据与大工件 |
| R-POL-01 | DGA-INFRA §5 | R-POL-01 | 权限检查在工具网关/服务端强制执行 |
| R-POL-02 | DGA-INFRA §5 | R-POL-02 | 子任务权限 ≤ 父任务；恢复检查点须重验当前授权 |
| R-POL-05 | DGA-INFRA §5 | R-POL-05 | OPA decision log 入证据流 |
| R-EVID-01 | DGA-INFRA §5 | R-EVID-01 | 证据契约独立定义 |
| R-EVID-03 | DGA-INFRA §5 | R-EVID-03 | 对象版本 + 内容摘要 + 独立写入权限 + 对象锁定 |
| R-EVID-04 | DGA-INFRA §5 | R-EVID-04 | 判定证据必须含判定器模型+版本+校准域 ID |
| R-EVID-05 | DGA-INFRA §5 | R-EVID-05 | 证据缺失是治理异常 |
| R-POOL-TRUST | DGA-INFRA §3.2 | R-POOL-TRUST | 信任标签路由（T0/T1/T2） |
| R-SEC-01 | DGA-INFRA §5 | R-SEC-01 | Agent 接 GitHub 用应用身份 |
| R-SEC-02 | DGA-INFRA §5 | R-SEC-02 | 凭证明文仅存凭据库 |
| R-FLOW-03 | DGA-INFRA §5 | R-FLOW-03 | 幂等键 + 结果核对 + 补偿 |
| SEL-04 | `_repos/.github/dga/infra/catalog/sel/SEL-04.md` | §3/§4/§5 | agent-protocol MCP/A2A 对接面；集成前提=所有工具调用经 OPA 网关（负面测试项）；不让 openJiuwen 内部状态成为公司唯一状态 |
| CalibrationDomain.harness_version | `schemas/include/core.yaml` | §CalibrationDomain | 校准时依据的 Harness 版本（已有字段） |
