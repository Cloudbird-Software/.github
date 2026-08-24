#!/usr/bin/env bash
# test-issue263-w1c5.sh —— W1-C5 条款入册自检（ISSUE-263 AC-19）
#
# 验证 transitions/testing/GOVERNANCE/REPOS/org-required-workflows 中新增的
# T5/T6、T-14/T-15、AR-10、specs/ & pipeline/ 申报、commit SHA 钉点均已落位。
# 零网络；由 gate 的 governance 脚本自测步骤自动调用。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GOV="$(cd "$HERE/.." && pwd)"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }

PY=""
for c in "${PYTHON:-}" python3 python py -3; do
  [[ -n "$c" ]] || continue
  "$c" -c 'import sys, yaml; print("ok")' >/dev/null 2>&1 || continue
  PY="$c"; break
done
[[ -n "$PY" ]] || { echo "::error::无可用 python（含 pyyaml）"; exit 2; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

"$PY" - "$GOV/transitions.yaml" "$GOV/policy/testing.yaml" "$GOV/GOVERNANCE.yaml" "$GOV/REPOS.yaml" "$GOV/rulesets/org-required-workflows.json" "$GOV/expected-state.json" >"$TMP/out.txt" 2>"$TMP/err.txt" <<'PYEOF'
import json, re, sys, yaml

errs = []
def need(cond, msg):
    if not cond:
        errs.append(msg)

try:
    transitions = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
    testing = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
    governance = yaml.safe_load(open(sys.argv[3], encoding="utf-8"))
    repos = yaml.safe_load(open(sys.argv[4], encoding="utf-8"))
    orw = json.load(open(sys.argv[5], encoding="utf-8"))
    expected = json.load(open(sys.argv[6], encoding="utf-8"))
except Exception as e:
    print(f"FATAL 解析失败: {e}", file=sys.stderr)
    sys.exit(2)

# --- T5/T6 转移 ---
trans_ids = {t.get("id") for t in transitions.get("transitions", [])}
need("T5" in trans_ids, "transitions.yaml 缺少 T5")
need("T6" in trans_ids, "transitions.yaml 缺少 T6")
for t in transitions.get("transitions", []):
    if t.get("id") == "T5":
        need(t.get("from_state") == "spec" and t.get("to_state") == "redteam",
             "T5 状态转移不是 spec→redteam")
    if t.get("id") == "T6":
        need(t.get("from_state") == "redteam" and t.get("to_state") == "wave-planned",
             "T6 状态转移不是 redteam→wave-planned")
        need("'adversary:survived' in label_set" in str(t.get("guard", "")),
             "T6 guard 未包含 survived 审计记录要求")

# --- T-14/T-15 测试政策 ---
active_ids = {x.get("id") for x in testing.get("active_now", [])}
need("T-14" in active_ids, "testing.yaml active_now 缺少 T-14")
need("T-15" in active_ids, "testing.yaml active_now 缺少 T-15")

# --- AR-10 治理条目 ---
measures = governance.get("domains", {}).get("agent_runtime", {}).get("measures", [])
ids = {m.get("id") for m in measures}
need("AR-10" in ids, "GOVERNANCE.yaml agent_runtime 缺少 AR-10")

# --- REPOS.yaml 补登 ---
repo_map = {r["name"]: r for r in repos.get("repos", [])}
need(".github" in repo_map, "REPOS.yaml 缺少 .github")
need("CI-Workflows" in repo_map, "REPOS.yaml 缺少 CI-Workflows")
need("specs/" in repo_map[".github"].get("key_paths", []),
     ".github key_paths 未补登 specs/")
need("pipeline/" in repo_map["CI-Workflows"].get("key_paths", []),
     "CI-Workflows key_paths 未补登 pipeline/")

# --- org-required-workflows 钉点（2026-08-24 平台约束修订：SHA 恒被拒，钉分支名）---
# ruleset API 对 required workflows 的 ref 只接受分支/标签（40 位 SHA 恒 422
# "does not have ref"——多轮实测，ADR-0083 关联）；供应链完整性改由
# expected-state.content 校验与 drift-check 后验承载。钉点=main + 双工作流面。
wf_paths = [w.get("path") for w in orw.get("rules", [])[0].get("parameters", {}).get("workflows", [])]
ref = (orw.get("rules", [])[0].get("parameters", {}).get("workflows", []) + [{}])[0].get("ref", "")
need(ref in ("main", "master"), f"org-required-workflows.json 钉点须为分支名（平台不接受 SHA）: {ref}")
need(".github/workflows/org-gate.yml" in wf_paths, "org-required-workflows 缺 org-gate.yml")
need(".github/workflows/adversary-gate.yml" in wf_paths, "org-required-workflows 缺 adversary-gate.yml（ADR-0082/0083）")

# expected-state 与 ruleset 一致（ref=分支名；ref_commit 字段随平台约束废弃）
orw_exp = expected.get("org_required_workflows", {})
need(orw_exp.get("ref") == ref,
     f"expected-state.org_required_workflows.ref ({orw_exp.get('ref')}) 与 ruleset ({ref}) 不一致")
need("ref_commit" not in orw_exp, "ref_commit 已随 SHA 钉点废弃（平台约束）——expected-state 应删除")

for e in errs:
    print("ERR", e)
sys.exit(1 if errs else 0)
PYEOF

if [[ $? -eq 0 ]]; then
  pass "W1-C5 条款入册自检通过（T5/T6/T-14/T-15/AR-10/REPOS/SHA 钉点）"
else
  fail "W1-C5 条款入册自检失败："
  sed 's/^/      /' "$TMP/err.txt" "$TMP/out.txt" 2>/dev/null
fi

echo "== test-issue263-w1c5: pass=$PASS fail=$FAIL =="
[[ $FAIL -eq 0 ]]
