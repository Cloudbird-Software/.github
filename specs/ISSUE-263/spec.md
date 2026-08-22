---
taskId: ISSUE-263
specVersion: 2
title: 卡绑定测试与红队守门制度
irRef: Cloudbird-Software/.github#263
amendments:
- rev: 2
  reason: 红队审计 insufficient（#263 评论链红队报告，2026-08-22）——IR 保真度丢失（T-15/AR-10/g060 掉落、运行时证据条款未落 AC）、blastRadius 结构失真、攻击面需向 spec 阶段重定义
acceptanceCriteria:
- id: AC-1
  given: 组织默认 verifier 范式已写入 GOVERNANCE.yaml 与 testing.yaml（点名到文件）
  when: LLM 参与判定环节
  then: 采用开源 LLM-as-a-Verifier 实践（绝对细粒度 reward、criteria 分解、K 次重复评估、阈值 gate），输出结构化连续分；运行时证据：一次真实判定的 CI 日志含 llm-verifier 实际调用记录、逐 criterion 连续分 JSON 与 token 消耗，日志由独立于 verifier 的采集组件写入，不接受"声明已写入"
- id: AC-2
  given: 红队 pipeline 判定环节
  when: 执行判定
  then: 使用 llm-verifier 连续分 + 阈值产出 verdict；报告中的每条证据引用由代码对运行时刻真实工件做字符串级机械核对；运行时证据：核对脚本在含已知捏造引用的 golden 样本上实测，作废记录全部命中
- id: AC-3
  given: 实现 PR 绑定卡
  when: PR 提交
  then: 自动走卡对应测试集与已注册 holdout 测试，且必须通过才能合并；运行时证据：缺测试 PR 被阻断的真实 CI 红记录、holdout hash 不匹配被阻断的真实 CI 红记录
- id: AC-4
  given: specs/** 路径的 PR
  when: 提交变更
  then: 必须经红队审计并作为合并阻断项，语义审计 verdict=insufficient 时机器阻断；运行时证据：用故意极差 spec 触发真实 insufficient 的端到端记录（Veto 理由由红队 AI 真实产出，修复针对该理由后 survived）
- id: AC-5
  given: 红队执行意图层探索
  when: 发现 S6-S8 问题
  then: 带证据报人裁决，不产生阻断性判定；证据须经 AC-9 的机械核对
- id: AC-6
  given: 红队 AI 运行
  when: 在沙箱中执行
  then: 以 GitHub Actions job 形态存在，配置面恰为 1 个 org secret + 1 个 org variable；运行时证据：Action run 日志含 LLM API 真实请求与代码库探索操作日志，空壳 job（echo survived）不满足
- id: AC-7
  given: LLM-as-a-Verifier 范式实施
  when: 执行判定
  then: CI 日志包含 llm-verifier 实际调用记录、逐 criterion 连续分 JSON 与 token 消耗；运行时证据：对一次真实 run 的日志做独立抽查，确认调用记录非 verifier 自报
- id: AC-8
  given: 阈值 gate 实施
  when: 使用含已知不合格样本的 golden set
  then: 故意构造的低分样本触发 gate 失败；阈值随 criteria 文件版本化，标定记录留档；golden set 中不合格样本的构造方法必须独立于判定脚本代码（防串通）
- id: AC-9
  given: 证据核对机制实施
  when: 红队/verifier 报告生成
  then: 每条引用由代码对运行时刻真实工件做字符串级机械匹配，基准版本（SHA/抓取时间）在 run 开始时动态获取并写入报告；核对不通过的命中作废并记录；运行时证据：含已知捏造引用样本的作废实测全部命中
- id: AC-10
  given: endpoint 三探测校验制度化
  when: 探测 endpoint
  then: 检测 logprobs 有无、top_logprobs 上限、prefill/structured_outputs 支持，结果决定打分抽取路径与精度预期并写入报告；不满足最低要求的 endpoint 配置即失败；运行时证据：一个被拒 endpoint 的失败记录
- id: AC-11
  given: verifier token 成本管理
  when: 执行判定
  then: token 成本随 run 持久化并与 LLM 响应 usage 字段交叉核对（偏差超阈值告警），纳入 automation-limits.yaml 预算口径；K 与 pivots 为暴露的成本旋钮；运行时证据：一次真实 run 的 token 账落盘文件
- id: AC-12
  given: 状态机 T5/T6 实施
  when: spec PR 合并且 suite 就绪
  then: conductor 按 T5/T6 转移状态，adversary 经 repository_dispatch 自动触发；运行时证据：conductor 按 T5/T6 路由真实卡的状态变更记录 + 证明 needs-human 不可直跳 wave-planned 的自动化断言在 CI 强制运行
- id: AC-13
  given: 红队沙箱运行
  when: 执行红队任务
  then: Actions job 内 checkout 完整代码库 + sparse-checkout 治理规范，配置面恰为 1 org secret + 1 org variable；运行时证据：配置面查询结果（key 不可见）+ 沙箱内探索日志
- id: AC-14
  given: Veto 强制力实施
  when: 红队审计 verdict=insufficient
  then: state 变为 needs-human 且无法进入 wave-planned；specs/** 路径 PR 必须包含 adversary check；开发实现路径 PR 按 EXPECTED_SKIP 模式条件化豁免（事件互补白名单，其余非 success 一律红）；运行时证据：开发路径 PR 无 adversary check 仍正常合并的对照记录
- id: AC-15
  given: 红队 run 执行
  when: run 失败、无产出或 no-attempts 白卷
  then: 有界重试≤2 次后自动开特定标签 issue、停止规划 agent 相关产出并提醒人类；Action success 但产物为空报告按失败同等处理；运行时证据：failure 与空报告两种形态的自动开 issue 实测记录
- id: AC-16
  given: 意图兜底道闸 S6-S8 实施
  when: 发现问题
  then: 入 attack-strategies.yaml（标 requires_explore），只报人不阻断；S8（blastRadius 集合比对）为确定性脚本——可脱离 LLM 独立运行且结果可复现；命中带 file:line 且经 AC-9 机械核对；运行时证据：对一张已知含 S6 重复问题的卡产出含 file:line 的评论
- id: AC-17
  given: T-14 条款实施
  when: spec PR 或实现 PR 提交
  then: spec PR 必须含 suite/；实现 PR 带卡必须跑卡对应测试 + 已注册 holdout 测试且通过；holdout 注册主体为验证者 APP（可挂载 holdout 仓），机器校验 PR 引用的 holdout hash 与已注册记录一致
- id: AC-18
  given: 验证者 APP 设立
  when: 测试相关内容修改
  then: CODEOWNER = 验证者 APP + 人类，开发 agent 修改测试被拒；g060 等价关卡落地治理仓（specs/*/suite/** 按 IR 分片锁定），非验证者 APP/owner 改测试 exit 2 且自动开 issue 路由 owner 裁决；运行时证据：开发 APP 令牌改测试被拒的 403 日志、真实 exit 2 阻断日志、阻断后自动开 issue 记录
- id: AC-19
  given: 条款入册
  when: 本 spec 实施
  then: testing.yaml 新增 T-14（card_bound_test_required）与 T-15（intent_backstop），GOVERNANCE.yaml agent_runtime 新增 AR-10（red_team_veto）；运行时证据：条款 diff + 机器检查读取新条款的实测（执行层恒绿不算）
- id: AC-20
  given: 一张真实卡
  when: 走完完整流程
  then: 从 ir-signed→spec→redteam→（Veto 一次→修复→survived）→wave-planned→认领→PR 绑定卡测试→合并全程；运行时证据：全程 issue 时间线 + 各 check run 链接链，Veto 与修复均为真实机器产物
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
  path: governance/rulesets/main-protection.json
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
  path: adr/**（ADR-0067 修订、ADR-0056 DECISION-02 修订、AG-1 修订 ADR、新增红队守门 ADR）
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
- **LLM 判定范式**：任何 LLM 参与判定的环节必须采用开源 LLM-as-a-Verifier 实践，包含绝对细粒度 reward、criteria 分解、K 次重复评估和阈值 gate，输出结构化连续分，不接受散文结论。

### INV-02
- **状态写权**：跨仓触发与 check 写回一律经 App 令牌（单仓作用域、1h 过期），GITHUB_TOKEN 不持有状态写权；验证者 APP 令牌同样单仓作用域、仅测试/验证路径写权。

### INV-03
- **证据核对铁律**：核对由代码执行、基准为运行时刻真实工件、基准版本写入报告；裁判（人或 LLM）凭记忆/转述比对一律无效。

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
- **LLM endpoint 接口**：endpoint 必须支持三探测（logprobs 有无、top_logprobs 上限、prefill/structured_outputs 支持），探测结果决定打分抽取路径与精度预期并写入报告。

## BUDGET 预算

### BUDGET-01
- **LLM token 成本**：verifier token 成本随 run 持久化并与 usage 字段交叉核对，纳入 automation-limits.yaml 预算口径；K 与 pivots 为暴露的成本旋钮。

## DECISION 决策

### DECISION-01
- **身份管理**：AG-1（身份唯一性）修订为"开发身份唯一 + 验证者身份独立"；验证者 APP 可挂载 holdout 仓。修订以 ADR 先行（AG-1 修订 ADR 与 ADR-0056 DECISION-02 修订 ADR 随本 IR 首批 C1 PR 提交），ADR 合并前不实施验证者 APP。

### DECISION-02
- **红队守门范围**：红队聚焦意图→spec→测试设计路径；开发实现路径 PR 不走红队审计，只跑确定性测试与 holdout 测试。

### DECISION-03
- **可逆性设计**：红队 check 可从 required checks 摘除；T5/T6 可停用；意图道闸可整体关停；llm-verifier 实现可替换，但替换物必须仍满足默认范式四件套。

### DECISION-04
- **spec 阶段攻击面**：ADR-0067 的 S1–S5 攻击面针对代码实现；红队审计扩展到 spec/测试设计路径后，攻击面面向文本工件重定义（AC 可摆拍性 S1'–S5' + IR 保真度核对），随 ADR-0067 修订案一并落文，作为红队在 spec 阶段的判定依据。

## ASSUMPTION 假设

### ASSUMPTION-01
- **治理合规**：遵守 GOVERNANCE.yaml 全部铁律；transitions.yaml / testing.yaml / GOVERNANCE.yaml / conductor / workflows 均为 C1 路径：PR + ADR + owner-merge。

### ASSUMPTION-02
- **语义审计不变**：语义审计维度不放宽 ADR-0067 判定语义：insufficient=blocking、survived=放行、no-attempts=infra 失败。

### ASSUMPTION-03
- **质量优先**：红队 Veto、卡绑定测试、机械证据核对不接受降级；K 与 pivots 默认取保守高值。
