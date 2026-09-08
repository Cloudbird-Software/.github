# 证据契约 schema 扩展草案（M6）

> **工作层草案，进治理仓须 C1 路径（PR + ADR + owner review）**
> 本文档为 DGA-INFRA M6 证据契约 schema 扩展草案，非治理仓正本。
> 起草日期：2026-09-08。
> 本草案展开 `state/specs/w8-m6.md` 第 2 条（证据契约 schema 扩展），对齐 `plans/2026-09-09-m5-checkpoint-ext-draft.md` 术语与检查点外置接口。

---

## 1. 目标与范围

### 1.1 来源锚点

- **DGA-INFRA §6 里程碑表 M6 行**：证据层：证据契约 + OTel/Langfuse + 对象存储版本锁定；判定证据含判定器模型 + 版本 + 校准域 ID；对象锁定验证。
- **DGA-INFRA §1 权威源表**：执行收据、验收证据、签发记录、校准资产 → 证据存储（保护对象）。
- **DGA-INFRA §5 R-EVID 系列**：
  - R-EVID-01（证据契约独立定义：执行收据 / 验收判定 / 签发记录 / 校准资产的结构）
  - R-EVID-02（Trace ≠ Evidence；评估界面 ≠ 校准能力）
  - R-EVID-03（重要证据：对象版本 + 内容摘要 + 独立写入权限 + 对象锁定；防篡改证明"记录未被改"）
  - R-EVID-04（判定证据必须含判定器模型 + 版本 + 校准域 ID）
  - R-EVID-05（证据缺失是治理异常，与业务失败 / 结果不确定 / 判定器失效区分登记）
- **核心 schema**：
  - `_repos/.github/dga/infra/schemas/include/core.yaml` L144–188 `EvidenceEntity`
  - `_repos/.github/dga/infra/schemas/include/enums.yaml` L195–212 `EvidenceType`
  - `_repos/.github/dga/infra/schemas/include/enums.yaml` L317–321 `Sha256Hex`
- **archive 证据账本标准**：
  - `_repos/archive/evidence/README.md`（append-only + hash 链 + checkpoint 纪律）
  - `_repos/.github/standards/evidence/record.schema.yaml`（EL-1/2 判定层记录 schema v1）
  - `_repos/.github/standards/evidence/pointer.schema.yaml`（EL-2 轨迹层指针协议 v1）
- **M5 检查点外置接口 spec**：`plans/2026-09-09-m5-checkpoint-ext-draft.md` §6.4（PreliminaryEvidence / `restored_from_checkpoint_id`）、§8.2（`failure_reason_code` 枚举）

### 1.2 本草案覆盖

| 件 | 定位 | 本文件处理方式 |
|----|------|----------------|
| `EvidenceEntity` 字段扩展（新字段 / 类型 / 必填 / 不可变） | 核心 | §2 完整字段规格 |
| 不可篡改与 append-only 语义（EL-1/2 hash 链、evidence-erratum、写路径唯一性、WORM） | 核心 | §3 |
| 与 archive 仓 evidence 账本的字段映射与三层纪律衔接 | 核心 | §4 |
| 与 M5 检查点外置的边界（PreliminaryEvidence → 正式 EvidenceEntity 管道、字段归属） | 核心 | §5 |
| 验收谓词 | 接口 | §6 |
| 负面测试不覆盖项 | 说明 | §6.2 |

### 1.3 不覆盖

- 实现代码、写入脚本、CI pipeline 配置。
- 对象存储具体选型（SEL-07 输出；本草案仅消费其接口语义：版本化 + 对象锁定）。
- Temporal workflow 定义（CMP-03 / M3 范围）。

---

## 2. `EvidenceEntity` 字段规格扩展

本节的 schema 骨架对齐 `core.yaml` L144–188，此处逐字段展开新增字段的类型约束、验证规则、不可变属性与示例值。

```yaml
EvidenceEntity:
  # ---- 既有字段（core.yaml L144–188）----
  id:
    type: string
    pattern: "^EVD-[0-9]{4,}$"
    required: true
    immutable: true
    description: 证据实体全局唯一 ID（由控制面在创建前生成）。
  evidence_type:
    type: EvidenceType
    required: true
    immutable: true
    description: 证据契约类型（R-EVID-01 五类 + 策略判定记录 + M5 事件类型扩展）。
  content_digest:
    type: Sha256Hex
    required: true
    immutable: true
    description: 证据内容摘要（R-EVID-03：对象版本 + 内容摘要 + 独立写入权限 + 对象锁定）。
  object_version:
    type: string
    required: true
    immutable: true
    description: 对象存储版本号（版本化存储层分配）。
  storage_uri:
    type: string
    required: true
    immutable: true
    description: 证据存储定位（权威源 = 证据存储，DGA-INFRA 第 1 章权威源表）。
  object_locked:
    type: boolean
    required: true
    immutable: true
    description: 是否对象锁定（WORM）。防篡改证明"记录未被改"（R-EVID-03）。
  trace_ref:
    type: string
    required: false
    description: 关联 OTel trace（R-EVID-02：遥测不构成证据，仅提供线索）。
  judge_model:
    type: string
    required: false
    immutable: true
    description: 判定器模型（R-EVID-04：判定证据必须含判定器模型）。
  judge_version:
    type: SemVer
    required: false
    immutable: true
    description: 判定器版本（R-EVID-04）。
  calibration_domain_ref:
    type: string
    required: false
    immutable: true
    description: 校准域 ID（R-EVID-04 / R-POOL-CALIB：判定溯源三要件之三）。

  # ---- 新增字段（M6 扩展）----
  restored_from_checkpoint_id:
    type: string
    required: false
    immutable: true
    description: >
      本次恢复动作来源的 checkpoint_id（M5 §6.4：恢复成功进入 RUNNING 后，
      Harness 追加本字段；仅在 evidence_type = EXECUTION_RECEIPT 且
      verdict 表明恢复成功时填写）。
    example: "CHK-0001"

  failure_reason_code:
    type: string
    required: false
    immutable: true
    description: >
      失败原因编码（M5 §8.2；仅在 verdict 表明失败时填写）。
    enum:
      - auth_expired
      - trust_insufficient
      - hash_mismatch
      - token_reused
      - calibration_invalid
      - isolation_downgrade
      - checkpoint_tamper
      - replay_attempt
      - orphan_checkpoint_cleaned

  checkpoint_event_type:
    type: string
    required: false
    immutable: true
    description: >
      检查点事件子类型（M5 事件映射；可选值：write / read / restore / delete / tamper / orphan_clean）。
    example: "restore"

  payload_ref:
    type: object
    required: false
    description: >
      大结果轨迹层指针（对齐 `pointer.schema.yaml`；git 侧零本体）。
    properties:
      sha256:
        type: string
        pattern: "^[0-9a-f]{64}$"
      store:
        type: string
        description: "存储 bucket 级标识（如 self-cloud-blob://<bucket>）"
      retention:
        type: string
        enum: ["30d", "90d", "180d", "1y", "3y", "forever"]
        description: "保留策略（pointer.schema.yaml 受控词表；retention 只增不减）"
      bytes:
        type: integer
        minimum: 1
      stored_at:
        type: string
        pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
        description: "入库时间 ISO 8601 UTC（retention 起算点）"

  tenant_id:
    type: string
    required: true
    immutable: true
    description: >
      计量租户 ID（archive evidence ledger subject.tenant 必填；
      DGA-INFRA 宪法 §14a：每条判定记录必含 tenant）。

  card_ref:
    type: string
    required: true
    immutable: true
    pattern: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$"
    description: >
      工作卡引用（archive evidence ledger subject.card 必填；
      owner/repo#issue 形态，三源统一查询 join key）。
```

### 2.1 不可变字段清单

以下字段在 EvidenceEntity 写入控制面 DB 后禁止修改；任何修改尝试必须触发 R-EVID-03 违规告警，并产出 `evidence_type = evidence-erratum` 记录指向原记录：

- `id`
- `evidence_type`
- `content_digest`
- `storage_uri`
- `object_version`
- `object_locked`
- `judge_model`
- `judge_version`
- `calibration_domain_ref`
- `restored_from_checkpoint_id`
- `failure_reason_code`
- `checkpoint_event_type`
- `tenant_id`
- `card_ref`

### 2.2 字段来源对齐速查

| 字段 | 对齐本体 / 策略 / 标准 | 说明 |
|------|------------------------|------|
| `restored_from_checkpoint_id` | M5 §6.4 | 恢复追溯三要件之一（checkpoint_id + content_hash + calibration_domain_id）。 |
| `failure_reason_code` | M5 §8.2 | 恢复失败原因编码集合；与 ClosureState.failure 区分登记（R-EVID-05）。 |
| `checkpoint_event_type` | M5 checkpoint schema 事件类型 | 轻量子类型标记；不替代 evidence_type。 |
| `payload_ref` | archive `pointer.schema.yaml` | 大结果外置；git 侧零本体；保留策略只增不减。 |
| `tenant_id` / `card_ref` | archive `record.schema.yaml` subject | 账本必填字段提升至 EvidenceEntity 必填，确保写账时零信息丢失。 |
| `object_locked` | CMP-09 / R-EVID-03 | 硬要求：版本化 + 对象锁定（WORM）。 |

---

## 3. 不可篡改与 append-only 语义

### 3.1 EL-1 单记录 hash

archive evidence ledger 的每条记录计算 `hash = SHA256(canonical_json(record excluding hash field))`，输出 lowercase hex，无 `0x` 前缀（`record.schema.yaml` L125–127）。

- **锚定作用**：单记录内容完整性锚；任何字段变更 → hash 变更。
- **验证**：`verify_evidence.py` 独立重算每条记录的 hash，与对象内 `hash` 字段比对（INV-01 机械锚点）。

### 3.2 EL-2 链式 hash

- `prev_hash` 字段指向上一条记录的 `hash`（首条为 `null`）。
- 链完整性 = 从首条至当前记录的 `prev_hash` 逐一对齐。
- **验证**：`verify_evidence.py` 对整条链做线性扫描；任一断裂 = 红（fail-closed）。

### 3.3 Monthly Checkpoint 前进性

- `YYYY-MM.json` 月度锚点文件包含：`chain_head_hash`（当月最后一条记录 hash）+ `record_count`。
- 月内滚动前移（落记录的同一 PR 内执行 `--checkpoint`），不可回拨。
- 跨月新月文件自然开链（prev_hash 重新从 null 开始）。

### 3.4 写路径唯一性

- **唯一写入路径**：`archive/scripts/write_evidence.py`。
- 手改 `ledger.jsonl` = 链断；CI 复算必红（archive evidence README 首条纪律）。
- 写入器必须验证 `seq` 连续性、`prev_hash` 正确性、必填字段、4KB 复检后方可追加。

### 3.5 evidence-erratum 纠错追加

- 历史修正 = 追加新记录，`action = "evidence-erratum"`。
- 新记录 payload 中必须包含 `corrected_seq`（被纠记录序号）与 `reason`。
- 被指向的原始记录内容**永远不被修改**。
- 验证器须确认 erratum 指向的 seq 存在且原始记录 hash 未被篡改。

### 3.6 内联 payload 上限

- `record.schema.yaml` payload 字段软上限 4096 字节（UTF-8 编码长度）。
- 写入器硬执法：超限拒写（AC-3a）。
- 超限内容必须走轨迹层 `payload_ref`（W1-B3 协议）。

### 3.7 WORM 锁定与释放

- EvidenceEntity 关联的 `storage_uri` 对象必须存储于支持版本化 + 对象锁定（WORM）的 bucket（CMP-09 / R-EVID-03）。
- 锁释放条件（与 M5 §6.2 对齐）：
  - 执行收据已闭环（EvidenceEntity 已写入且 hash 链已验证）。
  - 漂移重估工作流已消费该证据的 `content_digest`（若适用）。
  - 保留期届满（当前默认 = 90 天，待 S5 裁决 DGA-INFRA §9 第 6 项）。
- 任何提前删除 / 解锁请求必须携带 S5 授权引用（`approval_ref`），否则返回 `403 Forbidden`。

---

## 4. 与 archive 仓 evidence 账本的衔接

### 4.1 EvidenceEntity → ledger record 字段映射

| EvidenceEntity 字段 | ledger record 字段 | 映射规则 |
|---------------------|-------------------|---------|
| `id` (EVD-xxxx) | `payload.evidence_id` | 内联于 payload JSON（record.schema.yaml 限制 additionalProperties: false；payload 为 string，需 JSON 序列化承载扩展字段） |
| `evidence_type` | `kind` + `action` | 见 4.2 映射表 |
| `content_digest` | `payload_ref.sha256`（trajectory layer）或 payload 内容 SHA256 | trajectory layer 时与 payload_ref.sha256 一致；inline 时 payload 承载内容，二者 hash 一致 |
| `storage_uri` | `payload_ref.store` | trajectory layer 指针 |
| `object_version` | `payload.object_version` | 内联 |
| `object_locked` | `payload.object_locked` | 内联 |
| `judge_model` | `actor.model` | 直接复用（record.schema.yaml L73–74） |
| `judge_version` | `payload.judge_version` | 内联 |
| `calibration_domain_ref` | `payload.calibration_domain_ref` | 内联 |
| `trace_ref` | `payload.trace_ref` | 内联 |
| `created_at` | `ts` | ISO 8601 UTC（record.schema.yaml L25–26） |
| `tenant_id` | `subject.tenant` | 必填，直接映射 |
| `card_ref` | `subject.card` | 必填，直接映射 |
| `restored_from_checkpoint_id` | `payload.restored_from_checkpoint_id` | 内联 |
| `failure_reason_code` | `payload.failure_reason_code` | 内联 |
| `checkpoint_event_type` | `payload.checkpoint_event_type` | 内联 |
| `trace_ref` | `payload.trace_ref` | 内联（R-EVID-02：Trace ≠ Evidence，仅线索） |

### 4.2 `evidence_type` ↔ `kind` / `action` 映射表

| EvidenceEntity.evidence_type | ledger.kind | ledger.action 示例 |
|-----------------------------|-------------|-------------------|
| EXECUTION_RECEIPT | gate | `exec.write-checkpoint` / `exec.read-checkpoint` / `exec.restore-checkpoint` / `exec.delete-checkpoint` |
| ACCEPTANCE_VERDICT | decision | `verdict.accept` / `verdict.reject` |
| AUTHORIZATION_RECORD | approval | `auth.grant` / `auth.revoke` |
| CALIBRATION_ASSET | decision | `calibration.propose` / `calibration.drift-detected` |
| POLICY_DECISION | gate | `policy.allow` / `policy.deny` |
| `checkpoint_tamper`（扩展） | gate | `checkpoint.tamper-detected` |
| `replay_attempt`（扩展） | gate | `checkpoint.replay-attempt` |
| `orphan_checkpoint_cleaned`（扩展） | gate | `checkpoint.orphan-cleaned` |
| `evidence-erratum`（纠错） | decision | `evidence.erratum` |

### 4.3 三层纪律对齐

archive evidence 账本采用三层纪律（archive evidence README / record.schema.yaml）：

1. **判定层**（本 ledger record）：payload 内联上限 4096 字节，结构化字段，hash 链锚定。
2. **轨迹层**（`payload_ref`）：大结果落对象存储，git 侧零本体；回取必须重算 sha256 比对（pointer.schema.yaml AC-3e）。
3. **丢弃层**（GitHub 事件面）：transient，不承诺持久；不得作为最终审计凭据。

本草案将上述三层纪律提升为 EvidenceEntity schema 约束：
- 控制面写入 EvidenceEntity 时，若 payload 预计 >4KB，必须走 `payload_ref` 协议。
- `payload_ref.retention` 必须为受控词表值（`30d / 90d / 180d / 1y / 3y / forever`），且只增不减（pointer.schema.yaml）。

### 4.4 Monthly Checkpoint 对账

- 每月 `YYYY-MM.json` checkpoint 文件记录：`chain_head_hash`（当月最后一条 ledger record.hash）+ `record_count`。
- `verify_evidence.py` 在独立复算时执行 checkpoint 对账（AC-3b）。
- 若 `chain_head_hash` 与当月最后一条 record.hash 不一致 → 红（fail-closed）。
- 跨月新月文件自然开链，`prev_hash` 重新从 `null` 开始。

---

## 5. 与 M5 检查点外置的边界

### 5.1 M5 事件生产者边界

M5 draft §6.4 定义了 Harness 在 checkpoint 事件中的证据产出义务。M6 的边界是：**M5 负责检测与产出轻量收据，M6 负责定义正式 EvidenceEntity schema 并提供入账管道**。

| M5 事件 | Harness / M5 动作 | M6 接收与处理 |
|---------|-------------------|---------------|
| `WriteCheckpoint` 成功 | 产出 `PreliminaryEvidence`（轻量收据，控制面 DB 或内存队列；M5 §6.4） | 不直接入 archive 账本；控制面 M6 管道在闭环时升级为正式 `EvidenceEntity` |
| `ReadCheckpoint` 恢复成功 | 在内存中记录 `restored_from_checkpoint_id` | M6 schema 支持本字段；恢复成功后由控制面补写 EvidenceEntity |
| 篡改检测失败（`hash_mismatch`） | 产出 `EvidenceEntity`（`evidence_type = checkpoint_tamper`） | M6 管道立即经 `write_evidence.py` 写入 archive 账本 |
| 重放攻击（`replay_attempt`） | 产出 `EvidenceEntity`（`evidence_type = replay_attempt`） | M6 管道立即写入 archive 账本 |
| `DeleteCheckpoint` | 产出 `EvidenceEntity`（`evidence_type = EXECUTION_RECEIPT`，`checkpoint_event_type = delete`） | M6 管道写入 archive 账本 |
| 孤儿 checkpoint 清理 | 产出 `EvidenceEntity`（`evidence_type = orphan_checkpoint_cleaned`） | M6 管道写入 archive 账本 |

### 5.2 PreliminaryEvidence 生命周期

- `PreliminaryEvidence` 是 M5 临时收据，生命周期由 Harness 控制面管理。
- **不进入** archive evidence 账本（R-EVID-01 四类正式证据之外的临时载体）。
- 闭环后（`SUCCESS` / `FAILED`），控制面 M6 管道执行升级：
  1. 读取 PreliminaryEvidence 字段。
  2. 补全 M6 必填字段（`tenant_id` / `card_ref` / `calibration_domain_ref` 等）。
  3. 创建正式 `EvidenceEntity`。
  4. 经 `write_evidence.py` 入 archive 账本。
- 升级动作本身须留痕（可在控制面日志记录，但不进入 archive 账本，除非升级失败）。

### 5.3 字段归属边界

| 字段 / 概念 | 所属里程碑 | 说明 |
|------------|-----------|------|
| `checkpoint_id` / `content_hash` / `storage_uri` / `resume_token` / `isolation_level` | M5 | `plans/2026-09-09-m5-checkpoint-ext-draft.md` §2 检查点对象 schema |
| `restored_from_checkpoint_id` / `failure_reason_code` / `checkpoint_event_type` | M6 | 本草案 §2 EvidenceEntity 扩展字段 |
| `PreliminaryEvidence`（轻量收据） | M5 临时 | 不入 archive 账本；闭环后升级为 EvidenceEntity |
| `EvidenceEntity`（正式证据） | M6 | 经 archive 账本管道写入，受 EL-1/2 保护 |
| `EvidenceType` 枚举扩展（`checkpoint_tamper` 等） | M6 | 本草案 §2 新增枚举值；进治理仓须登记 `enums.yaml` |

### 5.4 恢复追溯完整性

M5 §6.4 要求恢复成功后在 EvidenceEntity 中追加 `restored_from_checkpoint_id`。M6 的约束是：

1. **必填条件**：`evidence_type = EXECUTION_RECEIPT` 且 `checkpoint_event_type = restore` 时，`restored_from_checkpoint_id` 为必填。
2. **格式约束**：必须匹配 `^CHK-[0-9]{4,}$`（与 checkpoint_id 同一 ID 空间）。
3. **溯源三要件**：恢复动作的证据必须同时包含 `checkpoint_id`（本字段）、`content_hash`（EvidenceEntity.content_digest）、`calibration_domain_id`（calibration_domain_ref），缺一不可（R-EVID-04 / R-POOL-CALIB）。

---

## 6. 验收谓词（可判定，含负面测试方向）

### 6.1 验收谓词

每条谓词均为可判定条件（true / false），不依赖模糊描述。

| 编号 | 谓词 | 测试方向 | 对齐原文 |
|------|------|----------|----------|
| EVC-01 | `EvidenceEntity.evidence_type = EXECUTION_RECEIPT` 写入后，ledger record `kind = gate` 且 `action` 映射符合表 4.2 | 正向映射 | R-EVID-01 |
| EVC-02 | `EvidenceEntity.content_digest` 与 `payload_ref.sha256`（trajectory layer）一致；或 payload 内联内容 SHA256 与 `content_digest` 一致 | 正向完整性 | R-EVID-03 |
| EVC-03 | `EvidenceEntity.object_version` 与 `storage_uri` 返回的对象存储版本号一致 | 正向完整性 | R-EVID-03 |
| EVC-04 | 修改 `ledger.jsonl` 中任一记录的 `hash` 或 `prev_hash` 后，`verify_evidence.py` 返回非零退出码（链断裂） | 篡改检测 | R-EVID-03 / EL-2 |
| EVC-05 | 删除 `ledger.jsonl` 中任一中间记录后，`verify_evidence.py` 检测到 `seq` 断号并返回非零 | 篡改检测 | EL-1 |
| EVC-06 | payload JSON UTF-8 编码长度 > 4096 字节时，`write_evidence.py` 拒绝写入并返回错误 | 内联上限 | record.schema.yaml AC-3a |
| EVC-07 | `EvidenceEntity` 写入后，archive evidence 账本中对应记录的 `prev_hash` 链从首条连续至当前 | 链完整性 | EL-2 |
| EVC-08 | `evidence-erratum` 追加后，被指向的原始记录内容未被修改，新记录 `action = evidence-erratum` 且 payload 含 `corrected_seq` | 纠错追加 | archive evidence README |
| EVC-09 | `PreliminaryEvidence` 不进入 archive evidence 账本（账本中无 `evidence_type = preliminary` 的记录） | 边界隔离 | M5 §6.4 / R-EVID-01 |
| EVC-10 | `checkpoint_tamper` / `replay_attempt` / `orphan_checkpoint_cleaned` 事件经 M6 管道写入后，`ledger.kind = gate` 且 `action` 符合表 4.2 | 事件映射 | M5 §6.4 / R-EVID-05 |
| EVC-11 | `restored_from_checkpoint_id` 字段在 `EvidenceEntity` 中存在且指向有效 `CHK-xxxx` ID | 恢复追溯 | M5 §6.4 |
| EVC-12 | `EvidenceEntity` 的 immutable 字段集合在写入后通过控制面 API 更新均被拒绝或产生 `evidence-erratum` | 不可篡改 | R-EVID-03 / R-EVID-04 |
| EVC-13 | 当月 `YYYY-MM.json` checkpoint 的 `chain_head_hash` 与当月最后一条 ledger record `hash` 一致 | 月度锚点 | archive evidence README BEH-02 |
| EVC-14 | `EvidenceEntity.failure_reason_code` 值域全部被 ledger payload 承载（无信息丢失） | 字段承载 | M5 §8.2 |

### 6.2 负面测试不覆盖项（待 SEL-07 落地 + Linux 常驻机）

- 真实对象存储 WORM 策略下的提前解锁尝试（需 MinIO / S3 生产 IAM + bucket 策略）。
- `payload_ref.sha256` 在对象存储端被篡改后的回取校验（需内网 blob-store.sh 生产环境）。
- 跨月 checkpoint 切换时的时间窗口内写入的记录归属判定（需 Temporal workflow 与月份边界对齐测试）。

---

## 7. 与既有 M0–M4 的关系

| 里程碑 | 本草案的依赖 | 说明 |
|--------|--------------|------|
| M0 | `EvidenceEntity` schema（`core.yaml` L144–188）、`EvidenceType` 枚举（`enums.yaml` L195–212）、`Sha256Hex` 类型（`enums.yaml` L317–321） | 直接复用既有字段语义；本草案仅做扩展与映射。 |
| M1 | 控制面 DB EvidenceEntity 表、闭环注册 | EvidenceEntity 写入控制面 DB 后经 M6 管道入 archive 账本。 |
| M2 | 池账本虚拟 key、`LogicalEndpoint.trust_level`、`RoutingPolicy` | `failure_reason_code` 中的 `trust_insufficient` 依赖 M2 池层路由判定。 |
| M3 | Temporal 流程定义 | 长流程暂停 / 跨环境迁移由 Temporal workflow 驱动；证据落盘与流程状态机绑定。 |
| M4 | Action Registry 网关、OPA decision log | `EvidenceType = POLICY_DECISION` 承载 OPA decision log（R-POL-05）；M4 六级管线后的判定记录是本草案的主要消费源。 |

---

## 8. 治理与变更路径

### 8.1 工作层限制

本文档为工作层草案，不具备治理仓正本效力。

### 8.2 进治理仓路径

进治理仓须 C1 路径（PR + ADR + owner review）：

1. **PR**：提交至 `gov-infra-repo` 的以下文件：
   - `schemas/include/core.yaml`：`EvidenceEntity` 类新增字段（`restored_from_checkpoint_id` / `failure_reason_code` / `checkpoint_event_type` / `payload_ref` / `tenant_id` / `card_ref`）
   - `schemas/include/enums.yaml`：`EvidenceType` 枚举新增值（`checkpoint_tamper` / `replay_attempt` / `orphan_checkpoint_cleaned`）
   - `standards/evidence/record.schema.yaml`：可选扩展（新增 `evidence_id` 字段或保留 payload 内联映射）
2. **ADR**：记录证据契约 schema 扩展选型（trajectory-layer 指针协议保留、 EvidenceEntity 与 ledger record 双层 hash 分离设计、M5 PreliminaryEvidence 升级管道）。
3. **owner review**：由 gov-infra repo owner（当前为 S5 指定负责人）评审：
   - `EvidenceEntity` immutable 字段集合是否满足 R-EVID-03 / R-EVID-04 不可篡改要求。
   - `payload_ref` 保留策略只增不减规则是否与对象存储实际能力对齐。
   - M5 PreliminaryEvidence 升级管道的 fail-closed 语义是否明确。
4. **验证**：schema 通过 `gen-python` / `gen-json-schema` 生成验证；ledger 记录通过 `verify_evidence.py` 独立复算。

### 8.3 与 SEL 的联动

- SEL-07（对象存储核实）：`storage_uri` / WORM / 版本化 / 对象锁定均依赖于 SEL-07 选型输出；本草案的 `object_locked` 字段依赖其接口语义。
- SEL-03（OPA 集成模式）：`EvidenceType = POLICY_DECISION` 的消费端依赖 OPA decision log 输出格式；本草案假设 OPA decision log 可映射为 ledger record。

---

## 9. 引用溯源

| 引用编号 | 来源文件 | 章节 / 位置 | 说明 |
|----------|----------|-------------|------|
| M6 验收要点 | DGA-INFRA §6 里程碑表 | M6 行 | 证据层：证据契约 + OTel/Langfuse + 对象存储版本锁定 |
| R-EVID-01 | DGA-INFRA §5 | R-EVID-01 | 证据契约独立定义（执行收据 / 验收判定 / 签发记录 / 校准资产的结构） |
| R-EVID-02 | DGA-INFRA §5 | R-EVID-02 | Trace ≠ Evidence；评估界面 ≠ 校准能力 |
| R-EVID-03 | DGA-INFRA §5 | R-EVID-03 | 对象版本 + 内容摘要 + 独立写入权限 + 对象锁定 |
| R-EVID-04 | DGA-INFRA §5 | R-EVID-04 | 判定证据必须含判定器模型 + 版本 + 校准域 ID |
| R-EVID-05 | DGA-INFRA §5 | R-EVID-05 | 证据缺失是治理异常 |
| 权威源表 | DGA-INFRA §1 | 执行收据 / 验收证据 / 签发记录 / 校准资产 → 证据存储 | EvidenceEntity 权威源归属 |
| EvidenceEntity | `_repos/.github/dga/infra/schemas/include/core.yaml` | L144–188 | M0 定稿证据实体 |
| EvidenceType | `_repos/.github/dga/infra/schemas/include/enums.yaml` | L195–212 | M0 定稿证据类型枚举 |
| Sha256Hex | `_repos/.github/dga/infra/schemas/include/enums.yaml` | L317–321 | M0 定稿 SHA-256 内容摘要类型 |
| record.schema.yaml | `_repos/.github/standards/evidence/record.schema.yaml` | 全文 | EL-1/2 判定层记录 schema v1（IR-0006 W1-B1 / ADR-0103） |
| pointer.schema.yaml | `_repos/.github/standards/evidence/pointer.schema.yaml` | 全文 | EL-2 轨迹层指针协议 v1（IR-0006 W1-B3 / ADR-0103） |
| archive evidence README | `_repos/archive/evidence/README.md` | 全文 | append-only + hash 链 + checkpoint 纪律 |
| M5 检查点边界 | `plans/2026-09-09-m5-checkpoint-ext-draft.md` | §6.4 / §8.2 | PreliminaryEvidence / restored_from_checkpoint_id / failure_reason_code |
