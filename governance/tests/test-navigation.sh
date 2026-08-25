#!/usr/bin/env bash
# test-navigation.sh —— 导航可达性自测（#363 / #362 审计收口）
#
# 治理可达性断裂曾是 #362 审计的核心发现（32 次 PM 模拟运行，置信度 4.8/10）：
# 被引用的导航文件不存在、入口面之间互相指空。本测试把「导航不变量」机械化为
# gate 关卡（断链即红，fail-closed 防回归）：
#   §A 全入口路由面存在且保留高频困惑锚点（g060 / C1 / drift-check / spec 位置）
#   §B AGENTS.md 契约：行数 ≤ 60（治理仓豁免上限）、入口协议块标记完整、索引可达
#   §C PLAYBOOK.md 契约：spec 位置规则、g060 路径、C1 runbook、路由回指
#   §D profile/README.md（org 首页）：指向路由表与 REPOS.yaml，不含已退役仓的活跃行
#   §E NAVIGATION.md 内的本仓 markdown 链接全部可解析（断链=红）
#   §F Makefile 暴露 drift-check 入口（C1 预检命令可发现性）
# 用法：bash governance/tests/test-navigation.sh（零网络）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }

cd "$ROOT"

# ---------- §A 全入口路由面 ----------
NAV="docs/NAVIGATION.md"
if [[ -s "$NAV" ]]; then pass "$NAV 存在且非空"; else fail "$NAV 缺失或为空（#363 复现面）"; fi
for anchor in "g060" "C1" "drift-check" "specs/IR-" "bug.yml" "intent.yml" "ghcb"; do
  if grep -q -- "$anchor" "$NAV" 2>/dev/null; then pass "NAVIGATION 锚点[$anchor] 在"; else fail "NAVIGATION 锚点[$anchor] 缺（高频困惑回归）"; fi
done

# ---------- §B AGENTS.md 契约 ----------
AG="AGENTS.md"
if [[ -s "$AG" ]]; then pass "$AG 存在"; else fail "$AG 缺失"; fi
LINES=$(wc -l < "$AG" 2>/dev/null || echo 999)
if (( LINES <= 60 )); then pass "AGENTS.md 行数 $LINES ≤ 60（治理仓豁免上限）"; else fail "AGENTS.md 行数 $LINES 超 60 上限"; fi
if grep -q '<!-- entry-protocol v[0-9]* -->' "$AG" && grep -q '<!-- /entry-protocol -->' "$AG"; then
  pass "入口协议块标记完整（drift §17 对账面）"
else
  fail "入口协议块标记缺失/不完整"
fi
grep -q "docs/NAVIGATION.md" "$AG" && pass "AGENTS.md 指向全入口路由表" || fail "AGENTS.md 未指向 docs/NAVIGATION.md（陌生 agent 断链）"
# 索引引用的本仓文件必须存在（引用链断裂= #362 P0 根因 1）
for f in governance/GOVERNANCE.yaml governance/REPOS.yaml governance/expected-state.json \
         governance/transitions.yaml governance/providers.yaml governance/policy \
         docs/pm/PLAYBOOK.md docs/NAVIGATION.md .github/workflows/gate.yml scripts/ghcb; do
  if [[ -e "$f" ]]; then pass "索引引用存在: $f"; else fail "索引引用断链: $f（#362 根因：文档引用链断裂）"; fi
done

# ---------- §C PLAYBOOK 契约 ----------
PB="docs/pm/PLAYBOOK.md"
if [[ -s "$PB" ]]; then pass "$PB 存在且非空"; else fail "$PB 缺失或为空（#362 P0-1 复现面）"; fi
for anchor in "spec 放哪" "g060 会拦你的 suite" "发起治理变更（C1 runbook" "conductor / arbiter" "NAVIGATION.md"; do
  if grep -q -- "$anchor" "$PB" 2>/dev/null; then pass "PLAYBOOK 锚点[$anchor] 在"; else fail "PLAYBOOK 锚点[$anchor] 缺（#363 落点回归）"; fi
done

# ---------- §D org 首页契约 ----------
PR="profile/README.md"
if [[ -s "$PR" ]]; then pass "$PR 存在"; else fail "$PR 缺失"; fi
grep -q "NAVIGATION.md" "$PR" && pass "profile README 指向全入口路由表" || fail "profile README 未指向 NAVIGATION.md"
grep -q "REPOS.yaml" "$PR" && pass "profile README 指向组织地图真源" || fail "profile README 未指向 REPOS.yaml"
if grep -q "agent-registry" "$PR"; then fail "profile README 仍列已退役仓 agent-registry 为活跃（ADR-0085）"; else pass "profile README 无已退役仓活跃行"; fi

# ---------- §E NAVIGATION 本仓链接可解析 ----------
BROKEN=0
while IFS= read -r link; do
  [[ -n "$link" ]] || continue
  target="${link%%#*}"
  [[ -n "$target" ]] || continue
  if [[ ! -e "docs/$target" ]]; then echo "      断链: docs/$target"; BROKEN=1; fi
done < <(grep -oE '\]\(([^)#]+)(#[^)]*)?\)' "$NAV" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | grep -vE '^(https?:|#)' || true)
(( BROKEN == 0 )) && pass "NAVIGATION 本仓链接全部可解析" || fail "NAVIGATION 存在断链（见上行）"

# ---------- §F Makefile 入口可发现性 ----------
if grep -qE '^drift-check:' Makefile 2>/dev/null; then pass "Makefile 暴露 drift-check 目标（C1 预检可发现）"; else fail "Makefile 缺 drift-check 目标"; fi
if grep -qE '^gates-pr:' Makefile 2>/dev/null; then pass "Makefile 暴露 gates-pr 目标"; else fail "Makefile 缺 gates-pr 目标"; fi

echo "== test-navigation: pass=$PASS fail=$FAIL =="
[[ $FAIL -eq 0 ]]
