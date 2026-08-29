---
taskId: IR-0006
specVersion: 1
title: 治理总纲吸收——三面分离治理架构、证据账本统一与云内网入图（条款级规格+六波次总图）
irRef: Cloudbird-Software/.github#402
adrRef: archive/adr/ADR-0103-governance-charter-absorption-three-plane-separation.md
acceptanceReport: specs/IR-0006/acceptance.md
amendments:
- rev: 1
  reason: 首版——owner 2026-08-29 会话 11 项锁定决策全集（ADR-0103 背书）；AC 自 IR#402 十条期望变化逐条派生；总纲 v1.0 分散吸收不立独立文档
acceptanceCriteria:
- id: AC-1
  given: 总纲 v1.0 十八部分章节与现有治理机制的映射关系
  when: 检查 specs/IR-0006/absorption-map.md 与本 spec PR 的红队审计
  then: 落位表覆盖 18 个部分（每行含落点/状态：已覆盖-直接映射、本 IR 吸收、延后-另行立项三类之一）且词汇归并表含 Wave/Broker/证据账本/Channel 四项等价映射；spec PR adversary check verdict=survived。运行时证据：adversary check run URL + absorption-map.md diff + 红队审计 issue 记录
- id: AC-2
  given: ADR-0103 已按家园单仓化流程落 archive 仓
  when: gate adr-required 与 drift-check §10 对 ADR-0103 的解析
  then: archive/adr/INDEX.yaml 含条目 103（content_sha256 与正本一致）且正本可达、lifecycle=active；宪法 §5（硬谓词+shadow）语义在 ADR-0103 与 constitution.md 中均未被推翻。运行时证据：INDEX.yaml diff + drift-check §10 run 日志
- id: AC-3
  given: 判定层账本载体落 archive 仓（evidence/ 目录）且证据 schema v1 定稿
  when: 对判定层写入与月度归档做核验
  then: 判定/轨迹/丢弃三层分离落 schema；payload 内联上限 4KB 超限拒写；hash 链头与月度 checkpoint 可由独立脚本复算验证（链断=红）；tenant 字段存在于每条判定记录。运行时证据：checkpoint 验证 run 的 JSONL 日志 + 账本目录 tree
- id: AC-4
  given: metering（ADR-0062）/ butler audit / drill history 三源事件存量
  when: 三源对齐改造完成后的统一查询
  then: 三源新事件可按同一 schema 查询（对齐 OTel gen_ai.* 字段命名），card-meta 为 join key；原 JSONL 只读保留可回退（平移不搬移）；tenant tag 注入到 metering 归账。运行时证据：统一查询 run 的 JSONL 输出 + 三源文件 diff（只增不改）
- id: AC-5
  given: 云内网（公网服务器+云电脑池+Vault+LLM 路由）为事实生产工厂
  when: 治理版图申报与漂移检测
  then: providers.yaml 含 self-cloud-pool 与 vault 条目（entry=服务器调度器，removal 声明同 CNB 模式）；env 定义仓按 flows.new_repo 建仓并申报 REPOS.yaml（layer/visibility/role/key_paths）；drift-check 对新申报面零漂移。运行时证据：providers.yaml/REPOS.yaml diff + drift-check run 日志 + env 仓建仓记录
- id: AC-6
  given: PM 会话已在云电脑上运行且个人 PAT 分布多机
  when: PM 凭证收敛完成后的日常写仓操作
  then: PM 的 GitHub 凭证由内网服务器代签 cloudbrid-agent 短令牌（gh-app-token 机制上收，单仓作用域）；个人 PAT 退出日常流程；应急回退通道（App 失效→owner PAT，24h 窗口）文档化。运行时证据：服务器令牌签发的 JSONL 记录 + TTL 到期收回断言日志
- id: AC-7
  given: 飞书多维表格作为 factory-floor 投影载体
  when: 投影运行与 drop & rebuild 演练
  then: 多维表格每行一卡（字段=状态/关卡/认领者/停留时长），数据源=label 唯一真源；整表删除后单轮同步内重建且字段一致；人工在表格上的修改被下一轮投影纠正（label 为准并告警）。运行时证据：rebuild 演练 run 日志 + 纠正实测记录 + 飞书 API 调用账本
- id: AC-8
  given: env repo 存期望态（环境定义/镜像/allowlist）且云内网上报实况
  when: R3 漂移对账与 SLO 周报
  then: 期望态与实况偏差触发漂移 issue（泛化 governance-drift 模式，自动开/自动关）；SLO 骨架进 sli-weekly；责任边界文件（SLO 定义/值班范围/破线升级路径/break-glass）落盘——在第一个托管客户出现之前。运行时证据：drift run 日志 + sli-weekly 报告 issue + 责任边界文件 diff
- id: AC-9
  given: card issue 模板扩展 budget/capabilities/evidence 字段
  when: 一张带波次预算的卡触发预算硬停
  then: conductor/cost-check 消费波次级预算（usd/tokens/wallclock/human_minutes）按 subject 聚合自统一账本；超限硬停+熔断标记；/elevate 评论走 arbiter 策略表（elevation 记录进账本）。运行时证据：预算超限硬停实测的 issue 记录 + cost-check run 日志
- id: AC-10
  given: holdout 仓扩展为 eval registry 且决策语料开始记录
  when: 首个 wave.kind=optimization 波次收口与语料累积
  then: eval registry 条目四元组 pin（代码+数据集+提示+模型）+ 非劣性 eval gate（不得比基线差超 δ）走通；决策语料文件（情境→选项→决策→理由→后果）append-only 落 archive 仓且不可篡改（链式 hash）。运行时证据：eval gate run 记录 + 语料 JSONL 及其 hash 链校验 run
blastRadius:
- repo: Cloudbird-Software/.github
  path: specs/IR-0006/（新增 spec/wave-plan/absorption-map/suite）
- repo: Cloudbird-Software/.github
  path: governance/（providers.yaml、REPOS.yaml、policy/ 账本条款、ISSUE_TEMPLATE 卡模板）
- repo: Cloudbird-Software/archive
  path: adr/（ADR-0103）、evidence/（判定层账本）、runs/、决策语料
- repo: Cloudbird-Software/CI-Workflows
  path: pipeline/metering/（三源对齐、tenant tag 注入）
- repo: Cloudbird-Software/<env-def-repo>
  path: 新仓（环境定义：拓扑/镜像/allowlist）
nonGoals:
- 不做治理编译器/policy rego 重写（GOVERNANCE.yaml intent/platform 分离已是手写编译器，演进不重写）
- 不建物理统一 egress 单点（broker=逻辑契约，物理分域适配）
- 不自建 harness（调度器=执行面基础设施≠harness；≥3 次妥协触发判据不变）
- 不做多账号 key 轮换（已否决，合规是护城河）
- 不做飞书 inbound 意图通道（污点标记/typed intent 延后另行立项）
- 不做外输三件套产品化（Profile/Policy Pack/Conformance Report——内部跑通后另行立项）
- 不做小模型训练与复杂 swarm 拓扑
- 不做潮玩公司完整分家工程（仅计量 tenant tag 先行）
inv: |
  INV-01 判定语义不随本次吸收改变：risk_class 仅参数包选择器（门禁集/entitlement 档/
  人工介入点），放行裁决仍硬谓词白名单+shadow 域解锁（宪法 §5 原样不动，ADR-0103 决策 1）。
  INV-02 判定锚点永不外置：云内网池与 CNB 同为可删除层；删除后 gate/org-gate/conductor
  语义不变（EX-1 延伸，ADR-0103 红线重申）。
  INV-03 append-only：判定层账本与决策语料只追加不改写；三源改造保留原 JSONL 只读
  （平移不搬移）；ADR-0062 hash 链机制平移且链断=红。
  INV-04 凭据纪律：key 只存 org secret/Vault，agent 上下文零凭据；PM 令牌收敛不改变
  此边界（服务器代签≠凭证进上下文）。
  INV-05 label 唯一真源：飞书多维表格=物化视图，可 drop & rebuild；投影与 label 漂移
  时以 label 为准并告警（宪法 §12 延伸）。
  INV-06 payload 指针纪律：判定层只存结论+指针，内联上限 4KB；轨迹层原始体只落内网
  blob，git 只存 sha256 摘要+指针+保留策略（ADR-0103 决策 3）。
budget: |
  BUDGET-01 判定层存储护栏：archive 仓 evidence/ 年增长软上限 200MB（gzip 后），
  超限开 governance-debt issue 而非静默扩容——账本膨胀本身是漂移信号。
  BUDGET-02 保留策略声明位：hot(90d)/warm(1y)/digest-only 三级+checkpoint 月度节奏
  声明在 governance/policy/（可 drift 对账、红队可审）；调整走 C1。
  BUDGET-03 波次预算四元组（usd/tokens/wallclock/human_minutes）真源=卡 issue 模板
  字段，cost-check 按统一账本 subject 聚合执法（超限硬停承 ADR-0040 复位流程）。
  BUDGET-04 本 IR 建设期消耗按 tenant=solo-co 归账（tenant tag 生效后追溯注入）。
decision: |
  DECISION-01 裁决模型调和：旋钮管配置不管裁决（ADR-0103 决策 1）；外输语言=
  参数包+谓词白名单+域解锁进度清单，非风险分。
  DECISION-02 三面分离：声明面=Git/执行面=内网+GitHub+CNB 多域/判定面=GitHub 恒定
  （ADR-0103 决策 2）；云内网=执行域+证据冷存储层。
  DECISION-03 证据三层承 ADR-0003 过程数据三分离：判定层 archive 仓永久/轨迹层内网
  blob+摘要指针/丢弃层 GitHub 原生保留（ADR-0103 决策 3）。
  DECISION-04 执行织物分界：GitHub 能启动的一律 GitHub Actions；自建调度器只承载
  PM 长驻会话与需内网资源作业；池化以公网服务器为锚（唯一出入口+调度+票据签发）
  （ADR-0103 决策 4）。
  DECISION-05 PM 凭证收敛 App 短令牌+JIT 分发由服务器承担；个人 PAT 退出日常
  （应急回退通道保留）（ADR-0103 决策 5）。
  DECISION-06 总纲分散吸收：18 章节落位表+词汇归并表为本 spec 附件；不立独立总纲
  文档；已覆盖机制直接映射防双 SSOT（ADR-0103 决策 6）。
  DECISION-07 飞书 outbound-only 多维表格投影；inbound 延后（ADR-0103 决策 7）。
  DECISION-08 建设时序内部跑通优先；潮玩公司仅计量 tenant tag 先行（ADR-0103 决策 8）。
---

# IR-0006 条款正文

本 spec 把《治理战略总纲 v1.0》按 ADR-0103 的裁决分散吸收进现有治理结构。
三个附件分工：[absorption-map.md](absorption-map.md)（18 章节落位表+词汇归并表——
总纲内容的唯一去向清单）、[wave-plan.md](wave-plan.md)（六波次建设总图——
本 IR 的执行计划）。本正文只立条款：不变量、行为、接口、预算、决策、假设。

## 条款

- **INV-01 裁决语义恒定**（AC-1/AC-2 承接）：risk_class 仅参数包选择器，放行裁决仍硬谓词+shadow（宪法 §5 不动）。任何把裁决语义参数化的条款变更=违宪，须新 ADR 推翻 §5 才可提出。
- **INV-02 判定锚点不外置**（AC-3/AC-5 承接）：云内网池为可删除层，removal 声明同 CNB 模式（REMOVAL 清单+删除后语义不变断言）。
- **INV-03 append-only 三处**（AC-3/AC-4/AC-10 承接）：判定层账本、决策语料、三源原 JSONL——只追加；hash 链平移（ADR-0062）；链断=红（fail-closed）。
- **INV-04 凭据纪律**（AC-6 承接）：服务器代签令牌仍单仓作用域+短 TTL；agent 上下文零凭据边界不变（AR-2 延伸）。
- **INV-05 label 唯一真源**（AC-7 承接）：飞书表格=第四投影（宪法 §12 三投影之外新增），人工修改被下轮纠正。
- **INV-06 payload 指针纪律**（AC-3 承接）：内联 ≤4KB 超限拒写；轨迹层 git 只存摘要+指针+保留策略。
- **BEH-01 账本写入路径**（AC-3 承接）：判定事件（gate 裁决/成本/审批/决策）经统一发射器写 archive evidence/，字段对齐 OTel gen_ai.* 语义约定；写入失败=fail-closed（同 butler-audit 守卫模式）。
- **BEH-02 月度 checkpoint**（AC-3 承接）：每月末对判定层做 checkpoint（链头 hash+当月汇总）提交 git；独立验证脚本可从任意旧 blob 复算整链。
- **BEH-03 三源渐进对齐**（AC-4 承接）：metering/butler/drill 新事件按 schema v1 双写过渡期一个波次，验证一致后旧格式停写；原文件冻结只读。
- **BEH-04 云内网对账**（AC-5/AC-8 承接）：env repo 存期望态；服务器上报实况快照；drift 引擎泛化（GitHub org 对账→环境对账），偏差开 issue、消除自动关（GM-1 模式复用）。
- **BEH-05 令牌签发与收回**（AC-6 承接）：服务器按 wave 生命周期签发短令牌（TTL≤波次）；TTL 到期自动收回；elevation 走 arbiter 策略表（附理由+spec 引用，批准记录进账本）。
- **BEH-06 投影同步与重建**（AC-7 承接）：同步器周期（≤15min，同 butler-ledger 节奏）从 label 真源重建表格差异；drop & rebuild 单轮完成；漂移告警进账本。
- **BEH-07 波次预算硬停**（AC-9 承接）：cost-check 从统一账本按 subject 聚合四元组预算；超限置熔断+撤 auto-merge+开 issue（ADR-0040 复位流程不变）。
- **BEH-08 非劣性 eval gate**（AC-10 承接）：optimization 波次的 exit gate=eval 家族（非劣性检验不得比基线差超 δ+污染检查+成本/延迟回归）；四元组 pin 进 registry。
- **IFACE-01 证据记录 schema v1**（AC-3/AC-4 承接）：`{subject:{wave,card,tenant,commit}, actor:{identity,role,model}, action, verdict, cost:{tokens,usd,wall_sec}, inputs_digest, payload_ref?, ts}`；字段命名对齐 OTel gen_ai.*；schema 文件落 standards/。
- **IFACE-02 providers.yaml 新条目**（AC-5 承接）：`self-cloud-pool`（kind: compute，entry=服务器调度器，secrets=[]——凭据在内网域 Vault，非 org secret）与 `vault`（kind: secret，entry=内网 Vault，标注"仅执行面内网域生效"）。
- **IFACE-03 卡模板扩展**（AC-9 承接）：card 模板新增 `budget:`（四元组+on_exceed）与 `capabilities:`（allowlist 式 org secret/Vault 引用）字段；conductor 解析存储、cost-check 消费。
- **IFACE-04 多维表格 schema**（AC-7 承接）：字段=卡 ID/状态/AC 进度/关卡状态/认领者/停留时长/谓词状态；与 factory-floor 板字段同源（宪法 §12 投影一）。
- **IFACE-05 env 定义仓结构**（AC-5/AC-8 承接）：`environments/*.yaml`（拓扑/镜像/网络 allowlist/secret 引用非值/资源上限）+ `reports/`（实况快照落点）。
- **BUDGET-01 判定层存储护栏**：见 frontmatter。
- **BUDGET-02 保留策略声明位**：见 frontmatter。
- **BUDGET-03 波次预算真源**：见 frontmatter。
- **BUDGET-04 建设期归账**：见 frontmatter。
- **DECISION-01..08**：见 frontmatter decision 块（ADR-0103 逐条承接）。
- **ASSUMPTION-01** 云内网服务器上报通道可用（不可用=对账 fail-closed 转 issue，不静默）。
- **ASSUMPTION-02** 飞书开放平台 API 配额满足 15min 级投影刷新（不足则降级为小时级，多维表格为物化视图不受损）。
- **ASSUMPTION-03** 云电脑池 worker 可承受无状态约束（任何持状态负载一律拒置内网池——同 CNB 定位纪律）。

## 测试设计（逐类讨论，ADR-0095 一等公民）

判断口径：每个测试映射三类风险之一（customer_upgrade_failure / llm_behavior_drift / fake_tests）。

### active_now

- **T-01 属性（unit_property_golden）— adopt**：证据 schema v1 记录做属性测试（必填字段/枚举值/ISO 时戳/payload ≤4KB 不变量）——映射 fake_tests 风险（摆拍账本）。suite 本 PR 先锁 spec 结构属性；实现波次锁记录属性。
- **T-02 race — adopt**：判定层并发追加幂等（同事件双写=一条+审计行）；checkpoint 验证与追加并发不死锁——映射 fake_tests。
- **T-03 泄漏 — adopt**：账本/语料/轨迹摘要中扫描 secret 模式（gitleaks 复用）+ holdout 诱饵内容出现在任何账本记录=报警——映射 llm_behavior_drift 与凭据纪律。
- **T-04 模糊 — adopt**：schema 解析器对畸形输入 fuzz（未知字段不崩、缺字段拒收、超限 payload 拒写）——映射 fake_tests。
- **T-05 文档示例 — adopt**：absorption-map.md 与 wave-plan.md 中出现的命令/路径引用做可执行校验（导航断链=test-navigation.sh 同款）。
- **T-08 flaky — reject**：本 IR 断言全部确定性（账本/声明面），无网络依赖断言；飞书投影测试用录制 fixture。
- **T-09 差分 — reject**：非重写项目（无新旧实现并存面）；三源对齐用对账而非行为差分。
- **T-10 变异 — adopt**：实现波次的判定/预算逻辑（checkpoint 验证、预算聚合）做变异测试（承宪法 §4A 三档阈值）。
- **T-12 diff 覆盖 — reject**：治理仓无产品代码面，沿现有 gate 语义。
- **T-13 测试完整性 — adopt**：本 suite 即 spec 结构完整性的机器断言（AC 三段/条款唯一/附件在场）。
- **T-14 卡绑定+suite 门 — adopt**：本 spec PR 自身受 T-14 约束（suite 随 PR、CI 真实执行）；实现卡卡绑定走 conductor。
- **T-15 意图回探 — adopt**：acceptance.md 验收时逐条回探 IR#402 十条期望变化（ROLE-ACCEPT 对账基准）。

### 条件激活族

- **L-01..L-04（eval/semantic golden/蜕变/对抗语料）— reject**：本 IR 不改变任何 LLM 判定链行为（verifier/adversary 不动）；L 族属 R5 optimization 波次届时激活。
- **L-05 成本时延 — adopt（窄）**：判定层账本写入路径与投影刷新的时延断言（预算旋钮 K/pivots 不变，承 automation-limits verifier 档先例）。
- **L-06 换模型差分 — reject**：同上，无判定模型变更。
- **R-01..R-06（升级/回滚/迁移幂等/抓 golden）— adopt（R-02/R-03 窄面）**：PM 凭证收敛有回退形态（App 失效→PAT 应急）；三源 schema 迁移幂等（双写过渡+可回退）；其余 reject（无系统重写）。
- **G-01 契约漂移 — adopt**：providers.yaml/REPOS.yaml/env 定义与线上实况对账即本 IR 的 drift 面（BEH-04）。
- **G-02..G-08 — reject**：无真实依赖集成/DAST/bench 面（治理仓无运行时服务；内网调度器 W2 建成时另行补充）。

### rejected 清单（X-01..X-06）

不启用任何 X 族条目（如全局覆盖率门槛）——维持 testing.yaml 声明的拒绝态；启用须先走治理变更（ADR）。

## holdout 测试设计（ADR-0095 必备）

封存验收场景三条（payload 由 verifier-app 经 `scripts/holdout-register.sh` 注册至
holdout 仓，W1 内完成；本 spec 只设计场景不携带内容——防泄题）：

1. **HO 账本篡改检测**：对判定层账本注入一条被篡改记录（改 verdict 不改链），验证 checkpoint 复算必红（fail-closed 活体证明）。映射 fake_tests。
2. **HO 投影重建保真**：对多维表格注入人工违规修改（绕过 label 真源改字段），验证下轮投影必纠正且告警进账本。映射 llm_behavior_drift（投影漂移）。
3. **HO 凭证边界**：PM 令牌 TTL 过期后持旧令牌写仓必拒；elevation 无理由请求必拒。映射 customer_upgrade_failure（凭证失效面）。

注册后 spec/卡引用仅 `id@sha8` 形态；泄漏监控承 holdout 仓既有诱饵机制（I5 延续）。

## 验收对账

acceptance.md（W6 收口）按 T-15 逐条回探 IR#402 十条期望变化+冷上下文六问复测
（a-f 六问有真实来源可答，主链路零假链——IR-0005 AC-7 同款）。
