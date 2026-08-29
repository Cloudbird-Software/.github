#!/usr/bin/env bash
# test-evidence-shadow.sh —— 影子双写/验链/查询执法自测（IR-0006 W1-B2 / 卡 #407）
#
# 覆盖（卡 AC 对应）：
#   AC-4a evidence_shadow append/verify/relink 闭环 + 统一输出形态
#   AC-4b 原 JSONL 只增不改：drill record 后 history 原行字节不变、只追加
#   AC-4c tenant 缺失拒写；audit_emit 影子行带 tenant
#   负向：篡改/断链 → 验链红（exit 3）；payload 超限拒写（INV-06）
# 用法: bash governance/tests/test-evidence-shadow.sh（gate.yml 自动纳入）
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SHADOW="$TMP/shadow-evidence.jsonl"

ev() {  # ev <file> [tenant] → 事件 JSON
  local tenant="${2:-cloudbird-internal}"
  cat >"$1" <<EOF
{"ts": "2026-08-29T00:00:0${3:-0}Z", "kind": "gate", "action": "test-event", "verdict": "pass",
 "subject": {"card": "Cloudbird-Software/.github#407", "tenant": "$tenant"},
 "actor": {"identity": "test-runner", "role": "bot", "model": null}}
EOF
}

# ---- 正向：append×2 → verify 绿 ----
ev "$TMP/ev1.json" && ev "$TMP/ev2.json" "" 1
python3 "$DIR/governance/evidence_shadow.py" append --file "$SHADOW" --event-file "$TMP/ev1.json" >/dev/null \
  && pass "影子 append #1" || fail "影子 append #1"
python3 "$DIR/governance/evidence_shadow.py" append --file "$SHADOW" --event-file "$TMP/ev2.json" >/dev/null \
  && pass "影子 append #2（链式续接）" || fail "影子 append #2"
python3 "$DIR/governance/evidence_shadow.py" verify --file "$SHADOW" >/dev/null \
  && pass "影子验链绿（2 条）" || fail "影子验链"

# ---- AC-4c 负向：tenant 缺失拒写 ----
cat >"$TMP/bad.json" <<'EOF'
{"ts": "2026-08-29T00:00:00Z", "kind": "gate", "action": "x", "verdict": "pass",
 "subject": {"card": "Cloudbird-Software/.github#407"},
 "actor": {"identity": "t", "role": "bot", "model": null}}
EOF
python3 "$DIR/governance/evidence_shadow.py" append --file "$SHADOW" --event-file "$TMP/bad.json" >/dev/null 2>&1
[[ $? -eq 3 ]] && pass "AC-4c tenant 缺失 → 拒写（exit 3）" || fail "AC-4c tenant 缺失未拒写"
N=$(wc -l <"$SHADOW" | tr -d ' ')
[[ "$N" == "2" ]] && pass "拒写零副作用（仍 2 条）" || fail "拒写后有副作用（$N 条）"

# ---- 负向：篡改 → 验链红 ----
TAMPER="$TMP/tamper.jsonl"; cp "$SHADOW" "$TAMPER"
python3 - "$TAMPER" <<'PYEOF'
import json, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
rec = json.loads(lines[0]); rec["verdict"] = "tampered"
lines[0] = json.dumps(rec, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
open(sys.argv[1], "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
PYEOF
python3 "$DIR/governance/evidence_shadow.py" verify --file "$TAMPER" >/dev/null 2>&1
[[ $? -eq 3 ]] && pass "篡改 → 验链红（exit 3，链断=红）" || fail "篡改未检出"

# ---- 负向：payload 4097B 拒写（INV-06） ----
python3 - "$TMP/big.json" <<'PYEOF'
import json, sys
ev = {"ts": "2026-08-29T00:00:00Z", "kind": "gate", "action": "x", "verdict": "pass",
      "subject": {"card": "Cloudbird-Software/.github#407", "tenant": "t"},
      "actor": {"identity": "t", "role": "bot", "model": None}, "payload": "x" * 4097}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(ev))
PYEOF
python3 "$DIR/governance/evidence_shadow.py" append --file "$SHADOW" --event-file "$TMP/big.json" >/dev/null 2>&1
[[ $? -eq 3 ]] && pass "payload 4097B → 拒写（INV-06）" || fail "4KB 上限未执法"

# ---- relink：本地续接基链 + 合并片验链 ----
python3 "$DIR/governance/evidence_shadow.py" relink --base "$SHADOW" --local "$TAMPER" --out "$TMP/merged.jsonl" >/dev/null 2>&1
[[ $? -ne 0 ]] && pass "relink 拒绝坏基链/坏本地（防覆盖掩盖篡改）" || fail "relink 未拒坏链"
BASE2="$TMP/base2.jsonl"; cp "$SHADOW" "$BASE2"
python3 "$DIR/governance/evidence_shadow.py" relink --base "$BASE2" --local "$SHADOW" --out "$TMP/merged2.jsonl" >/dev/null \
  && python3 "$DIR/governance/evidence_shadow.py" verify --file "$TMP/merged2.jsonl" >/dev/null \
  && pass "relink 创世续接 + 合并片验链绿（4 条）" || fail "relink 正向闭环"

# ---- drill record 双写（AC-4b：原台账只增不改） ----
DHIST="$TMP/drill/history.jsonl"; mkdir -p "$(dirname "$DHIST")"
mkdrill() {  # mkdrill <ts> <run_id>
  cat >"$TMP/drec.json" <<EOF
{"ts": "$1", "kind": "seed-drill", "run_id": "$2", "seed": "s1", "sample_id": "x",
 "difficulty": 3, "gate": "g060", "target_repo": "Cloudbird-Software/.github",
 "branch": null, "head_sha": null, "surface": "draft-pr", "verdict": "detected",
 "limitation": "无", "canary_link": "healthy"}
EOF
}
mkdrill "2026-08-29T01:00:00Z" "run-1"
python3 "$DIR/governance/drill/drill.py" record --history "$DHIST" --json "$(cat "$TMP/drec.json")" >/dev/null \
  && pass "drill record #1（history+影子双写）" || fail "drill record #1"
DSHADOW="$TMP/drill/shadow-evidence.jsonl"
[[ -s "$DSHADOW" ]] && pass "drill 影子已落盘" || fail "drill 影子缺失"
H1=$(cat "$DHIST")
mkdrill "2026-08-29T02:00:00Z" "run-2"
python3 "$DIR/governance/drill/drill.py" record --history "$DHIST" --json "$(cat "$TMP/drec.json")" >/dev/null \
  && pass "drill record #2" || fail "drill record #2"
head -1 "$DHIST" | grep -qx "$H1" \
  && pass "AC-4b drill history 原行字节不变（只追加）" || fail "AC-4b drill history 原行被改"
python3 "$DIR/governance/evidence_shadow.py" verify --file "$DSHADOW" >/dev/null \
  && pass "drill 影子验链绿（双写一致）" || fail "drill 影子链断"
python3 - "$DSHADOW" <<'PYEOF'
import json, sys
rec = json.loads(open(sys.argv[1], encoding="utf-8").readlines()[0])
assert rec["kind"] == "gate" and rec["action"] == "drill-seed-drill", rec
assert rec["subject"]["tenant"] == "cloudbird-internal", rec
assert rec["actor"]["identity"] == "drill-seed-bot", rec
print("OK")
PYEOF
[[ $? -eq 0 ]] && pass "drill 影子字段对齐 schema v1" || fail "drill 影子字段断言"

# ---- butler audit_emit 双写（AC-4c：影子行带 tenant） ----
BUTLER_SHADOW="$TMP/butler/shadow-evidence.jsonl"
BUTLER_SHADOW_FILE="$BUTLER_SHADOW" bash "$DIR/governance/butler-audit.sh" test-butler cron ok '{"k":1}' >/dev/null \
  && pass "butler-audit CLI（AUDIT 行 + 影子双写）" || fail "butler-audit CLI"
[[ -s "$BUTLER_SHADOW" ]] && pass "butler 影子已落盘" || fail "butler 影子缺失"
python3 "$DIR/governance/evidence_shadow.py" verify --file "$BUTLER_SHADOW" >/dev/null \
  && pass "butler 影子验链绿" || fail "butler 影子链断"
grep -q '"butler-test-butler"' "$BUTLER_SHADOW" && grep -q '"tenant":"cloudbird-internal"' "$BUTLER_SHADOW" \
  && pass "AC-4c butler 影子带 action/tenant" || fail "butler 影子字段断言"
# ---- 负向：影子写入失败 = fail-closed（BEH-01 双写不一致当场可见） ----
mkdir -p "$TMP/shadow-is-dir"
BUTLER_SHADOW_FILE="$TMP/shadow-is-dir" bash "$DIR/governance/butler-audit.sh" test-butler cron ok '{"k":1}' >/dev/null 2>&1
[[ $? -ne 0 ]] && pass "影子写入失败 → butler-audit 非零退出（fail-closed）" || fail "影子写失败未 fail-closed"

# ---- elevation 裁决入账（W2-C4 / AC-9c：evidence-query 第 4 源，subject 可查询） ----
ELEVDIR="$TMP/elevation"; mkdir -p "$ELEVDIR"
ESHADOW="$ELEVDIR/shadow-evidence.jsonl"
cat >"$TMP/ereq.json" <<'EOF'
{"kind": "elevate", "card": "Cloudbird-Software/.github#415", "requester": "agent-x",
 "delivery_id": "cmt-1", "capability": "label-write", "reason": "状态机补偿写",
 "spec_ref": "specs/IR-0006/spec.md#AC-9"}
EOF
python3 "$DIR/governance/elevation.py" adjudicate --request-file "$TMP/ereq.json" --role agent \
  --policy "$DIR/governance/policy/elevation.yaml" --now 2026-08-29T00:00:00Z >"$TMP/everd.json" \
  && pass "elevation adjudicate 出裁决（策略表路径）" || fail "elevation adjudicate"
python3 - "$TMP/everd.json" >"$TMP/eev.json" <<'PYEOF'
import json, sys
v = json.load(open(sys.argv[1], encoding="utf-8"))
ev = {"ts": "2026-08-29T00:00:02Z", "kind": "approval", "action": "elevation." + v["verdict"],
      "verdict": v["verdict"],
      "subject": {"card": v["card"], "tenant": "cloudbird-internal"},
      "actor": {"identity": v["requester"], "role": "agent"},
      "payload": json.dumps(v, ensure_ascii=False, sort_keys=True)}
print(json.dumps(ev, ensure_ascii=False, sort_keys=True))
PYEOF
python3 "$DIR/governance/evidence_shadow.py" append --file "$ESHADOW" --event-file "$TMP/eev.json" >/dev/null \
  && pass "elevation 裁决入影子账本（链式 append）" || fail "elevation 影子 append"
python3 "$DIR/governance/evidence_shadow.py" verify --file "$ESHADOW" >/dev/null \
  && pass "elevation 影子验链绿" || fail "elevation 影子链断"

# ---- tickets 短票据事件（W2-C1 / AC-5b：evidence-query 第 5 源，subject 可查询） ----
TICKETS="$TMP/tickets.jsonl"
cat >"$TMP/tk1.json" <<'EOF'
{"ts": "2026-08-29T00:00:00Z", "kind": "approval", "action": "ticket.grant", "verdict": "pass",
 "subject": {"card": "Cloudbird-Software/.github#412", "tenant": "cloudbird-internal"},
 "actor": {"identity": "selfcloud-scheduler", "role": "bot"},
 "payload": "{\"job_id\": \"job-t1\", \"ttl_minutes\": 30}"}
EOF
cat >"$TMP/tk2.json" <<'EOF'
{"ts": "2026-08-29T00:30:00Z", "kind": "approval", "action": "ticket.revoke", "verdict": "pass",
 "subject": {"card": "Cloudbird-Software/.github#412", "tenant": "cloudbird-internal"},
 "actor": {"identity": "selfcloud-scheduler", "role": "bot"},
 "payload": "{\"job_id\": \"job-t1\", \"reason\": \"ttl-expired\"}"}
EOF
python3 "$DIR/governance/evidence_shadow.py" append --file "$TICKETS" --event-file "$TMP/tk1.json" >/dev/null \
  && python3 "$DIR/governance/evidence_shadow.py" append --file "$TICKETS" --event-file "$TMP/tk2.json" >/dev/null \
  && python3 "$DIR/governance/evidence_shadow.py" verify --file "$TICKETS" >/dev/null \
  && pass "tickets 影子验链绿（grant/revoke 双事件）" || fail "tickets 影子链断"

# ---- feishu 投影同步事件（W3-F1 / AC-7a：evidence-query 第 6 源，payload 带 api_calls） ----
FEISHU="$TMP/feishu.jsonl"
cat >"$TMP/fs1.json" <<'EOF'
{"ts": "2026-08-29T00:05:00Z", "kind": "gate", "action": "butler-feishu-sync", "verdict": "ok",
 "subject": {"card": "Cloudbird-Software/.github#416", "tenant": "cloudbird-internal"},
 "actor": {"identity": "feishu-sync", "role": "bot"},
 "payload": "{\"cards\": 2, \"drift_alarms\": 0, \"api_calls\": {\"GET /open-apis/bitable/v1/apps/{app}/tables\": 1}}"}
EOF
python3 "$DIR/governance/evidence_shadow.py" append --file "$FEISHU" --event-file "$TMP/fs1.json" >/dev/null \
  && python3 "$DIR/governance/evidence_shadow.py" verify --file "$FEISHU" >/dev/null \
  && pass "feishu 影子验链绿（投影同步事件+api_calls payload）" || fail "feishu 影子链断"

# ---- env 环境对账事件（W4-R1 / AC-8b：evidence-query 第 7 源，对账日志入账本） ----
ENVD="$TMP/envd.jsonl"
cat >"$TMP/ed1.json" <<'EOF'
{"ts": "2026-08-29T07:33:10Z", "kind": "gate", "action": "butler-env-drift", "verdict": "ok",
 "subject": {"card": "Cloudbird-Software/.github#418", "tenant": "cloudbird-internal"},
 "actor": {"identity": "env-drift", "role": "bot"},
 "payload": "{\"scope\": [\"dev-self\", \"staging-self\"], \"checked\": 2, \"drifts\": 0}"}
EOF
python3 "$DIR/governance/evidence_shadow.py" append --file "$ENVD" --event-file "$TMP/ed1.json" >/dev/null \
  && python3 "$DIR/governance/evidence_shadow.py" verify --file "$ENVD" >/dev/null \
  && pass "env 影子验链绿（对账日志事件+scope/drifts payload）" || fail "env 影子链断"

# ---- evidence-query 七源统一查询（AC-4a：归并 + 验链 + fail-closed） ----
GHSTUB="$TMP/gh-stub"
mkdir -p "$TMP/fixtures"
# fixture：metering=周分片列表（$SHADOW）；drill/butler/elevation/feishu/env=各自影子（独立成链）；tickets=短票据链
python3 - "$SHADOW" "$DSHADOW" "$BUTLER_SHADOW" "$ESHADOW" "$TICKETS" "$FEISHU" "$ENVD" "$TMP/fixtures" <<'PYEOF'
import base64, json, sys
shadow, dshadow, bshadow, eshadow, tickets, feishu, envd, fixdir = sys.argv[1:9]
b64 = lambda p: base64.b64encode(open(p, "rb").read()).decode()
json.dump([{"type": "file", "name": "shadow-evidence-2026-W35.jsonl", "content": b64(shadow)}],
          open(f"{fixdir}/metering-list.json", "w"))
json.dump({"type": "file", "content": b64(dshadow)}, open(f"{fixdir}/drill.json", "w"))
json.dump({"type": "file", "content": b64(bshadow)}, open(f"{fixdir}/butler.json", "w"))
json.dump({"type": "file", "content": b64(eshadow)}, open(f"{fixdir}/elev.json", "w"))
json.dump({"type": "file", "content": b64(tickets)}, open(f"{fixdir}/tickets.json", "w"))
json.dump({"type": "file", "content": b64(feishu)}, open(f"{fixdir}/feishu.json", "w"))
json.dump({"type": "file", "content": b64(envd)}, open(f"{fixdir}/envd.json", "w"))
PYEOF
cat >"$GHSTUB" <<'STUBEOF'
#!/usr/bin/env bash
# gh 桩：按 API 路径回放 fixture（evidence-query 测试专用）
set -euo pipefail
url="${2:-}"
F="${GH_STUB_FIXTURES:?}"
case "$url" in
  "repos/Cloudbird-Software/CI-Workflows/contents?ref=metering-ledger")
    cat "$F/metering-list.json" ;;
  "repos/Cloudbird-Software/.github/contents/governance/drill/shadow-evidence.jsonl?ref=drill-ledger")
    if [[ -f "$F/drill-tampered.json" ]]; then cat "$F/drill-tampered.json"; else cat "$F/drill.json"; fi ;;
  "repos/Cloudbird-Software/.github/contents/governance/butler/shadow-evidence.jsonl?ref=butler-ledger")
    if [[ "${GH_STUB_BUTLER_MISSING:-}" == "1" ]]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
    if [[ "${GH_STUB_BUTLER_MISSING:-}" == "2" ]]; then
      echo 'gh: No ref found for "butler-ledger" in repo Cloudbird-Software/.github (HTTP 404)' >&2; exit 1
    fi
    if [[ "${GH_STUB_BUTLER_MISSING:-}" == "3" ]]; then
      echo 'gh: No commit found for the ref butler-ledger (HTTP 404)' >&2; exit 1
    fi
    cat "$F/butler.json" ;;
  "repos/Cloudbird-Software/.github/contents/governance/elevation/shadow-evidence.jsonl?ref=elevation-ledger")
    if [[ "${GH_STUB_ELEV_MISSING:-}" == "1" ]]; then
      echo "gh: No commit found for the ref elevation-ledger (HTTP 404)" >&2; exit 1
    fi
    cat "$F/elev.json" ;;
  "repos/Cloudbird-Software/cnb-bridge/contents/tickets.jsonl?ref=tickets-ledger")
    if [[ "${GH_STUB_TICKETS_MISSING:-}" == "1" ]]; then
      echo "gh: No commit found for the ref tickets-ledger (HTTP 404)" >&2; exit 1
    fi
    cat "$F/tickets.json" ;;
  "repos/Cloudbird-Software/.github/contents/governance/feishu/shadow-evidence.jsonl?ref=feishu-ledger")
    if [[ "${GH_STUB_FEISHU_MISSING:-}" == "1" ]]; then
      echo "gh: No commit found for the ref feishu-ledger (HTTP 404)" >&2; exit 1
    fi
    cat "$F/feishu.json" ;;
  "repos/Cloudbird-Software/.github/contents/governance/env/shadow-evidence.jsonl?ref=env-ledger")
    if [[ "${GH_STUB_ENVD_MISSING:-}" == "1" ]]; then
      echo "gh: No commit found for the ref env-ledger (HTTP 404)" >&2; exit 1
    fi
    cat "$F/envd.json" ;;
  *) echo "gh-stub: 意外 URL $url" >&2; exit 1 ;;
esac
STUBEOF
chmod +x "$GHSTUB"
nlines() { grep -c . <<<"$1" || true; }  # 非空行计数（wc 对空 herestring 误报 1）
QOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/q.err"); QRC=$?
N=$(nlines "$QOUT")
[[ $QRC -eq 0 && "$N" -eq 10 ]] && pass "统一查询归并七源（10 条，rc=0）" || fail "统一查询（rc=$QRC 行=$N）"
grep -q '"source":"metering"' <<<"$QOUT" && grep -q '"source":"drill"' <<<"$QOUT" && grep -q '"source":"butler"' <<<"$QOUT" \
  && grep -q '"source":"elevation"' <<<"$QOUT" && grep -q '"source":"tickets"' <<<"$QOUT" \
  && grep -q '"source":"feishu"' <<<"$QOUT" && grep -q '"source":"env"' <<<"$QOUT" \
  && pass "七源标记齐全（source 字段）" || fail "source 标记缺失"
grep -q '^SUMMARY ' "$TMP/q.err" && grep -Eq '"metering": ?2' "$TMP/q.err" \
  && pass "分源统计（stderr SUMMARY）" || fail "SUMMARY 统计缺失"
# --card 过滤：metering 影子绑 #407，drill/butler 哨兵 #0，elevation 绑 #415
COUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub \
  bash "$DIR/governance/evidence-query.sh" --card Cloudbird-Software/.github#407 2>/dev/null); CRC=$?
CN=$(nlines "$COUT")
[[ $CRC -eq 0 && "$CN" -eq 2 ]] && pass "--card 过滤（#407 → 2 条）" || fail "--card 过滤（rc=$CRC 行=$CN）"
# AC-9c：elevation 记录按 subject 可查询（#415 → 1 条，source=elevation）
EOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub \
  bash "$DIR/governance/evidence-query.sh" --card Cloudbird-Software/.github#415 2>/dev/null); ERC=$?
EN=$(nlines "$EOUT")
[[ $ERC -eq 0 && "$EN" -eq 1 ]] && grep -q '"source":"elevation"' <<<"$EOUT" \
  && pass "AC-9c elevation 记录 subject 可查询（#415 → 1 条）" || fail "elevation 查询（rc=$ERC 行=$EN）"
# AC-5b：短票据 grant/revoke 事件按 subject 可查询（#412 → 2 条，source=tickets）
TQOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub \
  bash "$DIR/governance/evidence-query.sh" --card Cloudbird-Software/.github#412 2>/dev/null); TQRC=$?
TQN=$(nlines "$TQOUT")
[[ $TQRC -eq 0 && "$TQN" -eq 2 ]] && grep -q '"source":"tickets"' <<<"$TQOUT" \
  && grep -q '"ticket.grant"' <<<"$TQOUT" && grep -q '"ticket.revoke"' <<<"$TQOUT" \
  && pass "AC-5b tickets 短票据事件 subject 可查询（#412 → 2 条）" || fail "tickets 查询（rc=$TQRC 行=$TQN）"
# AC-7a：feishu 投影同步事件按 subject 可查询（#416 → 1 条，payload 带 api_calls）
FQOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub \
  bash "$DIR/governance/evidence-query.sh" --card Cloudbird-Software/.github#416 2>/dev/null); FQRC=$?
FQN=$(nlines "$FQOUT")
[[ $FQRC -eq 0 && "$FQN" -eq 1 ]] && grep -q '"source":"feishu"' <<<"$FQOUT" \
  && grep -q '"butler-feishu-sync"' <<<"$FQOUT" && grep -q 'api_calls' <<<"$FQOUT" \
  && pass "AC-7a feishu 同步事件 subject 可查询（#416 → 1 条，payload 带 api_calls）" || fail "feishu 查询（rc=$FQRC 行=$FQN）"
# AC-8b：env 对账日志按 subject 可查询（#418 → 1 条，payload 带 scope/drifts）
EDOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub \
  bash "$DIR/governance/evidence-query.sh" --card Cloudbird-Software/.github#418 2>/dev/null); EDRC=$?
EDN=$(nlines "$EDOUT")
[[ $EDRC -eq 0 && "$EDN" -eq 1 ]] && grep -q '"source":"env"' <<<"$EDOUT" \
  && grep -q '"butler-env-drift"' <<<"$EDOUT" && grep -q 'scope' <<<"$EDOUT" \
  && pass "AC-8b env 对账日志 subject 可查询（#418 → 1 条，payload 带 scope）" || fail "env 查询（rc=$EDRC 行=$EDN）"
# 源缺席（404）：过渡期合法，非红（须在篡改 fixture 生成前跑——桩对篡改片优先回放）
MOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub GH_STUB_BUTLER_MISSING=1 \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/m.err"); MRC=$?
MN=$(nlines "$MOUT")
[[ $MRC -eq 0 && "$MN" -eq 9 ]] && pass "butler 源缺席（404）→ 跳过非红（9 条）" || fail "源缺席误红（rc=$MRC 行=$MN）"
# 源缺席（404 第二报文形态——账本分支未建 "No ref found"）：同跳过非红
# （2026-08-29 波次通道实测回归：该形态曾被误判"非 404"→ INFRA exit 2）
ROUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub GH_STUB_BUTLER_MISSING=2 \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/r.err"); RRC=$?
RN=$(nlines "$ROUT")
[[ $RRC -eq 0 && "$RN" -eq 9 ]] && pass "源缺席（No ref found 分支未建）→ 跳过非红（9 条）" || fail "分支未建误红（rc=$RRC 行=$RN）"
# 源缺席（404 第三报文形态——分支缺失 "No commit found for the ref"，本地实测
# 真实报文）：按 HTTP 404 状态码判定后同跳过非红
COUT2=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub GH_STUB_BUTLER_MISSING=3 \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/c2.err"); C2RC=$?
C2N=$(nlines "$COUT2")
[[ $C2RC -eq 0 && "$C2N" -eq 9 ]] && pass "源缺席（No commit found for the ref）→ 跳过非红（9 条）" || fail "分支缺失误红（rc=$C2RC 行=$C2N）"
# 源缺席（elevation 第 4 源分支未建——"No commit found"）：同跳过非红
EOUT2=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub GH_STUB_ELEV_MISSING=1 \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/e2.err"); E2RC=$?
E2N=$(nlines "$EOUT2")
[[ $E2RC -eq 0 && "$E2N" -eq 9 ]] && pass "elevation 源缺席（分支未建）→ 跳过非红（9 条）" || fail "elevation 缺席误红（rc=$E2RC 行=$E2N）"
# tickets 第 5 源缺席（分支未建）：同跳过非红（REMOVAL 语义：源消失≠链断）
TKOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub GH_STUB_TICKETS_MISSING=1 \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/tk.err"); TKRC=$?
TKQN=$(nlines "$TKOUT")
[[ $TKRC -eq 0 && "$TKQN" -eq 8 ]] && pass "tickets 源缺席（分支未建）→ 跳过非红（8 条）" || fail "tickets 缺席误红（rc=$TKRC 行=$TKQN）"
# feishu 第 6 源缺席（分支未建——投影未开通的过渡期常态）：同跳过非红
FOUT2=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub GH_STUB_FEISHU_MISSING=1 \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/f2.err"); F2RC=$?
F2N=$(nlines "$FOUT2")
[[ $F2RC -eq 0 && "$F2N" -eq 9 ]] && pass "feishu 源缺席（分支未建=投影未开通过渡期）→ 跳过非红（9 条）" || fail "feishu 缺席误红（rc=$F2RC 行=$F2N）"
# env 第 7 源缺席（分支未建=W4-R1 对账未跑的过渡期常态）：同跳过非红
EVOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub GH_STUB_ENVD_MISSING=1 \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/ev.err"); EVRC=$?
EVN=$(nlines "$EVOUT")
[[ $EVRC -eq 0 && "$EVN" -eq 9 ]] && pass "env 源缺席（分支未建=对账未跑过渡期）→ 跳过非红（9 条）" || fail "env 缺席误红（rc=$EVRC 行=$EVN）"
# 负向：任一源链断 → exit 3 且 stdout 零输出（不可信数据不出结果）
python3 - "$TMP/fixtures" <<'PYEOF'
import base64, json, sys
fixdir = sys.argv[1]
lines = base64.b64decode(json.load(open(f"{fixdir}/drill.json"))["content"]).decode().splitlines()
rec = json.loads(lines[0]); rec["verdict"] = "tampered"
lines[0] = json.dumps(rec, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
json.dump({"type": "file", "content": base64.b64encode(("\n".join(lines) + "\n").encode()).decode()},
          open(f"{fixdir}/drill-tampered.json", "w"))
PYEOF
TOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/t.err"); TRC=$?
TN=$(nlines "$TOUT")
[[ $TRC -eq 3 && "$TN" -eq 0 ]] && pass "源链断 → exit 3 零输出（fail-closed）" || fail "链断未 fail-closed（rc=$TRC 行=$TN）"

echo "----------------------------------------"
if [[ $FAILS -eq 0 ]]; then echo "test-evidence-shadow: PASS"; exit 0; fi
echo "test-evidence-shadow: $FAILS 处失败"; exit 1
