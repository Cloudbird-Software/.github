"""main.py · DGA Action Registry / MCP 工具网关 v0（M4 + SEL-13d）组装入口。

启动（共享 venv）：
    D:/Projects/dga-infra/.venv/Scripts/python.exe -m uvicorn app.main:app \
        --host 127.0.0.1 --port 8091      # 工作目录 = action-registry/
常驻启停：services/scripts/start-action-registry.sh / stop-action-registry.sh

本服务 = MCP 网关的 HTTP 形态原型：注册表（/tools）+ 受治理调用路径（/invoke）。
真实 MCP 协议适配（stdio/SSE tool discovery）登记为遗留缺口，服务器阶段接入登记服务器。
"""
from fastapi import FastAPI, HTTPException

import httpx

from .db import DSN, get_conn
from .gateway import OPA_URL, router as gateway_router
from .registry import router as registry_router

app = FastAPI(
    title="DGA Action Registry / MCP Tool Gateway",
    version="0.1.0-M4",
    description=(
        "M4 工具网关 + Action Registry 原型（SEL-13d）：每个 MCP 工具注册时必须绑定本体 "
        "ActionType + params schema + OPA 权限谓词 + 审计要求 + 副作用声明；"
        "未注册工具不存在调用路径（ontology-research §2.3）。"
        "权限在网关强制（R-POL-01），判定隔离（R-POL-04），判定收据三要件（R-EVID-04），"
        "幂等键 + 结果核对（R-FLOW-03）。"
    ),
)

app.include_router(registry_router)
app.include_router(gateway_router)


@app.get("/healthz")
def healthz():
    """DB（注册表行数）+ OPA 可达性。任一不可达 → 503（网关 fail-closed 前置健康位）。"""
    try:
        with get_conn() as conn:
            tools = conn.execute("SELECT count(*) AS n FROM ar_tools WHERE enabled").fetchone()["n"]
    except Exception as e:  # noqa: BLE001
        raise HTTPException(503, detail={"status": "degraded", "db": str(e)}) from e
    try:
        httpx.get(f"{OPA_URL}/health", timeout=3)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(503, detail={"status": "degraded", "opa": str(e),
                                         "opa_url": OPA_URL}) from e
    return {
        "status": "ok",
        "service": "dga-action-registry",
        "milestone": "M4",
        "db_dsn_host": DSN.split("@")[-1].split("/")[0],
        "registered_tools": tools,
        "opa": OPA_URL,
    }
