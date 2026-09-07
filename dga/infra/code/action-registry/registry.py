"""registry.py · Action Registry 注册表读写（SEL-13d / ontology-research §2.3）。

每个注册工具 = 本体 ActionType（ACT-xxxx）的运行时投影 + 网关强制点声明：
params schema（按工具独立提交，注册时校验可解析）、OPA 策略位置（package/path）、
必产证据类型（audit_requirements）、副作用声明（side_effects）、幂等要求（R-FLOW-03）、
judicial（R-POL-04 判定隔离标记）、is_judgment（R-EVID-04 判定收据三要件强制）、required_scope（R-POL-02）。

核心不变式：**未注册/停用工具不存在调用路径**——gateway 阶段①即 404+审计行，
不会到达 schema 校验、OPA 或执行器。
"""
from __future__ import annotations

import json
from typing import Any

from fastapi import APIRouter, HTTPException
from jsonschema import Draft202012Validator
from pydantic import BaseModel, Field

from .db import get_conn

router = APIRouter(prefix="/tools", tags=["registry"])

SCOPES = ("public", "internal", "customer_data")
EVIDENCE_TYPES = ("EXECUTION_RECEIPT", "ACCEPTANCE_VERDICT", "AUTHORIZATION_RECORD",
                  "CALIBRATION_ASSET", "POLICY_DECISION")


class ToolRegistration(BaseModel):
    """注册请求体（POST /tools）。Git 种子（action-registry.sql）为权威源，此端点为运行期登记口。"""
    tool_name: str = Field(pattern=r"^[a-z][a-z0-9_]{2,63}$")
    action_type_id: str = Field(pattern=r"^ACT-[0-9]{4,}$")
    params_json_schema: dict[str, Any]
    audit_requirements: list[str] = Field(min_length=1)
    side_effects: dict[str, Any]
    idempotency_key_required: bool = False
    judicial: bool = False
    is_judgment: bool = False
    required_scope: str
    permission_package: str = "dga.action"
    permission_path: str = "tool_invoke"
    enabled: bool = True


def get_tool(tool_name: str) -> dict[str, Any] | None:
    """按名取注册行（仅 enabled）；未注册 → None。"""
    with get_conn() as conn:
        row = conn.execute(
            "SELECT * FROM ar_tools WHERE tool_name = %s AND enabled", (tool_name,)
        ).fetchone()
    return row


def _validate_registration(spec: ToolRegistration) -> None:
    """注册时强制：schema 可解析、证据类型/范围词表合法、 ActionType 存在（FK 前置可读校验）。"""
    try:
        Draft202012Validator.check_schema(spec.params_json_schema)
    except Exception as e:  # noqa: BLE001 —— 注册口的契约校验错误要原样上报
        raise HTTPException(422, detail=f"params_json_schema 不是合法 JSON Schema: {e}") from e
    bad_ev = set(spec.audit_requirements) - set(EVIDENCE_TYPES)
    if bad_ev:
        raise HTTPException(422, detail=f"audit_requirements 含未知证据类型: {sorted(bad_ev)}")
    if spec.required_scope not in SCOPES:
        raise HTTPException(422, f"required_scope 必须∈{SCOPES}")
    with get_conn() as conn:
        if conn.execute('SELECT id FROM "ActionType" WHERE id = %s',
                        (spec.action_type_id,)).fetchone() is None:
            raise HTTPException(422, f"action_type_id 不存在: {spec.action_type_id}")


@router.post("", status_code=201)
def register_tool(spec: ToolRegistration) -> dict[str, Any]:
    """注册/更新工具（运行时投影；权威源仍为 Git 种子，start 脚本重放即收敛）。"""
    _validate_registration(spec)
    with get_conn() as conn:
        conn.execute(
            """
            INSERT INTO ar_tools (tool_name, action_type_id, params_json_schema,
                permission_package, permission_path, audit_requirements, side_effects,
                idempotency_key_required, judicial, is_judgment, required_scope, enabled)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (tool_name) DO UPDATE SET
                action_type_id=EXCLUDED.action_type_id,
                params_json_schema=EXCLUDED.params_json_schema,
                permission_package=EXCLUDED.permission_package,
                permission_path=EXCLUDED.permission_path,
                audit_requirements=EXCLUDED.audit_requirements,
                side_effects=EXCLUDED.side_effects,
                idempotency_key_required=EXCLUDED.idempotency_key_required,
                judicial=EXCLUDED.judicial,
                is_judgment=EXCLUDED.is_judgment,
                required_scope=EXCLUDED.required_scope,
                enabled=EXCLUDED.enabled
            """,
            (spec.tool_name, spec.action_type_id,
             json.dumps(spec.params_json_schema), spec.permission_package,
             spec.permission_path, json.dumps(spec.audit_requirements),
             json.dumps(spec.side_effects), spec.idempotency_key_required,
             spec.judicial, spec.is_judgment, spec.required_scope, spec.enabled),
        )
    return {"registered": spec.tool_name, "action_type_id": spec.action_type_id,
            "permission": f"{spec.permission_package}/{spec.permission_path}"}


@router.get("")
def list_tools() -> list[dict[str, Any]]:
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT tool_name, action_type_id, permission_package, permission_path, "
            "audit_requirements, side_effects, idempotency_key_required, judicial, "
            "is_judgment, required_scope, enabled, registered_at FROM ar_tools ORDER BY tool_name"
        ).fetchall()
    return rows


@router.get("/{tool_name}")
def get_tool_api(tool_name: str) -> dict[str, Any]:
    row = get_tool(tool_name)
    if row is None:
        raise HTTPException(404, detail=f"tool 未注册: {tool_name}")
    return row


@router.get("/{tool_name}/effects")
def tool_effects(tool_name: str) -> dict[str, Any]:
    """mock 执行器副作用计数器（负面测试⑦的观测点）。"""
    with get_conn() as conn:
        row = conn.execute(
            "SELECT tool_name, exec_count, last_executed_at FROM ar_mock_effects WHERE tool_name=%s",
            (tool_name,),
        ).fetchone()
    if row is None:
        raise HTTPException(404, detail=f"tool 无副作用记录: {tool_name}")
    return row
