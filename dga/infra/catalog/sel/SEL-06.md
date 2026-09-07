# SEL-06 调研报告：凭据库（OpenBao vs HashiCorp Vault）

- 任务来源：DGA-INFRA 第 8.2 节 SEL-06；CMP-06（候选：OpenBao / Vault）
- 调研执行：SEL 轨道执行 agent
- 核实日期：2026-09-06（全部事实当日核实；许可证均为 LICENSE 原文逐字核对）

## 1. 任务范围与强制约束

- R-SEC-02：凭证明文仅存凭据库；控制面/Git/飞书仅存引用。多账号池化（第 3 章）下凭据管理是硬需求（CMP-06 定位）。
- R-SEC-01/R-SEC-03：机器身份（应用身份/OIDC 短期凭证）与池账号凭据轮换 runbook——凭据库须支持机器访问模式。
- 8.1 裁决权分配：凭据体系属 S5 裁决（本体资产类）——本文提供裁决输入，不代替裁决。
- CMP-06 预设疑点：Vault 的 BSL 许可证对"客户复刻"的影响（PR-INF-01.e）——本文 §3.3 逐条款分析。
- 本机建设关键约束（BUILD-LOG 环境侦察）：无 Docker、无 WSL 发行版 → **Windows 原生构建有无 = 硬过滤条件**。

## 2. 候选集

| 候选 | 一句话定位 |
|---|---|
| A | OpenBao（Linux Foundation OpenSSF，Vault 社区分叉，MPL-2.0） |
| B | HashiCorp Vault（IBM 旗下，BUSL-1.1） |
| C（对照） | 云托管 KMS/Secrets Manager（AWS/Azure/GCP）——与 PR-INF-01"客户可复刻栈"冲突，仅作客户环境适配器的落点，不作主选 |

## 3. 评估矩阵

### 3.1 许可证原文结论

**OpenBao** — 来源：[openbao/openbao LICENSE](https://github.com/openbao/openbao/blob/main/LICENSE)（raw 原文逐字核对，2026-09-06）：

> "Mozilla Public License, version 2.0"

- 原文头部保留 "Copyright (c) 2015 HashiCorp, Inc."（分叉继承）+ MPL 2.0 全文。
- 结论：**MPL-2.0，文件级 copyleft**。可合法商用部署、可给客户复刻交付；修改的源文件须开源，专有集成文件可与 MPL 文件分离。对"把栈当产品资产"的复刻路径无附加义务陷阱。

**Vault** — 来源：[hashicorp/vault LICENSE](https://github.com/hashicorp/vault/blob/main/LICENSE)（raw 原文全文逐字核对，2026-09-06）：

- **Business Source License 1.1**（License text copyright (c) 2020 MariaDB Corporation Ab）。
- Licensor：**International Business Machines Corporation (IBM)**；Licensed Work：**Vault Version 1.15.0 or later**（(c) 2024 IBM Corp.）。
- **Additional Use Grant 原文（关键条款）**：允许生产使用，条件是不以 hosted 或 embedded 方式向第三方提供、与 IBM 付费版竞争。"Hosting or using the Licensed Work(s) for internal purposes within an organization is not considered a competitive offering."（组织内部使用不算竞争性产品）
- **Change Date**："Four years from the date the Licensed Work is published"（每个版本单独计）；**Change License**：**MPL 2.0**。
- 非生产使用、复制、修改、再分发均被授予；违约（含超授权的生产使用）→ 当前及所有版本权利**自动终止**。

**BSL 对客户复刻的具体影响（逐场景分析，基于上述原文条款）**：

| 场景 | BSL 判定 | 依据条款 |
|---|---|---|
| 客户在自己组织内部署 Vault 自用 | 允许（生产使用，内部用途非竞争） | "internal purposes within an organization" 条款 |
| DGA 将 Vault **嵌入**收费治理产品卖给客户 | **风险区**：若该产品"significantly overlaps with the capabilities of IBM's paid version(s)"构成 competitive offering → 违约 | "competitive offering"/"Embedded" 定义条款 |
| DGA 自用（公司内部运行治理栈） | 允许 | 同内部使用条款 |
| 等 Change Date 后 | 该版本转 MPL 2.0，恢复完全自由 | Change Date/Change License 条款 |

结论：BSL 不阻止客户"自用复刻"，但给 DGA 的**产品化路径**（池/治理栈未来可能商业化，PR-INF-02.b）埋了条款边界；OpenBao 无此边界。

### 3.2 Windows 原生构建（逐 asset 核实，2026-09-06）

**OpenBao**：GitHub API [openbao/openbao releases/latest](https://github.com/openbao/openbao/releases) 逐资产枚举（2026-09-06）：

- 最新版 **v2.6.2**（发布 2026-08-18）。
- **存在 `openbao_2.6.2_windows_amd64.zip` 与 `openbao_2.6.2_windows_arm64.zip`**（各附 .gpgsig/.sbom.json/.sigstore 签名件）。
- 全平台面：linux(amd64/arm64/armv6/ppc64le/riscv64/s390x + hsm 变体)、darwin(amd64/arm64)、freebsd、netbsd、openbsd、windows。**本机（Windows x64、无 Docker）可直接原生运行**。

**Vault**：[releases.hashicorp.com/vault/](https://releases.hashicorp.com/vault/)（2026-09-06 抓取版本索引 + 2.1.0 子页逐资产）：

- 最新 **2.1.0**（另有 2.1.0+ent / +ent.hsm / +ent.fips1403 变体）。
- **存在 `vault_2.1.0_windows_amd64.zip`**（另有 windows_386、linux、darwin、freebsd）。

结论：**两者均有 Windows 原生官方二进制**——本机建设约束不构成过滤淘汰。

### 3.3 能力对照（以已核实来源为限）

| 维度 | OpenBao | Vault | 来源 |
|---|---|---|---|
| 治理 | Linux Foundation OpenSSF，Sandbox 项目；"open source, community-driven secrets manager and fork of Vault" | IBM（BUSL Licensor） | [openbao.org](https://openbao.org/)（2026-09-06）；Vault LICENSE |
| 存储后端（文档现行清单） | Filesystem / In-Memory / **Integrated Storage (Raft)** / PostgreSQL（四类；建议大多数场景用集成 Raft——"an embedded OpenBao data storage writing to the file system"） | 未在本轮逐页核实 Vault 后端清单（数量多于 OpenBao 为公开常识但**不引用**；登记 §6 补核） | [openbao.org/docs/configuration/storage](https://openbao.org/docs/configuration/storage/)（2026-09-06） |
| 客户端生态兼容 | 官方声明："OpenBao intends to remain API compatible with HashiCorp Vault. This means that most of the existing libraries for Vault should also work with OpenBao."；官方维护 Go client（`github.com/openbao/openbao/api/v2`），社区 VaultCourier（Swift） | 原生 | [openbao.org/docs/api/libraries](https://openbao.org/docs/api/libraries/)（2026-09-06） |
| KV / 机器访问模式 | Vault API 面兼容（上条声明）→ KV secrets engine、AppRole 等 Vault 语义客户端可用（PoC 验证项，§5-N2） | 原生完整 | 同上 + PoC |
| 版本节奏 | v2.6.2 @ 2026-08-18 | 2.1.0（2026-09-06 索引在售） | 各自 release 渠道 |

### 3.4 客户可复刻四问

**OpenBao**：
1. 合法部署？能——MPL-2.0（原文 §3.1），无使用领域限制。
2. 文档/单机起步？有——官方 docs（configuration/storage 等）+ GitHub README；单机 = 单节点 Raft 文件存储（官方建议形态，§3.3）。
3. 强制云绑定？无。二进制全平台自托管（§3.2 资产表）。
4. 复刻缺失项？相对 Vault：部分企业功能与更多云后端（Vault 企业 HSM/FIPS/Replication 类）缺失；文档后端清单短于 Vault（四类 vs 更多，§3.3）；生态兼容声明为"intent"级——极端边缘 API 可能漂移（PoC 验证）。

**Vault**：
1. 合法部署？客户自用可（BSL 内部使用条款）；嵌入 DGA 付费产品则触竞争条款（§3.1 表）。
2. 文档/单机起步？有（developer.hashicorp.com Vault 文档体系；本轮未逐页核，登记补核）。
3. 强制云绑定？无（HCP Vault 为可选云）。
4. 复刻缺失项？OSS 版 vs Vault 企业（+ent）功能分界 = HSM/FIPS/多集群复制等（release 索引 ent 变体旁证）；**商业产品化复用受 BSL 限制**（§3.1）。

### 3.5 运维成本 / TOS / 活跃度速评

- 运维：两者同为单二进制 + 存储后端形态；OpenBao Raft 内嵌存储免除外部 DB 依赖（单机起步最短路径）；unseal/密封管理两者同构。
- TOS：开源自托管无供应商 TOS 灰区；云托管对照项不选。
- 活跃度：OpenBao v2.6.2（2026-08-18）+ 全平台签名资产流水线（sigstore/SBOM）= 活跃维护证据；Vault 2.1.0 现行（企业变体齐全）。

### 3.6 凭据引用与轮换面（设计判断，供 M0 schema 定稿）

凭据引用格式与池账本字段的对应（设计声明，能力边界以 §3.3 已核来源为限）：

| 池对象字段（第 3 章） | 凭据库侧形态 | 纪律 |
|---|---|---|
| `credential_ref` | `openbao://<mount>/<path>#<field>?version=N`（§6-4 默认格式） | 控制面/Git 只存此引用（R-SEC-02） |
| 轮换（R-SEC-03） | 新版本写入（KV-v2 版本化）→ 执行单元重读 → 旧版本 revoke；轮换编排走 Temporal（SEL-02） | 撤销验证步骤强制，PoC N-1 即其演练 |
| 执行单元访问 | 每执行单元独立 token/凭据租约（短 TTL），过期自动失效 | 爆炸半径控制（§7 降级运行） |
| 信任标签联动 | T0 执行单元只解析 T0 凭据路径（路径规范含标签段） | OPA 网关 + 凭据路径双层校验 |
| 池健康/审计 | OpenBao 侧访问审计日志（若该能力在核心许可内——建设期核实，未核实不预断）入证据流 | 联动 R-POL-05 |

版本面事实补充：OpenBao 当前 major 为 v2.x（v2.6.2，§3.2），与 Vault 1.15+ BSL 系的版本线已分叉——客户端兼容声明（§3.3）覆盖的是 API 面，**管理面/CLI 旗标可能存在差异**，PoC 以实际命令为准，不假设逐旗标兼容。

### 3.7 风险矩阵

| 风险 | 等级 | 依据 | 缓解 |
|---|---|---|---|
| OpenBao 单仓维护强度弱于 IBM 系 Vault | 中 | LF Sandbox 定位（§3.3） | 季度活跃度复测；API 兼容留回迁通道（§7） |
| 客户端兼容为 "intent" 声明，非逐 API 保证 | 中 | §3.3 官方原文措辞 | PoC N-2 全链验证；核心链路只用 KV+auth 两面 |
| 本机单节点 Raft 无高可用 | 低（本机阶段） | 单机部署形态 | 服务器阶段转多节点或 PG 后端（§6-2 联动） |
| unseal 人工依赖 | 中 | 手动 unseal 默认（§6-2） | 服务器阶段评估 auto-unseal（KMS 绑定权衡升级 S5） |

## 4. 推荐与理由

**推荐：候选 A（OpenBao）为 CMP-06 默认选型；本机 = windows_amd64 zip + 单节点 Raft；服务器 = 同栈 Linux 化。Vault 保留为"客户指定 HashiCorp 栈"时的适配目标（API 兼容使客户端代码几乎零改）。**

推导链（DGA-CORE 未交付，语义对应登记）：

1. PR-INF-01.a/e（复刻即资产 + 四问硬约束）：MPL-2.0 使"我们怎么跑 = 客户可怎么复刻"无许可条款边界；Vault BSL 在产品化场景留下 §3.1 的风险区——**资产侧优先，选无边界的那个**（PR-INF-01.c 相权原则）。
2. R-SEC-01/03：机器访问（AppRole 等 Vault API 语义）+ 轮换 runbook 在 OpenBao 上按 API 兼容面实现；轮换编排走 Temporal（联动 SEL-02/SEL-05）。
3. 本机约束（BUILD-LOG 阻塞判定 B 同构逻辑）：无 Docker → OpenBao windows_amd64 原生 zip 是唯一零依赖起步路径，已逐 asset 核实存在（§3.2）。
4. 风险对冲：OpenBao 由 LF/OpenSSF 治理、多公司赞助（GitLab/Proton 等，openbao.org Supporters 节），非单厂商分叉；若 OpenBao 演进失速，Vault 客户端生态兼容声明提供了回迁通道（§7）。

## 5. PoC 计划与对应负面测试清单

PoC（M2 池 v0 前置，本机 Windows）：

1. 解包 `openbao_2.6.2_windows_amd64.zip`，单节点 `-dev` 与 Raft 文件存储两模式起服，KV-v2 写读。
2. 用 Python `hvac`（Vault 客户端）连 OpenBao 完成 KV 读写（验证 API 兼容声明的实际可用性）。
3. 控制面接"凭据引用"模式：DB 只存 `openbao://path#field` 引用，注入经环境变量/临时 token（R-SEC-02）。

负面测试：

| # | 负面测试 | 期望 |
|---|---|---|
| N-1 | 撤销执行单元 token 后旧 token 复用 | 403 拒绝；撤销验证入 runbook（R-SEC-03"撤销验证"） |
| N-2 | hvac 走 AppRole 登录 + KV 读写全链 | 成功；失败即触发兼容性风险升级（§3.4-4） |
| N-3 | 控制面/执行单元试图直读凭据明文路径 | 仅凭引用可解析；明文路径无控制面权限（R-SEC-02 红线测试） |
| N-4 | 泄漏演练：假凭据写入 Git 提交 | 密钥扫描拦截 + 轮换工作流触发（联动 M8"撤权"演练） |

## 6. 待 S5 裁决点（每点附默认方案）

| # | 裁决点 | 默认方案（先行，待追认） |
|---|---|---|
| 1 | CMP-06 终裁：OpenBao vs Vault | **OpenBao**（MPL-2.0 无产品化边界；BSL 风险区见 §3.1） |
| 2 | 本机 unseal/密封模式 | 单节点 Raft + 手动 unseal（本机调试期）；生产 seal 方式（auto-unseal 需 KMS——云绑定权衡）服务器阶段另行裁决，登记依赖 |
| 3 | Vault 文档/后端清单补核 | 建设期对 developer.hashicorp.com storage 后端页与 OSS/企业功能分界做逐页核实并回填本文（本轮刻意未引用未核实清单） |
| 4 | 凭据引用格式定稿 | `openbao://<mount>/<path>#<field>` + 版本参数；写入 schemas 仓库 M0 |
| 5 | 客户环境适配（客户自带 Vault/KMS 时） | 通过 API 兼容走同一客户端；差异登记为适配器用例，不改变主选型 |

## 7. 回滚与迁移成本

- OpenBao → Vault：API 兼容（官方 intent 声明）→ 客户端改动近零；数据迁移 = 存储 后端快照迁移 + seal 参数重建；成本：低-中。反向同理。
- OpenBao/Raft → OpenBao/PostgreSQL：存储后端切换需快照恢复流程（Raft 快照 → PG 后端恢复），官方提供 snapshot 工具链（PoC 验证项，未列入负面测试即不承诺）。
- 降级运行：凭据库宕机 → 已注入凭据的执行单元继续运行至 token 到期（短 TTL 设计控制爆炸半径）；新凭据签发停止并触发 R-GOV-07 只读/排队模式。
- 迁移纪律（R-IR-03）：任何凭据库切换 = 影子运行 + 单写切换 + 旧库撤权验证（旧 token 全撤销后旧入口不可再写）。

---

*引用清单（核实于 2026-09-06）：github.com/openbao/openbao（LICENSE raw 逐字 + releases/latest API 逐资产）；github.com/hashicorp/vault（LICENSE raw 全文逐字）；releases.hashicorp.com/vault/（索引 + 2.1.0 子页逐资产）；openbao.org（首页、/docs/configuration/storage/、/docs/api/libraries/）。*
