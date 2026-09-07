# SEL-10 调研报告：IaC 落地（OpenTofu 现状 · 本机阶段范围界定 · SaaS 快照+读回方案）

- 任务来源：DGA-INFRA 8.2 SEL-10；CMP-12（OpenTofu，已定；"已有可靠 IaC 则不强行替换"）；第 4 章（治理配置仓库结构 + "云资源经 OpenTofu 管理；SaaS 中无法 API 化的配置保留人工步骤 + 配置快照 + 读回检查"）
- 核实日期：2026-09-06/07（许可证均 LICENSE 原文逐字核对；版本/资产取撰写时 latest）

## 1. 任务范围与强制约束

- 第 4 章边界原文："云资源经 OpenTofu 管理；SaaS 中无法 API 化的配置保留人工步骤 + 配置快照 + 读回检查。配置即代码的目标是**可重建、可核对，不宣称全自动**。"——本报告的全部范围界定以此为纲。
- R-CFG-01：治理配置仓库结构；PR-INF-01.b：IaC/runbook=可交付 spec 工件（复利资产）。
- PR-INF-01.e：客户可复刻四问为硬约束——IaC 引擎的许可证边界直接影响"客户可复刻"。
- R-SEC-02：state 文件含敏感值时的存储纪律（不得入 Git）。
- 本机约束：Windows x64、无 Docker；本机阶段无云资源（S5 指令"先都在本机建设和调试"）。

## 2. 候选集

| 候选 | 一句话定位 |
|---|---|
| A | OpenTofu（Terraform 社区分叉，MPL-2.0，Linux Foundation 治理生态） |
| B | Terraform（IBM 旗下，BUSL-1.1） |
| C | 无引擎脚本化（幂等 shell 脚本 + seed SQL，本机现状的延伸）——CMP-12 "已有可靠 IaC 则不强行替换"条款的对照物 |

## 3. 评估矩阵

### 3.1 许可证原文结论

**OpenTofu** — 来源：[opentofu/opentofu LICENSE](https://raw.githubusercontent.com/opentofu/opentofu/main/LICENSE)（raw 逐字核对，2026-09-07）：

> "Copyright (c) The OpenTofu Authors / Copyright (c) 2014 HashiCorp, Inc. / **Mozilla Public License, version 2.0**"

- 结论：**MPL-2.0，文件级 copyleft**。可合法商用部署与客户复刻交付；修改的源文件须开源、专有集成文件可分离；对"把栈当产品资产"的复刻路径无附加义务陷阱（与 SEL-06 OpenBao 同款许可证形制）。

**Terraform** — 来源：[hashicorp/terraform LICENSE](https://raw.githubusercontent.com/hashicorp/terraform/main/LICENSE)（raw 逐字核对，2026-09-07）：

- **Business Source License 1.1**（License text copyright (c) 2020 MariaDB Corporation Ab）。
- Licensor：**International Business Machines Corporation (IBM)**；Licensed Work：**Terraform Version 1.6.0 or later**（(c) 2024 IBM Corp.）。
- Additional Use Grant 原文（关键句）："You may make production use of the Licensed Work, provided Your use does not include **offering the Licensed Work to third parties on a hosted or embedded basis in order to compete with** IBM Corp.'s paid version(s)…"；"A 'competitive offering' is a Product that is offered to third parties **on a paid basis**… that significantly overlaps with the capabilities of IBM Corp.'s paid version(s)…"
- Change Date/Change License 原文（L43-44）："Four years from the date the Licensed Work is published." / "**MPL 2.0**"。
- 客户复刻影响（逐场景，与 SEL-06 Vault BSL 分析同构）：客户自用部署=允许（非竞争、内部使用）；**DGA 将其嵌入收费治理产品或以托管方式卖给客户=竞争条款风险区**；等每版本 4 年期满转 MPL 2.0 后恢复完全自由。

### 3.2 Windows 可用性（逐 asset 核实，2026-09-07）

- OpenTofu releases/latest：**v1.12.6**（published 2026-08-19）。Windows 资产共 16 件，含 **`tofu_1.12.6_windows_amd64.zip`（35,467,196 B）**，且附 `.sig`/`.pem`/`.gpgsig` 全套签名件（cosign/GPG 双通道）；另有 windows_386、linux、darwin、freebsd 等全平台面。**本机可直接原生运行，无 Docker 依赖。**
- Terraform：本轮未逐 asset 核实其 releases（主判据为许可证差异；登记 §6 补核）。

### 3.3 OpenTofu Registry 现状（2026-09-07 实测）

- 服务在线：`registry.opentofu.org` HTTP 302→200；服务发现端点 `/.well-known/terraform.json` 实测返回：`{"modules.v1": "/v1/modules/", "providers.v1": "/v1/providers/"}`——标准 Terraform Registry API 协议。
- 运营模式：[opentofu/registry](https://github.com/opentofu/registry)（408 stars，Apache-2.0，**pushed 2026-09-06 即当日**）："This repository is home to the metadata that drives the provider and module registry… **Thanks to Cloudflare for sponsoring** a Business plan to host the registry on!"——社区运营的元数据聚合（提交经 issue 模板人工审核），非 HashiCorp 官方 registry 的镜像。
- 判读：registry 可用且活跃，但 **provider 覆盖是逐个事实问题**——本项目将用到的 provider（如 Backblaze B2 的 S3 兼容 backend/provider）在服务器阶段 PoC 时逐个核实可得性，不在本报告预断（8.4 纪律）。

### 3.4 能力/成本/集成/活跃度速评

| 维度 | OpenTofu | Terraform | 脚本化（现状） |
|---|---|---|---|
| 许可证 | MPL-2.0（原文 §3.1） | BUSL-1.1（原文 §3.1） | 自有代码无许可边界 |
| Windows 原生 | ✅ v1.12.6 zip+签名（§3.2） | （未核实，登记） | ✅（已在跑） |
| 生态 | TF Registry API 协议兼容；社区 registry 当日活跃（§3.3） | 原生 registry+最全 provider 矩阵 | 零依赖、零漂移检测 |
| 漂移核对 | plan 检出真实状态 vs 声明 | 同 | 无（全靠自查） |
| 客户复刻四问 | ①合法 ②官方 docs+单二进制起步 ③无云绑定 ④无企业分界 | ①自用可/嵌入付费产品受限 ②有 ③无强制 ④OSS vs +ent 分界另核 | ①合法 ②无文档资产 ③无 ④无（但也无资产可交付） |
| 活跃度 | v1.12.6@2026-08-19；registry repo 当日 push | 未逐项核（登记） | — |

## 4. 推荐与理由

**推荐：CMP-12 维持 OpenTofu 为服务器阶段云资源 IaC 引擎；本机阶段 IaC 范围界定为"三层可重建性"，本机层不引入 tofu。**

1. **许可证资产侧**（PR-INF-01.c 相权）：MPL-2.0 vs BUSL 的差异不在当下自用（两者都允许），在产品化边界（§3.1 风险区）——凡"客户可复刻的栈"一律取无边界者，与 SEL-06 同构裁决。
2. **本机阶段 IaC 范围界定（第 4 章"可重建、可核对"的本机形态）**——分层：

| 层 | 对象 | 本机"IaC 等价物"（已在位，BUILD-LOG 证据） | 服务器阶段 |
|---|---|---|---|
| L1 组件层 | OPA/Temporal/OpenBao/PG/LiteLLM 等本机服务 | `services/` 幂等脚本组（每组件 start/stop/health，幂等实测"start→stop→stop→start"）+ `services/README.md` 汇总表 | systemd/部署清单 + **OpenTofu 接管云侧计算资源** |
| L2 数据层 | 控制面 DB/池账本 schema+种子 | `catalog/sel/SEL-01-ddl-patch.sql` + `pools/ledger.sql`（幂等 DDL+种子）+ initdb 流程 | 同脚本化+迁移工具（SQL 为主，不进 tofu） |
| L3 云资源层 | 对象存储桶（SEL-07 主选 B2：版本化+对象锁定）、服务器、DNS | **不存在**（本机无云资源，不造无对象之 IaC） | **OpenTofu 唯一接管层**：`gov-infra-repo/infra/`（或独立 infra 仓）HCL+lock 文件 |

   判据：第 4 章"可重建、可核对，不宣称全自动"⇒本机层的幂等脚本+SQL 已满足可重建（重建演练=BUILD-LOG 各 HEALTH.txt 可复跑），引入 tofu 反而加一层无对象的状态文件；云资源层天然是 tofu 语义（声明式+漂移检测）。**本机层不强行替换 = CMP-12 条款原文适用。**
3. **SaaS 层（第 4 章"人工步骤+配置快照+读回检查"的方案设计）**——以飞书为例（CMP-15：非生产运行时；R-GOV-01：飞书非权威源）：

- **快照**：飞书应用凭据就位后（connectors/feishu/README.md 前置条件 1），定期拉取多维表格 schema（字段名/类型/选项/视图）与审批流程定义 → JSON 快照入 Git `connectors/feishu/snapshots/`（人工步骤的"已声明状态"，等价 IaC 的期望态文件）。
- **读回校验基准=LinkML schema**：字段映射表已在 `connectors/feishu/README.md`（W1 闭环登记→`POST /closures` 逐字段：LinkML 槽位 ↔ 飞书表格列 ↔ 目标表.列；W2/W3/W4 同构）。读回检查=飞书 API 实拉 bitable 字段清单 → 与"LinkML 生成物导出的期望投影"比对 → 不一致即报警。这正是本体论轨道负面测试③（"LinkML schema 与飞书字段不一致报警"）的工程化落点：**期望态的权威源是 schemas/dga-ontology.yaml（Git），不是飞书侧**——读回是核对，不是反向同步（R-GOV-01 单主写者不破）。
- **频率与通道**：凭据未就位前仅人工核对（诚实边界，connectors/feishu/README.md 自述"占位件"）；M6+ 定时读回，报警入控制面异常登记 + W3 S5 队列投影。
- 该三件套（人工步骤显式化+快照入 Git+读回报警）即为第 4 章 SaaS 条款的可执行定义，同样适用于 Chatwoot/GitHub 设置等一切 SaaS 配置面。

4. **候选 C 的定位**：不是候选 A 的替代，而是**本机层的既成事实**（L1/L2 层）；tofu 引入后脚本层保留（组件进程管理非云资源），两者边界按上表 L1/L3 分层——"已有可靠 IaC 等价物则不强行替换"的忠实执行。

## 5. PoC 计划与对应负面测试清单

PoC 绑定**服务器阶段**（本机无云资源，本机阶段无 PoC——诚实登记，不做 mock 自欺）：

1. 安装 `tofu_1.12.6_windows_amd64.zip`（或服务器 Linux 版），`tofu init` 指向 B2 的 S3 兼容 backend（**可得性与参数逐项核实**，§3.3 判据）。
2. 声明一个真实最小资源：B2 桶 + versioning + object-lock configuration（SEL-07 语义）→ `plan`/`apply`/`destroy` 全周期，state 存 backend、不入 Git（R-SEC-02）。
3. provider 版本锁定：`required_providers` 精确版本 + `.terraform.lock.hcl` 入 Git。

| # | 负面测试 | 期望 |
|---|---|---|
| N-1 | apply 后在 B2 控制台手工改桶配置 → `plan` | 检出 drift（"读回检查"思想在云资源层的原生形态） |
| N-2 | 无凭据/错误凭据 `apply` | 拒绝且无部分变更 |
| N-3 | state 文件误提交 Git 演练 | 密钥扫描拦截+轮换流程（联动 M8 撤权演练；state 含敏感值=纪律红线） |
| N-4 | 删除远端 state 后 `plan` | 全量"新建"视图可见——验证 state 不是权威源、真实基础设施才是（对照第 1 章权威源纪律） |
| N-5 | （SaaS 层同构）改飞书表格字段名不更新映射 | 读回校验报警入控制面（M6+ 凭据就位后） |

## 6. 待 S5 裁决点（每点附默认方案）

| # | 裁决点 | 默认方案（先行，待追认） |
|---|---|---|
| 1 | IaC 引擎终裁：OpenTofu vs Terraform | **OpenTofu**（CMP-12 已定；MPL-2.0 无产品化边界，BUSL 风险区 §3.1；若客户指定 HashiCorp 栈再评估 Terraform 适配） |
| 2 | tofu 接管边界清单 | **仅 L3 云资源**（B2 桶/服务器/DNS）；L1 组件层=systemd+脚本、L2 数据层=SQL、SaaS=快照+读回（§4-2 表）；边界外资源进 tofu 须逐项增补裁决 |
| 3 | tofu backend 选型 | 首选 **B2 经 S3 兼容 backend**（与 SEL-07 主选同源，PoC 核实）；备选本地加密 state 暂存（过渡期，不宣称生产形态） |
| 4 | SaaS 快照读回的频率与报警通道 | 手动触发起步 → M6+ 定时（凭据就位为前提）；报警=控制面异常登记+W3 投影（R-GOV-07 安全默认） |
| 5 | Terraform 侧未核项补核时点 | 若/当客户环境指定 Terraform 时，对其 releases 的 Windows/企业分界逐 asset 补核并回填 §3.2/§3.4（当前不引用未核实信息） |
| 6 | OpenTofu↔Terraform 配置/state 兼容度 | 本轮**不做未核实断言**（1.6+/1.12 的互相兼容性各有版本边界，须 PoC 实测）；默认按"不可无痛互换"规划，避免锁定幻觉 |

## 7. 回滚与迁移成本

- 引擎互换（tofu↔terraform）：HCL 语法层大体同源，但**配置/state 兼容性未核实**（§6-6）——任何互换按 R-IR-03 走影子运行（同资源双引擎 plan 比对）+单写切换；成本：中-高（因兼容性未证实），故裁决点 1 尽量不翻。
- 本机→服务器：无引擎迁移问题（本机从未有 state）；L1/L2 脚本层整体平移复用。
- 云资源层回滚：tofu state 即回收清单，`destroy` 或 state 条目移除即解管；危险面在 object-lock 资源（WORM 不可逆）——apply 前置检查进 runbook。
- 降级运行：tofu/registry 不可用不影响存量资源运行（声明式引擎只在变更时需要），新资源变更冻结并登记——与 R-GOV-07 只读模式语义一致。

---

*引用清单（核实于 2026-09-06/07）：raw.githubusercontent.com/opentofu/opentofu/main/LICENSE（MPL-2.0 逐字）；api.github.com/repos/opentofu/opentofu/releases/latest（v1.12.6 Windows 资产逐枚举）；raw.githubusercontent.com/hashicorp/terraform/main/LICENSE（BUSL-1.1 全文含 Additional Use Grant/Change Date/Change License 逐字）；registry.opentofu.org（/.well-known/terraform.json 实测）；api.github.com/repos/opentofu/registry + raw README（运营模式）；本机 services/、pools/ledger.sql、connectors/feishu/README.md（现状与映射表）。*
