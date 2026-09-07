# S5 待裁决项 · 默认方案先行登记（DGA-INFRA 第 9 章）

> 纪律依据：DGA-INFRA 8.3 第 6 节"待 S5 裁决点（显式列出，每点附默认方案）"。
> 状态规则：owner 晨起逐项追认或改判；**改判即触发对应构建件的重估**（登记于 BUILD-LOG）。
> 生效原则：默认方案仅约束本机建设期行为，不构成对外承诺。

| # | 待裁决项 | 夜间默认方案 | 影响面 |
|---|---|---|---|
| 1 | OpenJiuwen 定位说明（SEL-04 前置） | SEL-04 先做事实调研（现状/许可证/活跃度/集成点），定位与集成方案待 S5 补充说明后定；架构预留治理场景集成位 | CMP-04 插桩位 |
| 2 | TOS 灰区账号池接受范围 | 本机建设期不接入任何真实灰区账号；池 schema 的 tos_risk 字段与 T0 强制标签先行；灰区判定一律升级 | R-POOL-COMPLIANCE |
| 3 | "内部低敏任务"界定（T0 白名单） | 默认定义：不含客户数据、不含凭据、不含判定资产答案层、不含个人信息的内部工件（schema/synthetic/公开语料） | R-POOL-TRUST/DATA |
| 4 | 判定仪器端点等级下限 | 采纳 INFRA 建议默认：eval runner ≥ T1；客户敏感判定 T2 | R-POOL-CALIB |
| 5 | 全司成本熔断阈值（日/月） | 本机建设期默认禁用全局熔断（本地端点零边际成本）；阈值结构体已实现，值置 null=未定，S5 填数即生效 | R-POOL-BUDGET |
| 6 | 证据对象锁定保留期 | 默认无限期+锁定（证据资产不设过期）；S5 可改 | R-EVID-03 |
| 7 | Temporal 后端选型 | 本机=Temporal dev server（内嵌存储，官方开发形态）；生产后端待 SEL-02 报告后 S5 定（倾向单库 Postgres） | CMP-02 |
| 8 | 池抽象是否立项对外产品 | 不立项；SEL-12 仅预研登记 | CMP/产品面 |

**追加登记（建设期发现，非第 9 章原项）**：

| # | 事项 | 处置 |
|---|---|---|
| A | DGA-CORE v1.1-A 原文未交付（INFRA 引用的 LAW/RULE/DER 编号体系来源） | 按 human v1.1 语义对应执行，编号映射表登记；CORE 交付后回链校对 |
| B | TerminusDB/TypeDB 无 Windows 原生构建，本机无 Docker/WSL 发行版 | 名词运行时本机以 PostgreSQL + 适配器接口（OntologyRuntime trait）先行；TerminusDB 落位=服务器部署阶段首批动作；LinkML 生成物不受影响 |
