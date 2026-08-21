#!/usr/bin/env bash
# test-ir0002.sh —— IR-0002 §12 (a)/(b) 缺失形态分类器自测（.github #143 收口件）
#
# 从 drift-check.sh 按 @ir0002-s12-classify 标记对提取 s12_classify 函数体（不复制
# 实现——防"测试测的是影子"），用 fixture PR/时戳数据断言四种形态：
#   (a)-1  org-gate 生效后无 PR 活动        → OK 待接入（非漂移）
#   (a)-2  无 PR 仓 degenerate 采样（非 org-gate check）→ OK 待接入
#   (b)    生效后有已完结 PR head 缺 check   → DRIFT 裸奔窗口（检出灵敏度不降级）
#   (b)-边界 生效前 PR 不构成"接入后消失"证据 → OK 待接入（时戳门生效）
#   fail-closed 查询失败                    → DRIFT fail-closed
# 红→绿记录：fixture (b) 为构造的"接入后消失"形态（曾有 PR、head 无 check run），
# 断言 drift() 报警含"裸奔窗口"——INV-4（不降低 (b) 检出）的机器证据。
# 用法：bash governance/tests/test-ir0002.sh（零网络依赖；需 jq）
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

# --- 提取被测函数（标记对缺失=fail-closed：测试与实现脱钩即红） ---
SRC="$DIR/drift-check.sh"
[[ -f "$SRC" ]] || { echo "FATAL: drift-check.sh 不存在"; exit 2; }
EXTRACTED=$(awk '/@ir0002-s12-classify-begin/{f=1} f{print} /@ir0002-s12-classify-end/{exit}' "$SRC")
if ! grep -q '^s12_classify()' <<<"$EXTRACTED"; then
  echo "FATAL: 标记对内未找到 s12_classify 定义（提取失效——实现与测试脱钩）"; exit 2
fi

# --- 桩：drift/ok 捕获输出（计数语义与主脚本一致） ---
DRIFTS=0
drift(){ echo "DRIFT $1"; DRIFTS=$((DRIFTS+1)); }
ok()   { echo "OK    $1"; }

eval "$EXTRACTED"

EFF="2026-08-20T07:43:21Z"   # 与主脚本 ORG_GATE_EFFECTIVE 同款时戳（fixture 自洽即可）
PRS_EMPTY='[]'
PRS_POST_EFF='[{"number":1,"state":"open","merged_at":null,"updated_at":"2026-08-21T10:00:00Z","head":{"sha":"aaa"}}]'
PRS_PRE_EFF='[{"number":1,"state":"open","merged_at":null,"updated_at":"2026-08-19T10:00:00Z","head":{"sha":"bbb"}}]'

run_case() {  # run_case <期望rc> <名> args...
  local want_rc="$1" name="$2"; shift 2
  local out rc=0
  out=$(s12_classify "$@") || rc=$?
  if [[ $rc -ne $want_rc ]]; then
    fail "$name：rc=$rc 期望=$want_rc（输出：$out）"; return
  fi
  LAST_OUT="$out"; LAST_RC="$rc"; LAST_NDRIFT=$(grep -c '^DRIFT' <<<"$out" || true)
}

# (a)-1：org-gate + 生效后零 PR 活动 → rc=0，OK 行含"待接入"，零 drift
run_case 0 "(a)-1 org-gate 生效后无 PR 活动" \
  demo-repo org-gate 0 0 "$PRS_EMPTY" "$EFF" 3
if grep -q "待接入" <<<"$LAST_OUT" && [[ $LAST_NDRIFT -eq 0 ]]; then
  pass "(a)-1 归待接入（非漂移）：$LAST_OUT"
else fail "(a)-1 应 OK 待接入且零 drift，得到：$LAST_OUT / drifts=$LAST_NDRIFT"; fi

# (a)-2：非 org-gate check + degenerate 采样（HAS_PR_ACTIVITY=0）→ rc=0 待接入
run_case 0 "(a)-2 degenerate 采样非 org-gate" \
  demo-repo some-local-gate 0 0 "$PRS_EMPTY" "$EFF" 1
if grep -q "待接入" <<<"$LAST_OUT" && [[ $LAST_NDRIFT -eq 0 ]]; then
  pass "(a)-2 degenerate 归待接入：$LAST_OUT"
else fail "(a)-2 应 OK 待接入，得到：$LAST_OUT / drifts=$LAST_NDRIFT"; fi

# (b)：生效后有 PR 活动但已完结 head 缺 check → rc=1，drift 含"裸奔窗口"
run_case 1 "(b) 生效后 PR head 缺失" \
  demo-repo org-gate 0 1 "$PRS_POST_EFF" "$EFF" 3
if [[ $LAST_NDRIFT -eq 1 ]] && echo "$LAST_OUT" | grep -q "裸奔窗口"; then
  pass "(b) 报警不降级：$LAST_OUT"
else fail "(b) 应 drift 裸奔窗口，得到：$LAST_OUT / drifts=$LAST_NDRIFT"; fi

# (b)-边界：仅生效前的 PR（updated_at < 生效时戳）→ 不构成接入后消失证据，rc=0 待接入
run_case 0 "(b)-边界 生效前 PR 不算 (b)" \
  demo-repo org-gate 0 1 "$PRS_PRE_EFF" "$EFF" 3
if [[ $LAST_NDRIFT -eq 0 ]] && grep -q "待接入" <<<"$LAST_OUT"; then
  pass "(b)-边界 生效前活动归 (a)：$LAST_OUT"
else fail "(b)-边界 应 OK 待接入，得到：$LAST_OUT / drifts=$LAST_NDRIFT"; fi

# fail-closed：查询失败 → rc=2，drift 含 fail-closed
run_case 2 "fail-closed 查询失败" \
  demo-repo org-gate 1 1 "$PRS_POST_EFF" "$EFF" 3
if [[ $LAST_NDRIFT -eq 1 ]] && echo "$LAST_OUT" | grep -q "fail-closed"; then
  pass "fail-closed 报警：$LAST_OUT"
else fail "fail-closed 应 drift，得到：$LAST_OUT / drifts=$LAST_NDRIFT"; fi

if [[ $FAILS -gt 0 ]]; then
  echo "== test-ir0002：$FAILS 项失败 =="
  exit 1
fi
echo "== test-ir0002：5/5 通过（(a) 归待接入 / (b) 检出不降级 / fail-closed 语义保持）=="
