#!/usr/bin/env bash
# test-samples.sh —— 样本库 schema 校验自测（W4-C4 AC-2）
# 校验逻辑与引擎共用同一实现（drill.py validate_samples）——防"测试过而引擎放行"分叉。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
PYTHON="$(pick_py)" || { echo "::error::无可用 python（含 pyyaml）"; exit 2; }
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

t() { # t <desc> <want: 0|非0> <cmd...>
  local desc="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1; local rc=$?
  if { [[ "$want" == "0" ]] && [[ $rc -eq 0 ]]; } || { [[ "$want" != "0" ]] && [[ $rc -ne 0 ]]; }; then
    PASS=$((PASS+1)); echo "ok   $desc"
  else FAIL=$((FAIL+1)); echo "FAIL $desc（rc=$rc 期望=$want）"; fi
}

# 经引擎同一校验器判合法/非法（decode 入口先 load_samples→validate_samples，
# 与 select/inject 共用——校验逻辑单一实现；fixture 样本统一 id=x-leak）
check() {
  "$PYTHON" "$ROOT/drill.py" decode --samples "$1" --id x-leak >/dev/null 2>&1
}

echo "== 1) 正式样本库合法（owner 审批/gate ID/难度/base64/{DATE} 全在）"
t "正式 registry.yaml 通过 schema 校验" 0 "$PYTHON" "$ROOT/drill.py" select --samples "$ROOT/samples/registry.yaml" --repos "$ROOT/../REPOS.yaml" --seed 1 --sample-id hygiene-gitleaks-aws-key --target-repo .github

echo "== 2) 破坏 fixture 逐项被拒（fail-closed：校验器不能只认存在性）"
mk() { printf '%s\n' "$2" > "$TMP/$1"; }
mk no_approval.yaml 'samples:
  - id: x-leak
    difficulty: easy
    gate: org-hygiene
    scope: org
    payload_kind: file
    payload_path: "drill/x-{DATE}.ini"
    defect_b64: aGVsbG8=
    pr_title_adr: true
    approval: {approved_by: someone-else, date: "2026-08-22"}'
t "审批人非 owner 被拒" 非0 check "$TMP/no_approval.yaml"
mk no_gate.yaml 'samples:
  - id: x-leak
    difficulty: easy
    scope: org
    payload_kind: file
    payload_path: "drill/x-{DATE}.ini"
    defect_b64: aGVsbG8=
    pr_title_adr: true
    approval: {approved_by: randypanding, date: "2026-08-22"}'
t "缺预期关卡 ID（gate）被拒" 非0 check "$TMP/no_gate.yaml"
mk bad_difficulty.yaml 'samples:
  - id: x-leak
    difficulty: trivial
    gate: org-hygiene
    scope: org
    payload_kind: file
    payload_path: "drill/x-{DATE}.ini"
    defect_b64: aGVsbG8=
    pr_title_adr: true
    approval: {approved_by: randypanding, date: "2026-08-22"}'
t "非法难度值被拒" 非0 check "$TMP/bad_difficulty.yaml"
mk bad_b64.yaml 'samples:
  - id: x-leak
    difficulty: easy
    gate: org-hygiene
    scope: org
    payload_kind: file
    payload_path: "drill/x-{DATE}.ini"
    defect_b64: "!!!不是base64!!!"
    pr_title_adr: true
    approval: {approved_by: randypanding, date: "2026-08-22"}'
t "defect_b64 非法 base64 被拒" 非0 check "$TMP/bad_b64.yaml"
mk no_date_placeholder.yaml 'samples:
  - id: x-leak
    difficulty: easy
    gate: org-hygiene
    scope: org
    payload_kind: file
    payload_path: "drill/x.ini"
    defect_b64: aGVsbG8=
    pr_title_adr: true
    approval: {approved_by: randypanding, date: "2026-08-22"}'
t "payload_path 缺 {DATE} 占位被拒" 非0 check "$TMP/no_date_placeholder.yaml"
mk dup_id.yaml 'samples:
  - {id: x-leak, difficulty: easy, gate: org-hygiene, scope: org, payload_kind: file, payload_path: "a/{DATE}", defect_b64: aGVsbG8=, pr_title_adr: true, approval: {approved_by: randypanding, date: "2026-08-22"}}
  - {id: x-leak, difficulty: easy, gate: org-hygiene, scope: org, payload_kind: file, payload_path: "b/{DATE}", defect_b64: aGVsbG8=, pr_title_adr: true, approval: {approved_by: randypanding, date: "2026-08-22"}}'
t "样本 id 重复被拒" 非0 check "$TMP/dup_id.yaml"
t "空样本库被拒" 非0 check /dev/null

echo "== 3) decode round-trip（owner 审阅通道可用；AC-2 审批前置能力）"
OUT=$("$PYTHON" "$ROOT/drill.py" decode --samples "$ROOT/samples/registry.yaml" --id hygiene-gitleaks-aws-key)
if grep -q "AKIA2N7QX9ZK4LMW8B3C" <<<"$OUT"; then PASS=$((PASS+1)); echo "ok   decode 输出含缺陷原文（可 owner 审）"
else FAIL=$((FAIL+1)); echo "FAIL decode 未还原缺陷内容"; fi
GEN=$("$PYTHON" "$ROOT/drill.py" decode --samples "$ROOT/samples/registry.yaml" --id hygiene-bigfile-blob)
if grep -q "生成物样本" <<<"$GEN"; then PASS=$((PASS+1)); echo "ok   generated 样本 decode 有诚实注记"
else FAIL=$((FAIL+1)); echo "FAIL generated 样本 decode 异常"; fi

echo "样本库自测: pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
