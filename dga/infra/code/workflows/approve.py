"""approve.py · 向等待中的 FeedbackLoopWorkflow 发批准信号（approval_signal）。

用法：
    python approve.py <workflow_id|feedback_id> [--approver S5-person] [--note "..."]

R-FLOW-01：人类等待由 Temporal signal 承载——发信号的人/会话与发起流程的会话可以完全无关。
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import defs  # noqa: E402
from defs import SIGNAL_APPROVAL, workflow_id_for  # noqa: E402

from temporalio.client import Client  # noqa: E402


async def main() -> int:
    ap = argparse.ArgumentParser(description="发批准 signal 给 FeedbackLoopWorkflow")
    ap.add_argument("workflow", help="workflow_id（feedback-loop-xxx）或裸 feedback_id")
    ap.add_argument("--approver", default="S5-local", help="批准人（演示占位）")
    ap.add_argument("--note", default="approved via approve.py")
    ap.add_argument("--address", default=defs.TEMPORAL_ADDRESS)
    args = ap.parse_args()

    wf_id = args.workflow if args.workflow.startswith("feedback-loop-") else workflow_id_for(args.workflow)
    payload = {
        "approver": args.approver,
        "note": args.note,
        "approved_at": datetime.now(timezone.utc).isoformat(),
    }
    client = await Client.connect(args.address, namespace=defs.NAMESPACE)
    handle = client.get_workflow_handle(wf_id)
    await handle.signal(SIGNAL_APPROVAL, payload)
    print(json.dumps({
        "signaled": True, "workflow_id": wf_id, "signal": SIGNAL_APPROVAL,
        "approver": payload["approver"], "note": payload["note"],
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
