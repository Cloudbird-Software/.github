#!/usr/bin/env bash
# test-board-fields.sh —— factory-floor 板字段完善自测（W5-C4 AC-3，ADR-0073 决策 5）
#
# 从 board-sync.py 按 @w5c4-board-pure 标记对提取纯函数区（不复制实现——防"测试
# 测影子"；标记对缺失=fail-closed 红），fixture 断言：
#   卡↔PR 关联（Card: 元数据行解析）· 关卡状态四值映射（绿/红/等待/无 CI——
#   fail-closed 方向：失败先于未完成，未知≠绿）· 漂移报警面（label/派生真源 vs
#   板值；停留天数等例行刷新字段不进漂移面）
# 用法：bash governance/tests/test-board-fields.sh（零网络零真实 gh）
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
SRC="$GOV/board-sync.py"
[[ -f "$SRC" ]] || { echo "FATAL: board-sync.py 不存在"; exit 2; }

awk '/@w5c4-board-pure-begin/{f=1} f{print} /@w5c4-board-pure-end/{exit}' "$SRC" >"$TMP/pure_body.py"
if ! grep -q '^def gate_status_text(' "$TMP/pure_body.py"; then
  echo "FATAL: 标记对内未找到板字段纯函数（提取失效——实现与测试脱钩）"; exit 2
fi
{ echo 'import re'; cat "$TMP/pure_body.py"; } >"$TMP/pure.py"

cat >>"$TMP/pure.py" <<'PYEOF'

# ==== 驱动断言 ====
results = []
def check(name, cond):
    results.append((name, bool(cond)))

# 1) 卡↔PR 关联：Card: 元数据行解析（入口协议 v1）；无元数据/无 body 不关联
prs = [
    {"body": "动机…\n\nCard: Cloudbird-Software/.github#227\n", "head": {"sha": "aaa"}},
    {"body": "Card: Cloudbird-Software/mutual#42", "head": {"sha": "bbb"}},
    {"body": "无元数据行的 PR", "head": {"sha": "ccc"}},
    {"body": None, "head": {"sha": "ddd"}},
]
refs = pr_refs_from_prs(prs)
check("卡↔PR 关联 2 条", refs == {(".github", 227): "aaa", ("mutual", 42): "bbb"})
check("空输入零关联", pr_refs_from_prs([]) == {})

# 2) 关卡状态映射（check-runs→绿/红/等待/无 CI；失败优先于未完成——未知≠绿）
ok = [{"status": "completed", "conclusion": "success"}, {"status": "completed", "conclusion": "success"}]
mix_fail = [{"status": "completed", "conclusion": "success"}, {"status": "completed", "conclusion": "failure"}]
mix_wait = [{"status": "completed", "conclusion": "success"}, {"status": "in_progress"}]
timed = [{"status": "completed", "conclusion": "timed_out"}]
incomplete = [{"status": "completed"}]  # completed 但无 conclusion（畸形态）——不算绿
check("全 success→绿", gate_status_text(ok) == "绿")
check("任一 failure→红（其余绿不遮红）", gate_status_text(mix_fail) == "红")
check("timed_out→红（fail-closed 方向）", gate_status_text(timed) == "红")
check("in_progress→等待", gate_status_text(mix_wait) == "等待")
check("completed 无 conclusion→等待（不冒充绿）", gate_status_text(incomplete) == "等待")
check("空 check-runs→无 CI", gate_status_text([]) == "无 CI")
check("None→无 CI（拉取失败调用方显式「未知」）", gate_status_text(None) == "无 CI")

# 3) 漂移报警面：人工可改字段进面；例行派生刷新（停留天数/卡号）不进面
want = {"State": "in-progress", "认领者": "randypanding", "AC 进度": "2/4",
        "关卡状态": "红", "谓词状态": "pending(W5-C2)", "停留天数": 3, "卡号": 227}
check("全一致→零漂移", board_drift_fields(want, want) == [])
check("State 漂移检出", board_drift_fields({**want, "State": "done"}, want) == ["State"])
check("关卡状态漂移检出", board_drift_fields({**want, "关卡状态": "绿"}, want) == ["关卡状态"])
check("认领者漂移检出", "认领者" in board_drift_fields({**want, "认领者": "someone"}, want))
multi = board_drift_fields({**want, "State": "spec", "谓词状态": "ok"}, want)
check("多字段漂移全列（State+谓词）", multi == ["State", "谓词状态"])
check("停留天数例行刷新不进漂移面", board_drift_fields({**want, "停留天数": 4}, want) == [])
check("板空值 vs 期望空串等价（GitHub 空文本不落值）",
      board_drift_fields({"认领者": None}, {"认领者": ""}) == [])
check("板有值 vs 期望空串=漂移", board_drift_fields({"认领者": "x"}, {"认领者": ""}) == ["认领者"])

bad = [n for n, ok in results if not ok]
for n, ok in results:
    print(("PASS  " if ok else "FAIL  ") + n)
raise SystemExit(1 if bad else 0)
PYEOF

if "$PY" "$TMP/pure.py" >"$TMP/run.txt" 2>"$TMP/err.txt"; then
  sed 's/^/  /' "$TMP/run.txt"
  pass "板字段纯函数 fixture 全过（$(grep -c '^PASS' "$TMP/run.txt") 项）"
else
  sed 's/^/  /' "$TMP/run.txt" "$TMP/err.txt" 2>/dev/null
  fail "板字段纯函数断言失败（详见上行）"
fi

echo "== test-board-fields: pass=$PASS fail=$FAIL =="
[[ $FAIL -eq 0 ]]
