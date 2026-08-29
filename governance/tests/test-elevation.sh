#!/usr/bin/env bash
# test-elevation.sh —— JIT 提权 v0 裁决/收回引擎自测（IR-0006 W2-C4 / 卡 #415）
#
# 覆盖（卡 AC 对应）：
#   AC-9c parse（kv 乱序/reason 含空格/ttl 非法拒绝）
#        adjudicate：HO 场景 3 负向（无 reason / 无 spec 必拒）；
#        未知 capability 拒；角色不匹配拒；ttl 超档拒；缺省 ttl+grant 全字段
#   AC-9d sweep（到期未收回列表）+ open-check 断言（过期驻留=exit 3；
#        已 revoke 不再计；未到期不计）
#   策略表加载 fail-closed（缺 capabilities / max_ttl 非法 → exit 2）
# 用法: bash governance/tests/test-elevation.sh（gate.yml 自动纳入）
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ELEV="$DIR/governance/elevation.py"
POLICY="$DIR/governance/policy/elevation.yaml"
NOW="2026-08-29T10:00:00Z"

req() {  # req <file> <comment>
  printf '%s\n' "$2" >"$1"
}

# ---- parse：kv 乱序 + reason 含空格 ----
req "$TMP/c1" "/elevate ttl=30 spec=specs/IR-0006/spec.md#AC-9 capability=org-variable-write reason=复位熔断前的根因排查与处置"
python3 "$ELEV" parse --comment-file "$TMP/c1" --card Cloudbird-Software/.github#415 \
  --requester agent-x --delivery-id node-1 >"$TMP/r1.json" \
  && pass "parse 乱序 kv" || fail "parse 乱序 kv"
python3 - "$TMP/r1.json" <<'PYEOF' && pass "parse 字段断言（reason 含空格完整保留）" || fail "parse 字段断言"
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
assert r["capability"] == "org-variable-write", r
assert r["ttl"] == 30, r
assert r["spec_ref"] == "specs/IR-0006/spec.md#AC-9", r
assert r["reason"] == "复位熔断前的根因排查与处置", r
assert r["delivery_id"] == "node-1" and r["requester"] == "agent-x", r
print("OK")
PYEOF

# ---- parse：ttl 非法 → exit 2（fail-closed） ----
req "$TMP/c2" "/elevate capability=label-write ttl=abc reason=x spec=y"
python3 "$ELEV" parse --comment-file "$TMP/c2" --card a/b#1 --requester t --delivery-id d >/dev/null 2>&1
[[ $? -eq 2 ]] && pass "parse ttl 非法 → exit 2" || fail "parse ttl 非法未拒"

# ---- adjudicate：HO 场景 3 负向（AC-9c 核心） ----
mk() {  # mk <file> <capability> <reason> <spec>
  cat >"$1" <<EOF
{"kind":"elevate","card":"Cloudbird-Software/.github#415","requester":"agent-x",
 "delivery_id":"node-x","capability":"$2","reason":$3,"spec_ref":$4}
EOF
}
mk "$TMP/req-noreason" "org-variable-write" '""' '"specs/IR-0006/spec.md#AC-9"'
python3 "$ELEV" adjudicate --request-file "$TMP/req-noreason" --role agent \
  --policy "$POLICY" --now "$NOW" >"$TMP/v1.json" && pass "无 reason 裁决出结果" || fail "无 reason 裁决失败"
python3 - "$TMP/v1.json" <<'PYEOF' && pass "HO 场景 3：无 reason 必拒（fail-closed）" || fail "HO 场景 3 无 reason 未拒"
import json, sys
v = json.load(open(sys.argv[1], encoding="utf-8"))
assert v["verdict"] == "deny" and "missing-reason" in v["reason"], v
print("OK")
PYEOF

mk "$TMP/req-nospec" "org-variable-write" '"有理由"' '""'
python3 "$ELEV" adjudicate --request-file "$TMP/req-nospec" --role agent \
  --policy "$POLICY" --now "$NOW" >"$TMP/v2.json"
python3 - "$TMP/v2.json" <<'PYEOF' && pass "HO 场景 3：无 spec 引用必拒" || fail "HO 场景 3 无 spec 未拒"
import json, sys
v = json.load(open(sys.argv[1], encoding="utf-8"))
assert v["verdict"] == "deny" and "missing-spec_ref" in v["reason"], v
print("OK")
PYEOF

# ---- adjudicate：未知 capability / 角色不匹配 / ttl 超档 ----
mk "$TMP/req-badcap" "root-shell" '"r"' '"s"'
python3 "$ELEV" adjudicate --request-file "$TMP/req-badcap" --role agent --policy "$POLICY" --now "$NOW" \
  | grep -q '"verdict": "deny"' && pass "未知 capability 拒（默认拒绝）" || fail "未知 capability 未拒"

mk "$TMP/req-role" "org-variable-write" '"r"' '"s"'
python3 "$ELEV" adjudicate --request-file "$TMP/req-role" --role none --policy "$POLICY" --now "$NOW" \
  | grep -q '"verdict": "deny"' && pass "角色不匹配拒（none）" || fail "角色不匹配未拒"

cat >"$TMP/req-ttl" <<'EOF'
{"kind":"elevate","card":"a/b#1","requester":"t","delivery_id":"d",
 "capability":"org-variable-write","reason":"r","spec_ref":"s","ttl":61}
EOF
python3 "$ELEV" adjudicate --request-file "$TMP/req-ttl" --role agent --policy "$POLICY" --now "$NOW" \
  | grep -q '"verdict": "deny"' && pass "ttl 超档拒（org-variable-write 上限 60）" || fail "ttl 超档未拒"

# ---- adjudicate：正向 grant（缺省 ttl 生效 + 全字段 + role=owner） ----
cat >"$TMP/req-ok" <<'EOF'
{"kind":"elevate","card":"Cloudbird-Software/.github#415","requester":"agent-x",
 "delivery_id":"node-ok","capability":"label-write","reason":"状态机补偿写",
 "spec_ref":"specs/IR-0006/spec.md#AC-9"}
EOF
python3 "$ELEV" adjudicate --request-file "$TMP/req-ok" --role agent --policy "$POLICY" --now "$NOW" >"$TMP/vg.json"
python3 - "$TMP/vg.json" <<'PYEOF' && pass "grant 正向（缺省 ttl=240 + expires_at/elevation_id/request_reason）" || fail "grant 正向断言"
import json, sys
v = json.load(open(sys.argv[1], encoding="utf-8"))
assert v["verdict"] == "grant", v
assert v["effective_ttl_minutes"] == 240, v
assert v["expires_at"] == "2026-08-29T14:00:00Z", v
assert v["elevation_id"].startswith("elev-20260829-10"), v
assert v["request_reason"] == "状态机补偿写" and v["spec_ref"].endswith("#AC-9"), v
print("OK")
PYEOF
python3 "$ELEV" adjudicate --request-file "$TMP/req-ok" --role owner --policy "$POLICY" --now "$NOW" \
  | grep -q '"verdict": "grant"' && pass "owner 亦过档" || fail "owner 被误拒"

# ---- 策略表 fail-closed ----
sed 's/^capabilities:/capabilities_broken:/' "$POLICY" >"$TMP/badpol.yaml"
python3 "$ELEV" adjudicate --request-file "$TMP/req-ok" --role agent --policy "$TMP/badpol.yaml" >/dev/null 2>&1
[[ $? -eq 2 ]] && pass "策略缺 capabilities → exit 2（fail-closed）" || fail "策略非法未拒"
sed 's/max_ttl_minutes: 60/max_ttl_minutes: -1/' "$POLICY" >"$TMP/badpol2.yaml"
python3 "$ELEV" adjudicate --request-file "$TMP/req-ok" --role agent --policy "$TMP/badpol2.yaml" >/dev/null 2>&1
[[ $? -eq 2 ]] && pass "max_ttl 非法 → exit 2（fail-closed）" || fail "max_ttl 非法未拒"

# ---- sweep + open-check（AC-9d） ----
LED="$TMP/elev"; mkdir -p "$LED"
# 账本：grant A（过期未收回）、grant B（未到期）、grant C（过期已收回）、非 grant 记录
python3 - "$LED" <<'PYEOF'
import datetime, json, os, sys
led = sys.argv[1]
def rec(action, eid, exp, cap="label-write", card="Cloudbird-Software/.github#415", actor="agent-x"):
    return json.dumps({
        "ts": "2026-08-29T09:00:00Z", "kind": "approval", "action": action,
        "verdict": "pass", "subject": {"card": card, "tenant": "cloudbird-internal"},
        "actor": {"identity": actor, "role": "agent"},
        "payload": json.dumps({"elevation_id": eid, "capability": cap,
                                "expires_at": exp, "request_reason": "r", "spec_ref": "s"}),
        "seq": 0, "prev_hash": None, "hash": "h"}, ensure_ascii=False, sort_keys=True)
rows = [
    rec("elevation.grant", "elev-A", "2026-08-29T09:30:00Z"),
    rec("elevation.grant", "elev-B", "2026-08-29T23:00:00Z"),
    rec("elevation.grant", "elev-C", "2026-08-29T08:00:00Z"),
    rec("elevation.revoke", "elev-C", None),
    rec("elevation.deny", None, None),
]
open(os.path.join(led, "shadow-evidence.jsonl"), "w", encoding="utf-8").write("\n".join(rows) + "\n")
PYEOF
python3 "$ELEV" sweep --ledger-dir "$LED" --now "$NOW" >"$TMP/sw.json"
python3 - "$TMP/sw.json" <<'PYEOF' && pass "sweep：仅过期未收回的 elev-A 入列（B 未到期/C 已收回/deny 不计）" || fail "sweep 列表断言"
import json, sys
rows = json.load(open(sys.argv[1], encoding="utf-8"))
assert [r["elevation_id"] for r in rows] == ["elev-A"], rows
assert rows[0]["card"].endswith("#415") and rows[0]["capability"] == "label-write", rows
print("OK")
PYEOF
python3 "$ELEV" open-check --ledger-dir "$LED" --now "$NOW" >/dev/null 2>&1
[[ $? -eq 3 ]] && pass "open-check：过期驻留 → exit 3（断言红）" || fail "open-check 未红"
# 收回 elev-A 后断言转绿
echo "$(cat "$LED/shadow-evidence.jsonl")" > "$LED/shadow-evidence.jsonl"
python3 - "$LED/shadow-evidence.jsonl" <<'PYEOF'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
rows.append({**rows[0], "action": "elevation.revoke", "payload": json.dumps({
    "elevation_id": "elev-A", "cause": "ttl-expired"})})
open(sys.argv[1], "w", encoding="utf-8").write("\n".join(json.dumps(r, ensure_ascii=False, sort_keys=True) for r in rows) + "\n")
PYEOF
python3 "$ELEV" open-check --ledger-dir "$LED" --now "$NOW" >/dev/null 2>&1
[[ $? -eq 0 ]] && pass "AC-9d：收回后 open-check 绿（无长期驻留提权）" || fail "收回后断言仍红"

echo "----------------------------------------"
if [[ $FAILS -eq 0 ]]; then echo "test-elevation: PASS"; exit 0; fi
echo "test-elevation: $FAILS 处失败"; exit 1
