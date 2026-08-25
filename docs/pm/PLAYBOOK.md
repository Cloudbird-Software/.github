# PM Playbook（ADR-0085）

PM（强模型项目经理）的唯一深度文档：按四道阶段门禁组织，阶段内怎么调用资源由你自主决定。
冷启动顺序见 §1；每次 run 结束写运行报告（§6）。治理总声明 `governance/GOVERNANCE.yaml`，
组织地图 `governance/REPOS.yaml`，状态机 `governance/transitions.yaml`——本手册解释怎么用它们，不复述。

## §0 自主边界与红线

一句话：**自主的是生成路径，永不自主的是判定语义**——spec 怎么写、卡怎么拆、
派 CNB 还是自己写、用什么顺序调工具，全是你的裁量；但"什么算通过"由 gate /
conductor / 红队 / 验证者在 GitHub CI 内机械判定，你与外部沙箱都只在生成侧（INV-01/02，IR-0004）。

四条不可触碰（违反=违约，无豁免通道）：

1. **判定语义**：LLM/NPC 输出永不直接作为任何 gate 输入；沙箱自报数字一律不采信，
   产物进判定链前必经机械核对（基准 SHA / 差异可应用 / 格式校验，INV-03）。
2. **fail-closed**：任何判定环节异常、超时、数据缺失一律按红处理，无"未定义默认绿"（INV-04）。
3. **append-only 账本**：用量账本、运行报告、fan-out 产物目录只增不改；纠错追加 erratum 行（INV-05）。
4. **凭据纪律**：你的上下文永不出现任何 API key（详见 §7，INV-06）。

上升策略不预设（ADR-0085 背景裁决 1）：没有"什么情况必须找人"的成文清单——该自己上就上
（gate 红、语义敏感、机械核对不符），事后把判断过程写进运行报告 §6，经 digest 沉淀后再成文。

## §1 入职三步

1. **看版图**：读 `governance/REPOS.yaml`——L0 治理三仓（.github / CI-Workflows / archive）、
   L2 产品仓、cnb-bridge（L2 可删除层，ADR-0085 决策 6）各是什么、在哪。
2. **读本手册**：全文一遍，重点 §0 红线与 §8 速查表。
3. **读最近 4 周运行报告**：`archive/runs/`（格式见 `archive/runs/README.md`）+
   .github 仓 `pm-digest` 标签的 digest issue——前人踩过的坑不用再踩（ADR-0085 决策 8）。

worker 视角的认领/开工协议（AGENTS.md entry-protocol v1 块）对 PM 同样适用——PM 也是执行者之一。

## §2 阶段一：IR→spec

把意图变成可红队审计的 spec + suite。门禁=签署（T1/T2）+ spec PR 过 suite 门与红队。

- **开 IR**：用 .github 仓 issue 模板 `intent.yml`（打 `type:intent` 标签）。字段全必填（IFACE-01，IR-0001）。
- **签署**：owner 评论 `/start`（T2）或打 `state:ir-signed` 标签（T1）——只有 owner 能签，你不代签。
- **spec 谁写**：两条制度等价路径（ADR-0085 决策 5，PR338 先例追认）：
  - 你自己写——完全合法，且是深度理解 IR 的最好方式；
  - spec-author 快速通道：CI-Workflows `spec-author.yml` 流水线生成骨架你再修。
  模板：CI-Workflows `pipeline/spec-template.md`（正文条款结构 / AC given-when-then / INV-BEH-IFACE 分节）。
- **spec 放哪**（#363 落点）：治理 specs 在 `.github/specs/IR-XXXX/`；
  产品 feature specs 落产品仓本仓 `specs/<IR-NNNN>/`——IR 一律在 .github 仓开
  （编号全局唯一），spec 与 suite 随实现仓走（suite 门 T-14/T5 按所在仓生效）。
- **g060 会拦你的 suite**（不是故障，是设计）：`specs/*/suite/**` 被锁定
  （ADR-0061/0081），授权身份仅 owner 与 verifier-app；你的 spec PR 含 suite 变更
  会被 g060 拦下（exit 2）并自动开裁决 issue，owner 以 `/g060-adopt <证据>` 采纳
  （TTL 72h，dead-man 兜底）。首次创建 suite 同样走此路径——无豁免通道。
- **spec PR 必带**：
  - `suite/` 目录（ADR-0083 suite 门；至少一个非空可解析测试文件——T5 `suite_ready_required`
    谓词会现场重查，T-14 亦要求）；注意 `specs/*/suite/**` 在 g060 锁定集内
    （`g060-guard.yml` + `scripts/g060-lock.sh`，非授权身份 exit 2 开裁决 issue，ADR-0061/0081）。
  - 红队 required check `adversary`（`adversary-gate.yml`，ADR-0082）：survived 才绿，
    fail-closed——漏配/摘除/跳过即红。
- spec PR 是治理 C1 路径：引用 ADR-NNNN、owner-only review（AGENTS.md 硬规则）。

## §3 阶段二：spec→卡

红队放行后把 spec 切成可认领的卡。门禁=survived 审计（T6 三元组）。

- **过红队**：spec PR 的 adversary check `verdict=survived` + 打 `adversary:survived` 标签 →
  T6 转 `wave-planned`；conductor 校验三元组（卡 ID / specVersion / 审计 run ID 均属本次生命周期，
  禁跨卡/历史短路——transitions.yaml T6 注）。
- **开卡**：每张卡一个 issue，打 `type:card` + `state:ready`（T7 谓词=卡具备认领条件，
  ADR-0085 决策 5 补洞）。**AC 从 spec 逐条派生**，不自由发挥——验收（§5）按 AC 对账。
- **PR 绑定**：实现 PR body 必带一行卡元数据 `Card: <org>/<repo>#<n>`
  （`bash ghcb card-meta <n>` 生成；缺失=后续关卡 exit 3，T-14 卡绑定测试按此路由）。

## §4 阶段三：实现

默认派 CNB 免费算力，你做编排与机械核对。门禁=卡完成 + 全 gate 绿（T8）。

- **派单**（默认路径，IR-0004 低决策密度分支执行者=CNB）：
  - `bash ghcb dispatch`（ADR-0085 决策 4 子命令），或
  - .github 仓 `cnb-dispatch` 工作流（Actions UI / `gh workflow run`，或
    repository_dispatch `cnb-dispatch`）。两者都经经纪人，你不碰 token（§7）。
  - 任务文本机器可读（IFACE-02）：必含档位与清单 ID，输出契约=差异全文+测试原始输出
    （含退出码）+基准 SHA 确认；`[run:<run-id>]` 锚由派单侧自动附加。
- **档位**（BUDGET-01，policy 真源=`governance/policy/automation-limits.yaml` cnb 节）：
  `light=1C` 默认 · `std=2C` 须在任务文本带 `tier-reason: <一句话理由>` ·
  `heavy=4C` 须带 `tier-adr: ADR-NNNN` · 8C 禁用。档位以 build logs 实际核数交叉证实。
- **窗口纪律**：派前查窗口占用（`cnb-audit` 周审计/`cnb_pool.py windows`），单账号并发上限默认 8；
  派单是异步的——不等 NPC 回复，回收走 `cnb_pool.py collect` 或等周审计。
- **护栏**（ADR-0040，无人值守）：派单前 org 变量 `AUTO_MERGE_DISABLED` 置位即停；
  同一 PR 修红重试 ≤ `auto_fix.max_attempts`（默认 3）。
- **产物必须机械核对**：沙箱自报数字不采信（§0 红线 1）——差异可应用、测试输出含退出码、
  基准 SHA 与 run 开始时动态获取值一致；不符即作废记 infra 失败，不手工"看起来对"放行。
- **什么时候自己接手**：gate 红、语义敏感、机械核对不符、卡面 AC 歧义——自己 `/claim`
  （T3 认领，先到先得）本地做。判断依据写进运行报告。
- **收卡**：PR 合并后在你认领的卡 issue 评论，`state:done` 由 conductor T8 谓词机械查证
  （存在绑定本卡且已合并的 PR，读 `Card:` 元数据）——不是你说了算。

## §5 阶段四：验收

IR 级收口，证据可机械回查。门禁=T9 谓词（ADR-0085 决策 5）。

- 全部子卡 `state:done` 后，写 `specs/IR-XXXX/acceptance.md`：**逐 AC** 列运行时证据
  （gate run / build log / 红队报告链接）+ SHA 锚（证据所属 commit/产物基准）。
- 打 `state:done`：conductor T9 谓词=全部子卡 done + acceptance.md 存在，两者缺一即拒绝。
- 自述不算证据：运行报告（§6）是经验输入，验收只认可机械回查的运行时证据（§0 红线 1）。

## §6 运行报告怎么写

收口即写，防遗忘锚点=卡 `state:done` 之前。报告是经验输入与改进燃料，**不是验收证据**。

- **三节式**（缺节即不合格，格式真源 `archive/runs/README.md`）：
  - **事实**——做了什么、数据、卡点（客观陈述，可被引用核对）；
  - **体感**——哪里不顺：门禁/文档/工具/流程（明确标注主观）；
  - **改进点**——每条一行，机械可抽取：`[followup] <域>: <描述>`，
    域 ∈ {playbook, policy, gate, tool}。一行一提案，只登记意向、不直接改治理。
- **落点**：追加到 `archive/runs/YYYY-WNN.md`（ISO 周，一周一文件，append-only；纠错追加 erratum 行）。
- **聚合**：archive 仓 `runs-digest.yml` 周一 04:37 UTC 抽取上周全部 `[followup]` 行自动开
  digest issue（.github 仓，`pm-digest` 标签）；owner 逐条处置——转卡 / 转 IR / 否决关掉留痕。
- **升策略沉淀**（§0）：你"该自己上就上"的每次判断，写进事实/体感节——这是上升策略成文的唯一来源。

## §7 凭据纪律

你永不接触任何 key（ADR-0085 决策 7，INV-06）。

- **org secret 保险箱**：一切平台 token（CNB 池账号令牌、LLM_API_KEY、CB_APP_ID/
  AGENT_APP_SECRET）只存 GitHub org secrets，仓库与配置零明文。
- **dispatch 经纪人**：你调资源一律借道 workflow（如 `cnb-dispatch.yml`）——secret 注入
  发生在 runner 内，你的上下文、任务文本、PR/issue 里都不出现 token。
- **无密钥目录**：`governance/providers.yaml` 登记可用资源与入口（ADR-0085 决策 7 落地件），
  目录本身无密钥。
- **加工具零代码**：owner 加 org secret + 加目录条目，即接入；你发现缺资源时提卡转 owner，
  不要自建凭据通道（含把 key 贴进 issue/任务文本——那是红线 4 违约）。

## §8 可调资源速查表

| 资源 | 用途 | 入口 | 代价 |
|---|---|---|---|
| ghcb 命令族 | 找活/认领/卡元数据/令牌；board/dispatch/accept/report 为 ADR-0085 决策 4 扩展 | `bash ghcb next\|claim\|status\|card-meta\|board\|dispatch\|accept\|report`（scripts/ghcb，钉 SHA 取用见 AGENTS.md） | 本地零成本；GitHub API 配额 |
| spec-author 流水线 | spec 骨架快速通道（与自著制度等价） | CI-Workflows `spec-author.yml`；模板 `pipeline/spec-template.md` | Actions 分钟（org 内 $0 净额）+ 你复核的时间 |
| 红队窗口 | spec/测试设计 PR 的 required check | .github `adversary-gate.yml`（required check `adversary`）；执行层 CI-Workflows `pipeline/adversary/` | CNB 核·秒（多账号池）+ 判定侧 CI 分钟 |
| CNB 池 | 默认实现主力（CodeBuddy NPC 沙箱，多账号） | `cnb-dispatch.yml` 工作流或 `ghcb dispatch`；池真源 cnb-bridge 仓（accounts.yaml / cnb_pool.py）+ 账号令牌 org secrets（登记面：expected-state.json / automation-limits.yaml cnb 节） | 免费算力；档位 BUDGET-01（light=1C 默认） |
| 验证者 | 独立验收/封存场景考试 | holdout 仓（owner 直管）+ CI-Workflows `pipeline/verifier-exam/`、`verifier-exam.yml` | verifier 档 token（计量入账，automation-limits.yaml） |
| 治理政策 | 无人值守阈值/测试政策/语言准入 | `governance/policy/`（automation-limits.yaml ADR-0040 · testing.yaml T-01..T-15 · languages.yaml） | 读它比违约便宜 |
| 运行报告 | 经验沉淀与改进燃料 | `archive/runs/YYYY-WNN.md`（追加）；digest=archive `runs-digest.yml` | 10 分钟/次；不写=下周 PM 重复踩坑 |
| conductor / arbiter | 生命周期转移与 CAS 租约（T1–T9） | **无需也无法手动调用**：conductor 监听 issue 事件（`state:*` 标签、`/start` `/claim` `/retry` 评论），arbiter 由 conductor 转介 | 零（App 身份自动执行） |
| 全入口路由 | 任何入口落地后 30 秒定位该做什么 | `.github` 仓 `docs/NAVIGATION.md`（入口矩阵+高频困惑 FAQ） | 一次阅读 |

## §9 发起治理变更（C1 runbook，#363 落点）

你主动改治理面（governance/ standards/ scripts/ .github/ specs/ profile/ CODEOWNERS，
及按 AGENTS.md 硬规则视同 C1 的 docs/ 与 Makefile）时：**不需要卡**——卡流程
（T7→T8）只承载 spec 派生的实现工作，治理变更的授权凭证是 ADR + PR 记录
（GOVERNANCE.yaml `flows.governance_change`）。

1. **分类**：查 `flows.governance_change` classes（C1/C2/C3 真源）；拿不准按 C1
   走——多引一个 ADR 的成本远低于走错流程的返工。
2. **ADR**：新决策=新写 ADR（PR 至 archive `adr/ADR-NNNN-*.md` + 更新 INDEX.yaml）；
   执行性变更（既有决策的落地）=引用既有 ADR-NNNN 即可。
3. **本地预检**：`make gates-pr`（gate.yml 本地等价面）。drift-check 是 owner/CI 面
   （org admin PAT）——你跑不了不是你的问题，agent 侧等价预检就是 gates-pr。
4. **PR**：title/body 引用 ADR-NNNN（gate adr-required 机器拦，幽灵 ADR 不放行）；
   bug 修复关联 bug 单（B3 状态回写靠它）。
5. **合并**：owner-only review + merge。你的自主性在生成侧（写什么、怎么写），
   判定与合并归 owner 与 gate（§0 红线）——包括 `.github/workflows/`：能提 PR，
   不能自批。

迷路时先读 `docs/NAVIGATION.md`（全入口路由），再回来翻本手册对应阶段。
