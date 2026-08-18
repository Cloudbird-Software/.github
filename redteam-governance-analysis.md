# Cloudbird-Software 治理体系红队测试报告：流程断点与角色触发分析

> 分析时间: 2026-08-19
> 分析范围: GOVERNANCE.yaml 全部 flows、agent.schema.yaml 九原型、team.schema.yaml 生命周期、event.schema.yaml 事件流、policy/testing.yaml 测试矩阵、drift-check.sh 漂移检测
> 分析方法: 逐条流程逆向推演、假设故障注入、验证触发条件覆盖

---

## 场景集1: 流程断点模拟

### 1.1 new_repo 流程断点

#### 断点1.1-A: 第2步 `bash new-repo-init.sh` 失败

**断点描述**: 脚本含 4 个子步骤（仓库基线设置 → production environment → App 安装 → 验证），任一步失败（如 GitHub API 超时、App 安装 HTTP 非 204、jq 解析错误），由于 `set -euo pipefail`，整个脚本中断。

**后果**:
- 仓库被创建（step 1 的 `gh repo create` 已完成）但处于**无治理状态**：
  - 无 production environment（RL-1 失效 → 部署无审批防线）
  - 无 App 挂载（AG-4 失效 → agent 无法写入，只能手动操作）
  - 可能处于非 squash 模式（BP-4 部分失效）
- 脚本最后给的手动路径提示只覆盖了 App 安装，没覆盖 production environment 的手动修复
- **第3步"申报入 REPOS.yaml"不被阻塞**——申报是独立的 PR 行为，理论上申报者可以绕过失败的 init 直接申报，但此时申报的内容与实际仓库状态不一致

**建议修补**:
1. 将脚本拆为幂等子步骤，失败后可从断点恢复（`init-stage-1.sh`, `init-stage-2.sh` ...）
2. 在 REPOS.yaml 申报流程中增加预检：申报前校验仓库至少满足 BP-4 + AG-4，不满足则 PR 拒绝合并
3. 脚本失败后自动创建 GitHub issue 标记仓库为"初始化未完成"状态，通知 owner

#### 断点1.1-B: 第3步 REPOS.yaml 申报遗漏

**断点描述**: 新建仓库后忘记或遗漏在 `governance/REPOS.yaml` 中申报。

**后果**:
- drift-check 检测频率为**每周一 03:00 UTC**（GM-1）。窗口期最长为 **7 天**
- 在此窗口期内：
  - 新仓处于**完全无治理状态**（GM-4 enforce + monitored 双失配）
  - drift-check §7b 只检测"线上仓未在图中申报"，但周期为周
  - 新仓不受任何 ruleset 约束（因为新仓默认不继承 ruleset，需要配置）
  - App 未挂载 → agent 无法操作 → 但 human 操作不受限
- 一旦 drift-check 发现，会自动开 issue，但需要人手动补申报

**建议修补**:
1. 在 `gh repo create` 后立即触发 webhook，自动在 REPOS.yaml 创建 PR 草稿（status: planned → 自动 PR 入图）
2. 将 drift-check 的 REPOS.yaml 校验（§7b）对新仓改为**日检**，或增加实时 webhook 监听
3. 增加 GitHub org webhook: `repository.created` → 自动 issue 创建 + 指派 owner

#### 断点1.1-C: 第4步"首PR"失败

**断点描述**: 首 PR 因为 lint/gate 检查不通过（如 `languages.yaml` 选型错误、dep-cruise 边界规则违例、AGENTS.md 缺失）而无法合并。

**后果**:
- 无人自动重试——流程描述中没有指定 retry 责任人
- 如果首 PR 长期挂起：
  - `languages.yaml` 要求 go/typescript 选型 + BAML 声明 + depcruise 边界，但首 PR 没有可参照的前例
  - AGENTS.md 必须声明 archetype，但新仓第一次写容易违反 `builder↔test-author 不得同一声明` 规则（AR-8）
  - 没有人/机制自动 review 首 PR 的合规性（C2 类变更需要 validate.py 通过，但 validate.py 在仓库内尚不存在——agent-registry 还未部署）
- 风险：新仓"死胎"——创建了但无法进入正常开发流程

**建议修补**:
1. 将首 PR 模板写入 `template-service`，预置语言选型、AGENTS.md 骨架、depcruise 配置
2. 在模板仓库中预置 validate.py 检查脚本，首 PR 即可自动校验
3. 指定 governance-core persistent 团队（或 owner）为首 PR 兜底 reviewer
4. 增加超时机制：首 PR 挂起超过 48h 自动 escalation 到 owner

---

### 1.2 governance_change 流程断点

#### 断点1.2-A: C1 类变更——ADR 编号冲突或引用未批准 ADR

**断点描述**: C1 要求 `[PR, ADR（新建或引用编号）, drift-check 本地预检, owner-merge]`。如果：
- 引用了一个 status != approved 的 ADR（AR-2 明确禁止）
- ADR 编号与已存在的编号冲突

**后果**:
- validate.py 的 `AR-2` 检查可以拦截 status != approved 的引用（已实现）
- 但**ADR 编号冲突没有自动检测**——如果两个 agent 同时提交 ADR-042，第二个可能通过验证（因为 validate.py 只检查 status 字段，不检查唯一性）
- owner-merge 可能在不完整信息下批准——owner 是唯一 reviewer，但无法假设 owner 人工检查了 ADR 编号唯一性

**建议修补**:
1. validate.py 增加 ADR 编号唯一性检查（扫描 decisions/ 目录，拒绝重复编号）
2. PR 模板中增加 ADR 编号预分配机制（从中央计数器获取）
3. GitHub merge-queue 中增加"ADR 已批准"作为 required status check（通过 GitHub API 查询 ADR registry）

#### 断点1.2-B: C2 类变更——validate.py 通过但运行时行为不符合预期

**断点描述**: C2 要求 `[PR, validate.py 通过]`。validate.py 是静态检查，无法覆盖：
- agent runtime 的动态行为（如权限引擎在特定条件下意外放行）
- skill 定义的 side_effects 声明与实际行为不一致
- tool schema 的 schema_ref 指向了过期的标准版本

**后果**:
- validate.py 只检查结构合规性，不验证语义正确性
- 运行时行为偏离预期时，没有自动检测机制
- GM-2 要求 owner 与 AI 同受约束，但 owner 没有技术手段验证 agent runtime 的实际行为
- **发现者角色缺失**：谁来在运行时发现 validate.py 通过但行为异常？

**建议修补**:
1. 在 agent runtime 中增加**动态验证层**：每次 agent 运行时，由 verifier 机制（非 agent）自动比对声明的预期行为 vs 实际行为
2. 增加**行为漂移检测**：在 `tool_called` 事件中，自动比对 `allow` 白名单 vs 实际调用的工具
3. AR-9 的"可信交付"链条中增加 runtime verifier：每次 run_finished 时自动生成 compliance report
4. 将 `tool_called.denied_by` 事件与声明的 `capabilities.allow` 做持续比对

#### 断点1.2-C: break_glass 24小时没人回填

**断点描述**: `break_glass` 规则要求紧急直推后 24h 内必须回填 PR + ADR。

**后果**:
- drift-check §8 只能检测"直推发生"，但**不能检测"24h 内是否回填"**
- 如果直推后超过 24h 没有回填（因为假期、忘记、优先级冲突）：
  - 系统**没有惩罚机制**——漂移检测只是开 issue
  - 没有 escalation 或 auto-block 机制
  - 治理意图与实际状态持续偏离
- detection 机制存在但没有**时效压力**

**建议修补**:
1. drift-check §8 增加**时效检测**：直推后超过 24h 未回填 = P0 漂移
2. 超时后自动将该仓的所有 PR 标记为 blocked
3. 超时通知升级到 owner 的备用联系渠道（如短信）
4. 引入 T-11 (governance_canary) 的变体：专门测试回填时效性

#### 断点1.2-D: GM-2 "owner 与 AI 同受约束"——owner 如何被约束？

**断点描述**: GM-2 声明"owner 与 AI 同受约束"，但：
- **owner 是 human**，不受 `capabilities.allow` 白名单约束
- owner 不受 `isolation` 隔离约束
- owner 不受 `approval` 审批模式约束（owner 是所有审批的 approval authority）
- CODEOWNERS 明确 `* @randypanding`，owner 可以直接 push 到 main
- owner 不受 `no-self-acceptance-test`、`no-bypass-gate` 等 guardrails 约束

**后果**:
- GM-2 实际上是**伪约束**——owner 可以绕过任何治理规则
- 唯一的约束是 drift-check §9（ADR-0010 vcs_admin 唯一性），确保只有一个 admin
- 如果 owner 行为偏离治理 intent，**没有任何技术手段检测或约束**
- 这是治理体系中最薄弱的一环（信任根单点失效）

**建议修补**:
1. 为 owner 引入**双重审批**：治理关键路径变更（C1 类）需要第二个 admin 审批（但需要新增第二个信任根）
2. 引入**owner 行为审计**：owner 的直推 commit 自动生成 ADR 草稿
3. drift-check 增加**owner 行为监控**：owner 的每次直推自动创建 issue 记录
4. 长期方案：将部分治理决策去中心化到 governance-core 团队，减少对单一 owner 的依赖

---

### 1.3 agent_team_lifecycle 断点

#### 断点1.3-A: handoff 步骤失败——无人重试

**断点描述**: ephemeral 团队销毁前执行 handoff，包含 6 步：
1. `artifacts-pr` —— 产物走 PR
2. `memory-distill` —— 记忆提炼
3. `skill-extract` —— 经验提炼为 skill
4. `adr-write` —— 关键决策升 ADR
5. `trace-archive` —— 轨迹归档
6. `retrospective` —— 回顾

**后果**:
- schema 声明 `handoff` 是 enum 数组，validate.py 检查"全部完成才允许销毁"
- 但**没有指定失败重试责任人**——handoff 是 agent 执行的动作，agent 失败后：
  - 谁来重新触发 handoff？
  - 如果 `artifacts-pr` 被 GitHub 拒绝（如目标分支冲突），agent 可能无法自行恢复
  - `adr-write` 需要与 agent-registry 交互，如果 registry 不可用，该步失败
- `destroy_policy: after-handoff` 是自动销毁——如果 handoff 失败，团队卡在"待销毁但无法销毁"状态
- **persistent 团队（governance-core）作为审计方，但不是 handoff 的执行者或重试者**

**建议修补**:
1. 将 handoff 步骤改造为**可重试的独立任务**，由 governance-core 作为兜底执行者
2. 每步 handoff 增加**超时检测**和**自动重试**（指数退避）
3. handoff 全部失败时，团队进入 `handoff_failed` 状态并永久挂起，不允许销毁
4. 增加 handoff 状态的 API 查询接口，供外部监控系统检测
5. 引入 handoff 完成率作为 governance-core 的 KPI

#### 断点1.3-B: persistent 团队（governance-core）的变更流程

**断点描述**: `governance-core` 是 persistent 团队，被声明为治理资产的持续责任人。但：
- 它的**定义位置不明确**——可能在 `agent-registry/registry/teams/` 下
- 如果 governance-core 本身需要变更（如成员变更、拓扑调整、验证策略修改）：
  - 需要走什么流程？GOVERNANCE.yaml 没有明确说明
  - governance-core 自身的 lifecycle 变更由谁审批？
  - GM-2 说"治理仓变更一律走 flows.governance_change 分级流程"，但 governance-core 是 agent-registry 的一部分，属于 C2 类变更（只需要 validate.py 通过）
  - governance-core 自己定义了 `external_audit`，但它自己变更时 external_audit 不适用（自己审自己）

**后果**:
- governance-core 的变更绕过 C1 类变更的 ADR 要求——**治理核心团队的变更不需要决策记录**
- 没有 owner-merger 约束——C2 只需要 validate.py 通过
- governance-core 作为治理监督者，自身缺乏监督

**建议修补**:
1. 将 governance-core 的 lifecycle 变更升级为 C1 类变更（即使它位于 agent-registry）
2. governance-core 的变更必须经过 owner 审批 + ADR 记录
3. 引入**治理监督的监督**：指定一个独立的验证机制（如 verifier-like mechanism）定期审计 governance-core 的合规性
4. 在 team.schema.yaml 中增加"self-audit exemption"字段，声明哪些团队需要外部审计

#### 断点1.3-C: ephemeral 团队 artifacts 追踪与 archive_to 拒绝

**断点描述**: ephemeral 团队销毁后，其 artifacts 通过 `artifacts-pr` 走 PR 归档到 `archive_to` 指向的 persistent 团队。

**后果**:
- 如果 `archive_to` 指向的 persistent 团队**拒绝接收**（如归档路径冲突、storage 已满、政策不兼容）：
  - PR 被关闭，但 artifacts 仍然在 ephemeral 团队的 workspace 中
  - ephemeral 团队无法销毁（handoff 未完成）
  - artifacts 持续占用存储空间
  - 没有降级路径——handoff 只声明了 6 种固定类型，没有 fallback 选项
- 如果 archive_to 团队不存在（拼写错误、已归档）：
  - validate.py 在声明时可以检测（引用的 team 必须存在）
  - 但如果 archive_to 团队在运行期间被归档，运行时检测机制不明确

**建议修补**:
1. handoff 增加**降级归档目标**：如果主 archive_to 拒绝，降级到 `governance-core`
2. artifacts-pr 增加**超时机制**：超过 72h 未合并 = 自动升级到 owner
3. 增加**artifact 保留期**：handoff 失败的 artifacts 在 workspace 保留 30 天后自动清理
4. validate.py 增加 archive_to 团队的 status 检查（active/archived）

---

### 1.4 rewrite_project 断点

#### 断点1.4-A: 步骤4"旧系统抓 golden fixtures"——不可逆操作

**断点描述**: R-06 明确标注"不可逆操作，立即执行"。如果旧系统在抓 fixtures 时崩溃：
- fixtures 捕获不完整（部分功能缺失）
- 旧系统状态可能已被修改（如读取了 production 数据库导致数据状态变更）
- 旧系统无法恢复（可能已经部分 dismantle）

**后果**:
- 新系统的差分测试（T-09）基准数据不正确
- 新系统可能在上线后才发现与旧系统行为不一致
- 无法重新抓取 fixtures（旧系统已不可用）
- **不可逆操作缺乏预演机制**——没有 dry-run 或 backup

**建议修补**:
1. 在执行 R-06 前增加**预检查**：抓取 fixtures 前创建旧系统的只读快照
2. 增加**fixture 完整性校验**：抓取完成后自动对比原系统的功能覆盖度（如覆盖率、API 端点数量）
3. 增加**fixture 有效期**：如果抓取失败超过 24h，自动升级到 owner
4. 增加**双路径抓取**：同时抓取旧系统的实际输出和从文档推导的预期输出，比对差异

#### 断点1.4-B: 步骤5"差分 job 进 gate"——基准数据不正确

**断点描述**: T-09 (differential) 要求"golden fixtures + 双实现回放"。如果基准数据（fixtures）本身不正确：
- 差分测试可能**全部通过**（因为两边实现共享同样的错误基准）
- 或者**误报不通过**（因为正确的新实现与错误的基准不匹配）
- 没人验证基准数据的正确性

**后果**:
- 差分测试成为**假信心**（false confidence）机制
- 即使新系统通过了差分测试，仍可能存在大量未检测的行为差异
- 基准数据的正确性完全依赖 R-06 的抓取质量
- **验证者缺失**：谁来验证基准数据本身的正确性？

**建议修补**:
1. 增加**基准数据审计层**：由 verifier 机制在差分测试前自动审计 fixtures 的完整性和一致性
2. 引入**独立验证者 archetype**（如 adversary archetype）对 fixtures 进行二次验证
3. 差分测试结果增加**置信度标记**：基准数据不完整时标记为"低置信度通过"
4. 增加**fixture 版本号**：基准数据每次更新都必须经过 C1 类变更审批

#### 断点1.4-C: 步骤6"mutation 周跑"——score 持续低于 60%

**断点描述**: T-10 (mutation) 要求"score < 60% = fake_tests 风险"。如果 mutation score 持续低于 60%：
- **没有升级机制**——policy 只记录"趋势比绝对值重要"，但没有定义：
  - 连续多少周低于 60% 需要升级？
  - 升级到谁？
  - 升级后的行动是什么？
- 没有自动通知机制——mutation 测试结果只是 weekly 报告，不会自动创建 issue

**后果**:
- Fake tests 风险持续存在但无人关注
- 测试覆盖率看起来很高但实际质量低下
- LLM 行为漂移无法被有效检测
- mutation 测试成为"墙上的装饰"

**建议修补**:
1. 定义**升级梯度**：
   - 连续 2 周 < 60% → 自动通知 builder team + governance-core
   - 连续 4 周 < 60% → 创建 P0 issue，暂停合并该模块的 PR
   - 连续 8 周 < 60% → 触发 rewrite_project 的重新评估
2. mutation 测试结果与 CI gate 联动：关键模块 mutation score 必须 ≥ 60% 才能合并
3. 引入**mutation score 趋势监控**：在 drift-check 中增加 mutation score 的长期趋势检测
4. 由 adversary archetype 执行补充的控制测试，检测 fake tests

---

## 场景集2: 角色/Agent 触发测试

### 2.1 test-author 触发分析

#### 断点2.1-A: test-author 工作产品与 builder 实现的解耦验证

**断点描述**: test-author archetype 的核心约束是：
- `builder ↔ test-author 不得同一声明`（AR-8）
- `test-author 族级独立（models.yaml family）`（AR-8）
- `agent.schema` 声明 `builder` 和 `test-author` 是不同 archetype，独立模型族

但这些约束只在**声明层**，**运行时验证**缺失：
- 如何确保 test-author 真的在 builder 之外独立生成测试？
- 如何验证 test-author 的 acceptance tests 不是 builder 实现的同义反复？
- AR-9 说"verifier 机制判卷"，但 verifier 是 mechanism（CI/服务），不是独立的 AI agent

**后果**:
- test-author 可能在心理上"受 builder 影响"（即使使用不同模型族，prompt 上下文可能泄露 builder 的实现细节）
- verifier 机制只做 pass/fail 判卷，不检测测试质量
- **没有独立的 AI 评判者来检测 fake tests**

**建议修补**:
1. 引入**test-author 独立验证层**：test-author 的输出必须经过第二个独立 verifier mechanism 检查"测试与实现的交叉熵"
2. 要求 test-author 的输出**不带任何 builder 上下文**（隔离 workspace、过滤共享记忆）
3. verifier 机制增加**交叉熵检查**：检测测试用例是否与实现代码的 token 分布过度重叠
4. 在 team verification 中增加 `independence_check` 字段：test-author 的独立性评分

#### 断点2.1-B: test-author 测试冻结的触发条件

**断点描述**: AR-9 声明"owner 已批验收示例 → 冻结测试树"，但：
- **谁来确保** test-author 的测试在 builder 开始开发前就冻结？
- 没有时间戳或事件顺序的强制验证
- 如果 builder 先开始开发，test-author 后写测试，"冻结"失去意义
- **冻结的定义不明确**：是指 test_tree_sha 不可变？还是指测试结果不可变？

**后果**:
- Test-author 可能在 builder 完成后才写测试 → 测试变成对实现的"同义反复"
- 冻结的测试树可能被悄悄更新（没有检测机制）
- AR-9 的"可信交付"链条在第一步就断裂

**建议修补**:
1. 引入**测试冻结事件**：test-author 完成后必须发出 `test_tree_frozen` 事件，带 sha 和时间戳
2. CI gate 增加**顺序验证**：检查 test_tree_sha 的创建时间是否早于 builder 首次 commit
3. verifier 机制在判卷时比对 test_tree_sha 与 builder 实现的时间戳
4. 冻结的测试树存入**不可变存储**（如对象存储版本控制），后续变更必须经 C1 类变更审批

---

### 2.2 verifier 机制分析

#### 断点2.2-A: verifier 的存在和正确配置

**断点描述**: AR-9 和 team.schema 都引用 `verifier 机制` 作为 required check：
- `verdict_by: "^mechanism:verifier"` —— 这是一个正则模式约束
- verifier 是**mechanism（CI/服务）** 不是 agent
- 但**谁来保证 verifier 存在和正确配置？**
- agent.schema 引用 `standards/archetype-profiles.yaml`（当前不存在此文件）
- verifier 的实现细节（是什么 CI job？如何判卷？）没有定义

**后果**:
- verifier 可能不存在 → `verdict_by` 只是一个空引用
- verifier 可能配置错误（如指向了错误的 CI workflow）
- 没有自动检测 verifier 存在性的机制
- validate.py 只检查 `mechanism:verifier` 字符串格式，不验证引用的真实性

**建议修补**:
1. 创建 `standards/archetype-profiles.yaml`，定义 verifier mechanism 的最小规范
2. validate.py 增加 verifier 存在性检测：检查引用的 CI workflow 是否真实存在
3. drift-check 增加 verifier 配置漂移检测
4. 在 team verification 中增加 `verifier_exists` 布尔字段，由 validate.py 自动填充

#### 断点2.2-B: verifier 误判（false positive / false negative）的复审

**断点描述**: verifier 判卷可能出现：
- **False Positive**: 测试通过但实际上有缺陷（测试不充分、同义反复）
- **False Negative**: 测试失败但实际上代码正确（测试本身有 bug、环境问题）

**后果**:
- False Positive → 缺陷代码合并 → 产品质量问题
- False Negative → 正确代码被拒绝 → 开发效率问题
- **没有复审机制**：
  - AR-9 提到 `persistent 团队外部审计（escape review/控制测试）`，但这是事后审计，不是实时复审
  - 没有独立的 agent 或 mechanism 在 verifier 判卷后进行复核
  - False Negative 可能导致手动 bypass gate → GM-2 直推

**建议修补**:
1. 引入**双 verifier 机制**：主 verifier + 辅助 verifier，两者结果不一致时标记为"需人工复审"
2. False Negative 增加**自动复审**：失败后自动触发 adversary archetype 对测试本身进行攻击分析
3. False Positive 增加**抽样复审**：每 N 次通过中有 M 次由 governance-core 手动验证
4. verifier 的判定记录进入事件流，供后续审计和机器学习改进

---

### 2.3 judge 触发分析

#### 断点2.3-A: "机械可判"的边界定义

**断点描述**: judge archetype 的触发条件是"域内分歧（机械可判不受理）"。问题：
- **什么是"机械可判"？** 由谁定义？
- judge schema 没有给出"机械可判"的明确定义
- 可能的边界模糊情况：
  - 代码风格分歧（机械可判？）
  - 架构选型分歧（不可机械判？）
  - 测试覆盖度分歧（机械可判？）
  - 安全性分歧（部分机械可判？）
- 边界定义权不明确——是 verifier？是 governance-core？是 owner？

**后果**:
- judge 可能受理本应机械判的争议（过载）
- judge 可能拒绝受理需要人类判断的争议（正义未伸）
- "机械可判不受理"的原则可能被滥用——一方声称某事"机械可判"来阻止 judge 介入

**建议修补**:
1. 在 `agent.schema.yaml` 或 `standards/archetype-profiles.yaml` 中明确"机械可判"的分类：
   - 明确列出哪些类型的争议"机械可判"（如 lint 错误、格式问题、命名规范）
   - 明确列出哪些类型的争议"不可机械判"（如架构设计、API 设计、用户体验）
2. 在 judge archetype 增加 `boundary_definition_ref` 字段，引用该分类
3. verifier 机制在判卷时自动标记"机械可判"的争议，过滤到 judge 之外

#### 断点2.3-B: judge 判例一致性保障

**断点描述**: judge archetype 声明"判例非规范"，但：
- 不同 judge 实例对类似争议可能给出不同判决
- 没有判例数据库或一致性检查机制
- 没有先例引用或遵循要求
- 判例可能被后续 judge 推翻，无追溯机制

**后果**:
- 同类争议在不同时间得到不同判决 → 治理不一致
- 开发者无法预判 judge 行为 → 开发效率降低
- judge 判例的质量无法累积 → 每次都从头判断

**建议修补**:
1. 引入**判例记录机制**：judge 的每次判决进入 ADR 或事件流，供后续 judge 参考
2. 在 judge archetype 增加 `precedent_ref` 字段，引用相关历史判例
3. 增加**判例一致性检查**：新判决与历史判例冲突时标记为"需升级"
4. 长期方案：构建判例知识库，由 curator archetype 维护

---

### 2.4 adversary 触发分析

#### 断点2.4-A: adversary findings 的消费路径

**断点描述**: adversary archetype 声明"findings 只进数据层"，执行 `control-tests（期望越权失败）` 和 `premortem`。

**后果**:
- Findings 进入数据层（JSONL）后，**谁来消费？**
  - 数据层没有自动消费机制
  - 事件流是 append-only 的，没有订阅者或处理管道
  - AR-7 说"过程数据三分离"——事件只进数据层，不进 git
- 如果 findings 不被消费：
  - 越权失败的 findings 可能被忽视 → 权限引擎 bug 持续存在
  - Premortem 的 insights 不被执行 → 项目重蹈覆辙
  - adversary 变成"形式上的合规"，没有实质影响

**建议修补**:
1. 引入**findings 消费管道**：数据层的 findings 定期由 governance-core 或 curator archetype 消费
2. 引入**严重度分级**：adversary findings 按 severity 分级，CRITICAL 级自动创建 issue
3. curator archetype 定期将 adversary findings 提炼为 ADR
4. 将 findings 消费率作为 governance-core 的 KPI

#### 断点2.4-B: adversary 测试与权限引擎 bug

**断点描述**: adversary archetype 执行 `control-tests`，期望"越权失败"。但：
- 如果权限引擎本身有 bug（如意外放行、规则缺失），adversary 的测试会**假阳性**（测试通过但权限引擎有 bug）
- adversary 只测"期望越权失败"的路径，不测"期望越权成功"的路径
- 假阳性的 findings 进入数据层后，无法区分是"权限引擎正确拦截了"还是"权限引擎根本没拦"

**后果**:
- 权限引擎 bug 被掩盖 → 长期积累后可能导致严重安全事故
- Adversary 测试结果不可信 → 信任危机
- AR-5 的"硬边界"被绕过而无人知晓

**建议修补**:
1. Adversary 的 control-tests 增加**双验证**：同时测试"越权失败"和"授权成功"两种路径
2. 引入**权限引擎自检**：由 verifier mechanism 定期（如 weekly）自检权限引擎的关键规则
3. Adversary 的测试结果增加**置信度标记**：标记哪些测试结果的可信度较低
4. T-11 (governance_canary) 扩展为权限引擎的 canary：定期尝试绕过权限引擎

---

### 2.5 所有 archetype 覆盖度分析

#### 9 种 LLM 原型在各流程中的触发分析

| Archetype | new_repo | governance_change | agent_team_lifecycle | rewrite_project | 必须触发 |
|-----------|:--------:|:-----------------:|:--------------------:|:---------------:|:--------:|
| **builder** | ❌ | ❌ | ✅(产出) | ✅(步骤3:模块实现) | ✅ |
| **planner** | ❌ | ❌ | ✅(任务分配) | ✅(步骤1-3:计划) | ✅ |
| **test-author** | ❌ | ❌ | ✅(验收测试) | ✅(每模块) | ✅ |
| **judge** | ❌ | ⚠️(分歧仲裁) | ⚠️(域内分歧) | ⚠️(差分争议) | ⚠️(条件触发) |
| **curator** | ❌ | ✅(ADR提炼) | ✅(归档) | ❌ | ✅ |
| **adversary** | ❌ | ❌ | ✅(control-tests) | ❌ | ✅ |
| **researcher** | ⚠️(选型调研) | ❌ | ⚠️(调研) | ✅(步骤4:fixtures) | ⚠️(条件触发) |
| **deployer** | ❌ | ❌ | ⚠️(部署) | ✅(步骤7:v2发布) | ✅ |
| **responder** | ❌ | ❌ | ❌ | ❌ | ❌ |

**图例**: ✅=必须触发  ⚠️=条件触发（可能不触发）  ❌=当前流程无触发点

#### 断点2.5-A: 死角色分析

**responder archetype —— 完全无触发点**：
- `new_repo`: 无部署/恢复需求
- `governance_change`: 变更流程无恢复路径
- `agent_team_lifecycle`: 生命周期事件中无恢复场景
- `rewrite_project`: 步骤 7 走的是 deployer 的环境审批流程，没有 responder 的恢复/回滚触发点

**后果**:
- responder archetype 声明了"预授权恢复动作（回滚/降级/开关）"和"先做后报全留痕"，但没有任何流程触发
- 如果 production 环境出现紧急故障，responder 的能力无处施展
- responder 的声明可能变成"纸面英雄"

**建议修补**:
1. 在 `rewrite_project` 增加**故障演练步骤**：步骤7之后增加步骤8"故障注入与恢复验证"，触发 responder
2. 在 `agent_team_lifecycle` 的 persistent 团队中增加**定期恢复演练**触发 responder
3. 或者：将 responder 作为 persistent 团队的常驻成员，在无故障时待命，有故障时自动触发

**judge, researcher —— 条件触发**：
- judge 只在"域内分歧"时触发，分歧频率低
- researcher 只在"选型调研"或"fixtures 抓取"时触发
- 这些 archetype 可能长期不被触发，导致：
  - LLM 能力退化（如果使用动态温度调整）
  - Prompt 过时
  - 模型族漂移

**建议修补**:
1. 增加**强制触发测试**：每个 archetype 至少每月触发一次（使用合成场景）
2. 在 drift-check 中增加 archetype 活跃度检查
3. 为条件触发 archetype 创建合成触发场景（如模拟分歧、模拟调研需求）

#### 断点2.5-B: 机制原型（verifier/integrator/scheduler/evidence-pack/interface-gateway/metrics-aggregator）的触发

**机制原型（非 agent）的覆盖度**：
- verifier: 在所有含 builder 的团队中必须触发（team verification 强制）
- integrator: 当前无显式触发点
- scheduler: 当前无显式触发点
- evidence-pack: 当前无显式触发点
- interface-gateway: 当前无显式触发点
- metrics-aggregator: 当前无显式触发点

**后果**:
- AR-8 说"六机制原型不实例化"，但没有说明它们的具体触发场景
- 机制原型可能同样存在"死角色"问题
- 它们的存在和正确配置无人验证

**建议修补**:
1. 在 `standards/archetype-profiles.yaml` 中明确每个机制原型的触发场景和配置要求
2. validate.py 增加机制原型的存在性检查
3. drift-check 增加机制原型的配置漂移检测
4. 为每个机制原型创建健康检查 dashboard

---

## 综合风险矩阵

| 严重度 | 风险 | 影响范围 | 修复优先级 |
|:------:|------|---------|:--------:|
| **P0** | GM-2 owner 伪约束 —— owner 可绕过任何治理 | 全组织 | 🔴 立即 |
| **P0** | new_repo 第3步申报遗漏 —— 最长7天无治理窗口 | 每个新仓 | 🔴 立即 |
| **P0** | break_glass 无惩罚机制 —— 回填超时无检测 | 所有变更 | 🔴 立即 |
| **P1** | verifier 存在性未验证 —— 可信交付链条断裂 | 所有 builder 团队 | 🟠 高 |
| **P1** | handoff 失败无重试 —— ephemeral 团队僵死 | agent_team_lifecycle | 🟠 高 |
| **P1** | responder 死角色 —— 无恢复能力 | production 故障 | 🟠 高 |
| **P1** | fake tests 无检测 —— mutation score 无升级 | 所有含测试的仓 | 🟠 高 |
| **P2** | test-author 冻结顺序无强制 —— 测试可能同义反复 | 所有含 test-author 的团队 | 🟡 中 |
| **P2** | adversary findings 无消费 —— 安全测试白做 | 安全治理 | 🟡 中 |
| **P2** | judge 判例无一致性 —— 治理不一致 | 争议仲裁 | 🟡 中 |
| **P3** | governance-core 自我变更无监督 | 治理核心 | 🔵 低 |
| **P3** | 条件触发 archetype 活跃度无监控 | 长期能力退化 | 🔵 低 |

---

## 关键发现总结

1. **信任根单点失效**: GM-2 声称"owner 与 AI 同受约束"，但技术实现上 owner 不受任何治理规则约束。这是最严重的结构性缺陷。

2. **检测 vs 响应的断层**: 多个检测机制存在（drift-check、verifier、mutation），但检测到异常后的**响应机制缺失**——没有自动修复、升级、通知管道。

3. **机制原型的幽灵化**: 6 个机制原型（verifier/integrator/scheduler/evidence-pack/interface-gateway/metrics-aggregator）在 schema 中引用但没有任何触发场景定义，`standards/archetype-profiles.yaml` 文件不存在。

4. **不可逆操作缺乏预演**: rewrite_project 的 R-06（fixtures 抓取）标注为"不可逆"但缺乏预演、回滚或备份机制。

5. **死角色**: responder archetype 和多个机制原型在当前所有流程中无触发点。

6. **事件流单向管道**: 事件流设计为 append-only 写入数据层，但没有定义消费管道——findings、violations、anomalies 可能永远不被读取。

7. **声明层 vs 运行时的双轨制**: 大量约束在声明层（schema validate）被强制，但运行时验证缺失——"结构合规 ≠ 行为正确"。
