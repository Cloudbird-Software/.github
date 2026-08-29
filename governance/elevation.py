#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""elevation.py —— JIT 提权 v0 裁决/收回引擎（IR-0006 W2-C4 / BEH-05 / 卡 #415）

/elevate 评论 → 本表裁决（governance/policy/elevation.yaml，默认拒绝）→
批准/拒绝记录按 schema v1 落 elevation-ledger（governance/elevation/
shadow-evidence.jsonl，kind=approval，evidence-query 第 4 源——subject.card
可查询，AC-9c）；TTL 到期 sweep 收回（AC-9d：sweep 后零"过期未收回"grant=
无长期驻留提权断言，open-check 机器锚点）。

评论格式（单行命令 + kv 参数，乱序允许）：

    /elevate capability=org-variable-write ttl=30 reason=复位熔断前的根因排查 spec=specs/IR-0006/spec.md#AC-9

- capability=NAME（词法 token）；ttl=分钟数（可缺省→policy defaults）；
  spec=<引用>（词法 token）；reason=自由文本（到下一个 " key=" 或行尾）。
- HO 场景 3：reason 或 spec 缺失 → deny（policy request.required 执法）。

子命令：
  parse      --comment-file F --card owner/repo#n --requester L --delivery-id ID
             → stdout 请求 JSON（capability/ttl/reason/spec_ref/delivery_id...）
  adjudicate --request-file F --role R [--policy P] [--now ISO]
             → stdout 裁决 JSON（verdict=grant|deny + reason/effective_ttl/expires_at）
  sweep      --ledger-dir D [--policy P] [--now ISO]
             → stdout 到期未收回 grant 列表 JSON（供 workflow 补 revoke 事件）
  open-check --ledger-dir D [--now ISO]
             → 无过期未收回 grant 断言（exit 0=通过 / 3=有驻留——sweep 后必须 0）

退出码：0=成功 | 2=参数/环境/策略非法（fail-closed——裁决输入不可信不判）
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

DEFAULT_POLICY = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "policy", "elevation.yaml")
CAP_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def now_iso(now_arg):
    if now_arg:
        try:
            return datetime.datetime.strptime(now_arg, "%Y-%m-%dT%H:%M:%SZ") \
                .replace(tzinfo=datetime.timezone.utc)
        except ValueError:
            die(2, f"--now 非法 ISO8601Z: {now_arg!r}")
    return datetime.datetime.now(datetime.timezone.utc)


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_comment(body: str, card: str, requester: str, delivery_id: str) -> dict:
    """提取 /elevate 命令与 kv 参数（首行；reason 为到下一 kv token 或行尾的自由文本）。"""
    first = (body or "").splitlines()[0].strip() if body else ""
    tokens = first.split()
    if not tokens or tokens[0] != "/elevate":
        die(2, "首 token 非 /elevate（调用方应先过滤）")
    rest = " ".join(tokens[1:])
    # kv token 定界：前有空白且 key ∈ {capability, ttl, spec, reason}
    kv_re = re.compile(r"(?:^|\s)(capability|ttl|spec|reason)\s*=\s*", re.IGNORECASE)
    req = {"kind": "elevate", "card": card, "requester": requester,
           "delivery_id": delivery_id}
    for m in kv_re.finditer(rest):
        key = m.group(1).lower()
        start = m.end()
        nxt = kv_re.search(rest, start)
        val = rest[start:nxt.start() if nxt else len(rest)].strip()
        if key == "ttl":
            if not re.match(r"^[0-9]+$", val):
                die(2, f"ttl 非法（须为正整数分钟）: {val!r}")
            req["ttl"] = int(val)
        elif key == "spec":  # 评论用 spec=，请求 JSON 规范化为 spec_ref
            req["spec_ref"] = val
        else:
            req[key] = val
    if "capability" in req and not CAP_RE.match(req["capability"]):
        die(2, f"capability 非法: {req['capability']!r}")
    return req


def load_policy(path: str) -> dict:
    if yaml is None:
        die(2, "缺 PyYAML——策略表无法加载（fail-closed）")
    try:
        pol = yaml.safe_load(open(path, encoding="utf-8"))
    except (OSError, yaml.YAMLError) as e:
        die(2, f"策略表加载失败: {e}")
    caps = pol.get("capabilities") or {}
    d = pol.get("defaults") or {}
    req = pol.get("request") or {}
    if not isinstance(caps, dict) or not caps:
        die(2, "策略表缺非空 capabilities")
    if not isinstance(d.get("ttl_minutes"), int) or d["ttl_minutes"] <= 0:
        die(2, "策略表 defaults.ttl_minutes 须为正整数")
    required = req.get("required") or ["reason", "spec_ref"]
    if not isinstance(required, list):
        die(2, "策略表 request.required 须为列表")
    for name, c in caps.items():
        if not CAP_RE.match(name):
            die(2, f"能力名非法: {name!r}")
        if not isinstance(c.get("allowed_roles"), list) or not c["allowed_roles"]:
            die(2, f"capabilities.{name}.allowed_roles 须为非空列表")
        mt = c.get("max_ttl_minutes")
        if not isinstance(mt, int) or mt <= 0:
            die(2, f"capabilities.{name}.max_ttl_minutes 须为正整数")
    return pol


def adjudicate(req: dict, role: str, policy: dict, now: datetime.datetime) -> dict:
    """策略裁决（纯函数）。返回 {verdict: grant|deny, reason, ...}。"""
    caps = policy["capabilities"]
    required = (policy.get("request") or {}).get("required") or ["reason", "spec_ref"]
    out = {"verdict": "deny", "requester": req.get("requester"),
           "card": req.get("card"), "delivery_id": req.get("delivery_id")}
    # HO 场景 3：缺理由/缺 spec 引用必拒（policy request.required 执法）
    for field in required:
        key = "spec_ref" if field == "spec_ref" else field
        if not str(req.get(key) or "").strip():
            out["reason"] = f"missing-{key}（HO 场景 3：{'理由' if key == 'reason' else 'spec 引用'}必附，fail-closed）"
            return out
    cap = req.get("capability")
    if cap not in caps:
        out["reason"] = f"capability 未在策略表声明（默认拒绝）: {cap!r}"
        return out
    c = caps[cap]
    if role not in c["allowed_roles"]:
        out["reason"] = f"role 不匹配（capability={cap} 允许 {c['allowed_roles']}，请求方 role={role!r}）"
        return out
    ttl = req.get("ttl")
    if ttl is None:
        ttl = policy["defaults"]["ttl_minutes"]
    if ttl <= 0 or ttl > c["max_ttl_minutes"]:
        out["reason"] = (f"ttl 越界（capability={cap} 上限 {c['max_ttl_minutes']} 分钟，"
                         f"请求 {ttl}）")
        return out
    expires = now + datetime.timedelta(minutes=ttl)
    out.update({"verdict": "grant", "capability": cap, "reason": "",
                "effective_ttl_minutes": ttl, "granted_at": iso(now),
                "expires_at": iso(expires),
                "elevation_id": "elev-" + iso(now).replace("-", "").replace(":", "")
                .replace("T", "-").replace("Z", "") + "-" + cap,
                "request_reason": req.get("reason"), "spec_ref": req.get("spec_ref")})
    return out


def load_ledger(ledger_dir: str) -> list:
    recs = []
    for f in sorted(glob.glob(os.path.join(ledger_dir, "shadow-evidence*.jsonl"))):
        with open(f, encoding="utf-8") as fh:
            for ln in (l.strip() for l in fh):
                if ln:
                    recs.append(json.loads(ln))
    return recs


def payload_of(rec: dict) -> dict:
    p = rec.get("payload")
    if isinstance(p, str):
        try:
            return json.loads(p)
        except json.JSONDecodeError:
            return {}
    return p if isinstance(p, dict) else {}


def open_grants(ledger_dir: str, now: datetime.datetime) -> list:
    """到期未收回的 grant（action=elevation.grant 且无同 elevation_id 的 revoke）。"""
    revoked = {payload_of(r).get("elevation_id")
               for r in load_ledger(ledger_dir)
               if r.get("action") == "elevation.revoke"}
    out = []
    for r in load_ledger(ledger_dir):
        if r.get("action") != "elevation.grant":
            continue
        p = payload_of(r)
        eid = p.get("elevation_id")
        if eid in revoked:
            continue
        exp = p.get("expires_at")
        if exp and exp < iso(now):  # 字典序即时间序（同 ISO 格式）
            out.append({"elevation_id": eid, "card": (r.get("subject") or {}).get("card"),
                        "capability": p.get("capability"),
                        "requester": (r.get("actor") or {}).get("identity"),
                        "expires_at": exp, "grant_record": r})
    return out


def main():
    ap = argparse.ArgumentParser(prog="elevation.py",
                                 description="JIT 提权 v0 裁决/收回引擎（IR-0006 W2-C4）")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("parse")
    p.add_argument("--comment-file", required=True)
    p.add_argument("--card", required=True)
    p.add_argument("--requester", required=True)
    p.add_argument("--delivery-id", required=True)

    p = sub.add_parser("adjudicate")
    p.add_argument("--request-file", required=True)
    p.add_argument("--role", required=True, help="owner/agent/none（调用方 API 判定）")
    p.add_argument("--policy", default=DEFAULT_POLICY)
    p.add_argument("--now", default=None, help="ISO8601Z（测试注入；缺省=当前）")

    p = sub.add_parser("sweep")
    p.add_argument("--ledger-dir", required=True)
    p.add_argument("--now", default=None)

    p = sub.add_parser("open-check")
    p.add_argument("--ledger-dir", required=True)
    p.add_argument("--now", default=None)

    a = ap.parse_args()
    if a.cmd == "parse":
        with open(a.comment_file, encoding="utf-8") as f:
            body = f.read()
        req = parse_comment(body, a.card, a.requester, a.delivery_id)
        print(json.dumps(req, ensure_ascii=False, sort_keys=True))
    elif a.cmd == "adjudicate":
        with open(a.request_file, encoding="utf-8") as f:
            req = json.load(f)
        pol = load_policy(a.policy)
        v = adjudicate(req, a.role, pol, now_iso(a.now))
        print(json.dumps(v, ensure_ascii=False, sort_keys=True))
    elif a.cmd == "sweep":
        expired = open_grants(a.ledger_dir, now_iso(a.now))
        slim = [{k: g[k] for k in ("elevation_id", "card", "capability",
                                   "requester", "expires_at")} for g in expired]
        print(json.dumps(slim, ensure_ascii=False, sort_keys=True))
    elif a.cmd == "open-check":
        expired = open_grants(a.ledger_dir, now_iso(a.now))
        if expired:
            for g in expired:
                print(f"ELEVATION-STALE {g['elevation_id']} card={g['card']} "
                      f"expired={g['expires_at']}", file=sys.stderr)
            die(3, f"存在 {len(expired)} 条过期未收回 grant——JIT 驻留断言失败（AC-9d）")
        print("OK 零过期未收回 grant（无长期驻留提权断言通过，AC-9d）")


if __name__ == "__main__":
    main()
