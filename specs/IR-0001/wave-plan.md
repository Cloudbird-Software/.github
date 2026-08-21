# IR-0001 波次计划（预览版，spec 签署后转为正式 Card issues）

> 波次边界按"何时能接触现实"切（#126 §3），不按工作量切。
> 每波次结束产出一个人类 5 分钟内可验收的东西。

## W0 编排底座 —— "签一条意图，spec PR 自己出现"
| 卡 | 内容 | 关键 AC |
|---|---|---|
| W0-C1 | org secret `LLM_API_KEY`（直连 provider，DECISION-01）+ 计量 wrapper（model/prompt版本/采样参数/用量落盘 artifact）+ AR-3 修订 ADR 正式落 agent-registry；secret 登记进 expected-state.json | secret 存在性被 drift-check §5 覆盖；wrapper 输出过 schema；连通性 check workflow 绿 |
| W0-C2 | `.github/ISSUE_TEMPLATE/intent.yml`（IR schema 表单）+ `state:*`/`needs-human` label 集；apply.sh 新增 §7 label 同步 | 表单字段与 IR schema 一一对应；label 漂移可检测 |
| W0-C3 | conductor workflow 骨架：仅一条通路（issues.labeled=state:ir-signed → 调 spec-author 可复用 workflow → 开 spec PR）；转移表 transitions.yaml | 签署测试意图后 spec PR 自动出现；非 owner 打 state 标签被回退 |
| W0-C4 | spec-author 可复用 workflow（CI-Workflows 仓，冷上下文，输出 spec.md + AC 表） | 产物过 g010-spec-schema 校验 |
| W0-C5 | AGENTS.md「找活协议」标准块 + `ghcb next`（查 state:ready 卡）+ label 认领协议 | 在一个测试仓实测：陌生 agent 仅读 AGENTS.md 完成认领一张演示卡 |

**W0 人类验收**：签一条真实意图 → 什么都不做 → spec PR 出现。

## W1 测试合规内核 —— "测试先行、锁定、可追溯"
| 卡 | 内容 | 关键 AC |
|---|---|---|
| W1-C1 | spec.schema.json + g010（条款 ID/AC≥1/禁实现细节关键词/blastRadius 非空） | 非法 spec 被 blocking |
| W1-C2 | AC 注册表 + 追溯闭合 check（IR↔SPEC↔AC↔Card 双向闭合，防镀金防丢失） | 孤儿条款/孤儿卡/无测试 AC 全部 fail |
| W1-C3 | 测试产物拓扑：test-author 先行 commit + fail-before 门禁（新测试在 HEAD 必须红）+ lock-tests 哈希锁定 + g060 防篡改 | 测试 commit 早于实现；实现前全红；改锁定测试 exit 2 只人类可解 |
| W1-C4 | 测试存放规约：`tests/acceptance/`（锁定）按 AC-ID 组织，pytest marker `@pytest.mark.ac("AC-n")` / vitest 标题 `[AC-n]`；g160 AC 追溯 | 每条 AC ≥1 个通过的测试且位置合规 |
| W1-C5 | 卡 PR 自动测试门：PR 解析卡元数据 → 自动选中该卡 AC 对应测试运行（required workflow 不用 paths 过滤，内部选择）+ Makefile 封装 `make card-test CARD=…` / `make gates-fast` / `make gates-pr` | 卡 PR 上该卡测试自动跑；agent 本地一条 make 命令复现 CI 同一套关卡 |

**W1 人类验收**：一张演示卡走完 test-author→implementer，git 历史上测试先于实现且曾红。

## W2 红队与 holdout —— "spec 有洞会被发现"
| 卡 | 内容 | 关键 AC |
|---|---|---|
| W2-C1 | holdout 私有仓 + ADR（ADR-0020 全公开政策的唯一例外）+ holdout 条目 schema + 版本化封存（hash） | cloudbrid-agent 未安装到该仓（drift-check 断言）；条目过 schema |
| W2-C2 | 只读凭据通道：第二个 App `cloudbird-holdout`（read-only，仅装 holdout 仓）或 HOLDOUT_TOKEN，仅在 verdict 可复用 workflow 内可用 | 实现阶段 workflow 日志审计：无 holdout 内容；揭封运行记录留痕 |
| W2-C3 | 分歧度量：k=5 冷上下文 matrix（混模型档位/家族）→ 决策表 artifact → 确定性比对 job 定位歧义热点，blocking | 人造歧义 spec 被定位到条款 ID；热点未清零不能合 |
| W2-C4 | 恶意合规：adversary 用最偷懒实现攻验收套件，通过=套件不充分（blocking） | 对故意弱套件必报不充分；对强套件报通过 |
| W2-C5 | holdout gate：verdict 阶段揭封跑；PR check 只显示通过计数，失败详情写私有 holdout 仓 issue | 实现 agent 日志无泄漏；人类在私有仓看到详情 |

**W2 人类验收**：红队对一个真实 spec 的完整攻击报告 + holdout 揭封记录。

## W3 质量关卡全量（#127 P0→P3 压缩版）—— "谓词守门，人看一页"
| 卡 | 内容 |
|---|---|
| W3-C1 | quality/ 骨架 + contract.yaml + 全关卡 non-blocking 跑通 + 首版 baseline.json + g900 棘轮（唯一 blocking） |
| W3-C2 | diff 硬化转 blocking：lint/typecheck/forbidden/test-tamper/blast-radius/tests/coverage-diff |
| W3-C3 | 结构+变异转 blocking：deps-arch/api-surface/module-shape/crap-diff/mutation-diff（diff 硬零存活）/flake + refine 循环（gate 报告驱动路由） |
| W3-C4 | adversary 黑盒阶段 + risk-score + 自动合并（复用 App automerge 通道，ceiling 从 20 起渐升）+ human-brief 一页阅读面 |

**W3 人类验收**：连续若干 PR 无误报；一份真实 human-brief 一页内读完。

## W4 度量与自进化 —— "系统自己变强"
缺陷归因标签（intent/spec/decomposition/test/impl/env）、规划逃逸率等指标落库、
规划回归集（改 planner 必重放历史意图）、thrash-detect、每周抽样审计→立法循环
（审计判断当周转成新关卡/forbidden-pattern，否则作废）。

## 依赖 DAG（简）
W0 → W1 → W2（W2-C1/C2 可在 W1 并行）→ W3 → W4
同波次内的卡预测文件集不相交（W0-C2/C3 都碰 .github/workflows，须串行）。

## 变更分级提示（DECISION-05）
不新建编排仓。W0/W1 的卡绝大多数落在 C1 路径（.github workflows、governance/、
CI-Workflows workflows/），每张卡的 PR 须附 ADR（新建或引用）——基建期
每张卡 = 一张 ADR + 一个 PR，这是刻意的（dogfood 治理流程）。
holdout 仓（W2-C1）走 flows.new_repo + GM-4 申报入 REPOS.yaml。
