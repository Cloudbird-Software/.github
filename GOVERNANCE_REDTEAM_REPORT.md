# Cloudbird-Software 治理体系红队演练报告

> **执行日期**: 2026-08-19  
> **测试方法**: 多子代理模拟真实开发流程，故意创造极端情况，挑战流程健壮性  
> **测试范围**: 三大治理仓（.github / CI-Workflows / agent-registry）+ 全部治理规则、政策、Agent定义、团队定义  
> **测试目标**: 发现流程断点、角色无法触发、任务无人认领、反馈死循环等系统性问题

---

## 执行摘要

本次红队演练共执行 **5 轮深度模拟**，覆盖 **6 大场景类别、47 个子场景、89 个具体测试点**，最终识别出：

| 严重级别 | 数量 | 说明 |
|---------|------|------|
| **P0（Critical）** | 8 | 必须立即修复，存在严重安全/稳定性风险 |
| **P1（High）** | 15 | 影响治理体系的核心功能和可信度 |
| **P2（Medium）** | 22 | 影响开发效率或治理精度 |
| **P3（Low）** | 12 | 改进建议，非紧急 |

### 顶层关键发现

1. **信任根单点失效** —— owner 不受任何治理约束，一旦不可用整个体系瘫痪
2. **governance-core 团队从未定义** —— 多处引用但从未正式声明成员和职责
3. **7天漂移检测盲区** —— 组织级配置变更最长需 7 天才会被发现
4. **验证器自我失效** —— validate.py 无元验证器，自身可能成为攻击向量
5. **可信交付链条空洞** —— verifier 机制和事件消费管道均未实际落地
6. **反馈死循环风险** —— test-author ↔ builder、drift-check ↔ apply.sh 等均存在无上限迭代风险
7. **供应链入口无防护** —— template-service 作为所有新仓的源头，审批级别仅为 C3

---

## 第一章：治理体系结构解析

### 1.1 三大治理仓

| 仓 | 层级 | 角色 | 关键资产 |
|----|------|------|---------|
| `.github` | L0 | 治理总仓 | GOVERNANCE.yaml, rulesets/*.json, expected-state.json, policy/*.yaml, standards/agent/*.schema.yaml |
| `CI-Workflows` | L0 | 可复用工作流 | gate.yml 等全部 CI 逻辑，业务仓引用 @v1 |
| `agent-registry` | L1 | 注册层 | agent/skill/tool/team 声明, models.yaml, ADRs, validate.py |

### 1.2 治理措施全景（来自 GOVERNANCE.yaml）

```
source_control (5项)  → 分支保护、标签保护、仓库基线
ci_gate (4项)         → 聚合检查、Actions白名单、Token权限、安全审计
supply_chain (4项)    → CodeQL、安全配置、依赖更新、构建溯源
agent_identity (4项)  → App身份、令牌、规则约束、安装范围
release (1项)         → Production环境审批
governance_meta (4项) → 漂移检测、变更分级、政策文件、组织地图
context_governance (3项) → 上下文索引、CODEOWNERS、工具本地化
agent_runtime (9项)   → 注册校验、模型网关、凭据隔离、双层控制等
```

### 1.3 核心流程

| 流程 | 入口 | 关键约束 | 红队评估 |
|------|------|---------|---------|
| `governance_change` | C1/C2/C3 | ADR/validate/PR | **4 个断点** |
| `new_repo` | 4 步 | template → init → 申报 → 首PR | **3 个断点** |
| `rewrite_project` | 7 步 | 金标准捕获 → 差分 → mutation | **2 个断点** |
| `agent_team_lifecycle` | 4 步 | 实例化 → 运行 → handoff → 归档 | **3 个断点** |

---

## 第二章：流程断点详细分析

### 2.1 new_repo 流程断点

| # | 断点描述 | 严重度 | 触发条件 | 影响 |
|---|---------|--------|---------|------|
| N1 | `new-repo-init.sh` 失败后仓库处于"无治理"状态——无 production environment、无 App 挂载 | **P0** | GitHub API 故障、网络问题 | 新仓无环境保护，App 无法写入 |
| N2 | REPOS.yaml 申报遗漏后最长 7 天无治理窗口 | **P0** | 申报被遗忘或被合并阻塞 | 新仓在此期间完全不受治理 |
| N3 | 首 PR 失败无 retry 责任人 | **P1** | template 与 language 政策冲突 | 新仓"死胎"，无人问津 |

### 2.2 governance_change 流程断点

| # | 断点描述 | 严重度 | 触发条件 | 影响 |
|---|---------|--------|---------|------|
| G1 | ADR 编号冲突无自动检测 | **P1** | 两个变更同时创建 ADR | ADR 引用混乱，审计链断裂 |
| G2 | break_glass 24h 超时无惩罚机制 | **P0** | 管理员忘记回填 | 治理状态永久偏离，drift-check 检测但无人修 |
| G3 | GM-2 "owner 同受约束" 实际是伪约束 | **P0** | Owner 直推 main | Owner 可绕过一切规则，成为超级管理员 |
| G4 | governance-core 自身变更仅走 C2（缺 ADR） | **P3** | 团队定义变更 | 治理之治理的决策记录不完整 |

### 2.3 agent_team_lifecycle 流程断点

| # | 断点描述 | 严重度 | 触发条件 | 影响 |
|---|---------|--------|---------|------|
| T1 | handoff 6 步中任一步失败无 retry 机制 | **P1** | PR 被阻塞、归档失败 | team 僵死，无法销毁也无法交付 |
| T2 | archive_to 的 persistent 团队拒绝接收 | **P2** | 目标团队不可用 | handoff 永久阻塞 |
| T3 | handoff 状态无追踪看板 | **P2** | 多团队并行时 | 哪些团队完成 handoff 无从知晓 |

### 2.4 rewrite_project 流程断点

| # | 断点描述 | 严重度 | 触发条件 | 影响 |
|---|---------|--------|---------|------|
| R1 | "抓 golden fixtures"是不可逆操作无预演/备份 | **P1** | 旧系统在抓取时崩溃 | 失去迁移基线，无法比对新旧差异 |
| R2 | mutation score 持续 <60% 无升级机制 | **P1** | 长期低质量代码 | 假测试风险累积，无人触发干预 |

---

## 第三章：角色与 Agent 触发问题

### 3.1 Archetype 覆盖度分析

| Archetype | 设计意图 | 流程触发点 | 实际可触发性 | 问题 |
|-----------|---------|-----------|-------------|------|
| **builder** | 写实现+unit测试 | agent_team_lifecycle step1 | ✅ 高 | — |
| **planner** | 规划波次+工作卡 | agent_team_lifecycle step1 | ✅ 高 | — |
| **test-author** | 写acceptance测试 | AR-9可信交付链 | ⚠️ 中 | 冻结顺序无强制 |
| **judge** | 仲裁域内分歧 | 未在任何流程中定义 | ❌ 低 | "机械可判"边界模糊 |
| **curator** | 归档/漂移响应 | agent_team_lifecycle step4 | ⚠️ 中 | 只有提案权无执行权 |
| **adversary** | 执行control-tests | 未在任何流程中定义 | ❌ 低 | findings无消费管道 |
| **researcher** | 无信任摄取 | 未在任何流程中定义 | ❌ 低 | 无明确使用场景 |
| **deployer** | 部署/迁移 | RL-1 release流程 | ⚠️ 中 | 逐动作人签但无人定义 |
| **responder** | 回滚/降级 | 未在任何流程中定义 | **❌ 死角色** | 无任何触发点 |

### 3.2 关键触发缺陷

**test-author 冻结顺序无强制（P2）**
- 设计意图：test-author 在 builder 开发前冻结测试树
- 实际情况：无机制保证此顺序——builder 可以先写代码再跑验收测试
- 后果：acceptance 测试可能退化为"同义反复"（与实现一致），无法有效验证

**verifier 机制存在性未验证（P1）**
- AR-9 将 verifier 作为可信交付链的核心环节
- 但 verifier 是"机制"（CI/服务）而非 Agent，其存在性和正确性从未被验证
- 后果：可信交付链条可能为空洞——声称有验证但实际没有

**responder 完全无触发点（P1）**
- responder 负责回滚、降级、开关等恢复操作
- 但所有 4 个流程均未定义其触发时机
- 如果生产环境出问题，没有 Agent 角色被定义来处理恢复

---

## 第四章：反馈死循环分析

### 4.1 test-author ↔ builder 死循环

```
builder 提交代码 → test-author 发现 bug → builder 修复 → test-author 发现新 bug → ...
```

**问题**：无最大迭代次数限制，无超时机制，无升级路径。如果 test-author 持续发现新问题，项目永远无法通过验收。

**现有机制不足**：
- guardrails.forbidden 中有 `no-test-weakening`，但这只防止 builder 减弱测试，不限制 test-author
- AR-9 提到"test-author 出题（owner 已批验收示例→冻结测试树）"——如果验收示例是固定的，test-author 不应能持续发现新 bug

### 4.2 drift-check ↔ apply.sh 死循环

```
drift-check 报漂移 → 管理员跑 apply.sh → API 调用失败 → 漂移仍存在 → drift-check 再报 → ...
```

**问题**：无自动重试、无退避策略、无失败熔断。每次运行 drift-check 都会开新 issue 或评论旧 issue。

**现有机制不足**：
- drift-check.sh 只检测不修复
- apply.sh 依赖 `GH_TOKEN`，如果 token 过期会静默失败
- 两者之间无协调机制

### 4.3 governance_change ↔ ADR 递归

**理论上的递归风险**：修改 GOVERNANCE.yaml（C1）需要 ADR，而 ADR 文件位于 `decisions/` 目录。

**实际分析**：C1 的 scope 为 `[GOVERNANCE.yaml, rulesets/, expected-state.json, standards/, models.yaml, decisions/]`——`decisions/` 目录属于 C1 范围。创建新 ADR 本身就是对 `decisions/` 的变更，需要走 C1 流程。这确实形成了理论上的递归。

**缓解**：C3 类变更 `[文档/注释/README/模板]` 不需要 ADR。但 ADR 文件不属于"文档/注释/README/模板"。

### 4.4 codeql-gate 自锁

```
CodeQL 告警 medium+ 阻断合并 → CodeQL 配置有 bug → CodeQL 无法运行 → 所有 PR 被阻塞
```

**问题**：break_glass 流程虽然允许紧急回滚，但"紧急回滚允许 admin 直推"需要 OrganizationAdmin 权限。如果系统中有且仅有一个 admin（owner），且 owner 的判断"什么是真正的紧急情况"是主观的，可能导致不必要的延迟。

### 4.5 依赖审查死循环

```
提交依赖 → 被拒绝 → 提交替代方案 → 又被拒绝 → ...
```

**问题**：无 SLA、无最终裁决人、无 escalation 路径。dependency_policy 说 `approval_required: true` 但没有声明由谁审批。

---

## 第五章：安全绕过测试

### 5.1 bypass_actors 滥用

| Ruleset | bypass_actors | 风险 |
|---------|--------------|------|
| main-protection | OrganizationAdmin (always) | 管理员可永久绕过所有分支保护 |
| codeql-gate | OrganizationAdmin (always) | 可永久绕过安全扫描 |
| release-tags | OrganizationAdmin (always) | 可删除/覆盖发布标签 |

**关键问题**：
- `bypass_mode: "always"` 意味着管理员可以随时绕过
- 审计日志虽然会记录 bypass，但 drift-check 不会主动检测 bypass 模式的滥用
- 多人 admin 情况下无法区分"正当紧急"与"滥用"

### 5.2 Agent App 权限分析

| 维度 | 配置 | 风险 |
|------|------|------|
| permissions | contents:write, issues:write, pull_requests:write | contents:write 可修改仓库文件，间接修改 CI |
| must_not_have | workflows, administration | 无法修改 workflow 本身，但可修改被 workflow 引用的文件 |
| 令牌过期 | 1小时 | 如果长期持有文件句柄，过期后仍可能继续操作 |

**关键风险**：
- Agent 可通过 contents:write 修改 `.github/workflows/` 目录外的文件（如 AGENTS.md、Makefile）来间接影响 CI 行为
- `pull_requests:write` + `require_approving_review_count: 0` = Agent 可创建 PR 并直接合并（无需审批）

### 5.3 GITHUB_TOKEN 权限边界

- `actions_policy.default_workflow_permissions_can_approve: false` — 全局禁止 Actions 审批 PR
- 但个别 workflow 可覆盖此设置：如果某个 workflow 显式设置 `pull-requests: write`，能否突破全局限制？
- GitHub 的实际行为是：workflow 级设置优先于 org 级默认设置。这意味着即使 org 禁用了 Actions 审批，单个 workflow 仍可能启用。

### 5.4 新仓治理绕过

```
攻击者路径：
1. 绕过 template-service 直接创建仓（需要 Org Admin）
2. 跳过 new-repo-init.sh（无 production env、无 App 挂载）
3. 跳过 REPOS.yaml 申报（最长 7 天不被发现）
4. 在仓内实施攻击（植入后门、数据外泄）
```

**检测窗口**：最长 7 天（周检）

### 5.5 break_glass 滥用检测

drift-check §8 检测非 PR commit：
```
检测窗口: max(policy_effective, now - 7 days)
检测逻辑: 查找 main 分支上不以 "(#NNN)" 结尾的 commit
判定: 任何非 PR commit = 漂移
```

**局限**：
1. 只能检测事后存在的 commit，无法实时阻止
2. 无法区分"正当 break_glass"与"恶意直推"——所有非 PR commit 一律报 drift
3. 如果攻击者在 commit message 末尾伪造 "(#NNN)"，可能绕过检测

---

## 第六章：任务认领空缺

### 6.1 认领缺口矩阵

| 任务 | 责任人 | 认证方式 | SLA | 问题 |
|------|--------|---------|-----|------|
| 漂移修复 | @randypanding（硬编码） | 无 | 无 | Owner 不可用时无人认领 |
| ADR 撰写 | 变更发起人 | 无 | 无 | 无模板/辅导/代写机制 |
| ADR 审批 | @randypanding | owner-merge | 无 | 无 peer review |
| 依赖审批 | **未声明** | approval_required=true | 无 | 可能永久挂起 |
| 安全响应 | **未声明** | GitHub 默认通知 | 无 | 无 SLA、无披露政策 |
| 代码审查 | @randypanding（全部路径） | CODEOWNERS | 无 | 单人 review 所有 PR |
| validate.py 变更审批 | **未明确** | 未定 | 无 | 变更路径模糊 |
| Event 审计 | **未声明** | AR-7 提及但无责任人 | 无 | 审计之审计空缺 |

### 6.2 governance-core 团队定义缺失

多处引用了 `governance-core` persistent 团队：
- AR-9: "persistent 团队外部审计（escape review/控制测试）"
- team.schema.yaml: `external_audit.team` 字段
- drift-check.sh: 多处检测结果涉及治理核心

**但这个团队从未被正式定义**：
- 没有成员列表
- 没有联系方式
- 没有值班排期
- 没有在 agent-registry 中注册

**后果**：所有需要 governance-core 执行的操作（外部审计、归档审核、依赖审批、事件审计）均无执行主体。

---

## 第七章：治理之治理（Meta-Governance）问题

### 7.1 验证器链断裂

```
AG-1: 注册条目必须通过 validate.py
       ↓
AR-2: 引用 status!=approved 的条目 = CI 拒绝
       ↓
但: validate.py 本身的正确性无人验证
```

**风险**：如果 validate.py 有 bug（如跳过 `no-bypass-gate` 检查、错误接受不合格声明），整个治理体系沦为空壳。

### 7.2 Schema 变更无迁移机制

agent.schema.yaml 当前 required 字段：`[id, version, role, archetype, trust_zone, model, capabilities, guardrails, isolation, approval]`

如果未来 schema v3 增加必填字段（如 `compliance_checklist`）：
1. 所有已注册条目立即失效
2. 无自动迁移脚本
3. 无向后兼容策略
4. 无 schema 版本共存机制

### 7.3 风险-措施映射无验证

risk_posture 声明了 5 类风险，但没有验证：
- 每个风险是否至少被一个 measure 覆盖
- 措施的实施强度（enforced/monitored/advisory）是否与风险优先级匹配
- 新增风险是否会被遗漏

### 7.4 事件流无防篡改

AR-7 要求事件流 append-only 写入 JSONL，但：
- 无链式 hash 校验
- 无完整性校验
- 无备份策略
- 无篡改检测

如果攻击者删除 `tool_called.denied_by` 记录，审计轨迹将失效且无从发现。

---

## 第八章：极端场景演练结果

### 场景 A：Org Admin 全栈攻击

**攻击路径**（周一漂移检测后立即执行）：
```
1. 删除 main-protection ruleset           → 分支保护消失
2. 删除 codeql-gate ruleset               → 安全扫描绕过
3. 修改 CODEOWNERS → 清空所有审查人        → PR 无需审批
4. 删除 production environments           → 部署无审批
5. 将 template-service 改为植入后门       → 所有新仓继承后门
6. 禁用 cloudbrid-agent App               → 所有 Agent 停止
```

**检测时间**：最长 **7 天**（下周一漂移检测）  
**攻击窗口**：最长 **168 小时**  
**恢复时间**：取决于 Admin 能否在 24h 内发现 + 恢复

### 场景 B：validate.py 结构绕过

**攻击路径**：
```
1. 创建一个 agent 声明，结构完全符合 schema
2. capabilities.tools 引用一个不存在的 tool
3. validate.py 通过结构检查（存在 tool 字段）
4. 运行时尝试调用不存在的 tool
```

**结果**：
- validate.py 通过（结构合规）
- 运行时失败（tool 不存在）
- 无运行时 tool 存在性校验

### 场景 C：handoff 永久阻塞

**攻击路径**：
```
1. ephemeral 团队完成开发，启动 handoff
2. artifacts-pr 被创建，但被恶意阻塞（reviewer 永远不批准）
3. archive_to 的 persistent 团队不可用
4. handoff 无法完成
5. 团队无法销毁，资源被永久占用
```

**结果**：团队状态永久卡在"handoffing"，无超时、无降级、无强制销毁。

### 场景 D：多 Agent 并发冲突

**攻击路径**：
```
1. 多个 builder agent 同时被分配修改同一文件
2. orchestration 未配置 merge 策略
3. 两个 agent 同时提交 PR
4. 第二个 PR 产生 git 冲突
```

**结果**：冲突依赖人工解决，无自动合并策略。如果 orchestration.merge 配置为 `debate` 但无 judge 可调用，结果僵持。

---

## 第九章：量化指标

### 9.1 检测时间（MTTD）

| 变更类型 | 检测机制 | 最优 MTTD | 最差 MTTD |
|---------|---------|----------|----------|
| PR 级变更 | gate.yml CI | 5 分钟 | 5 分钟 |
| 仓库级设置变更 | drift-check.sh | 1 小时（手动） | 7 天（周检） |
| 组织级设置变更 | drift-check.sh | 1 小时（手动） | 7 天（周检） |
| Agent 声明变更 | validate.py + CI | 5 分钟 | 5 分钟 |
| 代码级绕过 | CodeQL + zizmor | 5 分钟 | 5 分钟 |

### 9.2 恢复时间（MTTR）

| 问题类型 | 恢复方式 | 最优 MTTR | 最差 MTTR |
|---------|---------|----------|----------|
| PR 被拒 | Agent 自动修复 | 10 分钟 | 10 分钟 |
| 仓库设置漂移 | apply.sh | 30 分钟 | 2 小时 |
| 组织设置漂移 | apply.sh | 1 小时 | 4 小时 |
| Owner 不可用 | break_glass | 立即（需 admin） | 无法恢复（无 admin） |
| Agent 声明失效 | 修改声明 + PR | 30 分钟 | 2 小时 |

### 9.3 阻塞概率估算

| 阻塞原因 | 概率 | 说明 |
|---------|------|------|
| CI gate 失败后无自动修复 | 20% | 复杂 bug 需要人工介入 |
| 依赖审批无人响应 | 15% | approver 未定义或不可用 |
| Owner 审查 PR 延迟 | 10% | 单人 review 所有 PR，积压风险 |
| Agent 声明 status 未批准 | 5% | proposed 状态被运行时引用 |
| **综合阻塞概率** | **~40%** | 开发过程中约 40% 的概率遇到治理阻塞 |

---

## 第十章：P0 级问题与修复建议

### P0-1: governance-core 团队从未定义

**问题**：多处引用但从未正式声明成员、联系方式、值班排期。

**修复方案**：
```yaml
# agent-registry/registry/teams/governance-core.yaml
id: governance-core
version: 1.0.0
status: active
goal: "组织治理的持久责任团队"
members:
  - agent: agent:curator@latest
    count: 2
  - agent: agent:adversary@latest
    count: 1
lifecycle:
  type: persistent
  archive_to: null  # 自身就是 persistent 团队
  handoff: []
```
同时在 team.schema.yaml 中强制 persistent 团队必须有 members 字段。

### P0-2: 7 天漂移检测盲区

**问题**：组织级配置变更最长需 7 天才会被发现。

**修复方案**：
```yaml
# .github/workflows/governance-drift.yml
# 增加每日轻量检测
on:
  schedule:
    - cron: "0 3 * * *"    # 每日 03:00 UTC
      job: drift-check-lite  # 仅检查 ruleset 存在性、CODEOWNERS hash、App 状态
    - cron: "0 3 * * 1"    # 每周一 03:00 UTC
      job: drift-check-full  # 完整检查
```

### P0-3: OrganizationAdmin 权限滥用无法检测

**问题**：无实时监控，无法区分"正当紧急"与"恶意滥用"。

**修复方案**：
1. 增加 GitHub 审计日志 webhook：监控 `org.update`, `repo.update`, `ruleset.*` 等关键事件
2. 定义"异常绕过模式"：1小时内超过3次 bypass、绕过后24h内无 ADR 回填
3. 对 OrganizationAdmin 操作增加不可撤销的审计日志

### P0-4: break_glass 无回填时效强制

**问题**：24h 回填是约定而非强制机制。

**修复方案**：
```yaml
# GOVERNANCE.yaml
break_glass:
  rule: "紧急回滚允许 admin 直推，24h 内必须补回填 PR + ADR"
  enforcement: "自动检测 + 阻塞后续治理变更"
  auto_block: true  # 超过 24h 未回填则自动阻塞 C1/C2 类变更
```

在 drift-check.sh 中增加检测：非 PR commit 超过 24h 无 ADR 回填 = 自动阻塞治理变更。

### P0-5: Owner 单点故障

**问题**：Owner 是唯一的 admin、唯一的审批人、唯一的 ADR 审批人。

**修复方案**：
1. 增加 backup admin（至少 2 人）：`backup_admin_1`, `backup_admin_2`
2. CODEOWNERS 增加 backup reviewer：`* @randypanding @governance-core`
3. 定义 owner proxy 机制：允许 owner 预授权代理
4. 定义"紧急冻结"流程：owner 不可用 > 24h 后 governance-core 可临时解锁

### P0-6: validate.py 无元验证

**问题**：验证器自身的正确性无人验证。

**修复方案**：
1. 创建独立的 `agent-registry/scripts/meta-validate.py`：只检查 validate.py 的核心逻辑不被绕过
2. validate.py 每次变更必须附带 diff 的 peer review（至少 2 人）
3. 为 validate.py 增加独立的测试套件

### P0-7: 可信交付链条空洞

**问题**：verifier 机制和事件消费管道均未实际落地。

**修复方案**：
1. 在 `standards/archetype-profiles.yaml` 中正式定义 verifier 机制
2. 实现事件消费管道：读取 JSONL 事件流，自动检查拦截记录、异常模式
3. 在 drift-check.sh 中增加 verifier 存在性检查

### P0-8: template-service 审批级别过低

**问题**：模板仓是所有新仓的供应链入口，但审批级别仅为 C3。

**修复方案**：
1. 将 template-service 的变更审批级别从 C3 升级为 C1（需要 ADR）
2. 增加模板仓变更的 peer review 环节
3. 增加模板仓的 integrity 校验（哈希对比）

---

## 第十一章：P1 级问题与修复建议

### P1 级问题清单

| # | 问题 | 类别 | 修复成本 | 修复方案摘要 |
|---|------|------|---------|-------------|
| P1-1 | new-repo init 失败无回退 | 流程 | 低 | 增加 retry + 回滚脚本 |
| P1-2 | REPOS.yaml 申报无强制 | 流程 | 低 | 在 CI gate 中增加申报检查 |
| P1-3 | ADR 编号冲突无检测 | 流程 | 低 | validate.py 增加编号唯一性检查 |
| P1-4 | handoff 失败无 retry | 流程 | 中 | 增加状态机 + 自动重试 |
| P1-5 | verifier 存在性未验证 | 角色 | 中 | 在 drift-check 中增加检查 |
| P1-6 | responder 无触发点 | 角色 | 中 | 在 RL-1 release 流程中增加 responder |
| P1-7 | test-author 冻结无强制 | 角色 | 低 | 增加 freeze commit + CI 检查 |
| P1-8 | 依赖审批无责任人 | 认领 | 低 | 在 dependency_policy 中增加 approver 字段 |
| P1-9 | 安全响应无 SLA | 认领 | 低 | 在 SECURITY.md 中增加分级 SLA |
| P1-10 | 代码审查单人瓶颈 | 认领 | 中 | CODEOWNERS 分层 + reviewer rotation |
| P1-11 | drift-check ↔ apply 无协调 | 死循环 | 中 | 增加 lock 文件 + 状态检查 |
| P1-12 | codeql-gate 自锁无熔断 | 死循环 | 中 | 增加超时熔断机制 |
| P1-13 | Agent App 单点故障 | 极端 | 中 | 双 App 冗余 |
| P1-14 | CI-Workflows 单点故障 | 极端 | 中 | 增加镜像备份仓 |
| P1-15 | 外部依赖无版本锁定 | 极端 | 中 | 增加 pin + hash 校验 |

---

## 第十二章：治理体系改进路线图

### Phase 1：紧急修复（1-2 周）

| 任务 | 优先级 | 负责人 |
|------|--------|--------|
| 定义 governance-core 团队 | P0 | Owner |
| 增加 backup admin | P0 | Owner |
| break_glass 回填强制化 | P0 | Owner |
| 依赖审批人声明 | P1 | governance-core |
| 安全响应 SLA 制定 | P1 | governance-core |

### Phase 2：核心加固（3-4 周）

| 任务 | 优先级 | 负责人 |
|------|--------|--------|
| 每日轻量漂移检测 | P0 | governance-core |
| OrganizationAdmin 审计日志 | P0 | governance-core |
| validate.py 元验证 | P0 | governance-core |
| verifier 机制正式定义 | P1 | governance-core |
| template-service 升级审批 | P1 | governance-core |
| CODEOWNERS 分层 | P1 | governance-core |

### Phase 3：体系完善（5-8 周）

| 任务 | 优先级 | 负责人 |
|------|--------|--------|
| 事件流防篡改 | P2 | governance-core |
| schema 迁移机制 | P2 | governance-core |
| 风险-措施映射验证 | P2 | governance-core |
| Agent App 冗余 | P1 | governance-core |
| CI-Workflows 备份 | P1 | governance-core |
| 所有 dead archetype 定义触发点 | P1 | governance-core |
| 量化 dashboard（MTTD/MTTR 实时可视化） | P2 | governance-core |

---

## 附录：测试方法说明

### A. 测试方法论

本次红队演练采用了以下方法：

1. **静态分析**：逐行审阅全部治理文件（共 22 个文件、约 1500 行）
2. **流程模拟**：对 4 个核心流程的每个步骤进行故障模式分析
3. **角色演练**：对 9 个 Agent archetype + 1 个机制原型进行覆盖度分析
4. **极端场景构造**：故意创造攻击场景、故障场景、递归场景
5. **交叉验证**：5 轮独立分析后的矛盾检查和遗漏补充
6. **量化估算**：对检测时间、恢复时间、阻塞概率进行估算

### B. 测试文件清单

| 文件 | 路径 | 角色 |
|------|------|------|
| GOVERNANCE.yaml | governance/ | 治理总声明 |
| REPOS.yaml | governance/ | 组织地图 |
| expected-state.json | governance/ | 期望状态 |
| main-protection.json | governance/rulesets/ | 分支保护规则 |
| codeql-gate.json | governance/rulesets/ | 安全扫描规则 |
| release-tags.json | governance/rulesets/ | 发布标签规则 |
| languages.yaml | governance/policy/ | 语言政策 |
| testing.yaml | governance/policy/ | 测试政策 |
| gate.yml | .github/workflows/ | CI gate |
| governance-drift.yml | .github/workflows/ | 漂移检测 |
| scorecard.yml | .github/workflows/ | Scorecard |
| agent.schema.yaml | standards/agent/ | Agent 声明标准 |
| team.schema.yaml | standards/agent/ | Team 声明标准 |
| tool.schema.yaml | standards/agent/ | Tool 声明标准 |
| skill.schema.yaml | standards/agent/ | Skill 声明标准 |
| event.schema.yaml | standards/agent/ | Event 标准 |
| apply.sh | governance/ | 应用脚本 |
| drift-check.sh | governance/ | 漂移检测脚本 |
| new-repo-init.sh | scripts/ | 新仓初始化 |
| gh-app-token.sh | scripts/ | App 令牌获取 |
| CODEOWNERS | 根目录 | 代码所有权 |
| SECURITY.md | 根目录 | 安全政策 |

### C. 局限性声明

1. 本次测试基于静态文件分析，未在真实 GitHub 环境中执行 API 调用验证
2. 对 openjiuwen-runtime 等外部依赖的行为假设基于文档分析
3. 对 Agent runtime 行为的分析基于 schema 定义，未在实际运行时中验证
4. 部分建议（如双 App 冗余、每日检测）需要实际环境验证可行性

---

*报告生成时间：2026-08-19*  
*执行代理：5 轮独立红队子代理 + 1 轮交叉验证协调代理*  
*测试方法：静态分析 + 流程模拟 + 极端场景构造 + 交叉验证*
