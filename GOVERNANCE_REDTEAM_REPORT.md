# Cloudbird-Software 治理体系红队演练报告

- 演练对象：组织 `Cloudbird-Software` 的三个治理仓（`.github` / `CI-Workflows` / `agent-registry`，见 `governance/REPOS.yaml`）声明的规则、政策、agent/团队定义
- 演练方式：起 6 个独立子代理，按不同真实开发流程各做一轮红队推演（越权/合并守卫、治理变更、新仓初始化、agent 团队生命周期、漂移闭环、角色触发矩阵），全程只读、无事务性命令，结论跨代理相互印证
- 结论基调：**声明层完备、机器层执行稀薄**。大量护栏"只声明、无实现或实现不可验证"；治理链条存在多处流程断点、死亡角色、无人认领任务与反馈死循环。

---

## 一、严重度总览

| 级别 | 数量 | 代表问题 |
|---|---|---|
| 🔴 P0 | 5 | org-admin 凭据落公开仓；守卫（gate）本身无内容防线；AD/ADR 无机器校验；漂移问题无人干预下无限报警；App 名称错位导致初始化静默失败 |
| 🟠 P1 | 8 | 治理单点（bus factor=1）永久搁置；多个角色永远无法触发；governance-core 幽灵实体；语义削弱检测不到；供应链初始脚本未 pin；24h 承诺无执行力等 |
| 🟡 P2 | 6 | §8 直推检测正则真假阴性；code-security 只写不可读；部分漂移无 owner 认领；数据层落盘无实现等 |
| ⚪ 依赖外部不可本地验证 | 6 | validate.py / models.yaml / telpher CI-Workflows / openjiuwen 运行时，均未落盘本地 |

---

## 二、P0 级问题

### F1. org-admin 凭据常驻公开仓 workf workflow —— identity_scope 风险实锤
- `.github` 为公开仓。`governance-drift.yml` 把 `secrets.GOVERNANCE_TOKEN`（脚本注释明确要求"org admin token"）注入 runner，并被 `drift-check.sh` 以 admin 身份调用全部 `api()`。
- 拿到该 token = 拥有全部 ruleset 的 `OrganizationAdmin` bypass + `workflows` 编辑权 + repo/code-security 配置权限。它同时是 §8/§9 反复使用的凭据，且 `expected-state.json` 的 `org_secrets_required` 里根本没列它（声明与使用脱节）。
- 证据：[governance-drift.yml](file:///workspace/.github/workflows/governance-drift.yml#L21-L27)、[drift-check.sh](file:///workspace/governance/drift-check.sh#L19-L22)、[expected-state.json](file:///workspace/governance/expected-state.json#L32-L35)、[REPOS.yaml](file:///workspace/governance/REPOS.yaml#L20-L25)
- 建议：改用权限剥到只读 + 必要读取权的最小令牌（或用 OIDC/short-lived），且 `drift-check` 只读检测逻辑必须彻底去掉对写权限的依赖。

### F2. 守卫的守卫：gate 本身无任何内容防线
- 现有防护几乎全部压在"App 无 `workflows` 权限，碰不了 workflow"这一平台规则上。
- 一旦拿到 admin 凭据（F1），把 `gate.yml` 改成空转即可让所有 required status 变绿；而 `drift-check.sh` 九个 section **没有一个**比对 workflow 文件内容，`flows.governance_change` 的 C1/C2/C3 scope 也未覆盖 `.github/workflows/*`。
- 证据：[gate.yml](file:///workspace/.github/workflows/gate.yml)、[GOVERNANCE.yaml](file:///workspace/governance/GOVERNANCE.yaml#L191-L201)（C1-C3 scope）、[drift-check.sh](file:///workspace/governance/drift-check.sh)
- 建议：把 workflow 文件本身纳入治理版本库的完整性校验（如对受控 workflow 做 hash 快照比对），并显式归属 owner。

### F3. "无 ADR 不合并"只有声明，没有机器校验
- C1 变更要求 `[PR, ADR, drift-check 本地预检, owner-merge]`，本仓唯一 gate 只做 YAML/JSON/`bash -n` 语法 + REPOS 重名检查，**无任何 ADR 存在性校验**。
- 证据：[GOVERNANCE.yaml](file:///workspace/governance/GOVERNANCE.yaml#L194-L195)、[gate.yml](file:///workspace/.github/workflows/gate.yml#L29-L44)
- 建议：gate 增加对 C1 范围的 ADR 存在/编号校验；对 `rulesets/*.json` 做语义校验（不得移除 `gate` 必需状态、不得把 enforcement 降级为 evaluate）。

### F4. 漂移修复的死循环：不可修复类漂移会无限周报警
- `governance-drift.yml` 每周一检测，任一 `DRIFT` 则 `exit 1`，用固定标题在同一个 open issue 上幂等追加并 `@randypanding`；**没有任何自动 close 分支**。
- `apply.sh` 只能修 §1 rulesets / §2 actions / §4 仓基线 / §3(仅当配置已存在)。§3-不存在、§5 secrets、§6 App 权限、§7 REPOS、§8 直推、§9 admin 数量，apply 全修不了 → 每周复用同一 issue 无限报警。
- 证据：[governance-drift.yml](file:///workspace/.github/workflows/governance-drift.yml#L29-L47)、[apply.sh](file:///workspace/governance/apply.sh)、[drift-check.sh](file:///workspace/governance/drift-check.sh)
- 建议：漂移 issue 增加 TTL / 自动 close / 连续 N 周同一报警即停噪并升级；区分"apply 可修复"与"需人工"两类并分别派发。

### F5. App 名称错位：`cloudbrid-agent` vs `cloudbird-agent`
- 创建清单用 `cloudbird-agent`（HTML manifest），而初始化的挂载脚本按 `app_slug == "cloudbrid-agent"` 查询、期望状态也写 `cloudbrid-agent`，拼写相差一个 "i"。
- 后果：新仓自动挂载 `.installations[]` 查不到 → `INSTALL_ID` 为空 → 挂载失败；且 `drift-check §6` 按期望名查 `apps/cloudbrid-agent` 会**恒定 DRIFT**。
- 证据：[create-cloudbird-agent-app.html](file:///workspace/scripts/create-cloudbird-agent-app.html#L12)、[new-repo-init.sh](file:///workspace/scripts/new-repo-init.sh#L30-L31)、[expected-state.json](file:///workspace/governance/expected-state.json#L37)
- 建议：全局统一 App 名（含 manifest / init / expected-state / GOVERNANCE AG-1），并加 CI 自检断言三处一致。

---

## 三、P1 级问题

### P1-1. 治理单点（bus factor = 1）：owner 缺席即永久搁置
- `randypanding` 同时是：`.github` 与治理仓 CODEOWNERS 全路径唯一 owner、所有 C1 审批人（`require_code_owner_review`）、漂移 issue 唯一被 @ 的人、全系统 admin 唯一且=owner（drift §9）、production env 默认 reviewer、ruleset 唯一 bypass actor。
- 任一环境 owner 不在 → 所有治理 PR 无 codeowner 批准、漂移无人认领/修复、admin 唯一性判定错乱。
- 证据：[CODEOWNERS](file:///workspace/CODEOWNERS)、[main-protection.json](file:///workspace/governance/rulesets/main-protection.json#L21-L27)、[drift-check.sh](file:///workspace/governance/drift-check.sh#L163)、[new-repo-init.sh](file:///workspace/scripts/new-repo-init.sh#L27)
- 建议：引入 backup owner / 团队审批、为漂移案提供第二认领人。

### P1-2. 角色触发矩阵：多个声明的角色在现实中无法被触发
| 角色 | 声明 else | 现实判定 |
|---|---|---|
| planner | [agent.schema:27](file:///workspace/standards/agent/agent.schema.yaml#L27) | 无任何 flow 调用 planner，无 plans 落盘流程 → 无法触发 |
| test-author | [team.schema:41-43](file:///workspace/standards/agent/team.schema.yaml#L41-L43) | 本仓无 team 声明，test_authors 无可装配 → 无法触发 |
| judge | [agent.schema:29](file:///workspace/standards/agent/agent.schema.yaml#L29) | 既禁 as_tool 又无裁决提交流程 → 死亡角色（永远没案子） |
| researcher | [agent.schema:32](file:///workspace/standards/agent/agent.schema.yaml#L32) | 唯一 untrusted_ingest 却无摄取流程/写入端点 → 死亡角色（信任边界失守） |
| responder | [agent.schema:34](file:///workspace/standards/agent/agent.schema.yaml#L34) | 无 hosted 服务、无 incident/rollback workflow，客户本地回滚无人下达/执行 → 对风险提纲首项失守 |
| deployer | [agent.schema:33](file:///workspace/standards/agent/agent.schema.yaml#L33) | production env 只建闸门不建执行端 → 无法触发 |
| adversary | [agent.schema:31](file:///workspace/standards/agent/agent.schema.yaml#L31) | AR-9 的"控制测试"无实现、无 premortem workflow → 无法触发 |
| curator | [agent.schema:30](file:///workspace/standards/agent/agent.schema.yaml#L30) | 漂移/归档响应被 owner 硬编码接管，curator 名存实亡 |
| 六机制原型 | [agent.schema:23-24](file:///workspace/standards/agent/agent.schema.yaml#L23-L24) | 集体引用缺失的 `standards/archetype-profiles.yaml` → 幽灵定义 |

### P1-3. 幽灵持久团队 `governance-core`
- 被 AR-6、flow agent_team_lifecycle、team.schema external_audit 三处引用为唯一 persistent 团队，但本仓**无任何 team 声明文件**，REPOS.yaml 也未列出团队。
- 结果：AR-6（handoff 强制）与 AR-9（外部审计）因承载团队不存在而**无法落实**；escape-review / control-test-report 审计环节永远触发不了。
- 证据：[GOVERNANCE.yaml:171,226](file:///workspace/governance/GOVERNANCE.yaml#L170-L173)、[team.schema:54-59](file:///workspace/standards/agent/team.schema.yaml#L54-L59)

### P1-4. handoff 六动作无人认领
- `team.schema` 定义 [artifacts-pr, memory-distill, skill-extract, adr-write, trace-archive, retrospective]，但**未指派任何 actor/owner**；销毁前是否完成（AR-6）的校验委托给外部 `validate.py`（本仓无实现），`event.run_finished.handoff_done` 只是没人消费的布尔字段。
- 证据：[team.schema:79-87](file:///workspace/standards/agent/team.schema.yaml#L79-L87)、[event.schema:63-64](file:///workspace/standards/agent/event.schema.yaml#L63-L64)

### P1-5. 治理语义削弱检测不到
- 改 `rulesets/*.json` 删掉 `gate` 必需状态或把 enforcement 降为 evaluate，gate 只做 jq 语法、drift 只做"落盘文件 vs 线上自洽"比对，**不比对文件 vs GOVERNANCE intent/strength** → 语义被削弱只在 owner 人工把关，机器层面零校验。
- 证据：[gate.yml:30](file:///workspace/.github/workflows/gate.yml#L30)、[drift-check.sh:34-45](file:///workspace/governance/drift-check.sh#L34-L45)

### P1-6. 分级可绕过：把 C1 文件标成 C3 无机器识别
- C1 scope 的 `expected-state.json` 不在 gate 校验范围（jq 只遍历 `rulesets/*.json`），预检/ADR/owner-merge 约束可被"标成 C3"整体绕过，drift 只认自洽不认分级。
- 证据：[GOVERNANCE.yaml:193-200](file:///workspace/governance/GOVERNANCE.yaml#L193-L200)、[gate.yml:30](file:///workspace/.github/workflows/gate.yml#L30)

### P1-7. 新仓初始化：静默失败 + admin 墙 + 供应链面
- 步骤1 `gh repo create` 需 admin（agent 无），且 `member_can_create=false` → AI 初始化第一步即被 admin 墙挡住。
- 步骤3 挂载失败仅 `echo`、**不 exit 1**，脚本继续并打印"完成" → 仓库建但 agent 写不进的**静默断点**。
- 步骤4 漏申报被 §7b 检出后无自动认领，`apply.sh` 不写 REPOS.yaml。
- 标准流程从 public `.github/main/scripts` `curl <(...)` 在 admin 凭据上下文执行、**未 pin commit/tag** → 供应链攻击面。
- 证据：[new-repo-init.sh](file:///workspace/scripts/new-repo-init.sh)、[GOVERNANCE.yaml:206-211](file:///workspace/governance/GOVERNANCE.yaml#L206-L211)

### P1-8. "24h 回填"承诺无执行力
- break_glass 承诺 24h 内补 ADR+PR，但检测是**周频**（非实时/非 24h），issue 只 `@randypanding`，无自动建回填 PR、无到期提醒、无升级；§8 窗口 `max(policy_effective, now-7d)` 使超 7 天的直推还会漏检。
- 证据：[GOVERNANCE.yaml:202-205](file:///workspace/governance/GOVERNANCE.yaml#L202-L205)、[drift-check.sh:141-147](file:///workspace/governance/drift-check.sh#L141-L147)

---

## 四、P2 / 依赖外部问题

### P2-1. §8 直推检测正则的真假阴性
- 正则仅看 commit 消息是否以字面 `(#N)` 结尾 → rebase/merge 合并（不加 `(#N)`）被**误判直推（假阳性）**；而刻意把直推消息写成 `xxx (#N)` 可**绕过检测（假阴性）**。
- 与 `main-protection` 的 `do_not_enforce_on_create:true`（放行新仓首推）**语义矛盾**，新仓 bootstrap 首推会被 §8 误报。
- 证据：[drift-check.sh:150-151](file:///workspace/governance/drift-check.sh#L150-L151)、[main-protection.json:54-55](file:///workspace/governance/rulesets/main-protection.json#L54-L55)

### P2-2. code-security 只写不可读
- `default_for_new_repos` 是只写 API，drift-check 无法只读验证、apply 幂等覆盖失败不报 → SC-2 实际不可验证。
- 证据：[drift-check.sh:73-76](file:///workspace/governance/drift-check.sh#L73-L76)

### P2-3. 无人认领的任务清单
| 任务 | 出处 | 现状 |
|---|---|---|
| flaky 隔离+修复回归 T-08 | [testing.yaml:16-17](file:///workspace/governance/policy/testing.yaml#L16-L17) | 无 owner、无自动化 |
| mutation <60% 响应 T-10 | [testing.yaml:20-21](file:///workspace/governance/policy/testing.yaml#L20-L21) | 无响应路径 |
| eval 漂移 L-02 / 换模型差分 L-06 | [testing.yaml:35-40](file:///workspace/governance/policy/testing.yaml#L35-L40) | 无响应人 |
| 依赖引入审批（GPL/AGPL 禁入） | [languages.yaml:45-48](file:///workspace/governance/policy/languages.yaml#L45-L48) | enforcement=review 却无审批人 |
| cost/latency 报警 L-05 | [testing.yaml:39](file:///workspace/governance/policy/testing.yaml#L39) | 无响应人 |

### P2-4. 依赖外部、本地不可验证的护栏（潜在空洞）
- CI-1 聚合 gate、CI-4 zizmor、SC-3/4 → 依赖未落盘的 CI-Workflows / template-service
- AR-1/2/6/8/9、no-test-weakening、内联凭据校验 → 依赖未落盘的 agent-registry `validate.py` / `models.yaml` / `side-effects.yaml`
- AR-3/5/7 强制 → 依赖外部 openjiuwen 编排运行时
- 数据层落盘（event → JSONL/对象存储）→ 本仓无任何写入端/retention 实现
- 建议逐一确认线上是否已部署，未部署即为只见声明、无实现。

---

## 五、演练方法说明与范围

- 演练为**静态红队推演**（本地 read-only），未实连 GitHub API、未运行任何写操作；因此"线上是否已 apply"、"CI-Workflows/agent-registry 实际实现"无法判真，统一标注"依赖外部"。
- 三个治理仓中仅 `.github` 内容完整落盘；`CI-Workflows` 与 `agent-registry`（真正承载 `gate` 内容与 `validate.py`）属引用型，其健壮性不在本次验证范围内，是需要单独审计的第二现场。

## 六、处置建议（按优先级）

1. **收敛凭据（F1）**：替换 org-admin `GOVERNANCE_TOKEN` 为最小权限令牌，并让 drift-check 只读化。
2. **给 gate 加内容防线（F2/F3/P1-5/P1-6）**：workflow 文件 hash 纳入治理校验；C1 强制 ADR；ruleset 语义校验；expected-state 纳入 gate 与分级校验。
3. **修漂移闭环（F4/P1-8）**：issue TTL/自动 close/降噪；区分自动可修与人工；为"不可修类"建立显式 owner 与升级。
4. **统一 App 命名并加自检（F5）**。
5. **消除 ghost 实体（P1-2/P1-3/P1-4）**：真正声明 team 文件与 `governance-core`；为每个 archetype 绑定可触发流程与 owner；为新仓第 1 步提供一条 agent 可独立完成的路径，消除 admin 墙与静默失败。
6. **降低 bus factor（P1-1）**：引入 backup owner / 团队审批 / 自动移交。
7. **补齐无人认领任务（P2-3）**、**pin 供应链脚本（P1-7）**、**修 §8 检测法（P2-1）**。