> **工作层草案，进治理仓须 C1 路径（PR + ADR + owner review）。**

# M7 漂移重估工作流设计草案

> 契约：`plans/2026-09-09-infra-m59-gap.md` §3.3 第 1、2、4 项  
> 日期：2026-09-09  
> 状态：工作层草案，未经治理仓 PR / ADR / owner review

---

## 1. 背景与范围

本草案针对 M7（池治理完善）中"池组成变更 → 漂移重估工作流"与"时距到期自动挂起机制"两项设计需求，在现有 M2/M3 代码基线与治理仓 schema 上给出可落地的接口与状态机设计。内容严格限于 `plans/2026-09-09-infra-m59-gap.md` §3.3 第 1、2、4 项，不扩展成本熔断（第 3 项）与池健康度量 schema（第 5 项）。

### 1.1 规则基线（与 §3.1 一致）

- **MET-01**：决断时距到期 ⇒ 自动挂起。
- **R-POOL-BUDGET**：闭环级预算上限声明（本草案不展开熔断 spec，但 `CalibrationProposal` 需携带预算影响评估）。
- **R-POOL-TRUST / DATA / COMPLIANCE / DEGRADE / QUOTA / CALIB / EVID**：第 5 章池治理谓词族，在漂移 diff / eval / calibration 各阶段作为规则命中锚点。

### 1.2 现有代码基线

- `code/workflows/feedback_loop.py`：六段骨架 + `approval_wait` 超时挂起模式。
- `code/workflows/defs.py`：`FeedbackLoopInput`、`SEGMENTS`、审批信号常量。
- `pools/ledger.sql`：`pool_providers` / `pool_accounts` / `pool_routing_policies` / `pool_endpoints` 四表。
- `schemas/include/pools.yaml`：本体 `Provider` / `PoolAccount` / `LogicalEndpoint` / `RoutingPolicy` 四类。

---

## 2. PoolCompositionChange 事件 schema

### 2.1 类定义

在 `schemas/dga-ontology.yaml`（或扩展现有 `schemas/include/pools.yaml`）定义 `PoolCompositionChange`，用于描述池组成任一要素的增删改事件。LinkML 风格骨架如下：

```yaml
PoolCompositionChange:
  attributes:
    change_id:
      identifier: true
      range: string
      required: true
      description: 变更事件 ID（DCC-YYYY）。
    change_type:
      range: ChangeType
      required: true
      description: 变更类型（add / remove / update）。
    target_table:
      range: string
      required: true
      description: 变更目标表（providers / accounts / routing_policies / endpoints）。
    target_id:
      range: string
      required: true
      description: 变更目标记录 ID（PRV-/ACC-/RTP-/EPL-前缀）。
    before_snapshot:
      range: JSON
      description: 变更前字段快照（对象级，仅 update/remove 必填）。
    after_snapshot:
      range: JSON
      required: true
      description: 变更后字段快照（对象级）。
    trigger_source:
      range: string
      description: 触发来源（manual / cron_collector / external_webhook）。
    detected_at:
      range: datetime
      required: true
    recorded_at:
      range: datetime
      required: true
    accountable_person:
      range: string
      description: 变更发起责任人（资产目录要件）。
```

### 2.2 与治理仓四表字段对齐

| 目标表 | 对齐字段（`after_snapshot` 必含） | 规则锚点 |
|--------|----------------------------------|----------|
| `pool_providers` | `id`、`name`、`mode`、`tos_risk_matrix_ref`、`data_usage_terms_summary`、`notes`、`created_at`、`retired_at` | R-POOL-COMPLIANCE |
| `pool_accounts` | `id`、`name`、`provider`、`credential_ref`、`cost_tier`、`trust_label`、`tos_risk`、`quota_state`（JSONB）、`health`（JSONB）、`accountable_person`、`notes`、`created_at`、`retired_at` | R-POOL-TRUST / DATA / QUOTA / EVID |
| `pool_routing_policies` | `id`、`name`、`target_capability`、`allowed_cost_tiers`、`min_trust_level`、`max_data_sensitivity`、`quota_constraints`、`calibration_domain_ref`、`fallback_chain`（TEXT[]）、`budget_cap`（JSONB）、`virtual_key_isolated`、`suspension_on_timespan_expiry`、`approval_ref`、`accountable_person`、`created_at` | R-POOL-DEGRADE / BUDGET / CALIB |
| `pool_endpoints` | `id`、`endpoint_name`、`trust_label`、`bound_account_ids`（TEXT[]）、`routing_policy_id`、`litellm_model`、`accountable_person`、`notes`、`created_at`、`retired_at` | R-POOL-TRUST / DATA |

**对齐说明**：
- `quota_state` / `health` / `budget_cap` 为 JSONB 值对象，在事件快照中保持内嵌 JSON，不拆散字段（与本体 `QuotaState` / `HealthSnapshot` / `Budget` 值对象一致）。
- `bound_account_ids` / `fallback_chain` / `allowed_cost_tiers` 为数组列，快照中保持有序数组顺序（降级链顺序语义在 R-POOL-DEGRADE 下不可丢失）。
- `retired_at` 非空时表示 remove 事件，需与 `pool_providers` / `pool_endpoints` 的退役约束一致。
- `virtual_key_isolated` 字段承载 R-POL-03 语义（待治理仓核对），事件快照中需原样保留布尔值，不得缺漏。

---

## 3. DriftReassessmentWorkflow 定义

### 3.1 六段骨架映射

`feedback_loop.py` 六段骨架（`SEGMENTS` 定义在 `defs.py`）是 M3 首条流程的编排原型。漂移重估工作流复用同一骨架，映射关系如下：

| 骨架段 | 反馈循环语义 | 漂移重估映射 | 执行方式 |
|--------|--------------|--------------|----------|
| seg1 | 客户反馈 | `collect_pool_snapshot` | 自动活动 |
| seg2 | 修复 | `diff` | 自动活动 |
| seg3 | CI/Eval | `eval_runner` | 自动活动 |
| seg4 | 发布 | `propose_calibration` | 自动活动 |
| seg5 | 验收 | `pre_approval_validation` | 自动活动（审批前校验） |
| [approval_wait] | 人类批准等待 | `approval_wait` | 超时挂起 |
| seg6 | 校准提案（批准后） | `apply_calibration` | 审批后活动 |

§3.3 第 2 项所列 5 项（`collect_pool_snapshot → diff → eval_runner → propose_calibration → approval_wait`）聚焦审批前主路径与挂起点；seg6 `apply_calibration` 为六段骨架固有段，草案一并占位。

### 3.2 活动签名（mock 版本）

以下签名基于 `feedback_loop.py` 的 `workflow.execute_activity` 模式，使用 Python dataclass 占位。活动本身在 M7 第一波只写 mock，不做真实 I/O。

```python
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional
from temporalio import workflow

# ---- 输入与输出类型 ----

@dataclass
class PoolCompositionChange:
    change_id: str
    change_type: str  # add / remove / update
    target_table: str  # providers / accounts / routing_policies / endpoints
    target_id: str
    before_snapshot: Optional[Dict[str, Any]]
    after_snapshot: Dict[str, Any]
    trigger_source: str
    detected_at: str
    recorded_at: str
    accountable_person: Optional[str]

@dataclass
class PoolSnapshot:
    snapshot_id: str
    taken_at: str
    providers: List[Dict[str, Any]]
    accounts: List[Dict[str, Any]]
    routing_policies: List[Dict[str, Any]]
    endpoints: List[Dict[str, Any]]
    snapshot_hash: str

@dataclass
class DriftReport:
    report_id: str
    change_id: str
    affected_tables: List[str]
    drift_items: List[Dict[str, Any]]
    risk_summary: Dict[str, str]  # 规则命中摘要，key=R-POOL-*，value=命中说明
    detected_at: str

@dataclass
class EvalResult:
    eval_id: str
    change_id: str
    passed: bool
    violations: List[Dict[str, Any]]
    eval_model: str          # judge_model，锚定 R-POOL-EVID
    eval_version: str        # judge_version
    evaluated_at: str

@dataclass
class CalibrationProposal:
    proposal_id: str
    change_id: str
    proposed_actions: List[Dict[str, Any]]
    calibration_domain_ref: Optional[str]  # R-POOL-CALIB
    risk_before: str
    risk_after: str
    proposed_at: str
    budget_impact: Dict[str, float]       # R-POOL-BUDGET 影响评估

@dataclass
class DriftReassessmentInput:
    change_id: str
    approval_timeout_sec: float = 300.0
    started_by: str = "local-dev"
    labels: Dict[str, Any] = field(default_factory=dict)

# ---- Mock activities（signatures 占位） ----

async def collect_pool_snapshot(inp: DriftReassessmentInput) -> PoolSnapshot:
    """seg1：采集变更后全池快照（四表全量），计算 snapshot_hash。"""

async def diff(
    prev: PoolSnapshot,
    curr: PoolSnapshot,
    change: PoolCompositionChange,
) -> DriftReport:
    """seg2：对比前后快照，输出漂移项列表与 R-POOL-* 规则命中摘要。"""

async def eval_runner(report: DriftReport) -> EvalResult:
    """seg3：对漂移项运行 eval（judge_model + judge_version），输出通过/失败。锚定 R-POOL-EVID。"""

async def propose_calibration(
    result: EvalResult,
    report: DriftReport,
) -> CalibrationProposal:
    """seg4：基于 eval 结果提出校准方案（quota_state / routing_policy / trust_label 调整建议）。锚定 R-POOL-CALIB。"""

async def pre_approval_validation(proposal: CalibrationProposal) -> Dict[str, Any]:
    """seg5：审批前就绪校验（责任人签字、calibration_domain_ref 存在、预算上限未溢出 R-POOL-BUDGET）。"""

async def apply_calibration(
    proposal: CalibrationProposal,
    approval: Dict[str, Any],
) -> Dict[str, Any]:
    """seg6：审批后实施校准（写回 ledger.sql 四表 + 更新 evidence）。"""
```

### 3.3 状态机

```
[pending]
    ↓ collect_pool_snapshot
[collecting]
    ↓ diff
[diffing]
    ↓ eval_runner
[evaluating]
    ↓ propose_calibration
[proposing]
    ↓ pre_approval_validation
[validating]
    ↓ approval_wait
[awaiting_approval]
    ├── timeout ──→ [suspended]  ← outcome=suspended
    └── signal ──→ [approved]
                     ↓ apply_calibration
                 [completed]
```

**状态说明**：
- `suspended`：由 `approval_wait` 超时触发（MET-01）。workflow 关闭态 = Temporal `COMPLETED`，域内持久化状态 = `suspended`，证据 = `wf_run_events` 中 `approval_wait` 行 + `ACT_SUSPENDED` marker。
- `approved`：收到审批信号后，`wait_condition` 条件满足，`TimerCanceled`，进入 seg6。
- `completed`：seg6 `apply_calibration` 成功结束。

### 3.4 TimerStarted / TimerCanceled / TimerFired 与 outcome=suspended 语义

`feedback_loop.py` 第 64–69 行使用 `workflow.wait_condition` 承载审批等待。其 Temporal 事件流如下：

1. **TimerStarted**：workflow 进入 `wait_condition` 时，Temporal 调度内部 timer（`timeout_summary="approval-timeout-met01"`），记录为 `TimerStarted` 事件。
2. **TimerCanceled**：在 timeout 之前收到审批信号（`SIGNAL_APPROVAL`），`self._approval` 变为非 None，`wait_condition` 立即返回 True，Temporal 取消 pending timer，记录 `TimerCanceled`。
3. **TimerFired**：timeout 到达而条件未满足，Temporal 触发 `TimerFired` 事件，向 workflow 体抛出 `TimeoutError`。
4. **outcome=suspended**：workflow 捕获 `TimeoutError`，执行 `ACT_SUSPENDED` marker（写 `wf_run_events`），返回字典包含 `outcome: "suspended"`、`suspended_reason: "MET-01 approval timeout (auto-suspend)"`、`suspended_at` 时间戳。此时 workflow 关闭态为 `COMPLETED`，但业务语义为挂起，需 S5 或 owner 手动恢复。

**M7 扩展语义**：
- `suspended_reason` 增加 `drift_type` 字段（`trust_label_change` / `quota_threshold_breach` / `routing_policy_break`），便于漂移分类统计。
- 恢复机制不自动实施校准（避免无人监督的风险链路），需外部触发重新运行或人工审批后补跑 seg6。

---

## 4. AutoSuspendMixin 通用化设计

### 4.1 设计动机

`feedback_loop.py` 中的审批等待模式（signal + wait_condition + timeout + marker）在 M7 漂移重估与 M8 故障演练中均需复用。为避免重复，抽象为 `AutoSuspendMixin`。

### 4.2 接口定义

```python
from temporalio import workflow
from temporalio.common import RetryPolicy

class AutoSuspendMixin:
    """M7/M8 通用自动挂起 mixin。

    用法：Workflow 类多重继承 AutoSuspendMixin + workflow.Defn。
    内部封装 approval_wait 的 signal / wait_condition / timeout / marker 四件套。
    """

    def __init__(self) -> None:
        self._suspend_payload: Optional[Dict[str, Any]] = None

    def _on_approval_signal(self, payload: Dict[str, Any]) -> None:
        self._suspend_payload = payload if isinstance(payload, dict) else {}

    async def approval_wait(
        self,
        signal_name: str,
        timeout_sec: float,
        context: Dict[str, Any],
    ) -> Dict[str, Any]:
        """启动自动挂起等待。

        Args:
            signal_name: Temporal 信号名（如 "approval_signal"）。
            timeout_sec: 超时秒数，默认从 env DGA_APPROVAL_TIMEOUT_SEC 读取
                        （M7/M8 统一配置）。
            context: 追加到 marker 的上下文（如 workflow_id / change_id）。

        Returns:
            approved: {"outcome": "approved", "marker": ..., "approval": ...}
            suspended: {"outcome": "suspended", "marker": ..., "suspended_at": ...,
                        "suspended_reason": ...}
        """
        timeout_sec = float(timeout_sec)
        workflow.set_signal_handler(signal_name, self._on_approval_signal)

        try:
            await workflow.wait_condition(
                lambda: self._suspend_payload is not None,
                timeout=workflow.timedelta(seconds=timeout_sec),
                timeout_summary="auto-suspend-met01",
            )
        except TimeoutError:
            marker = await self._marker("auto_suspend_marker", {
                "timeout_sec": timeout_sec,
                "suspended_at": workflow.now().isoformat(),
                "suspended_reason": "MET-01 approval timeout (auto-suspend)",
                **context,
            })
            return {
                "outcome": "suspended",
                "marker": marker,
                "suspended_at": workflow.now().isoformat(),
                "suspended_reason": "MET-01 approval timeout (auto-suspend)",
            }

        marker = await self._marker("auto_approval_marker", self._suspend_payload)
        return {
            "outcome": "approved",
            "marker": marker,
            "approval": self._suspend_payload,
        }

    async def _marker(self, activity_name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        """复用 feedback_loop.py 的 marker activity 执行模式。"""
        opts = dict(
            start_to_close_timeout=workflow.timedelta(seconds=15),
            retry_policy=RetryPolicy(
                initial_interval=workflow.timedelta(seconds=1),
                maximum_attempts=3,
            ),
        )
        return await workflow.execute_activity(activity_name, payload, **opts)
```

### 4.3 M7/M8 复用场景

| 场景 | signal_name | timeout_sec 来源 | context 追加 |
|------|-------------|-----------------|-------------|
| M7 漂移重估 | `drift_approval_signal` | env `DGA_APPROVAL_TIMEOUT_SEC` | `change_id` / `drift_type` |
| M8 故障演练 | `drill_approval_signal` | env `DGA_APPROVAL_TIMEOUT_SEC` | `drill_id` / `scenario` |

**env 配置**：`DGA_APPROVAL_TIMEOUT_SEC` 为 float 类型秒数，建议生产值 3600（1 小时），演示值 300（5 分钟，与 `FeedbackLoopInput` 默认值对齐）。

---

## 5. 开放问题（待核对）

1. `PoolCompositionChange` 的 `ChangeType` 枚举是否沿用现有 `dga-ontology.yaml` 的变更类型，还是新增？建议复用 `schemas/enums.yaml`（待治理仓核对）。
2. `before_snapshot` 对 `add` 事件是否必须为空对象？草案建议为 null，待本体轨道确认。
3. `apply_calibration`（seg6）的具体幂等键设计（R-FLOW-03）需 M3 worker 实际落地时定夺，本草案只占位。
4. `AutoSuspendMixin` 的 marker activity 名（`auto_suspend_marker` / `auto_approval_marker`）需与 `defs.py` 现有常量风格对齐（待治理仓核对）。
5. `DriftReassessmentInput` 是否继承 `FeedbackLoopInput` 以复用 `approval_timeout_sec` 字段？草案建议独立定义以避免父类耦合，待 ADR 评审时决定。

---

## 6. 进入治理仓的 C1 检查清单

### 6.1 需要 PR 的文件路径

- `schemas/dga-ontology.yaml` 或 `schemas/include/pools.yaml`：新增 `PoolCompositionChange` 类、`ChangeType` 枚举。
- `code/workflows/drift_reassessment.py`：新增 `DriftReassessmentWorkflow` 类 + 六段映射。
- `code/workflows/defs.py`：新增 `DRIFT_SEGMENTS`、`DriftReassessmentInput`。
- `code/workflows/activities.py`：新增 `collect_pool_snapshot` / `diff` / `eval_runner` / `propose_calibration` / `pre_approval_validation` / `apply_calibration` 六个 mock / 实装 activity。
- `code/workflows/auto_suspend_mixin.py` 或合入 `defs.py`：新增 `AutoSuspendMixin` 类。
- `pools/ledger.sql`：若需要持久化 `PoolCompositionChange` 变更日志表，则新增 DDL。
- `policies/pool-routing.rego`：若漂移结果自动触发路由策略调整，则更新 rego 谓词。

### 6.2 需要的 ADR 条目

至少一条 ADR（如 `ADR-M7-001`）记录以下决策：
- 采用 `AutoSuspendMixin` 抽象审批挂起模式，M7/M8 统一超时语义。
- `PoolCompositionChange` 以 JSONB 内嵌快照而非拆表，保持值对象完整性。
- `suspended` 状态不自动恢复，需 owner 人工介入（MET-01 安全边界）。

### 6.3 Owner Review 要点

- S5 / 治理 owner 确认超时阈值（`DGA_APPROVAL_TIMEOUT_SEC`）与各闭环风险等级匹配。
- 确认 `apply_calibration`（seg6）的幂等与回滚策略（R-FLOW-03 延伸）。
- 确认 `PoolCompositionChange` 事件保留期（审计证据保留策略，R-POOL-EVID）。
- 确认 M8 复用 `AutoSuspendMixin` 时，`drill_approval_signal` 的信号路由不与 M7 冲突。
- 确认 `PoolCompositionChange.target_table` 与 `schemas/include/pools.yaml` 四类命名一致。
