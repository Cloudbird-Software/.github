#!/usr/bin/env bash
# test-feishu-sync.sh —— 飞书多维表格投影同步器自测（IR-0006 W3-F1 / 卡 #416）
#
# 覆盖（卡 AC 对应，全部离线——飞书测试用桩注入，spec T-08：无网络依赖断言）：
#   AC-7a plan_sync 纯函数：建行/漂移纠正（INV-05 报警面）/孤儿删除/派生刷新不报警/
#        空值等价/unknown-state 跳过 State
#   AC-7a 桩 e2e：GitHub 桩（label 真源）+ 飞书桩 → 同步 → batch_create 落正确字段；
#        二轮人工改 State → 纠正（batch_update）+ WARN + 漂移入审计；孤儿行删除；
#        AUDIT 行 + schema v1 影子落盘（链验绿）+ api_calls 计数
#   AC-7b fail-open 面：--verify 只读（不收敛=exit 3 且零写）；--drop 单轮重建；
#        停用/未配置=skipped 绿；飞书 API 故障=exit 2（fail-closed 方向）；
#        GH_TOKEN 缺失=exit 2（label 真源不可缺席）
# 用法: bash governance/tests/test-feishu-sync.sh（gate.yml 自动纳入）
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

TMP=$(mktemp -d)
trap '[[ -n "${STUB_PID:-}" ]] && kill "$STUB_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

FSYNC="python3 $DIR/governance/feishu-sync.py"

# ---- 纯函数区（plan_sync：IFACE-04 字段期望 + INV-05 漂移语义） ----
python3 - "$DIR" <<'PYEOF' && pass "plan_sync 纯函数五断言（建行/纠正/删除/派生/空值）" || fail "plan_sync 纯函数"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("feishu_sync", f"{sys.argv[1]}/governance/feishu-sync.py")
fs = importlib.util.module_from_spec(spec); spec.loader.exec_module(fs)
cards = [
    {"repo": ".github", "number": 416, "title": "t", "state": "in-progress",
     "assignee": "randypanding", "days_idle": 2, "ac_progress": "1/2",
     "gate_status": "绿", "predicate_status": "pending"},
    {"repo": ".github", "number": 417, "title": "t2", "state": "ready",
     "assignee": "", "days_idle": 0, "ac_progress": "",
     "gate_status": "无 PR", "predicate_status": "pending"},
]
opts = {"in-progress", "ready", "done"}
# 1) 空表 → 全量建行；卡 ID 唯一键
p = fs.plan_sync(cards, {}, opts)
assert len(p["to_create"]) == 2 and not p["to_update"] and not p["drift_alarms"], p
assert p["to_create"][0]["fields"]["卡 ID"] == ".github#416"
assert p["to_create"][0]["fields"]["State"] == "in-progress"
# 2) 人工改 State=done（label=in-progress）→ 纠正 + 报警（INV-05）
recs = {".github#416": {"record_id": "rec1", "fields": {**fs.want_fields(cards[0]), "State": "done"}}}
p = fs.plan_sync(cards, recs, opts)
assert p["to_update"] == [{"record_id": "rec1", "fields": {"State": "in-progress"}}], p
assert p["drift_alarms"] == [(".github#416", "State", "done", "in-progress")], p
# 3) 孤儿行（卡已 closed）→ 删除；停留天数派生刷新不进报警面
recs = {".github#416": {"record_id": "rec1", "fields": fs.want_fields(cards[0])},
        ".github#417": {"record_id": "rec2", "fields": fs.want_fields(cards[1]) | {"停留天数": 5}},
        ".github#999": {"record_id": "rec9", "fields": {"卡 ID": ".github#999", "停留天数": 99}}}
p = fs.plan_sync(cards, recs, opts)
assert p["to_delete"] == ["rec9"], p
assert [u for u in p["to_update"] if u["record_id"] == "rec2"] == [{"record_id": "rec2", "fields": {"停留天数": 0}}], p
assert p["to_create"] == [] and p["drift_alarms"] == [], p
# 4) 空值等价：记录 None ≈ 期望 ""（认领者/AC 进度空卡不误报）
recs2 = {".github#417": {"record_id": "rec2", "fields": fs.want_fields(cards[1]) | {"认领者": None, "AC 进度": None}}}
p = fs.plan_sync([cards[1]], recs2, opts)
assert p["to_update"] == [] and p["drift_alarms"] == [], p
# 5) unknown state：State 剔除出 want，其余照常
c3 = dict(cards[0], number=418, state="weird")
p = fs.plan_sync([c3], {}, {"in-progress"})
assert "State" not in p["to_create"][0]["fields"] and p["unknown_states"] == [(".github#418", "weird")], p
print("OK")
PYEOF

# ---- 双桩 e2e：GitHub 桩（label 真源）+ 飞书桩（投影面） ----
mkdir -p "$TMP/ctrl"
CAP="$TMP/captured.jsonl"; : > "$CAP"
cat > "$TMP/stub.py" <<'STUBEOF'
#!/usr/bin/env python3
# e2e 桩：单服务器双面（/repos/=GitHub fixture；/open-apis/=飞书带状态投影面）
import json, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
TMP = sys.argv[1]; CTRL = os.path.join(TMP, "ctrl")
CAP = os.path.join(TMP, "captured.jsonl")
ERR = os.path.join(TMP, "feishu-error")
GH_ISSUES = [
    {"node_id": "n416", "number": 416, "title": "W3-F1 桩卡", "state": "open",
     "labels": [{"name": "type:card"}, {"name": "state:in-progress"}],
     "assignees": [{"login": "randypanding"}],
     "html_url": "https://github.com/Cloudbird-Software/.github/issues/416",
     "updated_at": "2026-08-29T00:00:00Z", "body": "- [x] AC-7a\n- [ ] AC-7b"},
    {"node_id": "n417", "number": 417, "title": "W3-F2 桩卡", "state": "open",
     "labels": [{"name": "type:card"}, {"name": "state:ready"}],
     "assignees": [], "html_url": "https://github.com/Cloudbird-Software/.github/issues/417",
     "updated_at": "2026-08-29T00:00:00Z", "body": ""},
]
GH_PRS = [{"number": 90, "body": "Card: Cloudbird-Software/.github#416", "head": {"sha": "abc123"}}]
GH_CHECKS = {"check_runs": [{"name": "gate", "status": "completed", "conclusion": "success"},
                            {"name": "adversary", "status": "completed", "conclusion": "success"}]}
def rd(name, default):
    p = os.path.join(CTRL, name)
    return json.load(open(p, encoding="utf-8")) if os.path.isfile(p) else default
def wr(name, obj):
    json.dump(obj, open(os.path.join(CTRL, name), "w", encoding="utf-8"), ensure_ascii=False)
def recs_file(tid): return f"records-{tid}.json"
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, obj):
        b = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def _cap(self, method, body):
        open(CAP, "a", encoding="utf-8").write(
            json.dumps({"m": method, "p": self.path, "b": body}, ensure_ascii=False) + "\n")
    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}
    def do_GET(self):
        p = self.path
        if p.startswith("/open-apis/"):
            if os.path.isfile(ERR):
                self._send({"code": 99999, "msg": "stub-injected-error"}); return
            if "/records" in p:
                tid = p.split("/tables/")[1].split("/")[0]
                self._send({"code": 0, "data": {"items": rd(recs_file(tid), []), "has_more": False}}); return
            self._send({"code": 0, "data": {"items": rd("tables.json", []), "has_more": False}}); return
        if "/commits/" in p and "/check-runs" in p:
            self._send(GH_CHECKS); return
        if "/issues" in p:
            self._send(GH_ISSUES if "/Cloudbird-Software/.github/" in p else []); return
        if "/pulls" in p:
            self._send(GH_PRS if "/Cloudbird-Software/.github/" in p else []); return
        self._send([])
    def do_POST(self):
        p, body = self.path, self._body()
        if p.startswith("/open-apis/auth/"):
            self._send({"code": 0, "tenant_access_token": "t-stub", "expire": 7200}); return
        if os.path.isfile(ERR):
            self._send({"code": 99999, "msg": "stub-injected-error"}); return
        self._cap("POST", body)
        if p.endswith("/tables"):
            tables = rd("tables.json", [])
            tid = f"tbl{len(tables) + 1}"
            tables.append({"table_id": tid, "name": (body.get("table") or {}).get("name")})
            wr("tables.json", tables)
            self._send({"code": 0, "data": {"table_id": tid}}); return
        if p.endswith("/batch_create"):
            tid = p.split("/tables/")[1].split("/")[0]
            recs = rd(recs_file(tid), [])
            for r in body["records"]:
                recs.append({"record_id": f"rec{len(recs) + 1}", "fields": r["fields"]})
            wr(recs_file(tid), recs)
            self._send({"code": 0, "data": {}}); return
        self._send({"code": 0, "data": {}})
    def do_PUT(self):
        p, body = self.path, self._body()
        if os.path.isfile(ERR):
            self._send({"code": 99999, "msg": "stub-injected-error"}); return
        self._cap("PUT", body)
        if p.endswith("/batch_update"):
            tid = p.split("/tables/")[1].split("/")[0]
            recs = rd(recs_file(tid), [])
            for r in body["records"]:
                for e in recs:
                    if e["record_id"] == r["record_id"]:
                        e["fields"].update(r["fields"])
            wr(recs_file(tid), recs)
        self._send({"code": 0, "data": {}})
    def do_DELETE(self):
        p, body = self.path, self._body()
        if os.path.isfile(ERR):
            self._send({"code": 99999, "msg": "stub-injected-error"}); return
        self._cap("DELETE", body)
        if "/records/batch_delete" in p:
            tid = p.split("/tables/")[1].split("/")[0]
            recs = [e for e in rd(recs_file(tid), []) if e["record_id"] not in body["records"]]
            wr(recs_file(tid), recs)
        else:  # 删表
            tid = p.split("/tables/")[1].split("/")[0]
            tables = [t for t in rd("tables.json", []) if t["table_id"] != tid]
            wr("tables.json", tables)
        self._send({"code": 0, "data": {}})
port_file = os.path.join(TMP, "port")
srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
open(port_file, "w").write(str(srv.server_address[1]))
srv.serve_forever()
STUBEOF
python3 "$TMP/stub.py" "$TMP" & STUB_PID=$!
for _ in $(seq 1 50); do [[ -s "$TMP/port" ]] && break; sleep 0.1; done
PORT=$(cat "$TMP/port")
BASE="http://127.0.0.1:$PORT"
FSHADOW="$TMP/feishu/shadow-evidence.jsonl"
run_sync() {  # run_sync [额外参数...] → stdout/stderr 落 $TMP/run.out
  BUTLER_SHADOW_FILE="$FSHADOW" BUTLER_TENANT=cloudbird-internal \
  GH_TOKEN=stub GH_API_BASE="$BASE" FEISHU_API_BASE="$BASE" \
  FEISHU_APP_ID=ci_app FEISHU_APP_SECRET=ci_secret FEISHU_BITABLE_APP_TOKEN=appSTUB \
    $FSYNC "$@" >"$TMP/run.out" 2>"$TMP/run.err"
}

# e2e-1 首轮：空表 → 建表 + 两行（batch_create 字段断言）+ 审计/影子
run_sync; RC=$?
[[ $RC -eq 0 ]] && pass "e2e 首轮同步 exit 0" || fail "e2e 首轮 exit=$RC $(tail -3 "$TMP/run.err")"
C1=$(grep -c '"m": "POST", "p": "/open-apis/bitable/v1/apps/appSTUB/tables"' "$CAP")
[[ $C1 -eq 1 ]] && pass "e2e 表幂等创建（1 次 POST /tables）" || fail "e2e 建表次数=$C1"
python3 - "$CAP" <<'PYEOF' && pass "e2e batch_create 两行·卡 ID/关卡状态/AC 进度字段断言" || fail "e2e batch_create 字段"
import json, sys
caps = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
creates = [c for c in caps if c["p"].endswith("/records/batch_create")]
assert len(creates) == 1 and len(creates[0]["b"]["records"]) == 2, creates
f = {r["fields"]["卡 ID"]: r["fields"] for r in creates[0]["b"]["records"]}
assert f[".github#416"]["State"] == "in-progress" and f[".github#416"]["关卡状态"] == "绿"
assert f[".github#416"]["AC 进度"] == "1/2" and f[".github#416"]["认领者"] == "randypanding"
assert f[".github#417"]["State"] == "ready" and f[".github#417"]["关卡状态"] == "无 PR"
print("OK")
PYEOF
grep -q '^AUDIT | butler=feishu-sync' "$TMP/run.out" && pass "e2e AUDIT 行（butler=feishu-sync）" || fail "AUDIT 行缺失"
python3 - "$DIR" "$FSHADOW" <<'PYEOF' && pass "e2e schema v1 影子落盘+验链绿+api_calls 计数" || fail "e2e 影子/验链"
import json, os, sys
sys.path.insert(0, f"{sys.argv[1]}/governance")
import evidence_shadow
lines = evidence_shadow.read_lines(sys.argv[2])
assert len(lines) == 1, lines
rec = json.loads(lines[0])
assert rec["action"] == "butler-feishu-sync" and rec["verdict"] == "ok", rec
payload = json.loads(rec["payload"])
assert payload["api_calls"]["GET /open-apis/bitable/v1/apps/{app}/tables"] >= 1, payload
assert payload["api_calls"]["POST /open-apis/bitable/v1/apps/{app}/tables/{tbl}/records/batch_create"] == 1, payload
assert rec["subject"]["tenant"] == "cloudbird-internal", rec
assert not evidence_shadow.verify_file(sys.argv[2]), "链断"
print("OK")
PYEOF

# e2e-2 二轮：人工改 State（.github#416 → done）+ 孤儿行注入 → 纠正+删除+报警
python3 - "$TMP/ctrl/records-tbl1.json" <<'PYEOF'
import json, sys
recs = json.load(open(sys.argv[1], encoding="utf-8"))
for r in recs:  # 人工违规：#416 State 改 done、#417 认领者乱填
    if r["fields"].get("卡 ID") == ".github#416": r["fields"]["State"] = "done"
    if r["fields"].get("卡 ID") == ".github#417": r["fields"]["认领者"] = "human-typo"
recs.append({"record_id": "rec9", "fields": {"卡 ID": ".github#999", "停留天数": 99}})
json.dump(recs, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PYEOF
: > "$CAP"
run_sync; RC=$?
[[ $RC -eq 0 ]] && pass "e2e 二轮纠正 exit 0" || fail "e2e 二轮 exit=$RC"
grep -q "WARN feishu-drift .github#416: State 表='done'" "$TMP/run.out" \
  && grep -q 'WARN feishu-drift .github#417: 认领者' "$TMP/run.out" \
  && pass "INV-05 漂移告警（State+认领者人工改动）" || fail "漂移告警缺失"
python3 - "$CAP" <<'PYEOF' && pass "e2e 纠正写回（batch_update State/认领者 + batch_delete 孤儿）" || fail "e2e 纠正写"
import json, sys
caps = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
upd = next((c for c in caps if c["p"].endswith("/records/batch_update")), None)
dele = next((c for c in caps if c["p"].endswith("/records/batch_delete")), None)
assert upd and dele, caps
byrec = {r["record_id"]: r["fields"] for r in upd["b"]["records"]}
# rec1=#416（State 纠正）、rec2=#417（认领者纠正为空——空值归一不落写时 diff 为 ""，仍需下发）
assert byrec.get("rec1", {}).get("State") == "in-progress", upd
assert "认领者" in byrec.get("rec2", {}), upd
assert dele["b"]["records"] == ["rec9"], dele
print("OK")
PYEOF

# e2e-3 --verify 只读对账：漂移态 → exit 3 且零写（fail-closed：不收敛=红）
: > "$CAP"
python3 - "$TMP/ctrl/records-tbl1.json" <<'PYEOF'
import json, sys
recs = json.load(open(sys.argv[1], encoding="utf-8"))
for r in recs:
    if r["fields"].get("卡 ID") == ".github#416": r["fields"]["State"] = "done"
json.dump(recs, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PYEOF
run_sync --verify; RC=$?
NOWRITES=$(grep -cE '"m": "(POST|PUT|DELETE)"' "$CAP")
[[ $RC -eq 3 && "$NOWRITES" -eq 0 ]] && pass "AC-7b --verify 只读：未收敛=exit 3 且零写" || fail "--verify（rc=$RC 写=$NOWRITES）"

# e2e-4 收敛态 --verify → 0
run_sync >/dev/null 2>&1
run_sync --verify; RC=$?
[[ $RC -eq 0 ]] && pass "--verify 收敛态 exit 0" || fail "--verify 收敛 rc=$RC"

# e2e-5 --drop：删表后同轮重建（BEH-06 单轮重建语义）
: > "$CAP"
run_sync --drop; RC=$?
DROPS=$(grep -c '"m": "DELETE", "p": "/open-apis/bitable/v1/apps/appSTUB/tables/tbl' "$CAP")
[[ $RC -eq 0 && "$DROPS" -ge 1 ]] && pass "--drop 删表+单轮重建 exit 0" || fail "--drop（rc=$RC drops=$DROPS）"
run_sync --verify; RC=$?
[[ $RC -eq 0 ]] && pass "--drop 重建后 --verify 收敛（字段一致）" || fail "--drop 重建后未收敛 rc=$RC"

# ---- 负向/守卫 ----
out=$(FEISHU_SYNC_DISABLED=1 GH_TOKEN=x FEISHU_APP_ID=a FEISHU_APP_SECRET=s FEISHU_BITABLE_APP_TOKEN=t \
  BUTLER_SHADOW_FILE="$FSHADOW" $FSYNC 2>&1); RC=$?
[[ $RC -eq 0 && "$out" == *投影停用* ]] && pass "AC-7b 停用守卫=skipped 绿" || fail "停用守卫 rc=$RC"
out=$(GH_TOKEN=x BUTLER_SHADOW_FILE="$FSHADOW" $FSYNC 2>&1); RC=$?
[[ $RC -eq 0 && "$out" == *未配置* ]] && pass "凭据缺席=skipped 绿（过渡期）" || fail "凭据守卫 rc=$RC"
GH_TOKEN= GH_API_BASE="$BASE" FEISHU_API_BASE="$BASE" FEISHU_APP_ID=a FEISHU_APP_SECRET=s \
  FEISHU_BITABLE_APP_TOKEN=t BUTLER_SHADOW_FILE="$FSHADOW" $FSYNC >/dev/null 2>&1
[[ $? -eq 2 ]] && pass "GH_TOKEN 缺失=exit 2（label 真源不可缺席）" || fail "GH_TOKEN 守卫"
touch "$TMP/feishu-error"
run_sync >/dev/null 2>&1
[[ $? -eq 2 ]] && pass "飞书 API 故障=exit 2（fail-closed 方向）" || fail "API 故障未红"
rm -f "$TMP/feishu-error"

echo "----------------------------------------"
if [[ $FAILS -eq 0 ]]; then echo "test-feishu-sync: PASS"; exit 0; fi
echo "test-feishu-sync: $FAILS 处失败"; exit 1
