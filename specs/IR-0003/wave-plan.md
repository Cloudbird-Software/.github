# IR-0003 波次计划（宪法 v2 建设总图）

> 波次边界按"何时能接触现实"切。W0 为既有卡（#130-134），其余为新增。
> 依赖：W0 → W1 → W2 →（W3 ∥ W4）→ W5。每波次退出判据见各波末节。

## W0 编排底座（既有，进行中）
#130 LLM 接入与计量 · #131 意图入口与状态标签 · #132 conductor 骨架 ·
#133 spec-author workflow · #134 找活协议。
退出判据：签一条真实意图 → 人类零操作 → spec PR 自动出现（含负向测试 AC-11）。

## W1 立宪与骨架（本 IR 主体，宪法 §1/§11/§12）
| 卡 | 内容 | 关键 AC |
|---|---|---|
| W1-C1 | archive 仓创建（new_repo 流程+REPOS.yaml 申报）+ 旧 ADR 逐条标 `active/superseded/archived` 迁移 + agent-registry 留墓碑索引 + adr-required 关卡改查索引 | 迁移后 adr-required 全绿；任何 ADR 编号可解析到 archive 路径；无内容丢失 |
| W1-C2 | arbiter 仓创建 + 仲裁内核：确定性命令解析 + capabilities.yaml 策略表 + 原子 CAS（createRef 422 即败）+ TTL 租约 + 防重放台账 + 自测试套件 + 误放行/误拒台账 | 无 LLM 依赖（静态扫描断言）；并发 /claim 同卡仅一胜者；重放事件 no-op；自测试入 CI |
| W1-C3 | 统一入口协议块（template-service 下发 + 各仓 drift 校验）+ Project 只读投影板「factory-floor」+ dashboard 账本 issue | AC-2 复测：干净容器陌生 agent 仅读 AGENTS.md 完成认领并开 PR；board 与 label 漂移报警 |
| W1-C4 | holdout 仓创建 + 条目 schema（IFACE-07）+ 封存/引用约定 + 泄漏诱饵 | cloudbrid-agent 未挂载该仓（drift 断言）；诱饵内容出现于任何日志即报警 |
| W1-C5 | 管家骨架：唤醒矩阵 cron 骨架（reconcile 6h + 账本 15min + 预算 1h）+ 审计日志条目 + digest 纪律 + 外部 dead-man 心跳 | 每次运行有触发器与日志条目（INV-12）；心跳缺席 → 自动停自动合并（fail-closed 实测） |

退出判据：宪法 §1 结构分层全部实体存在；唤醒矩阵前五行在跑且有审计日志。

## W2 测试合规内核（宪法 §4A/§4E）
| 卡 | 内容 |
|---|---|
| W2-C1 | quality/ 骨架 + contract.yaml + spec lint（EARS 句型正则 + 模糊禁词表 + UID 追溯闭合）+ g010 |
| W2-C2 | test-first 拓扑 + fail-before（断言失败才算红）+ lock-tests + g060 + Makefile 三命令 |
| W2-C3 | 计量 wrapper 完整版（按 invoke 聚合去重 + artifact 落盘 + hash 链 + BEH-09 字段齐全） |
| W2-C4 | OCR shadow 接入（钉版 + SBOM + telemetry 审计 + 输出后处理过滤 + shadow 记录管线） |

退出判据：一张真实卡走完 test-first→锁定→实现，git 历史可证；OCR shadow 在 2 个仓跑且有记录。

## W3 Bug 流水线 + patrol（宪法 §3）
| 卡 | 内容 |
|---|---|
| W3-C1 | bug form + reproduce 阶段：env-gate（锁依赖镜像）+ 哨兵环境自证 + 三值判定（SWT-bench F→P 扩展）+ cannot-reproduce 流程 |
| W3-C2 | patrol 服务：三源场景生成 + 指纹去重 + 频控 + observation 桶 + 毕业机制 |

退出判据：一个真 bug 从 patrol 发现到自动合并（或合规升级）全链路；误关抽样机制运转。

## W4 红队与 holdout 设施（宪法 §4B/§4E）
| 卡 | 内容 |
|---|---|
| W4-C1 | 语义熵分歧度量：k=5 跨族 + 双向蕴含聚簇 + 底噪扣减 + 交叉质询定位条款坐标 |
| W4-C2 | 恶意合规 adversary（judge-deep 档锁定）+ 套件不充分判定 |
| W4-C3 | holdout 揭封 gate（hash 校验 + 计数化 PR 展示 + 详情写 holdout 仓 + 日志审计） |
| W4-C4 | 周种子缺陷演习 + holdout 泄漏诱饵联动 + 缺席 fail-closed 全链路 |

退出判据：红队对一个真实 spec 的完整攻击报告；演习中注入缺陷 100% 被关卡抓红。

## W5 整洁关卡全量 + 信任门（宪法 §4A/§4C/§5/§8）
| 卡 | 内容 |
|---|---|
| W5-C1 | 整洁关卡组：导航关卡组 + 抗复杂度关卡 + CRAP/认知复杂度 + 变异三档 + 棘轮 baseline |
| W5-C2 | 硬谓词白名单 + shadow 决策记录管线 + 前三域解锁机制（≥50 例一致零逃逸） |
| W5-C3 | verifier 入职考试 CI（RewardBench2+LLMBar+金丝雀+双序）+ AI 可读性 rubric shadow + 校准集循环 |
| W5-C4 | 度量 dashboard：北极星对 + 注意力会计 + 安全正确性 + 成本 + Project 板字段完善 |

退出判据：连续若干 PR 无误报阻断；第一域 shadow 数据开始累积；human-brief 一页可读。

## 变更分级提示
W1/W2 的卡多数落 C1 路径：每张卡 = 一张 ADR + 一个 PR（dogfood 治理流程）。
新仓（archive/arbiter/holdout）走 flows.new_repo + GM-4 申报。
