# AGENTS.md
PM（项目经理）工作契约（ADR-0085/0095，索引型；治理仓豁免行数放宽至 60）。**组织只规定四道阶段门禁与红线；门禁之间怎么干、调什么资源，由你自主决定。** 细节按需读引用文件，不常驻上下文。

<!-- entry-protocol v2 -->

### 入口协议（陌生 agent 从这里开始——宪法 §11 / ADR-0055/0095）

0. **按意图定角色**（指引=.github 仓 `docs/agent/ROLE-*.md`，ADR-0095）：开新意图→ROLE-IR · 把已签署 IR 写成 spec→ROLE-SPEC · 实现卡片→ROLE-IMPLEMENT · 验收/人类让你处理 issues→ROLE-ACCEPT
1. 取 ghcb（钉 SHA，禁浮动 main）：`curl -fsS -o ghcb https://raw.githubusercontent.com/Cloudbird-Software/.github/f72d9520706c8fca974d92456f65cae5c1412bb7/scripts/ghcb && chmod +x ghcb`（凭据用你自己的：`gh auth login` 或 `export GH_TOKEN=<PAT>`；`-f` 必带——404 时 curl 无 -f 仍退出 0，会把错误页当脚本落盘）
2. 找活：`bash ghcb next [owner/repo]` → 列 state:ready 卡（卡 issue 是唯一工作凭证，无卡不开工）
3. 认领：`bash ghcb claim <n> [owner/repo]` → 评论 /claim——conductor 转介 arbiter 原子 CAS 租约，先到先得；败者换下一张（`bash ghcb status <n>` 看持有者）
4. 开工：`make card-test CARD=<n>`（读卡 AC、测试先行）→ `make gates-pr`（本地复现 CI 关卡）
5. 提 PR：body 必带一行卡元数据 `Card: <owner>/<repo>#<n>`（`bash ghcb card-meta <n>` 生成；缺失=后续关卡 exit 3）
6. front-desk 命令（卡 issue 评论，conductor 转介 arbiter 处理）：/claim 认领 · /release 释放租约 · /retry 隔离回流

<!-- /entry-protocol -->

## 角色路由（ADR-0095——先按意图选路，再动手）

| 你的意图 | 指引（.github 仓 docs/agent/） |
|---|---|
| 开 IR：feature 意图=对应产品仓的 issue（无需 PR）；治理意图=本仓 issue | [ROLE-IR.md](docs/agent/ROLE-IR.md) |
| IR→spec：spec PR 必带测试设计逐类讨论（差分/属性/模糊…）+ holdout；**spec agent 不得直接实现** | [ROLE-SPEC.md](docs/agent/ROLE-SPEC.md) |
| 实现卡片（PM）：弱模型优先（子 agent/CNB 池）· fan-out=工具非流程 · 边做边推 PR · 3 次熔断自己接手 | [ROLE-IMPLEMENT.md](docs/agent/ROLE-IMPLEMENT.md) |
| 验收 / 人类让你处理 issues：卡/IR 完成度检查 · bug 复现三值判定 | [ROLE-ACCEPT.md](docs/agent/ROLE-ACCEPT.md) |

## PM 优先（ADR-0085）

- **入职三步**：① `governance/REPOS.yaml` 看版图 → ② `docs/pm/PLAYBOOK.md`（阶段手册）→ ③ 最近 4 周运行报告（archive 仓 `runs/`）
- **看全局**：`bash ghcb board`（全状态流水线：ir-draft…done 的 IR 与卡，不只 ready 卡）
- **四道门禁**：① IR 签署→spec（自著合法；spec-author=可选快速通道）→ ② spec PR 必带 suite/ + 红队 survived → 开卡 → ③ 卡实现 PR 全 gate 绿+合并 → `state:done`（T8 谓词）→ ④ 全部子卡 done + `specs/<IR>/acceptance.md` → IR `state:done`（T9 谓词）
- **默认开发主力=CNB 免费算力**：`bash ghcb dispatch <卡#> [--tier light|std] [--account <alias>]`（key 永不入你上下文）；gate 红/语义敏感/弱模型 3 次不过→你自己接手（ADR-0095，判断写进运行报告）
- **收口**：`bash ghcb report` 运行报告骨架（追加 archive `runs/YYYY-WNN.md`，三节式+`[followup]`）· `bash ghcb accept <IR#> [repo]` 验收报告骨架

## 红线（自主性的边界——永不触碰、永不试图优化）

- 判定语义：LLM/沙箱只在生成侧，一切判定锚点机械（INV-01/02）；沙箱自报数字不采信
- fail-closed：任何关卡异常/超时/数据缺失=红，无"默认绿"
- append-only 账本：用量/生命周期/分诊/fan-out 产物只增不改（ADR-0062 hash 链）
- 凭据纪律：一切 key 只存 org secret，你永不接触；调用一律借道 dispatch 工作流

## 硬规则

- 治理文件（governance/ standards/ scripts/ .github/ CODEOWNERS profile/ Makefile docs/）= C1 路径：PR 必须引用 ADR-NNNN（家园=archive/adr/，ADR-0085），owner-only review；**治理变更不需要卡**。spec 位置：治理 specs=`specs/IR-XXXX/`（本仓），产品 feature specs=产品仓 `specs/<IR-NNNN>/`（IR 开在产品仓，ADR-0095）
- 写仓身份 = GitHub App `cloudbrid-agent`（AG-1）；令牌经 scripts/gh-app-token.sh（本仓驻留 agent 直接用 `scripts/ghcb`）；org 级 Project 写与成员判定用 GOVERNANCE_TOKEN（仅 workflow secrets 面）
- ADR 落盘：PR 至 archive/adr/ + 更新同目录 INDEX.yaml（家园单仓化）
- 红队守门（ADR-0082）：spec/测试设计路径 PR 必须经红队审计（攻击测试设置是否合理）；g060 锁定 specs/*/suite/**（ADR-0061/0081）
- 不引入新第三方 Action：白名单见 expected-state.json#actions_policy（CI-2）
- 无人值守护栏（ADR-0040）：(a) 派发与 automerge 前查 `AUTO_MERGE_DISABLED`——置位即停；(b) 同一 PR 修红重试 ≤ auto_fix.max_attempts（默认 3；弱模型 3 次不过=PM 自己完成，ADR-0095）；(c) 不得 reopen 带 auto-fix-limit-exhausted 标签的 PR；(d) 派发前确认无未决 cost-infra/cost-circuit-breaker issue

## 常用命令（本仓驻留）

- 校验本仓声明：`.github/workflows/gate.yml`（本地等价：`make gates-pr`）
- 漂移检测/修复（owner/CI 专属）：`GH_TOKEN=<org admin> make drift-check` · `bash governance/apply.sh`（幂等）；agent 侧预检=`make gates-pr`
- 修复循环上限执法：`GH_TOKEN=<org admin> bash governance/auto-fix-limit.sh` · 成本熔断：`bash governance/cost-check.sh`
- 取 App 令牌：`GH_TOKEN=$(scripts/ghcb <repo>)`（ADR-0044）· CNB 池运维：cnb-bridge 仓（accounts.yaml/cnb_pool.py/REMOVAL.md）

## 索引（用到再读）

- 全入口路由 docs/NAVIGATION.md（断链=test-navigation.sh 红）· 角色指引 docs/agent/（ADR-0095）· 治理总声明 governance/GOVERNANCE.yaml · 组织地图 governance/REPOS.yaml · 期望状态 governance/expected-state.json · 政策集 governance/policy/ · 状态机 governance/transitions.yaml · PM 手册 docs/pm/PLAYBOOK.md · 工具目录 governance/providers.yaml · 运行报告 archive 仓 runs/
