---
taskId: IR-0001
specVersion: 1
title: agent 自治生产系统（意图→实现闭环）
irRef: plan/IR-0001.md（签署 2026-08-20，正式 issue #128（本文件即其 spec PR））
acceptanceCriteria:
  - id: AC-1
    given: 任一仓存在已登记的 IR issue
    when: owner 打 state:ir-signed 标签（或评论 /start）
    then: 10 分钟内 spec-author 阶段启动，spec PR 自动出现且过 g010；失败则在 issue 评论原因
    observability: e2e
  - id: AC-2
    given: 一个含 state:ready 卡的产品仓
    when: 陌生 coding agent 打开该仓并仅阅读 AGENTS.md
    then: 它能找到找活命令、认领该卡、开工并提交 PR
    observability: e2e
  - id: AC-3
    given: 一张进入 implement 阶段的卡
    when: 检查该卡分支的 git 历史
    then: 测试 commit 早于实现 commit，且新测试在实现前全部红
    observability: api
  - id: AC-4
    given: 已合并锁定的验收测试
    when: 任何非 owner 身份的 PR 改动锁定路径
    then: g060 以 exit 2 阻断并升级；owner 经 spec 变更流程可解锁
    observability: e2e
  - id: AC-5
    given: 一套故意写弱的验收套件（存在可钻的洞）
    when: 恶意合规 adversary 攻击该套件
    then: 它产出通过全部测试的退化实现，check 判"套件不充分"并 blocking
    observability: api
  - id: AC-6
    given: verdict 阶段运行
    when: 揭封 holdout 并执行
    then: PR check 只显示通过计数；详情写入 holdout 仓；实现阶段日志审计无 holdout 内容
    observability: api
  - id: AC-7
    given: 一个故意脏的 PR（高复杂度函数/浅模块/跨层依赖/eslint-disable）
    when: 整洁关卡运行
    then: 各违规被对应关卡逐条拦下且每条带 fixHint；修复后同一 PR 全绿
    observability: e2e
  - id: AC-8
    given: verdict 通过且 riskScore 低于 contract.yaml 的 ceiling
    when: PR 全部 blocking check 绿
    then: 系统以 App 身份 squash auto-merge，无 LLM 参与合并判定
    observability: e2e
  - id: AC-9
    given: 同一关卡在同一任务上连续失败
    when: 达到 contract.yaml 的 sameGateFailureLimit
    then: 回滚到最后绿点、PR/issue 打 needs-human 并 assign owner
    observability: api
  - id: AC-10
    given: 系统运行若干周
    when: 审计 baseline.json 历史
    then: 全仓指标单调改善（棘轮方向），且阈值只存在于 quality/contract.yaml 一处
    observability: api
nonGoals:
  - 不引入多 agent 框架；git+文件+Actions 即编排底座
  - LLM 无合并判定/approve 权；绝大多数 PR 维持自动合并
  - 第一期不新建常驻 LLM 服务器（直连 provider API，见 DECISION-01）
  - 不追求全仓 100% 覆盖；diff 上严、全仓棘轮
  - 不启用 Projects v2（与 BP-4 仓基线一致）
blastRadius:
  - "Cloudbird-Software/.github: .github/workflows/**, .github/ISSUE_TEMPLATE/**, governance/**, specs/**"
  - "Cloudbird-Software/CI-Workflows: .github/workflows/**"
  - "Cloudbird-Software/agent-registry: decisions/**（AR-3 修订 ADR）"
  - "Cloudbird-Software/template-service 及全部 L2 产品仓: quality/**, Makefile, AGENTS.md, tests/**, .github/workflows/**"
apiDelta: { public: true, file: specs/IR-0001/api-delta.md }
dataMigration: false
rollback: "全部设施新增式落地；删除 conductor workflow 与 state 标签即整体停用，现有 rulesets 语义不变"
---

# Spec IR-0001：条款

> 只含 INV/BEH/IFACE/BUDGET/DECISION/ASSUMPTION/NONGOAL 七类条款。设计细节不进本文，进 ADR。

## INV 不变量（每条绑定可执行断言）

- INV-01 合并决策仅由确定性脚本做出。断言：auto-merge 触发链路（conductor/verdict workflow）静态扫描无 LLM 调用步骤；riskScore 计算为纯脚本。
- INV-02 `state:*` 标签只能由 owner 或 conductor workflow 设置。断言：conductor 校验事件 sender ∈ {owner, app/cloudbrid-agent}，否则回退标签并评论。
- INV-03 验收测试 commit 先于实现 commit 且实现前为红；合并后锁定路径 sha256 记入 quality/locks.json；任何身份（含 bypassPermissions 的 agent）写锁定路径必被 g060 以 exit 2 阻断。例外仅：commit trailer 含 `Spec-Change: <TASK> vN->vM` 且 specVersion 已递增。
- INV-04 每阶段全新冷上下文，阶段间只经 git/artifact 通信；holdout 内容不得出现在 planner/implementer 的输入与 workflow 日志。断言：阶段产物 hash 落盘；日志正则审计。
- INV-05 凡可判定的整洁规则只以关卡形式存在。断言：仓库 lint 扫描 AGENTS.md/CLAUDE.md 出现可判定规则（阈值数字/禁用 API 清单）即 fail；两文件各 ≤100 行（CLAUDE.md）/≤30 行（AGENTS.md，对齐 CG-1）。
- INV-06 模型调用凭据只存 org secret（`LLM_API_KEY`），仓库与 agent 配置零明文 key；一切 LLM 调用经计量 wrapper（落盘 model/prompt版本/采样参数/用量）。断言：gitleaks + 调用点静态扫描（直连 SDK 裸调用即 fail）。注：本条是 AR-3 修订后的第一期形态，正式化依赖 DECISION-01 的 ADR。
- INV-07 每任务 token/美元/墙钟三重预算；任一触顶回滚最后绿点并升级。断言：wrapper 计量记录存在；预算字段过 schema。

## BEH 行为（EARS）

- BEH-01 When IR issue 被打 `state:ir-signed`（或 owner 评论 `/start`），conductor shall 在 10 分钟内启动 spec-author 阶段，在目标仓开 spec PR；启动失败 shall 在原 issue 评论原因。
- BEH-02 When spec PR 合并，conductor shall 依次启动分歧度量与恶意合规红队，结果作为该 spec 后续卡工作的 blocking 前置。
- BEH-03 When 红队全过，wave-planner shall 开出卡 issues：每卡含 AC 表（Given-When-Then + observability）、blastRadius 预测文件集、依赖卡编号、预算；以 tasklist 挂到 spec issue。
- BEH-04 When 卡的前置卡全部合并，conductor shall 将其置 `state:ready`。
- BEH-05 When 卡 PR 打开，gate workflow shall 解析 PR body 卡元数据，自动选中该卡 AC 对应测试集运行（required workflow 不用 paths 过滤，内部选择）。
- BEH-06 If 关卡失败，系统 shall 按 gate report 的 ownerRole 路由修复角色；同一关卡失败达上限 → 回滚最后绿点 + `needs-human` + assign owner。
- BEH-07 When verdict 通过且 riskScore < ceiling，系统 shall 以 cloudbrid-agent 身份 squash auto-merge；否则推 quarantine 分支 + `needs-human`。
- BEH-08 When 本地 agent 打开任一产品仓，AGENTS.md shall 提供找活三命令（查 ready 卡/认领/跑关卡），agent 无需人类转述即可开工。
- BEH-09 When 任一阶段产物落盘，系统 shall 记录 model/prompt 版本/采样参数/产物 hash（过程确定性，可重放）。

## IFACE 契约

- IFACE-01 IR issue form 字段 ≡ IR schema v1（job/触发场景/痛点证据/期望可观察变化/非目标/约束/验收证据/可逆性偏好/质量速度旋钮）。
- IFACE-02 spec.md frontmatter 过 `spec.schema.json`（本文件即其非正规实例；正规 schema 在 W1-C1 交付）。
- IFACE-03 转移表 `governance/transitions.yaml` schema：`{from_state, event, to_state, action, guard}`；conductor 只解释不内嵌逻辑。
- IFACE-04 关卡统一 CLI 契约：env `GATE_*`、exit 0/1/2/3、report 过 `gate-report.schema.json`（引用 issue #127 §3，逐字采用）。
- IFACE-05 测试↔AC 绑定：Python 仓 `pytest` marker `ac("AC-n")`；TS 仓测试标题前缀 `[AC-n]`；g160 断言每条 AC ≥1 个通过的绑定测试。
- IFACE-06 模型角色映射语义（对齐 registry/models.yaml 的分层与 AR-8 族级独立）：spec-author/test-author → reviewer 档；implementer/refactorer → coder-fast 档；恶意合规/对抗 → judge-deep 档（必须独立于 builder/test-author 模型族）；分歧度量 → k=5 跨族混编（各族至少 1 路）。第一期的"档 → 具体 provider 模型名 + 采样参数"解析表落 `pipeline/models.yaml`（版本化、过 schema、改动走 PR）；gateway 启用后改由 gateway alias 解析，本表退役。
- IFACE-07 holdout 条目 schema：`{id, ir_ref|ac_ref, type: golden-scenario|trajectory, payload, sealed_sha256, created_at}`；揭封事件 append-only 记录。
- IFACE-08 本地封装命令（每产品仓 Makefile）：`make card-test CARD=<id>` / `make gates-fast` / `make gates-pr`——agent 与 CI 跑同一编排器入口。

## BUDGET 预算（数字，唯一来源 quality/contract.yaml）

- BUDGET-01 perTask：usd 12 / tokens 3M / wallClock 90min；perStage contextTokens ≤150K、maxAttempts 3。
- BUDGET-02 PR 关卡总时长 ≤8min；hook 快关 ≤15s；nightly ≤120min。
- BUDGET-03 Actions 分钟：本期不设上限；cost-check 既有 20000 分钟预算与 AUTO_MERGE_DISABLED 熔断参数相应调整（走 C1 变更）。
- BUDGET-04 LLM token：第一期只计量不熔断，由调用 wrapper 逐次落盘 artifact（供后续预算化）。
- BUDGET-05 单次 agent 调用 prompt ≤2KB；violations 每批 ≤20 条（#127 §6.2）。

## DECISION（含理由与可逆性）

- DECISION-01 第一期模型接入直连 provider API（org secret `LLM_API_KEY` + 计量 wrapper），不使用 llm-gateway。理由：gateway（LiteLLM，ADR-0002）必须常驻一台机器（VPS/家用机），GitHub 内无免费托管持久服务的途径，owner 裁定运维成本大于第一期收益。后果：违反 AR-3 字面（provider key 应仅存 gateway secret store）——须以 ADR 修订 AR-3 的第一期形态（草案随本 spec：`specs/IR-0001/ADR-draft-ar3-phase1-direct-api.md`，正式落到 agent-registry/decisions/ 后本条生效）。回切触发条件（任一满足即重启 gateway 评估）：需要 per-team 配额 / 多 provider failover / 按角色成本归账。可逆：是（换调用端点即切回）。
- DECISION-02 holdout 仓为公开仓（owner 已裁：agent 读公开仓是不确定风险，私有化的运维是确定支出）。隔离机制 = cloudbrid-agent 不安装到该仓 + 揭封凭据仅 verdict workflow 可用 + 日志计数化。可逆：转为私有只需一次仓设置变更 + ADR。
- DECISION-03 自动合并为常态（owner 已裁）：riskScoreCeiling 初始值在 contract.yaml 设定，按 #127 P3 的"零逃逸则渐升"机制演进，而非人工审批常态化。可逆：改一个阈值。
- DECISION-04 状态机以 label 为载体，不建 Projects v2（对齐 BP-4 仓基线"projects 关"）。可逆：看板随时可加，纯展示层。
- DECISION-05 不新建编排仓：conductor 与 transitions.yaml 放 .github 仓、阶段可复用 workflow 放 CI-Workflows——路由规则即治理意图，接受每次变更走 C1（PR+ADR+owner-merge）的迭代成本，正好 dogfood ADR 流程。可逆：迁出即建仓流程。

## ASSUMPTION（每条绑定监控）

- ASSUMPTION-01 GitHub-hosted runner 可稳定访问 provider API 端点。监控：W0-C1 的连通性 check workflow，失败开 issue。
- ASSUMPTION-02 基建引导期 owner 会提供具备 .github 仓 contents/issues/PRs 写权限的凭据（或亲跑 bootstrap 脚本）。监控：本 spec 第一个执行动作即验证。
- ASSUMPTION-03 公开 holdout 被 agent 读取的概率低且影响可接受（DECISION-02 的另一半）。监控：holdout 失败率异常升高（实现疑似过拟合 holdout）时重估，转私有。

## NONGOAL

继承 frontmatter nonGoals 五条，不再重复。
