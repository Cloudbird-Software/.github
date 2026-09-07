"""defs.py · FeedbackLoopWorkflow 共享常量与输入类型（workflow/worker/client 三方共用）。

首条流程（M3）：客户反馈 → 修复 → CI/Eval → 发布 → 验收 → [人类批准] → 校准提案
规则锚点：R-FLOW-01（人类等待进 Temporal，不依赖会话）
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict

# Temporal 连接参数（环境变量可覆盖，本地 dev server 默认值）
TEMPORAL_ADDRESS = "127.0.0.1:7233"
TASK_QUEUE = "dga-main"
NAMESPACE = "default"

# 人类批准信号（R-FLOW-01：等待由 signal + wait_condition 承载，会话可死可换人）
SIGNAL_APPROVAL = "approval_signal"

# 六段定义：(段号, activity 名, 中文段名)
SEGMENTS: list[tuple[int, str, str]] = [
    (1, "collect_feedback", "客户反馈"),
    (2, "apply_fix", "修复"),
    (3, "run_ci_eval", "CI/Eval"),
    (4, "publish_release", "发布"),
    (5, "accept_verify", "验收"),
    (6, "propose_calibration", "校准提案"),
]
# 审批等待的三个标记 activity（副作用统一落 wf_run_events 的 approval_wait 行）
WAIT_EVENT = "approval_wait"          # wf_run_events 里的 activity 名
ACT_AWAITING = "awaiting_approval"    # 进入等待（写 pending 行）
ACT_APPROVED = "approval_received"    # 收到批准（pending → done）
ACT_SUSPENDED = "approval_suspended"  # 超时挂起（pending → suspended，MET-01）


@dataclass
class FeedbackLoopInput:
    """workflow 输入。approval_timeout_sec 默认 300（演示用），生产语义=MET-01 决断时距。"""

    feedback_id: str
    approval_timeout_sec: float = 300.0
    started_by: str = "local-dev"
    labels: Dict[str, Any] = field(default_factory=dict)


@dataclass
class SegmentResult:
    activity: str
    title: str
    skipped: bool
    recovered: bool
    detail: Dict[str, Any]


def workflow_id_for(feedback_id: str) -> str:
    return f"feedback-loop-{feedback_id}"
