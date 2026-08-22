---
taskId: ISSUE-263
specVersion: 3
title: 卡绑定测试与红队守门制度
irRef: Cloudbird-Software/.github#263
amendments:
- rev: 2
  reason: 红队审计 insufficient（#263 评论链红队报告 R1）——IR 保真度丢失、blastRadius 结构失真、攻击面需向 spec 阶段重定义
- rev: 3
  reason: 红队审计 insufficient（#263 评论链红队报告 R2/R3，CNB 轮）——S5 错误路径守卫缺失（spec 路径缺 check 必须红、作废须转 insufficient、no-attempts 状态后果）、反摆拍断言逐 run 常驻化、REPOS.yaml 申报补登、ADR-0061 验证者 APP 通道修订
acceptanceCriteria:
- id: AC-1
  given: 组织默认 verifier 范式已写入 GOVERNANCE.yaml 与 testing.yaml（点名到文件）
  when: LLM 参与判定环节
  then: 采用开源 LLM-as-a-Verifier 实践（绝对细粒度 reward、criteria 分解、K 次重复评估、阈值 gate），输出结构化连续分；PPT 锦标赛仅作 best-of-N 选择层，胜率不得作为 gate 输入（负向断言）；运行时证据：一次真实判定的 CI 日志含 llm-verifier 实际调用记录、逐 criterion 连续分 JSON 与 token 消耗，日志由独立于 verifier 的采集组件写入，不接受"声明已写入"
- id: AC-2
  given: 红队 pipeline 判定环节
  when: 执行判定
  then: 使用 llm-verifier 连续分 + 阈值产出 verdict；报告中的每条证据引用由代码对运行时刻真实工件做字符串级机械核对；任一引用被核对作废时该报告 verdict 强制转 insufficient（作废是判定不是记录）；golden 样本含未公开隐藏项且须对未见过的随机捏造引用泛化作废；golden 回归纳入 CI 常驻 required check（非一次性验收）；运行时证据：作废后判定链被拒的真实记录
- id: AC-3
  given: 实现 PR 绑定卡
  when: PR 提交
  then: 自动走卡对应测试集与已注册 holdout 测试，且必须通过才能合并；测试集非空且含有效断言，且测试先于实现首次运行为红（fail-before，ADR-0061）；运行时证据：缺测试 PR、空测试集 PR、holdout hash 不匹配 PR 三类互异失败源的真实 CI 红记录
- id: AC-4
  given: specs/** 路径的 PR
  when: 提交变更
  then: 必须经红队审计并作为合并阻断项，语义审计 verdict=insufficient 时机器阻断；spec 路径 PR 缺失 adversary check（漏配/被摘除/被跳过）时 CI 必须红（负向断言）；运行时证据：用故意极差 spec 触发真实 insufficient 的端到端记录 + 故意移除 adversary check 的 PR 被阻断的红记录
- id: AC-5
  given: 红队执行意图层探索
  when: 每次 run
  then: 产出探索留痕（读过的工件清单 + 显式"本轮是否发现 S6-S8"字段）；发现 S6-S8 问题时带证据报人裁决，不产生阻断性判定，证据须经 AC-9 机械核对；无产出不得静默绿，按 AC-15 空报告分支处理
- id: AC-6
  given: 红队 AI 运行
  when: 在沙箱中执行
  then: 以 GitHub Actions job 形态存在，配置面恰为 1 个 org secret + 1 个 org variable；配置面膨胀（出现第 2 个 secret 或额外凭据）时 job 判红（负向断言）；运行时证据：Action run 日志含 LLM API 真实请求与代码库探索操作日志，空壳 job（echo survived）不满足
- id: AC-7
  given: LLM-as-a-Verifier 范式实施
  when: 执行判定
  then: CI 日志包含 llm-verifier 实际调用记录、逐 criterion 连续分 JSON 与 token 消耗；运行时证据：对一次真实 run 的日志做独立抽查，确认调用记录非 verifier 自报
- id: AC-8
  given: 阈值 gate 实施
  when: 使用含已知不合格样本的 golden set
  then: 故意构造的低分样本触发 gate 失败；阈值随 criteria 文件版本化，标定记录留档（标定 SHA、golden 版本、定标时间机器可查）；golden set 每次 run 全量重放并含回归断言（不合格样本仍不合格）；用非 golden 的随机低分样本反特判；不合格样本构造方法独立于判定脚本代码；运行时证据：上述反向测试日志
- id: AC-9
  given: 证据核对机制实施
  when: 红队/verifier 报告生成
  then: 每条引用由代码对运行时刻真实工件做字符串级机械匹配，基准版本（SHA/抓取时间）在 run 开始时动态获取并写入报告，基准获取失败/为空时该条核对判不通过并阻断；核对不通过的命中作废并记录；核对所依据的工件快照随报告持久化归档（事后可重放，杜绝验过即焚）；运行时证据：含已知捏造引用样本的作废实测全部命中
- id: AC-10
  given: endpoint 三探测校验制度化
  when: 每次 verifier run 前探测 endpoint（防探测后动态降级）
  then: 检测 logprobs 有无、top_logprobs 上限、prefill/structured_outputs 支持，结果决定打分抽取路径与精度预期并写入报告；不满足最低要求的 endpoint 配置即失败；探测本身失败/超时不得误判为通过；top_logprobs 截断造成的精度折损必须在 run 报告中声明；运行时证据：一个被拒 endpoint 的失败记录
- id: AC-11
  given: verifier token 成本管理
  when: 执行判定
  then: token 成本随 run 持久化并与 LLM 响应 usage 字段交叉核对，偏差超阈值时该 run 判定作废并转人工（非仅告警）；纳入 automation-limits.yaml 预算口径；K 与 pivots 为暴露的成本旋钮，降档须留痕且不得改动判定语义与阈值；运行时证据：一次真实 run 的 token 账落盘文件
- id: AC-12
  given: 状态机 T5/T6 实施
  when: spec PR 合并且 suite 就绪
  then: conductor 按 T5/T6 转移状态，adversary 经 repository_dispatch 自动触发；"suite 就绪"为确定性谓词（suite/ 存在且含非空测试文件且可解析）；repository_dispatch 的 event_type 白名单精确匹配，T5/T6 全部前置条件由 conductor 侧重新断言（不信任 dispatch 载荷）；进入 wave-planned 必须存在对应的 survived 审计记录；前置不满足或 dispatch 未触发时转移拒绝并告警；运行时证据：状态变更记录 + needs-human 不可直跳 wave-planned 的自动化断言在 CI 强制运行
- id: AC-13
  given: 红队沙箱运行
  when: 执行红队任务
  then: Actions job 内 checkout 完整代码库 + sparse-checkout 治理规范，配置面恰为 1 org secret + 1 org variable；运行时证据：配置面查询结果（key 不可见）+ 沙箱内探索日志
- id: AC-14
  given: Veto 强制力实施
  when: 红队审计 verdict=insufficient
  then: state 变为 needs-human 且无法进入 wave-planned；specs/** 路径 PR 必须包含 adversary check；开发实现路径 PR 按 EXPECTED_SKIP 模式条件化豁免——豁免谓词由 diff 路径集确定性派生（禁止人工打标），与 ADR-0032 登记豁免制一致（豁免须登记、其余非 success 一律红）；含 specs/** 变更却试图走豁免的 PR 必须红（反向断言）；运行时证据：开发路径 PR 无 adversary check 仍正常合并的对照记录 + 伪装豁免被阻断的红记录
- id: AC-15
  given: 红队 run 执行
  when: run 失败、无产出或 no-attempts 白卷
  then: 有界重试≤2 次（重试计数以不可篡改的 run ID 序列工件为准，不依赖可写状态）后自动开特定标签 issue、停止规划 agent 相关产出并提醒人类；产物报告须通过结构化 JSON schema 校验，空报告/不合 schema 按失败同等处理；no-attempts/空报告 run 之后该卡锁定 needs-human、不得进入 wave-planned（白卷不得视为红队已通过）；运行时证据：failure 与空报告两种形态的自动开 issue 实测记录 + 白卷后状态锁定记录
- id: AC-16
  given: 意图兜底道闸 S6-S8 实施
  when: 每张卡
  then: 道闸每卡实跑并留痕（无命中也产出"无命中"落盘记录，区别于未运行）；S6-S8 入 attack-strategies.yaml（标 requires_explore），只报人不阻断；S8（blastRadius 集合比对）为确定性脚本——可脱离 LLM 独立运行且结果可复现（独立性自成一条，不与机械核对耦合），脚本崩溃或两次运行结果不一致时告警；命中带 file:line 且经 AC-9 机械核对；#263 dogfood 三条有效命中（专用 APP vs AG-1、每 PR 审计 vs ADR-0067 频率、holdout 强制 vs DECISION-02 隔离）作为首批实跑记录存档；运行时证据：对一张已知含 S6 重复问题的卡产出含 file:line 的评论 + 一张无问题卡的"无命中"落盘记录
- id: AC-17
  given: T-14 条款实施
  when: spec PR 或实现 PR 提交
  then: spec PR 必须含 suite/（至少一个非空测试文件且含有效断言），缺失即合并阻断（显式负向断言）；实现 PR 带卡必须跑卡对应测试 + 已注册 holdout 测试且通过；holdout 注册主体为验证者 APP（可挂载 holdout 仓），机器校验 PR 引用的 holdout hash 与已注册记录一致；非验证者 APP 写入 holdout 内容被拒（覆盖跨仓场景）；运行时证据：缺 suite/ 的 spec PR 被阻断的红记录 + 跨仓写入被拒的 403 记录
- id: AC-18
  given: 验证者 APP 设立
  when: 测试相关内容修改
  then: CODEOWNER = 验证者 APP + 人类，开发 agent 修改测试被拒；g060 等价关卡落地治理仓（specs/*/suite/** 按 IR 分片锁定），非验证者 APP/owner 改测试 exit 2 且自动开 issue 路由 owner 裁决（裁决闭环：TTL 内处置 + dead-man 提醒）；ADR-0061 同步修订以为验证者 APP 定义合法写豁免通道；运行时证据：验证者 APP 安装与权限范围查询记录；开发 APP 有效授权令牌改测试被拒的 403 日志（覆盖治理仓与 holdout 仓两场景）；真实 exit 2 阻断日志 + 阻断后自动开 issue 的记录
- id: AC-19
  given: 条款入册
  when: 本 spec 实施
  then: testing.yaml 新增 T-14（card_bound_test_required）与 T-15（intent_backstop），GOVERNANCE.yaml agent_runtime 新增 AR-10（red_team_veto），REPOS.yaml key_paths 补登 .github 的 specs/ 与 CI-Workflows 的 pipeline/（GM-4 申报）；新条款必须被至少一处执行逻辑引用（死条款判失败）；运行时证据：条款 diff + 机器检查读取新条款的实测（执行层恒绿不算）
- id: AC-20
  given: 一张真实卡
  when: 走完完整流程
  then: 从 ir-signed→spec→redteam→（Veto 一次→修复→survived）→wave-planned→认领→PR 绑定卡测试→合并全程；Veto 理由与修复 diff 经机械核对证明修复确实回应了该理由；"Veto 过一次"不构成可复用资历，每卡红队守门相互独立；运行时证据：全程 issue 时间线 + 各 check run 链接链
blastRadius:
- repo: .github
  path: governance/transitions.yaml
- repo: .github
  path: governance/policy/testing.yaml
- repo: .github
  path: governance/policy/automation-limits.yaml
- repo: .github
  path: governance/GOVERNANCE.yaml
- repo: .github
  path: governance/REPOS.yaml
- repo: .github
  path: governance/rulesets/main-protection.json
- repo: .github
  path: governance/rulesets/org-required-workflows.json
- repo: .github
  path: .github/workflows/conductor.yml
- repo: .github
  path: specs/**
- repo: CI-Workflows
  path: .github/workflows/adversary*.yml
- repo: CI-Workflows
  path: pipeline/adversary/**
- repo: template-service
  path: .github/workflows/ci.yml
- repo: template-service
  path: AGENTS.md
- repo: archive
  path: adr/**（ADR-0067 修订、ADR-0061 修订、ADR-0056 DECISION-02 修订、AG-1 修订 ADR、新增红队守门 ADR）
nonGoals:
- 不自研 LLM 验证/打分框架
- 不把 PPT 锦标赛排名分当作判定信号
- 不把意图探索（S6-S8）做成 Verify 工作或阻断关卡
- 不再设第三个 App 身份
- 开发实现路径 PR 不强制红队审计
- 不做运维安全红队
- 不改 verifier-exam 入职考试机制
- 不替换现有 gate / org-gate 结构
- 不赋予红队任何写权限
- 不在本 IR 内重建 template-service 全套 quality 体系（仅 ci.yml 与 AGENTS.md 两处适配）
- 不要求红队/verifier 与实现 agent 使用同一模型
---

## INV 不变量

### INV-01
- **LLM 判定范式**：任何 LLM 参与判定的环节必须采用开源 LLM-as-a-Verifier 实践，包含绝对细粒度 reward、criteria 分解、K 次重复评估和阈值 gate，输出结构化连续分，不接受散文结论；PPT 胜率不得作为 gate 输入。

### INV-02
- **状态写权**：跨仓触发与 check 写回一律经 App 令牌（单仓作用域、1h 过期），GITHUB_TOKEN 不持有状态写权；验证者 APP 令牌同样单仓作用域、仅测试/验证路径写权。

### INV-03
- **证据核对铁律**：核对由代码执行、基准为运行时刻真实工件、基准版本写入报告；裁判（人或 LLM）凭记忆/转述比对一律无效。

### INV-04
- **反摆拍常驻**：关键反摆拍断言（golden 回归、无绕过转移断言、机械核对、配置面校验）逐 run 常驻 CI，非一次性验收动作；一次性演示不构成合规证据。

## BEH 行为

### BEH-01
- **红队守门流程**：红队审计覆盖意图→spec→测试设计路径，该路径每个 PR 都必须经红队审计并作为合并阻断项；语义审计 verdict=insufficient 时机器阻断，survived 才放行。

### BEH-02
- **红队沙箱边界**：红队 AI 以 GitHub Actions job 形态存在，沙箱内直接完成代码库探索；harden-runner 出向白名单限制；job 内凭据仅 org secret 注入的 LLM_API_KEY；一次性 runner，产物判定后即焚。

### BEH-03
- **卡绑定测试流程**：开卡必须挂钩验收测试；实现 PR 绑定卡后自动走卡对应测试集与已注册 holdout 测试（合并阻断）。

### BEH-04
- **意图探索道闸**：红队顺带做意图层探索（S6 重复已有功能 / S7 违反治理约束 / S8 越出 blastRadius），不产生阻断性判定，命中带证据报人裁决。

## IFACE 契约

### IFACE-01
- **验证者 APP 接口**：新设验证者专用 GitHub App，测试相关内容（suite/、holdout、卡测试）的 CODEOWNER = 验证者 APP + 人类，防止开发 agent 经既有 APP 修改测试。**时序约束：AG-1 修订 ADR 合并前，验证者 APP 不得实施。**

### IFACE-02
- **LLM endpoint 接口**：endpoint 必须支持三探测（logprobs 有无、top_logprobs 上限、prefill/structured_outputs 支持），探测结果决定打分抽取路径与精度预期并写入报告；探测在每次 verifier run 前执行。

## BUDGET 预算

### BUDGET-01
- **LLM token 成本**：verifier token 成本随 run 持久化并与 usage 字段交叉核对（偏差超阈值 run 作废转人工），纳入 automation-limits.yaml 预算口径；K 与 pivots 为暴露的成本旋钮，降档留痕且不动判定语义与阈值。

## DECISION 决策

### DECISION-01
- **身份管理**：AG-1 修订为"开发身份唯一（cloudbrid-agent）+ 验证者身份独立（新设验证者 APP，仅测试/验证路径写权）"——修订后目标文本即此句；验证者 APP 可挂载 holdout 仓。ADR 批次：AG-1 修订 ADR、ADR-0056 DECISION-02 修订、ADR-0061 修订（为验证者 APP 定义合法写豁免通道）随本 IR 首批 C1 PR 提交，合并前不实施验证者 APP。

### DECISION-02
- **红队守门范围**：红队聚焦意图→spec→测试设计路径；开发实现路径 PR 不走红队审计，只跑确定性测试与 holdout 测试。

### DECISION-03
- **可逆性设计**：红队 check 可从 required checks 摘除；T5/T6 可停用；意图道闸可整体关停；llm-verifier 实现可替换，但替换物必须仍满足默认范式四件套。

### DECISION-04
- **spec 阶段攻击面**：ADR-0067 的 S1–S5 攻击面针对代码实现；红队审计扩展到 spec/测试设计路径后，攻击面面向文本工件重定义（AC 可摆拍性 S1'–S5' + IR 保真度核对），随 ADR-0067 修订案一并落文。

### DECISION-05
- **证据链终点**：证据链终止于"独立采集组件 + endpoint usage 交叉核对 + 人类签收抽检"三层，不追求对证据的证据无限回溯；运行时证据防机器摆拍，人类抽检防证据摆拍（回应红队 S1' 元攻击）。

## ASSUMPTION 假设

### ASSUMPTION-01
- **治理合规**：遵守 GOVERNANCE.yaml 全部铁律；transitions.yaml / testing.yaml / GOVERNANCE.yaml / conductor / workflows 均为 C1 路径：PR + ADR + owner-merge。

### ASSUMPTION-02
- **语义审计不变**：语义审计维度不放宽 ADR-0067 判定语义：insufficient=blocking、survived=放行、no-attempts=infra 失败（有界重试后转 needs-human + 自动开 issue）。

### ASSUMPTION-03
- **质量优先**：红队 Veto、卡绑定测试、机械证据核对不接受降级；K 与 pivots 默认取保守高值。
