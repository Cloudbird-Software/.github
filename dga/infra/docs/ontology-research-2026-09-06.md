# Palantir 本体论选型研究（S5 交付 2026-09-06，归档保存）

> 结论先行：目前没有任何一个开源项目是 Palantir Ontology 的完整平替——数据+逻辑+行动+安全四位一体、受治理写回、决策谱系，这四样 Palantir 锁得很死，开源世界也还没有人完整拼出来。但这不等于要从零造。正确的构造是组合式栈：**LinkML 做声明层，TerminusDB 做运行时查询层（带 Git-for-data 能力），动作层（Action Types）与治理层直接复用 DGA-INFRA 已确认的 Temporal + MCP 网关 + OPA**——动词与治理是判定资产本体，开源没有现成物，也不该有。
>
> S5 裁决（2026-09-06 会话）：采纳本方案（SEL-13 落地验证）；基础设施选型与本体论建设一开始就按企业级要求全量建设——"自己环境下用企业级方法跑出来的证据，才是未来向企业级环境迁移最好的资产"。先本机建设调试，后部署服务器。

## 一、开源现状盘点（判据：Ontology = Semantic + Kinetic + Dynamic 三层 + 贯穿安全治理）

### 1.1 想做完整复刻的（均不可生产依赖）

| 项目 | 许可证 | 现状 | 定位 |
|---|---|---|---|
| OpenFoundry（DioCrafts） | AGPL-3.0 | 12–193 stars、无正式 release、社区基本不存在 | 架构参考价值极高（33 服务边界/Protobuf 契约/审计管道全画清楚），生产依赖价值为零 |
| Semantica | Python 系，GitHub Trending | 活跃度真实 | 面向 agent 的知识图谱+溯源+决策链，偏上下文增强，非完整运营型 Ontology |
| TIS Ontology × ChatBI | 开源 | 2026 新出 | 声称完整落地（对象建模/链接/动作/对话查询），完整度需实测 |

### 1.2 分层零件（真正可用的开源生态）

| Palantir 的层 | 开源候选 | 能力 | 边界 |
|---|---|---|---|
| 名词·模式声明 | LinkML | YAML 建模、编译到 OWL/RDF/JSON Schema/SQL DDL/GraphQL/Python dataclass、SchemaSheets、FAIR 默认、30+ 生成器 | 声明层完胜，但不存储不查询 |
| 名词·强类型运行时（闭世界） | TypeDB 3.x（MPL-2.0，Rust） | 实体/关系/属性一等类型、继承、n-ary 关系、写入时强制约束 | 单服务器部署，无分布式 |
| 名词·版本化文档图运行时 | TerminusDB v12（Apache 2.0） | 文档+图二合一、Git-for-data（branch/diff/merge/clone/time-travel）、ACID、WOQL | 缺"动词"层，版本化数据对上证据留存需求 |
| 名词·虚拟知识图谱 | Ontop（OBDA） | 关系库映射虚拟 RDF KG，不复制数据 | 对应 virtual tables/Native Federation |
| 动词·受治理写回（Action） | **无现成开源原语** | OpenFoundry actions-service 是唯一尝试；其余退化为 CRUD | 判定资产本体所在，开源不提供——护城河本身 |
| 语义层（只读指标口径） | Cube / dbt Semantic Layer / Malloy | 统一数字口径 | Palantir 拒绝把它当 Ontology；缺动词 |
| 治理与谱系 | OPA / Cedar / Apache Atlas | 策略引擎、ABAC/RBAC、血缘 | OPA 已定；OpenFoundry 用 Cedar 值得跟进 |

### 1.3 明确要避开的

- 经典 OWA/RDF/OWL 全家桶（Jena、Protégé、纯 RDF 存储）：开放世界假设+推理引擎，Palantir 明确拒绝，DGA 也应拒绝——闭世界、可判定、写入即验证才符合 [LAW-04] 精神。
- 把"语义层"当 Ontology 卖的产品（Cube、dbt）：只有名词没有动词的栈是废铁（[DER-03]）。
- OpenFoundry 作为生产依赖：AGPL 传染+极端早期。唯一正确用法=当 ARCHITECTURE.md 参考文献读两小时（四边界上下文/Protobuf 契约/审计管道/Cedar 模型/What-if 分支）。

## 二、推荐栈（S5 已采纳）

```
本体论契约层（宪法）  LinkML（YAML in Git，S5 签发）
  ↓ 生成 ↓ JSON Schema · OWL · SQL DDL · TypeScript/Python 类型
本体论运行时层（名词查询 + 动词执行）
  名词侧：TerminusDB v12（主选，文档图/ACID/Git-for-data/WOQL）；TypeDB 3.x（备选，gen-typedb 路径）
  动词侧（自研，复用 DGA-INFRA）：
    Temporal（事务化 Action 编排）· MCP 网关（工具调用治理入口）· OPA（权限谓词强制）
治理与证据层（已有不变）OPA decision log · 对象存储锁定 · 治理度量 · 公示仪表
```

### 2.1 为什么是 LinkML（声明层）

schema-first、模式在 YAML、Git 权威源、S5 签发流——与 R-ONT-01 对齐；它是编译器不是运行时——一份声明多系统投影（飞书表格/控制面 DB/MCP 工具 schema 全部同源生成），落实"允许多种入口，不允许同一字段多个主写者"；许可证宽松（MIT/Apache 系）；FAIR 默认（PROD-06 合规加分）；有 TypeDB 生成器（gen-typedb 已验证路径）。

### 2.2 为什么是 TerminusDB（运行时主选）

决定性理由是版本控制：证据层要求"对象版本+内容摘要+独立写入权限+对象锁定"（R-EVID-03），本体论运行时天然继承同样纪律——不可变 commit 层、time-travel、branch/merge，对象语义历史与校准域历史同库。TypeDB 备选（TypeQL 类型系统/n-ary/写入时约束）；Ontop 不选（虚拟映射适合存量 RDB，控制面是新建无包袱，且 RDF 带 OWA 气质）。

### 2.3 动词层为什么必须自研

[PR-INF-01] + [DER-03] ⇒ Action Type 是判定资产本体，开源没有也不该有。Palantir Actions = 参数校验+前置条件+副作用声明+权限约束+审计日志+可回滚。工程化落点 DGA-INFRA 已全选好：Temporal（saga 执行层）/MCP 网关（暴露层）/OPA（权限层）/证据存储（审计层）。**新增自研量很小：MCP 网关上加 Action Registry**——每个 MCP 工具注册时必须在 LinkML 声明对应 Action Type（输入参数 schema/权限谓词/审计要求/副作用声明），未注册即无调用路径。这个 Registry 本身就是判定资产，可产品化为对 A 类客户的"受治理执行权"输出——Palantir 护城河的开源复刻版。

## 三、落地架构与关键设计决策

1. **声明层与运行时层分离**：LinkML YAML 在 Git（S5 签发流），TerminusDB 与控制面 DB 是运行时投影。本体论权威源永远是 Git，不是任何数据库。
2. **MCP 工具注册与 Action Schema 强制绑定**：参数 schema 必须从 LinkML 生成的 JSON Schema 校验；权限谓词与 Action Type 的 security 字段对应；未注册的工具不存在调用路径（网关直接拒绝）。
3. **飞书字段 = 本体论投影**：多维表格字段映射 LinkML class/slot；SaaS 不可 IaC 部分保留人工步骤+配置快照+读回检查（LinkML 生成 schema 作为读回校验基准）。
4. **本体论版本参与校准域声明**：LinkML schema 的 Git commit hash 作为校准域声明维度；schema 变更 → 新 hash → 校准域变化 → 触发漂移重估工作流。

## 四、工具对比总表

| 维度 | LinkML | TerminusDB | TypeDB 3.x | OpenFoundry | Semantica | TIS Ontology |
|---|---|---|---|---|---|---|
| 定位 | 声明层 | 运行时（文档图 DB） | 运行时（类型化图 DB） | 完整复刻尝试 | Agent 本体增强 | 完整复刻尝试 |
| Action（动词）能力 | 无（声明定义） | 无 | 无 | 有（actions-service） | 部分 | 声称有 |
| 版本控制 | Git 原生 | 内建 Git-for-data | 无 | GitOps（基础设施层） | 无 | 无 |
| 许可证 | MIT/Apache 系 | Apache 2.0 | MPL-2.0 | AGPL-3.0（传染） | 开源 | 开源 |
| 成熟度 | 高（十年 biomedical） | 中高（v12，DFRNT） | 中（3.12） | 极早期 | 新 | 新 |
| 客户可复刻四问 | ✅ | ✅ | ✅（MPL 文件级） | ⚠️ AGPL | ✅ | 待验证 |
| 推荐用法 | 主选声明层 | 主选运行时（名词） | 备选运行时 | 架构参考 | 关注 | 关注验证 |

## 五、SEL-13 本体论工程栈落地验证（任务定义）

a) LinkML 安装与 schemas/ 仓库初始化（linkml-project-copier 模板起步；DGA 全部实体写成 LinkML YAML）
b) 生成器验证（gen-json-schema / gen-sqlddl / gen-python / gen-typedb / gen-doc）——验证与控制面/MCP 网关/飞书映射实际对接
c) TerminusDB v12 部署与 schema 加载（Docker；branch/merge/time-travel 满足证据查询需求验证）
d) MCP 网关的 Action Registry 原型（LinkML Action Type → MCP 工具注册；OPA 谓词绑定；Temporal 事务绑定）
e) OpenFoundry ARCHITECTURE.md 研读报告（四边界上下文/Cedar 模型/审计管道设计模式清单，标注哪些可吸收）
f) 负面测试设计（未注册 MCP 工具被网关拒绝；本体论版本变更触发漂移重估；LinkML schema 与飞书字段不一致报警）

核实要求：LinkML/TerminusDB/TypeDB 当前版本、许可证、活跃度重核；OpenFoundry star 数与社区状态重核；TIS Ontology 实际能力部署验证。

## 六、理论收尾

本体论工程栈的正确姿势不是"采购一个平台"，而是"组装一套生成器+运行时"。开源给了名词（LinkML+TerminusDB），动词与治理是自己的护城河（MCP 网关 Action Registry+OPA+Temporal+证据存储）。LinkML YAML 进 schemas/ 仓库的那一刻，它就是 DGA 理论的机器可读形态——S5 签发流+版本纪律+校准域绑定全部就位。
