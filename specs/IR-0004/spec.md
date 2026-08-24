---
taskId: IR-0004
specVersion: 1
title: 验证体系缺口闭环（变异/属性/模糊/蜕变/符号/形式化条件触发/SAST 台账）+ spec 质量测量（DSL 编译与骨架 fan-out）+ 实现 fan-out 生命周期（early-exit/champion/oracle/红队燃料管道）+ CNB 临时算力底座条款级规格
irRef: Cloudbird-Software/.github#315
acceptanceCriteria:
- id: AC-1
  given: aws-tb 仓 weekly 变异测试执行入口已落地
  when: 该入口每周运行且 LLM 生成的定向变异体候选提交
  then: 分数与趋势出现在治理仪表盘、趋势下滑自动告警、候选经机械初筛（可执行性与被现有套件杀死率预演）后入池且淘汰率入账；分数核算与入池判定仅由 GitHub CI 执行；运行时证据为 run 链接、仪表盘 JSON 与入池清单三件
- id: AC-2
  given: 属性不变量候选已经机械过滤为可执行属性
  when: 变异裁判对候选执行裁定
  then: 每条候选产生"杀死的变异体清单"日志、杀死数为零者标记平凡并拒收、存活者进入常驻测试随 CI 运行；运行时证据为裁判日志（含至少一条平凡拒收样本）与常驻测试运行记录
- id: AC-3
  given: schema 感知的模糊测试种子语料已入库且深跑任务已派发至外部沙箱
  when: 深跑完成
  then: 覆盖率增量与唯一崩溃数由 GitHub 侧核算（沙箱自报数字不采信）、崩溃样本经栈哈希机械去重、LLM 产物仅标记为草稿的分诊建议；运行时证据为语料入库历史与 GitHub 侧核算日志
- id: AC-4
  given: aws-tb 领域自然蜕变关系经 fan-out 盘点产出结构化候选
  when: 人类抽检完成
  then: 候选不少于 15 条且每条含机械可验证方式字段、不少于 3 条实现为常驻测试、testing.yaml 新增对应条款；运行时证据为候选清单、抽检记录与条款 diff
- id: AC-5
  given: 符号执行试点已在解析/实例化纯函数目标上运行
  when: 试点数据齐备
  then: 产出含路径覆盖、求解超时率、单位时间发现数的证据报告并按三段式判据回答 adopt 或 reject；adopt 则登记触发式条款、reject 则登记拒绝条款并带翻案条件，两种结论均视为验收通过；运行时证据为报告、指标原始数据与条款 diff
- id: AC-6
  given: SAST 告警分诊台账已建立并回填存量告警
  when: weekly 清点运行
  then: 每条告警处置（固修/豁免附 ADR 引用/判误报附理由）结构化入账且不可改写、未处置告警自动开 issue、误报率与豁免存量入仪表盘；运行时证据为台账文件、一次清点 issue 与仪表盘 JSON
- id: AC-7
  given: 形式化验证适用性 checklist（机器可读、治理路径）与卡模板风险等级字段已落地
  when: 一张卡进入形式化触发判定
  then: 判断由弱模型或纯脚本按元数据执行且逐项理由留痕入卡、同输入重跑判定一致、风险等级缺失被 fail-closed 拦截、判适用即自动启动形式化作业并以 kernel 二值结果回写、判不适用同样留痕；X-04 由无条件拒绝修订为条件触发（经 ADR）；运行时证据为一次真实触发全链记录、一次不适用留痕、拦截反向测试与 ADR diff
- id: AC-8
  given: 验收 DSL 已定义且新 spec 以 DSL 书写验收标准
  when: spec PR 合并
  then: DSL 验收标准机械编译为测试骨架且携带 spec hash 溯源头、手改生成测试触发 CI 红、修改 spec 重编译后转绿、spec CI 关卡（结构校验/可编译/blastRadius 申报路径存在性）在 specs 路径全部 PR 生效且关卡被摘除时 CI 必红；豁免仅经 ADR 登记通道且计数入账；运行时证据为编译产物、篡改红记录与一次 spec PR 全关卡绿
- id: AC-9
  given: 一张卡处于 spec 阶段且骨架 fan-out 已派发（N 默认 3–4、含至少一个异构模型实例）
  when: N 份骨架（路线陈述/接口签名草稿/测试草案/假设清单四组件）齐备
  then: 分歧正交分解由脚本执行（契约解读分歧输出为 spec 修订项、路线分歧落盘为策略菜单）、N 份测试草案的交集进入验收标准候选、并集减交集进入红队输入、假设清单去重并集成为 spec 缺口显式清单、趋同度与分歧率入仪表盘且高分歧自动退回规划层；运行时证据为骨架产物、机械计算日志与仪表盘数据
- id: AC-10
  given: 实现决策矩阵（决策密度×可判定性）已入政策
  when: 一张卡进入实现阶段
  then: 低决策密度卡自动获得免 fan-out 标签、通过 gating 的卡以 N 路并行实现（策略来自骨架策略菜单）、第一个通过全部既有 gate 的实现立即合并且不跳过任何 gate、其余实现转后台执行全量评价；运行时证据为标签记录与多路实现的完整时间线
- id: AC-11
  given: 后台实现完成全量 gate、性能基准与对拍
  when: 后台结果优于现任 champion 且对拍等价
  then: 替换经改进 PR 通道进行且必须同时通过 oracle 对拍与全部 gate 双重裁决；运行时证据为改进 PR 及其双重裁决记录
- id: AC-12
  given: 实现竞速完成且存在跨路线簇的亚军
  when: oracle 冻结执行
  then: 冻结记录含簇归属与去相关理由、champion 与 oracle 对拍常驻运行且硬区/软区边界标注落盘、硬区分歧即暂停相关合并并路由裁决（缺陷修复或契约修订二选一）、oracle 只换代不修补且换代流程脚本化；运行时证据为冻结记录、对拍运行历史与一次注入分歧的裁决记录
- id: AC-13
  given: fan-out 产物（骨架分歧/假设/淘汰路线/对拍分歧四类）统一以结构化格式落盘（含卡 ID、spec hash、基准 SHA）
  when: 红队或意图道闸运行
  then: 输入适配器只读该产物目录、被淘汰路线机械生成差异攻击查询（champion 是否覆盖其边界）、假设清单进入 S6–S8 扫描候选、S8 集合比对纳入产物路径、产物消费前经基准 SHA 机械核对且不符作废留痕；运行时证据为一次真实红队消费燃料产物的全链记录与一次道闸消费留痕
- id: AC-14
  given: cnb-bridge 仓建立且治理仓新增外部算力声明条目
  when: 隔离审计运行
  then: 治理仓内全部 CNB 引用仅命中三处接缝（声明条目/组织秘密清单/两个工作流）、删除清单单页存在且其审计脚本 dry-run 输出影响报告零副作用；运行时证据为审计命令输出
- id: AC-15
  given: 配额以配置存在（账号清单/档位阈值/并发上限/告警线）且快照与实耗两路数据齐备
  when: 记账运行
  then: 加账号仅改配置零代码、逐账号核·秒差值可查且偏差超阈值告警、余量低于阈值自动开成本类 issue、默认档位为最低核数档（8 核档禁用）且档位以构建记录标签证实；运行时证据为仪表盘数据、告警记录与含最低核数标签的构建记录
- id: AC-16
  given: 账号生命周期 runbook（每步带验收命令）与 append-only 生命周期台账已建立
  when: 一个未参与开发的 AI 仅凭 runbook 执行新账号入职
  then: 全流程无人工判断步骤、最终 canary 任务通过、入职/降级/退休/事故全部留痕且纠错仅以追加方式；运行时证据为该 AI 会话记录、生命周期台账与 canary 构建记录
- id: AC-17
  given: work-inbox 工作发现入口协议（pending 定义/租约/心跳/产物写回）已落地
  when: 强模型按小时自起连续七天
  then: 有 pending 时认领带租约且并发会话不重复认领、租约超时可被接管且原认领作废留痕、无 pending 时仅追加心跳行零派单、任何派单以清单 ID 去重；运行时证据为七天运行历史与会话记录
- id: AC-18
  given: 周审计（配额/活性/延迟/产物真实性抽样/平台政策 diff）已自动化
  when: 审计运行
  then: 五项齐全以结构化 issue 产出、政策页变更自动告警、任一红项产出死开关置位建议；运行时证据为连续四周审计 issue 链与一次注入红项处置记录
- id: AC-19
  given: 功能演练脚本就绪
  when: 季度演练自动执行
  then: 置位死开关→发散链切换付费 API 回退完成一轮真实任务→gate 全绿→自动复位→计时报告全程零人工；物理删除仅为一次性退休动作不做演习且此证明力边界已入册；运行时证据为演练计时与回退任务 run 链接
- id: AC-20
  given: 本 IR 的一张高可判定实现卡进入执行
  when: 走完骨架 fan-out→策略菜单→N 路竞速→early-exit 合并→后台对拍→亚军冻结 oracle 全链
  then: 人类触点为一次规划会话加一次抽检、外部沙箱产物经机械核对零作废进入判定；运行时证据为完整时间线（骨架产物→多实现 PR→合并→后台记录→冻结记录）
blastRadius:
- repo: .github
  path: specs/IR-0004/**
- repo: .github
  path: governance/GOVERNANCE.yaml
- repo: .github
  path: governance/policy/automation-limits.yaml
- repo: .github
  path: governance/policy/testing.yaml
- repo: .github
  path: governance/metrics.py
- repo: .github
  path: .github/workflows/cnb-dispatch.yml
- repo: .github
  path: .github/workflows/cnb-audit.yml
- repo: .github
  path: .github/ISSUE_TEMPLATE/**
- repo: agent-registry
  path: decisions/**
- repo: archive
  path: adr/**
- repo: CI-Workflows
  path: pipeline/adversary/**
- repo: aws-tb
  path: tests/**
- repo: aws-tb
  path: .github/workflows/**
- repo: cnb-bridge
  path: "**"
nonGoals:
- 不追求全仓形式化——仅条件触发小而稳定高危面
- 不重写存量 spec 为 DSL——新增 spec 起强制、存量自然迁移
- 不自研模糊/变异/符号/形式化框架——全部接入现有工具
- 不做无停止规则的无限 fan-out——N 默认 3–4、大于 16 需 ADR 特殊理由
- 不给所有卡强制 fan-out——决策矩阵 gating
- 不把 oracle 当产品维护——只换代不修补
- 不迁移 SSOT 到 CNB、不做镜像同步与平台互备演练（后续 IR）
- 不依赖 api_trigger 直接触发通道（未开放，仅留月度复验探针）
- 不做物理删除演习（owner 裁决：一次性退休动作）
- 不修改既有判定语义——testing.yaml 既有条款、gate/org-gate 结构、conductor/arbiter 状态机零变化（新增为增量）
- 不把 NPC/LLM 输出直接作为任何 gate 输入
---

## INV（不变量）

- **INV-01 生成/裁决分离**：LLM 与外部沙箱仅出现在生成侧；变异分数、测试通过、覆盖率、DSL hash、栈哈希去重、交集/并集计算、竞速选择器、kernel 检查全部由 GitHub CI 内代码核算，沙箱自报数字一律不采信。
- **INV-02 判定链不经过外部算力平台**：一切 CNB 内容可整体删除，删除后 gate/org-gate/conductor/arbiter 语义不变；任何把 CNB 写进判定路径的改动即违约。
- **INV-03 机械核对铁律**：外部沙箱产物进入任何判定链前必经机械核对——基准 SHA 在 run 开始时动态获取并写入报告（#263 erratum 为鉴）、差异可应用、输出格式校验；不符即作废并记 infra 失败。燃料管道产物消费同受此铁律。
- **INV-04 fail-closed**：形式化触发的风险等级缺失即拦截；审计任一红项产出死开关置位建议；平台失效时清单挂起加开 issue，永不为完成而跳过记账或核对。
- **INV-05 账本不可改写**：用量账本、生命周期台账、分诊台账、fan-out 产物目录均 append-only；纠错仅追加 erratum 行。
- **INV-06 凭据纪律**：平台 token 仅存 GitHub org secret；任务文本不含任何凭据；沙箱不注入 GitHub 凭据；高权限 token 的额外风险由 ADR 缓解条款覆盖。
- **INV-07 既有护栏全部适用**：派单前检查 AUTO_MERGE_DISABLED 与成本熔断未决 issue；同一卡修红重试上限对沙箱派单同样计数。

## BEH（行为）

- **BEH-01**（AC-1）weekly 变异实跑 + 定向候选机械初筛入池。
- **BEH-02**（AC-2）属性候选过滤 + 变异裁判（零杀死 = 平凡拒收）+ 存活常驻。
- **BEH-03**（AC-3）种子入库 + 外部沙箱深跑 + GitHub 侧核算 + 栈哈希去重 + 分诊仅草稿。
- **BEH-04**（AC-4）蜕变领域 fan-out 盘点 + 人抽检 + 条款入册 + 常驻实现。
- **BEH-05**（AC-5）符号执行试点出指标 + adopt/reject 二选一登记。
- **BEH-06**（AC-6）SAST 分诊台账 + 回填 + weekly 清点 + 误报率入仪表盘。
- **BEH-07**（AC-7）checklist 触发（弱模型留痕可重放）+ kernel 二值锚 + X-04 经 ADR 修订为条件触发。
- **BEH-08**（AC-8）DSL 编译 + spec hash 溯源 + 篡改红 + spec CI 关卡负向断言。
- **BEH-09**（AC-9）骨架 fan-out 四组件 + 分歧正交分解 + 交集/并集机械计算 + 高分歧退回规划层。
- **BEH-10**（AC-10）决策矩阵 gating + N 路竞速 + early-exit 不跳 gate。
- **BEH-11**（AC-11）后台评价 + 改进 PR 双重裁决替换。
- **BEH-12**（AC-12）跨簇亚军冻结 + 对拍常驻 + 硬软区 + 分歧路由 + 只换代不修补。
- **BEH-13**（AC-13）fan-out 产物四类统一落盘 + 适配器只读 + 差异攻击查询机械生成 + 消费前核对。
- **BEH-14**（AC-14/15）三接缝隔离 + 配额配置化 + 快照/实耗对账 + 最低核数档默认。
- **BEH-15**（AC-16）runbook 每步验收命令 + 陌生 AI 入职 + 生命周期 append-only。
- **BEH-16**（AC-17）work-inbox 租约/幂等/心跳。
- **BEH-17**（AC-18/19）周审计五项 + 政策 diff + 功能演练零人工（置位→回退→复位→计时）。

## IFACE（契约）

- **IFACE-01 三接缝**：治理仓对 CNB 的引用收敛为 GOVERNANCE 声明条目、org secrets、cnb-dispatch/cnb-audit 两个工作流；隔离审计 grep 仅命中此三处。
- **IFACE-02 派单协议**：任务描述机器可读、必含档位与清单 ID、输出契约（差异全文+测试原始输出含退出码+基准 SHA 确认）、run-id 前缀、投递前二次确认窗口归属、单账号并发上限可配置（默认 8）。
- **IFACE-03 产物目录格式**：fan-out 产物为 append-only 结构化记录，字段含类型（骨架分歧/假设/淘汰路线/对拍分歧）、卡 ID、spec hash、基准 SHA；红队与意图道闸输入适配器只读该目录。
- **IFACE-04 spec 产物契约**：DSL 编译产物携带 spec hash 头；hash 校验为 gate 级检查；豁免仅 ADR 登记通道。

## BUDGET（预算）

- **BUDGET-01 核时档位**：light=最低核数档（默认）、std=双核、heavy=四核须理由、默认八核档禁用；档位以构建记录标签证实；快照差分与构建日志实耗双路对账、偏差超阈值告警。
- **BUDGET-02 fan-out 纪律**：N 默认 3–4；趋同卡获免 fan-out 标签；top-2 差距小于选择器判别力时升级选择器而非加大 N；N>16 需 ADR；预算由收敛带宽决定与 token 无关。
- **BUDGET-03 审计抽样**：产物真实性抽样比例默认 10%、可降不可免。

## DECISION（决策）

- **DECISION-01** 高权限 token 保持不变（owner 裁决：管理简单性优先），缓解条款与泄漏应急随实现卡以 ADR 落实。
- **DECISION-02** X-04 由无条件拒绝修订为条件触发，修订经 ADR 完成（spec 不直接修改治理条款）。
- **DECISION-03** 演练全自动零人工；物理删除为一次性退休动作不做演习，证明力边界（功能脱离经周期证明、物理删除未经演习）如实入册（owner 裁决）。
- **DECISION-04** api_trigger 不作为依赖通道，保留月度复验探针；issue 窗口评论为当前唯一已验证机器派单通道。
- **DECISION-05 承接引用**：条款级规格方法承接 ADR-0050；无人值守护栏适用 ADR-0040；中心审判钉点 ADR-0046；ADR 墓碑机制 ADR-0053；fail-before 语义 ADR-0061；verifier 范式 ADR-0072（红队候选生成属选择层不进判定链，不冲突）；#263 的卡绑定测试与红队守门（T-14/T-15/AR-10）为上游依赖，本 spec 的 DSL 编译与骨架 fan-out 为其机械层承接，不重复建设。

## ASSUMPTION（假设）

- **ASSUMPTION-01** CNB 免费额度与 NPC 行为稳定（当前实测：单账号月度开发额度约 1600 核时；政策变化由周审计 diff 监测，失效即回退付费 API）。
- **ASSUMPTION-02** 形式化与符号执行工具链按栈可用，具体选型由试点实测决定（spec 不指定）。
- **ASSUMPTION-03** 强模型可按小时自起（协议就位后由 owner 配置调度；本 spec 只定义协议）。
