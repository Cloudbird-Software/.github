# AGENTS.md

AI agent 进入本仓的工作契约（索引型，CG-1；细节按需读引用文件，不常驻上下文）。

## 硬规则

- 治理文件（governance/ standards/ scripts/ .github/ CODEOWNERS profile/）= C1 路径：PR 必须引用 ADR-NNNN，owner-only review（GOVERNANCE flows.governance_change；与 gate adr-required 机器检查同路径集）
- agent 写仓库身份 = GitHub App `cloudbrid-agent`（AG-1）；令牌经 scripts/gh-app-token.sh，单仓作用域、1h 过期
- 本仓只读治理声明；ADR 与注册条目落盘 agent-registry（REPOS.yaml L1）
- 不引入新第三方 Action：白名单见 expected-state.json#actions_policy（CI-2）

## 常用命令

- 校验本仓声明：`.github/workflows/gate.yml`（本地等价：yaml/json 解析 + `bash -n` 各脚本）
- 漂移检测：`GH_TOKEN=<org admin> bash governance/drift-check.sh`（每日 CI 自动跑）
- 漂移修复：`GH_TOKEN=<org admin> bash governance/apply.sh`（幂等；失败 loud 退出）
- 新仓初始化：`bash scripts/new-repo-init.sh <name>`（失败 loud 退出）

## 索引

| 主题 | 文件 |
|---|---|
| 治理总声明（域/措施/流程） | governance/GOVERNANCE.yaml |
| 组织仓库地图 | governance/REPOS.yaml |
| 期望状态（漂移真源） | governance/expected-state.json |
| 语言/依赖政策 | governance/policy/languages.yaml |
| 测试政策 | governance/policy/testing.yaml |
| agent 标准 schema | standards/agent/*.schema.yaml |
| bot/agent 反馈通道规范（禁 review thread） | standards/automation/bot-channels.md |
| 原型 profiles / 注册条目 | Cloudbird-Software/agent-registry |
