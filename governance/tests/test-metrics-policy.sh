#!/usr/bin/env bash
# test-metrics-policy.sh —— metrics.yaml policy schema 自测（W5-C4 .github#227，ADR-0073）
#
# 阈值唯一真源=policy 文件（宪法 §4A 同源原则）：本测试锁定 schema 完整性，
# 缺护栏/缺阈值/畸形配额记录即红——防"互锁静默缺一路护栏"（北极星对漏一路
# 等于 Goodhart 通道敞开）。数值语义（归零触发/聚合口径）由 test-metrics-northstar.sh
# 与 test-metrics-groups.sh 锁定。用法：bash governance/tests/test-metrics-policy.sh
# （零网络；需 python3+PyYAML——CI gate 预装，本地按 lib.sh 同款探测垫片）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GOV="$(cd "$HERE/.." && pwd)"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }

# --- python 解释器探测（CI 恒有 python3；本地 Git Bash python3 可能是商店 stub） ---
PY=""
for c in "${PYTHON:-}" python3 python py -3; do
  [[ -n "$c" ]] || continue
  "$c" -c 'import sys, yaml; print("ok")' >/dev/null 2>&1 || continue
  PY="$c"; break
done
[[ -n "$PY" ]] || { echo "::error::无可用 python（含 pyyaml）"; exit 2; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

"$PY" - "$GOV/policy/metrics.yaml" "$GOV/REPOS.yaml" >"$TMP/out.txt" 2>"$TMP/err.txt" <<'PYEOF'
import sys, yaml

errs = []
def need(cond, msg):
    if not cond:
        errs.append(msg)

try:
    m = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
    repos = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
except Exception as e:
    print(f"FATAL 解析失败: {e}", file=sys.stderr); sys.exit(2)

need(isinstance(m, dict), "顶层非对象")
need(m.get("version") == 1, "version 须为 1")

# --- 北极星护栏全集（缺一路=互锁盲区——ADR-0073 决策 1+卡面护栏面） ---
ns = m.get("north_star") or {}
GUARDS = ("escape_rate_sustained", "revert_rate", "holdout_gap",
          "drill_red_rate", "false_allow", "state_change_leak")
g = ns.get("guardrails") or {}
for k in GUARDS:
    need(k in g, f"north_star.guardrails 缺 {k}")
need(set(g) == set(GUARDS), f"guardrails 键集须恰为 {GUARDS}（多/少都算漂移），现={sorted(g)}")
need(isinstance(ns.get("window_days"), int) and ns["window_days"] > 0,
     "north_star.window_days 须为正整数")
# 数据源 pending 必须显式声明（缺证据≠劣化，但盲区必须可见——ADR-0073 决策 7）
for k in ("holdout_gap", "state_change_leak"):
    need((g.get(k) or {}).get("data_source") == "pending",
         f"guardrails.{k}.data_source 须为 pending（读取位未建——诚实声明）")
need((g.get("drill_red_rate") or {}).get("data_source") == "governance/drill/history.jsonl",
     "drill_red_rate 数据源须指向 drill 台账")
need("false_decision_ledger.jsonl" in str((g.get("false_allow") or {}).get("data_source")),
     "false_allow 数据源须指向 arbiter 误放行台账")
# 数值阈值方向性（回滚率上限/演习红率下限）
rr = g.get("revert_rate") or {}
need(isinstance(rr.get("red_when_gt"), (int, float)) and 0 < rr["red_when_gt"] < 1,
     "revert_rate.red_when_gt 须为 (0,1) 数值")
dr = g.get("drill_red_rate") or {}
need(isinstance(dr.get("red_when_lt"), (int, float)) and 0.5 <= dr["red_when_lt"] <= 1.0,
     "drill_red_rate.red_when_lt 须为 [0.5,1.0]（红率目标≈100%）")
fa = g.get("false_allow") or {}
need(fa.get("red_when_gt") == 0, "false_allow.red_when_gt 须为 0（一票即破线）")

# --- 注意力会计阈值 ---
at = m.get("attention") or {}
need(isinstance(at.get("suspicious_fast_sign_seconds"), (int, float))
     and 0 < at["suspicious_fast_sign_seconds"] <= 600,
     "suspicious_fast_sign_seconds 须为 (0,600] 秒（>10min 不再算「快速」签署）")
need(isinstance(at.get("needs_human_p90_stop_hours"), (int, float))
     and at["needs_human_p90_stop_hours"] == 24,
     "needs_human_p90_stop_hours 须为 24（宪法 §7：超 1 天=整机停摆）")
need(isinstance(at.get("sign_window_days"), int) and at["sign_window_days"] > 0,
     "sign_window_days 须为正整数")

# --- 成本声明价 + 快照 TTL ---
co = m.get("cost") or {}
for k in ("actions_price_per_minute_usd", "llm_price_per_1k_tokens_usd"):
    need(isinstance(co.get(k), (int, float)) and co[k] > 0, f"cost.{k} 须为正数")
need(isinstance(co.get("snapshot_ttl_minutes"), int) and co["snapshot_ttl_minutes"] >= 15,
     "snapshot_ttl_minutes 须 ≥15（快于刷新节奏=每轮重拉，TTL 失效）")

# --- 用户结果指标：产品清单非空、唯一、且都在组织地图内；配额记录位形状 ---
ur = m.get("user_results") or {}
prods = [p.get("repo") for p in (ur.get("products") or [])]
need(len(prods) >= 1, "user_results.products 须非空（宪法 §8：每产品至少一个指标位）")
need(len(prods) == len(set(prods)), f"products 有重复仓: {prods}")
declared = {r["name"] for r in (repos.get("repos") or [])}
for p in prods:
    need(p in declared, f"产品仓 {p} 不在 REPOS.yaml 组织地图（GM-4 申报面）")
need(bool(ur.get("read_path")), "user_results.read_path 缺失（产品仓读取位约定）")
quota = (ur.get("quarterly_hard_quota") or {}).get("entries") or []
need(isinstance(quota, list), "quarterly_hard_quota.entries 须为列表（记录位）")
for e in quota:
    need(isinstance(e, dict) and e.get("quarter") and e.get("product"),
         f"配额 entry 形状非法（须 quarter+product）: {e}")
    need(e.get("status") in (None, "planned", "doing", "done"),
         f"配额 entry.status 非法: {e}")

# --- 板字段 pending 标注（AC-3：谓词数据源未落=值 pending，不造数） ---
need(str((m.get("board") or {}).get("predicate_status_pending", "")).startswith("pending"),
     "board.predicate_status_pending 须以 pending 开头")

for e in errs:
    print("ERR", e)
sys.exit(1 if errs else 0)
PYEOF
if [[ $? -eq 0 ]]; then
  pass "metrics.yaml schema 完整（护栏全集/阈值方向/pending 声明/产品面/配额位）"
else
  fail "metrics.yaml schema 校验失败："; sed 's/^/      /' "$TMP/err.txt" "$TMP/out.txt" 2>/dev/null
fi

echo "== test-metrics-policy: pass=$PASS fail=$FAIL =="
[[ $FAIL -eq 0 ]]
