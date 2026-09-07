"""db.py · 控制面唯一 SQL 触点（SEL-01：psycopg3 同步薄层，无 ORM）。

表名/列名直接使用 gen-sqlddl 产物（schemas/generated/dga-ontology.sql），
API 字段名 = LinkML schema 槽位名——六元组 schema 直映射的落点。
连接串默认本机 trust 认证；服务器阶段经环境变量 DGA_CONTROL_DSN 覆盖。
"""
from __future__ import annotations

import os
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row

DSN = os.environ.get("DGA_CONTROL_DSN", "postgresql://dga@localhost:5432/dga_control")

# ID 体系（M0 定稿前缀）：本表白名单 = 允许服务端发号的表，防 SQL 注入的表名插值
_ID_TABLES = {
    "ClosureUnit": "CU",
    "AccountabilityLink": "ALK",
    "S5DecisionCard": "DC",
    "Authorization": "AUT",
    "Intent": "INT",
    "ContextAsset": "CTX",
    "CapabilityEntity": "CAP",
    "ActionType": "ACT",
    "EvidenceEntity": "EVD",
    "Person": "PSN",
}


@contextmanager
def get_conn():
    """每请求一连接：成功 commit，异常 rollback（延迟 FK 环在 COMMIT 统一校验）。"""
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
    """发号 PREFIX-0001（LinkML pattern ^PREFIX-[0-9]{4,}$，取现最大序号 +1）。"""
    prefix = _ID_TABLES[table]
    row = conn.execute(
        f'SELECT COALESCE(MAX(SUBSTRING(id FROM \'[0-9]+\')::int), 0) + 1 AS n '
        f'FROM "{table}" WHERE id LIKE %s',
        (f"{prefix}-%",),
    ).fetchone()
    return f"{prefix}-{row['n']:04d}"


def next_int_id(conn, table: str) -> int:
    """整型主键表（Budget/DecisionOption 等 LinkML mixin 类）的发号。"""
    row = conn.execute(f'SELECT COALESCE(MAX(id), 0) + 1 AS n FROM "{table}"').fetchone()
    return row["n"]


def must_exist(conn, table: str, id_value: str | None, field: str) -> None:
    """外键目标存在性校验：引用不存在的实体 → 422（在写库前给出可读错误）。"""
    if id_value is None:
        return
    row = conn.execute(f'SELECT id FROM "{table}" WHERE id = %s', (id_value,)).fetchone()
    if row is None:
        raise LookupError(f"{field}: 引用的 {table} 记录不存在: {id_value!r}")
