# IR-0006 验收报告（T9 / T-15 意图回探）

- IR: Cloudbird-Software/.github#402（治理战略总纲吸收——三面分离治理架构、证据账本统一与云内网入图）
- 验收人: PM（GLM-5.3 会话，owner 全量授权）
- 验收日期: 2026-08-29
- 判据: IR#402 正文的 10 条"期望的可观察变化"逐条回探（T-15，ROLE-ACCEPT 对账基准）+ 冷上下文六问复测（IR-0005 AC-7 同款）

## 子卡清单（20 张全 done——T9 前置）

| 波次 | 卡 | 标题 | 绑定 PR（Card: 元数据机械对账） |
|---|---|---|---|
| W1 | #405 | 宪法 v2.4 吸收 I3/I4/I7+GOVERNANCE evidence_ledger | .github#426 |
| W1 | #406 | 证据 schema v1 定稿+archive evidence/ 载体 | .github#429+archive#41 |
| W1 | #407 | 三源对齐（metering/butler/drill 双写+tenant） | .github#430 |
| W1 | #408 | 轨迹层指针协议 pointer@1+内网 blob | .github#431 |
| W1 | #409 | providers.yaml self-cloud-pool/vault+资产登记簿 | .github#427 |
| W1 | #410 | env-defs 建仓+REPOS.yaml 申报 | .github#428 |
| W1 | #411 | 决策语料 append-only+链式 hash | archive#40 |
| W2 | #412 | 内网调度器 v0（Job Contract+短票据+egress） | .github#444 |
| W2 | #413 | PM 凭证收敛 gh-app-token 上收+应急回退 | .github#446+archive#43 |
| W2 | #414 | Wave schema 入卡+conductor/cost-check 消费 | .github#432/#433/#436/#438 |
| W2 | #415 | JIT elevation v0（/elevate+arbiter 策略表） | .github#440-#443 |
| W3 | #416 | 飞书多维表格投影（同步器+调用账本） | .github#447-#451 |
| W3 | #417 | 重建保真与漂移纠正（drop&rebuild+HO 场景 2） | run 33254361404 演练+feishu-ledger 分支 |
| W4 | #418 | env 期望态+实况+drift 引擎泛化 | .github#452 |
| W4 | #419 | SLO 骨架进 sli-weekly+责任边界 | .github#454 |
| W4 | #420 | 签名证据包 v0（attestation+SBOM 绑定） | .github#456/#457+archive#46/#47 |
| W5 | #421 | eval registry（四元组 pin+eval gate 家族） | .github#458+holdout#9 |
| W5 | #422 | 首个 optimization 波次 exit gate 全链 | .github#459/#460+archive#48 |
| W6 | #423 | conformance 语料库种子+四列元治理 | .github#461+archive#49 |
| W6 | #424 | R3→R1 反馈边骨架 | .github#462（候选 #463/#464 实产） |

spec PR：.github#403（adversary:survived 红队审计通过）；背书 ADR：archive#38/#39（ADR-0103）。

## 逐条回探（T-15——十条期望变化 × 运行时证据）

| # | 期望变化 | 证据 | 结论 |
|---|---|---|---|
| 1 | 18 章节落位表+词汇归并表，spec PR 红队 survived | specs/IR-0006/absorption-map.md（落位表"已覆盖映射/吸收后退役"两类+词汇归并）；.github#403 merged，IR#402 带 adversary:survived | ✅ |
| 2 | ADR-0103 落 archive/adr/ 并入 INDEX.yaml（risk_class=参数包选择器，裁决仍硬谓词+shadow） | archive PR #38/#39 merged；archive/adr/0103*；宪法 §5 未动（调和非回退） | ✅ |
| 3 | 统一判定层账本（三层/payload 指针/月度 checkpoint/hash 链/tenant/三源同 schema 查询） | archive evidence/ledger.jsonl（链尾 841c63dcaab5）+checkpoints/2026-08.json；**本轮实测**：scripts/verify_evidence.py 独立复算 OK（3 条链完整+checkpoint×1 对账一致）；governance/evidence-query.sh 七源（metering/drill/butler/elevation/tickets/feishu/env）一条命令 | ✅ |
| 4 | providers.yaml 含 self-cloud-pool/vault；env-defs 建仓申报 REPOS.yaml，期望态/实况可对账 | .github#427（providers+governance/assets-register.yaml）+#428（REPOS.yaml 申报）；.github#452 env-drift 引擎（run 33257903305 漂移检出→issue #453 自动开→消除自动关，GM-1 实走） | ✅ |
| 5 | PM 凭证收敛为 cloudbrid-agent 短令牌，个人 PAT 退出日常 | .github#446（gh-app-token 上收+应急回退通道 24h 窗口文档化，ADR-0044）；本会话起全程 GH_TOKEN=gh-app-token.sh 代签 | ✅ |
| 6 | 飞书多维表格看板（label 唯一真源，drop & rebuild） | .github#447-#451；feishu-ledger 分支（影子账本链验通过）；run 33254361404：人工违规改表被下轮投影纠正+drift 告警入账本（INV-05 实证）；飞书 API 数字字段字符串怪癖/batch POST 形态两实测缺陷修复（#450/#451） | ✅ |
| 7 | R3 骨架在跑（env 期望态+漂移对账+SLO 进 sli-weekly） | env-drift.yml 每日 07:33 UTC 定时+scope=dev/staging（prod 不在检测面，R3 相位）；.github#454 sli-weekly SLO 骨架+责任边界文件 | ✅ |
| 8 | Wave schema budget/capabilities/evidence 进卡模板并被 conductor/cost-check 消费 | .github#432（schema+解析器）+#433（conductor T7 解析存储+cost-check 波次视图硬停三件套，BEH-07 熔断位实测 exit 4） | ✅ |
| 9 | holdout 扩展 eval registry+非劣性 eval gate，首个 optimization 波次走通 | holdout#9（eval-quad 四元组 pin）+.github#458；W5-OPT-1 波次（waves.yaml 注册）：run 33263909046 基线/候选同 harness 评测+非劣性裁决 GREEN；fail-closed 活体：run 33263613945 ts 缺字段被 verify_evidence 拦截红→#460 修复重跑绿 | ✅ |
| 10 | 决策语料 append-only 落 archive 开始累积 | archive decisions/ledger.jsonl（链式 hash+机械校验；首条真实记录 ADR-0103 决策情境，五段齐备） | ✅ |

**十条全绿。**

## 冷上下文六问复测（a-f，主链路零假链）

| 问 | 回答 | 真实来源（可点验） |
|---|---|---|
| a | 第一天干什么 | AGENTS.md 入口协议（ghcb next→claim→card-test→gates-pr→PR）；角色指引 docs/agent/ROLE-*.md |
| b | 进行中工作是什么 | 管家账本 dashboard issue #200（机器可读 JSON，北极星对+在制卡清单）；`bash ghcb board` 全状态流水线 |
| c | IR→spec 的路径是什么 | ROLE-SPEC.md 四道门禁（签署→spec PR 带 suite+红队→开卡→T8→T9）；specs/IR-0006/ 本 IR 即实例 |
| d | 可调资源有哪些 | governance/REPOS.yaml（组织版图）+providers.yaml（cnb-pool/self-cloud-pool/vault/llm 路由）；CNB 免费算力=默认开发主力（bash ghcb dispatch） |
| e | 复盘落点在哪 | archive runs/（2026-W35 分段运行报告，三节式+[followup]）；`bash ghcb report` 骨架 |
| f | key 怎么获取 | org secret（GOVERNANCE_TOKEN 等，仅 workflow secrets 面）+scripts/gh-app-token.sh App 代签（ADR-0044）——agent 上下文零凭据，全链经 dispatch 工作流 |

六问全有真实来源可答——复测通过。

## 状态机实走记录（T8 全程）

- 20 子卡全部经 /claim（arbiter CAS 租约）→ 实现态 → state:done（T8）；conductor 跨仓核验（merged PR search+Card: 串精确复核）
- 负向执法样本：eval-wave run 33263613945 落账步红（fail-closed 无默认绿）；feishu 人工违规改表被投影纠正；gitleaks 504 瞬态红经 failed-job 重跑绿（非泄密，PR #461 留痕）
- T9 谓词：全部子卡 done（20/20）+ 本文件合并 → IR#402 可收口

## 残留与移交（诚实申报）

1. **反馈边首产候选待 owner 裁决**：#463（needs-human p90 30.39h>24h 停摆线）/#464（逃逸护栏 red 双窗）——真实信号越阈自动生成，停留 state:ir-draft（AC-8h：无自动签署旁路）。根因指向 §7 注意力面（P0 停滞+非演习 [auto-revert] 事件），建议 owner 醒后优先裁决。
2. **R5 骨架未立项**（IR 非目标：外输三件套另行立项）——conformance/ 产物（32 卡语料+四列评审+晋级账本）已为外输预留底料。
3. **仪表盘 pending 项**：user_results 全产品仓 pending（埋点未落）、holdout_gap 检测面未建——按 ADR-0073 决策 7 诚实 pending，不造数。
4. **飞书数字字段字符串怪癖**已修（#450）但飞书 API 形态漂移风险常在——feishu-drill 每日演练=回归面。
5. **main 直推事件（2026-08-29 17:36 UTC）**：owner 侧另一会话将"一人公司治理体系诊断与落地"巨型提交（15ac9c1）直推 main——绕过全部门禁（治理文件一致性未验）；其携带 holdout/ gitlink 致 CI checkout 全红（#438 同款缺陷），由本 PR 修复（git rm --cached holdout）。直推豁免未登记——建议 owner 醒后按 ADR-0093 同款追认或回退。

## 结论

IR#402 十条期望变化全部有运行时证据支撑，冷上下文六问复测通过，20/20 子卡 done。T9 谓词满足，IR-0006 可收口（state:done）。
