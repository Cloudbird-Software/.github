# Decision Log 管道 spec（M6 第一波设计件）

> **工作层草案，进治理仓须 C1 路径（PR + ADR + owner review）。**
> 本文档为 DGA-INFRA M6 判定日志管道的完整 spec，非治理仓正本。
> 起草日期：2026-09-08。

---

## 1. 目标与范围

### 1.1 来源锚点

- **M6 验收要点**（DGA-INFRA §6 里程碑表 M6 行）：证据契约 + OTel/Langfuse + 对象存储版本锁定；判定证据必须含判定器模型+版本+校准域 ID；Trace ≠ Evidence。
- **架构锚点**（DGA-INFRA §1 总体架构图）：「证据与判定层 — 证据契约 · 对象存储（版本+锁定）· 校准与漂移 · 治理度量 · 公示」。
- **组件锚点**：CMP-08（OpenTelemetry）、CMP-09（对象存储）、CMP-03（OPA：decision log 作为证据流的一部分）、CMP-07（Langfuse：评估工作台，不承载证据账本）。
- **策略锚点**：
  - R-EVID-01（证据契约独立定义）
  - R-EVID-02（Trace ≠ Evidence）
  - R-EVID-03（对象版本 + 内容摘要 + 独立写入权限 + 对象锁定）
  - R-EVID-04（判定证据必须含判定器模型+版本+校准域 ID）
  - R-EVID-05（证据缺失是治理异常）
  - R-POL-05（OPA decision log 入证据流）
  - R-OBS-01（全链路 OpenTelemetry）
  - R-OBS-02（治理度量自动化进公示仪表）
  - R-OBS-03（验证比计量固定口径；Goodhart 防护）
  - R-POOL-CALIB（校准域声明制）
  - R-POOL-EVID（池健康证据）
  - R-FLOW-01（跨系统流程进 Temporal；Agent 会话不承载等待）
  - R-FLOW-02（唯一重试责任方；结果不明进待核实）
  - R-FLOW-03（幂等键 + 结果核对 + 补偿）

### 1.2 数据源（产生点）

判定日志管道接收三类输入，三者缺一不可：

| 数据源 | 产生位置 | 输出物 | 对齐原文 |
|--------|----------|--------|----------|
| 控制面遥测 | `code/control-plane/api.py` | OTel spans（请求/响应/DB 操作） | CMP-08 / R-OBS-01 |
| 判定网关 | `code/action-registry/gateway.py` + OPA sidecar | `EvidenceEntity` 事件 + OPA decision log JSONL | M4 / R-POL-05 / R-EVID-04 |
| Worker 执行 | `code/workflows/worker.py` | OTel spans（workflow/activity/heartbeat） | CMP-08 / R-OBS-01 |

### 1.3 本草案覆盖

| 件 | 定位 | 本文件处理方式 |
|----|------|----------------|
| 管道五阶段定义 | 核心 | §2 全文详述 |
| 每阶段 fail-closed 语义 | 核心 | §3 全文详述 |
| 背压与降级机制 | 核心 | §4 全文详述 |
| 与 M6 OTel / 对象存储封装的关系 | 接口边界 | §5 全文详述 |
| 与 M5 既有产物（Harness / Checkpoint / EnvRegistry / MCP Adapter）的关系 | 接口边界 | §6 全文详述 |

### 1.4 不覆盖

- Langfuse 部署与评估工作台细节（CMP-07 / SEL-08，M6 第二波 Linux 常驻机）。
- 对象存储具体选型与 WORM 桶配置（CMP-09 / SEL-07）。
- 公示仪表前端与实时度量管线（M9）。
- 实现代码、部署脚本、服务启停配置。

---

## 2. 管道阶段划分

```
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ 控制面 OTel  │   │ 网关 + OPA  │   │ Worker OTel  │
│   (spans)    │   │ decision log │   │   (spans)    │
└──────┬───────┘   └──────┬───────┘   └──────┬───────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          ▼
              ┌─────────────────────┐
              │ Stage 1             │
              │ Collection & Buffer │  ← OTel Collector / log shipper
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │ Stage 2             │
              │ Enrichment &        │  ← exec_id / calibration_domain_id / virtual_key_ref 关联
              │ Correlation         │
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │ Stage 3             │
              │ Evidence Extraction │  ← EvidenceEntity schema 转换 + content_hash 计算
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │ Stage 4             │
              │ Object Storage      │  ← 版本化 + WORM 写入
              │ Ingestion           │
              └─────────┬───────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │ Stage 5             │
              │ Ledger Registration │  ← 账本登记（DB 索引 + manifest）
              └─────────────────────┘
```

### Stage 1：Collection & Buffer（采集与缓冲）

| 项目 | 说明 |
|------|------|
| 输入 | OTLP spans（控制面/网关/Worker）+ OPA decision log JSONL |
| 处理 | OTel Collector 按 `exec_id` / `trace_id` 分片；OPA log shipper 追加到同一分片 |
| 校验 | 必填属性：`trace_id`、`span_id`、`exec_id`、`span_kind`、`pipeline_stage_version`。缺失必填属性的记录进入 quarantine，不进入主缓冲 |
| 缓冲 | 持久化队列（写前日志 WAL），保证 Collector 重启后可恢复 |
| 输出 | 带校验标记的 span/decision record stream |

### Stage 2：Enrichment & Correlation（增强与关联）

| 项目 | 说明 |
|------|------|
| 输入 | Stage 1 输出的 record stream |
| 处理 | 按 `exec_id` + `tool_call_id` 关联 OTel span 与 OPA decision log；注入 `judge_model`、`judge_version`、`calibration_domain_id`（来自 workflow 上下文 / Checkpoint `calibration_domain_id`） |
| 过滤 | 移除不携带 `exec_id` 的纯心跳/健康检查 span；这些 span 保留在 OTel 遥测流，但不进入证据流（R-EVID-02） |
| 校验 | `calibration_domain_id` 必须在控制面 DB 有效（`CalibrationDomain.validity_status == true`）；`harness_version` 必须与 `ExecutionEnvironment.harness_version` 兼容 |
| 输出 | 已关联、已增强的 record batch |

### Stage 3：Evidence Extraction（证据提取）

| 项目 | 说明 |
|------|------|
| 输入 | Stage 2 输出的 record batch |
| 处理 | 转换为 `EvidenceEntity`（对齐 M4 `code/action-registry/gateway.py` 现有字段：`tool` / `params_hash` / `decision` / `timestamp` / `content_digest` / `storage_uri`，并补全 `judge_model` / `judge_version` / `calibration_domain_id` / `pipeline_stage_version`） |
| 哈希 | `content_hash = SHA-256( canonical_json( record_batch ) )`，规范序列化规则对齐 `plans/2026-09-09-m5-checkpoint-ext-draft.md` §4（键排序、无空格、NFC、大结果外置仅哈希 URI） |
| 幂等 | 同一 `exec_id` + `tool_call_id` + `pipeline_stage_version` 重复提交视为同一证据，返回既有 `storage_uri` |
| 输出 | 可落盘的 EvidenceEntity record |

### Stage 4：Object Storage Ingestion（对象存储写入）

| 项目 | 说明 |
|------|------|
| 输入 | Stage 3 输出的 EvidenceEntity |
| 存储 | 写入 CMP-09 对象存储（主选阿里云 OSS / 备选腾讯 COS / 备用 B2），路径模式：`s3://dga-evidence/decision-logs/{calibration_domain_id}/{exec_id}/{tool_call_id}.json` |
| 版本与锁定 | 存储层自动启用版本化 + WORM（R-EVID-03）。同一路径重复写入产生新 version-id，旧版本保留在 WORM 保护期内 |
| 返回 | `storage_uri` + `version_id` + `content_hash` |
| 输出 | 已持久化、不可篡改的证据对象 |

### Stage 5：Ledger Registration（账本登记）

| 项目 | 说明 |
|------|------|
| 输入 | Stage 4 返回的 `storage_uri` + `version_id` + `content_hash` |
| 处理 | 在控制面 DB 的 `evidence_ledger` 表追加一行：`ledger_id`、`record_type`（OPA_DECISION / EXECUTION_RECEIPT / CALIBRATION_EVENT）、`storage_uri`、`version_id`、`content_hash`、`created_at`、`pipeline_stage_version`、`exec_id`、`calibration_domain_id` |
| 索引 | 同时更新对象存储 manifest（JSONL 追加），供离线审计与 reconcile 使用 |
| 完成 | 证据状态标记 `closed`；可被 Langfuse / 公示仪表 / 审计查询消费 |
| 输出 | 可验证、可追溯、可查询的已闭环证据条目 |

---

## 3. 每阶段失败语义（fail-closed）

fail-closed 在本管道的含义：**任何阶段发生异常、超时或数据缺失时，不得生成“伪成功”证据记录；未闭环 = 未完成，不进入已闭环账本。**

| 阶段 | 输入 | 正常输出 | 失败语义 | 治理异常编码 |
|------|------|----------|----------|--------------|
| Stage 1 | OTLP / OPA log | 带校验标记的 record stream | 必填属性缺失 → quarantine；Collector 崩溃 → 重启后 WAL 恢复，若发现时间戳间隙 → 记录 `PIPELINE_GAP` 并升级；未校验通过的记录不进入主缓冲 | DLP-GAP-01 |
| Stage 2 | record stream | 已关联增强的 batch | `exec_id` / `calibration_domain_id` 缺失 → 无法关联 → quarantine；`CalibrationDomain.validity_status == false` → quarantine（R-POOL-CALIB）；关联错误（一对多/多对一且无法消歧） → quarantine | DLP-CORR-02 |
| Stage 3 | record batch | EvidenceEntity | 必填字段缺失（judge_model / judge_version / calibration_domain_id）→ 拒绝，写入 DLQ（R-EVID-04）；`content_hash` 计算异常 → 拒绝；schema 版本不兼容 → 拒绝并升级 S5 | DLP-EXTRACT-03 |
| Stage 4 | EvidenceEntity | `storage_uri` + `version_id` | 对象存储写入失败（网络/认证/配额）→ 重试至最大次数；仍失败 → stage 失败，记录保留在 staging，不标记 ledger `closed`；上游（Temporal/Harness）不收到“证据已闭环”信号 | DLP-STORAGE-04 |
| Stage 5 | `storage_uri` + `version_id` | 控制面 DB `closed` 条目 | 控制面 DB 写入失败 → 证据对象存在于对象存储，但 ledger 状态为 `staged`；reconciliation job 补齐索引前，该记录不对外呈现为已闭环证据（R-EVID-05）；manifest 追加失败 → 同上 | DLP-LEDGER-05 |

**关键区分（R-EVID-05）**：

- **业务失败 / 结果不确定**：Harness 产出 `FAILED` EvidenceEntity，包含失败原因编码。这是正常证据。
- **判定器失效**：CalibrationDomain 失效导致 quarantine。这是治理异常。
- **证据缺失**：上述任一阶段 quarantine/失败，导致最终无 EvidenceEntity 落账。这是治理异常，与业务失败区分登记。

---

## 4. 背压与降级（判定只延迟不降质）

### 4.1 硬约束：不降质

以下操作在任何背压场景下均为**禁止**：

- 对证据记录进行采样（sampling）或截断（truncation）。
- 移除 EvidenceEntity 的必填字段（judge_model / judge_version / calibration_domain_id / content_hash / storage_uri）。
- 将未闭环（`staged` / `quarantine` / `dlq`）记录伪标记为 `closed`。
- 通过静默丢弃记录来降低队列深度。

### 4.2 允许的降级：延迟与暂停

| 触发条件 | 动作 | 对齐原文 |
|----------|------|----------|
| OTel Collector 缓冲深度 > 阈值（默认 80%） | 向 Instrumented 服务发送 `FLOW_CONTROL` 信号；控制面暂停接受新的外部请求；Temporal workflow 进入 `approval_wait`（R-FLOW-01） | R-FLOW-01 |
| 对象存储写入队列 > 阈值 | 暂停 Stage 4 消费；Stage 3 输出本地持久化队列 | CMP-09 / R-FLOW-02 |
| 控制面 DB 写入失败 | Stage 5 挂起；Stage 4 继续写入对象存储；reconciliation job 补录 | R-EVID-05 |
| 连续 3 次 Stage 5 失败 | 全局挂起新证据闭环，升级 S5；已 staging 记录进入人工核实队列 | R-FLOW-02 |

### 4.3 背压链

```
Stage 5 (Ledger)
  │  失败/慢
  ▼
Stage 4 (Object Storage queue 深度 > 阈值)
  │  满
  ▼
Stage 3 (Extraction 本地持久化队列)
  │  满
  ▼
Stage 1 (OTel Collector OTLP flow control)
  │  限流
  ▼
控制面 / 网关 / Worker（span export 节流）
```

每一级都有持久化缓冲，且缓冲区容量是可配置的治理参数（进治理仓后登记在 `pools/circuit-breaker.rego` 或等效策略）。

### 4.4 一致性保护（R-FLOW-03）

- 每条证据记录携带 `pipeline_stage_version` 与 `idempotency_key = SHA256(exec_id + tool_call_id + calibration_domain_id)`。
- 重试时只产生新的 object version-id，不覆盖旧版本。
- 补偿：若 Stage 4 成功但 Stage 5 失败，reconciliation job 以 `storage_uri` 为输入补齐 ledger；若 reconciliation 多次失败，记录升级为 `PIPELINE_GAP`。

---

## 5. 与 M6 OTel / 对象存储封装的关系

| 维度 | OTel 层 | 对象存储层 | 本管道 |
|------|---------|------------|--------|
| 职责 | 采集 spans / traces；导出到 Collector | 持久化、版本化、WORM 保护证据对象 | 将 spans/decisions 转换为 EvidenceEntity 并注册到账本 |
| 数据形态 | Trace / Span（多维、包含冗余） | Object（二进制/JSON，版本化，锁定） | EvidenceEntity（精简、可审计、可查询） |
| 与 Trace 的关系 | Trace 是原材料 | Trace 不是存储对象 | Trace ≠ Evidence（R-EVID-02）；管道只抽取 Trace 中构成证据的字段 |
| 与对象存储的关系 | 不直接写入对象存储 | 接收管道写入的证据对象 | 管道的 Stage 4 是对象存储的唯一写入面 |
| Langfuse 关系 | Langfuse 消费 OTel/Langfuse trace 用于评估 | Langfuse 不写对象存储 WORM 桶 | 本管道不依赖 Langfuse；评估与证据是两条独立链路（R-EVID-02） |

**关键约束**：

- 控制面/网关/Worker 的 OTel 插桩**不得**将 EvidenceEntity 直接写入对象存储；必须经过本管道 Stage 3 的 schema 校验与哈希计算，防止绕过校验。
- 对象存储的 WORM 策略由存储层强制执行；本管道只负责决定何时写入、写什么内容（R-EVID-03）。
- OTel Collector 的 buffer 与对象存储的 write queue 是两级独立缓冲；Collector 重启不导致对象存储写入间隙。

---

## 6. 与 M5 草案术语对齐

本管道使用 M5 第一波四件草案定义的术语，不做二次解释或别名：

| 术语 | 来源 | 本管道用法 |
|------|------|------------|
| `EvidenceEntity` | M4 `code/action-registry/gateway.py` | Stage 3 输出 schema |
| `Checkpoint` | M5 checkpoint-ext §2 | Stage 2 恢复时读取 `calibration_domain_id` / `harness_version` |
| `ExecutionEnvironment` | M5 env-registry §2 | `env_id` 作为证据记录的环境溯源字段 |
| `virtual_key_ref` | M5 checkpoint-ext §2 | Stage 2 注入 EvidenceEntity |
| `calibration_domain_id` | M5/R-POOL-CALIB | Stage 2 注入；Stage 3 必填校验；Stage 5 索引 |
| `harness_version` | `CalibrationDomain.harness_version` (core.yaml L212–215) | Stage 3 schema 版本兼容校验 |
| `judge_model` / `judge_version` | R-EVID-04 / M6 evidence contract | Stage 3 必填字段 |
| `content_hash` | M5 checkpoint-ext §4 | Stage 3 计算；Stage 4 校验 |
| `storage_uri` | M5 checkpoint-ext §2 | Stage 4 返回；Stage 5 索引 |
| `TrustLevel` (T0/T1/T2) | pools.yaml | `virtual_key_ref` 绑定的端点信任等级 |
| `SensitivityLevel` (S0/S1/S2) | enums.yaml | 与 `ExecutionEnvironment.trust_label` 对比的敏感度标签 |
| `IsolationLevel` (process/container/vm/bare-metal) | M5 env-registry §3 | 环境隔离等级；证据记录的环境溯源 |

---

## 7. 与既有 M0–M4 的关系

| 里程碑 | 本管道的依赖 | 说明 |
|--------|--------------|------|
| M0 | schemas 框架、ID 体系（DLP-xxxx）、`CalibrationDomain` | `ledger_id` 使用 DLP 前缀；`calibration_domain_id` 复用 M0 定稿字段 |
| M1 | 控制面 DB `EvidenceEntity` 表 | Stage 5 向控制面 DB 追加 ledger 条目 |
| M2 | 池账本 `PoolAccount.health` / `QuotaState`、`LogicalEndpoint` | `virtual_key_ref` 对应池层端点健康与配额；池健康证据可触发 `PIPELINE_GAP` 候选 |
| M3 | Temporal workflow `approval_wait` / 挂起语义 | 背压时 Temporal workflow 承担等待语义（R-FLOW-01） |
| M4 | Action Registry 网关 `EvidenceEntity` + OPA decision log | Stage 1 的核心输入；网关是 decision log 的权威产生点（R-POL-05） |

---

## 8. 验收谓词（可判定，含负面测试方向）

每条谓词均为 true/false 条件，不依赖模糊描述。

| 编号 | 谓词 | 测试方向 | 对齐原文 |
|------|------|----------|----------|
| DLP-01 | 对于一条完整工具调用 trace，管道在 Stage 5 完成后恰好产生一个 `closed` 状态的 EvidenceEntity，其 `storage_uri` 可访问且 `content_hash` 与对象存储返回一致。 | 正向端到端 | R-EVID-01 / CMP-09 |
| DLP-02 | Stage 1 的 OTel Collector 进程被杀后重启，pipeline 检测到 `pipeline_stage_version` 序列间隙，产生至少一条 `PIPELINE_GAP` 记录并升级；该间隙内原 spans 不会被 Stage 5 伪闭环。 | Collector 故障 | R-EVID-05 / R-FLOW-02 |
| DLP-03 | Stage 4 对象存储写入在重试最大次数后仍失败，控制面 DB 中该记录的 `ledger_status` 为 `staged` 或 `failed`，绝不出现 `closed`。 | 存储故障 | CMP-09 / R-EVID-03 |
| DLP-04 | 缺少 `judge_model` / `judge_version` / `calibration_domain_id` 的 record 进入 Stage 3 后，被拒绝并写入 DLQ，原因码 `MISSING_CALIBRATION`；DLQ 记录数 > 0。 | 缺失必填字段 | R-EVID-04 / R-POOL-CALIB |
| DLP-05 | 同一 `content_hash` + `exec_id` + `tool_call_id` 并发写入两次 Stage 4，对象存储返回不同 `version_id`；Stage 5 ledger 只登记最新版本，旧版本保留可追溯但标记 `superseded`，不丢记录。 | 并发/幂等 | R-FLOW-03 / R-EVID-03 |
| DLP-06 | 纯心跳 span（`span_kind=internal`，不含 `exec_id`）经过 Stage 2 后从证据流过滤，不出现在 Stage 5 ledger 中；但在 OTel 遥测流中仍然存在。 | 负面：Trace ≠ Evidence | R-EVID-02 |
| DLP-07 | Stage 5 写入控制面 DB 失败但 Stage 4 已成功，查询 `evidence_ledger` 表按 `storage_uri` 返回零行；reconciliation job 补齐后返回一行 `closed`。 | 账本故障 | R-EVID-05 |
| DLP-08 | 下游查询对 `ledger_status=closed` 的记录发起 DELETE 或 UPDATE，存储层/服务层返回 403/404；WORM 锁定有效期内无法解除。 | 篡改防护 | R-EVID-03 |
| DLP-09 | OPA decision log 缺少 `exec_id` 的条目，Stage 2 无法关联任何 Span，进入 quarantine；不通过时间戳模糊匹配强行绑定。 | 关联失败 | R-POL-05 / R-EVID-04 |
| DLP-10 | 当 Stage 1 缓冲深度 > 阈值时，控制面新请求被拒绝（503）或 Temporal workflow 被暂停（`approval_wait`），但已接收的 span 不丢失、不采样、不截断。 | 背压 | R-FLOW-01 / R-OBS-02 |
| DLP-11 | 任何采样率 >0% 的配置作用于携带 `calibration_domain_id` 的服务时，Collector 启动校验拒绝该配置并记录 `SAMPLING_REJECTED`；若运行时动态启用采样，所有已生成记录标记 `QUALITY_DEGRADED` 并升级 S5。 | 负面：禁用采样 | CMP-08 / R-EVID-01 |
| DLP-12 | Stage 3 的 EvidenceEntity schema 版本与 `pipeline_stage_version` 登记不符时，该批次整体 quarantine，不进入 Stage 4；Stage 4 不尝试静默字段映射。 | Schema 演化 | R-EVID-01 |

### 负面测试不覆盖项（待 Linux 常驻机 + SEL-07/SEL-08 落地）

- 真实对象存储 WORM 策略下的并发 version 冲突（需 MinIO/S3 生产 IAM + bucket 策略）。
- Langfuse 与证据账本的双写一致性（需 SEL-08 落地后）。
- Temporal workflow 在长期背压（>24h）下的 `approval_wait` 超时行为（需 M3 生产拓扑）。

---

## 9. 治理与变更路径

### 9.1 工作层限制

本文档为工作层草案，不具备治理仓正本效力。

### 9.2 进治理仓路径

进治理仓须 C1 路径（PR + ADR + owner review）：

1. **PR**：提交至 `gov-infra-repo`（或 DGA-INFRA 正本仓）的 `docs/` 或 `schemas/` 目录。
2. **ADR**：记录背压阈值选型、stage versioning 策略、reconciliation job 容错边界、以及 WORM 保留期与 S5 裁决点的绑定。
3. **owner review**：由 gov-infra repo owner（当前为 S5 指定负责人）评审 fail-closed 语义是否覆盖 R-EVID-05 全部子场景。
4. **验证**：pipeline 契约通过 OpenAPI/JSON Schema 校验；证据 schema 通过 `gen-python` / `gen-json-schema` / `gen-sqlddl` 生成验证。

### 9.3 与 SEL 的联动

- **SEL-07**（对象存储核实）：Stage 4 的 `storage_uri` / WORM / 版本化语义依赖于 SEL-07 选型输出。
- **SEL-08**（Langfuse 核实）：Stage 5 的评估数据与证据账本分离机制依赖 SEL-08 的许可证与功能分界结论。
- **SEL-04**（openJiuwen 调研）：若 agent-protocol 引入 A2A，其判定日志必须同样接入 Stage 1，不新建旁路。

---

## 10. 引用溯源

| 引用编号 | 来源文件 | 章节 / 位置 | 说明 |
|----------|----------|-------------|------|
| M6 验收要点 | DGA-INFRA §6 里程碑表 | M6 行 | 证据契约 + OTel/Langfuse + 对象存储版本锁定 |
| CMP-08 | DGA-INFRA §2 组件表 | CMP-08 | OpenTelemetry；Trace ≠ Evidence |
| CMP-09 | DGA-INFRA §2 组件表 | CMP-09 | 对象存储：证据与大工件；硬要求：版本化 + WORM |
| CMP-07 | DGA-INFRA §2 组件表 | CMP-07 | Langfuse：评估工作台，不承载证据账本 |
| CMP-03 | DGA-INFRA §2 组件表 | CMP-03 | OPA：decision log 作为证据流的一部分 |
| R-EVID-01 | DGA-INFRA §5 | R-EVID-01 | 证据契约独立定义 |
| R-EVID-02 | DGA-INFRA §5 | R-EVID-02 | Trace ≠ Evidence |
| R-EVID-03 | DGA-INFRA §5 | R-EVID-03 | 对象版本 + 内容摘要 + 独立写入权限 + 对象锁定 |
| R-EVID-04 | DGA-INFRA §5 | R-EVID-04 | 判定证据必须含判定器模型+版本+校准域 ID |
| R-EVID-05 | DGA-INFRA §5 | R-EVID-05 | 证据缺失是治理异常 |
| R-POL-05 | DGA-INFRA §5 | R-POL-05 | OPA decision log 入证据流 |
| R-OBS-01 | DGA-INFRA §5 | R-OBS-01 | 全链路 OpenTelemetry |
| R-OBS-02 | DGA-INFRA §5 | R-OBS-02 | 治理度量自动化进公示仪表 |
| R-OBS-03 | DGA-INFRA §5 | R-OBS-03 | 验证比计量固定口径；Goodhart 防护 |
| R-POOL-CALIB | DGA-INFRA §3.8 | R-POOL-CALIB | 校准域声明制 |
| R-POOL-EVID | DGA-INFRA §3.9 | R-POOL-EVID | 池健康证据 |
| R-FLOW-01 | DGA-INFRA §5 | R-FLOW-01 | 跨系统流程进 Temporal；Agent 会话不承载等待 |
| R-FLOW-02 | DGA-INFRA §5 | R-FLOW-02 | 唯一重试责任方；结果不明进待核实 |
| R-FLOW-03 | DGA-INFRA §5 | R-FLOW-03 | 幂等键 + 结果核对 + 补偿 |
| EvidenceEntity | M4 `code/action-registry/gateway.py` | — | 现有最小证据实体字段定义 |
| 证据契约扩展 | `plans/2026-09-09-m6-evidence-contract-draft.md` | §2/§3 | 姊妹草案：EvidenceEntity 新增字段与 append-only 语义；本管道 Stage 3 的 schema 转换以该契约为准 |
| CalibrationDomain.harness_version | `_repos/.github/dga/infra/schemas/include/core.yaml` | L212–215 | 校准时依据的 Harness 版本（SemVer，required） |
| ExecutionEnvironment.harness_version | `_repos/.github/dga/infra/schemas/include/pools.yaml` / M5 env-registry | — | 当前部署的 Harness 版本 |
| content_hash 规范序列化 | `plans/2026-09-09-m5-checkpoint-ext-draft.md` | §4 | 键排序、无空格、NFC、大结果外置指针级摘要 |
| virtual_key_ref | `plans/2026-09-09-m5-checkpoint-ext-draft.md` | §2 | 本次执行使用的虚拟 key 引用 |
| storage_uri | `plans/2026-09-09-m5-checkpoint-ext-draft.md` | §2 | 对象存储路径 |
| Judgment evidence fields | `plans/2026-09-09-m6-evidence-contract-draft.md`（契约卡另一件） | — | judge_model / judge_version / calibration_domain_id |
