"""db.py · Action Registry 唯一 SQL 触点（与控制面 db.py 同款薄层：psycopg3 同步，无 ORM）。

表：ar_tools / ar_audit / ar_idempotency / ar_mock_effects（DDL 权威源 =
gov-infra-repo/policies/action-registry.sql，start 脚本每次重放，Git 为权威源）。
连接串默认本机 trust 认证；服务器阶段经环境变量 DGA_CONTROL_DSN 覆盖（与控制面一致）。
"""
from __future__ import annotations

import os
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row

DSN = os.environ.get("DGA_CONTROL_DSN", "postgresql://dga@localhost:5432/dga_control")

# 本服务允许发号的表/前缀（EvidenceEntity 沿用本体 EVD 前缀；ar_audit 为本服务自有表）
_ID_TABLES = {
    "EvidenceEntity": "EVD",
    "ar_audit": "ARA",
}


@contextmanager
def get_conn():
    """每请求一连接：成功 commit，异常 rollback（管线六写同事务原子落盘）。"""
    conn = psycopg.connect(DSN, row_factory=dict_row)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def next_id(conn, table: str) -> str:
    """发号 PREFIX-0001（与控制面同法：现最大序号 +1）。"""
    prefix = _ID_TABLES[table]
    row = conn.execute(
        f"SELECT COALESCE(MAX(SUBSTRING(id FROM '[0-9]+')::int), 0) + 1 AS n "
        f'FROM "{table}" WHERE id LIKE %s',
        (f"{prefix}-%",),
    ).fetchone()
    return f"{prefix}-{row['n']:04d}"
