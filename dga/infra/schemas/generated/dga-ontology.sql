-- # Class: SecurityMark Description: Security 层安全标记混入（human v1.1 §5.2 第五层：贯穿 Object/Link/Action/Function 四层的信任标记与权限谓词）。作为 mixin 挂接到关键类：携带 trust_level/data_class/ boundary 三标记。为什么是独立层而非散落注解：安全策略需要独立演进，散落的标记 不可审计——"这个操作曾被允许吗"需要统一裁决点（OPA 层）回答；本 mixin 只保证 字段在位，路由/调用谓词的强制在 OPA 层（M0 诚实边界）。
--     * Slot: id
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
-- # Class: Person Description: 具名的人（责任承载者）。责任守恒律（human v1.1 §1.4）：自动化搬运工作量但不搬运 责任；责任只能在具名的人之间转移，不能被系统吸收、不能被 agent 承载。 本类是 AccountabilityLink.responsible_person 的唯一合法目标类型—— agent、模型组合均不可充当责任锚点（R-GOV-03 负面测锚点的类型学根据）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: full_name Description: 具名责任人的真实姓名（责任守恒律：责任只能在具名的人之间转移）。
--     * Slot: org_role Description: 组织内职能（如 S5 所有者、规格所有者、裁决者——human v1.1 §3.4 人的岗位收敛形态）。
--     * Slot: contact_channel Description: 可达渠道（升级路径的终点，human v1.1 §3.4 汇报关系拆解为证据流+升级路径）。
-- # Class: Intent Description: 意图（六元组分量一；human v1.1 §5.3 映射：Intent → Object 闭环类型+挂接责任人的关系）。 决策前提的最顶层声明。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: statement Description: 意图声明——闭环存在的原因（没有意图的闭环是僵尸流程，human v1.1 §2.1）。
--     * Slot: closure_type Description: 闭环类型（客服/开发/资源调度等；类型清单属实例层）。
--     * Slot: desired_outcome Description: 期望产物与判定标准（对齐"规格层"声明，human v1.1 §3.1）。
--     * Slot: holder Description: 意图持有者（具名的人）。
--     * Slot: source_ref Description: 来源引用（权威源=飞书的需求草稿/业务讨论，DGA-INFRA 第 1 章权威源表）。
-- # Class: ContextAsset Description: 上下文资产（六元组分量二；human v1.1 §5.3 映射：Context → Object 上下文资产+ 校准域实体）。行动的决策前提——有限理性公理的直接落点（§1.1 推论：控制决策 前提即控制行为）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: asset_type Description: 知识形态（规格/记忆/负结果/能力前沿，human v1.1 §3.2）。
--     * Slot: uri Description: 资产定位（Git 路径/对象存储 URI 等）。
--     * Slot: version Description: 资产版本。
--     * Slot: expiry_condition Description: 过期条件（负结果与判例的半衰期，human v1.1 §3.2/§4.4：当时模型版本、当时能力 边界；条件变化触发重估）。
--     * Slot: authority_source Description: 该资产的权威源（R-GOV-01 关键字段唯一权威源）。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
--     * Slot: ClosureUnit_id Description: Autocreated FK slot
-- # Class: CapabilityEntity Description: 能力实体（六元组分量三；human v1.1 §5.3 映射：Capability → Object 能力实体）。 执行的手段：agent、工具、模型、流程引擎的组合体。注意：能力实体可承载执行权， 但不可承载责任（责任守恒律，human v1.1 §1.4 推论二）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: executor_type Description: 执行体类型（agent/工具/模型/流程引擎）。
--     * Slot: endpoint_ref Description: 接入的逻辑端点（LogicalEndpoint id，EPL-xxxx）。
--     * Slot: capability_version Description: 能力版本（换模型不换结构——角色槽填充物的版本记录）。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
-- # Class: EvidenceEntity Description: 证据实体（六元组分量五；human v1.1 §5.3 映射：Evidence → Object 证据实体）。 行动可被外部判定的记录——缺证据的闭环叫赌博（human v1.1 §2.1）。 判定类证据必须可溯源：判定器模型+版本+校准域 ID（R-EVID-04）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: evidence_type Description: 证据契约类型（执行收据/验收判定/签发记录/校准资产/策略判定记录，R-EVID-01）。
--     * Slot: content_digest Description: 内容摘要（R-EVID-03：对象版本+内容摘要+独立写入权限+对象锁定）。
--     * Slot: object_version Description: 对象存储版本号。
--     * Slot: storage_uri Description: 证据存储定位（权威源=证据存储，DGA-INFRA 第 1 章权威源表）。
--     * Slot: object_locked Description: 是否对象锁定（WORM）。防篡改证明"记录未被改"，不证明"记录为真"（R-EVID-03）。
--     * Slot: trace_ref Description: 关联 OTel trace。Trace ≠ Evidence（R-EVID-02）：遥测不构成证据，仅提供线索。
--     * Slot: judge_model Description: 判定器模型（R-EVID-04：判定证据必须含判定器模型）。
--     * Slot: judge_version Description: 判定器版本（R-EVID-04）。
--     * Slot: calibration_domain_ref Description: 校准域 ID（R-EVID-04/R-POOL-CALIB：判定溯源三要件之三）。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
--     * Slot: ClosureUnit_id Description: Autocreated FK slot
-- # Class: CalibrationDomain Description: 校准域（DGA-INFRA 3.8 R-POOL-CALIB 与 R-EVID-04 的锚点类）。 每份 eval 校准必须声明其校准域：覆盖的模型集合（池组成快照）+ Spec/Harness 版本 + 观察窗口 + 本体版本引用。池组成变化 ⇒ 触发相关闭环的漂移重估工作流—— 不是禁止漂移，而是把漂移纳入治理。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: spec_version Description: 校准时依据的 Spec 版本。
--     * Slot: harness_version Description: 校准时依据的 Harness 版本。
--     * Slot: observation_window_start Description: 观察窗口起点。
--     * Slot: observation_window_end Description: 观察窗口终点。
--     * Slot: ontology_commit Description: 本体 schema 的 Git commit（human v1.1 §5.7 第三触发线：本体漂移—— 对象语义是分布的最底层参数；本体变更 ⇒ 已校准判定的有效性存疑 ⇒ 触发重估）。
--     * Slot: validity_status Description: 当前是否有效（池组成/spec/harness/本体任一变化即触发漂移重估工作流）。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
-- # Class: Budget Description: 预算结构体（R-POOL-BUDGET 成本熔断的声明载体）。全司级日/月熔断阈值 属 S5 裁决项（S5-PENDING-DEFAULTS #5），本结构只承载闭环级与全局声明。
--     * Slot: id
--     * Slot: currency Description: 币种（如 CNY/USD/credit）。
--     * Slot: amount_cap Description: 上限金额（闭环级预算上限，R-POOL-BUDGET）。
--     * Slot: period Description: 计费周期口径（per-run/daily/monthly）。
-- # Class: Commitment Description: 已接受承诺（权威源=控制面 DB，DGA-INFRA 第 1 章权威源表）。 承诺→闭环→授权→执行→证据→判定→责任连接关系的起点（CMP-01 核心资产）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: retired_at Description: 退役时间（资产目录要求：每个池对象/资产有退役方式与时间）。
--     * Slot: promise Description: 承诺内容（对谁、承诺什么）。
--     * Slot: promisee Description: 承诺相对方（客户/干系人）。
--     * Slot: accountable_person Description: 承诺责任人（具名的人；社会关系的合法主体，human v1.1 §1.4）。
--     * Slot: linked_authorization Description: 关联授权（Authorization id，AUT-xxxx）。
--     * Slot: state Description: 承诺履约状态。
-- # Class: Authorization Description: 有效授权（权威源=控制面 DB，DGA-INFRA 第 1 章权威源表）。 结构：scope/budget/decision_timespan。恢复检查点须重验当前授权（R-POL-02）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: decision_timespan Description: 决断时距（human v1.1 §2.3：自治的最大无人复核时间跨度；超时挂起，R-POOL-DEGRADE）。
--     * Slot: autonomy_level Description: 授予的自治等级（L0-L5；跳级即事故）。
--     * Slot: granted_executor Description: 被授权执行体（CapabilityEntity id，CAP-xxxx）——授权 agent 的是执行权。
--     * Slot: granted_by Description: 授权人（具名的人）——授权人的是责任（human v1.1 §1.4 推论二：两份授权文书、两种治理）。
--     * Slot: valid_from Description: 生效时间。
--     * Slot: valid_until Description: 失效时间（自治边界到期即停；崩溃恢复后须重验当前授权，R-POL-02）。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
--     * Slot: budget_id Description: 预算上限（闭环级；R-POOL-BUDGET）。
-- # Class: DecisionOption Description: S5 决策卡片的候选项（R-GOV-04 固定结构之"选项"）。
--     * Slot: id
--     * Slot: option_label Description: 选项名。
--     * Slot: tradeoff Description: 该选项的代价与收益（供 S5 审阅的取舍说明）。
--     * Slot: S5DecisionCard_id Description: Autocreated FK slot
-- # Class: S5DecisionCard Description: S5 决策卡片（R-GOV-04 锚点类）：固定结构=对象/证据/选项/推荐/期限/批准后果， 六字段全部 required。飞书审批卡是本类的受控投影（第 1 章：飞书仪表盘= 权威信息的受控投影，非权威源）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: decision_object Description: 决策对象（要裁决什么）。
--     * Slot: recommendation Description: 推荐项及理由（推导链引用 DGA-INFRA/CORE 条目 ID，8.3 纪律）。
--     * Slot: deadline Description: 审阅期限（超期按 R-GOV-07 安全默认模式处理）。
--     * Slot: approval_consequences Description: 批准后果（批准后会发生什么/爆炸半径声明）。
--     * Slot: decided_by Description: 裁决人（S5；S5 不可代理——R-SEC-04 禁止代签）。
--     * Slot: decided_at Description: 裁决时间。
-- # Class: Project Description: 项目（R-GOV-05 锚点类之一）：有限期变更的登记。项目与服务分离登记， 项目完成不注销责任——accountable_person 在项目关闭后仍为历史证据链的责任锚点 （R-IR-04：历史证据不足的项目标记"治理状态未知/待验证"）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: retired_at Description: 退役时间（资产目录要求：每个池对象/资产有退役方式与时间）。
--     * Slot: accountable_person Description: 项目责任人（具名）。项目完成 ≠ 责任消失（R-GOV-05）。
--     * Slot: start_date Description: 开始日期。
--     * Slot: end_date Description: 结束日期（有限期变更的界定字段；届满须显式延期或关闭）。
--     * Slot: deliverable_spec Description: 交付物规格引用。
--     * Slot: linked_service Description: 交付后转入的持续服务（Service id，SVC-xxxx）。
-- # Class: Service Description: 服务（R-GOV-05 锚点类之二）：持续履约的登记。与 Project 分离登记—— 一次性交付与持续运营的责任结构不同，不得混用同一登记类型。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: retired_at Description: 退役时间（资产目录要求：每个池对象/资产有退役方式与时间）。
--     * Slot: accountable_person Description: 服务责任人（具名；持续履约期间责任持续在位）。
--     * Slot: service_scope Description: 履约范围声明。
--     * Slot: sla_summary Description: SLA 摘要（响应/恢复目标）。
-- # Class: ActionType Description: 操作类型（Action 层唯一类；R-POL/R-FLOW 锚点类）。每个操作类型定义：参数 schema、 前置条件、副作用声明、权限谓词、必须产生的证据类型、失败语义、幂等键。 为什么动词层是治理的实体：实体清单可以复制，但"在什么条件下允许做什么操作"的 知识是治理的实体本身（human v1.1 §5.2）。判定者不得持有本层执行权限（§5.9）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: params_schema_ref Description: 参数 schema 引用（JSON Schema URI；由本仓库 LinkML 生成物提供， MCP 网关注册时强制绑定——ontology-research §三.2）。
--     * Slot: permission_predicate_ref Description: 权限谓词引用（OPA policy 路径；"模型被告知不能做"不算权限控制，R-POL-01）。
--     * Slot: required_evidence_type Description: 必须产生的证据类型（六元组 Evidence 分量的构造化，human v1.1 §5.10）。
--     * Slot: failure_semantics Description: 失败语义（可重试/需补偿/待核实；R-FLOW-02/03）。
--     * Slot: idempotency_key Description: 幂等键模板（R-FLOW-03：幂等键+结果核对+补偿；Temporal 语义不默认保证恰好一次）。
--     * Slot: retry_owner Description: 唯一重试责任方（R-FLOW-02：每个有外部副作用的步骤必须有唯一重试责任方）。
--     * Slot: executor_binding Description: 绑定的执行能力（CapabilityEntity id，CAP-xxxx）。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
--     * Slot: ClosureUnit_id Description: Autocreated FK slot
-- # Class: FunctionType Description: 判定类型（Function 层唯一类）。每个 Function 定义：类型化输入输出、所属校准域、 版本。为什么独立于 Action：判定逻辑混入操作实现会使判定不可独立演化、不可独立 审计、不可交叉比对（human v1.1 §5.2）。执行者不能修改校准参数与已记录失败 （R-POL-04）；换模型评审≠获得校准判定。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: function_kind Description: 判定函数类别（评估/校准/漂移检测/度量计算）。
--     * Slot: input_schema_ref Description: 类型化输入 schema 引用（typed in）。
--     * Slot: output_schema_ref Description: 类型化输出 schema 引用（typed out）。
--     * Slot: calibration_domain_ref Description: 所属校准域（CalibrationDomain id，CAL-xxxx；R-POOL-CALIB：校准有效性声明）。
--     * Slot: version Description: 函数版本（可独立演化、独立审计、可交叉比对——三重度量的结构支点）。
--     * Slot: hidden_sealed_ref Description: 隐匿判定集密封指针（hash 引用纪律，human v1.1 §4.3 其二·附形态乙： 考卷公开、答案密封）。执行侧上下文装配物理不含本字段内容。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
-- # Class: ClosureUnit Description: 闭环单元（六元组：Intent/Context/Capability/Action/Evidence/Accountability）—— 组织分析的最小单元（human v1.1 §2.1）。六元缺一闭环在治理上不完整； 其中 accountability 必填（R-GOV-03），其余五元 recommended（缺省须说明）。 采用嵌套+角色槽路线而非类继承（human v1.1 §5.4：类继承把嵌套压扁成分类， 递归性丢失）。同构于 VSM：每个闭环节点内部可挂完整五职能子节点，任意深度。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: capability Description: 能力（六元组之三）——执行手段。
--     * Slot: state Description: 生命周期状态机（Object 层要件，human v1.1 §5.2）。
--     * Slot: parent Description: 父闭环（嵌套关系的实体侧表达；组织=闭环的递归嵌套图，human v1.1 §2.1）。 嵌套的 Link 侧正式登记用 ClosureNesting；本字段是父引用快捷键。 子闭环的决断时距不得超过父闭环（约束谓词在 OPA 层强制）。
--     * Slot: decision_timespan Description: 决断时距（human v1.1 §2.3）——无人复核的最大自主时间跨度。
--     * Slot: autonomy_level Description: 当前自治等级（L0-L5；跳级即事故）。
--     * Slot: authorization_ref Description: 有效授权（Authorization id，AUT-xxxx）。
--     * Slot: git_binding_ref Description: 六元组稳定定义在 Git 中的绑定位置（R-GOV-02：稳定定义与运行时动态值分离）。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
--     * Slot: intent_id Description: 意图（六元组之一）——闭环存在的原因。
--     * Slot: accountability_id Description: 责任（六元组之六，REQUIRED）——闭环终点的具名的人。缺责任人的闭环叫事故待发； 新闭环缺具名责任人 ⇒ 拒绝生产执行资格（R-GOV-03，M0 负面测试锚点）。 本槽缺失必须使校验失败。
-- # Class: AccountabilityLink Description: 责任挂接关系（Link 层；六元组 Accountability 分量在本体的正式载体，human v1.1 §5.3 映射：Accountability → Link 责任挂接关系（必填约束））。 closure→responsible_person 的关系约束：目标必须是具名的人。 本关系的 required 性质是 R-GOV-03 负面测试（缺责任人拒绝创建）的 schema 锚点。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: closure Description: 被挂接的闭环（ClosureUnit id，CU-xxxx）。
--     * Slot: responsible_person Description: 责任人（具名的人，Person 类型——类型系统层面排除 agent 充当责任锚点； 责任守恒律 human v1.1 §1.4；R-GOV-03）。
--     * Slot: responsibility_scope Description: 责任范围声明（对什么后果应答）。
--     * Slot: delegated_executor Description: 受托执行体（CapabilityEntity id，CAP-xxxx）——执行权可授，责任不随之转移。
--     * Slot: assumed_at Description: 责任接手时间。
-- # Class: ClosureNesting Description: 嵌套关系（Link 层；human v1.1 §5.4：闭环实体表+父引用建立递归嵌套； Simon 近可分解性的 agent 实现——分解单位从部门变为闭环，粘合剂从汇报关系 变为嵌套关系）。关系合法性谓词"子闭环自治不得放大父闭环约束"在本结构上是 Link 层标准合法性谓词（变异度律的可执行形态）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: parent_closure Description: 父闭环（ClosureUnit id，CU-xxxx）。
--     * Slot: child_closure Description: 子闭环（ClosureUnit id，CU-xxxx）。
--     * Slot: nesting_rationale Description: 拆分理由（近可分解性的分解记录）。
--     * Slot: timespan_constraint_checked Description: "子决断时距 ≤ 父决断时距"约束已核验标记（登记时人工/工具核验）。 纯 schema 无法表达跨实例不等式——该谓词属 OPA/运行时强制（M0 诚实边界）； 本字段保证核验动作本身被记录在位。
--     * Slot: authority_inheritance_declared Description: 权限继承声明（R-POL-02：子任务权限 ≤ 父任务；拆十个 agent 不获得十倍预算）。
-- # Class: RoleSlot Description: 角色槽（Link 层；human v1.1 §5.4：实体在闭环中扮演的角色是独立的类型化槽位）。 "角色稳定、执行者可替换"的结构表达：换执行者不动结构（§2.1/§3.4 岗位重定义的 构造基础）。责任槽（ACCOUNTABLE）的填充物只能是 Person——由 AccountabilityLink 强制，本槽不做第二责任源。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: closure Description: 所属闭环（ClosureUnit id，CU-xxxx）。
--     * Slot: role Description: 角色类型（稳定结构槽位；VSM 五职能+意图/上下文/验证/责任槽）。
--     * Slot: filler_person Description: 填充物（人）——与 filler_capability 二选一；角色稳定、执行者可替换。
--     * Slot: filler_capability Description: 填充物（能力实体：agent/模型组合）——与 filler_person 二选一。
--     * Slot: filled_at Description: 填充时间（换填充物=撤换记录，撤槽须走责任检查：在途闭环的责任不得悬空）。
-- # Class: OriginalProjection Description: 原件-投影关系（Link 层；human v1.1 §5.8：投影关系本身是本体 Link 类型， 可见性不是部署细节而是实体的结构属性）。信息只从高权限区向低权限区投影， 反向读取与反向写入在架构上禁止。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: original_ref Description: 原件（真值区实体 id）。
--     * Slot: projection_ref Description: 投影（低权限区实体 id）。
--     * Slot: gradient_zone Description: 投影目标分区（真值区/工作区/冗余区，human v1.1 §5.8）。
--     * Slot: transform_pipeline Description: 脱敏管道描述（投影关系的物化实现）。
--     * Slot: writeback_allowed Description: 是否允许回写（默认 false——禁止反向写：投影没有对原件的回写路径， 修改须走受治理的回流流程，human v1.1 §5.8 不变量一）。
--     * Slot: cross_read_allowed Description: 是否允许跨梯度读（默认 false——低权限区行动者无法读高权限区内容； 判定隔离由此获得架构保证而非纪律约定，human v1.1 §5.8 不变量二）。
-- # Class: QuotaState Description: 配额状态值对象（DGA-INFRA 3.1 Account.quota_state：RPM/TPM/日额/月额/信用池余量）。 无独立 ID 的内嵌值对象，随 PoolAccount 存续。
--     * Slot: id
--     * Slot: rpm_limit Description: 每分钟请求数限额（RPM）。
--     * Slot: tpm_limit Description: 每分钟 token 限额（TPM）。
--     * Slot: daily_quota Description: 日额余量。
--     * Slot: monthly_quota Description: 月额余量。
--     * Slot: credit_balance Description: 信用池余量。
--     * Slot: observed_at Description: 账本观测时间（R-POOL-QUOTA：账本 vs 供应商面板定期抽查，误差超阈值报警）。
-- # Class: HealthSnapshot Description: 健康快照值对象（DGA-INFRA 3.1 Account.health：可用性/延迟/错误率/最近故障）。 池健康度量进入治理度量体系与公示仪表（3.9 R-POOL-EVID）。
--     * Slot: id
--     * Slot: availability_pct Description: 可用性（百分比 0-100）。
--     * Slot: latency_ms_p95 Description: P95 延迟（毫秒）。
--     * Slot: error_rate Description: 错误率（0-1）。
--     * Slot: last_failure_at Description: 最近故障时间。
--     * Slot: last_check_at Description: 最近健康检查时间（验证时间——资产目录要件）。
-- # Class: Provider Description: 供应商（DGA-INFRA 3.1：anthropic/google/deepseek/openai/cloudflare/rayway 等）。 池对象模型顶层；每个 Provider 的 TOS 风险矩阵是池准入依据（R-POOL-COMPLIANCE）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: retired_at Description: 退役时间（资产目录要求：每个池对象/资产有退役方式与时间）。
--     * Slot: tos_risk_matrix_ref Description: TOS 风险矩阵引用（DGA-INFRA 3.4：每个 Provider 出具 TOS 风险矩阵——多账号 条款/免费层用途限制/数据使用条款/个人订阅转 API 许可度）。
--     * Slot: data_usage_terms_summary Description: 数据使用条款摘要（T0/T1/T2 定级依据之一）。
--     * Slot: notes Description: 备注。
-- # Class: PoolAccount Description: 池账号（DGA-INFRA 3.1：一个 Provider 可多账号）。字段全集=credential_ref/ cost_tier/quota_state/trust_label/tos_risk/health。多付费个人账号轮换是 S5 认可的 价值获取策略：不禁止、不默认，风险显式标注（R-POOL-COMPLIANCE）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: retired_at Description: 退役时间（资产目录要求：每个池对象/资产有退役方式与时间）。
--     * Slot: provider Description: 所属供应商（Provider id，PRV-xxxx）。
--     * Slot: credential_ref Description: 凭据引用（明文仅存凭据库，此处仅存引用——R-SEC-02；轮换有 runbook 与撤销 验证——R-SEC-03）。
--     * Slot: cost_tier Description: 成本分层（free/low-paid/high-paid/enterprise）。
--     * Slot: trust_label Description: 信任标签（T0/T1/T2）。个人订阅账号一律 T0（R-POOL-COMPLIANCE 强制）； 数据红线：客户业务数据禁止路由至 T0 端点（R-POOL-DATA）。
--     * Slot: tos_risk Description: TOS 合规风险标签（灰区账号强制 T0 且隔离；agent 发现灰区即升级 S5）。
--     * Slot: accountable_person Description: 具名责任人（池对象=资产目录正式资产的要件，DGA-INFRA 3.1）。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
--     * Slot: quota_state_id Description: 配额状态（内嵌值对象）。
--     * Slot: health_id Description: 健康快照（内嵌值对象）。
-- # Class: LogicalEndpoint Description: 逻辑端点（DGA-INFRA 3.1：绑定 Account 集合+路由策略）。池路由是资源层的 harness（[DER-03] 成对律在资源层的实现，3.2）。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: retired_at Description: 退役时间（资产目录要求：每个池对象/资产有退役方式与时间）。
--     * Slot: endpoint_name Description: 逻辑端点名（如 free-workhorse / paid-judge / t1-only，DGA-INFRA 3.1）。
--     * Slot: trust_level Description: 端点级信任标签（3.2：端点带 trust 标签；任务 sensitivity ≤ 端点 trust—— 不等式谓词属 OPA 层，本字段保证端点侧在位）。
--     * Slot: routing_policy_ref Description: 路由策略（RoutingPolicy id，RTP-xxxx）。
--     * Slot: accountable_person Description: 具名责任人。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
-- # Class: RoutingPolicy Description: 路由策略（DGA-INFRA 3.1 全字段：按能力/成本/信任/配额/漂移五约束路由； 扩展承载降级链/预算/虚拟 key/时距挂起）。策略本体进 Git（权威源=Git 经批准 版本），运行时投影进 LiteLLM 与 OPA。
--     * Slot: id Description: 全局唯一稳定标识：类前缀-序号（ID 体系 M0 第一天定稿，DGA-INFRA 第 4 章）。 前缀对照：CU=ClosureUnit INT=Intent CTX=ContextAsset CAP=CapabilityEntity ACT=ActionType FN=FunctionType EVD=EvidenceEntity CMT=Commitment AUT=Authorization DC=S5DecisionCard PSN=Person CAL=CalibrationDomain PRJ=Project SVC=Service PRV=Provider ACC=PoolAccount EPL=LogicalEndpoint RTP=RoutingPolicy ALK=AccountabilityLink CNL=ClosureNesting RSL=RoleSlot OPR=OriginalProjection。 本全局 pattern 由各类 slot_usage 收紧为单前缀。
--     * Slot: name Description: 人类可读名称（飞书表格等投影的主显示字段）。
--     * Slot: created_at Description: 登记时间（UTC）。
--     * Slot: target_capability Description: 能力约束——路由针对的能力需求（3.1：按能力路由）。
--     * Slot: min_trust_level Description: 信任约束——任务允许的端点最低信任级。
--     * Slot: max_data_sensitivity Description: 本策略可承接的最大任务敏感度（与端点 trust_level 构成"sensitivity ≤ trust" 路由谓词的两端字段；谓词强制在 OPA 层——M0 诚实边界登记）。
--     * Slot: quota_constraints Description: 配额约束（3.1：按配额路由；余量阈值、独占/共享等声明）。
--     * Slot: calibration_domain_ref Description: 漂移约束——关联校准域（CalibrationDomain id，CAL-xxxx；3.8：池组成变化触发 漂移重估工作流）。
--     * Slot: virtual_key_isolated Description: 是否启用每执行单元独立虚拟 key 限额（R-POL-03：池路由的虚拟 key 限额落实 子任务不放大授权）。
--     * Slot: suspension_on_timespan_expiry Description: 等待超过闭环授权的决断时距 ⇒ 挂起（3.5；MET-01）。
--     * Slot: approval_ref Description: 批准来源（Authorization id，AUT-xxxx；策略变更走 Git 批准版本）。
--     * Slot: accountable_person Description: 具名责任人。
--     * Slot: trust_level Description: 信任等级（T0/T1/T2，DGA-INFRA 3.2）。
--     * Slot: data_class Description: 保密级别（D_公开/D_内部/D_客户敏感）。
--     * Slot: boundary Description: 归属/信任边界坐标（Security 层标记维度，human v1.1 §5.2），如 company-cloud / customer-onprem / s5-personal。信息梯度上的位置声明（§5.8： 每个信息存储的位置必须声明其在梯度上的坐标）。
--     * Slot: budget_cap_id Description: 预算上限（3.6 R-POOL-BUDGET：闭环级预算上限声明）。
-- # Class: CapabilityEntity_model_refs
--     * Slot: CapabilityEntity_id Description: Autocreated FK slot
--     * Slot: model_refs Description: 依赖的模型清单（池组成相关；漂移监控对象）。
-- # Class: CalibrationDomain_model_set_snapshot
--     * Slot: CalibrationDomain_id Description: Autocreated FK slot
--     * Slot: model_set_snapshot Description: 覆盖的模型集合快照（池组成快照，DGA-INFRA 3.8 R-POOL-CALIB）。 评估器建模的是池混合分布，不是单端点（PR-INF-02c）。
-- # Class: Authorization_scope
--     * Slot: Authorization_id Description: Autocreated FK slot
--     * Slot: scope Description: 授权范围（允许的操作集合/资源边界；R-POL-02：子任务权限≤父任务）。
-- # Class: S5DecisionCard_evidence_refs
--     * Slot: S5DecisionCard_id Description: Autocreated FK slot
--     * Slot: evidence_refs Description: 支撑证据（EvidenceEntity id 列表，EVD-xxxx）。
-- # Class: Service_related_projects
--     * Slot: Service_id Description: Autocreated FK slot
--     * Slot: related_projects Description: 关联项目（Project id 列表，PRJ-xxxx）。
-- # Class: ActionType_preconditions
--     * Slot: ActionType_id Description: Autocreated FK slot
--     * Slot: preconditions Description: 前置条件（可执行谓词声明；强制点在服务端/工具网关，R-POL-01）。
-- # Class: ActionType_side_effects
--     * Slot: ActionType_id Description: Autocreated FK slot
--     * Slot: side_effects Description: 副作用声明——将修改哪些实体与关系（审计与回滚的依据，R-IR-02）。
-- # Class: OriginalProjection_clipping_declaration
--     * Slot: OriginalProjection_id Description: Autocreated FK slot
--     * Slot: clipping_declaration Description: 裁剪声明——被裁剪/脱敏的字段清单（投影携带裁剪后的子集，须显式声明）。
-- # Class: LogicalEndpoint_bound_accounts
--     * Slot: LogicalEndpoint_id Description: Autocreated FK slot
--     * Slot: bound_accounts Description: 绑定的账号集合（PoolAccount id 列表，ACC-xxxx）。
-- # Class: RoutingPolicy_allowed_cost_tiers
--     * Slot: RoutingPolicy_id Description: Autocreated FK slot
--     * Slot: allowed_cost_tiers Description: 成本约束——S5 批准的成本等级白名单（3.5：禁止自动跳到 S5 未批准的成本等级）。
-- # Class: RoutingPolicy_fallback_chain
--     * Slot: RoutingPolicy_id Description: Autocreated FK slot
--     * Slot: fallback_chain Description: 降级链（有序）：T1 主力付费 → T1 备用付费 → 低成本付费 → 队列等待/挂起 → 升级 S5（3.5 R-POOL-DEGRADE；免费层 T0 不作为任何客户链路的降级终点）。 列表顺序即降级顺序。

CREATE TABLE "SecurityMark" (
	id INTEGER NOT NULL,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_SecurityMark_id" ON "SecurityMark" (id);

CREATE TABLE "Person" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	full_name TEXT NOT NULL,
	org_role TEXT,
	contact_channel TEXT,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_Person_id" ON "Person" (id);

CREATE TABLE "CapabilityEntity" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	executor_type VARCHAR(8),
	endpoint_ref TEXT,
	capability_version TEXT,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_CapabilityEntity_id" ON "CapabilityEntity" (id);

CREATE TABLE "CalibrationDomain" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	spec_version TEXT NOT NULL,
	harness_version TEXT NOT NULL,
	observation_window_start TIMESTAMP,
	observation_window_end TIMESTAMP,
	ontology_commit TEXT NOT NULL,
	validity_status BOOLEAN,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_CalibrationDomain_id" ON "CalibrationDomain" (id);

CREATE TABLE "Budget" (
	id INTEGER NOT NULL,
	currency TEXT,
	amount_cap FLOAT,
	period TEXT,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_Budget_id" ON "Budget" (id);

CREATE TABLE "FunctionType" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	function_kind VARCHAR(15) NOT NULL,
	input_schema_ref TEXT NOT NULL,
	output_schema_ref TEXT NOT NULL,
	calibration_domain_ref TEXT,
	version TEXT NOT NULL,
	hidden_sealed_ref TEXT,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_FunctionType_id" ON "FunctionType" (id);

CREATE TABLE "ClosureUnit" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	capability TEXT,
	state VARCHAR(21),
	parent TEXT,
	decision_timespan TEXT,
	autonomy_level VARCHAR(2),
	authorization_ref TEXT,
	git_binding_ref TEXT,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	intent_id TEXT,
	accountability_id TEXT NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(capability) REFERENCES "CapabilityEntity" (id),
	FOREIGN KEY(parent) REFERENCES "ClosureUnit" (id)
);
CREATE INDEX "ix_ClosureUnit_id" ON "ClosureUnit" (id);

CREATE TABLE "AccountabilityLink" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	closure TEXT NOT NULL,
	responsible_person TEXT NOT NULL,
	responsibility_scope TEXT,
	delegated_executor TEXT,
	assumed_at TIMESTAMP,
	PRIMARY KEY (id),
	FOREIGN KEY(closure) REFERENCES "ClosureUnit" (id),
	FOREIGN KEY(responsible_person) REFERENCES "Person" (id)
);
CREATE INDEX "ix_AccountabilityLink_id" ON "AccountabilityLink" (id);

CREATE TABLE "ClosureNesting" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	parent_closure TEXT NOT NULL,
	child_closure TEXT NOT NULL,
	nesting_rationale TEXT,
	timespan_constraint_checked BOOLEAN,
	authority_inheritance_declared BOOLEAN,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_ClosureNesting_id" ON "ClosureNesting" (id);

CREATE TABLE "OriginalProjection" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	original_ref TEXT NOT NULL,
	projection_ref TEXT NOT NULL,
	gradient_zone VARCHAR(15),
	transform_pipeline TEXT,
	writeback_allowed BOOLEAN,
	cross_read_allowed BOOLEAN,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_OriginalProjection_id" ON "OriginalProjection" (id);

CREATE TABLE "QuotaState" (
	id INTEGER NOT NULL,
	rpm_limit INTEGER,
	tpm_limit INTEGER,
	daily_quota FLOAT,
	monthly_quota FLOAT,
	credit_balance FLOAT,
	observed_at TIMESTAMP,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_QuotaState_id" ON "QuotaState" (id);

CREATE TABLE "HealthSnapshot" (
	id INTEGER NOT NULL,
	availability_pct FLOAT,
	latency_ms_p95 INTEGER,
	error_rate FLOAT,
	last_failure_at TIMESTAMP,
	last_check_at TIMESTAMP,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_HealthSnapshot_id" ON "HealthSnapshot" (id);

CREATE TABLE "Provider" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	retired_at TIMESTAMP,
	tos_risk_matrix_ref TEXT,
	data_usage_terms_summary TEXT,
	notes TEXT,
	PRIMARY KEY (id)
);
CREATE INDEX "ix_Provider_id" ON "Provider" (id);

CREATE TABLE "Intent" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	statement TEXT NOT NULL,
	closure_type TEXT,
	desired_outcome TEXT,
	holder TEXT,
	source_ref TEXT,
	PRIMARY KEY (id),
	FOREIGN KEY(holder) REFERENCES "Person" (id)
);
CREATE INDEX "ix_Intent_id" ON "Intent" (id);

CREATE TABLE "ContextAsset" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	asset_type VARCHAR(19),
	uri TEXT,
	version TEXT,
	expiry_condition TEXT,
	authority_source TEXT,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	"ClosureUnit_id" TEXT,
	PRIMARY KEY (id),
	FOREIGN KEY("ClosureUnit_id") REFERENCES "ClosureUnit" (id)
);
CREATE INDEX "ix_ContextAsset_id" ON "ContextAsset" (id);

CREATE TABLE "EvidenceEntity" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	evidence_type VARCHAR(20) NOT NULL,
	content_digest TEXT,
	object_version TEXT,
	storage_uri TEXT,
	object_locked BOOLEAN,
	trace_ref TEXT,
	judge_model TEXT,
	judge_version TEXT,
	calibration_domain_ref TEXT,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	"ClosureUnit_id" TEXT,
	PRIMARY KEY (id),
	FOREIGN KEY("ClosureUnit_id") REFERENCES "ClosureUnit" (id)
);
CREATE INDEX "ix_EvidenceEntity_id" ON "EvidenceEntity" (id);

CREATE TABLE "Commitment" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	retired_at TIMESTAMP,
	promise TEXT NOT NULL,
	promisee TEXT,
	accountable_person TEXT NOT NULL,
	linked_authorization TEXT,
	state VARCHAR(21),
	PRIMARY KEY (id),
	FOREIGN KEY(accountable_person) REFERENCES "Person" (id)
);
CREATE INDEX "ix_Commitment_id" ON "Commitment" (id);

CREATE TABLE "Authorization" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	decision_timespan TEXT,
	autonomy_level VARCHAR(2),
	granted_executor TEXT,
	granted_by TEXT NOT NULL,
	valid_from TIMESTAMP,
	valid_until TIMESTAMP,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	budget_id INTEGER,
	PRIMARY KEY (id),
	FOREIGN KEY(granted_by) REFERENCES "Person" (id),
	FOREIGN KEY(budget_id) REFERENCES "Budget" (id)
);
CREATE INDEX "ix_Authorization_id" ON "Authorization" (id);

CREATE TABLE "S5DecisionCard" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	decision_object TEXT NOT NULL,
	recommendation TEXT NOT NULL,
	deadline TIMESTAMP NOT NULL,
	approval_consequences TEXT NOT NULL,
	decided_by TEXT,
	decided_at TIMESTAMP,
	PRIMARY KEY (id),
	FOREIGN KEY(decided_by) REFERENCES "Person" (id)
);
CREATE INDEX "ix_S5DecisionCard_id" ON "S5DecisionCard" (id);

CREATE TABLE "Project" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	retired_at TIMESTAMP,
	accountable_person TEXT NOT NULL,
	start_date DATE NOT NULL,
	end_date DATE NOT NULL,
	deliverable_spec TEXT,
	linked_service TEXT,
	PRIMARY KEY (id),
	FOREIGN KEY(accountable_person) REFERENCES "Person" (id)
);
CREATE INDEX "ix_Project_id" ON "Project" (id);

CREATE TABLE "Service" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	retired_at TIMESTAMP,
	accountable_person TEXT NOT NULL,
	service_scope TEXT NOT NULL,
	sla_summary TEXT,
	PRIMARY KEY (id),
	FOREIGN KEY(accountable_person) REFERENCES "Person" (id)
);
CREATE INDEX "ix_Service_id" ON "Service" (id);

CREATE TABLE "ActionType" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	params_schema_ref TEXT NOT NULL,
	permission_predicate_ref TEXT NOT NULL,
	required_evidence_type VARCHAR(20) NOT NULL,
	failure_semantics VARCHAR(15) NOT NULL,
	idempotency_key TEXT,
	retry_owner TEXT,
	executor_binding TEXT,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	"ClosureUnit_id" TEXT,
	PRIMARY KEY (id),
	FOREIGN KEY("ClosureUnit_id") REFERENCES "ClosureUnit" (id)
);
CREATE INDEX "ix_ActionType_id" ON "ActionType" (id);

CREATE TABLE "RoleSlot" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	closure TEXT NOT NULL,
	role VARCHAR(16) NOT NULL,
	filler_person TEXT,
	filler_capability TEXT,
	filled_at TIMESTAMP,
	PRIMARY KEY (id),
	FOREIGN KEY(filler_person) REFERENCES "Person" (id),
	FOREIGN KEY(filler_capability) REFERENCES "CapabilityEntity" (id)
);
CREATE INDEX "ix_RoleSlot_id" ON "RoleSlot" (id);

CREATE TABLE "PoolAccount" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	retired_at TIMESTAMP,
	provider TEXT NOT NULL,
	credential_ref TEXT NOT NULL,
	cost_tier VARCHAR(10) NOT NULL,
	trust_label VARCHAR(2) NOT NULL,
	tos_risk VARCHAR(9),
	accountable_person TEXT,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	quota_state_id INTEGER,
	health_id INTEGER,
	PRIMARY KEY (id),
	FOREIGN KEY(accountable_person) REFERENCES "Person" (id),
	FOREIGN KEY(quota_state_id) REFERENCES "QuotaState" (id),
	FOREIGN KEY(health_id) REFERENCES "HealthSnapshot" (id)
);
CREATE INDEX "ix_PoolAccount_id" ON "PoolAccount" (id);

CREATE TABLE "LogicalEndpoint" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	retired_at TIMESTAMP,
	endpoint_name TEXT NOT NULL,
	trust_level VARCHAR(2) NOT NULL,
	routing_policy_ref TEXT,
	accountable_person TEXT,
	data_class VARCHAR(20),
	boundary TEXT,
	PRIMARY KEY (id),
	FOREIGN KEY(accountable_person) REFERENCES "Person" (id)
);
CREATE INDEX "ix_LogicalEndpoint_id" ON "LogicalEndpoint" (id);

CREATE TABLE "RoutingPolicy" (
	id TEXT NOT NULL,
	name TEXT,
	created_at TIMESTAMP,
	target_capability TEXT,
	min_trust_level VARCHAR(2),
	max_data_sensitivity VARCHAR(21),
	quota_constraints TEXT,
	calibration_domain_ref TEXT,
	virtual_key_isolated BOOLEAN,
	suspension_on_timespan_expiry BOOLEAN,
	approval_ref TEXT,
	accountable_person TEXT,
	trust_level VARCHAR(2),
	data_class VARCHAR(20),
	boundary TEXT,
	budget_cap_id INTEGER,
	PRIMARY KEY (id),
	FOREIGN KEY(accountable_person) REFERENCES "Person" (id),
	FOREIGN KEY(budget_cap_id) REFERENCES "Budget" (id)
);
CREATE INDEX "ix_RoutingPolicy_id" ON "RoutingPolicy" (id);

CREATE TABLE "CapabilityEntity_model_refs" (
	"CapabilityEntity_id" TEXT,
	model_refs TEXT,
	PRIMARY KEY ("CapabilityEntity_id", model_refs),
	FOREIGN KEY("CapabilityEntity_id") REFERENCES "CapabilityEntity" (id)
);
CREATE INDEX "ix_CapabilityEntity_model_refs_model_refs" ON "CapabilityEntity_model_refs" (model_refs);
CREATE INDEX "ix_CapabilityEntity_model_refs_CapabilityEntity_id" ON "CapabilityEntity_model_refs" ("CapabilityEntity_id");

CREATE TABLE "CalibrationDomain_model_set_snapshot" (
	"CalibrationDomain_id" TEXT,
	model_set_snapshot TEXT NOT NULL,
	PRIMARY KEY ("CalibrationDomain_id", model_set_snapshot),
	FOREIGN KEY("CalibrationDomain_id") REFERENCES "CalibrationDomain" (id)
);
CREATE INDEX "ix_CalibrationDomain_model_set_snapshot_model_set_snapshot" ON "CalibrationDomain_model_set_snapshot" (model_set_snapshot);
CREATE INDEX "ix_CalibrationDomain_model_set_snapshot_CalibrationDomain_id" ON "CalibrationDomain_model_set_snapshot" ("CalibrationDomain_id");

CREATE TABLE "OriginalProjection_clipping_declaration" (
	"OriginalProjection_id" TEXT,
	clipping_declaration TEXT NOT NULL,
	PRIMARY KEY ("OriginalProjection_id", clipping_declaration),
	FOREIGN KEY("OriginalProjection_id") REFERENCES "OriginalProjection" (id)
);
CREATE INDEX "ix_OriginalProjection_clipping_declaration_OriginalProjection_id" ON "OriginalProjection_clipping_declaration" ("OriginalProjection_id");
CREATE INDEX "ix_OriginalProjection_clipping_declaration_clipping_declaration" ON "OriginalProjection_clipping_declaration" (clipping_declaration);

CREATE TABLE "DecisionOption" (
	id INTEGER NOT NULL,
	option_label TEXT NOT NULL,
	tradeoff TEXT,
	"S5DecisionCard_id" TEXT,
	PRIMARY KEY (id),
	FOREIGN KEY("S5DecisionCard_id") REFERENCES "S5DecisionCard" (id)
);
CREATE INDEX "ix_DecisionOption_id" ON "DecisionOption" (id);

CREATE TABLE "Authorization_scope" (
	"Authorization_id" TEXT,
	scope TEXT NOT NULL,
	PRIMARY KEY ("Authorization_id", scope),
	FOREIGN KEY("Authorization_id") REFERENCES "Authorization" (id)
);
CREATE INDEX "ix_Authorization_scope_scope" ON "Authorization_scope" (scope);
CREATE INDEX "ix_Authorization_scope_Authorization_id" ON "Authorization_scope" ("Authorization_id");

CREATE TABLE "S5DecisionCard_evidence_refs" (
	"S5DecisionCard_id" TEXT,
	evidence_refs TEXT,
	PRIMARY KEY ("S5DecisionCard_id", evidence_refs),
	FOREIGN KEY("S5DecisionCard_id") REFERENCES "S5DecisionCard" (id)
);
CREATE INDEX "ix_S5DecisionCard_evidence_refs_S5DecisionCard_id" ON "S5DecisionCard_evidence_refs" ("S5DecisionCard_id");
CREATE INDEX "ix_S5DecisionCard_evidence_refs_evidence_refs" ON "S5DecisionCard_evidence_refs" (evidence_refs);

CREATE TABLE "Service_related_projects" (
	"Service_id" TEXT,
	related_projects TEXT,
	PRIMARY KEY ("Service_id", related_projects),
	FOREIGN KEY("Service_id") REFERENCES "Service" (id)
);
CREATE INDEX "ix_Service_related_projects_Service_id" ON "Service_related_projects" ("Service_id");
CREATE INDEX "ix_Service_related_projects_related_projects" ON "Service_related_projects" (related_projects);

CREATE TABLE "ActionType_preconditions" (
	"ActionType_id" TEXT,
	preconditions TEXT,
	PRIMARY KEY ("ActionType_id", preconditions),
	FOREIGN KEY("ActionType_id") REFERENCES "ActionType" (id)
);
CREATE INDEX "ix_ActionType_preconditions_ActionType_id" ON "ActionType_preconditions" ("ActionType_id");
CREATE INDEX "ix_ActionType_preconditions_preconditions" ON "ActionType_preconditions" (preconditions);

CREATE TABLE "ActionType_side_effects" (
	"ActionType_id" TEXT,
	side_effects TEXT NOT NULL,
	PRIMARY KEY ("ActionType_id", side_effects),
	FOREIGN KEY("ActionType_id") REFERENCES "ActionType" (id)
);
CREATE INDEX "ix_ActionType_side_effects_ActionType_id" ON "ActionType_side_effects" ("ActionType_id");
CREATE INDEX "ix_ActionType_side_effects_side_effects" ON "ActionType_side_effects" (side_effects);

CREATE TABLE "LogicalEndpoint_bound_accounts" (
	"LogicalEndpoint_id" TEXT,
	bound_accounts TEXT,
	PRIMARY KEY ("LogicalEndpoint_id", bound_accounts),
	FOREIGN KEY("LogicalEndpoint_id") REFERENCES "LogicalEndpoint" (id)
);
CREATE INDEX "ix_LogicalEndpoint_bound_accounts_bound_accounts" ON "LogicalEndpoint_bound_accounts" (bound_accounts);
CREATE INDEX "ix_LogicalEndpoint_bound_accounts_LogicalEndpoint_id" ON "LogicalEndpoint_bound_accounts" ("LogicalEndpoint_id");

CREATE TABLE "RoutingPolicy_allowed_cost_tiers" (
	"RoutingPolicy_id" TEXT,
	allowed_cost_tiers VARCHAR(10),
	PRIMARY KEY ("RoutingPolicy_id", allowed_cost_tiers),
	FOREIGN KEY("RoutingPolicy_id") REFERENCES "RoutingPolicy" (id)
);
CREATE INDEX "ix_RoutingPolicy_allowed_cost_tiers_RoutingPolicy_id" ON "RoutingPolicy_allowed_cost_tiers" ("RoutingPolicy_id");
CREATE INDEX "ix_RoutingPolicy_allowed_cost_tiers_allowed_cost_tiers" ON "RoutingPolicy_allowed_cost_tiers" (allowed_cost_tiers);

CREATE TABLE "RoutingPolicy_fallback_chain" (
	"RoutingPolicy_id" TEXT,
	fallback_chain TEXT,
	PRIMARY KEY ("RoutingPolicy_id", fallback_chain),
	FOREIGN KEY("RoutingPolicy_id") REFERENCES "RoutingPolicy" (id)
);
CREATE INDEX "ix_RoutingPolicy_fallback_chain_RoutingPolicy_id" ON "RoutingPolicy_fallback_chain" ("RoutingPolicy_id");
CREATE INDEX "ix_RoutingPolicy_fallback_chain_fallback_chain" ON "RoutingPolicy_fallback_chain" (fallback_chain);

