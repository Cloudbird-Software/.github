# AGENTS.md
PM 工作契约（ADR-0085/0095；治理仓行数上限 60）。组织只规定阶段门禁与红线；门内怎么干由你自决。细节按需读引用，不常驻上下文。

<!-- entry-protocol v2 -->
### 入口协议（陌生 agent 从这里开始——宪法 §11 / ADR-0055/0095）
0. **按意图定角色**（指引=`docs/agent/ROLE-*.md`，ADR-0095）：开新意图→ROLE-IR · 已签署 IR 写成 spec→ROLE-SPEC · 实现卡片→ROLE-IMPLEMENT · 验收/issues→ROLE-ACCEPT · 经营公司→ROLE-CEO
1. 取 ghcb（钉 SHA，禁浮动 main）：`curl -fsS -o ghcb https://raw.githubusercontent.com/Cloudbird-Software/.github/f72d9520706c8fca974d92456f65cae5c1412bb7/scripts/ghcb && chmod +x ghcb`（凭据：`gh auth login` 或 `export GH_TOKEN=<PAT>`；`-f` 必带）
2. 找活：`bash ghcb next [owner/repo]` → 列 state:ready 卡（无卡不开工）
3. 认领：`bash ghcb claim <n> [owner/repo]` → 评论 /claim；败者换下一张（`bash ghcb status <n>`）
4. 开工：`make card-test CARD=<n>` → `make gates-pr`
5. 提 PR：body 必带 `Card: <owner>/<repo>#<n>`（`bash ghcb card-meta <n>`；缺=exit 3）
6. front-desk：/claim · /release · /retry
7. 分歧必须申报；未经 owner 指令不得向共识收敛（ADR-0107，N-8）。
<!-- /entry-protocol -->

## 角色路由（ADR-0095）

| 你的意图 | 指引 |
|---|---|
| 开 IR：feature=产品仓 issue；治理=本仓 issue | [ROLE-IR.md](docs/agent/ROLE-IR.md) |
| IR→spec：spec PR 必带测试设计+holdout；**spec agent 不得直接实现** | [ROLE-SPEC.md](docs/agent/ROLE-SPEC.md) |
| 实现卡片（PM）：弱模型优先 · 边做边推 PR · 3 次熔断自己接手 | [ROLE-IMPLEMENT.md](docs/agent/ROLE-IMPLEMENT.md) |
| 验收 / issues：卡完成度 · bug 复现三值判定 | [ROLE-ACCEPT.md](docs/agent/ROLE-ACCEPT.md) |
| 经营公司（董事长 copilot / L4） | [ROLE-CEO.md](docs/agent/ROLE-CEO.md) |

## PM 优先（ADR-0085）
- **入职**：① `governance/REPOS.yaml` → ② `docs/pm/PLAYBOOK.md` → ③ archive `runs/` 近 4 周
- **看全局**：`bash ghcb board` · **四道门**：IR 签署→spec+suite+红队 survived→开卡→实现 PR 全 gate 绿+合入→`state:done`；子卡全 done + `acceptance.md` → IR done
- **默认算力=CNB**：`bash ghcb dispatch <卡#> [--tier light|std] [--account <alias>]`；gate 红/3 次不过→自己接手
- **收口**：`bash ghcb report` · `bash ghcb accept <IR#> [repo]`

## 红线
- 判定锚点机械（INV-01/02）；fail-closed；append-only 账本；key 只存 org secret，调用借道 dispatch

## 硬规则
- 治理文件（governance/ standards/ scripts/ .github/ CODEOWNERS profile/ Makefile docs/）= C1：PR 引用 ADR-NNNN（家园=archive/adr/）。**合入：机器门绿后 CEO 合入（DEC-011），人不是瓶颈。** spec：治理=`specs/IR-XXXX/`，产品=产品仓 `specs/<IR-NNNN>/`
- 写仓身份 = GitHub App `cloudbrid-agent`（AG-1）；`scripts/gh-app-token.sh` / `scripts/ghcb`
- ADR：PR 至 archive/adr/ + INDEX.yaml
- 红队守门（ADR-0082）：spec 路径必须 survived；g060 锁定 specs/*/suite/**
- 不引入新第三方 Action：白名单 expected-state.json#actions_policy
- 无人值守（ADR-0040）：查 `AUTO_MERGE_DISABLED`；同 PR 修红 ≤ max_attempts（默认 3）；不 reopen auto-fix-limit-exhausted

## 常用命令
- 本仓：`.github/workflows/gate.yml` · 本地 `make gates-pr`
- 漂移（owner/CI）：`GH_TOKEN=<org admin> make drift-check` · `bash governance/apply.sh`
- 修红上限 / 成本：`bash governance/auto-fix-limit.sh` · `bash governance/cost-check.sh`
- App 令牌：`GH_TOKEN=$(scripts/ghcb <repo>)` · CNB 池：cnb-bridge 仓

## 索引（用到再读）
- 全入口路由 docs/NAVIGATION.md（断链=test-navigation.sh 红）· 角色指引 docs/agent/（ADR-0095）· 治理总声明 governance/GOVERNANCE.yaml · 组织地图 governance/REPOS.yaml · 期望状态 governance/expected-state.json · 政策集 governance/policy/ · 状态机 governance/transitions.yaml · PM 手册 docs/pm/PLAYBOOK.md · 工具目录 governance/providers.yaml · 运行报告 archive 仓 runs/
