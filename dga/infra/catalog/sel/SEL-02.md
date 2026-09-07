# SEL-02 调研报告：Temporal 后端与部署形态

- 任务来源：DGA-INFRA 第 8.2 节 SEL-02；CMP-02（S5 已定：全量自托管）
- 调研执行：SEL 轨道执行 agent
- 核实日期：2026-09-06（本文全部事实均于当日核实，未核实处显式标注）
- 纪律声明：本文不包含任何凭模型记忆断言的版本号/支持状态；全部带来源 URL。

## 1. 任务范围与强制约束

- R-FLOW-01：跨系统、跨天、含人类等待的流程一律进 Temporal；Agent 会话不承载等待。
- R-FLOW-02：每个有外部副作用的步骤，唯一重试责任方；结果不明进"待核实"。
- R-FLOW-03：幂等键 + 结果核对 + 补偿；Temporal 语义不默认保证恰好一次。
- R-FLOW-04：崩溃恢复后可区分：已发生/未发生/未确定的副作用。
- CMP-02 硬约束：全量自托管；后端倾向单库 MySQL/Postgres，Cassandra+ES 为扩展预留——须核实 2026 生产支持等级（本文即该核实）。
- DGA-INFRA 第 9 章第 7 项：Temporal 后端选型为待 S5 裁决项（本文提供裁决输入）。
- 8.4 客户可复刻四问硬约束（PR-INF-01.e）：许可证允许客户合法部署、有单机起步路径、无强制云绑定、复刻功能缺失明示。

## 2. 候选集

Temporal Server 为 S5 指定组件（CMP-02 已定），故候选集为**持久层/部署形态**组合，非引擎替换：

| 候选 | 组合 | 说明 |
|---|---|---|
| A | PostgreSQL 单库后端（主存储 + Advanced Visibility 同引擎） | 单库运维，与控制面 CMP-13 同栈 |
| B | MySQL 单库后端（主存储 + Advanced Visibility 同引擎） | 同上，MySQL 变体 |
| C | PostgreSQL + Elasticsearch/OpenSearch 分离 visibility | 扩展形态（S5 预留项） |
| D（对照，不推荐） | Cassandra 体系 | 已核实其 visibility 支持被移除，见 §3 |

本机开发形态（owner 已定）：Temporal CLI dev server，不进入生产候选（见 §3.4 差距清单）。

## 3. 评估矩阵

### 3.1 Advanced Visibility 支持矩阵（官方文档，逐行核实）

来源：[Temporal 自托管指南 · Visibility](https://docs.temporal.io/self-hosted-guide/visibility)，核实 2026-09-06。

| Visibility 后端 | Server 版本要求 | 备注 |
|---|---|---|
| PostgreSQL ≥ 12 | Server ≥ v1.20 | Advanced Visibility 当前代 |
| MySQL ≥ 8.0.17 | Server ≥ v1.20 | Advanced Visibility 当前代 |
| SQLite ≥ 3.31.0 | Server ≥ v1.20 | Advanced Visibility 当前代 |
| Elasticsearch v7 | Server ≥ v1.7 | |
| Elasticsearch v8 | Server ≥ v1.18 | |
| OpenSearch 2+ | Server ≥ v1.30.1 | |
| Cassandra | **不支持**（Advanced Visibility） | 官方提供迁移指南链接 |

关键结论（同页原文核实）：

1. **ES/OpenSearch 不是必需品**：页面通篇未声明任何场景"必须"使用 ES；其定位为"Recommended for any setup that spawns more than a few Workflow Executions"（推荐给产生多于少量 Workflow Execution 的部署）。即：纯 SQL 后端承载 visibility 是正式支持形态。
2. Advanced Visibility（当前代）"supports the modern query model, including custom Search Attributes"——即纯 SQL 后端同样支持自定义 Search Attribute 查询，不是残缺形态。
3. Standard Visibility（旧代）"deprecated in Temporal Server v1.21 and removed in v1.24"；旧代下 Cassandra 同样 "Deprecated in Temporal Server v1.21, removed in Temporal Server v1.24"（visibility 语境）。
4. 持久存储与 visibility 存储"can use any combination of the supported databases"——单引擎双库/双 schema 组合是官方支持面。
5. Server v1.21 起支持双 visibility 存储（Dual Visibility），官方定位为 visibility 库迁移工具——这是 SQL→ES 升级路径的官方机制（同页核实）。

### 3.2 版本快照（2026-09-06 核实）

| 组件 | 最新版 | 发布/资产证据 | 来源 |
|---|---|---|---|
| Temporal Server | v1.31.2 | 发布于 2026-07-08；release 资产含 `temporal_1.31.2_windows_amd64.zip`、`temporal_1.31.2_windows_arm64.zip` | [temporalio/temporal releases](https://github.com/temporalio/temporal/releases)（GitHub API releases/latest 逐资产核实，2026-09-06） |
| Temporal CLI | v1.8.3 | 资产含 `temporal_cli_1.8.3_windows_amd64.zip` 等 | [temporalio/cli releases](https://github.com/temporalio/cli/releases)（GitHub API 逐资产核实，2026-09-06） |

Windows 现状结论：**Server 与 CLI 均有官方 Windows 原生二进制资产**（逐 asset 核实）。但官方部署文档面向 Docker/Kubernetes/手动部署（见 3.3），Windows 原生 server 属"资产存在、部署文档不覆盖"状态。本机已定 dev server 方案（S5-PENDING-DEFAULTS 第 7 项），服务器部署形态按 Linux 容器/二进制规划。

### 3.3 部署形态与单库后端运维要点

来源：[部署文档](https://docs.temporal.io/self-hosted-guide/deployment)、[生产检查清单](https://docs.temporal.io/self-hosted-guide/production-checklist)，核实 2026-09-06。

- 官方部署方法四种：① docker-compose（samples-server 仓库，默认栈=PostgreSQL + Elasticsearch，gRPC Frontend 7233）；② 两个 Go 二进制（server + UI，可 systemd + Nginx/Envoy）；③ 作为 Go 库导入自建进程（Server Options 插件机制，Go ≥1.19）；④ Helm chart 接入既有 DB 与 ES。
- `temporalio/server` 镜像为生产形态（"This is what you need to use in your production environments"）；使用该镜像须"manually manage schema updates using the `temporalio/admin-tools` image"。
- 安全基线：服务"should be secured similarly to a database"，主机"should not be exposed to the open internet"。
- **Shard 数在建库时定死且"can't adjust it later"——加 shard 需重建+迁移**（生产检查清单原文）。单库起步时这是唯一需要在容量上先想清楚的参数。
- 自托管 Temporal **不带控制面**：无开箱 RBAC、无审计日志（"Self-hosted Temporal doesn't support role-based access control (RBAC) or audit logging out of the box"）——须自建。对 DGA 而言该缺口由控制面（CMP-01）+ OPA decision log（R-POL-05）补位，不重复建设。
- 升级纪律：顺序升级、不可跳 minor（patch 可跳）；使命关键可用性目标 99.99%、须 Multi-Cluster Replication（同页）。
- 官方压测工具 Omes；监控三类指标：service / persistence / Workflow Execution 统计（同页）。

### 3.4 dev server 与生产的差距清单

来源：[自托管指南](https://docs.temporal.io/self-hosted-guide/)（dev server 定位："a single binary with no external dependencies"，`temporal server start-dev`，官方明确"推荐用于本地开发，即使你生产计划自托管或用 Cloud"），核实 2026-09-06。

| 维度 | dev server | 生产自托管 |
|---|---|---|
| 进程/依赖 | 单二进制、零外部依赖 | server+UI 多进程/容器 + 外部 DB（+可选 ES） |
| 存储 | 内嵌存储（零依赖即指不外挂数据库） | PostgreSQL/MySQL（主+visibility 独立库）或 ES/OpenSearch |
| Schema | 自动 | 须用 admin-tools 手动管理 schema 更新 |
| 安全 | 无生产 TLS/账号体系要求 | 须按"同数据库级别"安全加固；不得暴露公网 |
| 可用性 | 单点、非持久承诺 | 99.99% 目标、备份、多集群复制（使命关键） |
| 观测 | 基本无 | persistence/服务指标 + Omes 压测 |
| 升级 | 跟随 CLI | 顺序升级纪律 + schema 版本对齐 |

推论（工程纪律）：dev server 产生的 Workflow 历史**不构成可迁移资产**；本机调试流程代码可无缝切生产（SDK 相同），但运行历史以生产库为唯一权威源（对应 R-GOV-01 权威源表：流程执行位置/等待/重试状态权威源 = Temporal——指生产实例）。

### 3.5 客户可复刻四问（对"Temporal 自托管 + PostgreSQL 后端"整体）

1. **客户能否合法部署？** 能。Temporal Server 与 CLI 为 MIT License（仓库 LICENSE：[temporalio/temporal](https://github.com/temporalio/temporal)、[temporalio/cli](https://github.com/temporalio/cli)——注：两仓库 LICENSE 文件原文未在本轮逐字打开核对，GitHub 仓库页标注 MIT；见 §6 待裁决点 4 要求建设期补一次逐字核对）。PostgreSQL 许可证另见 SEL-01/控制面栈。
2. **有无部署文档与单机起步路径？** 有。官方自托管指南四种部署方法 + 生产检查清单 + samples-server compose 栈；单机起步 = dev server 或单节点 compose（来源同 §3.3）。
3. **是否存在强制性云绑定或供应商锁定？** 无强制。Temporal Cloud 存在但自托管为完整受支持路径（本文全部依据即自托管文档）。锁定点在 Workflow 代码 SDK 语义（Go/Java/Python SDK），迁移成本见 §7。
4. **复刻时哪些功能会缺失？** Web UI 控制面能力有限、无内置 RBAC/审计日志、无自带多集群（MCR 需自建运营）。这些缺失对 DGA 是显式的（控制面自研补位），对客户复刻必须如实写入交付 spec（PROD-05 语义）。

### 3.6 候选对照小结

| 维度 | A: PG 单库 | B: MySQL 单库 | C: PG+ES | D: Cassandra（对照） |
|---|---|---|---|---|
| Advanced Visibility 支持 | 是（≥v1.20，PG≥12） | 是（≥v1.20，≥8.0.17） | 是（最完整查询能力） | 否（visibility 已移除） |
| 与 CMP-13 同栈 | 是（控制面主库=PG） | 否 | 部分 | 否 |
| 运维面 | 单引擎 | 单引擎 | 双系统（+JVM 集群） | 高（被官方逐步移除） |
| 扩展触发 | 查询/量级压力时经 Dual Visibility 平滑加 ES | 同左 | 已是扩展形态 | 迁移出（官方指南） |

来源：§3.1 同页矩阵；Cassandra 结论为官方矩阵原文。

## 4. 推荐与理由

**推荐：候选 A（PostgreSQL 单库后端）为生产默认；本机 dev server 维持；C（+ES/OpenSearch）作为显式触发条件下的扩展路径，不做预建。**

推导链（DGA-CORE 原文未交付，按 DGA-INFRA 归档注以语义对应登记）：

1. PR-INF-01（企业级复刻即资产）：单库 Postgres 是企业常见形态且有官方支持等级背书（Server ≥v1.20 + PG ≥12），复刻叙事完整；无 ES 不构成架构缩水（§3.1 结论 1/2：SQL 承载 Advanced Visibility 为正式支持形态）。
2. PR-INF-01.c（运维负担 vs 复刻价值相权）：跳过 ES 省去 JVM 集群运维（执行成本），而查询能力仍为当前代（资产价值不损）。
3. 第 3 章/R-GOV-01：控制面主库已定 PostgreSQL（CMP-13），池账本/闭环登记与 Temporal 持久层同引擎 → 备份、监控、IaC、DBA runbook 四类工件复用。
4. R-FLOW-03/04：幂等与崩溃可区分性由 Temporal 语义 + 我们的应用层补偿承担，与后端引擎选择正交；单库不削弱该要求。
5. 升级路径闭合：v1.21+ Dual Visibility 提供 SQL→ES 的官方在线迁移机制，扩展为"加法式"而非"重做式"（§3.1 结论 5）——满足 8.5"架构不缩水、分期的是范围"。

## 5. PoC 计划与对应负面测试清单

PoC（M2–M3 前置，本机 dev server → 单节点 PG compose）：

1. `temporal server start-dev` 跑通第一条跨天含人工等待的流程（R-FLOW-01）。
2. compose 栈裁剪 ES（仅 PG），部署 `temporalio/server` + admin-tools schema 初始化，验证 List/Query/Search Attribute 在纯 SQL Advanced Visibility 下可用（§3.1 结论 2）。
3. 压测参数记录：单库 PG 下 shard 配置决策记录（§3.3 shard 不可后加）。

负面测试（对应第 7 章验收矩阵"恢复与幂等"）：

| # | 负面测试 | 期望 |
|---|---|---|
| N-1 | Worker 执行外部副作用（HTTP 调用）后进程被 kill，重启 | 副作用不重复发生；结果不明时进"待核实"状态而非盲重发（R-FLOW-02/03） |
| N-2 | 流程执行中途杀掉整个 server + DB，恢复后核对 | 已发生/未发生/不确定副作用可区分（R-FLOW-04） |
| N-3 | 在无 ES 的 SQL visibility 下按自定义 Search Attribute 查询跨命名空间流程 | 查询成功（验证 §3.1 结论 2，防"SQL visibility 是残缺形态"的假设） |
| N-4 | 跳版本升级演练（dev 环境故意 skip minor） | 按官方纪律应被流程阻止/记录为违规，验证 runbook 有牙齿 |

## 6. 待 S5 裁决点（每点附默认方案）

| # | 裁决点 | 默认方案（先行，待追认） |
|---|---|---|
| 1 | 生产后端定稿（第 9 章第 7 项） | PostgreSQL 单库（主+visibility 同引擎分库），Server ≥v1.20 + PG ≥12 支持线 |
| 2 | ES/OpenSearch 引入触发条件 | 触发条件预登记：① visibility 查询延迟/规模超出 PG 能力实测阈值；② 出现跨集群审计检索需求。默认不预建，触发后经 Dual Visibility 加法式迁移 |
| 3 | 服务器部署形态 | Linux + `temporalio/server` 镜像（compose 起步，K8s 后评估）；Windows 原生二进制仅作实验，不进生产 |
| 4 | 仓库 LICENSE 逐字核对补漏 | 建设期对 temporalio/temporal、temporalio/cli 的 LICENSE 文件各做一次逐字核对并回填本报告（本轮依赖 GitHub 仓库页标注 MIT，未逐字打开原文） |
| 5 | shard 数初值 | 建库前按 Omes 压测结果定初值并写入 runbook（默认：单机规模最小可用值，宁小勿滥，因不可后加） |

## 7. 回滚与迁移成本

- dev server → 生产 PG：流程代码零迁移（同 SDK），历史不可迁移（dev 数据非资产，§3.4）。成本≈0。
- PG ↔ MySQL：官方支持两引擎，但切换需数据层迁移（导出/重放或双写窗口），无官方在线换引擎机制——**选型后回滚成本高，裁决点 1 应一次定死**。
- PG → +ES（候选 C）：加法式。Dual Visibility 双写 → 历史回填 → 切主 → 摘除 SQL visibility（§3.1 结论 5）。成本中等、在线操作。
- 自托管 → Temporal Cloud：SDK 不变，迁移为运营动作；反之亦然。当前无计划，仅登记存在此通道。
- 回滚触发登记：若 PoC N-3 失败（SQL visibility 查询残缺），本推荐降级为候选 C，并登记 BUILD-LOG。

---

*引用清单（全部核实于 2026-09-06）：docs.temporal.io（visibility / self-hosted-guide / deployment / production-checklist 四页）；github.com/temporalio/temporal 与 temporalio/cli 的 releases API（逐资产）。*
