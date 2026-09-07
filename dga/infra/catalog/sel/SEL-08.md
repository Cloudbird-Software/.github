# SEL-08 调研报告：Langfuse（许可证分界与自托管边界）

- 任务来源：DGA-INFRA 第 8.2 节 SEL-08；CMP-07（推荐，核实许可证现状与自托管边界）
- 调研执行：SEL 轨道执行 agent
- 核实日期：2026-09-06（全部事实当日核实；许可证为仓库 LICENSE 原文逐字核对）

## 1. 任务范围与强制约束

- 8.2/SEL-08：核心 vs 功能分界的许可证现状；自托管边界。
- R-OBS-01：全链路 OpenTelemetry；Langfuse 管评估工作台。
- **R-EVID-02（边界红线）：Trace ≠ Evidence；评估界面 ≠ 校准能力**——本文须给出 Langfuse 数据与证据层的边界说明（§3.4）。
- R-EVID-03：证据本体走对象存储锁定管道（SEL-07），不因 Langfuse 存在而弱化。
- 本机环境约束（BUILD-LOG 环境侦察）：**无 Docker、无 WSL 发行版**——本文须给出本机无 Docker 前提下的可行性结论（§3.4/§4）。

## 2. 候选集

| 候选 | 形态 |
|---|---|
| A | Langfuse 自托管（开源核心，容器编排栈） |
| B | Langfuse Cloud（官方 SaaS） |
| C（对照/过渡） | 仅 OTel 管道（CMP-08 已定）+ 观测数据落自有存储，Langfuse 推迟 |

## 3. 评估矩阵

### 3.1 许可证原文结论（2026-09-06 逐字核对）

来源：[langfuse/langfuse LICENSE](https://github.com/langfuse/langfuse/blob/main/LICENSE)（raw 原文）：

- 版权行：**"Copyright (c) 2023-2026 ClickHouse, Inc."**（注意：非 Langfuse 独立实体——与 §3.5 收购事实互证）。
- 分界条款（原文逐字引）：
  > "All content that resides under the "ee/", "web/src/ee/", and/or "worker/src/ee/" directories of this repository, if these directories exist, is licensed under the license defined in "ee/LICENSE"."
  > "Content outside of the above mentioned directories or restrictions above is available under the "MIT Expat" license"
- **核心 = MIT Expat；`ee/`、`web/src/ee/`、`worker/src/ee/` 三目录 = 企业许可证**（目录级分界，与 LiteLLM 同款模式，可部署物审计）。

来源：[ee/LICENSE](https://github.com/langfuse/langfuse/blob/main/ee/LICENSE)（raw 原文头部）：

- "Langfuse is an open core project. Langfuse's core is permissively licensed (MIT license). Certain parts of the periphery of Langfuse are commercially licensed and governed by this Enterprise License."——并明确该企业许可**不适用于** `/LICENSE` 定义的核心。
- 结论：open core 结构现行有效；自托管 MIT 核心合法；**部署镜像不得包含 ee/ 目录编译产物**（官方 docker compose 的核心镜像不含 ee 功能——建设期按 §5 PoC 验证镜像内容）。

### 3.2 自托管系统要求（官方文档，2026-09-06）

来源：[ClickHouse 基础设施页](https://langfuse.com/self-hosting/deployment/infrastructure/clickhouse)、[Scaling/最低配置页](https://langfuse.com/self-hosting/configuration/scaling)（均逐页核实）：

Langfuse v3/v4 自托管必需组件（缺一不可）：

| 组件 | 作用 | 最低配置（官方 Scaling 页原文值） |
|---|---|---|
| Langfuse Web 容器 | 应用/界面 | 2 CPU, 4 GiB 内存 |
| Langfuse Worker 容器 | 异步事件处理 | 2 CPU, 4 GiB 内存 |
| **PostgreSQL** | 持久状态 | 2 CPU, 4 GiB 内存 |
| **ClickHouse** | trace/observation/score OLAP 存储；v3 要求 **≥ 24.3**（该页并显示 v4 要求 ≥ 25.12、推荐 26.4） | 2 CPU, 8 GiB 内存（大部署建议 ≥16 GiB） |
| **Redis/Valkey** | 队列与缓存 | 1 CPU, 1.5 GiB 内存 |
| **Blob 存储（S3 或 MinIO 兼容）** | 大事件载荷 | Serverless S3 或 MinIO（2 CPU, 4 GiB） |

- 时区约束：全部组件须 UTC（ClickHouse 页原文："ClickHouse must run with its timezone set to UTC"）。
- 部署方法：官方 docker compose（本地/自托管）与 Helm chart；无"单二进制"发行形态。
- **Windows 原生可行性**：ClickHouse 官方安装文档（[clickhouse.com/docs/install](https://clickhouse.com/docs/install)，2026-09-06 核实）生产安装路径仅列 Debian/Ubuntu、Redhat、NixOS、"Other Linux"，本地路径为 Quick install/Docker/源码——**Windows 不在安装路径之列**（文档未显式写"不支持 Windows"的声明，属路径缺失而非明文禁止，如实记录）。Redis/Valkey 官方亦无 Windows 原生生产支持形态（其 Windows 形态历来为非官方移植——本轮未逐页核实，如实标注）。

### 3.3 许可证/功能分界小结

- MIT 核心承载：trace 摄取、存储、查询、UI 基础面、prompt 管理、评估基础面（以核心目录内容为准——**具体哪些功能文件在 ee/ 下未逐目录清点**，建设期按 PoC N-3 实测验证；本轮不凭记忆列举 ee 功能清单）。
- 企业分界风险：上游可把功能从核心移入 ee/（open core 常态）；S5-PENDING-DEFAULTS 的追认机制覆盖该风险（升级触发登记）。

### 3.4 Trace ≠ Evidence 边界说明（R-EVID-02 落地）

- Langfuse 中的 trace/observation/score 是**观测投影**：界面可编辑、可删除、采样、聚合——不构成 R-EVID-03 的"记录未被改"证明。
- 边界管道设计（与 CMP-08/CMP-09 协同）：
  1. 执行单元/agent-core（SEL-04）产出 OTel trace → 同时双写：Langfuse（评估工作台，R-OBS-01）与**证据落盘管道**（关键判定步骤的收据摘要 → 对象存储 compliance 锁定，SEL-07）。
  2. 证据契约（R-EVID-01）字段含 trace ID 引用——证据本体在锁定对象存储，Langfuse 里的 trace 只是可点击的投影入口；Langfuse 数据丢失/被改不影响证据有效性，反之亦然。
  3. 评估工作台的"评估结果"是校准输入，不是校准判定本体（R-EVID-04 判定证据须含判定器模型+版本+校准域 ID，落证据存储）。
- 结论：**Langfuse 定位 = 观测与评估工作台（R-OBS-01）；永不作为证据权威源（R-GOV-01 权威源表无 Langfuse 条目，保持不新增）。**

### 3.5 归属变更事实（2026-01-16）

来源：[ClickHouse 官方公告](https://clickhouse.com/blog/clickhouse-raises-400-million-series-d-acquires-langfuse-launches-postgres)、[Langfuse 官方博客 joining-clickhouse](https://langfuse.com/blog/joining-clickhouse)（2026-09-06 核实）：

- ClickHouse 于 2026-01-16 收购 Langfuse（与 $400M Series D 同日宣布）；Langfuse 博客声明"roadmap stays the same"。
- 与 §3.1 版权行（ClickHouse, Inc.）互证。**治理风险重估**：核心存储层（ClickHouse）与 Langfuse 同主后，开源承诺的长期性是正面信号；单一公司控制下 open core 分界漂移风险仍存在（登记 §6 监测项）。

### 3.6 客户可复刻四问

1. **能否合法部署？** 能——MIT 核心自托管合法（LICENSE 原文 §3.1）；条件：不使用/不分发 ee/ 目录内容。
2. **部署文档与单机起步？** 有——官方 self-hosting 文档（infrastructure/scaling/升级指南系列）+ docker compose 起步栈；但"单机"= 单机跑全组件栈（§3.2 表 6+ 组件），非单二进制。
3. **强制云绑定？** 无——自托管为完整支持路径（官方部署文档体系）；Langfuse Cloud 为可选项。
4. **复刻缺失项？** ee/ 目录功能（具体清单待 PoC N-3 清点）；Cloud 侧运维（自动扩缩/SLO）由自建承担。交付 spec 须如实写明"评估工作台为观测投影，证据本体在对象存储"。

### 3.7 OTel 语义映射与本机管道形态（设计判断）

R-OBS-01 前半段（全链路 OTel）在本机即可成立，不依赖 Langfuse（设计声明）：

| 层 | 本机形态（无 Docker） | 服务器形态（M6+） |
|---|---|---|
| 摄取 | OTel SDK（控制面/执行单元/agent-core 进程内） | 同左 |
| 传输 | OTel Collector（Windows 原生二进制，资产待核 §6-6）→ 文件/PG 导出 | Collector → Langfuse OTel 端点 |
| 评估工作台 | 无（判定链调试用 trace 导出文件 + 控制面页面） | Langfuse 自托管（MIT 核心） |
| 证据管道 | 与观测管道并行：关键收据摘要 → B2 锁定桶（SEL-07） | 同左，trace ID 双向引用（§3.4） |

采样与保留纪律（R-EVID-02 防污染设计）：

1. 全量 trace 进观测管道；**证据不采样**——收据类关键步骤 100% 落锁定存储，Langfuse 侧采样率不影响证据完整性。
2. Langfuse 侧数据按运营保留期滚动清理；证据对象无限期锁定（S5-PENDING-DEFAULTS 第 6 项）——两套生命周期独立。
3. 工作台中的"评估结论"字段不得被证据管道引用为权威值（R-EVID-04 判定证据须含判定器模型+版本+校准域 ID，全部落证据存储）。

### 3.8 风险矩阵

| 风险 | 等级 | 依据 | 缓解 |
|---|---|---|---|
| open core 分界漂移（功能移入 ee/） | 中 | §3.1/§3.3 目录级分界机制 | 季度镜像审计 + LICENSE diff（§6-5） |
| 单一公司控制（ClickHouse）后的路线变化 | 中 | §3.5 收购事实 | OTel 中立格式防锁定（§7）；社区讨论渠道监测 |
| 本机无工作台导致评估延迟到 M6 | 低 | §4-2 里程碑解读 | 本机用 trace 导出 + 控制面页面顶替调试 |
| Langfuse 栈资源下限（合计 ≥10 GiB 级）超初期服务器预算 | 中 | §3.2 最低配置表 | 服务器规格规划时单列；必要时 ClickHouse 单副本起步（生产建议 3 副本，届时权衡升级 S5） |

## 4. 推荐与理由

**推荐：候选 C 为本机阶段形态（仅 OTel 管道，Langfuse 不在本机自托管）；候选 A 为 M6 服务器阶段形态（官方容器栈）；候选 B（Cloud）不采用（默认）。**

推导链（DGA-CORE 未交付，语义对应登记）：

1. 本机可行性判定（硬结论）：Langfuse v3+ 依赖 ClickHouse + Redis + Blob + Postgres 全栈容器编排（§3.2），ClickHouse 官方安装路径无 Windows——**无 Docker/WSL 的 Windows 本机不可行**（与 BUILD-LOG 阻塞判定 B/TerminusDB 同构）。此为环境事实，非选型缺陷。
2. R-OBS-01 分层解读：该条要求"全链路 OTel"（本机可先行：OTel SDK/collector 均有 Windows 原生形态——collector 单二进制，建设期核实其 Windows 资产后启用）+ "Langfuse 管评估工作台"（工作台是 M6 证据层里程碑的组件，服务器阶段落位不违背里程碑次序）。
3. R-EVID-02 边界（§3.4）：Langfuse 越晚接入越不污染证据管道设计——先固化"证据走锁定对象存储"的契约，再接工作台，防止评估界面被误用为校准权威（第 7 章"判定隔离"验收项）。
4. PR-INF-01：MIT 核心 + 目录级分界 + ClickHouse 治理背书 → 复刻资产价值成立；自托管形态正是企业客户可复刻形态（A 比 B 更贴 PR-INF-01.a 的"自己怎么跑"叙事）。

## 5. PoC 计划与对应负面测试清单

PoC（服务器阶段 M6 前置；本机仅做 OTel 半段）：

1. 本机：OTel SDK（含 SEL-04 agent-core 的 trace 出口）→ OTel Collector（Windows 原生二进制，建设期核实资产）→ 落地文件/PG——验证 R-OBS-01 前半段不依赖 Langfuse。
2. 服务器：官方 docker compose 起 Langfuse（MIT 核心镜像），OTel 管道接入，验证 trace/评估工作台可用。
3. 证据双写管道：关键步骤收据 → B2 锁定桶（SEL-07），trace ID 关联。

负面测试：

| # | 负面测试 | 期望 |
|---|---|---|
| N-1 | 删除/改写 Langfuse 中某 trace 后，凭证据契约重放判定链 | 证据本体（锁定对象）完好，治理结论不依赖被改 trace（R-EVID-02 实测） |
| N-2 | Langfuse 全宕机 | 执行单元/闭环继续运行（观测降级非业务降级）；恢复后追补导出（联动 R-GOV-07 降级模式） |
| N-3 | 镜像内容审计：部署镜像不含 ee/ 功能（触发任一 ee 专属功能入口应不可用） | 审计通过并记录为交付 spec 附录（§3.3 缺失项清单） |
| N-4 | 租户隔离：客户 A 的执行单元 trace 在工作台不可见客户 B | 隔离生效（第 7 章"遥测与租户隔离"验收项） |

## 6. 待 S5 裁决点（每点附默认方案）

| # | 裁决点 | 默认方案（先行，待追认） |
|---|---|---|
| 1 | 本机观测形态 | 仅 OTel 管道（Collector Windows 原生，资产待核）+ 落地 PG/文件；Langfuse 不自托管于本机 |
| 2 | Langfuse 落位时点 | M6 服务器阶段（与证据层里程碑绑定）；不提前 |
| 3 | Langfuse Cloud 是否允许 | 不采用（数据出域 + 复刻叙事弱化）；若 S5 欲用于演示场景，另裁数据边界 |
| 4 | ee/ 功能依赖策略 | 零依赖（默认）；若某 ee 功能（如高级 RBAC）被需要 → 升级 S5 裁决采购或替代 |
| 5 | open core 分界漂移监测 | 每季度跑 PoC N-3 镜像审计 + LICENSE diff；分界变化触发重估（8.5 升级触发） |
| 6 | OTel Collector Windows 原生资产核实 | 建设期对 collector releases 逐 asset 核实并回填本文（本轮未核，不预断） |

## 7. 回滚与迁移成本

- Langfuse → 无：观测降级，执行链无损（§5-N2 设计）；trace 数据已双写 OTel 后端/自有存储，无锁定损失。
- Langfuse → 替代工作台（如其他 OTel 原生 UI）：OTel 为中立格式，切换 = 换消费端；成本：低-中（评估数据集/评分结构需迁移映射）。
- 自托管 → Cloud（或反向）：SDK/摄取 API 同构，迁移为数据重放；Cloud→自托管方向受 Cloud 导出能力约束——**默认不采用 Cloud 即消除该单向风险**。
- 数据寿命纪律：Langfuse 内数据按运营数据保留策略滚动清理；证据本体永存对象存储——两套生命周期互不绑定，回滚任一不影响另一。

---

*引用清单（核实于 2026-09-06）：github.com/langfuse/langfuse（LICENSE、ee/LICENSE raw 逐字）；langfuse.com（/self-hosting/deployment/infrastructure/clickhouse、/self-hosting/configuration/scaling、/blog/joining-clickhouse）；clickhouse.com（docs/install、acquisition 公告）。*
