# AGENTS.md

AI agent 进入本仓的工作契约（索引型，CG-1；细节按需读引用文件，不常驻上下文）。

## 硬规则

- 治理文件（governance/ standards/ scripts/ .github/ CODEOWNERS profile/）= C1 路径：PR 必须引用 ADR-NNNN，owner-only review（GOVERNANCE flows.governance_change；与 gate adr-required 机器检查同路径集）
- agent 写仓库身份 = GitHub App `cloudbrid-agent`（AG-1）；令牌经 scripts/gh-app-token.sh，单仓作用域、1h 过期
- 本仓只读治理声明；ADR 与注册条目落盘 agent-registry（REPOS.yaml L1）
- 不引入新第三方 Action：白名单见 expected-state.json#actions_policy（CI-2）
- 无人值守护栏（ADR-0040，跨仓生效）：(a) 每次任务派发与 `gh pr merge --auto` 前，必须检查 org 变量 `AUTO_MERGE_DISABLED`（`gh api /orgs/Cloudbird-Software/actions/variables/AUTO_MERGE_DISABLED --jq .value`，404=未置位）——置位即停一切派发与 automerge，禁止任何绕过尝试；(b) 同一 PR 的修红重试 ≤ policy/automation-limits.yaml `auto_fix.max_attempts`（默认 3），达上限即停手（auto-fix-limit workflow 会关 PR + 开 issue）；(c) 不得 reopen 带 `auto-fix-limit-exhausted` 标签的 PR；计数真源 = Checks API（commit 元数据），删标签/重开不重置计数；(d) 派发前确认 .github 仓无未决 `cost-infra`/`cost-circuit-breaker` issue（用量不可知时同样停）

## 常用命令

- 校验本仓声明：`.github/workflows/gate.yml`（本地等价：yaml/json 解析 + `bash -n` 各脚本）
- 漂移检测：`GH_TOKEN=<org admin> bash governance/drift-check.sh`（每日 CI 自动跑）
- 修复循环上限执法：`GH_TOKEN=<org admin> bash governance/auto-fix-limit.sh`（小时级 CI 自动跑；`AUTOFIX_DRY_RUN=1` 只报告）
- 成本熔断检查：`GH_TOKEN=<org admin> bash governance/cost-check.sh`（6h CI 自动跑；`COST_USAGE_MINUTES_OVERRIDE=<n>` 注入测试）
- 漂移修复：`GH_TOKEN=<org admin> bash governance/apply.sh`（幂等；失败 loud 退出）
- 新仓初始化：`bash scripts/new-repo-init.sh <name>`（失败 loud 退出）
- 取 App 令牌：`GH_TOKEN=$(scripts/ghcb <repo>)`（缓存命中零网络；`--refresh` 强刷；Windows Git Bash 开箱可用——ADR-0044）
- 找活/认领（ADR-0051）：`scripts/ghcb next`（列 state:ready 卡）→ `scripts/ghcb claim <n>`（评论 /claim，conductor 置 state:in-progress）→ `make gates-pr`（本地复现关卡，W1-C5 落地）

## 索引

| 主题 | 文件 |
|---|---|
| 治理总声明（域/措施/流程） | governance/GOVERNANCE.yaml |
| 组织仓库地图 | governance/REPOS.yaml |
| 期望状态（漂移真源） | governance/expected-state.json |
| 语言/依赖政策 | governance/policy/languages.yaml |
| 测试政策 | governance/policy/testing.yaml |
| 无人值守护栏阈值（auto-fix 上限/成本熔断，ADR-0040） | governance/policy/automation-limits.yaml |
| agent 标准 schema | standards/agent/*.schema.yaml |
| 自动化规范（CI 链路 / bot 反馈通道 / App 权限与工作流变更通道，ADR-0031/0032/0045） | standards/automation/ |
| 原型 profiles / 注册条目 | Cloudbird-Software/agent-registry |
