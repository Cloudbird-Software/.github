"""db.py · wf_run_events / wf_activity_idem 的 PG 访问层（psycopg3，同步，autocommit）。

设计（规则锚点）：
- R-FLOW-03：幂等键 = (workflow_id, activity)，权威源是 wf_activity_idem；重试/重放先查它。
- R-FLOW-04：副作用证据 = wf_run_events 行，先写 pending（不确定态）再改 done（已发生态），
  中断的 activity 留下 pending 行，崩溃恢复后可区分"已发生/未发生/不确定"。
- UNIQUE(workflow_id, activity) 双表硬约束：任何重入（重试/重放/同 id 二次 start）都不产生第二行。
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, Optional

import psycopg
from psycopg.types.json import Jsonb

DDL_PATH = Path(__file__).resolve().parent / "ddl.sql"


def dsn() -> str:
    return os.environ.get("DGA_PG_DSN", "host=127.0.0.1 port=5432 user=dga dbname=dga_control")


def connect() -> psycopg.Connection:
    return psycopg.connect(dsn(), autocommit=True)


def ensure_ddl() -> None:
    """幂等建表（ddl.sql 全 IF NOT EXISTS），worker/脚本启动时调用。"""
    with connect() as conn:
        conn.execute(DDL_PATH.read_text(encoding="utf-8"))


# ---------- 幂等表 wf_activity_idem ----------

def idem_get(conn: psycopg.Connection, workflow_id: str, activity: str) -> Optional[Dict[str, Any]]:
    row = conn.execute(
        "SELECT status, result FROM wf_activity_idem WHERE workflow_id=%s AND activity=%s",
        (workflow_id, activity),
    ).fetchone()
    if row is None:
        return None
    return {"status": row[0], "result": row[1]}


def idem_start(conn: psycopg.Connection, workflow_id: str, activity: str) -> bool:
    """占坑（running）。返回 True=本次占坑成功；False=已有人占坑（重入/并发）。"""
    cur = conn.execute(
        """INSERT INTO wf_activity_idem (workflow_id, activity, status)
           VALUES (%s, %s, 'running')
           ON CONFLICT (workflow_id, activity) DO NOTHING
           RETURNING workflow_id""",
        (workflow_id, activity),
    )
    return cur.fetchone() is not None


def idem_done(conn: psycopg.Connection, workflow_id: str, activity: str, result: Dict[str, Any]) -> None:
    conn.execute(
        """UPDATE wf_activity_idem
              SET status='done', result=%s, updated_at=now()
            WHERE workflow_id=%s AND activity=%s""",
        (Jsonb(result), workflow_id, activity),
    )


# ---------- 副作用证据表 wf_run_events ----------

def event_pending(
    conn: psycopg.Connection,
    workflow_id: str,
    run_id: str,
    segment_no: int,
    activity: str,
    title: str,
    detail: Optional[Dict[str, Any]] = None,
) -> bool:
    """写 pending 证据行。返回 True=新建行；False=行已存在（重入，保留首行不动）。"""
    cur = conn.execute(
        """INSERT INTO wf_run_events (workflow_id, activity, segment_no, title, status, detail, run_id)
           VALUES (%s, %s, %s, %s, 'pending', %s, %s)
           ON CONFLICT (workflow_id, activity) DO NOTHING
           RETURNING id""",
        (workflow_id, activity, segment_no, title, Jsonb(detail or {}), run_id),
    )
    return cur.fetchone() is not None


def event_set_status(
    conn: psycopg.Connection,
    workflow_id: str,
    activity: str,
    status: str,
    detail: Optional[Dict[str, Any]] = None,
) -> Optional[Dict[str, Any]]:
    """pending → done|suspended（崩溃恢复核对也走这里）。返回行（供调用方判断）。"""
    cur = conn.execute(
        """UPDATE wf_run_events
              SET status=%s,
                  detail = detail || %s,
                  updated_at=now()
            WHERE workflow_id=%s AND activity=%s
        RETURNING id, status""",
        (status, Jsonb(detail or {}), workflow_id, activity),
    )
    row = cur.fetchone()
    return {"id": row[0], "status": row[1]} if row else None


def event_get(conn: psycopg.Connection, workflow_id: str, activity: str) -> Optional[Dict[str, Any]]:
    row = conn.execute(
        """SELECT activity, segment_no, title, status, detail, run_id, created_at, updated_at
             FROM wf_run_events WHERE workflow_id=%s AND activity=%s""",
        (workflow_id, activity),
    ).fetchone()
    if row is None:
        return None
    return {
        "activity": row[0], "segment_no": row[1], "title": row[2], "status": row[3],
        "detail": row[4], "run_id": row[5],
        "created_at": row[6].isoformat(), "updated_at": row[7].isoformat(),
    }


def events_for(conn: psycopg.Connection, workflow_id: str) -> Dict[str, Dict[str, Any]]:
    rows = conn.execute(
        """SELECT activity, segment_no, title, status, detail, run_id, created_at, updated_at
             FROM wf_run_events WHERE workflow_id=%s ORDER BY segment_no, id""",
        (workflow_id,),
    ).fetchall()
    out: Dict[str, Dict[str, Any]] = {}
    for r in rows:
        out[r[0]] = {
            "activity": r[0], "segment_no": r[1], "title": r[2], "status": r[3],
            "detail": r[4], "run_id": r[5],
            "created_at": r[6].isoformat(), "updated_at": r[7].isoformat(),
        }
    return out


def idem_for(conn: psycopg.Connection, workflow_id: str) -> Dict[str, Dict[str, Any]]:
    rows = conn.execute(
        "SELECT activity, status, result FROM wf_activity_idem WHERE workflow_id=%s ORDER BY activity",
        (workflow_id,),
    ).fetchall()
    return {r[0]: {"status": r[1], "result": r[2]} for r in rows}


def dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, default=str)
