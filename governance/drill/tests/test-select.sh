#!/usr/bin/env bash
# test-select.sh —— 选样随机性自测（W4-C4）：seed 可注入（确定性复盘）+ 目标池约束
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
PYTHON="$(pick_py)" || { echo "::error::无可用 python（含 pyyaml）"; exit 2; }
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

sel() { "$PYTHON" "$ROOT/drill.py" select --samples "$ROOT/samples/registry.yaml" \
          --repos "$ROOT/../REPOS.yaml" "$@"; }

echo "== 1) 同 seed 确定性（随机可注入=可复盘可审计）"
sel --seed 20260822 > "$TMP/a.json"; sel --seed 20260822 > "$TMP/b.json"
if cmp -s "$TMP/a.json" "$TMP/b.json"; then PASS=$((PASS+1)); echo "ok   同 seed 输出一致"
else FAIL=$((FAIL+1)); echo "FAIL 同 seed 输出漂移"; cat "$TMP/a.json" "$TMP/b.json"; fi

echo "== 2) 目标池约束（holdout 永不入池；github-scope 样本只打治理总仓）"
BAD=0
for s in 1 2 3 5 8 13 21 34 55; do
  R=$(sel --seed "$s" | "$PYTHON" -c 'import json,sys;print(json.load(sys.stdin)["target_repo"])')
  [[ "$R" == "holdout" ]] && { echo "FAIL seed=$s 选中 holdout（隔离面污染）"; BAD=1; }
done
[[ $BAD -eq 0 ]] && { PASS=$((PASS+1)); echo "ok   多 seed 采样 holdout 零命中（owner 直管封存面隔离）"; } || FAIL=$((FAIL+1))

G=$(sel --seed 7 --sample-id gate-yaml-parse-corrupt | "$PYTHON" -c 'import json,sys;print(json.load(sys.stdin)["target_repo"])')
[[ "$G" == ".github" ]] && { PASS=$((PASS+1)); echo "ok   github-scope 样本固定目标=.github"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL github-scope 样本目标=$G"; }

echo "== 3) 固定样本/目标（首演与复盘通道）"
O=$(sel --seed 99 --sample-id hygiene-gitleaks-aws-key --target-repo .github)
echo "$O" | grep -q '"sample_id": "hygiene-gitleaks-aws-key"' && echo "$O" | grep -q '"target_repo": ".github"' \
  && { PASS=$((PASS+1)); echo "ok   --sample-id/--target-repo 钉选生效"; } \
  || { FAIL=$((FAIL+1)); echo "FAIL 钉选失效: $O"; }

echo "== 4) 选样输出字段完整（AC-2 关卡 ID + AC-4 难度随记录可溯）"
sel --seed 3 | "$PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert d["sample_id"] and d["gate"] and d["difficulty"] in ("easy", "medium", "hard") and d["target_repo"], d
' && { PASS=$((PASS+1)); echo "ok   字段齐全"; } || { FAIL=$((FAIL+1)); echo "FAIL 字段缺失"; }

echo "== 5) 非法钉选被拒（fail-closed，不静默回退随机）"
sel --seed 1 --sample-id no-such-sample >/dev/null 2>&1; [[ $? -ne 0 ]] \
  && { PASS=$((PASS+1)); echo "ok   未知样本 id 非零退出"; } || { FAIL=$((FAIL+1)); echo "FAIL 未知样本被放行"; }

echo "选样自测: pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
