---
taskId: IR-0002
specVersion: 1
title: 区分「从未接入」与「接入后消失」的活体误报治理
irRef: "Cloudbird-Software/<repo>#<n>"
acceptanceCriteria:
  - id: AC-1
    given: drift-check §12 活体存在性检查运行
    when: 检查的仓库自 ADR-0046 ruleset 生效后无任何 PR/push 活动
    then: 该仓库被标记为"待接入"而非"裸奔窗口"
  - id: AC-2
    given: drift-check §12 活体存在性检查运行
    when: 检查的仓库曾有 org-gate check run 但近期消失
    then: 该仓库仍被标记为"裸奔窗口"并报警
  - id: AC-3
    given: drift-check §12 活体存在性检查运行
    when: 检查多个仓库
    then: 输出包含"待接入"计数的信息行
  - id: AC-4
    given: 人为构造 (b) 形态的仓库
    when: 提交新内容后检查活体存在性
    then: 仍正确报警且不受本变更影响
blastRadius:
  - repo: governance
    path: drift-check.sh
nonGoals:
  - 重构活体检测机制本身
  - 修改 org rulesets / required workflows 配置
  - 引入新仓级配置面
---

## INV 不变量

- INV-1: drift-check §12 必须能区分从未接入与接入后消失两种形态
- INV-2: 仅接入后消失(b)形态触发裸奔窗口报警
- INV-3: 从未接入(a)形态归入待接入清单
- INV-4: 不降低对(b)形态的检出灵敏度

## BEH 行为

- BEH-1: 当仓库自 ruleset 生效后无任何活动时，输出"待接入"状态
- BEH-2: 当仓库曾有 check run 但近期消失时，输出"裸奔窗口"报警
- BEH-3: 在 drift run 输出中包含"待接入"计数信息

## IFACE 契约

- IFACE-1: 输出格式必须保持与现有 drift-check.sh 兼容
- IFACE-2: 必须通过 expected-state.json 现有结构处理待接入状态

## BUDGET 预算

- BUDGET-1: 仅修改 drift-check.sh 中的活体检测逻辑部分
- BUDGET-2: 不引入新的外部依赖

## DECISION 决策

- DECISION-1: 采用保守策略，模糊形态归(b)报警
- DECISION-2: 不修改 ADR-0034 语义

## ASSUMPTION 假设

- ASSUMPTION-1: ADR-0046 ruleset 生效时间可准确获取
- ASSUMPTION-2: 仓库活动历史记录可访问
- ASSUMPTION-3: org-gate check run 历史记录可访问
