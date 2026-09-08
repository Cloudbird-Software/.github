---
taskId: IR-0011
specVersion: 2
irRef: Cloudbird-Software/.github#524
adr: ADR-0110
acceptanceCriteria:
  - id: AC-1
    given: 治理仓 docs/agent/ 与 AGENTS.md
    when: agent 按意图选路
    then: AGENTS.md 角色表含 ROLE-CEO.md 链接且 ROLE-CEO.md 可读。运行时证据=本仓文件路径 docs/agent/ROLE-CEO.md + AGENTS.md 表格行（suite 断言，禁止 assert True）
  - id: AC-2
    given: ROLE-CEO.md
    when: 抽取身份与自治条款
    then: 含五元组表五行、L4、S5 六项独占、不可自我晋升、永不载责。运行时证据=suite 读文件断言（记录在 t14-spec-suite run 日志）
  - id: AC-3
    given: ADR-0110 已入 archive/adr 且 INDEX 有 number 110
    when: 治理变更引用
    then: spec/PR 引用 ADR-0110。运行时证据=archive 仓 adr/ADR-0110-*.md 在 main 或本 PR 链；org-adr-required check run
  - id: AC-4
    given: ADR-0085
    when: 读 ROLE-CEO
    then: 明文不复活声明式 team 注册表。运行时证据=suite 对「不复活」+「team」同文件共现的负向断言
nonGoals:
  - 不实现 Temporal/WorkSwarm 全量部署
  - 不代 owner 合并本 PR 以外的产品卡
  - 不把 CEO 做成责任终点
  - 不复活 agent-registry
  - 不在本 IR 授予 LLM approve/merge
blastRadius:
  - repo: Cloudbird-Software/.github
    path: docs/agent/ROLE-CEO.md
  - repo: Cloudbird-Software/.github
    path: AGENTS.md
  - repo: Cloudbird-Software/.github
    path: specs/IR-0011/
  - repo: Cloudbird-Software/archive
    path: adr/ADR-0110-role-ceo-l4-slot.md
---

# IR-0011 spec · ROLE-CEO 入治理仓

## 背景

IR-0011 已 owner 签署（#524 `/start`）。要把工作区草案登记为治理仓角色指引。

## 条款

- **INV-01** 角色槽可替换，填充物永不载责（AC-2）
- **INV-02** LLM 永无 GitHub approve（AC-3）
- **BEH-01** L4 日常自决，S5 六项独占必须升级（AC-2）
- **BEH-02** 建设顺序组织与基建先于资产（DEC-010，AC-4）
- **DECISION-01** 不复活声明式 team 注册表（ADR-0085，AC-4）

## 测试设计（ADR-0095 逐类）

| 类 | 决定 | 理由 |
|----|------|------|
| T-01 unit_property_golden | adopt | suite 断言 ROLE-CEO.md 必备标题、五元组表、禁令句 |
| T-02 race | reject | 无并发运行时 |
| T-03 泄漏 | adopt | suite 断言文件不含凭据前缀 |
| T-04 fuzz | reject | 纯文档 |
| T-05 文档示例 | reject | 无代码示例义务 |
| T-08 flaky | reject | 无 CI 时序 |
| T-09 差分 | reject | 非重写项目 |
| T-10 变异 | reject | 非代码模块 |
| T-12 diff 覆盖 | reject | 文档增量 |
| T-13 测试完整性 | adopt | 本表本身 |
| T-14 suite 门 | adopt | suite/ 非空且含真实断言 |
| T-15 意图回探 | adopt | AC 回链 IR 四条期望变化 |
| L-01 | reject | 本 IR 不交付 LLM 产品行为 |
| L-05 | reject | 无延迟 SLA |
| R-01 | reject | 非重写 |
| R-02 | reject | 非重写 |
| G-01 | reject | 无服务端点 |
| X-01 | reject | 不启用全局覆盖率 |

风险映射：条款缺失 → 治理漂移；假测试 → suite 必须读文件而非 assert True。负控制：仅有标题无五元组表的 ROLE 必须红；AC 缺 given/when/then 或「运行时证据」必须红。

## holdout 测试设计

封存场景（只引用 id，不写答案）：**CEO 试图自我授予 L5 或签署对外合同**。注册走 holdout 仓标准入口；本 spec 仅声明需要一条 `HO-CEO-NO-S5@pending` 级场景，由 verifier-app 后续编号。cloudbrid-agent 不挂载 holdout payload。

## 实现落盘契约（adversary 文件名白名单）

恶意合规实现只许单层文件名 `[A-Za-z0-9._-]`（禁目录前缀）：`spec.md`、`ROLE-CEO.md`、`AGENTS.md`。
`docs/agent/ROLE-CEO.md` 是治理仓正本路径，审计 impl 目录用扁平 `ROLE-CEO.md`。

## 非目标

见 frontmatter nonGoals。不复活 agent-registry。
