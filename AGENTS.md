# AGENTS.md

AI agent 进入本仓的工作契约（索引型，CG-1；治理仓豁免 ≤40 行——协议块+硬规则+索引三合一，ADR-0055 决策 4）。细节按需读引用文件，不常驻上下文。

<!-- entry-protocol v1 -->

### 入口协议（陌生 agent 从这里开始——宪法 §11 / ADR-0055）

1. 取 ghcb（钉 SHA，禁浮动 main）：`curl -fsS -o ghcb https://raw.githubusercontent.com/Cloudbird-Software/.github/f72d9520706c8fca974d92456f65cae5c1412bb7/scripts/ghcb && chmod +x ghcb`（凭据用你自己的：`gh auth login` 或 `export GH_TOKEN=<PAT>`；`-f` 必带——404 时 curl 无 -f 仍退出 0，会把错误页当脚本落盘）
2. 找活：`bash ghcb next [owner/repo]` → 列 state:ready 卡（卡 issue 是唯一工作凭证，无卡不开工）
3. 认领：`bash ghcb claim <n> [owner/repo]` → 评论 /claim——conductor 转介 arbiter 原子 CAS 租约，先到先得；败者换下一张（`bash ghcb status <n>` 看持有者）
4. 开工：`make card-test CARD=<n>`（读卡 AC、测试先行）→ `make gates-pr`（本地复现 CI 关卡）
5. 提 PR：body 必带一行卡元数据 `Card: <owner>/<repo>#<n>`（`bash ghcb card-meta <n>` 生成；缺失=后续关卡 exit 3）
6. front-desk 命令（卡 issue 评论，conductor 转介 arbiter 处理）：/claim 认领 · /release 释放租约 · /retry 隔离回流

<!-- /entry-protocol -->

## 硬规则

- 治理文件（governance/ standards/ scripts/ .github/ CODEOWNERS profile/ Makefile docs/）= C1 路径：PR 必须引用 ADR-NNNN，owner-only review（GOVERNANCE flows.governance_change；与 gate adr-required 机器检查同路径集）
- 红队守门（ADR-0082 / ISSUE-263 AC-1/AC-7/AC-10/AC-11）：LLM 参与判定环节默认采用开源 LLM-as-a-Verifier 范式（四件套：细粒度 reward / criteria 一卡一文件 / K 次重复 / 阈值 gate）；endpoint 三探测（logprobs/top_logprobs/prefill）每次 run 前执行，不满足 fail-closed；token 账与 metering 交叉核对，偏差超阈值 void_and_escalate
- g060 测试分片锁定（ADR-0061 / ISSUE-263 AC-18 / ADR-0081）：`specs/*/suite/**` CODEOWNER = verifier-app + owner；非授权身份改测试 exit 2 + 自动开 issue 路由 owner 裁决（裁决闭环=scripts/g060-escalation.py：终态机器可核 + TTL 48h + dead-man 提醒）
- agent 写仓库身份 = GitHub App `cloudbrid-agent`（AG-1）；令牌经 scripts/gh-app-token.sh，单仓作用域、1h 过期（本仓驻留 agent 直接用 `scripts/ghcb`，等价协议块下载版）。例外：org 级 Project(v2) 写与组织成员判定（App 无 organization_projects/members 权限，ADR-0055 决策 8）用 GOVERNANCE_TOKEN（org admin PAT，仅 workflow secrets 面，不落 agent 手）
- 本仓只读治理声明；ADR 与注册条目落盘 agent-registry（REPOS.yaml L1）
- 不引入新第三方 Action：白名单见 expected-state.json#actions_policy（CI-2）
- 无人值守护栏（ADR-0040，跨仓生效）：(a) 每次任务派发与 `gh pr merge --auto` 前，必须检查 org 变量 `AUTO_MERGE_DISABLED`（`gh api /orgs/Cloudbird-Software/actions/variables/AUTO_MERGE_DISABLED --jq .value`，404=未置位）——置位即停一切派发与 automerge，禁止任何绕过尝试；(b) 同一 PR 的修红重试 ≤ policy/automation-limits.yaml `auto_fix.max_attempts`（默认 3），达上限即停手（auto-fix-limit workflow 会关 PR + 开 issue）；(c) 不得 reopen 带 `auto-fix-limit-exhausted` 标签的 PR；计数真源 = Checks API（commit 元数据），删标签/重开不重置计数；(d) 派发前确认 .github 仓无未决 `cost-infra`/`cost-circuit-breaker` issue（用量不可知时同样停）

## 常用命令（本仓驻留）

- 校验本仓声明：`.github/workflows/gate.yml`（本地等价：`make gates-pr`——bash -n + yaml 全量解析）
- 漂移检测/漂移修复/新仓初始化（**owner 或 CI 专属**——需 org admin PAT，agent 不得持此令牌，AG-1；agent 需要时提卡转交 owner 或走 workflow_dispatch）：`GH_TOKEN=<org admin> bash governance/drift-check.sh`（每日 CI 自动跑；§17=入口协议块对账）· `GH_TOKEN=<org admin> bash governance/apply.sh`（幂等；失败 loud 退出）· `bash scripts/new-repo-init.sh <name>`（owner）
- 修复循环上限执法：`GH_TOKEN=<org admin> bash governance/auto-fix-limit.sh`（小时级；`AUTOFIX_DRY_RUN=1` 只报告；同上 owner/CI 专属）
- 成本熔断检查：`GH_TOKEN=<org admin> bash governance/cost-check.sh`（6h；`COST_USAGE_MINUTES_OVERRIDE=<n>` 注入测试；同上 owner/CI 专属）
- 取 App 令牌：`GH_TOKEN=$(scripts/ghcb <repo>)`（缓存命中零网络；`--refresh` 强刷，ADR-0044）
- factory-floor 板/账本手动刷新：Actions → board-sync（dispatch-only；日常 cron 归 butler-ledger，ADR-0055）

## 索引（用到再读）

- 治理总声明 governance/GOVERNANCE.yaml · 组织地图 governance/REPOS.yaml · 期望状态 governance/expected-state.json
- 政策集 governance/policy/（languages.yaml、testing.yaml T-16 g060_suite_lock、无人值守阈值 automation-limits.yaml ADR-0040 含 verifier token 口径；入口协议/卡元数据=ADR-0055）
- 红队守门制度 ADR-0082（agent-registry/decisions/ADR-0082-redteam-gate.md 墓碑 → archive/adr/ADR-0082-redteam-gate.md 正本）：默认 verifier 范式、三探测、token 账核对、veto 语义、g060、CNB fallback 链、可逆性设计
- agent 标准 schema standards/agent/ · 自动化规范 standards/automation/（ADR-0031/0032/0045）· 注册条目与 ADR → agent-registry 仓
