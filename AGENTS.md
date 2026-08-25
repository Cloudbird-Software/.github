# AGENTS.md

PM（项目经理）工作契约（ADR-0085，索引型；治理仓豁免行数放宽至 60——PM 优先范式的入口即本文件）。**组织只规定四道阶段门禁与红线；门禁之间怎么干、调什么资源，由你自主决定。** 细节按需读引用文件，不常驻上下文。

<!-- entry-protocol v1 -->

### 入口协议（陌生 agent 从这里开始——宪法 §11 / ADR-0055）

1. 取 ghcb（钉 SHA，禁浮动 main）：`curl -fsS -o ghcb https://raw.githubusercontent.com/Cloudbird-Software/.github/f72d9520706c8fca974d92456f65cae5c1412bb7/scripts/ghcb && chmod +x ghcb`（凭据用你自己的：`gh auth login` 或 `export GH_TOKEN=<PAT>`；`-f` 必带——404 时 curl 无 -f 仍退出 0，会把错误页当脚本落盘）
2. 找活：`bash ghcb next [owner/repo]` → 列 state:ready 卡（卡 issue 是唯一工作凭证，无卡不开工）
3. 认领：`bash ghcb claim <n> [owner/repo]` → 评论 /claim——conductor 转介 arbiter 原子 CAS 租约，先到先得；败者换下一张（`bash ghcb status <n>` 看持有者）
4. 开工：`make card-test CARD=<n>`（读卡 AC、测试先行）→ `make gates-pr`（本地复现 CI 关卡）
5. 提 PR：body 必带一行卡元数据 `Card: <owner>/<repo>#<n>`（`bash ghcb card-meta <n>` 生成；缺失=后续关卡 exit 3）
6. front-desk 命令（卡 issue 评论，conductor 转介 arbiter 处理）：/claim 认领 · /release 释放租约 · /retry 隔离回流

<!-- /entry-protocol -->

迷路了（从别的仓/入口进来）？全入口路由表：docs/NAVIGATION.md（入口矩阵+高频困惑 FAQ，ADR-0055/0085，#363 收口）。

## PM 优先（ADR-0085）

- **入职三步**：① `governance/REPOS.yaml` 看版图 → ② `docs/pm/PLAYBOOK.md`（阶段手册：资源/用法/代价/报告格式）→ ③ 最近 4 周运行报告（`Cloudbird-Software/archive` 仓 `runs/`）
- **看全局**：`bash ghcb board`（全状态流水线：ir-draft…done 的 IR 与卡，不只 ready 卡）
- **四道门禁**（组织控制的全部过程面）：① IR 签署→spec——你自著 spec 合法（PR338 先例），spec-author 流水线=可选快速通道 → ② spec PR 必带 suite/ + 红队 survived → 开卡 → ③ 卡实现 PR 全 gate 绿+合并 → 置 `state:done`（T8 谓词机械查合并事实）→ ④ 全部子卡 done + `specs/<IR>/acceptance.md` → IR `state:done`（T9 谓词）
- **默认开发主力=CNB 免费算力**：`bash ghcb dispatch <卡#> [--tier light|std] [--account <alias>]`（经 cnb-dispatch 经纪人，key 永不入你上下文）；gate 红/语义敏感→你自己接手（上升策略不预设，事后写进运行报告）
- **每次 run 结束**：`bash ghcb report` 生成骨架 → 追加到 archive `runs/YYYY-WNN.md`（三节式：事实/体感/改进点；`[followup]` 行=周度 digest 的机械抓手）
- **验收**：`bash ghcb accept <IR#>` 生成验收报告骨架

## 红线（自主性的边界——永不触碰、永不试图优化）

- 判定语义：LLM/沙箱只在生成侧，一切判定锚点机械（INV-01/02）；沙箱自报数字不采信
- fail-closed：任何关卡异常/超时/数据缺失=红，无"默认绿"
- append-only 账本：用量/生命周期/分诊/fan-out 产物只增不改（ADR-0062 hash 链）
- 凭据纪律：一切 key 只存 org secret，你永不接触；调用一律借道 dispatch 工作流

## 硬规则

- 治理文件（governance/ standards/ scripts/ .github/ CODEOWNERS profile/ Makefile docs/）= C1 路径：PR 必须引用 ADR-NNNN（家园=archive/adr/，ADR-0085），owner-only review；**治理变更不需要卡**（卡只承载 spec 派生的实现工作）。spec 位置：治理 specs=`specs/IR-XXXX/`（本仓），产品 feature specs=产品仓 `specs/<IR-NNNN>/`
- 写仓身份 = GitHub App `cloudbrid-agent`（AG-1）；令牌经 scripts/gh-app-token.sh，单仓作用域、1h 过期（本仓驻留 agent 直接用 `scripts/ghcb`）。例外：org 级 Project 写与成员判定用 GOVERNANCE_TOKEN（仅 workflow secrets 面，不落 agent 手）
- ADR 落盘：PR 至 `archive/adr/ADR-NNNN-*.md` + 更新同目录 INDEX.yaml（家园单仓化，ADR-0085）
- 红队守门（ADR-0082）：spec/测试设计路径 PR 必须经红队审计；g060 锁定 specs/*/suite/**（ADR-0061/0081）
- 不引入新第三方 Action：白名单见 expected-state.json#actions_policy（CI-2）
- 无人值守护栏（ADR-0040，跨仓生效）：(a) 派发与 automerge 前查 org 变量 `AUTO_MERGE_DISABLED`——置位即停一切；(b) 同一 PR 修红重试 ≤ automation-limits.yaml `auto_fix.max_attempts`（默认 3）；(c) 不得 reopen 带 `auto-fix-limit-exhausted` 标签的 PR；(d) 派发前确认无未决 `cost-infra`/`cost-circuit-breaker` issue

## 常用命令（本仓驻留）

- 校验本仓声明：`.github/workflows/gate.yml`（本地等价：`make gates-pr`）
- 漂移检测/修复（owner/CI 专属，需 org admin PAT）：`GH_TOKEN=<org admin> make drift-check`（等价 `bash governance/drift-check.sh`，每日 CI 自动跑；agent 侧预检=`make gates-pr`）· `GH_TOKEN=<org admin> bash governance/apply.sh`（幂等）
- 修复循环上限执法：`GH_TOKEN=<org admin> bash governance/auto-fix-limit.sh` · 成本熔断：`GH_TOKEN=<org admin> bash governance/cost-check.sh`
- 取 App 令牌：`GH_TOKEN=$(scripts/ghcb <repo>)`（缓存命中零网络，ADR-0044）
- CNB 池运维：`Cloudbird-Software/cnb-bridge` 仓（accounts.yaml/cnb_pool.py/REMOVAL.md）；周审计=本仓 cnb-audit 工作流（EX-1 三接缝之一）

## 索引（用到再读）

- 全入口路由 docs/NAVIGATION.md（从哪进来→去哪→怎么走；断链=test-navigation.sh 红）· 治理总声明 governance/GOVERNANCE.yaml（agent_runtime/external_compute 域=ADR-0085 新范式）· 组织地图 governance/REPOS.yaml · 期望状态 governance/expected-state.json
- 政策集 governance/policy/（languages/testing/automation-limits 含 cnb: 节）
- 状态机 governance/transitions.yaml（T7 卡就绪/T8 卡完成/T9 IR 验收——conductor 唯一定义源）
- PM 手册 docs/pm/PLAYBOOK.md · 工具目录 governance/providers.yaml（无密钥） · 运行报告 archive 仓 runs/
