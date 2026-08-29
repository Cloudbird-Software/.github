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

# ---- evidence-query 三源统一查询（AC-4a：归并 + 验链 + fail-closed） ----
GHSTUB="$TMP/gh-stub"
mkdir -p "$TMP/fixtures"
# fixture：metering=周分片列表（$SHADOW）；drill/butler=各自影子（独立成链）
python3 - "$SHADOW" "$DSHADOW" "$BUTLER_SHADOW" "$TMP/fixtures" <<'PYEOF'
import base64, json, sys
shadow, dshadow, bshadow, fixdir = sys.argv[1:5]
b64 = lambda p: base64.b64encode(open(p, "rb").read()).decode()
json.dump([{"type": "file", "name": "shadow-evidence-2026-W35.jsonl", "content": b64(shadow)}],
          open(f"{fixdir}/metering-list.json", "w"))
json.dump({"type": "file", "content": b64(dshadow)}, open(f"{fixdir}/drill.json", "w"))
json.dump({"type": "file", "content": b64(bshadow)}, open(f"{fixdir}/butler.json", "w"))
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
    cat "$F/butler.json" ;;
  *) echo "gh-stub: 意外 URL $url" >&2; exit 1 ;;
esac
STUBEOF
chmod +x "$GHSTUB"
nlines() { grep -c . <<<"$1" || true; }  # 非空行计数（wc 对空 herestring 误报 1）
QOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/q.err"); QRC=$?
N=$(nlines "$QOUT")
[[ $QRC -eq 0 && "$N" -eq 5 ]] && pass "统一查询归并三源（5 条，rc=0）" || fail "统一查询（rc=$QRC 行=$N）"
grep -q '"source":"metering"' <<<"$QOUT" && grep -q '"source":"drill"' <<<"$QOUT" && grep -q '"source":"butler"' <<<"$QOUT" \
  && pass "三源标记齐全（source 字段）" || fail "source 标记缺失"
grep -q '^SUMMARY ' "$TMP/q.err" && grep -Eq '"metering": ?2' "$TMP/q.err" \
  && pass "分源统计（stderr SUMMARY）" || fail "SUMMARY 统计缺失"
# --card 过滤：metering 影子绑 #407，drill/butler 哨兵 #0 → 仅 2 条
COUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub \
  bash "$DIR/governance/evidence-query.sh" --card Cloudbird-Software/.github#407 2>/dev/null); CRC=$?
CN=$(nlines "$COUT")
[[ $CRC -eq 0 && "$CN" -eq 2 ]] && pass "--card 过滤（#407 → 2 条）" || fail "--card 过滤（rc=$CRC 行=$CN）"
# 源缺席（404）：过渡期合法，非红（须在篡改 fixture 生成前跑——桩对篡改片优先回放）
MOUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub GH_STUB_BUTLER_MISSING=1 \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/m.err"); MRC=$?
MN=$(nlines "$MOUT")
[[ $MRC -eq 0 && "$MN" -eq 4 ]] && pass "butler 源缺席（404）→ 跳过非红（4 条）" || fail "源缺席误红（rc=$MRC 行=$MN）"
# 源缺席（404 第二报文形态——账本分支未建 "No ref found"）：同跳过非红
# （2026-08-29 波次通道实测回归：该形态曾被误判"非 404"→ INFRA exit 2）
ROUT=$(GH="$GHSTUB" GH_STUB_FIXTURES="$TMP/fixtures" GH_TOKEN=stub GH_STUB_BUTLER_MISSING=2 \
  bash "$DIR/governance/evidence-query.sh" 2>"$TMP/r.err"); RRC=$?
RN=$(nlines "$ROUT")
[[ $RRC -eq 0 && "$RN" -eq 4 ]] && pass "源缺席（No ref found 分支未建）→ 跳过非红（4 条）" || fail "分支未建误红（rc=$RRC 行=$RN）"
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
