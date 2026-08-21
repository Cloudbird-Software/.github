#!/usr/bin/env bash
# test-failclose.sh —— 缺席 fail-closed 演练 dry-run 断言自测（W4-C4 AC-3）
# 只跑 dry-run 路径（不动 org 真变量 AUTO_MERGE_DISABLED——真置位路径由季度
# 演练/显式 FAILCLOSE_DRY_RUN=0 承担，本测试永不触发）。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

run_fc() { env -u GH_TOKEN FAILCLOSE_STALE_HOURS=3 FAILCLOSE_DRY_RUN=1 bash "$ROOT/failclose-test.sh"; }

echo "== 1) dry-run 全链通过（谓词表 + 将要置位证据，不动真变量）"
OUT=$(run_fc | tee "$TMP/fc.log"); RC=${PIPESTATUS[0]}
[[ $RC -eq 0 ]] && grep -q "缺席超时.*trip\|→ trip" "$TMP/fc.log" \
  && { PASS=$((PASS+1)); echo "ok   谓词: 缺席超时→trip 判定在"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 谓词/退出码 rc=$RC"; }
grep -q "心跳 30min 前.*no-trip\|新鲜.*no-trip" "$TMP/fc.log" \
  && { PASS=$((PASS+1)); echo "ok   谓词: 新鲜心跳不误杀"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 新鲜心跳谓词"; }
grep -q "将要执行.*AUTO_MERGE_DISABLED\|将要执行" "$TMP/fc.log" \
  && { PASS=$((PASS+1)); echo "ok   dry-run 输出'将要置位'判定证据（凭据不足时的替代证据路径）"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL dry-run 证据行缺失"; }
grep -q "dry-run-pass" "$TMP/fc.log" \
  && { PASS=$((PASS+1)); echo "ok   AUDIT dry-run-pass 留痕"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL dry-run 审计行缺失"; }

echo "== 2) fail-closed 语义（真置位拒绝无凭据执行，不半演）"
OUT=$(env -u GH_TOKEN FAILCLOSE_DRY_RUN=0 bash "$ROOT/failclose-test.sh" 2>&1); RC=$?
if [[ $RC -eq 2 ]] && grep -q "真置位需 GH_TOKEN" <<<"$OUT"; then
  PASS=$((PASS+1)); echo "ok   真置位模式缺凭据→infra 拒绝（exit2）"
else FAIL=$((FAIL+1)); echo "FAIL 真置位无凭据 rc=$RC"; fi

echo "== 3) 阈值非法值被拒（真源防护）"
OUT=$(env -u GH_TOKEN FAILCLOSE_STALE_HOURS=abc FAILCLOSE_DRY_RUN=1 bash "$ROOT/failclose-test.sh" 2>&1); RC=$?
[[ $RC -eq 2 ]] && { PASS=$((PASS+1)); echo "ok   非数值阈值→exit2"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 非法阈值 rc=$RC"; }

echo "failclose 自测: pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
