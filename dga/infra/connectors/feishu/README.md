# 飞书四工作台 ↔ 控制面 API 字段映射（M1 占位，未做真实集成）

- 日期：2026-09-06 | 轨道：控制面 M1
- 状态：**占位件，不含任何伪造的集成证据。** 本机无飞书应用凭据（app token / tenant token /
  事件订阅均未申请），故 M1 只交付映射设计与接入前置条件；真实收发在凭据就位后实施。
- 规范依据：CMP-15（飞书=人类协作与业务工作台，**非生产运行时**；群消息/表格状态不构成
  生产授权）；第 1 章架构图（人类交互层）与权威源表——飞书只是"客户、联系人、商机、需求
  草稿、业务讨论"的权威源，闭环登记/授权/判定状态的权威源永远是控制面 DB（R-GOV-01：
  多入口不允许多主写者——飞书写操作一律经控制面 API 落库，飞书侧不直接写 DB）。
- 映射源：`schemas/dga-ontology.yaml`（M0 产物；字段名经
  `schemas/generated/dga-ontology.schema.json` 与控制面 pydantic 模型同源对齐）。

## 四工作台 ↔ API 总览

| 工作台 | 飞书形态 | 承载的控制面能力 | 读写方向 |
|---|---|---|---|
| W1 闭环登记 | 多维表格（登记表单+视图） | `POST /closures`、`GET /closures(/{id})` | 表格→API 写入；API→表格投影回显 |
| W2 审批 | 审批（飞书 approval 实例） | `POST /authorizations`、`GET /authorizations/{id}` | 审批通过回调→API 签发；API 状态→审批详情 |
| W3 S5 队列 | 机器人卡片消息 + 交互按钮 | `GET /decisions/queue`、`POST /decisions/{id}/resolve` | API→卡片推送；按钮回调→resolve |
| W4 资产目录 | 多维表格（只读视图） | `GET /closures?state=`、`GET /authorizations`、（后续 `GET /healthz` 投影） | API→表格单向投影（只读） |

## 字段映射表

### W1 闭环登记 → `POST /closures`

| 飞书表格列（建议名） | LinkML 槽位 / API 字段 | 目标表.列 | 约束 |
|---|---|---|---|
| 闭环ID（自动） | id | ClosureUnit.id | 服务端发号 `CU-\d{4,}` |
| 意图 | intent_id | ClosureUnit.intent_id | FK Intent，须先存在（否则 422） |
| 能力 | capability_id | ClosureUnit.capability | FK CapabilityEntity |
| 上下文资产 | context_asset_id | ContextAsset.ClosureUnit_id | FK ContextAsset，可空（DRAFT） |
| 动作类型 | action_type_ids[] | ActionType.ClosureUnit_id | FK ActionType，可多选 |
| 证据 | evidence_ids[] | EvidenceEntity.ClosureUnit_id | FK EvidenceEntity，可多选 |
| 责任人 | accountability.responsible_person_id | AccountabilityLink.responsible_person | **必填**，FK Person（R-GOV-03；缺→422，DB NOT NULL 兜底） |
| 责任范围 | accountability.role | AccountabilityLink.responsibility_scope | 必填 |
| 状态 | state | ClosureUnit.state | 枚举 ClosureState 九值 |
| 决断时距 | decision_timespan | ClosureUnit.decision_timespan | ISO 8601 duration（PT8H/P1D） |
| 信任标签 | trust_level | ClosureUnit.trust_level | T0/T1/T2 |

### W2 审批 → `POST /authorizations`

| 飞书审批字段 | LinkML 槽位 / API 字段 | 目标表.列 | 约束 |
|---|---|---|---|
| 审批单号（自动） | id | Authorization.id | `AUT-\d{4,}` |
| 授权范围 | scope[] | Authorization_scope.scope | ≥1 项（R-POL-02） |
| 预算币种/上限/周期 | budget.currency / amount_cap / period | Budget 三列 | 三者必填（R-POOL-BUDGET） |
| 决断时距 | decision_timespan | Authorization.decision_timespan | 必填 |
| 授权人 | granted_by | Authorization.granted_by | FK Person；须与审批实际通过人一致（R-SEC-04） |
| 被授权执行体 | granted_executor | Authorization.granted_executor | FK CapabilityEntity |
| 自治等级 | autonomy_level | Authorization.autonomy_level | L0–L5 |
| 生效/失效 | valid_from / valid_until | 同名列 | 失效后授权不可引用（R-POL-02 重验，谓词强制在 OPA 层） |

### W3 S5 队列 ↔ 决策卡（R-GOV-04 固定结构）

| 卡片消息区 / 按钮 | LinkML 槽位 / API 字段 | 目标表.列 | 约束 |
|---|---|---|---|
| 卡片ID | id | S5DecisionCard.id | `DC-\d{4,}` |
| 决策对象 | object | S5DecisionCard.decision_object | 必填 |
| 支撑证据 | evidence[] | S5DecisionCard_evidence_refs | 必填字段（可空列表） |
| 候选项 | options[].label / tradeoff | DecisionOption 两列 | ≥1 项 |
| 推荐 | recommendation | S5DecisionCard.recommendation | 必填 |
| 期限 | deadline | S5DecisionCard.deadline | 必填；超期按 R-GOV-07 安全默认 |
| 批准后果 | consequences | S5DecisionCard.approval_consequences | 必填 |
| 发给谁 | addressee | cp_decision_addressee.addressee | 必填；resolve 鉴权锚点 |
| 【按钮】批准/驳回回调 | — | `POST /decisions/{id}/resolve` | 头 `X-S5-Person` ← 飞书 user_id 经 Person 映射；**≠addressee → 403（R-SEC-04）**。飞书 user_id ↔ Person.id 对照表 = 接入时新增的前置数据 |
| 裁决回执 | decision/decided_by/decided_at | S5DecisionCard 后两列 | 已裁决再回调 → 409 |

### W4 资产目录（只读投影）← `GET /closures`、`GET /authorizations`

| 目录列 | 来源 | 说明 |
|---|---|---|
| 闭环清单/状态 | GET /closures?state= | state 九枚举直接投影 |
| 责任人 | GET /closures/{id} 的 accountability_* | 具名的人，不含 agent（责任守恒律） |
| 授权台账 | GET /authorizations | scope/预算/时距/有效期 |
| 服务健康 | GET /healthz | 表数/版本（池健康度量 M2 起并入） |

## 接入前置条件清单（凭据就位前不动手）

1. **飞书开放平台应用**：自建应用 app_id/app_secret；启用机器人能力（W3 卡片）+
   多维表格 + 审批 API 权限。凭据落 OpenBao（R-SEC-02：控制面仅存引用
   `openbao://secret/dga/feishu`），不入 Git。
2. **权限 scope 清单**（最小集）：`bitable:app`（读写登记/目录表）、
   `approval:approval`（W2 实例读写）、`im:message` 与 `im:message:send_as_bot`
   （W3 卡片推送）、事件订阅回调（approval 通过事件、卡片按钮回调）的加签
   encrypt key/verification token。
3. **身份对照表**：飞书 user_id ↔ `Person.id`（PSN-xxxx）双向映射——W3 的
   X-S5-Person 与 W2 的 granted_by 都从这里取值；无对照则 403/422（不得默认放行）。
4. **回调入口**：公网可达 HTTPS 回调地址（服务器阶段；本机开发期以轮询
   `GET /decisions/queue` 变通）。
5. **写路径纪律**：一切落库经控制面 API（R-GOV-01 单一主写者）；飞书表格仅投影
   与发起，禁止成为权威源（CMP-15）。
6. **待 S5 追认**：W2 是否用飞书审批流承载授权签发的合规性（审批记录≠签发记录，
   签发记录权威源在控制面 DB，R-EVID-01）。

## 诚实边界

本文件是设计占位，不包含任何"已接入"声明；四工作台的端到端验收（含
X-S5-Person 的真实身份链）随服务器部署阶段（M6+）与凭据申请进度实施。
