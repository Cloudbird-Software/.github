# SEL-13e 调研报告：OpenFoundry ARCHITECTURE.md 研读（架构参考，非生产依赖）

- 任务来源：ontology-research-2026-09-06.md 第 1.1/1.3 节判读 + SEL-13 任务定义 e) 项；DGA-INFRA 8.2 SEL-13
- 报告性质：**研读报告**（架构模式吸收清单），非组件选型——OpenFoundry 已被 1.1 节判为"生产依赖价值为零"（AGPL 传染 + 极端早期），唯一正确用法=当 ARCHITECTURE.md 参考文献读
- 核实日期：2026-09-06/07（本报告全部 URL 当晚抓取核对）
- 纪律声明：所有引文逐字摘自当次抓取的原文并给出行号；**未读到的部分诚实标注**（见 §0.3 与各节"未核实"标记）

## 0. 仓库定位（重要发现：任务书给的 repo 实名已失效）

### 0.1 DioCrafts/OpenFoundry 已 404

- 任务书指定 `github.com/DioCrafts/OpenFoundry`（及 raw 路径 `raw.githubusercontent.com/DioCrafts/OpenFoundry/main/ARCHITECTURE.md`）。核实（2026-09-07）：github.com HTML 页与 `api.github.com/repos/DioCrafts/OpenFoundry` 均 **HTTP 404**，无重定向（repo 改名/转移会 301，本仓无）。
- DioCrafts 账号存活（api.github.com/users/DioCrafts，2019-12 注册，**public_repos=33**，2026-09-07 枚举全部 33 仓），其中**无 OpenFoundry**——判定：原仓在 ontology-research 文档观察（2026-09-06）之后**被删除或转私有**。
- Wayback Machine 无存档：CDX 查询 `github.com/DioCrafts/OpenFoundry*` 与 `raw.githubusercontent.com/DioCrafts/OpenFoundry/*` 均返回空（web.archive.org/cdx，2026-09-07）。
- ontology 文档记录的"12–193 stars"因此**无法复核**（登记为不可验证的历史陈述）。

### 0.2 存活副本：DSMPromo fork（本报告的引用基准）

| 仓库 | 关系 | 许可证（LICENSE 原文） | 状态（2026-09-07） |
|---|---|---|---|
| `u485349-coder/OpenFoundry` | fork 网络当前根（API parent/source 字段指向它） | LICENSE 文件 **0 字节**（README 徽章自称 Apache-2.0，**无原文可验**）；main 树 ARCHITECTURE.md **0 字节**、21 个 services/ 子目录 | 102 stars，pushed 2026-04-23；账号 2025-11 注册、47 仓 |
| **`DSMPromo/OpenFoundry`** | **上述仓库的 fork（created 2026-05-22，pushed 2026-05-24），完整保留富内容快照** | LICENSE = **AGPL-3.0 原文逐字核验**（34,523 B，"GNU AFFERO GENERAL PUBLIC LICENSE Version 3, 19 November 2007"） | 1 star；**ARCHITECTURE.md 14,922 B**；51 个 services/ 子目录；完整 ADR 组（ADR-0007…0046）+ docs/architecture/* |
| 同名无关项目 | 消歧 | Shadowfax-Data/OpenFoundry（Apache-2.0，29★）、Przyval/openfoundry（Apache-2.0，19★）、smilebank7/OpenFoundry（Apache-2.0，4★）均无本报告所引的 ARCHITECTURE.md/Cedar/outbox 内容 | 非本报告对象 |

- **判定**：ontology 文档 1.1 节描述的 OpenFoundry（33 服务边界/Protobuf 契约/审计管道/Cedar/What-if）与 DSMPromo fork 快照内容**逐项吻合**（51 服务目录、ADR-0022 outbox、ADR-0027 Cedar、ADR-0033 branching、`action_what_if_branches` 表）；AGPL-3.0 判定经 fork LICENSE 原文确认成立。本报告所有引文出自 `https://github.com/DSMPromo/OpenFoundry`（main @ pushed 2026-05-24 快照），**这是唯一可核实的原文来源**。
- AGPL 边界纪律：本报告只读只引（研究性引用），**不复制任何代码/配置/SQL 进 gov-infra-repo**（§7）。

### 0.3 诚实边界

- 只逐字读了 ARCHITECTURE.md（229 行全文）、docs/architecture/contracts-and-sdks.md、ADR-0022、ADR-0027、ADR-0033、ADR-0044、docs/ontology-building/ontology-architecture/index.md、ontology-actions-service 两条 migration SQL、lakehouse-evidence summary（节选）、policy-bundles.md（节选）、services-and-ports.md（前 60 行）、runtime-topology.md（前 50 行）。其余 40+ ADR 与 services/ 源码实现**未读**；ADR 中指向的源码路径仅核实到"目录在 git 树中存在"，未逐文件核实实现。
- fork 是快照，**不能代表原仓最新状态**；原仓 404 后无法对照。

## 1. 四边界上下文划分（ARCHITECTURE.md §Service grouping）

原文（ARCHITECTURE.md L31-32）：

> "Services are grouped into Helm releases ("ownership boundaries") rather than physically merged binaries."

四边界 + 共享运维 release（L39-48 图，逐字摘录服务名）：

| 边界 | 服务（原文图内清单） | 职责判读 |
|---|---|---|
| **of-platform** | edge-gateway / identity-fed. / authorization / tenancy-orgs | 入口、身份、授权、租户=平台底座 |
| **of-data-engine** | connector-mgmt / ingestion-repl / dataset-versioni / lineage / media-sets / pipeline-build / sql-bi-gateway | 数据接入/版本化/血缘/管道/BI 网关 |
| **of-ontology** | ontology-definition / ontology-actions / ontology-query / object-database / ontology-indexer* | 本体控制面/动词/查询/写权威/索引 |
| **of-ml-aip** | model-catalog / model-deployment / agent-runtime / llm-catalog / retrieval-context / ai-evaluation / ai-sink* | 模型目录/部署/agent/LLM/RAG/评估 |
| of-apps-ops（共享） | application-composition, notebook-runtime, ontology-exploratory, solution-design, workflow-automation, notification-alerting, **audit-compliance + audit-sink***, telemetry-governance, federation-product-exchange, code-repository-review, sdk-generation, entity-resolution | 应用与运维横切（L50-60） |

- 底层存储面（L62-66 图）：Cassandra / Postgres（CNPG+PgBouncer）/ Kafka（Strimzi+MM2）/ Iceberg（Lakekeeper）/ Vespa / Temporal / Ceph（S3）。`* = Kafka sinks (counted separately from ownership boundaries)`（L68）。
- 划分要点判读：**按"所有权/Helm release"分组而不物理合并二进制**——边界是治理边界不是进程边界；与 DGA 的"权威源分工表"（INFRA 第 1 章）同构：DGA 用信息维度划权威源，OpenFoundry 用服务维度划所有权，两者都拒绝"一个进程包打天下"。
- 深读入口（L217-228 Bounded contexts 表）：Identity & federation / Authorization (Cedar/ABAC/RBAC) / Datasets-branches-transactions / Ontology kernel / Audit pipeline（`libs/audit-trail` + `services/audit-sink`）。
- 跨切面不变量段（L86-90）："These contracts are pinned by tests in `libs/core-models/**/*_test.go` and must not drift"——RID 格式 `ri.<service>.<instance>.<type>.<uuid>`（L95-97）、/healthz 载荷、JWT claims 字段名（L91-93）等全用测试钉死。

## 2. Protobuf 契约 → OpenAPI → 多语言 SDK 同步机制（contracts-and-sdks.md）

原文（contracts-and-sdks.md L3）：

> "OpenFoundry treats contracts as first-class repository artifacts."

- 单一契约源：`proto/` 按 23 个域分目录（L7-33 表：ai/audit/auth/dataset/ontology/pipeline/query/workflow 等）；buf 管理（`proto/buf.yaml|buf.lock|buf.gen.yaml`，L35-39）。
- 生成流（L43-56，原文图逐字）：

```text
proto/*.proto → of-cli docs generate-openapi / validate-openapi
  → apps/web/public/generated/openapi/openfoundry.json
  → TypeScript SDK / Python SDK / Java SDK / frontend consumers
```

- 产物落点表（L58-67）：OpenAPI JSON、三个 SDK、**Terraform provider schema JSON**（契约连 IaC provider schema 都从同一管道出）。
- 运维闸门（L69-82）：`make openapi-gen/check`、`sdk-typescript/python/java-gen/check`、`contracts-gen/check` 成对出现——**生成与"检查生成物未漂移"是两个独立 target**。
- 为什么（L86-93 逐字）：

> "Generated artifacts are not secondary documentation. In OpenFoundry they are part of the platform contract: … CI treats drift as a failure, not as optional cleanup"

**判读**：同步机制的核心不是"生成"而是 **drift=CI failure**：生成物入库、任何手工改动在 `contracts-check` 处挂掉。这正是 DGA"允许多种入口，不允许同一字段多个主写者"的工程化形态（LinkML YAML=唯一手写源，generated/* 同源产物=投影）。

## 3. 审计管道：PG Outbox → Debezium → Kafka → Iceberg（ADR-0022）

- 决策（ADR-0022 §Decision，L130-141 逐字要点）："the transactional outbox lives in the **`pg-policy.outbox.events`** table, written by the mutation handler inside the same Postgres transaction as any policy / metadata write, and is drained to Kafka by a **Strimzi-managed Debezium Kafka Connect** cluster running the official **Outbox Event Router SMT**."
- 表结构（L145-160）：`event_id uuid PRIMARY KEY`（**确定性 UUIDv5**，由 `(aggregate, aggregate_id, version, payload_hash)` 派生，L162-165："a retried handler converges and Debezium / consumers deduplicate trivially"）、`aggregate/aggregate_id/topic/headers jsonb/payload jsonb/created_at`。
- 生命周期（L174-175）："The table is short-lived: rows are deleted by Debezium **after** the Kafka offset for the produced record has been committed."（`outbox.event.deletion.policy: delete`，L240）——outbox 表不是日志是**待发布队列**，发布确认即删。
- 落 Iceberg 段（证据链）：
  - ARCHITECTURE.md L55/L68：`audit-compliance + audit-sink*`，`* = Kafka sinks`；
  - lakehouse-evidence/2026-05-03/summary.md（逐字）："ai-sink and audit-sink record append success/failure metrics immediately after Iceberg append attempts. **Kafka offsets are still committed only after successful appends.**"——at-least-once 消费 + **先落 Iceberg 后交 offset**，恰好一次生效（effective exactly-once）。
  - 审计事件契约：ARCHITECTURE.md L161-166："libs/audit-trail defines the standard compass.resource.* lifecycle events… handlers emit them in **the same transaction as the resource mutation**"。
- 失败模式表（L335-343，逐条）：handler 崩溃于 commit 前/后、Connect pod 崩溃（slot 保 WAL）、Kafka 不可用（slot >100 MB 报警）、slot 误删（"run a backfill workflow that re-emits every outbox row (the table is the source of truth until deletion)"）、schema 不匹配（Apicurio 拒 → 死信主题）。
- 生态位对比一节同页给出（L107-128）：为什么不用 LISTEN/NOTIFY（L118-120："in-memory, not durable"）、不用自研 relay（L107-113："strictly less production hardening"）。
- **判读**：该管道 = R-FLOW-02/03（唯一重试责任方/幂等键）+ R-EVID-03（独立写入权限：审计消费者只读 Kafka，写 Iceberg 的只有 audit-sink）在事件层的标准答案；代价是引入 Debezium+Kafka 两个 HA 组件（L365-371 自认），DGA 本机阶段不付这个成本（§6 吸收的是模式不是组件）。

## 4. Cedar 授权模型（ADR-0027）——只吸收模型表达，不吸收引擎

- 决策原文（L111-113）："We adopt **Option A**: **Cedar (the AWS open-source policy language and engine) is embedded as a Rust library** (`cedar-policy = "4"`) in every service that needs to make an authorisation decision."
- 它要表达的四类需求（L21-33）：对象级访问（read/write/**branch**）、**Marking 沿本体图传播**（"access requires holding every marking applied to the object"）、**分支感知**（"a user with read on `main` may have write on a personal branch"）、项目/组织边界 + 人类可写带类型 schema 的策略。
- 对 OPA 的拒绝理由（§Option C，L90-103，逐字）："Embedding OPA in Rust requires either: Calling out to a sidecar (network hop per decision), or Embedding OPA-WASM…"；"Rego is **untyped**; policy authors get errors at evaluation, not authoring. Cedar is typed against a schema and rejects ill-typed policies at upload."；"Cedar has a formal semantics and a published validator."
- 分发与热更新（L214-239）：策略文本与 schema 存 `pg-policy.cedar_policies`（writer=policy-decision-service 唯一写者，经 Cedar validator 验后入库），每次写发 outbox 事件 `authz.policy.changed` → Debezium → Kafka → NATS 桥 → 各服务热重载；启动失败时用"last known-good cached policy set"降级（L237-239）。
- 决策审计（L257-262，逐字）："Every decision emits a structured audit log line with: `principal_id`, `action`, `resource_id`, `decision`, `policy_ids` that contributed, `request_id`, `latency_us`. **Sampled to the audit pipeline (every Deny + 1% of Allows by default; configurable per service).**"
- **vs OPA 的裁决**：DGA 不翻案——CMP-03 已定 OPA 全量建设，且第 0 章修正声明②明确推翻"OPA 内嵌代码替代方案"。Cedar 的三个优势各有 DGA 对应解法：类型化 schema ↔ **LinkML 生成 OPA 输入类型**（gen-json-schema 同源，R-ONT-01 轨道）；无网络跳 ↔ **OPA 独立服务与工具网关同机部署**（SEL-03 §4）；形式语义 ↔ 本机量级下不构成决策瓶颈。**吸收点=模型表达**：①marking/信任标签作谓词属性（对应 DGA T0/T1/T2 sensitivity≤trust，R-POOL-TRUST——我们的 pool-routing.rego 已按此语义实现）；②策略文本带版本+active 位+authored_by/at 审计列（cedar_policies 表形制 L195-204）→ DGA 侧对应 Git 策略文件 + bundle revision 进 decision log（权威源在 Git 而非 DB，这是与 OpenFoundry 的刻意分歧，R-GOV-01/R-CFG-01）；③Deny 全采+Allow 采样的证据量控制策略（SEL-03 §6-3 登记）；④schema 变更跑全量策略验证的 CI 检查（L280-282）。

## 5. Action Type 支撑 What-if 分支的机制

- action_types 表（`docs/architecture/legacy-migrations/ontology-actions-service/20260423113000_action_types.sql` 逐字）：

```sql
CREATE TABLE IF NOT EXISTS action_types (
    id UUID PRIMARY KEY, name TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    object_type_id UUID NOT NULL REFERENCES object_types(id) ON DELETE CASCADE,
    operation_kind TEXT NOT NULL,
    input_schema JSONB NOT NULL DEFAULT '[]'::jsonb,
    config JSONB NOT NULL DEFAULT 'null'::jsonb,
    confirmation_required BOOLEAN NOT NULL DEFAULT FALSE,
    permission_key TEXT, owner_id UUID NOT NULL, ...);
```

- What-if 表（`20260426001500_action_type_policies_and_what_if.sql` 逐字核心）：

```sql
ALTER TABLE action_types
    ADD COLUMN IF NOT EXISTS authorization_policy JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE TABLE IF NOT EXISTS action_what_if_branches (
    id UUID PRIMARY KEY,
    action_id UUID NOT NULL REFERENCES action_types(id) ON DELETE CASCADE,
    target_object_id UUID REFERENCES object_instances(id) ON DELETE CASCADE,
    name TEXT NOT NULL, ...
    parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    preview JSONB NOT NULL DEFAULT '{}'::jsonb,
    before_object JSONB, after_object JSONB, ...);
```

- 机制判读：What-if = **Action 的干跑投影**——不执行 mutation，而是落一行"拟真分支"：捕获 `parameters`、算出 `preview`、存 `before_object`/`after_object` 前后快照，归属 `owner_id`，软删可追溯。动词（Action Type）与拟真（what-if branch）共享同一主数据，`authorization_policy` 直接挂在 action_types 上（GIN 索引，谓词下推）。这是"分支=另一种事务视角"的 Palantir parity 实现（ADR-0033 D1：markings 随分支**建分支时快照**，"the snapshot is the audit point"，父分支后加 marking 不回溯传播）。
- 对 DGA 的意义：本体论轨道的 What-if 落点=TerminusDB branch（Git-for-data）+ 自研动词层；OpenFoundry 证明的价值点是 **before/after 快照作为证据工件** 与 **confirmation_required/permission_key 内建于 Action Type**——与 R-GOV-04（决策卡固定结构）、MCP Action Registry（LinkML ActionType 的 security/audit 字段）一一对应。

## 6. 可吸收设计模式清单

| # | 模式 | 来源原文（摘句） | DGA 落点 | 吸收方式 |
|---|---|---|---|---|
| P1 | 契约即一等公民 + **drift=CI failure** | "Generated artifacts are not secondary documentation… CI treats drift as a failure"（contracts-and-sdks.md L86-91） | R-CFG-01/R-GOV-01；SEL-13b 生成器产物 | schemas/generated/* 入库；新增 CI 校验：gen-json-schema 重跑 diff=0，否则 fail（M0 已同源生成，缺的只是 check 闸） |
| P2 | 事务性 Outbox（业务写+事件写同事务，CDC 中继发布，发布确认后删） | "written by the mutation handler inside the same Postgres transaction"（ADR-0022 L132-136） | R-FLOW-02/03、R-EVID-03 | 模式登记进 runbook/证据层设计：控制面证据事件表同事务写；本机=脚本轮询读出，服务器若引入 Kafka 才升 Debezium（M6 PoC） |
| P3 | 确定性幂等键 event_id（UUIDv5(aggregate,id,version,payload_hash)） | "a retried handler converges … consumers deduplicate trivially"（ADR-0022 L162-165） | R-FLOW-03 | 证据事件/执行收据 ID 改用确定性派生（重跑收敛，不做随机 UUID）—— schemas ID 规则修订点 |
| P4 | 决策审计字段集 + **Deny 全采/Allow 采样** | "Every decision emits a structured audit log line with: principal_id, action, resource_id, decision, policy_ids…"（ADR-0027 L257-262） | R-POL-05 | opa_decisions 证据表字段集按此七元组+OPA 原生字段设计；采样默认全采，量级超限升级 S5（SEL-03 §6-3） |
| P5 | before/after 快照式 What-if（干跑落 preview+前后对象快照，归 owner） | `action_what_if_branches` 表（§5 引 SQL） | R-EVID-01；SEL-13d Action Registry | MCP Action Registry 增加 dry-run 语义：preview+before/after 快照作为执行收据附件；What-if 运行时落 TerminusDB 分支 |
| P6 | 跨切面不变量用测试钉死 | "These contracts are pinned by tests … and must not drift"（ARCHITECTURE.md L86-90） | R-EVID-03/R-CFG-01 | ID 前缀 22 前缀、schema 必填槽位、decision 卡六字段已做 M0 负面测试——固化为常驻 CI 用例而非一次性 |
| P7 | 写平面单一写权威 + append-only revisions 同事务 | "writes the current state, appends a revision record, and inserts an outbox row in a single transaction. No other service mutates object or link data directly."（ontology-architecture/index.md L40） | R-GOV-01/R-EVID-01 | 控制面 PG 增加状态历史表（append-only），与业务写同事务；台账只此一处可写 |
| P8 | 分支安全：marking 建分支时快照，不回溯传播 | "If the parent later gains a new marking, the **child does not inherit it** … The snapshot is the audit point."（ADR-0033 D1） | R-POL-02/R-POOL-TRUST | 授权不随上游放宽自动放宽：What-if/子任务分支继承授权时快照当时 scope，重验走 R-POL-02 |
| P9 | 策略 bundle 版本化 + 变更失效广播 + 降级用 last-known-good | ADR-0027 分发节（L214-239）+ policy-bundles.md："There is no central PDP on the hot path" | R-POL-05、SEL-03 | OPA decision log 原生带 bundles.revision（OPA docs，SEL-03 §3-4）——证据必含策略版本；OPA 不可达时网关按 fail-closed 拒绝（与 OpenFoundry 的缓存放行**刻意相反**：治理栈宁可停） |

## 7. 明确不吸收清单（含 AGPL 边界）

| # | 不吸收项 | 理由 |
|---|---|---|
| N1 | **任何 OpenFoundry 代码/配置/SQL 文本/ADR 文字进 DGA 仓库** | AGPL-3.0 传染（LICENSE 原文 §0.2）：网络服务分发须开源对应源码。控制面/证据层/Action Registry 是公司判定资产本体（PR-INF-01、ontology 文档 §2.3"护城河"），不得置于 AGPL。只做研究性阅读与模式归纳（本报告），实现全部独立写成 |
| N2 | 51 服务微服务拆分形态 | CMP-01：薄服务+PG，禁止过度拆分；OpenFoundry 自己都在 ADR-0030 做"service consolidation-30-targets"、services-and-ports.md 开篇自述 consolidation 状态——它自己也认为拆过头 |
| N3 | Cassandra/NATS/Kafka/Iceberg/Vespa/Ceph 数据面全家桶 | 一人公司无 Docker 本机 + 服务器阶段按需引入；CMP 表未含这些组件；第 3 章池化体系不需要其数据面。若 M6 证据层需事件中继，仅按 P2 模式自裁最小件 |
| N4 | Cedar 引擎 | 已定 OPA（CMP-03 + 第 0 章修正声明②）；吸收仅限模型表达（§4）。ADR-0027 拒 OPA 的理由（Rust 侧嵌入/网络跳）在 DGA 栈内不成立：控制面是 Python（SEL-01），OPA 独立服务+同机网关即答案 |
| N5 | 策略权威源放 DB（pg-policy.cedar_policies 制） | DGA 权威源=Git 经批准版本（第 1 章表、R-CFG-01）；DB 只存运行时投影（R-GOV-02 稳定定义/动态值分离） |
| N6 | OMCP（本体 MCP 对外暴露） | 其 ADR-0044 自己推迟（"Defer until MCP adoption stabilises"，L87-88）；DGA 的 MCP 网关+Action Registry 是自研动词层，不依赖对方路线 |
| N7 | 以 Palantir 文档逐段复刻为方法论（docs_original_palantir_foundry/ 对照法） | ADR-0033 通篇逐条对 Foundry 文档声明 parity——方法可读不可抄：对商业产品文档的逐段复刻有未评估的合规面，且 DGA 的 parity 对象是自家 Spec/Eval，不是 Foundry |

## 8. 结论

OpenFoundry 的价值在其**文档化的治理原语形制**：契约生成闸门（P1）、事务性证据事件（P2/P3/P7）、决策审计字段（P4）、干跑快照（P5）、分支安全快照（P8）。全部九项均可用 DGA 已定栈（LinkML+PG+OPA+Temporal+对象存储）以自有代码实现，无一需要引入其依赖。原仓消失事件本身也是一条治理注脚：**把架构认知写进自己仓库的 ADR 与测试，比 fork 别人的仓库更抗失联**——引用基准已固定为 DSMPromo 快照（§0.2），后续批次勿再引用 DioCrafts 路径。

---

*引用清单（核实于 2026-09-06/07）：api.github.com（repos/users/search/releases 多端点）；raw.githubusercontent.com/DSMPromo/OpenFoundry/main/{LICENSE, ARCHITECTURE.md, docs/architecture/contracts-and-sdks.md, docs/architecture/adr/ADR-0022…, ADR-0027…, ADR-0033…, ADR-0044…, docs/architecture/services-and-ports.md, docs/architecture/runtime-topology.md, docs/architecture/lakehouse-evidence/2026-05-03/summary.md, docs/ontology-building/ontology-architecture/index.md, docs/security-governance/policy-bundles.md, docs/architecture/legacy-migrations/ontology-actions-service/2026*}.sql}；web.archive.org/cdx（空结果）；open-policy-agent/opa 与 opentofu 相关引用见 SEL-03/SEL-10。*
