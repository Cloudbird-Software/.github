"""activities.py · FeedbackLoopWorkflow 的 6 段 mock activity + 3 个审批标记 activity。

统一骨架（规则锚点）：
- R-FLOW-03 幂等：每个 activity 首行查 PG 幂等表 wf_activity_idem（workflow_id+activity 唯一键），
  status=done → 跳过副作用直接返回；status=running → 上次执行中断，做结果核对后补记完成；
  未见过 → INSERT ... ON CONFLICT DO NOTHING 占坑（防并发重入）。
- R-FLOW-04 可区分：每个 activity 先写 wf_run_events pending 行（"不确定"态），
  副作用完成后改 done（"已发生"态）；中断即留 pending 行，inspect 脚本可区分三态。
- R-FLOW-02：mock 副作用 = 本段事件行本身（本机演示无外部系统）；心跳用于让 worker 死亡
  被 server 快速感知（heartbeat_timeout）以便重试交给唯一重试责任方（本 activity）。
"""
from __future__ import annotations

import time
from typing import Any, Callable, Dict, Optional

from temporalio import activity

import db
from defs import ACT_AWAITING, ACT_APPROVED, ACT_SUSPENDED, SEGMENTS, WAIT_EVENT

# 每段 mock 工作耗时：制造可观察的 pending 窗口（崩溃窗口演示用）
MOCK_WORK_SECONDS = 1.0


def _run_idempotent(
    act_name: str,
    title: str,
    segment_no: int,
    inp: Dict[str, Any],
    build_result: Callable[[Dict[str, Any]], Dict[str, Any]],
    pending_detail: Optional[Dict[str, Any]] = None,
    event_name: Optional[str] = None,
) -> Dict[str, Any]:
    """六段与标记 activity 的公共幂等骨架。event_name：事件行 activity 名（默认同 act_name）。

    审批标记三兄弟共用同一事件行 approval_wait（idem 键仍各自独立）。
    """
    info = activity.info()
    wf_id, run_id = info.workflow_id, info.workflow_run_id
    conn = db.connect()
    try:
        # --- R-FLOW-03 首行：幂等表检查（重试/重放/同 id 二次 start 都从这里短路） ---
        prior = db.idem_get(conn, wf_id, act_name)
        if prior is not None and prior["status"] == "done":
            activity.logger.info("[%s] idem hit(done) -> skip side effect", act_name)
            return {
                "activity": act_name, "title": title, "segment_no": segment_no,
                "skipped": True, "recovered": False, "detail": prior["result"],
            }
        recovered = prior is not None and prior["status"] == "running"
        if prior is None:
            if not db.idem_start(conn, wf_id, act_name):  # 并发重入防线
                prior = db.idem_get(conn, wf_id, act_name) or {}
                recovered = prior.get("status") == "running"

        # --- R-FLOW-04：先写 pending 证据行（已存在则保留首行，UNIQUE 兜底） ---
        ev_name = event_name or act_name
        db.event_pending(conn, wf_id, run_id, segment_no, ev_name, title,
                         pending_detail or {})
        activity.heartbeat()  # 存活心跳：worker 被杀后 server 在 heartbeat_timeout 内重投
        time.sleep(MOCK_WORK_SECONDS)  # mock 工作量 = 崩溃窗口

        detail = build_result(inp)
        detail["run_id"] = run_id
        if recovered:
            detail["recovered_from_running"] = True  # 结果核对：中断后补记完成
        db.event_set_status(conn, wf_id, ev_name, "done", {"result": detail})
        db.idem_done(conn, wf_id, act_name, detail)
        activity.logger.info("[%s] done (recovered=%s)", act_name, recovered)
        return {
            "activity": act_name, "title": title, "segment_no": segment_no,
            "skipped": False, "recovered": recovered, "detail": detail,
        }
    finally:
        conn.close()


# ---------- 六段 mock activity ----------

def _segment_activity(seg_no: int, act_name: str, title: str, result_builder):
    def _impl(inp: Dict[str, Any]) -> Dict[str, Any]:
        return _run_idempotent(act_name, title, seg_no, inp, result_builder)
    _impl.__name__ = act_name
    return _impl


@activity.defn
def collect_feedback(inp: Dict[str, Any]) -> Dict[str, Any]:
    return _run_idempotent(
        "collect_feedback", "客户反馈", 1, inp,
        lambda i: {"ticket": f"FB-{i.get('feedback_id')}", "source": "mock-crm",
                   "severity": "P2", "summary": "mock：客户反馈已入册（本行事件=副作用证据）"},
        pending_detail={"phase": "collecting"},
    )


@activity.defn
def apply_fix(inp: Dict[str, Any]) -> Dict[str, Any]:
    return _run_idempotent(
        "apply_fix", "修复", 2, inp,
        lambda i: {"commit": f"mock-{i.get('feedback_id')}-fix", "pr": "#mock-pr",
                   "summary": "mock：修复提交完成"},
        pending_detail={"phase": "fixing"},
    )


@activity.defn
def run_ci_eval(inp: Dict[str, Any]) -> Dict[str, Any]:
    return _run_idempotent(
        "run_ci_eval", "CI/Eval", 3, inp,
        lambda i: {"ci": "passed", "eval_score": 0.93, "harness": "mock-eval-v0",
                   "summary": "mock：CI 绿 + Eval 过线"},
        pending_detail={"phase": "running_ci_eval"},
    )


@activity.defn
def publish_release(inp: Dict[str, Any]) -> Dict[str, Any]:
    return _run_idempotent(
        "publish_release", "发布", 4, inp,
        lambda i: {"release": f"v0.1.0+fb-{i.get('feedback_id')}", "channel": "mock-staging",
                   "summary": "mock：发布完成"},
        pending_detail={"phase": "publishing"},
    )


@activity.defn
def accept_verify(inp: Dict[str, Any]) -> Dict[str, Any]:
    return _run_idempotent(
        "accept_verify", "验收", 5, inp,
        lambda i: {"acceptance": "passed", "verified_by": "mock-acceptor",
                   "summary": "mock：验收通过，待人类批准进入校准提案"},
        pending_detail={"phase": "verifying"},
    )


@activity.defn
def propose_calibration(inp: Dict[str, Any]) -> Dict[str, Any]:
    return _run_idempotent(
        "propose_calibration", "校准提案", 6, inp,
        lambda i: {"proposal_id": f"CAL-mock-{i.get('feedback_id')}",
                   "calibration_domain": "mock-domain",
                   "summary": "mock：校准提案已生成（批准后执行）"},
        pending_detail={"phase": "drafting_calibration"},
    )


# ---------- 审批等待标记 activity（R-FLOW-01 / MET-01） ----------

@activity.defn
def awaiting_approval(inp: Dict[str, Any]) -> Dict[str, Any]:
    """进入人类等待：写 approval_wait pending 行。等待本体由 workflow.wait_condition+signal 承载。"""
    return _run_idempotent(
        ACT_AWAITING, "等待人类批准", 0, inp,
        lambda i: {"waiting": True, "signal": "approval_signal",
                   "approval_timeout_sec": i.get("approval_timeout_sec"),
                   "summary": "mock：等待人工批准（会话可死，等待在 Temporal）"},
        pending_detail={"phase": "awaiting_approval",
                        "approval_timeout_sec": inp.get("approval_timeout_sec")},
        event_name=WAIT_EVENT,
    )


@activity.defn
def approval_received(payload: Dict[str, Any]) -> Dict[str, Any]:
    """收到批准：approval_wait 行 pending → done。幂等同骨架。"""
    info = activity.info()
    wf_id = info.workflow_id
    conn = db.connect()
    try:
        prior = db.idem_get(conn, wf_id, ACT_APPROVED)
        if prior is not None and prior["status"] == "done":
            return {"activity": ACT_APPROVED, "skipped": True, "detail": prior["result"]}
        if prior is None:
            db.idem_start(conn, wf_id, ACT_APPROVED)
        if db.event_get(conn, wf_id, WAIT_EVENT) is None:  # 防御：等待行意外缺失
            db.event_pending(conn, wf_id, info.workflow_run_id, 0, WAIT_EVENT, "等待人类批准", {})
        db.event_set_status(conn, wf_id, WAIT_EVENT, "done", {
            "approver": payload.get("approver"), "note": payload.get("note"),
            "approved_at": payload.get("approved_at"), "signal": "approval_signal",
        })
        detail = {"approver": payload.get("approver"), "note": payload.get("note")}
        db.idem_done(conn, wf_id, ACT_APPROVED, detail)
        return {"activity": ACT_APPROVED, "skipped": False, "detail": detail}
    finally:
        conn.close()


@activity.defn
def approval_suspended(payload: Dict[str, Any]) -> Dict[str, Any]:
    """超时挂起（MET-01 时距到期自动挂起）：approval_wait 行 pending → suspended。"""
    info = activity.info()
    wf_id = info.workflow_id
    conn = db.connect()
    try:
        prior = db.idem_get(conn, wf_id, ACT_SUSPENDED)
        if prior is not None and prior["status"] == "done":
            return {"activity": ACT_SUSPENDED, "skipped": True, "detail": prior["result"]}
        if prior is None:
            db.idem_start(conn, wf_id, ACT_SUSPENDED)
        if db.event_get(conn, wf_id, WAIT_EVENT) is None:
            db.event_pending(conn, wf_id, info.workflow_run_id, 0, WAIT_EVENT, "等待人类批准", {})
        db.event_set_status(conn, wf_id, WAIT_EVENT, "suspended", {
            "reason": "MET-01 时距到期自动挂起",
            "approval_timeout_sec": payload.get("approval_timeout_sec"),
            "suspended_at": payload.get("suspended_at"),
        })
        detail = {"reason": "met01_timeout_suspended",
                  "approval_timeout_sec": payload.get("approval_timeout_sec")}
        db.idem_done(conn, wf_id, ACT_SUSPENDED, detail)
        return {"activity": ACT_SUSPENDED, "skipped": False, "detail": detail}
    finally:
        conn.close()


ALL_ACTIVITIES = [
    collect_feedback, apply_fix, run_ci_eval, publish_release, accept_verify,
    propose_calibration, awaiting_approval, approval_received, approval_suspended,
]

# 供 workflow 侧校验：六段 activity 名与 defs.SEGMENTS 一致
SEGMENT_ACTIVITY_NAMES = [name for _, name, _ in SEGMENTS]
