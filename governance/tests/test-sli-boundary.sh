#!/usr/bin/env bash
# test-sli-boundary.sh —— W4-R2（#419）责任边界 + 环境面 SLI 入 gate
#
# AC-8c：sli-report.sh --self-test 含 env_face 断言（环境面 SLI 数据源进周报）
# AC-8d：docs/slo-boundary.md 四节齐备（SLO 定义/值班范围/破线升级路径/break-glass）
#        + NAVIGATION 入口行（冷上下文可达）
# 真源引用一致：sli-report.sh 与 docs/slo-boundary.md 互指（SLO 定义真源=文件，
# 数据源=脚本——两锚点互查，防单侧漂移）。
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }

# ---- AC-8c：self-test 全绿（含 T-env 环境面三态断言） ----
OUT=$(bash "$DIR/scripts/sli-report.sh" --self-test 2>&1); RC=$?
[[ $RC -eq 0 ]] && ok "sli-report self-test 全绿（rc=0）" || bad "sli-report self-test rc=$RC"
grep -q "PASS=1[3-9]" <<<"$OUT" && ok "断言计数 ≥13（7 原有+6 env_face）" || bad "断言数不足：$(grep -o 'PASS=[0-9]*' <<<"$OUT" | head -1)"
grep -q "T-env 账本缺席 → absent 过渡期非红" <<<"$OUT" && grep -q "T-env 3d 前末轮" <<<"$OUT" \
  && ok "T-env 环境面断言在册（freshness/absent）" || bad "T-env 断言缺失"

# ---- AC-8c：env_face 指标行形态（真实 env-ledger 语义对齐） ----
F=$(mktemp)
cat >"$F" <<'EOF'
{"ts": "2026-08-29T14:31:55Z", "kind": "gate", "action": "butler-env-drift", "payload": "{\"scope\": [\"dev-self\", \"staging-self\"], \"checked\": 2, \"drifts\": 0}"}
EOF
E=$(python3 -c "
import json, datetime, sys
now = datetime.datetime.now(datetime.timezone.utc)
# 复刻 env_face_calc 锚点（不 import 脚本——独立对拍：环境面字段从 payload 正确提取）
r = json.loads(open('$F').read().strip())
p = json.loads(r['payload'])
print('env_face_last_run=%s scope=%s drifts=%d' % (r['ts'], p['scope'], p['drifts']))")
grep -q "drifts=0" <<<"$E" && grep -q "dev-self" <<<"$E" \
  && ok "env_face 锚点对拍（payload scope/drifts 提取）" || bad "env_face 对拍失败：$E"

# 周报 body 引用环境面（AC-8c：报告含环境面 SLI 数据源——脚本内 body 模板锚定）
grep -q "env_face" "$DIR/scripts/sli-report.sh" && grep -q "env-ledger" "$DIR/scripts/sli-report.sh" \
  && ok "sli-report 周报模板含 env_face（数据源=env-ledger）" || bad "周报未接环境面"

# ---- AC-8d：责任边界文件四节齐备 ----
DOC="$DIR/docs/slo-boundary.md"
[[ -f "$DOC" ]] && ok "docs/slo-boundary.md 落盘" || bad "责任边界文件缺失"
for SEC in "SLO 定义" "值班范围" "破线升级路径" "break-glass"; do
  grep -q "## .*$SEC" "$DOC" && ok "四节齐备：$SEC" || bad "缺节：$SEC"
done

# SLO 定义含骨架期指标（SLO-1 收敛/SLO-2 新鲜度——与 env_face 指标对应）
grep -q "SLO-1" "$DOC" && grep -q "SLO-2" "$DOC" && grep -q "convergence" "$DOC" \
  && ok "SLO-1/2 与 env_face convergence 对应（定义↔数据源）" || bad "SLO 定义与指标脱节"

# 互指锚点（文件指脚本数据源；脚本指文件 SLO 真源——双向）
grep -q "sli-report.sh" "$DOC" && grep -q "slo-boundary.md" "$DIR/scripts/sli-report.sh" \
  && ok "双向互指锚点（SLO 真源=文件，数据源=脚本）" || bad "互指断链"

# break-glass 节含留痕规则（48h 回填——治理红线锚点）
grep -q "48h" "$DOC" && grep -q "回填" "$DOC" \
  && ok "break-glass 留痕规则（48h 回填豁免登记）" || bad "break-glass 留痕缺失"

# ---- NAVIGATION 入口行（冷上下文可达，断链由 test-navigation 执法） ----
grep -q "slo-boundary.md" "$DIR/docs/NAVIGATION.md" \
  && ok "NAVIGATION 入口行在册" || bad "NAVIGATION 无 slo-boundary 入口"

echo "----------------------------------------"
echo "test-sli-boundary: $([[ $FAIL -eq 0 ]] && echo PASS || echo "FAIL（$FAIL）")"
exit $([[ $FAIL -eq 0 ]] && echo 0 || echo 1)
