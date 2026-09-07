# SEL-04 调研报告：OpenJiuwen 调研与定位

- 任务来源：DGA-INFRA 第 8.2 节 SEL-04；CMP-04（S5 已定：纳入全量建设）
- 调研执行：SEL 轨道执行 agent
- 核实日期：2026-09-06（全部事实当日核实）
- 报告性质：**事实 与 待 S5 定位 两分离**（CMP-04 的定位说明仍待 S5 补充，本文不代替 S5 裁决）

## 0. 结论速览（两分离声明）

- **事实层**：项目**真实存在且高度活跃**。GitHub org `openJiuwen-ai`（18 个公开仓库，旗舰 jiuwenswarm 8,133 stars），多数仓库 Apache-2.0，最近提交在核实当日。产品定位为开源 AI Agent 平台（低代码 Studio + Python/Java SDK + 分布式 Runtime + MCP/A2A 协议栈）。
- **待 S5 层**：CMP-04 在 DGA-INFRA 中的"治理场景资产"具体落位（哪个仓库、哪条流程、哪个里程碑插槽）仍需 S5 定位说明；本文仅核实事实与候选集成点。

## 1. 任务范围与强制约束

- 8.2/SEL-04：核实项目现状、许可证、活跃度、与栈的集成点；输出集成方案与里程碑插入点；先向 S5 确认定位说明。
- CMP-04：定位为"可企业级复刻的治理场景资产"；在架构中预留治理场景组件集成位。
- PR-INF-01.e / 8.4：客户可复刻四问为硬约束——**许可证必须查 LICENSE 原文**（本文对主仓库已逐字打开核对）。
- R-GOV-01：集成后其运行状态不得成为任何权威源的唯一主写者（集成位是执行组件，不是权威源）。

## 2. 候选集（= 项目内可集成单元）

OpenJiuwen 为 S5 指定项目，无替换候选；候选集为其**仓库/模块选择**（来源：[GitHub org](https://github.com/openJiuwen-ai) 与官方文档仓 [openJiuwen-ai/docs](https://github.com/openJiuwen-ai/docs)，核实 2026-09-06）：

| 单元 | 定位 | 集成相关度 |
|---|---|---|
| agent-core | Python Agent SDK（编排/运行时/模型/工具/检索/评测） | **高**（框架集成主候选） |
| agent-protocol | MCP SDK / A2A SDK / A2X Registry（C++） | **高**（工具网关/OPA 执行点对接面） |
| agent-core-java / agent-runtime-java | Java SDK 与 Spring Boot Runtime | 中（客户侧复刻选项） |
| agent-studio | 低代码/零代码可视化开发平台（Java） | 中（治理场景演示资产） |
| agent-runtime | Agent 服务化运行/部署管理平台（Python） | 中 |
| agent-memory | 长期记忆模块 | 低-中 |
| jiuwenswarm | 多智能体协同旗舰应用 | 低（应用而非框架） |
| deepsearch / skillhub / sciencediscovery 等 | 应用/生态 | 低 |

## 3. 评估矩阵

### 3.1 项目现状（GitHub API 逐仓库核实，2026-09-06）

来源：GitHub API `orgs/openJiuwen-ai/repos`（逐项拉取，2026-09-06）：

| 仓库 | Stars | Forks | Open Issues | 最近 push | 创建 | 语言 | License(API) |
|---|---|---|---|---|---|---|---|
| jiuwenswarm | 8,133 | 1,238 | 1,332 | 2026-09-05 | 2026-03-05 | Python | Apache-2.0 |
| agent-core | 424 | 101 | 267 | 2026-09-05 | 2026-02-26 | Python | Apache-2.0 |
| agent-studio | 162 | 49 | 175 | 2026-09-04 | 2026-02-26 | Java | Apache-2.0 |
| deepsearch | 119 | 26 | 33 | 2026-09-04 | 2026-02-26 | Python | **无 LICENSE 文件（见 3.3）** |
| agent-protocol | 81 | 24 | 20 | 2026-09-04 | 2026-02-26 | C++ | Apache-2.0 |
| agent-memory | 57 | 17 | 57 | **2026-09-06（核实当日）** | 2026-06-18 | Python | Apache-2.0 |
| agent-runtime | 12 | 4 | 12 | 2026-09-04 | 2026-06-29 | Python | Apache-2.0 |
| 其余 10 仓 | — | — | — | 均在 2026-08~09 | — | — | 多为 Apache-2.0；docs/community 为 CC-BY-4.0 |

活跃度证据：

- agent-core 最近提交（GitHub API commits，2026-09-06 拉取）：`2026-09-04 feat(symphony): add graph experience accumulation`、`2026-09-04 fix(trace): Fix OTel trace breakage…` 等，提交间隔以小时计。
- Release：jiuwenswarm v0.2.5（2026-08-25）；agent-core v0.1.17（2026-08-20）（GitHub API releases/latest，2026-09-06）。**版本均 <1.0**。
- 组织首个仓库创建于 2026-02-26 → 项目公开期约 6 个月（截至核实日）。
- 官方站：[openjiuwen.com](https://openjiuwen.com/)；文档中心：[openJiuwen-ai/docs](https://github.com/openJiuwen-ai/docs)；官方文档同时维护 [gitcode.com/openJiuwen](https://gitcode.com/openJiuwen) 镜像位（docs 仓 产品简介.md 链接表，2026-09-06 核实）。

### 3.2 LICENSE 原文结论

逐字打开核对（raw.githubusercontent.com，2026-09-06）：

- [agent-core/LICENSE](https://github.com/openJiuwen-ai/agent-core/blob/main/LICENSE)：**Apache License 2.0** 原文（"Apache License / Version 2.0, January 2004" 全文起始逐字核对）。
- [jiuwenswarm/LICENSE](https://github.com/openJiuwen-ai/jiuwenswarm/blob/main/LICENSE)：**Apache License 2.0** 原文（同上逐字核对）。
- docs / community 仓库：API 标注 CC-BY-4.0（未逐字打开，建设期补核）。
- **deepsearch：raw LICENSE 返回 HTTP 404，GitHub API license 字段为 null——无 LICENSE 文件。在澄清前不得复用其代码。**
- 未逐字打开核对的其他仓库：以 API 标注为线索，集成选定仓库时逐个补核（登记 §6）。

### 3.3 功能定位（官方文档引文）

来源：[openJiuwen-ai/docs · zh/产品简介.md](https://github.com/openJiuwen-ai/docs/blob/main/zh/产品简介.md)（经 GitHub API 原文拉取，2026-09-06）：

- 定位："openJiuwen作为开源Agent平台，致力于提供灵活、强大且易用的 AI Agent 开发与运行能力……助力企业与个人快速搭建 AI Agent 系统或平台"。
- 分层架构五层：DeepAgents（jiuwenswarm/jiuwensymbiosis/deepsearch）→ Agent Studio（低代码/零代码）→ Agent Framework（agent-core 等 SDK）→ Agent Distributed Runtime（多租户隔离/弹性扩缩/注册发现）→ Agent System Service（沙箱/记忆持久化/文件系统/通信总线）。
- agent-protocol 说明："Agent 互操作协议 SDK，提供 MCP SDK、A2A SDK 与 A2X Registry"。
- 背景关联（**二手转述，未直接核实原文，仅登记不作事实使用**）：搜索结果（中国人民大学 SE 办公室新闻页、昇腾社区上手指南转述）称 openJiuwen 为华为生态开源项目并有高校合作活动；此说法未从官方渠道逐字核实，待建设期从 openjiuwen.com/community 页直接核实。

### 3.4 客户可复刻四问

1. **能否合法部署？** agent-core / jiuwenswarm 等 Apache-2.0 仓库：能（含商业部署、修改、分发，附 NOTICE/许可声明义务）。deepsearch：**当前不能**（无 LICENSE，默认保留所有权利）。
2. **有无部署文档与单机起步路径？** 有：官方文档中心 docs 仓 + 各 SIG 仓库内 docs 目录（agent-core/agent-studio 均有 docs 目录链接，docs 仓 README 核实）；openjiuwen.com/docs-page 提供 pip 安装/源码运行路径（搜索结果转述，建设期 PoC 实测——登记 §5）。Java 栈仓库基于 Spring Boot（agent-runtime-java 仓库描述，API 核实）。
3. **是否存在强制性云绑定？** 无强制。全部组件仓库公开可自托管；gitcode 镜像与 openjiuwen.com 在线体验为可选服务，未发现无云不可运行的声明（基于已核实文档面；PoC 阶段以"离线部署"为验收项验证）。
4. **复刻缺失项？** 版本 <1.0（API 不稳定风险）；企业级支持/SLA 无（社区开源）；agent-gateway "当前 Opening Soon"（产品简介.md 原文）——通道网关缺失需自建或以 LiteLLM/自研网关补位；Studio 完整功能边界待 PoC 确认。

### 3.5 能力 / 运维 / TOS / 集成 / 活跃度速评

| 维度 | 评估 | 依据 |
|---|---|---|
| 能力 | Agent 编排/多智能体/工具/记忆/评测全链 SDK，与 DGA Harness 层同构可替换评估 | 产品简介.md（2026-09-06） |
| 运维成本 | 年轻项目（6 个月），<1.0 版本，API 变动风险；Java+Python 双栈运维面大——按单元选集成，不全量 | §3.1 版本证据 |
| TOS | 开源仓库使用无 TOS 灰区；在线体验/云服务条款未评估（默认不使用） | 本文范围 |
| 集成点 | ① agent-protocol MCP SDK ↔ 工具网关（R-POL-01 服务器端强制点）；② agent-core OTel trace ↔ OTel/Langfuse（R-OBS-01；commit "fix(trace): Fix OTel trace breakage" 证明 OTel 出口存在）；③ agent-core 模型接口 ↔ LiteLLM 池端点（待 PoC 验证其 OpenAI 兼容面） | §3.1 提交证据 + 产品简介.md |
| 活跃度 | 高（旗舰仓 8k stars、当日 push、双周 release 节奏） | §3.1 |

### 3.7 功能特性与治理相关性（官方文档功能节）

来源：[openJiuwen-ai/docs · zh/产品简介.md](https://github.com/openJiuwen-ai/docs/blob/main/zh/产品简介.md) 功能特性节（2026-09-06 原文拉取）：

- 开发态："openJiuwen在开发态提供了Agent编排构建的能力，帮助开发者快速构建Agent，进行高效开发。"
- 运行态："openJiuwen在运行态提供了高可靠执行引擎作为底座的能力，为智能体的高效运行提供保证。"
- 与 DGA 治理条的映射（设计判断，非上游声明）：

| openJiuwen 能力 | DGA 治理面的接触点 | 需要补的治理壳 |
|---|---|---|
| 工具/技能调用（agent-core + skillhub） | R-POL-01 工具网关强制点 | 所有工具调用经 OPA 网关；skillhub 分发的 skill 须入 Git 审批流（R-GOV-02） |
| 多智能体协同（jiuwenswarm） | R-POL-02 子任务权限 ≤ 父任务 | 每个 agent 独立虚拟 key + 预算（SEL-05） |
| 记忆子系统（agent-memory） | R-GOV-01 权威源 | 记忆库非权威源；判定与授权状态只在控制面 DB |
| OTel trace 出口 | R-OBS-01 / R-EVID-02 | 双写证据管道（SEL-08 §3.4） |
| Studio 低代码编排 | PR-INF-01 复刻资产（演示/交付件） | Studio 产出的流程定义导出进 Git（防"界面即定义"黑箱） |

### 3.8 风险矩阵（调研发现，定性登记）

| 风险 | 等级 | 依据 | 缓解 |
|---|---|---|---|
| 版本 <1.0，API 漂移 | 高 | §3.1 release 记录（v0.1.x / v0.2.x） | commit-pin + 升级回归门禁（PoC N-3） |
| 项目公开期仅约 6 个月 | 中 | §3.1 org 创建时间 | 不入主干关键路径（§4） |
| deepsearch 无 LICENSE | 高（法务） | §3.2 HTTP 404 + API null | 禁用该单元（§6-3） |
| 上游单生态主导（华为关联未核实） | 中 | §3.3 二手转述标注 | 口径纪律（§6-5）+ 每季活跃度复测 |
| 文档以中文为主、英文面薄 | 低 | docs 仓 zh/en 目录结构 | 交付 spec 自行补英文面 |

## 4. 推荐与理由

**推荐：CMP-04 保持"预留治理场景组件集成位"，集成主候选 = agent-core（Apache-2.0）+ agent-protocol（MCP/A2A 对接面）；不入主干关键路径，以 M4–M7 之间插槽做平行 PoC。**

推导链（DGA-CORE 未交付，按语义对应登记）：

1. PR-INF-01（复刻即资产）：Apache-2.0 + 企业级定位（多租户 Runtime、Studio）满足"客户可复刻的栈"叙事，与 CMP-04 的 S5 定位一致。
2. R-POL-01/R-POL-02：agent 的工具调用必须经服务端强制权限点——agent-protocol 的 MCP SDK 使 openJiuwen 生态的工具面可接我们的 OPA 工具网关，而不是绕过它。**集成前提 = 所有 agent-core/agent-protocol 工具调用经网关**，此为负面测试项。
3. R-OBS-01：agent-core 具 OTel 出口（提交证据）→ trace 进 OTel 管道，Langfuse 评估工作台可见；Trace ≠ Evidence 边界不变（R-EVID-02）。
4. 风险对冲（8.4 纪律）：项目仅 6 个月、<1.0——因此**只集成协议面与 SDK 面，不让 openJiuwen 的内部状态成为公司唯一状态**（对应 CMP-14 同款纪律：框架内存不承载权威状态）。
5. deepsearch 无 LICENSE：不集成、不复制代码，待上游澄清（升级触发：若 S5 指名要 deepsearch 能力，按 8.5 升级 S5 处理许可证缺口）。

## 5. PoC 计划与对应负面测试清单

PoC（M4 前置，本机）：

1. agent-core pip 安装 + 快速开始样例跑通（验证官方安装路径真实可用，补 §3.4-2 的转述证据）。
2. agent-core OTel 导出 → 本机 OTel collector → Langfuse（服务器阶段）管道联调。
3. agent-protocol MCP SDK 写一个示例工具，挂到 OPA sidecar 网关之后。

负面测试：

| # | 负面测试 | 期望 |
|---|---|---|
| N-1 | agent 绕过网关直连外部 API | 网络策略/egress 白名单阻断；事件入证据（R-POL-01"提示词级不算权限控制"） |
| N-2 | 子 agent 持有的虚拟 key 超父任务预算调用 | LiteLLM 侧限额拒绝（R-POL-02，联动 SEL-05） |
| N-3 | 升级 agent-core 一个 minor 版本后跑既有 PoC | API 破坏性变更被 CI 捕获（验证 <1.0 风险可控性） |
| N-4 | 断网（无 openjiuwen.com/gitcode 依赖）运行 PoC | 全功能本地可用（验证无强制云绑定） |

## 6. 待 S5 裁决点（每点附默认方案）

| # | 裁决点 | 默认方案（先行，待追认） |
|---|---|---|
| 1 | CMP-04 定位说明（第 9 章第 1 项，前置输入） | 维持"治理场景资产、预留集成位"；集成主候选 agent-core；定位与 S5 补充说明一致后再升级为正式集成 |
| 2 | 集成哪个/哪些仓库 | 仅 agent-core + agent-protocol（均 Apache-2.0 且已逐字核 LICENSE）；不集成 deepsearch（无 LICENSE） |
| 3 | deepsearch 无 LICENSE 缺口 | 不使用；若 S5 指名需要，向 S5 呈许可证风险矩阵后裁决（8.4：TOS/许可灰区 agent 不做可否判断） |
| 4 | CC-BY-4.0 文档仓与其余仓库 LICENSE 逐字核对 | 建设期对实际选用的每个仓库补逐字核对并回填本文 |
| 5 | 华为生态关联的表述口径 | 官方口径未核实前，对外/对客户文档不写"华为项目"表述，只写"Apache-2.0 开源项目 openJiuwen"（防二手转述失实） |
| 6 | 里程碑插入点 | M4–M5 之间平行 PoC（不阻塞 M4 OPA 主线）；PoC 通过且 S5 追认后定正式插槽 |

## 7. 回滚与迁移成本

- 回滚面小：集成位为平行 PoC，不进主干关键路径；回滚 = 从流程定义中摘除该执行单元 + 撤销其虚拟 key（R-IR-03 撤销验证）。
- 状态无锁定：按 §4-4 纪律，openJiuwen 内部状态（Studio 配置、runtime 会话）不承载权威状态，权威数据在控制面 DB 与 Git——替换/移除组件不丢治理状态。
- 迁移成本主项 = 工具/技能改写（若从 MCP 迁其他协议）与 prompt/评测资产重放（Eval 定义在 Git，可重放）。
- 版本钉死策略：PoC 期 commit-level pin + 供应商镜像留存，缓解 <1.0 上游漂移；升级按 SEL-04 PoC N-3 回归门禁执行。

---

*引用清单（核实于 2026-09-06）：github.com/openJiuwen-ai（org repos API / commits API / releases API / LICENSE raw ×2）；github.com/openJiuwen-ai/docs（产品简介.md 原文）；openjiuwen.com。转述类（已标注未直接核实）：中国人民大学 SE 办公室新闻、昇腾社区指南。*
