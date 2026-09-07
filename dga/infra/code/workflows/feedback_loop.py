"""feedback_loop.py · FeedbackLoopWorkflow 定义（M3 首条流程）。

结构（六段 + 审批闸门）：
    seg1 客户反馈 → seg2 修复 → seg3 CI/Eval → seg4 发布 → seg5 验收
        → [approval_wait：wait_condition + approval_signal，超时=MET-01 挂起]
        → 批准后 seg6 校准提案 → 完成

规则锚点：
- R-FLOW-01 人类等待在 Temporal（wait_condition+signal），不依赖任何 Agent 会话；会话死了流程照等。
- R-FLOW-03 幂等在 activity 侧（PG 幂等表），workflow 只保证确定性的编排。
- MET-01 超时分支：wait_condition 带 timeout，到点走 suspended 标记 activity 后正常收束
  （Temporal 关闭态=COMPLETED，域内状态=suspended，证据=wf_run_events 的 approval_wait 行）。
注意：workflow 体内不做任何 I/O；activity 以名字符串引用，避免把 psycopg 拖进沙箱。
"""
from __future__ import annotations

from datetime import timedelta
from typing import Any, Dict, Optional

from temporalio import workflow
from temporalio.common import RetryPolicy

from defs import (
    ACT_APPROVED, ACT_AWAITING, ACT_SUSPENDED, FeedbackLoopInput, SEGMENTS, SIGNAL_APPROVAL,
)

RETRY_SEGMENTS = RetryPolicy(initial_interval=timedelta(seconds=1), backoff_coefficient=2.0,
                             maximum_attempts=5)
SEGMENT_OPTS = dict(start_to_close_timeout=timedelta(seconds=30),
                    heartbeat_timeout=timedelta(seconds=6), retry_policy=RETRY_SEGMENTS)
MARKER_OPTS = dict(start_to_close_timeout=timedelta(seconds=15), retry_policy=RETRY_SEGMENTS)


@workflow.defn
class FeedbackLoopWorkflow:
    def __init__(self) -> None:
        self._approval: Optional[Dict[str, Any]] = None

    def _on_approval(self, payload: Dict[str, Any]) -> None:
        self._approval = payload if isinstance(payload, dict) else {}

    async def _seg(self, name: str, inp: FeedbackLoopInput) -> Dict[str, Any]:
        return await workflow.execute_activity(name, inp, **SEGMENT_OPTS)

    async def _marker(self, name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        return await workflow.execute_activity(name, payload, **MARKER_OPTS)

    @workflow.run
    async def run(self, inp: FeedbackLoopInput) -> Dict[str, Any]:
        info = workflow.info()
        timeout_sec = float(inp.approval_timeout_sec)
        workflow.set_signal_handler(SIGNAL_APPROVAL, self._on_approval)

        # 前五段自动执行（客户反馈→修复→CI/Eval→发布→验收）
        segments = [await self._seg(name, inp) for _, name, _ in SEGMENTS[:5]]

        # 进入人类等待：写 approval_wait=pending 证据行
        await self._marker(ACT_AWAITING, {"approval_timeout_sec": timeout_sec,
                                          "feedback_id": inp.feedback_id})

        # R-FLOW-01：等待不依赖会话；timer 分支：MET-01 超时挂起
        approved = True
        try:
            await workflow.wait_condition(
                lambda: self._approval is not None,
                timeout=timedelta(seconds=timeout_sec),
                timeout_summary="approval-timeout-met01",
            )
        except TimeoutError:
            approved = False

        if not approved:
            await self._marker(ACT_SUSPENDED, {"approval_timeout_sec": timeout_sec,
                                               "suspended_at": workflow.now().isoformat()})
            return {
                "workflow_id": info.workflow_id, "run_id": info.run_id,
                "feedback_id": inp.feedback_id, "outcome": "suspended",
                "suspended_reason": "MET-01 approval timeout (auto-suspend)",
                "approval_timeout_sec": timeout_sec, "segments": segments,
            }

        await self._marker(ACT_APPROVED, self._approval or {})
        segments.append(await self._seg("propose_calibration", inp))
        return {
            "workflow_id": info.workflow_id, "run_id": info.run_id,
            "feedback_id": inp.feedback_id, "outcome": "approved",
            "approved_by": (self._approval or {}).get("approver"),
            "segments": segments,
        }
