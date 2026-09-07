"""inspect_side_effects.py · R-FLOW-04 崩溃恢复可区分清单。

用法：
    python inspect_side_effects.py <workflow_id|feedback_id>

对某 workflow 输出七条预期副作用（六段 + approval_wait）的三态判定：
    done      = 已发生（副作用完成且已确认）
    pending   = 不确定（activity 已领取副作用未确认：进行中，或 worker 中断残留）
    suspended = 挂起（MET-01 时距到期自动挂起）
    absent    = 未发生（无行）
附 wf_activity_idem 表状态（幂等权威源）。
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import db  # noqa: E402
from defs import SEGMENTS, WAIT_EVENT, workflow_id_for  # noqa: E402

VERDICT = {
    "done": "已发生",
    "pending": "不确定(进行中或中断残留)",
    "suspended": "挂起(MET-01)",
}


def main() -> int:
    ap = argparse.ArgumentParser(description="某 workflow 的副作用三态清单（R-FLOW-04）")
    ap.add_argument("workflow", help="workflow_id（feedback-loop-xxx）或裸 feedback_id")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    args = ap.parse_args()
    wf_id = args.workflow if args.workflow.startswith("feedback-loop-") else workflow_id_for(args.workflow)

    conn = db.connect()
    try:
        events = db.events_for(conn, wf_id)
        idem = db.idem_for(conn, wf_id)
    finally:
        conn.close()

    expected = [(name, title, seg_no) for seg_no, name, title in SEGMENTS]
    expected.append((WAIT_EVENT, "等待人类批准", 0))
    expected.sort(key=lambda t: (0 if t[2] == 0 else t[2], t[2]))

    lines = []
    counts = {"done": 0, "pending": 0, "suspended": 0, "absent": 0}
    rows = []
    for name, title, seg_no in expected:
        ev = events.get(name)
        if ev is None:
            status, verdict, run_id, updated = "absent", "未发生", "-", "-"
        else:
            status = ev["status"]
            verdict = VERDICT.get(status, status)
            run_id = ev["run_id"] or "-"
            updated = ev["updated_at"]
        counts[status] = counts.get(status, 0) + 1
        rows.append({"activity": name, "segment_no": seg_no, "title": title,
                     "status": status, "verdict": verdict, "run_id": run_id, "updated_at": updated})

    if args.json:
        import json
        print(json.dumps({"workflow_id": wf_id, "rows": rows,
                          "summary": counts, "idem": idem}, ensure_ascii=False, indent=2))
        return 0

    w = 22
    print(f"== wf_run_events 三态清单 · workflow_id={wf_id} ==")
    print(f"{'activity'.ljust(w)}{'seg':<5}{'status':<11}{'判定'.ljust(22)}{'run_id(首写)':<22}updated_at")
    for r in rows:
        print(f"{r['activity'].ljust(w)}{r['segment_no']:<5}{r['status']:<11}{r['verdict'].ljust(22)}"
              f"{r['run_id'][:19].ljust(22)}{r['updated_at']}")
    print(f"== summary == done(已发生)={counts['done']} pending(不确定)={counts['pending']} "
          f"suspended(挂起)={counts['suspended']} absent(未发生)={counts['absent']}")
    if idem:
        print("== wf_activity_idem（幂等权威源）==")
        for name in sorted(idem):
            print(f"  {name.ljust(28)}{idem[name]['status']}")
    else:
        print("== wf_activity_idem（幂等权威源）== (空)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
