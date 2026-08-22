---
taskId: ISSUE-263
specVersion: 1
title: 卡绑定测试与红队守门制度
irRef: Cloudbird-Software/.github#263
acceptanceCriteria:
- id: AC-1
  given: 组织默认 verifier 范式已写入治理文件
  when: LLM 参与判定环节
  then: 采用开源 LLM-as-a-Verifier 实践，包含绝对细粒度 reward、criteria 分解、K 次重复评估和阈值 gate，输出结构化连续分
- id: AC-2
  given: 红队 pipeline 判定环节
  when: 执行判定
  then: 使用 llm-verifier 连续分 + 阈值产出 verdict，报告中的每条证据引用由代码对运行时刻真实工件做字符串级机械核对
- id: AC-3
  given: 实现 PR 绑定卡
  when: PR 提交
  then: 自动走卡对应测试集与已注册 holdout 测试，且必须通过才能合并
- id: AC-4
  given: specs/** 路径的 PR
  when: 提交变更
  then: 必须经红队审计并作为合并阻断项，语义审计 verdict=insufficient 时机器阻断
- id: AC-5
  given: 红队执行意图层探索
  when: 发现 S6-S8 问题
  then: 带证据报人裁决，不产生阻断性判定
- id: AC-6
  given: 红队 AI 运行
  when: 在沙箱中执行
  then: 以 GitHub Actions job 形态存在，仅使用 org secret 和 org variable 进行配置
- id: AC-7
  given: LLM-as-a-Verifier 范式实施
  when: 执行判定
  then: CI 日志包含 llm-verifier 实际调用记录、逐 criterion 连续分 JSON 与 token 消耗
- id: AC-8
  given: 阈值 gate 实施
  when: 使用含已知不合格样本的 golden set
  then: 故意构造的低分样本触发 gate 失败，证明判定脚本进行数值比较
- id: AC-9
  given: 证据核对机制实施
  when: 红队/verifier 报告生成
  then: 每条引用由代码对运行时刻真实工件做字符串级机械匹配，基准版本写入报告
- id: AC-10
  given: endpoint 三探测校验制度化
  when: 探测 endpoint
  then: 检测 logprobs 有无、top_logprobs 上限、prefill/structured_outputs 支持，结果决定打分抽取路径
- id: AC-11
  given: verifier token 成本管理
  when: 执行判定
  then: token 成本随 run 持久化，纳入 automation-limits.yaml 预算口径
- id: AC-12
  given: 状态机 T5/T6 实施
  when: spec PR 合并且 suite 就绪
  then: conductor 按 T5/T6 转移状态，adversary 经 repository_dispatch 自动触发
- id: AC-13
  given: 红队沙箱运行
  when: 执行红队任务
  then: Actions job 内 checkout 完整代码库 + sparse-checkout 治理规范，仅使用 org secret 和 org variable
- id: AC-14
  given: Veto 强制力实施
  when: 红队审计 verdict=insufficient
  then: state 变为 needs-human 且无法进入 wave-planned，specs/** 路径 PR 必须包含 adversary check
- id: AC-15
  given: 红队 run 执行
  when: run 失败或无产出
  then: 自动开特定标签 issue、停止规划 agent 相关产出并提醒人类
- id: AC-16
  given: 意图兜底道闸 S6-S8 实施
  when: 发现问题
  then: 入 attack-strategies.yaml，只报人不阻断，S8 为确定性脚本，命中带 file:line
- id: AC-17
  given: T-14 条款实施
  when: spec PR 或实现 PR 提交
  then: spec PR 必须含 suite/，实现 PR 带卡必须跑卡对应测试 + 已注册 holdout 测试且通过
- id: AC-18
  given: 验证者 APP 设立
  when: 测试相关内容修改
  then: CODEOWNER = 验证者 APP + 人类，开发 agent 修改测试被拒
- id: AC-19
  given: 一张真实卡
  when: 走完完整流程
  then: 从 ir-signed→spec→redteam→(Veto 一次→修复→survived)→wave-planned→认领→PR 绑定卡测试→合并全程
blastRadius:
- repo: governance
  path: transitions.yaml
- repo: governance
  path: testing.yaml
- repo: governance
  path: GOVERNANCE.yaml
- repo: main-protection
  path: main-protection.json
- repo: adr
  path: ADR-0067
- repo: adr
  path: ADR-0061
- repo: specs
  path: '**'
- repo: template-service
  path: '**'
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
- 不在本 IR 内重建 template-service 全套 quality 体系
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
- **验证者 APP 接口**：新设验证者专用 GitHub App，测试相关内容（suite/、holdout、卡测试）的 CODEOWNER = 验证者 APP + 人类，防止开发 agent 经既有 APP 修改测试。

### IFACE-02
- **LLM endpoint 接口**：endpoint 必须支持三探测（logprobs 有无、top_logprobs 上限、prefill/structured_outputs 支持），探测结果决定打分抽取路径与精度预期。

## BUDGET 预算

### BUDGET-01
- **LLM token 成本**：verifier token 成本随 run 持久化，纳入 automation-limits.yaml 预算口径；K 与 pivots 为暴露的成本旋钮。

## DECISION 决策

### DECISION-01
- **身份管理**：AG-1（身份唯一性）修订为"开发身份唯一 + 验证者身份独立"；验证者 APP 可挂载 holdout 仓，随本 IR 以 ADR 修订 DECISION-02。

### DECISION-02
- **红队守门范围**：红队聚焦意图→spec→测试设计路径；开发实现路径 PR 不走红队审计，只跑确定性测试与 holdout 测试。

### DECISION-03
- **可逆性设计**：红队 check 可从 required checks 摘除；T5/T6 可停用；意图道闸可整体关停；llm-verifier 实现可替换，但替换物必须仍满足默认范式四件套。

## ASSUMPTION 假设

### ASSUMPTION-01
- **治理合规**：遵守 GOVERNANCE.yaml 全部铁律；transitions.yaml / testing.yaml / GOVERNANCE.yaml / conductor / workflows 均为 C1 路径：PR + ADR + owner-merge。

### ASSUMPTION-02
- **语义审计不变**：语义审计维度不放宽 ADR-0067 判定语义：insufficient=blocking、survived=放行、no-attempts=infra 失败。

### ASSUMPTION-03
- **质量优先**：红队 Veto、卡绑定测试、机械证据核对不接受降级；K 与 pivots 默认取保守高值。
