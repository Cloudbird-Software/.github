# NAVIGATION —— 全入口路由（从哪进来 → 该做什么 → 怎么做）

> 目的：任何 agent / 人从任意入口（org 首页、任意仓、issue 表单、Actions）落地后，
> 30 秒内定位「该做什么、怎么做」。这是 #362 治理可达性审计（32 次 PM 模拟运行，
> 置信度 4.8/10）的收口件之一。
> 依据：ADR-0055（统一入口协议）· ADR-0085（PM 优先范式）· ADR-0095（角色路由 +
> IR 挂靠产品仓）· ADR-0064（Bug 流）。
> 维护契约：新增入口面（仓 / 模板 / 表单 / 工作流）须同步本表；本表引用的本仓文件
> 必须真实存在——断链由 `governance/tests/test-navigation.sh` 机械检测（gate 每 PR 跑）。

## §0 三句话版本

1. **先按意图定角色**（ADR-0095，指引文件在 [docs/agent/](agent/)）：
   开 IR → [ROLE-IR.md](agent/ROLE-IR.md) · 把已签署 IR 写成 spec →
   [ROLE-SPEC.md](agent/ROLE-SPEC.md) · 实现卡片（PM）→
   [ROLE-IMPLEMENT.md](agent/ROLE-IMPLEMENT.md) · 验收 / 处理 issues →
   [ROLE-ACCEPT.md](agent/ROLE-ACCEPT.md)。
2. **在产品/支撑仓干活**（实现角色）→ 唯一工作凭证是卡：`bash ghcb next <owner/repo>` 找
   `state:ready` 卡 → `bash ghcb claim <n>` 认领 → 实现 → PR body 带 `Card: <owner>/<repo>#<n>` 行；
   弱模型优先（子 agent / CNB 池），3 次熔断后 PM 接手。
3. **要改治理面**（governance/ standards/ scripts/ .github/ specs/ profile/ CODEOWNERS，
   以及按 AGENTS.md 硬规则视同 C1 的 docs/ 与 Makefile）→ **不需要卡**：直接开 PR +
   引用 ADR-NNNN + owner review（C1 流程，见 §2）。

## §1 入口矩阵

| 你在哪 / 你是谁 | 先读 | 然后 |
|---|---|---|
| org 首页（profile/README.md） | 本表 §0 | 按角色下钻；仓库全量真源 [governance/REPOS.yaml](../governance/REPOS.yaml) |
| 任意仓、任意图 | §0 角色路由 | 按意图读对应 ROLE-*.md（本仓 docs/agent/） |
| 产品仓（AI_Web_School / mutual / QW_Arena1 …） | 该仓根部 AGENTS.md 的入口协议块+角色路由节 | 取 ghcb（AGENTS.md 内钉 SHA 命令）→ `ghcb next <owner/repo>` 找卡；无卡不开工，新想法走该仓 intent 表单 |
| 治理仓 .github | [AGENTS.md](../AGENTS.md)（本仓契约） | 治理变更走 C1（§2，无需卡）；卡工作照入口协议块 |
| 治理仓 CI-Workflows | 该仓 AGENTS.md | workflow/pipeline 变更=C1 面（.github/ 路径）：PR 引 ADR + owner review |
| 治理仓 archive | `runs/README.md` | 运行报告只追加（append-only）；ADR 落 `adr/` + 更新 INDEX.yaml |
| 支撑仓 cnb-bridge | 仓内 `REMOVAL.md` + `accounts.yaml` | 池运维 owner 面；派单一律经 .github 仓 `cnb-dispatch` 工作流（key 不入上下文） |
| 支撑仓 arbiter / holdout | —（owner 直管） | 你不直接调用（见 §2「conductor/arbiter」）；holdout 对 agent 只读 |
| 发现 bug | [.github/ISSUE_TEMPLATE/bug.yml](../.github/ISSUE_TEMPLATE/bug.yml)（org 级继承，各仓可用） | 提交即机器复现（B1–B5，ADR-0064）：reproduced → 修复合入 → fixed → done；处理 issues 的完整指引=[ROLE-ACCEPT.md](agent/ROLE-ACCEPT.md) |
| 有新意图（feature/治理意图） | [ROLE-IR.md](agent/ROLE-IR.md) | **feature IR 开在对应产品仓**（issue 即 IR，无需 PR；intent.yml 模板 org 级继承）；治理 IR 开 .github 仓。IR 流：owner 签署 → spec（[ROLE-SPEC.md](agent/ROLE-SPEC.md)）→ 红队 → 开卡 |
| 想看全局进度 | `bash ghcb board` | 全状态流水线（ir-draft…done 的 IR 与卡，非只 ready 卡） |
| App 代签失效（写仓令牌签不出） | [pm-credential-convergence.md](pm-credential-convergence.md) | 按 §2 判定失效 → §3 应急回退（owner PAT，24h 窗口）→ 恢复判定 drill 全绿 |
| SLO/值班/破线/break-glass 疑问 | [slo-boundary.md](slo-boundary.md) | 责任边界真源（四节：SLO 定义/值班范围/破线升级路径/break-glass——首个托管客户前写死，IR-0006 W4-R2） |

## §2 高频困惑（#362 实测断裂点，逐条落点）

- **IR 开在哪 / spec 放哪**（ADR-0095）：feature IR 一律开在**对应产品仓**的 issue
  （编号 IR-NNNN 全局唯一，标题前缀；`bash ghcb board` 查重）；治理 IR 开 .github 仓。
  spec 与 suite 随实现仓走：产品 feature specs 落产品仓本仓 `specs/<IR-NNNN>/`，
  治理 specs 在 `.github/specs/IR-XXXX/`（suite 门 T-14/T5 按所在仓生效）。
  spec PR 必带测试设计逐类讨论（testing.yaml 清单 adopt-or-reject，差分/属性/模糊/
  蜕变等）+ holdout 测试设计；开 spec 的 agent **不得直接实现**（ADR-0095）。
- **治理变更要不要开卡**：不要。卡流程（T7→T8）只承载 spec 派生的实现工作；
  治理变更走 C1：PR + 引用 ADR-NNNN（新建或引既有）+ owner-only review + merge。
  同一 PR 不混两种性质。
- **C1 的「drift-check 本地预检」跑不了**：drift-check 需 org admin PAT（owner/CI 专属面）。
  agent 侧等价预检 = `make gates-pr`（.github 仓；CI-Workflows 仓同款目标已就位）；owner 可 `make drift-check`。
  **只读查漂移态**（零凭据）：`gh run list --workflow governance-drift.yml -R Cloudbird-Software/.github --limit 3`
  ——success=无漂移；failure 且 log 含 `DRIFT` 行=真漂移；failure 且 log 含 `FATAL`/exit 2=检测器自身故障
  （多为 GOVERNANCE_TOKEN 失效，owner 面处置，你只消费结论）。
- **g060 拦截了你的 suite 变更**：不是故障，是设计。`specs/*/suite/**` 被锁定
  （ADR-0061/0081），授权身份仅 owner 与 verifier-app；你的 spec PR 含 suite 变更会被
  g060 拦下（exit 2）并自动开裁决 issue，owner 以 `/g060-adopt <证据>` 采纳或
  `/g060-reject` 驳回（TTL 72h）。首次创建 suite 同样走此路径——无豁免通道是刻意的。
- **conductor / arbiter 怎么触发**：不用也无法手动调用。conductor 监听 issue 事件
  （`state:*` 标签、评论 `/start` `/claim` `/retry`），arbiter 由 conductor 转介执行
  CAS 租约。你只管评论与打标签，状态换签是机器的事。（机器面 ADR-0097：conductor
  事件面覆盖 .github + 8 产品仓 + template-service——IR 所在仓即事件仓，全状态机
  语义各仓一致。）
- **测试先行 vs gate 要绿**：红测试不进 main。spec PR 的 suite 断言制度/结构不变量，
  合入时必须绿；修 bug 的失败复现测试走 bug 流（B2 reproduced 锚定 base 红，
  fix PR 合入时转绿）。
- **PM 能不能改 .github/workflows/**：能提 PR——但这是 C1 面：引用 ADR、owner-only
  review；PM 的自主性在生成侧，判定与合并归 owner 与 gate（PLAYBOOK §0 红线）。
- **根目录文件归属（C1 还是 C3）**：GOVERNANCE.yaml `flows.governance_change` 的
  classes 是分类真源；AGENTS.md 硬规则把 docs/ 与 Makefile 一并视同 C1（宁严勿松）。
  拿不准就按 C1 走：多引一个 ADR 的成本远低于走错流程的返工。

## §3 机器护栏

本文件的断链由 [governance/tests/test-navigation.sh](../governance/tests/test-navigation.sh)
机械检测（随 gate 与 `make gates-pr` 每次运行）：入口引用的本仓文件必须存在、
AGENTS.md 行数 ≤ 60（治理仓豁免上限）、入口协议块标记完整、本表必须保留 g060/C1/
drift-check 等高频困惑锚点。
