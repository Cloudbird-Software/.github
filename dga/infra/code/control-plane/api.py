"""api.py · 控制面路由（闭环登记 / S5 决策队列 / 授权）。

治理锚点：
- R-GOV-03  缺具名责任人 → API 层 pydantic required（422）+ DB 层
            ClosureUnit.accountability_id NOT NULL + FK 双层拒绝。
- R-GOV-04  S5 决策卡片固定结构；字段缺失 → 422。
- R-SEC-04  签发不可代（M1 最小形态）：X-S5-Person 头必须等于卡片 addressee，
            否则 403。真实身份体系待服务器阶段（见 README 诚实边界）。
- R-POL-02  授权三要素 scope / budget / decision_timespan 强制在位。
"""
from __future__ import annotations

import re
from datetime import datetime
from typing import Literal, Optional

from fastapi import APIRouter, Header, HTTPException, Query
from pydantic import BaseModel, Field

from .db import get_conn, must_exist, next_id, next_int_id

router = APIRouter()

# LinkML enums（schemas/generated/dga-ontology.schema.json 同源键名）
ClosureState = Literal[
    "DRAFT", "REGISTERED", "AUTHORIZED", "RUNNING", "AWAITING_VERIFICATION",
    "SUSPENDED", "COMPLETED", "FAILED", "RETIRED",
]
AutonomyLevel = Literal["L0", "L1", "L2", "L3", "L4", "L5"]
TrustLevel = Literal["T0", "T1", "T2"]
# DecisionTimespan 类型 pattern（schemas/include/base.yaml，ISO 8601 duration）
TIMESPAN_RE = re.compile(
    r"^P(?!$)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?=\d)(\d+H)?(\d+M)?(\d+(\.\d+)?S)?)?$"
)


def _check_timespan(v: str, field: str) -> str:
    if not TIMESPAN_RE.match(v):
        raise HTTPException(422, detail=f"{field}: 决断时距须为 ISO 8601 duration（如 PT8H/P1D），得到 {v!r}")
    return v


def _422(err: LookupError) -> HTTPException:
    return HTTPException(422, detail=str(err))


# ---------------------------------------------------------------- closures

class AccountabilityIn(BaseModel):
    """R-GOV-03：具名责任人。responsible_person 必须是 Person——责任守恒律。"""
    responsible_person_id: str
    role: str = Field(min_length=1, description="责任范围/角色（→ AccountabilityLink.responsibility_scope）")


class ClosureIn(BaseModel):
    """六元组登记入参（字段名 = LinkML 槽位名）。

    intent/capability/accountability 为创建即必需；context/action/evidence 三分量
    允许空（ClosureState=DRAFT='六元组登记中'），一经提供即校验存在性。
    """
    intent_id: str
    capability_id: str
    accountability: AccountabilityIn  # 缺失 → pydantic 422（R-GOV-03 API 层）
    state: ClosureState
    decision_timespan: str
    name: Optional[str] = None
    context_asset_id: Optional[str] = None
    action_type_ids: list[str] = Field(default_factory=list)
    evidence_ids: list[str] = Field(default_factory=list)
    autonomy_level: Optional[AutonomyLevel] = None
    authorization_ref: Optional[str] = None
    trust_level: Optional[TrustLevel] = None
    data_class: Optional[str] = None
    boundary: Optional[str] = None


@router.post("/closures", status_code=201)
def create_closure(body: ClosureIn):
    _check_timespan(body.decision_timespan, "decision_timespan")
    try:
        with get_conn() as conn:
            must_exist(conn, "Intent", body.intent_id, "intent_id")
            must_exist(conn, "CapabilityEntity", body.capability_id, "capability_id")
            must_exist(conn, "Person", body.accountability.responsible_person_id,
                       "accountability.responsible_person_id")
            must_exist(conn, "ContextAsset", body.context_asset_id, "context_asset_id")
            for x in body.action_type_ids:
                must_exist(conn, "ActionType", x, "action_type_ids[]")
            for x in body.evidence_ids:
                must_exist(conn, "EvidenceEntity", x, "evidence_ids[]")

            cu_id = next_id(conn, "ClosureUnit")
            alk_id = next_id(conn, "AccountabilityLink")

            # 环插法：ALK 与 CU 互指（两条延迟 FK 在 COMMIT 统一校验），
            # accountability_id NOT NULL 在 CU 插入时即时强制（R-GOV-03 DB 层）。
            conn.execute(
                'INSERT INTO "AccountabilityLink" '
                '(id, created_at, closure, responsible_person, responsibility_scope, assumed_at) '
                'VALUES (%s, now(), %s, %s, %s, now())',
                (alk_id, cu_id, body.accountability.responsible_person_id, body.accountability.role),
            )
            conn.execute(
                'INSERT INTO "ClosureUnit" '
                '(id, name, created_at, capability, state, decision_timespan, autonomy_level, '
                ' authorization_ref, intent_id, accountability_id, trust_level, data_class, boundary) '
                'VALUES (%s, %s, now(), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)',
                (cu_id, body.name, body.capability_id, body.state, body.decision_timespan,
                 body.autonomy_level, body.authorization_ref, body.intent_id, alk_id,
                 body.trust_level, body.data_class, body.boundary),
            )
            if body.context_asset_id:
                conn.execute('UPDATE "ContextAsset" SET "ClosureUnit_id" = %s WHERE id = %s',
                             (cu_id, body.context_asset_id))
            for x in body.action_type_ids:
                conn.execute('UPDATE "ActionType" SET "ClosureUnit_id" = %s WHERE id = %s', (cu_id, x))
            for x in body.evidence_ids:
                conn.execute('UPDATE "EvidenceEntity" SET "ClosureUnit_id" = %s WHERE id = %s', (cu_id, x))
            return {"id": cu_id, "accountability_link_id": alk_id, "state": body.state}
    except LookupError as e:
        raise _422(e) from e


def _load_closure(conn, cu_id: str) -> Optional[dict]:
    cu = conn.execute(
        'SELECT cu.*, '
        '       al.responsible_person AS accountability_responsible_person_id, '
        '       al.responsibility_scope AS accountability_role, '
        '       p.full_name AS accountability_responsible_person_name '
        'FROM "ClosureUnit" cu '
        'JOIN "AccountabilityLink" al ON al.id = cu.accountability_id '
        'LEFT JOIN "Person" p ON p.id = al.responsible_person '
        'WHERE cu.id = %s',
        (cu_id,),
    ).fetchone()
    if cu is None:
        return None
    cu["context_asset_ids"] = [r["id"] for r in conn.execute(
        'SELECT id FROM "ContextAsset" WHERE "ClosureUnit_id" = %s ORDER BY id', (cu_id,))]
    cu["action_type_ids"] = [r["id"] for r in conn.execute(
        'SELECT id FROM "ActionType" WHERE "ClosureUnit_id" = %s ORDER BY id', (cu_id,))]
    cu["evidence_ids"] = [r["id"] for r in conn.execute(
        'SELECT id FROM "EvidenceEntity" WHERE "ClosureUnit_id" = %s ORDER BY id', (cu_id,))]
    return cu


@router.get("/closures/{cu_id}")
def get_closure(cu_id: str):
    with get_conn() as conn:
        cu = _load_closure(conn, cu_id)
    if cu is None:
        raise HTTPException(404, detail=f"ClosureUnit 不存在: {cu_id}")
    return cu


@router.get("/closures")
def list_closures(state: Optional[ClosureState] = None, limit: int = Query(100, ge=1, le=1000)):
    with get_conn() as conn:
        if state:
            rows = conn.execute(
                'SELECT id, name, state, intent_id, capability, decision_timespan, created_at '
                'FROM "ClosureUnit" WHERE state = %s ORDER BY id LIMIT %s', (state, limit)).fetchall()
        else:
            rows = conn.execute(
                'SELECT id, name, state, intent_id, capability, decision_timespan, created_at '
                'FROM "ClosureUnit" ORDER BY id LIMIT %s', (limit,)).fetchall()
    return {"items": rows, "count": len(rows)}


# ---------------------------------------------------------------- decisions (S5 队列)

class DecisionOptionIn(BaseModel):
    label: str = Field(min_length=1, description="→ DecisionOption.option_label")
    tradeoff: Optional[str] = None


class DecisionIn(BaseModel):
    """R-GOV-04 固定结构 + addressee。任一必填字段缺失 → pydantic 422。

    说明：任务书称"七字段"而清单列六项（R-GOV-04 原文亦为六元结构：
    对象/证据/选项/推荐/期限/批准后果）；第 7 项 = addressee（卡片发给谁），
    为 R-SEC-04 错人防护所必需，v0 一并强制。
    """
    object: str = Field(min_length=1, description="→ S5DecisionCard.decision_object")
    evidence: list[str] = Field(description="→ S5DecisionCard_evidence_refs（EvidenceEntity id）")
    options: list[DecisionOptionIn] = Field(min_length=1, description="→ DecisionOption 行")
    recommendation: str = Field(min_length=1)
    deadline: datetime
    consequences: str = Field(min_length=1, description="→ S5DecisionCard.approval_consequences")
    addressee: str = Field(min_length=1, description="裁决人（S5）；resolve 时凭此校验 X-S5-Person")


@router.post("/decisions", status_code=201)
def create_decision(body: DecisionIn):
    try:
        with get_conn() as conn:
            for x in body.evidence:
                must_exist(conn, "EvidenceEntity", x, "evidence[]")
            must_exist(conn, "Person", body.addressee, "addressee")

            card_id = next_id(conn, "S5DecisionCard")
            conn.execute(
                'INSERT INTO "S5DecisionCard" '
                '(id, created_at, decision_object, recommendation, deadline, approval_consequences) '
                'VALUES (%s, now(), %s, %s, %s, %s)',
                (card_id, body.object, body.recommendation, body.deadline, body.consequences),
            )
            for opt in body.options:
                conn.execute(
                    'INSERT INTO "DecisionOption" (id, option_label, tradeoff, "S5DecisionCard_id") '
                    "VALUES (%s, %s, %s, %s)",
                    (next_int_id(conn, "DecisionOption"), opt.label, opt.tradeoff, card_id),
                )
            for ev in dict.fromkeys(body.evidence):  # 去重保序（复合主键不允许重复对）
                conn.execute(
                    'INSERT INTO "S5DecisionCard_evidence_refs" ("S5DecisionCard_id", evidence_refs) '
                    "VALUES (%s, %s)", (card_id, ev),
                )
            conn.execute(
                "INSERT INTO cp_decision_addressee (card_id, addressee) VALUES (%s, %s)",
                (card_id, body.addressee),
            )
            return {"id": card_id, "state": "pending", "addressee": body.addressee}
    except LookupError as e:
        raise _422(e) from e


def _load_decision(conn, card_id: str) -> Optional[dict]:
    card = conn.execute(
        'SELECT d.*, a.addressee, p.full_name AS addressee_name, '
        "       (d.decided_by IS NULL) AS pending "
        'FROM "S5DecisionCard" d '
        "JOIN cp_decision_addressee a ON a.card_id = d.id "
        "LEFT JOIN \"Person\" p ON p.id = a.addressee "
        "WHERE d.id = %s", (card_id,)).fetchone()
    if card is None:
        return None
    card["evidence"] = [r["evidence_refs"] for r in conn.execute(
        'SELECT evidence_refs FROM "S5DecisionCard_evidence_refs" '
        'WHERE "S5DecisionCard_id" = %s ORDER BY evidence_refs', (card_id,))]
    card["options"] = conn.execute(
        'SELECT option_label AS label, tradeoff FROM "DecisionOption" '
        'WHERE "S5DecisionCard_id" = %s ORDER BY id', (card_id,)).fetchall()
    card["pending"] = bool(card.pop("pending"))
    return card


@router.get("/decisions/queue")
def decision_queue():
    """pending 列表（R-GOV-07：S5 不可用时队列积压可见，安全默认模式输入）。"""
    with get_conn() as conn:
        rows = conn.execute(
            'SELECT d.id, d.decision_object AS object, d.recommendation, d.deadline, '
            "       a.addressee, p.full_name AS addressee_name "
            'FROM "S5DecisionCard" d '
            "JOIN cp_decision_addressee a ON a.card_id = d.id "
            "LEFT JOIN \"Person\" p ON p.id = a.addressee "
            "WHERE d.decided_by IS NULL ORDER BY d.deadline, d.id").fetchall()
    return {"items": rows, "count": len(rows)}


@router.get("/decisions/{card_id}")
def get_decision(card_id: str):
    with get_conn() as conn:
        card = _load_decision(conn, card_id)
    if card is None:
        raise HTTPException(404, detail=f"S5DecisionCard 不存在: {card_id}")
    return card


class ResolveIn(BaseModel):
    decision: Literal["approved", "rejected"]
    decided_by: str = Field(min_length=1, description="裁决人 Person id，须与 X-S5-Person 一致")


@router.post("/decisions/{card_id}/resolve")
def resolve_decision(card_id: str, body: ResolveIn,
                     x_s5_person: Optional[str] = Header(default=None, alias="X-S5-Person")):
    # R-SEC-04 代签防护（M1 最小形态）：请求者身份仅凭头声明，且必须等于卡片 addressee。
    if not x_s5_person:
        raise HTTPException(403, detail="缺少 X-S5-Person 头（R-SEC-04：签发不可代）")
    if body.decided_by != x_s5_person:
        raise HTTPException(403, detail="decided_by 与 X-S5-Person 不一致（R-SEC-04 代签防护）")
    try:
        with get_conn() as conn:
            must_exist(conn, "Person", body.decided_by, "decided_by")
            card = conn.execute(
                'SELECT decided_by, decided_at FROM "S5DecisionCard" WHERE id = %s',
                (card_id,)).fetchone()
            if card is None:
                raise HTTPException(404, detail=f"S5DecisionCard 不存在: {card_id}")
            addr = conn.execute(
                "SELECT addressee FROM cp_decision_addressee WHERE card_id = %s",
                (card_id,)).fetchone()
            if addr is None:
                raise HTTPException(409, detail="卡片未登记 addressee，无法按 R-SEC-04 校验")
            if x_s5_person != addr["addressee"]:
                raise HTTPException(
                    403, detail=f"X-S5-Person={x_s5_person!r} 不是该卡片的 addressee"
                                f"（{addr['addressee']!r}），拒绝代签")
            if card["decided_by"] is not None:
                raise HTTPException(409, detail=f"卡片已于 {card['decided_at']} 由 "
                                                f"{card['decided_by']} 裁决，不可重复 resolve")
            conn.execute(
                'UPDATE "S5DecisionCard" SET decided_by = %s, decided_at = now() WHERE id = %s',
                (body.decided_by, card_id))
            return {"id": card_id, "state": "resolved", "decision": body.decision,
                    "decided_by": body.decided_by}
    except LookupError as e:
        raise _422(e) from e


# ---------------------------------------------------------------- authorizations

class BudgetIn(BaseModel):
    currency: str = Field(min_length=1)
    amount_cap: float = Field(ge=0, description="闭环级预算上限（R-POOL-BUDGET）")
    period: Literal["per-run", "daily", "monthly"]


class AuthorizationIn(BaseModel):
    """R-POL-02：scope/budget/decision_timespan 三要素强制在位。"""
    scope: list[str] = Field(min_length=1, description="→ Authorization_scope 行")
    budget: BudgetIn
    decision_timespan: str
    granted_by: str = Field(min_length=1, description="授权人（具名的人，Person id）")
    name: Optional[str] = None
    autonomy_level: Optional[AutonomyLevel] = None
    granted_executor: Optional[str] = Field(default=None,
                                            description="被授权执行体（CapabilityEntity id）")
    valid_from: Optional[datetime] = None
    valid_until: Optional[datetime] = None
    trust_level: Optional[TrustLevel] = None
    data_class: Optional[str] = None
    boundary: Optional[str] = None


@router.post("/authorizations", status_code=201)
def create_authorization(body: AuthorizationIn):
    _check_timespan(body.decision_timespan, "decision_timespan")
    try:
        with get_conn() as conn:
            must_exist(conn, "Person", body.granted_by, "granted_by")
            must_exist(conn, "CapabilityEntity", body.granted_executor, "granted_executor")
            budget_id = next_int_id(conn, "Budget")
            conn.execute(
                'INSERT INTO "Budget" (id, currency, amount_cap, period) VALUES (%s, %s, %s, %s)',
                (budget_id, body.budget.currency, body.budget.amount_cap, body.budget.period))
            aut_id = next_id(conn, "Authorization")
            conn.execute(
                'INSERT INTO "Authorization" '
                '(id, name, created_at, decision_timespan, autonomy_level, granted_executor, '
                ' granted_by, valid_from, valid_until, trust_level, data_class, boundary, budget_id) '
                'VALUES (%s, %s, now(), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)',
                (aut_id, body.name, body.decision_timespan, body.autonomy_level,
                 body.granted_executor, body.granted_by, body.valid_from, body.valid_until,
                 body.trust_level, body.data_class, body.boundary, budget_id))
            for s in dict.fromkeys(body.scope):
                conn.execute(
                    'INSERT INTO "Authorization_scope" ("Authorization_id", scope) VALUES (%s, %s)',
                    (aut_id, s))
            return {"id": aut_id, "budget_id": budget_id, "scope": body.scope,
                    "decision_timespan": body.decision_timespan}
    except LookupError as e:
        raise _422(e) from e


def _load_authorization(conn, aut_id: str) -> Optional[dict]:
    row = conn.execute(
        'SELECT a.*, b.currency AS budget_currency, b.amount_cap AS budget_amount_cap, '
        "       b.period AS budget_period "
        'FROM "Authorization" a LEFT JOIN "Budget" b ON b.id = a.budget_id '
        "WHERE a.id = %s", (aut_id,)).fetchone()
    if row is None:
        return None
    row["scope"] = [r["scope"] for r in conn.execute(
        'SELECT scope FROM "Authorization_scope" WHERE "Authorization_id" = %s ORDER BY scope',
        (aut_id,))]
    row["budget"] = ({k: row.pop(f"budget_{k}") for k in ("currency", "amount_cap", "period")}
                     if row["budget_currency"] is not None else None)
    return row


@router.get("/authorizations")
def list_authorizations(limit: int = Query(100, ge=1, le=1000)):
    with get_conn() as conn:
        ids = [r["id"] for r in conn.execute(
            'SELECT id FROM "Authorization" ORDER BY id LIMIT %s', (limit,))]
        items = [_load_authorization(conn, i) for i in ids]
    return {"items": items, "count": len(items)}


@router.get("/authorizations/{aut_id}")
def get_authorization(aut_id: str):
    with get_conn() as conn:
        row = _load_authorization(conn, aut_id)
    if row is None:
        raise HTTPException(404, detail=f"Authorization 不存在: {aut_id}")
    return row
