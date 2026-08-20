# App 权限政策与 CI 工作流变更通道

适用对象：cloudbrid-agent App（AG-1）及未来任何自动化写仓身份。决策背书：
ADR-0045（.github issue #102）；机器执法：`governance/expected-state.json`
`github_app.must_not_have` + drift-check §6。

## 规则 1：App 永不持有 workflows / administration 权限

`workflows:write` 等于允许修改审判自己的 gate 定义（自动合并计划 #81 §3.3
的核心威胁模型）。App 是高频自动化身份，该权限面不可接受。GitHub 侧的
自然结果：App 创建的 tree 一旦包含 `.github/workflows/**` 即 403
（Resource not accessible by integration）——这是**预期行为**，不是故障；
drift-check §6 一旦发现 App 出现禁用权限即报漂移（应立即在 App 设置页移除）。

## 规则 2：CI 工作流变更走 owner 凭据通道

`.github/workflows/**` 的变更由 owner 凭据提交，两种形态：

1. **常态**：agent 在 issue/PR 描述中以 diff 形式产出补丁，owner 审后自行
   apply 提交 PR；
2. **owner 显式授权的 agent 会话**：owner 以 PAT 授权 agent 代为提交
   （先例：T-W5-034 回迁，AI_Web_School PR #51）——PR 留痕，审计面完整。

通道约束：owner 凭据**不豁免任何机器门禁**——变更仍必须走 PR 过 gate +
ruleset（owner-merge 语义见 GOVERNANCE flows.governance_change）。

## 规则 3：agent 遇到工作流变更需求的动作序列

1. 产出完整 diff，登记到对应 issue/PR；
2. 声明「需 owner 凭据通道」（引用本规范 + ADR-0045）；
3. 等待 owner apply 或显式授权；**不得**尝试以 App 身份直推（403 且无意义），
   **不得**因此绕过 PR 流程（如请求 owner 直推 main——那要走破玻璃流程）。
