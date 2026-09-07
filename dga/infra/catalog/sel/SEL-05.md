# SEL-05 调研报告：LiteLLM Proxy（开源边界与池账本同步）

- 任务来源：DGA-INFRA 第 8.2 节 SEL-05；CMP-05（推荐主选型，本文核实）
- 调研执行：SEL 轨道执行 agent
- 核实日期：2026-09-06（全部事实当日核实）

## 1. 任务范围与强制约束

- 8.2/SEL-05：虚拟 key / 预算 / 路由的开源可用性（企业功能是否分离）；fallback 链配置；与池账本的数据同步方式。
- R-POL-02/R-POL-03：子任务权限 ≤ 父任务；池路由的虚拟 key 限额落实（每个执行单元独立限额 key）——**虚拟 key + 限额必须在开源版可用**，否则 CMP-05 推荐失效。
- R-POOL-BUDGET：成本熔断；R-POOL-QUOTA：配额账本校准（账本 vs 供应商面板抽查误差 < 阈值，第 7 章）。
- R-SEC-02：池账号凭证明文仅存凭据库，LiteLLM 配置中只允许引用/注入，不落明文于 Git。
- PR-INF-01.e / 8.4：客户可复刻四问。

## 2. 候选集

CMP-05 已推荐 LiteLLM 为主选型，本文核实该推荐；候选集为 LiteLLM 的**版本/部署形态**：

| 候选 | 说明 |
|---|---|
| A | LiteLLM OSS 自托管（MIT，pip/uv 安装 Python 网关） |
| B | LiteLLM OSS 自托管（容器形态） |
| C | LiteLLM Enterprise（同网关 + 企业功能授权，加购） |

对照项（未深研，仅登记存在）：直连各 provider SDK 自研路由层、OpenRouter 等托管网关——与 CMP-05 的 S5 推荐冲突，仅作回滚参照（§7）。

## 3. 评估矩阵

### 3.1 许可证原文结论

来源：[BerriAI/litellm LICENSE](https://github.com/BerriAI/litellm/blob/main/LICENSE)（raw 原文逐字核对，2026-09-06）：

- **MIT License，"Copyright (c) 2023 Berri AI"**。
- 原文关键 carve-out（逐字引）："content under the `enterprise/` directory (if present) is governed instead by the license in `enterprise/LICENSE` — everything else falls under the MIT terms above."
- 结论：仓库主体 MIT；`enterprise/` 目录内容（如存在）单独授权。**开源/企业分界在代码目录级可辨识**——客户复刻时可直接审计自己部署的镜像是否包含 enterprise/ 目录内容。

### 3.2 开源版能力边界（对照官方 enterprise 文档）

来源：[LiteLLM Enterprise 官方页](https://docs.litellm.ai/docs/enterprise) 与 [虚拟 key 文档](https://docs.litellm.ai/docs/proxy/virtual_keys)（均核实 2026-09-06）。

**OSS 已含（官方页原文引）**："an OpenAI-compatible gateway, virtual keys, spend tracking, budgets, fallbacks, and request/response logging"；OSS guardrail 框架含自定义 + Presidio（PII 掩码）；Prometheus 指标；单区域部署。

**Enterprise 独有（官方页清单核实，对 DGA 有影响项加粗）**：

- SSO/SAML（**SSO 对 ≤5 用户免费**，原文："SSO is free for up to 5 users. Beyond that, an enterprise license is required."）、JWT 认证、审计日志（带保留策略）、RBAC、路由级公私控制、IP ACL（CIDR）
- **Key rotations（虚拟 key 文档页原文："This feature requires a LiteLLM Enterprise license."）→ 池账号轮换自动化缺失，须自建（联动 R-SEC-03）**
- Secret managers 集成（AWS KMS/Secrets Manager、Azure、GCP、HashiCorp Vault、CyberArk 等）→ 用 OpenBao 需自建注入管道（联动 SEL-06）
- 多租户组织→团队→项目→key 分层、**tag budgets、model-specific budgets per virtual key、临时预算上调、soft budget email alerts（成本熔断告警面缺失→须自接 OSS webhook）**、programmatic spend reports
- **Team-based log routing（含 Langfuse 路由为 Enterprise 项）→ 池账号日志分流到观测栈须自建**
- 日志导出 GCS/Azure Blob、企业 guardrail 集、品牌定制、请求体大小限制、multi-region 单授权

**对 CMP-05 推荐成立性的判定**：R-POL-03 要求的"虚拟 key + 独立限额"在 OSS（官方页明列 OSS 含 virtual keys/budgets）。fallback 链在 OSS（同句明列）。**推荐成立**；企业版为锦上添花非依赖项。

### 3.3 自托管依赖

来源：[prod 生产最佳实践](https://docs.litellm.ai/docs/proxy/prod)、[db_info](https://docs.litellm.ai/docs/proxy/db_info)（核实 2026-09-06）：

- **PostgreSQL：状态库**（key/预算/团队/spend 日志全在 DB，表清单见 3.4）。
- **Redis：可选，多实例才必需**。原文逐字引："Run Redis (7.0 or newer) as soon as you run more than one proxy instance."；用途：跨实例共享限流计数器、router 状态、响应缓存；高流量（约 1000+ RPS 或 10+ 实例）建议 `use_redis_transaction_buffer: true` 防 spend 写入死锁。
- **本机建设结论：单实例 + PostgreSQL 即可，无 Redis 依赖**（与 BUILD-LOG 环境侦察"无 Docker"兼容：OSS 网关为 Python 包，`uv add litellm` 安装（[docs 首页](https://docs.litellm.ai/docs/)，2026-09-06 核实），Windows 原生 Python 可运行——建设期以 PoC 实测为准）。

### 3.4 与池账本的数据同步面

来源：[db_info 官方页](https://docs.litellm.ai/docs/proxy/db_info)（表清单逐项核实）、[spend_logs_deletion](https://docs.litellm.ai/docs/proxy/spend_logs_deletion)（索引/保留）、[config_settings](https://docs.litellm.ai/docs/proxy/config_settings)（分区），2026-09-06：

| 表 | 用途 | 池账本用途（R-POOL-QUOTA/EVID） |
|---|---|---|
| `LiteLLM_VerificationToken` | "Manages Virtual Keys and their permissions" + key 级预算/限流/spend | **虚拟 key = 逻辑端点↔执行单元绑定的运行时投影**；控制面 DB 为权威源，此表为投影（R-GOV-01） |
| `LiteLLM_SpendLogs` | 全部 API 请求明细（token/spend/时延） | 配额校准原始数据；支撑"账本 vs 供应商面板抽查误差<阈值" |
| `LiteLLM_DailyUserSpend` / DailyTeam/DailyTag/DailyEndUser/DailyAgent 等 | 预聚合日汇总（Usage 页数据源） | 成本熔断（R-POOL-BUDGET）的日粒度输入 |
| `LiteLLM_BudgetTable` | 预算/限流配置（max budget、soft budget、TPM/RPM） | 预算结构体镜像 |
| `LiteLLM_AuditLog` | 配置变更审计（**默认关闭**） | 开启后入证据流（联动 R-POL-05） |

- 字段级权威 schema：仓库 [schema.prisma](https://github.com/BerriAI/litellm/blob/main/schema.prisma)（docs 指认其为字段级来源；`LiteLLM_SpendLogs` 的 `api_key` 存**哈希**而非明文 key——池账本同步时不可反查明文，明文只在凭据库 R-SEC-02）。
- 运维开关：`disable_spend_logs`/`disable_error_logs`；spend 表支持按 day/week/month 分区（config_settings）。
- 同步方式结论：**同库直读（PG）为主通道**——控制面池账本轮询/订阅 `LiteLLM_SpendLogs` + `Daily*` 汇总做校准；反向（账本→LiteLLM）走 Proxy Admin API/DB 写虚拟 key。不引入第三方同步中间件。

### 3.5 客户可复刻四问

1. **能否合法部署？** 能。MIT（LICENSE 原文核实 §3.1），企业/ 目录不打入部署镜像即无授权义务；官方定价页口径"Self-host LiteLLM OSS with no license fee, forever"（搜索结果转述该页存在此句，未逐字核验——登记 §6 补核）。
2. **部署文档与单机路径？** 有。官方 docs proxy 系列 + 快速安装（`uv add litellm` / CLI 运行 / Docker，docs 首页核实）；单机 = 单实例 + Postgres。
3. **强制云绑定？** 无。自托管为完整路径；管理 UI 随 OSS 分发（企业页将 SSO 而非 UI 本身列为付费项）。
4. **复刻缺失项？** 企业功能清单（§3.2）如实转移给客户：key 轮换、SSO>5 人、审计日志保留策略、团队级日志路由、soft budget 告警等需客户自建或采购——写入 PROD-05 交付 spec 的"开源/企业分界"附录。

### 3.6 活跃度与健康度

- 仓库：[github.com/BerriAI/litellm](https://github.com/BerriAI/litellm)（本轮未拉取 star 数/release 数——登记 §6 补核；不凭记忆断言）。
- docs 站活跃（enterprise/virtual_keys/prod/db_info 各页均为现行维护内容，2026-09-06 内容含近期能力如 Redis transaction buffer）。

### 3.7 池抽象 → LiteLLM 配置面映射（设计判断）

DGA-INFRA 第 3 章池对象模型落到 LiteLLM 的投影方式（设计声明，字段以 §3.4 已核表结构为限）：

| 池对象（第 3 章） | LiteLLM 投影 | 权威源方向 |
|---|---|---|
| Provider + Account（credential_ref） | model 配置项（provider+key 注入）；key 明文由 OpenBao 注入环境（SEL-06），不进配置文件/Git | 控制面 DB → 下发 |
| LogicalEndpoint（free-workhorse / paid-judge / t1-only） | 虚拟 key（`LiteLLM_VerificationToken`）+ model group/alias 组合 | 控制面为权威，DB 表为投影 |
| trust_label（T0/T1/T2） | key 元数据标签 + OPA 网关侧强制（key 自身不做信任语义，只做限额） | OPA/控制面 |
| quota_state | `LiteLLM_BudgetTable`（max budget/TPM/RPM）+ `LiteLLM_SpendLogs` 回读校准 | 双向：控制面写预算，LiteLLM 回写消耗 |
| RoutingPolicy / 降级链 | fallback 链 + 路由策略配置（OSS 明列 fallbacks，§3.2） | 控制面下发，Git 存模板（R-GOV-02） |
| health | LiteLLM 侧错误/延迟指标（Prometheus，OSS 明列）→ 池健康度量（R-POOL-EVID） | LiteLLM → 控制面聚合 |

校准闭环（R-POOL-QUOTA）：`LiteLLM_SpendLogs`/`Daily*`（LiteLLM 侧） vs 供应商面板用量（人工/脚本抽查） vs 控制面账本预期——三方核对，误差阈值触发治理异常（第 7 章"配额准确"验收项）。**明文 key 永不出现在任何一方**（spend logs 存哈希，§3.4）。

### 3.8 风险与缺口登记（OSS 边界引出）

| 缺口（OSS 无） | DGA 对应动作 | 依据 |
|---|---|---|
| key rotations | Temporal 工作流自建轮换器 + 撤销验证（R-SEC-03） | §3.2 virtual_keys 页 Enterprise 标注 |
| soft budget email alerts | 熔断告警自接：Daily* 表阈值扫描 → 飞书/S5 决策卡片（R-POOL-BUDGET、R-GOV-04） | §3.2 enterprise 清单 |
| team-based log routing（Langfuse 分流） | 观测路由自建（OTel 层处理，SEL-08） | §3.2 enterprise 清单 |
| RBAC / 审计日志 | 控制面自研权限 + `LiteLLM_AuditLog` 开启兜底（§6-5 默认开启） | §3.2 / §3.4 |

## 4. 推荐与理由

**推荐：候选 A（OSS 自托管，单实例 + PostgreSQL，无 Redis）为本机与初期生产形态；企业版不采购（默认）。**

推导链（DGA-CORE 未交付，语义对应登记）：

1. R-POL-03：虚拟 key + 限额在 OSS 官方明列 → CMP-05 硬约束满足（§3.2 判定）。
2. R-GOV-01/权威源：LiteLLM DB 定位为投影与原始计量层，池账本权威源仍在控制面 DB（第 1 章表）——`LiteLLM_SpendLogs` 是配额校准（R-POOL-QUOTA）的证据原料。
3. PR-INF-02.d：免费层/付费层混合池 = 显式策略——OSS 零许可费与该策略同构；企业功能缺口以"自建 + 登记缺失"处理（PR-INF-01.c 运维成本 agent 化，廉价）。
4. R-SEC-02/03：key 轮换为企业功能 → 轮换器自建（控制面工作流，经 Temporal 编排，runbook + 撤销验证），凭据明文仅经 OpenBao 注入 LiteLLM 环境（联动 SEL-06）。

## 5. PoC 计划与对应负面测试清单

PoC（M2 池 v0 前置）：

1. Windows 本机 `uv add litellm` + PG 启动代理，接 ≥2 个模拟 provider 端点，配 fallback 链与虚拟 key。
2. 同库直读 `LiteLLM_SpendLogs`/`Daily*`，跑通控制面配额校准批处理。
3. 容器形态（B）留作服务器阶段对照（性能基线同机对比）。

负面测试：

| # | 负面测试 | 期望 |
|---|---|---|
| N-1 | T0 端点（虚拟 key 标签）请求敏感任务 | 策略层拒绝，非提示词级（联动 OPA；第 7 章"数据红线"验收） |
| N-2 | 子执行单元 key 超budget 调用 | 超限拒绝，父任务 key 不受影响（R-POL-02"拆十个 agent 不获得十倍预算"） |
| N-3 | 主端点注入 429/宕机 | fallback 链切换，闭环不中断，事件落证据（第 7 章"池故障转移"） |
| N-4 | 伪造 spend：绕过代理直调 provider | 校准抽查发现账本缺口→治理异常登记（R-EVID-05 证据缺失区分登记） |

## 6. 待 S5 裁决点（每点附默认方案）

| # | 裁决点 | 默认方案（先行，待追认） |
|---|---|---|
| 1 | 企业版是否采购 | 不采购；缺失项自建清单已登记（key 轮换器/熔断告警/日志路由），每季度重估 |
| 2 | LiteLLM DB 落位 | 与控制面 PG 同实例、独立数据库（校准查询免跨网；控制面权威表与投影表物理分库防误写） |
| 3 | 定价页"forever free"口径逐字补核 + 仓库活跃度指标补核 | 建设期各做一次并回填本文（本轮未逐字核验，见 §3.5/§3.6） |
| 4 | Windows 原生跑代理的形态确认 | 本机 PoC 以 Python 原生进程为准；失败则 dev 阶段降级为容器（需 Docker 时按环境阻塞判定升级） |
| 5 | `LiteLLM_AuditLog` 开关 | 生产开启（联动 R-POL-05 证据流）；本机阶段可关 |

## 7. 回滚与迁移成本

- 回滚路径：代理层整体替换 = 自研薄路由（CMP-05 禁止自研通用网关，仅作灾难回滚）或托管网关（OpenRouter 类）。虚拟 key 语义需自建表投影，迁移脚本量级：中。
- 数据资产：`LiteLLM_SpendLogs` 为计量原始数据，回滚前先全量导出到证据存储（R-EVID-03 对象锁定），保证配额校准历史可审计。
- 降级运行：代理宕机时降级链 = 直连 provider 的白名单端点（R-POOL-DEGRADE），须预登记并纳入 M8 故障演练（第 7 章）。
- 升级策略：OSS 迭代快，pin 版本 + schema migration 演练纳入常规 runbook（`schema.prisma` 变更 = 同步面变更，需控制面适配）。

---

*引用清单（核实于 2026-09-06）：github.com/BerriAI/litellm（LICENSE raw 逐字）；docs.litellm.ai（/docs/enterprise、/docs/proxy/virtual_keys、/docs/proxy/prod、/docs/proxy/db_info、/docs/proxy/spend_logs_deletion、/docs/proxy/config_settings、/docs/ 首页）；schema.prisma 位置经 docs 指认。*
