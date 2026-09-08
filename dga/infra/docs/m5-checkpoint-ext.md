# 检查点外置接口 spec（完整草案）

> **工作层草案，进治理仓须 C1 路径（PR + ADR + owner review）。**
> 本文档为 DGA-INFRA M5 检查点外置接口的完整 spec，非治理仓正本。
> 起草日期：2026-09-08。
> 本草案展开 `plans/2026-09-09-m5-harness-spec-draft.md` §4「检查点外置接口（接口边界）」的接口边界段落，不重复其状态机与恢复流程图；二者叠加构成完整接口定义。

---

## 1. 目标与范围

### 1.1 来源锚点

- **M5 验收要点**（DGA-INFRA §6 里程碑表 M5 行）：Harness 接池 + ≥2 个执行环境 + 检查点外置；换执行环境不丢业务状态。
- **架构锚点**（DGA-INFRA §1 总体架构图）：隔离执行单元「Harness + MCP 适配器 + 判定探针（无本地状态，检查点外置）」。
- **组件锚点**：CMP-09（对象存储：版本化 + 对象锁定 WORM）；CMP-17（现有 Harness 保留，单次执行与开发门禁）；CMP-05（LiteLLM 虚拟 key 限额）。
- **策略锚点**：
  - R-EVID-03（对象版本 + 内容摘要 + 独立写入权限 + 对象锁定；防篡改证明"记录未被改"）。
  - R-EVID-04（判定证据必须含判定器模型 + 版本 + 校准域 ID）。
  - R-EVID-05（证据缺失是治理异常）。
  - R-POL-02（子任务权限 ≤ 父任务；重建 Run 须重验当前授权；恢复检查点须重验当前授权）。
  - R-POL-03（池路由的虚拟 key 限额落实子任务权限不放大）。
  - R-SEC-02（凭证明文仅存凭据库；控制面 / Git / 飞书仅存引用）。
  - R-FLOW-01（跨系统流程进 Temporal；Agent 会话不承载等待）。

### 1.2 本草案覆盖

| 件 | 定位 | 本文件处理方式 |
|----|------|----------------|
| 检查点对象 schema（字段、类型、验证、不可变属性） | 核心 | §2 完整字段规格 |
| 版本与 schema 演化策略 | 核心 | §3 |
| 篡改检测（SHA-256 规范输入 + 验证协议） | 核心 | §4 |
| 重放防护（resume_token 生命周期） | 核心 | §5 |
| 存储生命周期（WORM、保留、孤儿清理、证据关联） | 核心 | §6 |
| REST 接口操作（请求 / 响应 / 错误码 / 幂等） | 接口 | §7 |
| 跨环境恢复完整流程（含授权重验） | 接口 | §8 |

### 1.3 不覆盖

- 实现代码、部署脚本、服务启动配置。
- 对象存储具体选型（SEL-07 输出；本草案仅消费其接口语义：版本化 + 对象锁定）。
- LangGraph 集成细节（CMP-14 按需候选；检查点序列化格式预留 LangGraph checkpoint 兼容位）。

---

## 2. 检查点对象完整字段规格

本节的 schema 骨架对齐 `plans/2026-09-09-m5-harness-spec-draft.md` §4.2，此处逐字段展开类型约束、验证规则、不可变属性与示例值。

```yaml
Checkpoint:
  checkpoint_id:
    type: string
    pattern: "^CHK-[0-9]{4,}$"
    required: true
    immutable: true
    description: 全局唯一检查点 ID，与 exec_id 绑定；由 Harness 在 WriteCheckpoint 前生成。
    example: "CHK-0001"

  exec_id:
    type: string
    required: true
    immutable: true
    description: 关联的执行实例 ID；跨环境恢复时用于路由与幂等。
    example: "EXEC-0042"

  env_id:
    type: string
    required: true
    description: 产生检查点的执行环境 ID（对齐 ExecutionEnvironment.env_id，ID 前缀 ENV-xxxx）。
    example: "ENV-0001"

  created_at:
    type: datetime
    required: true
    immutable: true
    description: 检查点创建时间（ISO 8601 with UTC）；由 Harness 写入时自动赋值。
    example: "2026-09-08T14:32:00Z"

  content_hash:
    type: Sha256Hex
    required: true
    description: 执行上下文内容摘要；输入为 tool_state 的规范序列化（见 §4）。Harness 写入时计算；对象存储层或恢复端均须独立重算比对。
    example: "a3b2c4d5e6f7..."

  storage_uri:
    type: Uri
    required: true
    description: 对象存储路径（s3:// / oss:// / cos:// / ...）；必须指向支持版本化 + WORM 的 bucket（CMP-09 / R-EVID-03）。
    example: "s3://dga-evidence/checkpoints/CHK-0001/v1"

  version:
    type: SemVer
    required: true
    description: 检查点 schema 版本（本字段自身的版本，不是存储对象版本）；参见 §3 版本策略。
    example: "1.0.0"

  harness_version:
    type: SemVer
    required: true
    description: 产生检查点的 Harness 版本。
    authority: _repos/.github/dga/infra/schemas/include/core.yaml L212–215
    description_source: "校准时依据的 Harness 版本"（CalibrationDomain.harness_version 原文描述）
    example: "0.9.0"

  calibration_domain_id:
    type: string
    required: true
    description: 关联的校准域 ID（CAL-xxxx；R-EVID-04 / R-POOL-CALIB）；恢复时用于判定器溯源与环境兼容性校验。
    example: "CAL-0012"

  isolation_level:
    type: IsolationLevel
    required: true
    description: 执行环境隔离等级（process / container / vm / bare-metal）；决定可承接的任务最高 sensitivity。
    example: "container"

  virtual_key_ref:
    type: string
    required: true
    description: 本次执行使用的虚拟 key 引用（不存明文；R-SEC-02 / CMP-05）；恢复时须重验当前授权与限额状态（R-POL-02）。
    example: "vkey-7f3a9c"

  tool_state:
    type: ToolState
    required: true
    description: MCP 工具调用中间状态；Harness 进程本地不持久化，仅通过本字段外置。
    subfields:
      pending_calls:
        type: list[string]
        description: 待调用 tool_call_id 列表。
        example: ["tc-001", "tc-002"]
      completed_calls:
        type: list[string]
        description: 已完成 tool_call_id 列表。
        example: ["tc-000"]
      results_uri:
        type: Uri
        description: 工具调用结果的对象存储 URI（大结果外置；避免 checkpoint 对象过大）。
        example: "s3://dga-evidence/results/EXEC-0042/tc-001/result.json"

  resume_token:
    type: string
    required: true
    immutable: true
    description: 恢复执行所需的一次性令牌；防重放（参见 §5）。
    example: "rt-abc123def456"
```

### 2.1 不可变字段清单

以下字段在 checkpoint 写入对象存储后禁止修改；任何修改尝试必须触发 R-EVID-03 违规告警：

- `checkpoint_id`
- `exec_id`
- `created_at`
- `content_hash`
- `version`（schema 版本；对象存储自身版本号由存储层管理，与本字段无关）
- `harness_version`
- `calibration_domain_id`
- `resume_token`

### 2.2 字段来源对齐速查

| 字段 | 对齐本体 / 策略 | 说明 |
|------|----------------|------|
| `harness_version` | `CalibrationDomain.harness_version`（`core.yaml` L212–215，SemVer，required） | 直接复用既有字段语义；检查点与校准域共用同一 Harness 版本声明。 |
| `calibration_domain_id` | R-EVID-04 / R-POOL-CALIB | 判定溯源三要件之一（判定器模型 + 版本 + 校准域 ID）。 |
| `virtual_key_ref` | CMP-05 / R-POL-03 / R-SEC-02 | 仅存引用，不存明文；恢复时重验限额与授权。 |
| `storage_uri` | CMP-09 / R-EVID-03 | 硬要求：版本化 + WORM；不绑定具体实现（SEL-07）。 |
| `isolation_level` | ExecutionEnvironment.isolation_level（M5 env registry 扩展草案） | 与执行环境注册表联动。 |

---

## 3. 版本与 schema 演化策略

### 3.1 版本号语义

- `version` 字段使用 SemVer 2.0.0。
- **Major**：移除字段、字段类型变更、`immutable: true` 字段改为可变（破坏旧读取器）。
- **Minor**：新增可选字段、新增枚举值（不破坏旧读取器；旧读取器忽略未知字段）。
- **Patch**：描述文本修正、验证规则细化（不改变结构）。

### 3.2 向后兼容承诺

- Harness 必须能读取 `version <= 当前生产 harness_version` 的检查点（即向下兼容）。
- 当 Harness 自身 `harness_version` 升级后，若 checkpoint schema version 发生 major 变更，Harness 应在写入时拒绝并升级 S5（禁止静默降级为旧 schema 写入）。

### 3.3 schema 版本映射表（治理仓登记）

进治理仓后，在 `schemas/include/checkpoints.yaml` 中维护版本映射表：

```yaml
checkpoint_schema_versions:
  - version: "1.0.0"
    supported_by_harness: ">=0.9.0"
    changes: "初始版本"
    deprecated_fields: []
```

---

## 4. 篡改检测

### 4.1 SHA-256 规范输入

`content_hash` 的输入为 `tool_state` 的规范序列化（canonical serialization），规则如下：

1. **键排序**：JSON 对象键按字典序升序排列。
2. **无空格**：去除所有空白字符（空格、换行、缩进）。
3. **Unicode 归一化**：采用 NFC。
4. **大结果外置**：若 `results_uri` 指向外部对象，`content_hash` 不包含该对象内容；但须在 `tool_state` 内包含 `results_uri` 本身的字符串，以及该对象在存储层的 `ETag` 或版本 ID，形成"指针级"可验证摘要。
5. **哈希域定义**：`content_hash = SHA-256( canonical_json(tool_state) )`，输出为 lowercase hex，无 `0x` 前缀。

### 4.2 验证协议

| 时机 | 验证方 | 动作 |
|------|--------|------|
| WriteCheckpoint 写入时 | Harness | 计算 `tool_state` 的 `content_hash`；写入对象存储后，立即执行 `GET` 并对返回体重算哈希，比对一致才向网关回报成功。 |
| ReadCheckpoint 恢复时 | Harness（恢复端） | 读取对象后，对 `tool_state` 字段重算哈希；若与对象内 `content_hash` 不一致，进入 FAILED，保留失败收据（R-EVID-05）。 |
| 证据抽审时 | 治理审计 | 对 `storage_uri` 指向的对象独立读取并重算哈希；若与 EvidenceEntity 中的 `content_digest` 不一致，标记证据链断裂。 |

### 4.3 篡改检测失败处置

- 对象存储层返回的 `content_hash` 与 Harness 重算值不一致：
  - 立即终止恢复流程，进入 `FAILED`。
  - 产出 EvidenceEntity，`evidence_type = "checkpoint_tamper"`，包含原始哈希与重算哈希。
  - 保留失败收据中的 `storage_uri` 与 `object_version`，供后续取证。
  - 升级 S5（R-EVID-03 违规 = 治理事件）。
- 对象存储层返回 HTTP 412 / 版本冲突：
  - 视为潜在并发篡改，拒绝覆盖，进入 FAILED。

---

## 5. 重放防护

### 5.1 `resume_token` 生成

- 格式：URL-safe Base64 编码的 256-bit 随机数（即 43 字符，无 padding）。
- 输入熵源：操作系统 CSPRNG（Windows：`BCryptGenRandom` / Python `secrets.token_urlsafe(32)`）。
- 生成时机：Harness 在 `WriteCheckpoint` 成功后生成；生成逻辑不在执行环境本地，而在 Harness 控制面侧，确保与执行上下文绑定。

### 5.2 生命周期

| 阶段 | 动作 |
|------|------|
| 生成 | WriteCheckpoint 成功后生成；写入 checkpoint 对象。 |
| 有效期 | 由执行授权 `decision_timespan` 决定；默认不超过 24 小时。超期未使用的 `resume_token` 视为失效。 |
| 消费 | ReadCheckpoint 恢复成功且状态机进入 `RUNNING` 后，立即将 `resume_token` 标记为 `USED`（在对象存储同目录写入 `resume_token.used` 标记对象，或利用存储层原子操作）。 |
| 一次性 | 同一 `resume_token` 第二次出现时，拒绝恢复请求，进入 FAILED，产出 EvidenceEntity（`evidence_type = "replay_attempt"`）。 |

### 5.3 并发竞态处理

- 两个环境同时发起 `ReadCheckpoint`：
  - 对象存储层对 `resume_token` 状态对象的写入采用 compare-and-swap（CAS）；先到先得。
  - 后到者收到 `409 Conflict`，拒绝恢复。
  - 后到者 Harness 进入 FAILED，保留失败收据；不无限重试（R-FLOW-02）。

### 5.4 过期与清理

- `resume_token` 过期后，对应的 checkpoint 对象可进入"待删除"队列，但须满足以下条件才能最终删除：
  - 执行收据已闭环（EvidenceEntity 已写入）。
  - 对象锁定（WORM）已释放或已过保留期。
  - 无未完成的漂移重估或审计引用。

---

## 6. 存储生命周期

### 6.1 保留策略

- 检查点对象的保留期不小于关联执行收据的法定保留期（当前待 S5 裁决，见 DGA-INFRA §9 第 6 项；默认方案 = 90 天）。
- 已闭环执行（SUCCESS / FAILED）的 checkpoint，保留期从执行收据 `created_at` 起算。
- 未闭环（PAUSED / 超时）的 checkpoint 不进入自动清理，须人工介入或漂移重估工作流触发。

### 6.2 WORM 锁定与释放

- WriteCheckpoint 写入时，对象存储层自动施加 WORM 锁（CMP-09 / R-EVID-03）。
- 锁释放条件：
  - 执行收据已闭环。
  - 漂移重估工作流已消费该 checkpoint 的 `content_digest`（若适用）。
  - 保留期届满。
- 任何提前删除 / 解锁请求必须携带 S5 授权引用（`approval_ref`），否则返回 `403 Forbidden`。

### 6.3 孤儿 checkpoint 清理

- 定义：`exec_id` 在控制面 DB 中不存在，或执行状态为 `FAILED` 且超 7 天无收据闭环。
- 清理流程：
  1. 扫描对象存储中 `storage_uri` 前缀。
  2. 与控制面 DB 的 `exec_id` 索引比对。
  3. 对孤儿对象施加标记，等待保留期届满后删除。
  4. 清理事件入证据流（`evidence_type = "orphan_checkpoint_cleaned"`）。

### 6.4 与 EvidenceEntity 的关联

- **WriteCheckpoint 事件**：Harness 在 checkpoint 写入成功后，必须产出 PreliminaryEvidence（轻量收据），包含 `checkpoint_id`、`storage_uri`、`content_hash`、`harness_version`、`calibration_domain_id`。此收据不进入最终判定，仅用于审计追踪。
- **ReadCheckpoint 恢复事件**：恢复成功进入 `RUNNING` 后，Harness 须在 EvidenceEntity 中追加 `restored_from_checkpoint_id` 字段，确保恢复动作本身可追溯（R-EVID-05）。
- **DeleteCheckpoint 事件**：删除前，Harness 必须验证执行收据中的 `storage_uri` 仍可访问（对象锁定未释放），防止证据链断裂（R-EVID-03 / M6 依赖）。

---

## 7. 接口操作详述

### 7.1 WriteCheckpoint

```
PUT /v1/checkpoint/{checkpoint_id}
```

**请求头**：

| Header | 必填 | 说明 |
|--------|------|------|
| `Authorization` | 是 | Bearer token（池层虚拟 key 或控制面服务账号） |
| `X-Harness-Version` | 是 | Harness 版本（与 body.harness_version 一致） |
| `X-Calibration-Domain` | 是 | 校准域 ID |
| `Idempotency-Key` | 否 | 幂等键；同一 exec_id + checkpoint_id + idempotency_key 重复提交视为版本更新，保留历史版本。 |

**请求体**：`Checkpoint` 对象（§2 完整字段）。

**响应**：

| 状态码 | 说明 |
|--------|------|
| `201 Created` | 写入成功；首次创建。 |
| `200 OK` | 幂等更新成功（同 checkpoint_id 已存在，视为版本更新）。 |
| `400 Bad Request` | schema 校验失败（缺失必填字段、SemVer 格式错误、immutable 字段重复写入）。 |
| `401 Unauthorized` | 缺少或无效 Authorization。 |
| `403 Forbidden` | virtual_key_ref 限额不足或 trust_label 不足（R-POOL-TRUST）。 |
| `409 Conflict` | resume_token 已被消费或 storage_uri 对象锁定冲突。 |
| `413 Payload Too Large` | checkpoint 对象超过对象存储单对象上限（默认 5 GiB）。 |

**对象存储层行为**：

- 自动启用版本化（version-id 由存储层分配）。
- 自动施加 WORM 锁（配置级，非每次调用）。
- 保留至少 2 个历史版本（可配置）。

### 7.2 ReadCheckpoint

```
GET /v1/checkpoint/{checkpoint_id}?version=<SemVer>&restore=true
```

**查询参数**：

| 参数 | 必填 | 说明 |
|------|------|------|
| `version` | 否 | 读取指定 schema 版本对应的对象；未指定则读取最新。 |
| `restore` | 否 | 布尔值；若为 `true`，接口除返回 checkpoint 体外，同时原子性标记 `resume_token` 为 `RESERVED`（预留），预留有效期 30 秒。 |

**响应**：

| 状态码 | 说明 |
|--------|------|
| `200 OK` | 读取成功；若 `restore=true`，`resume_token` 已被预留。 |
| `400 Bad Request` | `version` 格式错误或 `restore` 参数非法。 |
| `404 Not Found` | checkpoint_id 不存在或已删除。 |
| `410 Gone` | checkpoint 已过期（超过保留期或已被明确删除）。 |
| `412 Precondition Failed` | `content_hash` 校验失败（存储层重算不一致）。 |
| `409 Conflict` | `resume_token` 已被其他恢复请求预留 / 消费。 |

### 7.3 DeleteCheckpoint

```
DELETE /v1/checkpoint/{checkpoint_id}?approval_ref=<AUT-xxxx>
```

**查询参数**：

| 参数 | 必填 | 说明 |
|------|------|------|
| `approval_ref` | 条件必填 | 若对象 WORM 锁未自动释放，必须提供 S5 授权引用；自动释放时可为空。 |

**响应**：

| 状态码 | 说明 |
|--------|------|
| `204 No Content` | 删除成功。 |
| `400 Bad Request` | `approval_ref` 缺失但 WORM 锁未释放。 |
| `404 Not Found` | checkpoint_id 不存在。 |
| `409 Conflict` | 执行收据尚未闭环，或 WORM 锁仍在保护期。 |
| `423 Locked` | WORM 锁未释放且无有效 `approval_ref`。 |

---

## 8. 跨环境恢复完整流程

本流程对齐 `plans/2026-09-09-m5-harness-spec-draft.md` §4.4 跨环境恢复流程，增加 R-POL-02「恢复检查点须重验当前授权」步骤。

```
环境 A（RUNNING）        对象存储          环境 B（COLD）
      │                      │                  │
      │  WriteCheckpoint     │                  │
      │─────────────────────▶│                  │
      │                      │                  │
      │ 环境 A 释放           │                  │
      │─────────────────────▶│                  │
      │                      │                  │
      │               ReadCheckpoint ?restore=true
      │◀─────────────────────────────────────────│
      │                      │                  │
      │  resume_token 预留    │                  │
      │──────────────────────┴──────────────────▶│
      │                      │                  │
      │  R-POL-02: 重验当前授权                    │
      │  - Authorization.valid_until >= now      │
      │  - virtual_key_ref 限额未耗尽             │
      │  - env B trust_label >= 任务 sensitivity  │
      │  - calibration_domain_id 仍然有效         │
      │                      │                  │
      │  content_hash 重算比对                     │
      │──────────────────────┴──────────────────▶│
      │                      │                  │
      │             RUNNING（环境 B）             │
      │                      │                  │
      │  EvidenceEntity 追加                      │
      │  restored_from_checkpoint_id = CHK-0001  │
      │─────────────────────────────────────────▶│
```

### 8.1 恢复不丢业务状态的判定条件

1. `content_hash` 与执行上下文摘要一致（防静默篡改；§4）。
2. `resume_token` 未过期且未被使用（一次性，防重放；§5）。
3. 当前授权有效（R-POL-02）：
   - `Authorization.valid_until >= now`；
   - `virtual_key_ref` 限额未耗尽；
   - 环境 B `trust_label >= 任务 sensitivity`（R-POOL-TRUST）。
4. `calibration_domain_id` 仍然有效（`CalibrationDomain.validity_status == true`；若池组成已漂移，应触发漂移重估工作流，不允许静默恢复）。
5. `isolation_level` 满足任务要求（不降级恢复；例如 `vm` 隔离任务不得恢复到 `process` 环境）。

### 8.2 恢复失败处置

- 上述任一条件不满足，Harness 进入 `FAILED`。
- 保留原始 checkpoint（不删除），产出失败收据。
- 收据中必须包含失败原因编码（auth_expired / trust_insufficient / hash_mismatch / token_reused / calibration_invalid / isolation_downgrade）。
- 不无限重试（R-FLOW-02）。

---

## 9. 验收谓词（可判定，含负面测试方向）

### 9.1 验收谓词

每条谓词均为可判定条件（true/false），不依赖模糊描述。

| 编号 | 谓词 | 测试方向 | 对齐原文 |
|------|------|----------|----------|
| CKP-01 | WriteCheckpoint 成功后，对象存储返回对象的 `content_hash` 与 Harness 写入前重算值一致 | 正向篡改检测 | R-EVID-03 |
| CKP-02 | 修改对象存储中 checkpoint 对象的 `tool_state` 后，Harness ReadCheckpoint 恢复必须检测到 `content_hash` 不一致并拒绝 | 篡改检测 | R-EVID-03 |
| CKP-03 | 同一 `resume_token` 第二次用于 ReadCheckpoint ?restore=true 时，接口必须返回 `409 Conflict` | 重放防护 | R-FLOW-02 / R-SEC-04 |
| CKP-04 | `resume_token` 超过有效期后，ReadCheckpoint 必须返回 `410 Gone` 或等效拒绝 | 过期保护 | R-POL-02（决断时距到期即停） |
| CKP-05 | 两个并发恢复请求同时携带同一 `resume_token` 时，仅第一个成功，第二个收到 `409 Conflict` | 并发安全 | R-FLOW-02 |
| CKP-06 | 执行收据闭环前，DeleteCheckpoint 必须返回 `409 Conflict` 或 `423 Locked` | 证据完整性 | R-EVID-03 / M6 依赖 |
| CKP-07 | 恢复流程中，`Authorization.valid_until` 已过期时，Harness 必须拒绝恢复并进入 FAILED | 授权重验 | R-POL-02 |
| CKP-08 | 恢复流程中，环境 B 的 `trust_label` 低于任务 `sensitivity` 时，Harness 必须拒绝恢复并进入 FAILED | 信任路由 | R-POOL-TRUST（DGA-INFRA 3.2：任务 sensitivity ≤ 端点 trust） |
| CKP-09 | 检查点 `calibration_domain_id` 对应的 `CalibrationDomain.validity_status` 为 false 时，Harness 必须拒绝恢复 | 校准漂移 | R-POOL-CALIB / R-EVID-04 |
| CKP-10 | 隔离等级不匹配（如 `isolation_level=vm` 的任务尝试恢复到 `isolation_level=process` 环境），Harness 必须拒绝恢复 | 隔离降级 | M5「多信任域」；R-POOL-DATA |
| CKP-11 | checkpoint schema `version` 为 "2.0.0"（major 高于 Harness 支持范围）时，Harness 必须拒绝写入并升级 S5 | schema 演化 | §3.2 向后兼容承诺 |
| CKP-12 | `content_hash` 计算排除 `results_uri` 指向的对象内容，仅哈希 `results_uri` 字符串本身；当外部结果对象被篡改但 `results_uri` 不变时，checkpoint 哈希不变，但恢复端读取大结果时应检测 ETag 不一致 | 大结果外置一致性 | R-EVID-03 |
| CKP-13 | WriteCheckpoint 请求未携带 `X-Harness-Version` 或值与 body 不一致时，对象存储层或网关必须返回 `400 Bad Request` | 接口契约 | `CalibrationDomain.harness_version` 对齐要求 |
| CKP-14 | 孤儿 checkpoint（exec_id 在控制面 DB 不存在）超过保留期后，清理事件必须入证据流 | 孤儿清理 | R-EVID-05（证据缺失是治理异常） |

### 9.2 负面测试不覆盖项（待 Linux 常驻机 + SEL-07 落地）

- 真实对象存储 WORM 策略下的并发写入冲突（需 MinIO / S3 生产 IAM + bucket 策略）。
- `results_uri` 指向的对象在保留期内被第三方删除后的恢复行为（需真实跨区域复制或版本回收测试）。
- CSP 对象存储层的 `content_hash` 服务端计算一致性（如 S3 ETag 与客户端 SHA-256 在分片上传时的差异）。

---

## 10. 与既有 M0–M4 的关系

| 里程碑 | 本草案的依赖 | 说明 |
|--------|--------------|------|
| M0 | `CalibrationDomain` schema（`core.yaml` L189–236）、ID 前缀体系（CHK-xxxx） | `calibration_domain_id` / `harness_version` 直接复用 M0 定稿字段。 |
| M1 | 控制面 DB EvidenceEntity 表 | checkpoint write / restore 事件须产出 EvidenceEntity（R-EVID-05）。 |
| M2 | 池账本虚拟 key、`LogicalEndpoint.trust_level`、`RoutingPolicy` | `virtual_key_ref` 与 `trust_label` 路由校验依赖 M2 池层。 |
| M3 | Temporal 流程定义 | 长流程暂停 / 跨环境迁移由 Temporal workflow 驱动；checkpoint 是执行上下文快照，不承载等待语义（R-FLOW-01）。 |
| M4 | Action Registry 网关、OPA decision log、幂等键 | Harness 仅接收 M4 六级管线后的请求；恢复时须重验当前授权（R-POL-02）。 |

---

## 11. 治理与变更路径

### 11.1 工作层限制

本文档为工作层草案，不具备治理仓正本效力。

### 11.2 进治理仓路径

进治理仓须 C1 路径（PR + ADR + owner review）：

1. **PR**：提交至 `gov-infra-repo` 的 `schemas/include/checkpoints.yaml`（新增）与 `docs/checkpoint-externalization.md`。
2. **ADR**：记录检查点 schema 版本策略选型（向后兼容窗口长度、major 变更触发条件、大结果外置指针级摘要设计）。
3. **owner review**：由 gov-infra repo owner（当前为 S5 指定负责人）评审篡改检测与重放防护机制是否满足 R-EVID-03 / R-FLOW-02。
4. **验证**：schema 通过 `gen-python` / `gen-json-schema` 生成验证；接口契约通过 OpenAPI 3.0 校验。

### 11.3 与 SEL 的联动

- SEL-05（LiteLLM 核实）：`virtual_key_ref` 限额端到端验证依赖于本草案定义的限额绑定与重验语义。
- SEL-07（对象存储核实）：`storage_uri` / WORM / 版本化 / 对象锁定均依赖于 SEL-07 选型输出。
- SEL-09（客户门户与客服）：检查点状态查询可暴露给客户门户，但属 M9 范围。

---

## 12. 引用溯源

| 引用编号 | 来源文件 | 章节 / 位置 | 说明 |
|----------|----------|-------------|------|
| M5 验收要点 | DGA-INFRA §6 里程碑表 | M5 行 | Harness 接池 + ≥2 个执行环境 + 检查点外置 |
| CMP-09 | DGA-INFRA §2 组件表 | CMP-09 | 对象存储：证据与大工件；硬要求：版本化 + WORM |
| CMP-17 | DGA-INFRA §2 组件表 | CMP-17 | 现有 Harness 保留，单次执行与开发门禁 |
| CMP-05 | DGA-INFRA §2 组件表 | CMP-05 | LiteLLM 虚拟 key（每执行单元独立 key+限额） |
| R-EVID-03 | DGA-INFRA §5 | R-EVID-03 | 对象版本 + 内容摘要 + 独立写入权限 + 对象锁定 |
| R-EVID-04 | DGA-INFRA §5 | R-EVID-04 | 判定证据必须含判定器模型+版本+校准域 ID |
| R-EVID-05 | DGA-INFRA §5 | R-EVID-05 | 证据缺失是治理异常 |
| R-POL-02 | DGA-INFRA §5 | R-POL-02 | 恢复检查点须重验当前授权 |
| R-POL-03 | DGA-INFRA §5 | R-POL-03 | 池路由的虚拟 key 限额落实 R-POL-02 |
| R-SEC-02 | DGA-INFRA §5 | R-SEC-02 | 凭证明文仅存凭据库 |
| R-FLOW-01 | DGA-INFRA §5 | R-FLOW-01 | 跨系统流程进 Temporal；Agent 会话不承载等待 |
| R-FLOW-02 | DGA-INFRA §5 | R-FLOW-02 | 唯一重试责任方；结果不明进待核实 |
| R-POOL-TRUST | DGA-INFRA §3.2 | R-POOL-TRUST | 信任标签路由（任务 sensitivity ≤ 端点 trust） |
| R-POOL-CALIB | DGA-INFRA §3.8 | R-POOL-CALIB | 校准域声明制；池组成变化触发漂移重估 |
| R-SEC-04 | DGA-INFRA §5 | R-SEC-04 | Agent 不能代签（重放旧批准 = 代签形式之一） |
| CalibrationDomain.harness_version | `_repos/.github/dga/infra/schemas/include/core.yaml` | L212–215 | 校准时依据的 Harness 版本（SemVer，required） |
| LogicalEndpoint.trust_level | `_repos/.github/dga/infra/schemas/include/pools.yaml` | L167–172 | 端点级信任标签（T0/T1/T2） |
| PoolAccount.health | `_repos/.github/dga/infra/schemas/include/pools.yaml` | L138–141 | 健康快照（内嵌值对象；R-POOL-EVID） |
