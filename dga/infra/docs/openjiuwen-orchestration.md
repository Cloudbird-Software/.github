# 2026-09-09 openjiuwen 编排落地草案（CEO 工作区）

> 结论先行：在 CEO 工作区有限试点 TeamAgent/Swarmflow，**不迁移 inbox/outbox/team_run 核心协议**，不复活声明式 team 注册表（ADR-0085）。

## 1. 真实 API 面确认（已读源码）

包路径：`runtime/sdk/.venv-win/Lib/site-packages/openjiuwen/agent_teams/` 与 `symphony/`

### 1.1 TeamAgent 构建面
- `TeamAgentSpec(agents, team_name, lifecycle, leader, ...)` → `build()` → `TeamAgent`
- `agents` 字典键为角色（`"leader"` / `"teammate"`），值为 `DeepAgentSpec(card, system_prompt, subagents=[])`
- `TeamAgent` 是组合而非继承：内部持有 `AgentConfigurator` / `SpawnManager` / `SessionManager` 等管理器
- 关键配置项：`enable_swarmflow`、`dispatch_mode`（`autonomous`/`scheduled`）、`model_pool`/`model_router`、`transport`、`storage`

### 1.2 Swarmflow 面
- 脚本 = 普通 Python 模块，必须有 `META = {"name": ...}` 和 `async def run(args)`
- 入口：`openjiuwen.agent_teams.workflow.runner.run_swarmflow`
- 引擎：dw/wf 确定性引擎 → `TeamWorkerBackend` 将每个 `agent()` 映射为**一次性 WORKER 成员**
- Worker 不是 roster 成员：从 teammate spec（或 leader spec）衍生 spec，单次 `run_once` 后释放
- Leader 视角： spectator，通过 `WorkflowObserver` 收进度事件并转述
- 并发：三层限制 `swarmflow_concurrency`（L1/L2/L3）；可选 `swarmflow_budget` 共享 token 上限

### 1.3 Symphony 面
- `OrchestrationService` / `OrchestrationPlan`：能力图（CapabilityGraph）+ 在线规划
- 当前 CEO 工作区不涉及 skill fingerprint / ontology matching，**本次不启用**

## 2. 与现有协议的关系

| 现有机制 | 定位 | openjiuwen 接缝 |
|---------|------|----------------|
| `state/inbox/*` 工单文件 | 权威任务输入（CEO → PM） | TeamAgent 轮询 inbox 或由 CEO dispatch 触发；工单内容不变 |
| `state/outbox/*` 回执文件 | 权威任务输出（PM → CEO） | TeamAgent 运行结束后写回执；字段与现有四字段 receipt 对齐 |
| `runtime/bin/team_run.py` | 简单并行多成员（JSON spec → 并行 subprocess） | 保留用于纯并行、无状态成员；复杂协调改用 TeamAgent |
| `state/protocol/dev-cycle.md` | 波次五道门 | TeamAgent 运行 itself 不改变门禁；红队/验收仍由 CEO 执行 |

## 3. 迁移路径（三阶段，不搞big bang）

### Phase A：单代理增强（本周）
- 用 `TeamAgentSpec.build()` 包装单个 PM 会话（zcode/grok 无头）
- 替换现有 `ceo_dispatch` / 子代理调用中的裸 `subprocess.run`
- 收益：session checkpoint、model pool 共享、team tools（spawn/claim）可用
- 不碰 inbox/outbox 文件协议

### Phase B：Swarmflow 固定工作流（下周）
- 将红队、审计等固定多阶段脚本改写为 swarmflow script
- 用 `TeamWorkerBackend` 替代手写 `subprocess.run` 多成员并行
- 收益：确定性 phase、budget 控制、observer 可观测
- 前提：Linux 机（Temporal 依赖）或继续用 Windows in-process worker

### Phase C：复杂协调（待 Linux）
- 启用 `dispatch_mode="autonomous"` + `claim_task` 让 leader 动态分派
- 集成 Temporal 持久化 workflow
- 前提：Linux VM / WSL2 with systemd

## 4. 什么不迁

- **inbox/outbox 文件协议**：SSOT 在 git，不迁入 SDK 内部状态
- **team_run.py 简单并行**：纯并行、无依赖成员继续用它，重量更轻
- **声明式 team 注册表**：永久不复活（ADR-0085）
- **Temporal 工作流**：待 Linux 机（当前 windev-01 仅 WSL1，无 systemd/Docker）

## 5. 硬约束

1. **ADR-0085**：不复活 agent-registry 声明式 team 注册表；所有 team 定义以代码/JSON spec 形式存在 runtime/teams/
2. **SEL-04**：权威状态永远在工作区文件/git；TeamAgent.session state 仅作运行态缓存，不作 SSOT
3. **Temporal 待 Linux**：当前 Windows/WSL1 环境不引入 Temporal worker；swarmflow 仅作 in-process 或 subprocess worker
4. **不改变波次协议**：dev-cycle.md 五道门不变；openjiuwen 只是执行工具，不是判定者

## 6. 下一步（CEO 决策项）

- [ ] 批准 Phase A 试点：单 PM 会话包装为 TeamAgent
- [ ] 指定第一个 swarmflow 脚本候选（建议：红队 w5 复盘脚本）
- [ ] 确认 Linux 机到位时间（Temporal / 复杂协调前置）
