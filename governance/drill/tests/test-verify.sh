#!/usr/bin/env bash
# test-verify.sh —— 红绿判定断言自测（W4-C4 AC-1 判定核）：离线注入 check-runs，
# 红=演习成功(0) / 绿=演习失败(1) / 中间态(3)——"没看到"绝不装绿。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
PYTHON="$(pick_py)" || { echo "::error::无可用 python（含 pyyaml）"; exit 2; }
export DRILL_VERIFY_GRACE_S=0 # 静默期压零——离线模式立即判定（默认 120s 仅在线用）
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

vf() { "$PYTHON" "$ROOT/verify_gate.py" --repo dot --sha deadbeef "$@"; }
verdict_of() { "$PYTHON" -c 'import json,sys;print(json.load(sys.stdin)["verdict"])'; }

mkcr() { printf '{"check_runs": [%s]}' "$1" > "$TMP/$2"; }

echo "== 1) 红=演习成功（关卡 conclusion=failure → 退出码 0）"
mkcr '{"name":"org-hygiene","status":"completed","conclusion":"failure"}' red.json
OUT=$(vf --gate org-hygiene --checkruns-file "$TMP/red.json"); RC=$?
V=$(verdict_of <<<"$OUT")
if [[ "$V" == "RED" && $RC -eq 0 ]]; then PASS=$((PASS+1)); echo "ok   failure→RED/exit0"
else FAIL=$((FAIL+1)); echo "FAIL 期望 RED/0 实得 $V/$RC"; fi

echo "== 2) 绿=演习失败（关卡 success → 退出码 1，绝不装绿）"
mkcr '{"name":"org-hygiene","status":"completed","conclusion":"success"}' green.json
OUT=$(vf --gate org-hygiene --checkruns-file "$TMP/green.json"); RC=$?
V=$(verdict_of <<<"$OUT")
if [[ "$V" == "GREEN" && $RC -eq 1 ]]; then PASS=$((PASS+1)); echo "ok   success→GREEN/exit1"
else FAIL=$((FAIL+1)); echo "FAIL 期望 GREEN/1 实得 $V/$RC"; fi

echo "== 3) NO-SURFACE（空 check 面=push 分支无 CI 局限，如实记录不装绿）"
mkcr '' empty.json
OUT=$(vf --gate org-hygiene --checkruns-file "$TMP/empty.json"); RC=$?
V=$(verdict_of <<<"$OUT")
if [[ "$V" == "NO-SURFACE" && $RC -eq 3 ]]; then PASS=$((PASS+1)); echo "ok   空→NO-SURFACE/exit3"
else FAIL=$((FAIL+1)); echo "FAIL 期望 NO-SURFACE/3 实得 $V/$RC"; fi

echo "== 4) MISSING-GATE（有别的 check、无目标关卡=名字漂移，不猜）"
mkcr '{"name":"lint","status":"completed","conclusion":"success"}' other.json
OUT=$(vf --gate org-hygiene --checkruns-file "$TMP/other.json"); RC=$?
V=$(verdict_of <<<"$OUT")
if [[ "$V" == "MISSING-GATE" && $RC -eq 3 ]]; then PASS=$((PASS+1)); echo "ok   缺关卡→MISSING-GATE/exit3"
else FAIL=$((FAIL+1)); echo "FAIL 期望 MISSING-GATE/3 实得 $V/$RC"; fi

echo "== 5) 子串唯一兜底 + 进行中不算结论（等不到=TIMEOUT）"
mkcr '{"name":"org-hygiene / gitleaks","status":"completed","conclusion":"failure"}' substr.json
OUT=$(vf --gate gitleaks --checkruns-file "$TMP/substr.json"); RC=$?
V=$(verdict_of <<<"$OUT")
[[ "$V" == "RED" && $RC -eq 0 ]] && { PASS=$((PASS+1)); echo "ok   精确名缺席时子串唯一命中"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 子串匹配: $V/$RC"; }
mkcr '{"name":"org-hygiene","status":"in_progress","conclusion":null}' wip.json
OUT=$(vf --gate org-hygiene --checkruns-file "$TMP/wip.json" --timeout 0); RC=$?
V=$(verdict_of <<<"$OUT")
[[ "$V" == "TIMEOUT" && $RC -eq 3 ]] && { PASS=$((PASS+1)); echo "ok   in_progress 不判结论→TIMEOUT"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 进行中语义: $V/$RC"; }

echo "== 6) 歧义子串不猜（两个候选=MISSING-GATE）"
mkcr '{"name":"org-hygiene-a","status":"completed","conclusion":"failure"},{"name":"org-hygiene-b","status":"completed","conclusion":"failure"}' amb.json
OUT=$(vf --gate org-hygiene --checkruns-file "$TMP/amb.json"); RC=$?
V=$(verdict_of <<<"$OUT")
[[ "$V" == "MISSING-GATE" ]] && { PASS=$((PASS+1)); echo "ok   歧义拒绝猜测"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 歧义应 MISSING-GATE 实得 $V"; }

echo "== 7) API 模式无凭据 fail-closed（不静默跳过）"
unset GH_TOKEN || true
vf --gate org-hygiene >/dev/null 2>&1; RC=$?
[[ $RC -eq 2 ]] && { PASS=$((PASS+1)); echo "ok   无 GH_TOKEN 拒跑（exit2）"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 无凭据 rc=$RC"; }

echo "验证核自测: pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
