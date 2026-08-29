#!/usr/bin/env bash
# test-env-drift.sh —— 环境对账引擎自测（IR-0006 W4-R1 / 卡 #418）
#
# 覆盖（卡 AC 对应，全部离线——ENV_DEFS_DIR 目录注入，不 clone）：
#   AC-8a plan_check/diff_env 纯函数：深 diff（嵌套/列表/缺失）/owner-fill 跳过/
#        快照缺失=漂移；e2e 基线零漂移 exit 0→篡改 DRIFT exit 1→消除回绿
#   AC-8b scope 旋钮：prod 环境文件在场=SKIP 行不对账（检测面边界断言）
#   审计：AUDIT 行（butler=env-drift）+ schema v1 影子落盘（BUTLER_SHADOW_FILE 注入）
#   负向：GH_TOKEN 缺失且无注入=exit 2；policy 缺 scope=exit 2
# 用法: bash governance/tests/test-env-drift.sh（gate.yml 自动纳入）
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
EDRIFT="python3 $DIR/governance/env-drift.py"

# ---- 纯函数区（diff_env / plan_check） ----
python3 - "$DIR" <<'PYEOF' && pass "diff_env/plan_sync 纯函数六断言（深 diff/列表/缺失/骨架跳过/scope/prod 排除）" || fail "纯函数"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("env_drift", f"{sys.argv[1]}/governance/env-drift.py")
ed = importlib.util.module_from_spec(spec); spec.loader.exec_module(ed)

# 1) 深 diff：嵌套字段偏差定位到路径
d = ed.diff_env({"topology": {"anchor": "public-server", "workers": ["pool-a"]}},
                {"topology": {"anchor": "public-server", "workers": ["pool-b"]}})
assert d == [("topology.workers[0]", "pool-a", "pool-b")], d
# 2) 列表长度差=整体漂移行
d = ed.diff_env({"network": {"egress_allowlist": ["a", "b"]}},
                {"network": {"egress_allowlist": ["a"]}})
assert len(d) == 1 and d[0][0] == "network.egress_allowlist", d
# 3) 实况缺失字段
d = ed.diff_env({"tenants": ["cloudbird"]}, {})
assert d == [("tenants", ["cloudbird"], None)], d
# 4) owner-fill 骨架值跳过（期望未填≠漂移）
d = ed.diff_env({"images": {"runtime": "owner-fill（digest）"}}, {"images": {"runtime": None}})
assert d == [], d
# 5) plan_check：快照缺失=漂移；scope 内核对账
p = ed.plan_check({"dev-self": {"a": 1}}, {}, ["dev-self"])
assert p["drifts"] == [("dev-self", "(report)", "实况快照缺失", None)] and p["checked"] == ["dev-self"], p
# 6) prod 排除：scope 外 SKIP（AC-8b——检测面边界）
p = ed.plan_check({"dev-self": {"a": 1}, "prod-self": {"a": 1}}, {"dev-self": {"a": 1}}, ["dev-self"])
assert p["drifts"] == [] and p["skipped"] == ["prod-self"], p
print("OK")
PYEOF

# ---- e2e fixture：本地 env-defs 目录（ENV_DEFS_DIR 注入，零 clone） ----
mk_fixture() {  # mk_fixture <dir>
  mkdir -p "$1/environments" "$1/reports"
  cat >"$1/environments/dev-self.yaml" <<'EOF'
version: 1
name: dev-self
topology:
  anchor: public-server
  workers:
    - cloud-desktop-pool
  secret_store: vault
images:
  runtime: owner-fill（digest）
network:
  egress_allowlist:
    - api.github.com
  ingress: none
resources:
  worker_count: 2
EOF
  cat >"$1/environments/staging-self.yaml" <<'EOF'
version: 1
name: staging-self
topology:
  anchor: public-server
  workers:
    - cloud-desktop-pool
EOF
  cat >"$1/environments/prod-self.yaml" <<'EOF'
version: 1
name: prod-self
topology:
  anchor: public-server
EOF
}
SHADOW="$TMP/env-shadow.jsonl"
run_ed() {  # run_ed <dir> [env...] → stdout 落 $TMP/out
  BUTLER_SHADOW_FILE="$SHADOW" BUTLER_TENANT=cloudbird-internal \
  ENV_DEFS_DIR="$1" python3 "$DIR/governance/env-drift.py" >"$TMP/out" 2>"$TMP/err"; return $?
}
# 实况快照=期望态基线（骨架期零漂移）+ 上报元数据（不对账面）
mk_snapshot() {  # mk_snapshot <dir> <env>：期望态复制为实况 + 元数据头
  python3 - "$1" "$2" <<'PYEOF'
import sys, yaml
envdir, env = sys.argv[1], sys.argv[2]
want = yaml.safe_load(open(f"{envdir}/environments/{env}.yaml", encoding="utf-8"))
rep = dict(want)
rep["reported_by"] = "env-reporter-stub"
rep["reported_at"] = "2026-08-29T00:00:00Z"
yaml.safe_dump(rep, open(f"{envdir}/reports/{env}.yaml", "w", encoding="utf-8"),
               allow_unicode=True, sort_keys=False)
PYEOF
}
FIX="$TMP/envdefs"; mk_fixture "$FIX"
mk_snapshot "$FIX" dev-self
mk_snapshot "$FIX" staging-self

# ---- e2e-1 基线：零漂移 exit 0（skip prod）
run_ed "$FIX"; RC=$?
[[ $RC -eq 0 ]] && pass "e2e 基线零漂移 exit 0" || fail "基线 exit=$RC $(cat "$TMP/err")"
grep -q 'SKIP  prod-self' "$TMP/out" && pass "AC-8b prod SKIP 行（scope 外不对账）" || fail "prod SKIP 缺失"
grep -q '检测面 scope=' "$TMP/out" && pass "scope 断言入对账日志" || fail "scope 断言缺失"
grep -q '^AUDIT | butler=env-drift' "$TMP/out" && pass "AUDIT 行（butler=env-drift）" || fail "AUDIT 行缺失"

# ---- e2e-2 注入偏差：DRIFT exit 1 + 偏差面行 ----
python3 - "$FIX" <<'PYEOF'
import sys, yaml
envdir = sys.argv[1]
rep = yaml.safe_load(open(f"{envdir}/reports/dev-self.yaml", encoding="utf-8"))
rep["topology"]["workers"] = ["wrong-worker"]      # 偏差面 1：worker 面
rep["resources"]["worker_count"] = 99               # 偏差面 2：资源面
yaml.safe_dump(rep, open(f"{envdir}/reports/dev-self.yaml", "w", encoding="utf-8"),
               allow_unicode=True, sort_keys=False)
PYEOF
run_ed "$FIX"; RC=$?
[[ $RC -eq 1 ]] && pass "e2e 偏差检出 exit 1（GM-1 报警面）" || fail "偏差 exit=$RC"
grep -q 'DRIFT dev-self topology.workers\[0\] 期望=.cloud-desktop-pool. 实况=.wrong-worker.' "$TMP/out" \
  && grep -q 'DRIFT dev-self resources.worker_count' "$TMP/out" \
  && pass "偏差面行（含 env+路径+期望/实况）" || fail "偏差面行缺失"

# ---- e2e-3 消除：改回实况 → exit 0（全链路闭环） ----
mk_snapshot "$FIX" dev-self
run_ed "$FIX"; RC=$?
[[ $RC -eq 0 ]] && pass "e2e 偏差消除回绿 exit 0（AC-8a 闭环）" || fail "消除后 exit=$RC"

# ---- 影子断言：3 轮（ok→drift-detected→ok）链式 + 验链 ----
python3 - "$DIR" "$SHADOW" <<'PYEOF' && pass "影子 3 轮链式落盘+验链绿+drifts 计数" || fail "影子/验链"
import json, os, sys
sys.path.insert(0, f"{sys.argv[1]}/governance")
import evidence_shadow
lines = evidence_shadow.read_lines(sys.argv[2])
assert len(lines) == 3, lines
v = [json.loads(l)["verdict"] for l in lines]
assert v == ["ok", "drift-detected", "ok"], v
assert not evidence_shadow.verify_file(sys.argv[2]), "链断"
rec = json.loads(lines[1])
p = json.loads(rec["payload"])
assert p["drifts"] == 2, p
print("OK")
PYEOF

# ---- 负向：GH_TOKEN 缺失且无注入=exit 2；policy 缺 scope=exit 2 ----
(unset GH_TOKEN GOVERNANCE_TOKEN; python3 "$DIR/governance/env-drift.py" >/dev/null 2>&1); RC=$?
[[ $RC -eq 2 ]] && pass "GH_TOKEN 缺失（无注入）=exit 2 fail-closed" || fail "GH_TOKEN 缺失 exit=$RC"
mkdir -p "$TMP/noscope"
printf 'scope: []\n' > "$TMP/noscope/env-drift.yaml"
BUTLER_POLICY="$TMP/noscope/env-drift.yaml" ENV_DEFS_DIR="$FIX" \
  python3 - >/dev/null 2>&1 <<'PYEOF'
import os, sys
sys.argv = ["env-drift.py"]
# policy 路径注入测试（缺 scope → FATAL exit 2）
PYEOF
sed "s|POLICY = .*|POLICY = '$TMP/noscope/env-drift.yaml'|" "$DIR/governance/env-drift.py" > "$TMP/ed-noscope.py"
BUTLER_SHADOW_FILE="$SHADOW" ENV_DEFS_DIR="$FIX" python3 "$TMP/ed-noscope.py" >/dev/null 2>&1; RC=$?
[[ $RC -eq 2 ]] && pass "policy 缺 scope=exit 2（旋钮不可空）" || fail "缺 scope exit=$RC"

echo "----------------------------------------"
if [[ $FAILS -eq 0 ]]; then echo "test-env-drift: PASS"; exit 0; fi
echo "test-env-drift: $FAILS 处失败"; exit 1
