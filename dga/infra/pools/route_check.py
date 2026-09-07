#!/usr/bin/env python
# route_check.py — DGA-INFRA 池路由器 v0（M2 资源池 v0）
#
# 登记定位：本脚本是**未来 MCP 网关 Action Registry 的路由入口**——MCP 网关在放行任何
#   模型调用类 Action 前，先经此处取得端点裁决（routed→端点 / denied→结构化原因 /
#   queued→按 3.5 降级链终点挂起）。v0 以 CLI 形态先行，接口签名即未来网关内部 API。
#
# 规范依据：DGA-INFRA-v1.0 3.1（账本权威源=控制面 DB）、3.2（R-POOL-TRUST：sensitivity ≤
#   trust，谓词强制在 OPA 层）、3.3（R-POOL-DATA 硬红线）、3.4（R-POOL-COMPLIANCE 灰区）、
#   3.5（R-POOL-DEGRADE：全败→队列/挂起，T0 不作客户链路降级终点）、R-POL-05（判定入证据流）。
#
# 数据面：候选端点查 dga_control 池表（psql 子进程，零额外依赖）；策略判定逐个 POST
#   OPA /v1/data/dga/pool/allow（deny 时取 /deny_reasons）。tos_risk 按端点绑定账号集合
#   聚合（任一 grey-zone/high-risk ⇒ 端点按灰区处理，3.4）。
#
# 用法：
#   python route_check.py --task-id T-0001 --sensitivity internal
#   python route_check.py --task-id T-0002 --sensitivity customer_sensitive
#   python route_check.py --task-id T-0003 --sensitivity public
#   python route_check.py --task-id T-0004 --sensitivity internal --mark-unhealthy gray-probe
#       （--mark-unhealthy 仅本进程内存生效，不写账本——用于演示 3.5 全败→queued）
#
# 裁决语义（结构化输出 decision 字段）：
#   routed — 首个 OPA allow 的端点（候选序：trust 升级序 → 成本层级升序，即"满足策略的
#            最便宜可信端点优先"）；
#   denied — 所有候选均被 OPA 策略拒绝（红线/合规拒绝不排队：排队不改变策略判定，
#            输出合并 deny_reasons，R-EVID-01 POLICY_DECISION 原料）；
#   queued — 存在策略上可承接近似任务的健康候选但当前全部不可用（health.available=false
#            或账本无候选）→ 按 3.5 队列等待，超决断时距挂起（MET-01，v0 仅返回状态）。
#   （任务书"全败返回 queued"在实现上细化：策略性全败=denied，可用性全败=queued——
#    把红线拒绝混入队列会诱导重试绕过，故区分；此细化已在 pools/README.md 登记。）
#
# 全 mock 纪律：本脚本不携带任何 API key，不直连任何上游；凭据仅在 OpenBao 引用中存在。

import argparse
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error

DEFAULT_DB = "dga_control"
DEFAULT_PSQL = r"D:\Projects\dga-infra\services\postgres\pgsql\bin\psql.exe"
DEFAULT_OPA = "http://127.0.0.1:8181"

# 候选排序键（3.1：按信任/成本路由；满足策略前提下最便宜优先）
_TRUST_ORDER = "CASE e.trust_label WHEN 'T0' THEN 0 WHEN 'T1' THEN 1 ELSE 2 END"
_COST_ORDER = ("CASE a.cost_tier WHEN 'free' THEN 0 WHEN 'low-paid' THEN 1 "
               "WHEN 'high-paid' THEN 2 ELSE 3 END")

_CANDIDATE_SQL = f"""
SELECT e.endpoint_name,
       e.trust_label,
       COALESCE(rp.id, '')                AS routing_policy_id,
       COALESCE(bool_or(a.tos_risk IN ('grey-zone','high-risk')), false) AS tos_gray,
       bool_and(COALESCE((a.health->>'available')::boolean, true))       AS accounts_available
FROM pool_endpoints e
LEFT JOIN pool_accounts a ON a.id = ANY (e.bound_account_ids) AND a.retired_at IS NULL
LEFT JOIN pool_routing_policies rp ON rp.id = e.routing_policy_id
WHERE e.retired_at IS NULL
GROUP BY e.endpoint_name, e.trust_label, rp.id
ORDER BY {_TRUST_ORDER}, min({_COST_ORDER}), e.endpoint_name;
"""


def fetch_candidates(db: str):
    """查池表候选端点（psql 子进程，管道分隔，避免额外 Python 依赖）。"""
    psql = DEFAULT_PSQL if os.path.exists(DEFAULT_PSQL) else "psql"
    out = subprocess.run(
        [psql, "-U", "dga", "-h", "localhost", "-d", db, "-A", "-F", "|", "-t", "-v", "ON_ERROR_STOP=1",
         "-c", _CANDIDATE_SQL],
        capture_output=True, text=True, encoding="utf-8",
    )
    if out.returncode != 0:
        raise RuntimeError(f"psql failed: {out.stderr.strip()}")
    rows = []
    for line in out.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        name, trust, policy, gray, avail = line.split("|")
        rows.append({
            "endpoint_name": name,
            "trust_label": trust,
            "routing_policy_id": policy or None,
            "tos_risk": "grey-zone" if gray == "t" else "clear",
            "accounts_available": avail != "f",
        })
    return rows


def opa_query(opa: str, rule: str, payload: dict):
    url = f"{opa}/v1/data/dga/pool/{rule}"
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8")).get("result")


def route(task_id: str, sensitivity: str, db: str, opa: str, unhealthy=None):
    result = {
        "task_id": task_id,
        "sensitivity": sensitivity,
        "decision": None,          # routed | denied | queued
        "endpoint": None,
        "trust_label": None,
        "routing_policy_id": None,
        "credential_ref": None,    # v0 不在此取引用（网关层凭据注入职责，R-SEC-02）
        "evaluated": [],
        "reasons": [],
        "policy": "dga.pool/pool-routing.rego (R-POOL-TRUST/DATA/COMPLIANCE)",
    }
    try:
        candidates = fetch_candidates(db)
    except RuntimeError as exc:
        result["decision"] = "queued"
        result["reasons"] = [f"POOL-LEDGER-UNREACHABLE: {exc}"]
        return result

    if unhealthy:
        unhealthy = set(unhealthy)

    saw_policy_deny = False
    for cand in candidates:
        if unhealthy and cand["endpoint_name"] in unhealthy:
            cand["accounts_available"] = False
        entry = {"endpoint": cand["endpoint_name"], "trust_label": cand["trust_label"]}
        if not cand["accounts_available"]:
            # 可用性失败 → 降级链语义：跳过该候选（3.5 故障转移）；不产生策略原因
            entry.update({"allow": None, "skipped": "account-unavailable (3.5 degrade)"})
            result["evaluated"].append(entry)
            continue
        payload = {"input": {"task": {"task_id": task_id, "sensitivity": sensitivity},
                             "endpoint": {"endpoint_name": cand["endpoint_name"],
                                          "trust_label": cand["trust_label"],
                                          "tos_risk": cand["tos_risk"]}}}
        allow = bool(opa_query(opa, "allow", payload))
        if allow:
            entry["allow"] = True
            result["evaluated"].append(entry)
            result["decision"] = "routed"
            result["endpoint"] = cand["endpoint_name"]
            result["trust_label"] = cand["trust_label"]
            result["routing_policy_id"] = cand["routing_policy_id"]
            return result
        reasons = sorted(opa_query(opa, "deny_reasons", payload) or [])
        entry.update({"allow": False, "reasons": reasons})
        result["evaluated"].append(entry)
        result["reasons"] = sorted(set(result["reasons"]) | set(reasons))
        saw_policy_deny = saw_policy_deny or bool(reasons)

    # 全败：策略性全败=denied（红线不排队）；可用性全败/无候选=queued（3.5 → MET-01 挂起）
    result["decision"] = "denied" if saw_policy_deny else "queued"
    if result["decision"] == "queued":
        result["reasons"] = result["reasons"] or [
            "R-POOL-DEGRADE: no policy-allowed healthy endpoint; queue/wait, "
            "suspend on decision-timespan expiry (MET-01); escalate S5"]
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description="DGA-INFRA pool router v0 (future MCP Action Registry entry)")
    ap.add_argument("--task-id", required=True)
    ap.add_argument("--sensitivity", required=True,
                    choices=["public", "internal", "customer_sensitive"])
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--opa", default=DEFAULT_OPA)
    ap.add_argument("--mark-unhealthy", action="append", default=None,
                    help="runtime-only health override (demo of 3.5 queued path); not written to ledger")
    ap.add_argument("--json", action="store_true", default=True)
    args = ap.parse_args()
    result = route(args.task_id, args.sensitivity, args.db, args.opa, args.mark_unhealthy)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["decision"] == "routed" else 2


if __name__ == "__main__":
    sys.exit(main())
