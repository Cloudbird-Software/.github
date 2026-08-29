# IR-0006 波次计划（六波次总图）

> 依赖：W1 →（W2 ∥ W3）→ W4 → W5 → W6；W1 内 A/B/C/D 四线可并行（A 是 B/C 的法律基础）。
> 与原总纲 P0-P3 映射：P0≈W1、P1≈W2、P2≈W3/W4、P3≈W5/W6——按"内部跑通优先"重排。
> 波次内每卡独立小 PR（C1 路径：PR+ADR 引用+owner merge）；治理变更不需要卡，
> 但涉及仓外执行面（内网/CNB）的卡按 ROLE-IMPLEMENT 走 dispatch/自建调度器。

## W1 地基（本 IR 主体）

| 卡 | 内容 | 关键 AC |
|---|---|---|
| W1-A1 | absorption-map.md + wave-plan.md + spec 正文/suite 落盘（本 PR） | AC-1 前半：落位表 18 行+词汇归并；红队 survived |
| W1-A2 | 宪法 v3 修正 PR：按落位表把 I3/I4/I7 扩展条款吸收进 constitution.md（§5 不动=硬边界）；GOVERNANCE.yaml 增账本/保留策略条款 | AC-1 后半；adr-required 引用 ADR-0103 |
| W1-B1 | 证据 schema v1 定稿（standards/，对齐 OTel gen_ai.*）+ archive 仓 evidence/ 判定层载体 + checkpoint 机制与验证脚本 | AC-3：payload ≤4KB 拒写、链断=红、tenant 字段 |
| W1-B2 | 三源对齐：metering/butler/drill 新事件按 schema v1 双写过渡（BEH-03）+ tenant tag 注入 metering 归账 | AC-4：统一查询可跑、原 JSONL 只读 |
| W1-B3 | 轨迹层指针协议：内网 blob 引用约定（sha256+指针+保留策略字段）+ 热数据先留内网本地的最小实现 | AC-3 轨迹层面：git 侧只见摘要 |
| W1-C1 | providers.yaml 增 self-cloud-pool/vault 条目 + 资产登记簿（repo/密钥/额度/环境归属+license 边界）| AC-5 前半：条目在场+removal 声明 |
| W1-C2 | env 定义仓建仓（flows.new_repo）+ REPOS.yaml 申报 + environments/*.yaml 骨架（拓扑/镜像/allowlist） | AC-5 后半：drift 对新申报面零漂移 |
| W1-D1 | 决策语料 append-only 文件 + 链式 hash + 记录约定（情境→选项→决策→理由→后果） | AC-10 后半：语料开始累积 |

退出判据：判定层可写可验（checkpoint run 绿）；三源统一查询一条命令出结果；drift 对 env 仓/self-cloud-pool 零漂移；决策语料 ≥1 条真实记录。

## W2 控制平面成形

| 卡 | 内容 | 关键 AC |
|---|---|---|
| W2-C1 | 内网调度器 v0（服务器侧 Go）：Job Contract 消费+worker 池内短票据签发+egress allowlist+无状态约束执法 | AC-5 执行面：worker 不直连公网、持状态负载拒置 |
| W2-C2 | PM 凭证收敛：gh-app-token 上收服务器代签（单仓+短 TTL）+ 应急回退通道文档化 | AC-6：PAT 退出日常、TTL 到期收回实测 |
| W2-C3 | Wave schema 入卡：card 模板 budget/capabilities/evidence 字段 + conductor 解析 + cost-check 波次视图（subject 聚合自统一账本）+ human_minutes 预算 | AC-9 前半：预算超限硬停实测 |
| W2-C4 | JIT elevation v0：/elevate 评论→arbiter 策略表（附理由+spec 引用；批准记录进账本） | AC-9 后半：无理由必拒（HO 场景 3） |

退出判据：一张真实带预算的卡走完"超限硬停→复位"；PM 用服务器代签令牌完成一次全流程写仓；elevation 有账本记录。

## W3 界面层（飞书 outbound）

| 卡 | 内容 | 关键 AC |
|---|---|---|
| W3-F1 | 飞书多维表格投影：factory-floor 每行一卡（IFACE-04 字段）+ 同步器（≤15min，BEH-06）+ 调用账本 | AC-7 前半：投影运行 |
| W3-F2 | 重建保真与漂移纠正：drop & rebuild 演练 + 人工违规修改被纠正实测 + holdout HO 场景 2 注册 | AC-7 后半：单轮重建一致 |

退出判据：多维表格连续一周无人工干预自同步；rebuild 演练绿；漂移告警进账本。

## W4 运行回路 R3

| 卡 | 内容 | 关键 AC |
|---|---|---|
| W4-R1 | env repo 期望态+实况上报+drift 引擎泛化（GitHub org 对账→环境对账；偏差开 issue/消除自动关） | AC-8 前半 |
| W4-R2 | SLO 骨架进 sli-weekly（复用 sli-report.sh 扩数据源）+ 责任边界文件（SLO/值班/破线/break-glass） | AC-8 后半：首个托管客户前写死 |
| W4-R3 | 签名证据包 v0：部署产物 attestation+SBOM（承 SC-4 provenance 先例）绑定 evidence/ 判定记录 | AC-8 附加：部署可回溯 |

退出判据：一次环境变更从期望态 diff→漂移 issue→修复→自动关闭全链路；SLO 周报含环境面。

## W5 能力回路 R5

| 卡 | 内容 | 关键 AC |
|---|---|---|
| W5-E1 | eval registry：holdout 仓扩展四元组 pin（代码+数据集+提示+模型）+ 非劣性 eval gate 家族（δ 阈值+污染检查+成本/延迟回归） | AC-10 前半 |
| W5-E2 | 首个 optimization wave：wave.kind=optimization 走 transitions 状态机，exit gate=eval 家族（BEH-08） | AC-10 中段：非劣性 run 记录 |

退出判据：一个真实优化目标（任一产品仓既有能力）从基线评测→优化→非劣性通过全链路，四元组 pin 可复现。

## W6 元环与收口

| 卡 | 内容 | 关键 AC |
|---|---|---|
| W6-M1 | conformance 语料库种子：30-50 张已完成卡回放语料（初始快照+目标+密封验收）+ 门禁元治理四列指标评审（metrics 扩展） | AC-1 联动：胜出实践晋级机制首跑 |
| W6-M2 | R3→R1 反馈边骨架：运行信号（错误/用量/SLO）自动生成候选 spec 入 backlog（走 R1 的门） | AC-8 联动 |
| W6-M3 | acceptance.md 汇总（T-15 逐条回探十条）+ 冷上下文六问复测 | 全 AC 收口 |

退出判据：IR#402 十条期望变化逐条有运行时证据；六问复测 a-f 全有真实来源；acceptance.md 合并后 IR 可置 done（T9 谓词）。

## 变更分级提示

- W1 全部/W2-C3/C4/W3/W6：C1 路径（PR+ADR 引用，多数引用 ADR-0103 即可）。
- W2-C1/C2、W4：涉及内网执行面建设，卡上须声明 capabilities 与 placement（自建域），
  判定与验收仍锚 GitHub（INV-02）。
- 新仓（env 定义仓）：走 flows.new_repo + GM-4 申报（W1-C2）。
