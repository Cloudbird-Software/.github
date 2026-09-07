#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
negtest_m0.py — M0 验收负面测试（DGA-INFRA 第 7 章：测坏情况，不测正常流程）

锚点：
  案例0（阳性对照） 完整六元组 ClosureUnit 必须 PASS
  案例1（R-GOV-03） 缺 accountability 的 ClosureUnit 必须 FAIL
  案例2（诚实边界） trust_label=T0 的 PoolAccount 承接 sensitivity=客户敏感 路由判定：
                    纯 JSON Schema 无法表达跨对象不等式谓词（sensitivity ≤ trust）——
                    该谓词属 OPA 层；schema 只保证两端字段在位且各自合法（必须 PASS），
                    拒绝动作由 OPA 策略完成（R-POOL-DATA/R-POOL-TRUST，M4 验收）。
  案例3（枚举封闭） trust_label=T9（枚举外值）必须 FAIL

运行：
  D:/Projects/dga-infra/.venv/Scripts/python.exe controls/negtest_m0.py
退出码：0 = 全部案例行为符合预期；1 = 有案例行为不符（治理缺陷）。
"""
import json
import sys
from pathlib import Path

import jsonschema
from jsonschema import Draft202012Validator

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "schemas" / "generated" / "dga-ontology.schema.json"

SCHEMA = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def validator_for(cls: str) -> Draft202012Validator:
    """构造针对单个类定义的校验器（closed world，$defs 同源）。"""
    return Draft202012Validator(
        {"$ref": f"#/$defs/{cls}", "$defs": SCHEMA["$defs"]}
    )


def validate(cls: str, instance: dict):
    errs = sorted(
        validator_for(cls).iter_errors(instance),
        key=lambda e: list(e.absolute_path),
    )
    return errs


VALID_ACCOUNTABILITY = {
    "id": "ALK-0001",
    "closure": "CU-0001",
    "responsible_person": "PSN-0001",
    "responsibility_scope": "对修复质量、证据完整性与升级路径应答",
    "assumed_at": "2026-09-06T12:00:00Z",
}

CLOSURE_BASE = {
    "id": "CU-0001",
    "name": "示例闭环：客户反馈修复",
    "created_at": "2026-09-06T12:00:00Z",
    "state": "REGISTERED",
    "decision_timespan": "P7D",
    "autonomy_level": "L2",
    "intent": {
        "id": "INT-0001",
        "name": "修复客户反馈",
        "statement": "48h 内完成修复并通过验收判定",
    },
    "trust_level": "T1",
    "data_class": "D_INTERNAL",
    "boundary": "company-cloud",
}

results = []


def record(case: str, expect: str, ok: bool, detail: str) -> None:
    results.append((case, expect, ok, detail))
    mark = "PASS" if ok else "FAIL"
    print(f"[{mark}] {case}（预期：{expect}）")
    print(f"       {detail}")


# ── 案例0：阳性对照——六元组齐备的闭环必须通过 ─────────────────────────────
closure_full = {**CLOSURE_BASE, "accountability": VALID_ACCOUNTABILITY}
errs = validate("ClosureUnit", closure_full)
record(
    "案例0 阳性对照：六元组齐备的 ClosureUnit",
    "通过",
    not errs,
    "0 个错误" if not errs else f"意外错误：{errs[0].message}",
)

# ── 案例1：缺 accountability 的 ClosureUnit 必须失败（R-GOV-03）────────────
errs = validate("ClosureUnit", dict(CLOSURE_BASE))  # 无 accountability 键
hit = [e for e in errs if "accountability" in (e.message or "")]
record(
    "案例1 缺 accountability 的 ClosureUnit（R-GOV-03）",
    "校验失败",
    bool(errs) and bool(hit),
    (
        f"拒绝理由：{hit[0].message}"
        if hit
        else (f"失败但未命中 accountability 必填约束：{errs[0].message}" if errs else "意外通过——治理缺陷！")
    ),
)

# ── 案例2：诚实边界——schema 只保证字段在位，路由谓词属 OPA 层 ──────────────
pool_account = {
    "id": "ACC-0001",
    "name": "某供应商免费层账号",
    "created_at": "2026-09-06T12:00:00Z",
    "provider": "PRV-0001",
    "credential_ref": "openbao://secret/pool/acc-0001",
    "cost_tier": "FREE",
    "trust_label": "T0",
    "tos_risk": "GREY_ZONE",
    "boundary": "company-cloud",
}
endpoint = {
    "id": "EPL-0001",
    "name": "free-workhorse",
    "endpoint_name": "free-workhorse",
    "trust_level": "T0",
    "bound_accounts": ["ACC-0001"],
    "boundary": "company-cloud",
}
routing_policy = {
    "id": "RTP-0001",
    "name": "客户敏感任务路由（声明侧）",
    "created_at": "2026-09-06T12:00:00Z",
    "max_data_sensitivity": "S2_CUSTOMER_SENSITIVE",
    "min_trust_level": "T1",
    "fallback_chain": ["EPL-0002", "EPL-0003"],
    "virtual_key_isolated": True,
    "boundary": "company-cloud",
}
case2_errs = []
for cls, inst in [
    ("PoolAccount", pool_account),
    ("LogicalEndpoint", endpoint),
    ("RoutingPolicy", routing_policy),
]:
    case2_errs += [(cls, e) for e in validate(cls, inst)]
print(
    "       诚实边界声明：任务 sensitivity(S2_客户敏感) ≤ 端点 trust(T0) 的不等式"
)
print(
    "       是跨对象谓词，JSON Schema（单实例结构校验）无法表达其拒绝；"
    "schema 保证"
)
print(
    "       trust_label / max_data_sensitivity / trust_level 字段在位且取值合法，"
    "拒绝动作"
)
print(
    "       由 OPA 策略强制（policies/routing.rego，M4 验收：越权路由被真实拒绝）。"
)
record(
    "案例2 T0 账号 × 客户敏感路由：字段在位校验（诚实边界）",
    "通过（字段在位）+ 登记 OPA 边界",
    not case2_errs,
    "三个对象全部通过 schema 校验（0 个错误）——证明字段在位；"
    "不等式谓词登记为 OPA 层职责"
    if not case2_errs
    else f"意外错误：{case2_errs[0][1].message}",
)

# ── 案例3：枚举外值 trust_label=T9 必须失败 ────────────────────────────────
bad_account = {**pool_account, "id": "ACC-9999", "trust_label": "T9"}
errs = validate("PoolAccount", bad_account)
hit = [e for e in errs if any("trust_label" in str(p) for p in e.absolute_path)]
record(
    "案例3 trust_label=T9（枚举外值）",
    "校验失败",
    bool(errs) and bool(hit),
    (
        f"拒绝理由（path={list(hit[0].absolute_path)}）：{hit[0].message}"
        if hit
        else (f"失败但未命中 trust_label：{errs[0].message}" if errs else "意外通过——治理缺陷！")
    ),
)

# ── 汇总 ──────────────────────────────────────────────────────────────────
all_ok = all(ok for _, _, ok, _ in results)
print()
from importlib.metadata import version as _pkg_version
print(f"jsonschema 版本：{_pkg_version('jsonschema')}")
print(f"schema 文件：{SCHEMA_PATH}")
print(f"结论：{'全部案例行为符合预期 —— M0 负面测试通过' if all_ok else '存在行为不符案例 —— 阻塞'}")
sys.exit(0 if all_ok else 1)
