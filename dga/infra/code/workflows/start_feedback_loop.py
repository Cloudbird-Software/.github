"""start_feedback_loop.py · 发起 FeedbackLoopWorkflow（client 连 127.0.0.1:7233）。

用法：
    python start_feedback_loop.py <feedback_id> [--timeout-sec N] [--task-queue dga-main]

- approval_timeout_sec：审批等待超时（MET-01 挂起演示秒数）。默认取环境变量
  DGA_APPROVAL_TIMEOUT_SEC，无则 300（演示默认）。
- id_reuse_policy=ALLOW_DUPLICATE：同 workflow_id 二次 start 会开出新 run（用于幂等验收：
  新 run 的 activity 全部被 PG 幂等表短路，副作用不重复）。
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import db  # noqa: E402
import defs  # noqa: E402
from defs import FeedbackLoopInput, workflow_id_for  # noqa: E402

from temporalio.api.enums.v1 import WorkflowIdReusePolicy  # noqa: E402
from temporalio.client import Client  # noqa: E402


async def main() -> int:
    ap = argparse.ArgumentParser(description="发起 FeedbackLoopWorkflow")
    ap.add_argument("feedback_id", help="客户反馈 ID，如 FB-1001（workflow_id=feedback-loop-<id>）")
    ap.add_argument("--timeout-sec", type=float, default=None,
                    help="审批等待超时秒数（默认 DGA_APPROVAL_TIMEOUT_SEC 或 300）")
    ap.add_argument("--task-queue", default=defs.TASK_QUEUE)
    ap.add_argument("--address", default=defs.TEMPORAL_ADDRESS)
    args = ap.parse_args()

    timeout_sec = args.timeout_sec
    if timeout_sec is None:
        timeout_sec = float(os.environ.get("DGA_APPROVAL_TIMEOUT_SEC", "300"))

    db.ensure_ddl()
    client = await Client.connect(args.address, namespace=defs.NAMESPACE)
    wf_id = workflow_id_for(args.feedback_id)
    inp = FeedbackLoopInput(
        feedback_id=args.feedback_id,
        approval_timeout_sec=timeout_sec,
        started_by=os.environ.get("USERNAME", "local-dev"),
    )
    handle = await client.start_workflow(
        "FeedbackLoopWorkflow", inp,
        id=wf_id,
        task_queue=args.task_queue,
        id_reuse_policy=WorkflowIdReusePolicy.WORKFLOW_ID_REUSE_POLICY_ALLOW_DUPLICATE,
    )
    desc = await handle.describe()  # 取实际 run_id（重复 id 场景下指向当前 run）
    print(json.dumps({
        "started": True,
        "workflow_id": wf_id,
        "run_id": desc.run_id,
        "status": getattr(desc.status, "name", str(desc.status)),
        "feedback_id": args.feedback_id,
        "approval_timeout_sec": timeout_sec,
        "task_queue": args.task_queue,
        "id_reuse_policy": "WORKFLOW_ID_REUSE_POLICY_ALLOW_DUPLICATE",
        "address": args.address,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
