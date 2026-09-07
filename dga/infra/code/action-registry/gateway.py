"""gateway.py · POST /invoke 调用管线（M4 工具网关核心，六级 + 幂等短路）。

管线（顺序即编号，对齐任务书六级；每级失败即短路并落审计行——审计与放行解耦，
R-POL-01/R-EVID-01）：
  ① 注册表查询       未注册/停用 → 404 + 审计 decision=unregistered（ontology-research §2.3：
                     未注册工具不存在调用路径——不进 schema/OPA/执行器任何后续级）
  ② params 校验      jsonschema(Draft 2020-12) 按注册 schema → 422 + schema_fail
  ③ OPA 鉴权         POST dga/action/tool_invoke（policies/action-authz.rego；tool_decl 由网关
                     从注册表信任源装配，调用方不可伪造）→ deny 403 + 审计含 deny 原因；
                     OPA 不可达 → fail-closed 503 + 审计 denied
  ④ 证据契约执法     is_judgment 工具：执行收据必须带 judge_model+judge_version+
                     calibration_domain_id（R-EVID-04）→ 缺任一 422 + schema_fail（fail_reason 显名）；
                     先于执行——不给"无法出具合规证据的副作用"放行
  ⑤ 幂等（R-FLOW-03） 工具声明 required 而请求缺键 → 422；键命中且 params_hash 一致 →
                     返回首次结果（不执行、不产新证据、副作用计数器不增）；
                     同键异参 → 409 冲突（结果核对）
  ⑥ 执行+证据+审计   mock 执行器（echo+副作用声明回显+计数器）；EvidenceEntity 执行收据行
                     （R-EVID-01 最小形态：tool/params hash/decision/时间戳 + sha256 内容摘要）；
                     ar_audit allowed 行；ar_idempotency 缓存行——四写同事务原子落盘
响应体始终含 audit_id（含全部拒绝路径——每次调用都留审计行）。
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from jsonschema import Draft202012Validator
from pydantic import BaseModel, Field

from .db import get_conn, next_id
from .registry import get_tool

router = APIRouter(tags=["gateway"])

OPA_URL = "http://127.0.0.1:8181"
JUDGE_FIELDS = ("judge_model", "judge_version", "calibration_domain_id")


class Caller(BaseModel):
    person_id: str = Field(min_length=1)
    roles: list[str] = Field(default_factory=list)
    active_authorizations: list[str] = Field(default_factory=list)


class Context(BaseModel):
    caller: Caller
    parent_task_scope: list[str] = Field(default_factory=list)
    task_id: str | None = None


class InvokeRequest(BaseModel):
    tool: str = Field(min_length=1)
    params: dict[str, Any] = Field(default_factory=dict)
    idempotency_key: str | None = None
    context: Context


def canonical(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def params_digest(params: dict[str, Any]) -> str:
    return hashlib.sha256(canonical(params)).hexdigest()


def write_audit(**fields: Any) -> str:
    """独立事务写审计行（失败/拒绝/重放路径用；allowed 路径在管线大事务内联写）。"""
    with get_conn() as conn:
        audit_id = fields.get("id") or next_id(conn, "ar_audit")
        conn.execute(
            "INSERT INTO ar_audit (id, tool_name, caller_person_id, caller_roles, decision, "
            "fail_reason, opa_decision_id, idempotency_key, evidence_entity_id, params_hash, "
            "idempotent_replay, detail) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
            (audit_id, fields.get("tool_name"), fields.get("caller_person_id"),
             json.dumps(fields.get("caller_roles")), fields["decision"],
             fields.get("fail_reason"), fields.get("opa_decision_id"),
             fields.get("idempotency_key"), fields.get("evidence_entity_id"),
             fields.get("params_hash"), fields.get("idempotent_replay", False),
             json.dumps(fields.get("detail"), ensure_ascii=False, default=str)),
        )
    return audit_id


class OPADownError(Exception):
    pass


def opa_tool_invoke(tool: dict[str, Any], req: InvokeRequest) -> tuple[bool, list[str], str | None]:
    """阶段③：OPA dga/action 谓词。tool_decl 由注册表信任源装配（调用方不可伪造）。

    返回 (allow, deny_reasons, opa_decision_id)。decision_id 由 OPA decision log 管道
    （--set decision_logs.console=true）随响应信封返回——R-POL-05 判定记录与审计行的接线点。
    """
    payload = {
        "input": {
            "tool": req.tool,
            "params": req.params,
            "caller": req.context.caller.model_dump(),
            "parent_task_scope": req.context.parent_task_scope,
            "tool_decl": {
                "required_scope": tool["required_scope"],
                "judicial": tool["judicial"],
                "idempotency_key_required": tool["idempotency_key_required"],
            },
        }
    }
    try:
        r1 = httpx.post(f"{OPA_URL}/v1/data/dga/action/tool_invoke",
                        json=payload, timeout=5).json()
        decision_id = r1.get("decision_id")
        reasons: list[str] = []
        if not r1.get("result", False):
            r2 = httpx.post(f"{OPA_URL}/v1/data/dga/action/deny_reasons",
                            json=payload, timeout=5).json()
            reasons = r2.get("result", []) or []
    except Exception as e:  # noqa: BLE001 —— fail-closed：OPA 不可达 = 不允许，绝不默认放行
        raise OPADownError(str(e)) from e
    return bool(r1.get("result", False)), sorted(reasons), decision_id


def _fail(stage: str, code: int, decision: str, reason: str, req: InvokeRequest,
          opa_decision_id: str | None = None, **extra: Any) -> HTTPException:
    """短路出口：先落审计行，再抛 HTTP 异常（审计与放行解耦）。"""
    audit_id = write_audit(
        tool_name=req.tool, caller_person_id=req.context.caller.person_id,
        caller_roles=req.context.caller.roles, decision=decision, fail_reason=reason,
        opa_decision_id=opa_decision_id,
        idempotency_key=req.idempotency_key, params_hash=params_digest(req.params),
        detail={"stage": stage, **extra},
    )
    return HTTPException(code, detail={
        "decision": decision, "fail_reason": reason, "stage": stage,
        "audit_id": audit_id, **extra,
    })


@router.post("/invoke")
def invoke(req: InvokeRequest) -> dict[str, Any]:
    # ---- ① 注册表查询（未注册工具不存在调用路径）----
    tool = get_tool(req.tool)
    if tool is None:
        raise _fail("1-registry", 404, "unregistered", "TOOL-NOT-REGISTERED", req,
                    caller=req.context.caller.model_dump())

    # ---- ② params 按注册 schema 校验 ----
    errors = sorted(Draft202012Validator(tool["params_json_schema"]).iter_errors(req.params),
                    key=lambda e: list(e.absolute_path))
    if errors:
        first = errors[0]
        msg = f"{list(first.absolute_path)}: {first.message}"
        raise _fail("2-params-schema", 422, "schema_fail", "PARAMS-SCHEMA-VIOLATION", req,
                    schema_error=msg)

    params_hash = params_digest(req.params)

    # ---- ③ OPA 鉴权（R-POL-01 真实强制点）----
    try:
        allow, reasons, decision_id = opa_tool_invoke(tool, req)
    except OPADownError as e:
        raise _fail("3-opa", 503, "denied", "R-POL-OPA-UNREACHABLE-FAIL-CLOSED", req,
                    opa_error=str(e)) from e
    if not allow:
        raise _fail("3-opa", 403, "denied", ";".join(reasons) or "R-POL-DENIED", req,
                    opa_deny_reasons=reasons, opa_decision_id=decision_id)

    # ---- ④ R-EVID-04 证据契约执法（判定收据三要件）----
    judge = {f: req.params.get(f) for f in JUDGE_FIELDS}
    if tool["is_judgment"] and any(not judge[f] for f in JUDGE_FIELDS):
        raise _fail("4-evid04", 422, "schema_fail", "R-EVID-04-JUDGE-RECEIPT-INCOMPLETE",
                    req, opa_decision_id=decision_id,
                    missing=[f for f in JUDGE_FIELDS if not judge[f]])

    # ---- ⑤ 幂等（R-FLOW-03：缺键 422 / 同键同参重放 / 同键异参 409）----
    if tool["idempotency_key_required"] and not req.idempotency_key:
        raise _fail("5-idempotency-required", 422, "schema_fail",
                    "IDEMPOTENCY-KEY-REQUIRED", req, opa_decision_id=decision_id)
    if req.idempotency_key:
        with get_conn() as conn:
            cached = conn.execute(
                "SELECT * FROM ar_idempotency WHERE idempotency_key = %s",
                (req.idempotency_key,)).fetchone()
        if cached is not None:
            if cached["params_hash"] != params_hash or cached["tool_name"] != req.tool:
                raise _fail("5-idempotency-conflict", 409, "schema_fail",
                            "IDEMPOTENCY-KEY-CONFLICT-SAME-KEY-DIFFERENT-REQUEST", req,
                            opa_decision_id=decision_id, first_tool=cached["tool_name"])
            replay_audit = write_audit(
                tool_name=req.tool, caller_person_id=req.context.caller.person_id,
                caller_roles=req.context.caller.roles, decision="allowed",
                opa_decision_id=decision_id,
                idempotency_key=req.idempotency_key, params_hash=params_hash,
                idempotent_replay=True, evidence_entity_id=cached["evidence_entity_id"],
                detail={"stage": "5-idempotent-replay", "first_audit_id": cached["audit_id"]},
            )
            body = dict(cached["response"])
            body["idempotent_replay"] = True
            body["replay_audit_id"] = replay_audit
            return body

    # ---- ⑥ 执行（mock）+ 证据 + 审计 + 幂等缓存：四写同事务 ----
    ts = datetime.now(timezone.utc)
    with get_conn() as conn:
        audit_id = next_id(conn, "ar_audit")
        evd_id = next_id(conn, "EvidenceEntity")

        # mock 执行器：echo + 副作用声明回显 + 副作用计数器（真实执行器接入位）
        conn.execute(
            "INSERT INTO ar_mock_effects (tool_name, exec_count, last_executed_at) "
            "VALUES (%s, 1, %s) ON CONFLICT (tool_name) DO UPDATE "
            "SET exec_count = ar_mock_effects.exec_count + 1, last_executed_at = EXCLUDED.last_executed_at",
            (req.tool, ts))
        seq = conn.execute("SELECT exec_count AS n FROM ar_mock_effects WHERE tool_name=%s",
                           (req.tool,)).fetchone()["n"]

        result = {
            "executor": "mock",
            "tool": req.tool,
            "echo": req.params,
            "side_effects_decl": tool["side_effects"],
            "execution_seq": seq,
            "executed_at": ts.isoformat(),
        }

        # 执行收据（R-EVID-01 最小形态：tool/params hash/decision/时间戳）
        receipt = {
            "type": "EXECUTION_RECEIPT", "tool": req.tool, "params_hash": params_hash,
            "decision": "allowed", "ts": ts.isoformat(), "audit_id": audit_id,
            "evidence_entity_id": evd_id, "execution_seq": seq,
            "caller": {"person_id": req.context.caller.person_id,
                       "roles": req.context.caller.roles},
            "parent_task_scope": req.context.parent_task_scope,
            "judge": judge if tool["is_judgment"] else None,
        }
        content_digest = hashlib.sha256(canonical(receipt)).hexdigest()

        conn.execute(
            'INSERT INTO "EvidenceEntity" (id, name, created_at, evidence_type, content_digest, '
            "object_version, storage_uri, object_locked, trace_ref, judge_model, judge_version, "
            'calibration_domain_ref) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)',
            (evd_id, f"execution-receipt:{req.tool}#{seq}", ts, "EXECUTION_RECEIPT",
             content_digest, f"seq-{seq}", f"ar://execution-receipt/{audit_id}", False, None,
             judge.get("judge_model"), judge.get("judge_version"),
             judge.get("calibration_domain_id")))

        conn.execute(
            "INSERT INTO ar_audit (id, tool_name, caller_person_id, caller_roles, decision, "
            "fail_reason, opa_decision_id, idempotency_key, evidence_entity_id, params_hash, "
            "idempotent_replay, detail) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
            (audit_id, req.tool, req.context.caller.person_id,
             json.dumps(req.context.caller.roles), "allowed", None, decision_id,
             req.idempotency_key, evd_id, params_hash, False,
             json.dumps({"stage": "6-executed", "execution_seq": seq})))

        body = {
            "decision": "allowed", "tool": req.tool,
            "caller": req.context.caller.person_id,
            "audit_id": audit_id, "evidence_entity_id": evd_id,
            "opa_decision_id": decision_id,
            "params_hash": params_hash, "result": result, "receipt": receipt,
            "idempotent_replay": False,
        }
        if req.idempotency_key:
            inserted = conn.execute(
                "INSERT INTO ar_idempotency (idempotency_key, tool_name, params_hash, response, "
                "audit_id, evidence_entity_id) VALUES (%s,%s,%s,%s,%s,%s) "
                "ON CONFLICT (idempotency_key) DO NOTHING",
                (req.idempotency_key, req.tool, params_hash,
                 json.dumps(body, ensure_ascii=False), audit_id, evd_id)).rowcount
            if inserted == 0:  # 并发同键：返回首次（缓存行已由赢家写入）
                winner = conn.execute(
                    "SELECT response FROM ar_idempotency WHERE idempotency_key=%s",
                    (req.idempotency_key,)).fetchone()
                replay = dict(winner["response"])
                replay["idempotent_replay"] = True
                return replay
    return body


# ---- 审计查询（负面测试/证据抽查用）----
@router.get("/audit")
def list_audit(tool: str | None = None, decision: str | None = None,
               limit: int = 20) -> list[dict[str, Any]]:
    q = "SELECT * FROM ar_audit"
    conds: list[str] = []
    args: list[Any] = []
    if tool is not None:
        conds.append("tool_name = %s")
        args.append(tool)
    if decision is not None:
        conds.append("decision = %s")
        args.append(decision)
    if conds:
        q += " WHERE " + " AND ".join(conds)
    q += " ORDER BY ts DESC, id DESC LIMIT %s"
    args.append(limit)
    with get_conn() as conn:
        return conn.execute(q, tuple(args)).fetchall()


@router.get("/audit/{audit_id}")
def get_audit(audit_id: str) -> dict[str, Any]:
    with get_conn() as conn:
        row = conn.execute("SELECT * FROM ar_audit WHERE id=%s", (audit_id,)).fetchone()
    if row is None:
        raise HTTPException(404, detail=f"audit row 不存在: {audit_id}")
    return row
