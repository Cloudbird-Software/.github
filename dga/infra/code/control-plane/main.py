"""main.py · DGA 控制面 v0（M1）组装入口。

启动（共享 venv）：
    D:/Projects/dga-infra/.venv/Scripts/python.exe -m uvicorn app.main:app \
        --host 127.0.0.1 --port 8090      # 工作目录 = control-plane/
常驻启停：services/scripts/start-control-plane.sh / stop-control-plane.sh
"""
from fastapi import FastAPI, HTTPException

from .api import router
from .db import get_conn

app = FastAPI(
    title="DGA Control Plane",
    version="0.1.0-M1",
    description=(
        "控制面薄服务（CMP-01 核心资产）：闭环登记 · 授权与预算 · S5 决策队列。"
        "权威源 = 控制面 DB（DGA-INFRA 第 1 章）；字段映射源 = LinkML schema（M0 产物）。"
    ),
)

app.include_router(router)


@app.get("/healthz")
def healthz():
    """DB 连通 + 表数 + 版本。DB 不可达 → 503。"""
    try:
        with get_conn() as conn:
            tables = conn.execute(
                "SELECT count(*) AS n FROM pg_tables WHERE schemaname = 'public'").fetchone()["n"]
            version = conn.execute("SELECT version() AS v").fetchone()["v"]
        return {
            "status": "ok",
            "service": "dga-control-plane",
            "milestone": "M1",
            "db": "reachable",
            "public_tables": tables,
            "postgres_version": version,
        }
    except Exception as e:  # noqa: BLE001 —— 健康端点必须把故障翻译成 503 而非 500 栈
        raise HTTPException(503, detail={"status": "degraded", "db": str(e)}) from e
