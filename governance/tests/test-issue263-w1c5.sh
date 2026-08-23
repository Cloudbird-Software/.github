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

# --- org-required-workflows 钉点为 commit SHA 而非 tag ---
wf = (orw.get("rules", [])[0].get("parameters", {}).get("workflows", []) + [{}])[0]
ref = wf.get("ref", "")
need(bool(re.fullmatch(r"[0-9a-f]{40}", ref)),
     f"org-required-workflows.json 钉点不是 40 位 commit SHA: {ref}")
need(wf.get("path") == ".github/workflows/org-gate.yml", "org-required-workflows 工作流路径异常")

# expected-state 与 ruleset 一致
orw_exp = expected.get("org_required_workflows", {})
need(orw_exp.get("ref") == ref,
     f"expected-state.org_required_workflows.ref ({orw_exp.get('ref')}) 与 ruleset ({ref}) 不一致")
need(orw_exp.get("ref_commit") == ref,
     f"expected-state.org_required_workflows.ref_commit 应与 ref 同值")

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
