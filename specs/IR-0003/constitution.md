# Cloudbird-Software 宪法 v2（最终 Strawman，待 owner 审查）
>
> 状态：**signed v2.2**（randypanding，2026-08-21）。本文件为宪法正本，IR 见 #161。

> 本文档 = 目标治理体系终态画像。输入：spec v3、STRAT-0001、两轮专家咨询、
> 10 路公共知识测绘（2026-08-21）。审查方式：红笔改，重点看 §0/§4/§5/§7/§11/§13。
> 审查通过后：本文作为 IR-0003「重订宪法」核心附件走流程，spec v4 吸收条款级变更。
> v2.1：按 owner 五问修订——§4 全量展开、§11 管家唤醒与统一入口、§12 状态可视化。
> v2.2：按 owner 业务模式陈述（2026-08-21）增补 §13 及三处小修订（§4C/§9/§10）。

## 0. 一句话（经前提异议修正版）

GitHub 组织即工厂：**系统压缩一切操作性工作；判断工作（做什么、对谁负责、
不可逆裁决）不可压缩，仍归 owner——系统设计的首要目标是让 owner 的判断力
不退化、有输入、被花在刀刃上。** 机器做的一切判定由可执行证据背书；
LLM 只做生成、veto 与叙述，永无合并权（合并权归自动合并基础设施）、approve 权、授权裁决权。

## 1. 结构分层（仓即职责）

| 层 | 仓 | 内容 | 变更规则 |
|---|---|---|---|
| 法律 | `.github` | 治理定义、IR/spec 账本、转移表 | C1：PR+ADR+owner merge |
| 机器 | `CI-Workflows` | 可复用 workflow、关卡实现（钉版下发） | C1 |
| 仲裁内核 | `arbiter`（新，最小仓） | 写入仲裁：确定性解析+策略表+原子 CAS+租约+台账。**无 LLM、默认拒绝、fail-closed、自带测试与误放行台账** | C1，独立测试 |
| 资产 | `agent-registry` | 角色/模型/技能/verifier 声明+validate | C2 |
| 记忆 | `archive` | 废止 ADR（墓碑索引）、规划回归集、事件 JSONL、红队报告 | append-only |
| 试卷 | `holdout` | 封存验收场景 + golden 集 + **泄漏诱饵** | owner 直管 |
| 工地 | 产品仓 ×N | 代码、测试、quality/ 关卡、AGENTS.md | 流水线 |

拆家原则：仲裁内核独立于管家（消掉"被审计者组装审计报告"的结构性冲突）；
旧 ADR 不删除，标 `active/superseded/archived` 迁记忆层。

## 2. 职责分配（补专家指出的 5 处无主）

| 职责 | 归属 | 机制 |
|---|---|---|
| 供应链/安全响应（CVE、上游破坏、密钥泄露/轮换） | security-response 通道 | 事件服务，有 SLA：扫描触发→卡→PR；密钥轮换 runbook 入仓 |
| 发布与对外（版本/changelog/废弃/外部漏洞报告） | release 流程（机器）+ 对外承诺判断（owner） | merge≠ship；changelog/tag 自动；废弃策略与对外承诺 = owner 判断，不进自动化 |
| 舰队迁移（关卡版本跨 10 仓升级） | fleet-upgrade 流程 | 新钉版 → canary 仓 → 批量 PR → 集体变红预案（回滚到上一钉版） |
| flaky 治理 | flaky 预算制（§4A） | 预算 + 隔离 SLA，详见 §9 知识地图 #10 |
| holdout/golden 集补给 | **owner 月度职责**（结构上不可交给 agent） | 月度 30 分钟，进审计节奏 |

## 3. 三条流水线 + 两个服务

**Feature 流**：IR（strawman 红笔改→签）→ spec（条款级）→ 红队（分歧度量+恶意合规）
→ 波次/卡 → 测试先行（fail-before+锁定）→ 实现 → refine（关卡路由）→ 对抗
→ verdict（确定性）→ 信任门（§5）→ 合并。

**Bug 流（复现前置，签署点后移）**：bug IR → reproduce（免签）：**三值判定**
{复现/证伪/不可判定}；环境自证（基线套件+哨兵测试）；env-gate 先行（锁依赖镜像）；
判定协议 = SWT-bench F→P 扩展：`(base上fail, fix上pass)=复现`，`(base上pass)=证伪`，
`环境错/超时/翻转异常=不可判定`；证伪不 close 只打 `cannot-reproduce`，同指纹二次上报绕过；
复现成功→failing repro test→owner 签→锁定→修复→关卡→合并。误关率每周抽样成数字。

**Hygiene 流**：度量信号生单 → AC=指标改善+行为不变（刻画测试）→ 可逆小步自决。
**纯重构豁免变异硬零**：改用等价证据（AST 等价 / 全测试+变异分不降）——最严关卡
不得卡死最该自动化的流。

**patrol**：场景三源（AC 注册表派生 / 历史逃逸模式攻击语法 / LLM 前沿探索+metamorphic）；
只在机器可判定 oracle 违约时开单；"看着不对"进 observation 桶两次独立才升级；
抓到真 bug 的场景毕业进 CI 回归并离库（防刷熟）。

**security-response**：CVE/上游破坏/密钥事件 → 时限卡 → PR；SLA 入 contract.yaml。

## 4. 验证体系（司法，全量展开）

### 4A. T1 可度量 → 确定性关卡全景（永远优先；阈值唯一来源 quality/contract.yaml）

**构建与测试拓扑**：测试先行（fail-before：红必须是断言失败）+ 哈希锁定（g060）+
AC 绑定（pytest marker/vitest 前缀，g160）+ coverage diff + 变异三档阈值（Stryker/mutmut，
nightly 全量、diff 硬零存活）+ flake 预算与隔离 SLA + e2e 行为证据。

**形式与类型**：format、lint（认知复杂度阈值）、typecheck strict、各类 schema 校验
（spec/handoff/gate-report/quarantine.yaml/transitions.yaml/models.yaml）。

**结构与架构**：CRAP diff；模块形状（depthRatio ≥3 理想 5、exports ≤7、fanOut 上限）；
依赖架构（dependency-cruiser / import-linter / go-arch-lint 按仓选型：分层、无环、
无跨 feature 私连、index 出口纪律）；api-surface diff（公共 API/路由/DB 迁移/env 集合）。

**AI 导航关卡组（自研度量，§9#5）**：每目录文件数上限（防平铺）；repo-map 固定 token
预算下符号覆盖率；引用图平均跳数/直径/环数；文档-符号链接验真（AGENTS.md/docs 引用的
符号对 AST 验存在）；词表 lint（版本化 glossary，未定义术语即 fail）；
抽样任务 agent 定位耗时配对校准（月度基准任务集）。

**抗复杂度（对 AI 复杂化冲动）**：死通用性检测（未使用的导出/参数/配置键）；
过度抽象（接口:实现=1:1 计数；新抽象调用点 <3 即拦，Rule-of-Three 机械化）；
无逻辑 wrapper 套娃计数；每卡净增 LOC 预算；抑制标记零增长；
豁免审计（豁免必须带理由且进 PR diff 可见，豁免行数本身是指标）。

**禁用模式**：forbidden-patterns（any/空 catch/裸 sleep/硬编码凭据/.only/.skip/
未注入的真实时钟与网络）。

**安全**：semgrep + 依赖审计 + gitleaks + CodeQL（medium+ 阻断）。

**棘轮**：全仓指标只许变好（baseline.json，仅 CI bot 可写，放宽须人类批准的 bot 提交）。

### 4B. 判定物有效性（宪法级原则）

判定物的有效性本身必须被度量成关卡：变异分数；负控制（revert 实现必变红）；
测试与实现强制跨模型族生成；**每周向随机 PR 注入已知缺陷**，演习关卡与 holdout
是否真会变红（整个安全论证唯一的活体证明）；holdout 内置泄漏诱饵。

### 4C. T2 可按判据验证 → 校准 LLM verifier（持证上岗制）

**范式来源（署名条款，见 §9 署名规则）**：本层方法论源自
**LLM-as-a-Verifier**（[arXiv:2607.05391](https://arxiv.org/abs/2607.05391)；
开源实现 [github.com/llm-as-a-verifier/llm-as-a-verifier](https://github.com/llm-as-a-verifier/llm-as-a-verifier)，
Stanford×Berkeley×NVIDIA）：连续分（对打分 token logits 分布取期望）、判据分解、
重复评估降方差、best-of-N 锦标赛排序。谱系上游：G-Eval（arXiv:2303.16634，连续分起点）、
MT-Bench 位置交换协议（arXiv:2306.05685）、RewardBench/LLMBar 对抗子集（allenai）、
敏感度/特异度校准（arXiv:2511.21140，ICML'26）、null-model 攻击实证（arXiv:2410.07137）。
开源实现经 spike 评估后决定直接采用或按范式自研薄层。

- **入职考试（CI 关卡）**：冻结考试集 = RewardBench2 生成式赛道 + LLMBar 对抗子集 +
  ≥20 条 null-model 金丝雀（空响应/模板复读必须判负）+ 成对样本双序（位置交换一致率 ≥0.90）；
  按 `judge_id@版本@prompt_hash` 存档，任一不过即拒上岗。
- **出分即校准**：维护 100–200 条人类裁决校准集（裁决后顺手回流，不是让人类自己去手动做，一定是静默完成的），
  估计敏感度/特异度，出分带"校正值±置信区间"，**CI 下界低于及格线→自动升人类**。
- **判据分解 + rubric 契约**：每条判据配每档锚定描述；连续分，禁离散印象分。
- **标注负债申报**：每个 T2 verifier 必须申报年度标注人力预算，未配预算不许从 T3 迁移。
- **对抗防御（自研薄层）**：输入隔离（被评内容不进 judge 指令通道）、模板封装、
  异构多 judge 分歧即升级。
- **模型无关（v2.2 增补）**：入职考试/校准/误差率门槛对一切"判定者候选"适用——
  provider 模型、未来自训练的小参数模型（如 0.9B 节点任务模型）、甚至外部工具。
  自训练模型不因其"自家出身"豁免任何考试（§13 推论三）。
- veto-only，永无 approve；一切 veto 先 shadow 达标再上岗（§5）。

**T2 检查项清单（整洁域，宁滥勿缺）**：
① **AI 可读性 verifier**——rubric 判据分解示例（每档锚定描述另行成文）：
可定位性（从 AGENTS.md/index 出发找到符号的容易度）、入口清晰度（index 出口
是否准确反映内部能力）、模块深度充分性（接口是否真把复杂度挡在门内）、
命名与词表一致性、示例与文档新鲜度；
② 命名质量；③ 注释价值（是否说清 why 而非复述 what）；④ 实现与 spec 意图的贴合度
（按 AC 逐条分解验证）；⑤ OCR 代码评审（见下，独立基础设施）。

**代码评审基础设施 = OCR**（[alibaba/open-code-review](https://github.com/alibaba/open-code-review)，
Apache-2.0，钉版+SBOM+telemetry 审计）：确定性工程硬约束（文件筛选/打包/规则匹配/
定位与反思模块）+ LLM 只做判断，precision-first 与 veto-only 天然契合。
落地节奏 = §5 shadow 机制：先 shadow 记录，用 **post-fix 基准**（bot 建议被事后修复
命中的比例=precision，自建管线，[withmartian/code-review-benchmark](https://github.com/withmartian/code-review-benchmark)
方法学 MIT fork）度量，达标升 veto 关卡。AACR-Bench 只作选型参考不作晋升依据
（厂商自评+AI 辅助标注+泄漏风险）。CodeRabbit 免费层挂全公开仓作高召回 shadow 补充。
B 计划：Kodus。评审输出统一经确定性后处理（file:line 落在 diff 内/命中规则集/去重，
不过则丢弃计数）。`ocr scan` 全文件模式复用于 hygiene 流与周审计热点扫描。

### 4D. T3 品味残余 → 提示词/技能/AGENTS.md 指导层

内容只限不可判定残余：深模块哲学（小接口大实现、宁深勿铺）、删除优先、
复杂度预算意识、命名心智。边界铁律（INV-05）：可判定规则禁止出现在此层；
CLAUDE.md ≤100 行、AGENTS.md ≤30 行索引型。技能资产全部注册 agent-registry（AR-1，
版本化+validate）；各仓 AGENTS.md 标准块由 template-service 统一下发（C1 scaffold），
drift-check 校验各仓协议块版本一致。每周审计立法负责把 T3 持续迁往 T1/T2
（迁移走 meta-IR 正常 Feature 流，owner 不写关卡——审计只产判例记录）。

### 4E. 测试与验证全景（两域，缺一不可）

**域一：产品正确性验证（意图→实现是否按预期）**

| 层 | 检查 |
|---|---|
| 追溯闭合 | 全链 UID 引用：IR↔SPEC↔AC↔Card↔测试↔代码；孤儿条款/镀金范围/断链即 fail（StrictDoc 模型） |
| 生产者红队 | spec 红队（语义熵分歧度量+恶意合规）；波次红队（k 路独立分解一致性）；测试红队（恶意合规攻 AC 套件）；实现 adversary（黑盒七类攻击→failing 回归测试） |
| 卡级 | test-first 产物拓扑、fail-before、AC 绑定、卡 PR 自动选中该卡测试集 |
| 波次级 | 切面"绿且可部署"：AC 全绿、无死代码、无半开 flag、公共接口无未声明变更、预测 vs 实际对账、replan drift 监控 |
| 系统级 | 差分测试（新旧版本行为对比）；金丝雀（种子缺陷演习 + 产品侧 canary 发布）；回归（patrol 毕业场景 + 对抗发现转回归 + holdout 揭封）；nightly 全量（全仓变异+全量指标漂移校正）；e2e 行为证据进 human-brief |
| 测试的测试 | 变异测试、负控制、判定物有效性演习、flaky 治理（§4A/§9#10） |

**域二：治理自洽性验证（检查的机制本身仍可信）**

| 层 | 检查 |
|---|---|
| 期望状态 | drift-check 小时级对账（rulesets/secrets/仓基线/App 形状/钉点完整性） |
| 宪法一致 | GOVERNANCE.yaml↔实际、transitions.yaml↔labels、models.yaml↔registry validate、ADR 墓碑索引一致、adr-required 实体性后验 |
| 验证器之验证 | 关卡/arbiter/计量 wrapper 自带测试套件，变更必须带测试；OCR/verifier 输出后处理过滤率本身是指标 |
| 活体演习 | 周种子缺陷注入（关卡必须红）、holdout 泄漏诱饵、缺席 fail-closed（§6） |
| 规划回归 | planner/prompt/流水线变更必须重放 Top-N 历史意图做结构 diff，重犯归档缺陷即 fail |

## 5. 信任演进（替代 spec v3 的 risk-score 标量——spec v4 修正）

标量风险分把"未知"折叠成"安全"，废除。改为 **硬谓词白名单（fail-closed）+ 常设 shadow 模式**：
- 准入为谓词清单：全关卡绿 ∧ 证据齐全（**缺证据=拒绝，不是中性**）∧ 属于已解锁域。
- **域解锁机制**：某域先跑 shadow（做出"本应合并"决策但不合并，与人裁决比对），
  连续 ≥50 例一致且零逃逸 → 该域解锁自动合并。域的选择标准 = 可逆性×可观测性×oracle 强度。
- **前三解锁域**：① 无行为 diff 的整洁（格式化/注释/文档同步，AST 等价可证）；
  ② 只增测试（不动产品代码，变异分必须升）；③ 有 failing repro 的小修复
  （红→绿+负控制+只碰 repro 覆盖文件——全系统最强 oracle）。
- **明确排除**：新功能实现、依赖升级、触及公开 API/schema/CI-Workflows 的改动（永远人签）。
- 成本熔断只准降级为人签，**不准降级为少验**。

## 6. 失效与降级（fail-closed 的缺席触发）

- **缺席即停**：审计包/账本缺席 → 自动关闭自动合并（不靠检测触发，靠缺席触发）。
- **外部 dead-man 心跳**：全部 cron 挂外部心跳监控，管家 cron 静默 = 全系统降级。
- **每周种子缺陷演习**（见 §4B）。
- **holdout 泄漏诱饵**：holdout 内置独特标记样本，其内容出现在任何 agent 上下文/日志即报警。
- 熔断变量一键停自动合并；全部设施新增式可拆，可回退"全人工+关卡辅助"。
- conductor 单项熔断：同一工作项连续 3 次推进失败 → 打 `stuck` 并跳过，绝不阻塞队列
  （Prow tide 卡死教训）。

## 7. 人类接口与反退化（对抗"审计退化成被叙述喂养"）

| 触点 | 设计 |
|---|---|
| 签 IR | 一屏：影响面+回滚成本+摘要；签署耗时如实计入判断预算（防"签署退化成隐形 review"的伪装解法） |
| 裁决 needs-human | 决策卡二选一+默认最保守分支；**必须有第三选项"都不对"并附反例**；超时默认触发数单独显示，不洗白成"队列健康" |
| 每周审计 30min | 抽样由 owner **从原始事件日志独立复算**（不用管家组装的包）；产出判例记录，转关卡走 meta-IR |
| 每周亲手一件真事 | 修一个真 bug 或写一条关卡（具身知识保鲜，防 owner 退化） |
| 月度 holdout 补给 | 30 分钟（§2） |

## 8. 度量

- **北极星对**：每周零人类接触合并数 × 质量护栏（逃逸率/回滚率/holdout 与主套件通过率差）不劣化。
- **用户结果指标**（防产品漂向"oracle 友好型"）：每产品至少一个用户侧结果指标进 dashboard；
  每季度刻意做一个难测的产品/功能（配额制），防止工厂只做"容易验证的"。
- **注意力会计**：owner 签署耗时、needs-human p90（超 1 天=整机停摆）、每合并 owner 分钟、
  超时默认触发数、周审计超时率。
- **安全正确性**：仲裁误放行/误拒数、未经仲裁的状态变更泄漏数、种子缺陷演习红率（应≈100%）。
- **成本**：单 IR 美元（硬上限+熔断）、管家美元/周、patrol yield（每百次唯一真 bug 数）。
- **判断预算**：T2 标注负债、IR 撰写时间如实入账——系统省的是操作，不是判断。

## 9. 公共知识地图与署名规则

**署名规则（宪法级）**：凡引入的外部范式/工具/基准，必须在引用条款旁显式注明源头
（论文 arXiv 号 / 仓库 URL），进入 registry 的资产还需版本钉死。目的：让后续开发者
与审计者能追溯每个设计决定的出处，杜绝"祖传黑话"。

| # | 原子问题 | 站在谁肩上 | 自研什么 |
|---|---|---|---|
| 1 | spec 结构化/lint/追溯 | OpenSpec validate 模式 + StrictDoc UID 追溯 + EARS 六句型 | 百行确定性 lint（句型正则+模糊禁词表+ID 引用完整性）；语义歧义留给红队 |
| 2 | 代码评审 | **OCR**（执行）+ withmartian post-fix bench（度量）+ CodeRabbit 免费层（shadow） | shadow→veto 晋升管线、输出后处理 |
| 3 | LLM judge 可靠性 | **LLM-as-a-Verifier 范式**（arXiv:2607.05391 + 同名开源项目）+ RewardBench2/LLMBar 入职考试 + ICML'26 校准 + 位置交换 + null-model 金丝雀 | 对抗防御薄层、校准集循环、AI 可读性 rubric |
| 4 | 测试强度 | Stryker/mutmut（三档阈值）+ fast-check/Hypothesis + MuTAP/AdverTest 闭环结构 | 对抗调度循环（薄）、豁免审计指标 |
| 5 | 整洁/导航 | dep-cruiser/import-linter/go-arch-lint + 认知复杂度 + CodeScene 因素清单 + aider repo-map | **AI 导航容易度度量**（repo-map token 成本+引用跳数+agent 定位耗时配对校准）——公共知识空白，自研 |
| 6 | Bug 复现 | SWT-bench F→P 判定协议 + Agentless 分层定位 + mini-SWE-agent 极简循环 + EPR 集合投票 | 三值判定扩展、env-gate、GitHub 胶水 |
| 7 | 编排/ChatOps | Prow 范式（label 状态机+reconcile+tide 教训）+ safe-settings + probot actions adapter + Copilot cloud agent hooks 模式 | conductor 业务编排；评估 safe-settings 替换 apply.sh/drift-check |
| 8 | holdout/回归 | promptfoo（执行+CI 门禁）+ autoevals Score 契约 + inspect_ai 日志 schema + git tag 版本管理 | 封存/引用约定、历史意图→样本转换器、重放 diff 脚本 |
| 9 | 分歧度量 | Semantic Entropy 双向蕴含聚簇（Nature 2024）+ 底噪扣减 + LM vs LM 交叉质询 + MAST 14 模式检查表 + Cognition 干净上下文实证 | 分歧→条款坐标定位；第 6 agent 反推 spec（不给 spec 从产物反推，比对隐式决策） |
| 10 | flaky 治理 | Google 同 SHA 重跑转迁 + Uber FSM 参数 + Mergify 隔离 SLA（2-4 周，修复或退役）+ DeFlaker 覆盖差分 veto + IDoFT 评测集 | quarantine.yaml+迁移脚本+CI 关卡的压缩形态 |

原则重申：判定归确定性工具，LLM 归生成/veto/叙述；凡是公共知识已有的判定轮子，
一律不自研（变异引擎、PBT 引擎、评审引擎、评估框架、架构约束工具均不造）。

**产品注记（v2.2）**：本宪法建设的生产系统本身是公司的第一个 harness 产品（dogfood）。
其组件（arbiter、关卡集、verifier rubric、front-desk 协议、AGENTS.md 协议块）按
**可产品化资产**标准构建：独立可拆、文档自包含、注册进 agent-registry（§13 推论四）。

## 10. 已知代价与开放项（诚实清单）

1. **供应商单点**：GitHub = 计算+存储+身份+事件总线+人机界面；owner 账号握 C1 合并权。
   缓解：设施全部新增式可拆 + 关键产物（archive/holdout）可异地备份。接受残余。
2. **判断工作的预算真相**：30 分钟/周审计 + 签署 + 立法分流 + 月度 holdout + 每周亲手一件——
   合计约 2-3 小时/周，不是最初的 30 分钟。这是诚实的底价，不再压缩。
3. **OCR 低召回是设计取舍**：漏报由确定性关卡+对抗+holdout 兜底，评审不是安全网。接受。
4. **T2 verifier 的标注负债是永久性的**：模型换代即重标。用申报制控制数量。
5. **公开仓的攻击面**：front-desk/仲裁/红队都读未受信文本——INV-10 防线 + 授权决策零 LLM + 频控。
6. **shadow 期的时间成本**：前三域各需 ≥50 例对齐才能解锁，估计 4-8 周。期间合并仍需人。
7. **业务模式是 bet（v2.2）**：§13 的假设（GUI 退化/agent 消费/harness 形态/FDE 模式）
   是方向性判断不是事实。宪法对两种世界均稳健（关卡不关心产品 UI 形态），
   但产品 AC 形态若预判错误，调整成本集中在 holdout 与验收层。每半年重估一次。

## 11. 管家唤醒矩阵与统一入口（答 owner 第四问）

**铁律：管家永远不"自己醒来"。** 它没有任何内生意志——每次运行都必须有明确触发器，
且每次运行产出审计日志条目（谁唤醒/干了什么/花了多少）。任何职责找不到触发器 = 设计错误。

| 触发器 | 唤醒的职责 | 说明 |
|---|---|---|
| cron 每 6h | reconcile（僵尸认领/孤儿标签/tasklist 脱节/状态-产物不一致） | 主收敛循环，事件丢失的最终兜底 |
| cron 每 15min | 账本/dashboard 刷新 + Project 板同步（§12） | 高频轻量，纯脚本 |
| cron 每 1h | 预算/配额检查（BYOK token、Actions 分钟、单 IR 成本） | 触限熔断 |
| cron 每日 | digest 汇总、flaky sweep、patrol 启动 | |
| cron 每周 | 审计包组装、种子缺陷演习、holdout 诱饵检查 | |
| event issues.labeled / issue_comment.created | 仲裁请求处理（/claim 等，转 arbiter）、入口分诊 | 频控+防重放（只认 created+delivery 台账） |
| event pull_request.* / check_run.completed | 卡状态联动、关卡结果记账 | |
| workflow_dispatch | 人工手动唤醒（调试/演习） | |
| 外部 dead-man 心跳 | 管家静默超时 → 缺席即停自动合并（§6） | 心跳是"唤醒的唤醒"，也必须外部 |

**统一入口协议（外部 agent 进组织工作的唯一入口，无需人类补任何提示词）**：
- 入口 = 各仓 AGENTS.md 的**同一协议块**（由 template-service 统一下发，C1；
  drift-check 校验各仓版本一致，漂移即 fail）。
- 协议块内容（自包含，≤30 行）：找活 `ghcb next`（列出 state:ready 卡）→
  认领 `ghcb claim <n>`（经 arbiter 原子 CAS，先到先得）→ 开工
  （`make card-test CARD=<n>` / `make gates-pr` 本地复现 CI 关卡）→ 提 PR
  （body 必带卡元数据，缺失 exit 3）。
- **卡 issue 是唯一工作凭证**：无卡不开工；卡只在 `state:ready` 可领；
  可领队列只有一个（state:ready 标签集），其两个视图见 §12。
- 入口有效性有验收判据（spec AC-2）：干净容器中的陌生 agent 仅读 AGENTS.md
  即可完成认领并开出合规 PR。

## 12. 状态可视化（答 owner 第五问）

**真相源唯一 = issue label**；一切视图都是投影，投影与 label 漂移时以 label 为准并报警。

- **投影一：组织级 Project 板「factory-floor」**（唯一一块，只读投影）：
  columns = state 全集（ir-draft→…→done），可按 repo/波次分组；
  字段 = 卡 ID、AC 进度、关卡状态、认领者、停留时长、谓词状态。
  由管家每 15min 经 GraphQL 同步 label→board；人工在 board 上的修改会在下一轮
  reconcile 被纠正回 label 状态。与 BP-4 兼容：仓级 Projects 仍关闭，
  组织级单块板是展示层不是管理系统（修正 DECISION-04 的适用范围，spec v4 注明）。
- **投影二：dashboard 账本 issue**（管家维护）：机器可读区（JSON 状态块）+
  人类可读区（一屏摘要），供 agent 一次读取全局、供 owner 一眼看全局。
- **投影三：human-brief（每 PR）+ 每周审计包**（管家组装、owner 可独立复算，§7）。

## 13. 业务模式假设与设计推论（v2.2，owner 陈述于 2026-08-21）

**假设（owner 的方向性判断）**：软件形态正从"多租户、按座位、人类 GUI"迁移到
"被模型调用的工具/作为模型 harness 存在"；人类 GUI 退化，交付结果由
"人 ↔ 模型 ↔ 软件"的链路产生。公司内核 = harness 群（含未来自训练的小参数
节点任务模型，如 0.9B）；界面与客户定制流程是从内核上由 LLM 确定性生成的派生物；
组织未来的对外形态 = FDE 工程师赴客户现场做集成与交付。

**推论一（产品验证形态）**：产品越来越多地被 agent 消费 → AC 与 holdout 新增
第四观测类 **"agent 任务轨迹"**（与 e2e/api/unit 并列）：验收问题从
"UI/API 返回什么"扩展为"agent 能否用本产品完成任务 X"。**agent-consumability**
（契约/工具 schema 质量、错误语义对模型的可理解性、输出确定性）进入产品验收
与 §4A 导航度量的外延。spec 的 observability 枚举相应扩展（spec v4）。

**推论二（数据飞轮）**：事件 JSONL、golden 集、校准集、红队报告、关卡报告、
规划回归集——这些不只是治理副产物，是**训练与评估飞轮的原料**，archive 仓
由此升级为战略资产。未来训练小模型的数据策展从这些资产出（触发条件成熟后立项）。

**推论三（自训练模型的治理）**：自训练小模型（如 0.9B 节点任务模型）不享有任何
特权——与 provider 模型走同一入职考试、同一误差率门槛、同一 shadow→veto 渐进
（§4C 模型无关条款）；models.yaml 届时扩展本地微调条目，治理机制不变。

**推论四（交付模式与组织）**：本生产系统即第一个 harness 产品（§9 产品注记）；
FDE 的交付动作可复用主流水线——客户定制 = 对产品仓发 IR + harness 组合，
验收 = 同一套关卡。多身份治理（FDE 的权限域）由 arbiter 策略表天然支持，
第一名 FDE 入职时再 formalize，现在不建。

**非推论（现在明确不建）**：训练管线、数据策展流、客户交付管线、多角色组织治理。
理由：核心生产流程未跑通前，这些都是无源之水。触发条件：任一假设被验证为真
（有真实客户/真实训练需求）时，按正常 IR 流程立项。

## 审查指引（owner 请重点看）

- §0 一句话的修正（判断不可压缩）——认吗？
- §4C LLM-as-a-Verifier 范式署名与 §9 署名规则——满足"可追溯"要求吗？
- §4 全景（4A 确定性 / 4C T2 检查项含 AI 可读性 rubric / 4D 指导层 / 4E 两域测试）——宁滥勿缺，有滥要砍吗？
- §5 用硬谓词+shadow 替代 risk-score 40（推翻此前裁决）——认吗？
- §7 反退化设计（独立复算、每周亲手一件、决策卡第三选项）——愿意承诺吗？
- §11 唤醒矩阵 + 统一入口协议、§12 Project 只读投影板（修正 DECISION-04）——认吗？
- §13 业务模式假设与四个推论（尤其"现在不建"清单）——认吗？
