#!/usr/bin/env bash
# test-metrics-wiring.sh —— dashboard 采集层纯函数自测（W5-C4 .github#227，ADR-0073）
#
# 从 dashboard-update.py 按 @w5c4-pure 标记对提取纯函数区（不复制实现——防"测试
# 测影子"，test-ir0002.sh 同模式；标记对缺失=fail-closed 红），fixture 断言：
#   逃逸双窗分割（sustained 无状态化）· 演习过滤可见 · 演习红率分母口径
#   误放行台账窗过滤 · 签署耗时 timeline 差（无 draft 不造 0）· needs-human 停留
#   产品仓用户结果指标读取位（缺失/畸形=pending 不造数）
# 用法：bash governance/tests/test-metrics-wiring.sh（零网络零真实 gh）
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
SRC="$GOV/dashboard-update.py"
[[ -f "$SRC" ]] || { echo "FATAL: dashboard-update.py 不存在"; exit 2; }

# --- 提取被测纯函数区（标记对缺失=fail-closed） ---
awk '/@w5c4-pure-begin/{f=1} f{print} /@w5c4-pure-end/{exit}' "$SRC" >"$TMP/pure_body.py"
if ! grep -q '^def partition_escapes(' "$TMP/pure_body.py"; then
  echo "FATAL: 标记对内未找到纯函数定义（提取失效——实现与测试脱钩）"; exit 2
fi
# 垫片头：提取块只依赖 stdlib（datetime/json）+局部 yaml——补导入即可独立运行
{ echo 'import datetime as _dt'; echo 'import json'; cat "$TMP/pure_body.py"; } >"$TMP/pure.py"

cat >>"$TMP/pure.py" <<'PYEOF'

# ==== 驱动断言（now 固定——离线可复现，owner 复算同款） ====
NOW = _dt.datetime(2026, 8, 22, 0, 0, tzinfo=_dt.timezone.utc)
W7 = _dt.timedelta(days=7)
results = []

def check(name, cond):
    results.append((name, bool(cond)))

# 1) 逃逸双窗分割：current=[now-7d,now) previous=[now-14d,now-7d)；演习排除且可见
prs = [
    {"title": "[auto-revert] #11 bad fix", "body": "x",
     "mergedAt": (NOW - _dt.timedelta(days=1)).isoformat()},          # 本窗 revert
    {"title": "[auto-revert] #10 older", "body": "x",
     "mergedAt": (NOW - _dt.timedelta(days=10)).isoformat()},         # 上一窗 revert
    {"title": "[auto-revert] drill tail", "body": "演习收尾",
     "mergedAt": (NOW - _dt.timedelta(days=2)).isoformat()},          # 演习排除
    {"title": "feat: normal", "body": "x",
     "mergedAt": (NOW - _dt.timedelta(days=2)).isoformat()},          # 非 revert
    {"title": "[auto-revert] ancient", "body": "x",
     "mergedAt": (NOW - _dt.timedelta(days=30)).isoformat()},         # 出 14d 窗
]
p0s = [
    {"title": "post-merge 冒烟失败 #91", "created_at": (NOW - _dt.timedelta(days=3)).isoformat()},
    {"title": "post-merge 冒烟失败 #80", "created_at": (NOW - _dt.timedelta(days=9)).isoformat()},
    {"title": "post-merge 冒烟失败 drill", "body": "[drill]", "created_at": (NOW - _dt.timedelta(days=1)).isoformat()},
]
esc = partition_escapes(prs, p0s, NOW)
check("逃逸双窗 current=2（1 revert+1 P0）", esc["current"] == 2)
check("逃逸双窗 previous=2（1 revert+1 P0）", esc["previous"] == 2)
check("回滚率分子 reverts_current=1（不含 P0）", esc["reverts_current"] == 1)
check("演习排除计数可见=2（过滤不可见=作弊通道）", esc["drills_excluded"] == 2)
check("空输入零窗", partition_escapes([], [], NOW) == {"current": 0, "previous": 0, "reverts_current": 0, "drills_excluded": 0})

# 2) 演习红率：kind=seed-drill + no-surface 不入分母（drill.py redrate 同口径）；畸形行计数可见
lines = [
    '# 台账头注释',
    '{"kind":"seed-drill","verdict":"red"}',
    '{"kind":"seed-drill","verdict":"green"}',
    '{"kind":"seed-drill","verdict":"no-surface"}',
    '{"kind":"failclose-drill","outcome":"pass"}',   # 非种子演习——不入红率分母
    'not-json-line',
]
agg = drill_redrate_lines(lines)
check("演习红率 red=1 denom=2（no-surface 与 failclose 出分母）", agg["red"] == 1 and agg["denom"] == 2)
check("畸形行 bad_lines=1 可见", agg["bad_lines"] == 1)

# 3) 误放行台账：注释跳过 · 窗过滤 · infra 不算误拒（ADR-0054 §7）
ledger = '\n'.join([
    '# arbiter 误放行/误拒台账（false decision ledger，ADR-0054 §7）',
    '{"date": "2026-08-15T00:00:00Z", "kind": "false-allow"}',
    '{"date": "2026-08-20T00:00:00Z", "kind": "false-deny"}',
    '{"date": "2026-05-01T00:00:00Z", "kind": "false-allow"}',
    '{"date": "2026-08-21T00:00:00Z", "kind": "infra"}',
])
allow, deny, fd_lines = false_decision_parse(ledger, NOW, 30)
check("误放行窗内=1（窗外不计）", allow == 1)
check("误拒窗内=1（infra 不计）", deny == 1)
check("行列表=4（注释行剔除）", len(fd_lines) == 4)

# 4) 签署耗时：draft→signed timeline 差；在途计数；无 draft 不造 0
t_ok = [
    {"event": "labeled", "label": {"name": "state:ir-draft"}, "created_at": "2026-08-20T10:00:00Z"},
    {"event": "labeled", "label": {"name": "state:ir-signed"}, "created_at": "2026-08-20T11:30:00Z"},
]
t_fast = [
    {"event": "labeled", "label": {"name": "state:ir-draft"}, "created_at": "2026-08-21T10:00:00Z"},
    {"event": "labeled", "label": {"name": "state:ir-signed"}, "created_at": "2026-08-21T10:00:30Z"},
]
t_inflight = [{"event": "labeled", "label": {"name": "state:ir-draft"}, "created_at": "2026-08-18T00:00:00Z"}]
t_nodraft = [{"event": "labeled", "label": {"name": "state:ir-signed"}, "created_at": "2026-08-19T00:00:00Z"}]
durs, inflight = sign_durations([t_ok, t_fast, t_inflight, t_nodraft])
check("签署耗时=[5400, 30]（90min 与 30s 快签）", durs == [5400, 30])
check("在途 draft=1", inflight == 1)
check("signed 无 draft 不入统计（不造 0）", len(durs) == 2)

# 5) needs-human 停留：取最近一次 labeled 时刻（反复进出取当前段）
ev = [
    {"event": "labeled", "label": {"name": "state:needs-human"}, "created_at": "2026-08-10T00:00:00Z"},
    {"event": "labeled", "label": {"name": "state:in-progress"}, "created_at": "2026-08-15T00:00:00Z"},
    {"event": "labeled", "label": {"name": "state:needs-human"}, "created_at": "2026-08-21T00:00:00Z"},
]
h = dwell_hours(ev, NOW)
check("停留=24h（最近一次 needs-human）", h == 24.0)
check("无事件→None", dwell_hours([], NOW) is None)
check("未来时戳→None（不造负数）", dwell_hours(
    [{"event": "labeled", "label": {"name": "state:needs-human"}, "created_at": "2026-08-23T00:00:00Z"}], NOW) is None)

# 6) 用户结果读取位：完整→ok；缺 value→None；非 yaml→None（pending 不造数）
check("完整声明→dict", user_metric_from("metric_key: dau\nvalue: 42\nunit: 人\n") == {"metric_key": "dau", "value": 42, "unit": "人"})
check("缺 metric_key→None", user_metric_from("value: 42\n") is None)
check("畸形 yaml→None", user_metric_from(":::not yaml[") is None)
check("空文本→None", user_metric_from("") is None)

bad = [n for n, ok in results if not ok]
for n, ok in results:
    print(("PASS  " if ok else "FAIL  ") + n)
raise SystemExit(1 if bad else 0)
PYEOF

if "$PY" "$TMP/pure.py" >"$TMP/run.txt" 2>"$TMP/err.txt"; then
  sed 's/^/  /' "$TMP/run.txt"
  pass "dashboard 采集层纯函数 fixture 全过（$(grep -c '^PASS' "$TMP/run.txt") 项）"
else
  sed 's/^/  /' "$TMP/run.txt" "$TMP/err.txt" 2>/dev/null
  fail "采集层纯函数断言失败（详见上行）"
fi

echo "== test-metrics-wiring: pass=$PASS fail=$FAIL =="
[[ $FAIL -eq 0 ]]
