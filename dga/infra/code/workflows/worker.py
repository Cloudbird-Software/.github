"""worker.py · DGA workflow worker（连 127.0.0.1:7233，task_queue=dga-main）。

- 启动时幂等应用 workflows/ddl.sql（wf_run_events / wf_activity_idem）。
- 把自身 Windows PID 写入 services/workflow-worker/worker.pid（taskkill 精确杀进程用）；
  正常退出时删除；被强杀则留 stale 文件，由 start-workflow-worker.sh 的存活守卫处理。
"""
from __future__ import annotations

import asyncio
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import activities  # noqa: E402
import db  # noqa: E402
import defs  # noqa: E402
from feedback_loop import FeedbackLoopWorkflow  # noqa: E402

from temporalio.client import Client  # noqa: E402
from temporalio.worker import Worker  # noqa: E402

PID_FILE = Path("D:/Projects/dga-infra/services/workflow-worker/worker.pid")


async def main() -> None:
    db.ensure_ddl()
    client = await Client.connect(
        defs.TEMPORAL_ADDRESS, namespace=defs.NAMESPACE,
        identity=f"dga-worker-{os.getpid()}",
    )
    # 同步 activity（psycopg 阻塞调用）跑在线程池
    activity_executor = ThreadPoolExecutor(max_workers=10, thread_name_prefix="dga-act")
    worker = Worker(
        client,
        task_queue=defs.TASK_QUEUE,
        workflows=[FeedbackLoopWorkflow],
        activities=activities.ALL_ACTIVITIES,
        activity_executor=activity_executor,
    )
    print(f"WORKER_READY task_queue={defs.TASK_QUEUE} temporal={defs.TEMPORAL_ADDRESS} "
          f"pid={os.getpid()} activities={len(activities.ALL_ACTIVITIES)}", flush=True)
    await worker.run()


if __name__ == "__main__":
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()), encoding="ascii")
    try:
        asyncio.run(main())
    finally:
        try:
            PID_FILE.unlink()
        except FileNotFoundError:
            pass
