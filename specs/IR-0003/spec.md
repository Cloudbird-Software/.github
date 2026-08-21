---
taskId: IR-0003
specVersion: 1
title: 重订宪法（治理体系 v2）
irRef: "Cloudbird-Software/<repo>#3"
acceptanceCriteria:
  - id: AC-1
    given: 宪法 v2.2 文件已准备就绪
    when: 宪法文件合并入 `specs/IR-0003/`
    then: 经跨族红队挑战并提交报告
  - id: AC-2
    given: 旧 ADR 已迁移完成
    when: adr-required 关卡修改为查墓碑索引
    then: W1 全部卡合并后，干净容器陌生 agent 仅读 AGENTS.md 完成认领并开 PR
blastRadius:
  - repo: specs/IR-0003
    path: constitution.md
  - repo: adr
    path: archive
  - repo: 各仓库
    path: AGENTS.md
nonGoals:
  - 删除任何历史 ADR/记录
  - 建设训练管线/客户交付管线/多角色组织治理
  - 改变现行 rulesets 语义
---

## INV 不变量

### INV-1
治理体系必须从"散文 ADR + 期望状态脚本"重构为 IR/spec 宪法体系，以宪法 v2 为治理唯一真相源。

### INV-2
旧 ADR 必须归档但不删除，标明 active/superseded/archived 并迁移至 archive 仓保留墓碑索引。

## BEH 行为

### BEH-1
独立仲裁内核必须实现，确保判断不可压缩，LLM 永无合并权、approve 权和授权裁决权。

### BEH-2
管家层必须实现，包含账本、卫生、仲裁转介、预算、停滞和审计包六职，由唤醒矩阵驱动，且永远不自己醒来。

### BEH-3
统一入口协议必须实现，各仓 AGENTS.md 包含同一协议块，卡 issue 作为唯一工作凭证，agent 无需人类补提示词。

## IFACE 契约

### IFACE-1
验证三层梯必须实现：
- T1: 确定性关卡全景
- T2: 校准 verifier（LLM-as-a-Verifier 范式，持证上岗+校准+标注负债申报）
- T3: 指导层（品味残余）

### IFACE-2
硬谓词信任门必须实现，包含：
- 硬谓词白名单（缺证据=拒绝）
- shadow 域解锁（≥50 例一致且零逃逸）

### IFACE-3
状态可视化必须实现，包含：
- label 唯一真相源
- Project 只读投影板

## BUDGET 预算

### BUDGET-1
W1 各卡必须走 C1 流程（PR+ADR+owner-merge）。

### BUDGET-2
全部设施必须新增式可拆，确保可逆性。

## DECISION 决策

### DECISION-1
废除 spec v3 的 risk-score 标量与 ceiling 40，由 spec v4 修订。

### DECISION-2
判定物有效性必须宪法化，包含：
- 变异分数
- 负控制
- 跨族生成
- 每周种子缺陷演习
- holdout 泄漏诱饵

### DECISION-3
公共知识必须署名规则，凡引入的外部范式/工具/基准必须注明源头（可审计可追溯）。

## ASSUMPTION 假设

### ASSUMPTION-1
业务模式推论：agent 任务轨迹成为第四观测类。

### ASSUMPTION-2
archive 仓将升级为数据飞轮战略资产。

### ASSUMPTION-3
自训练模型与 provider 模型将参加同一入职考试。

### ASSUMPTION-4
FDE 交付将复用主流水线（现在不建）。
