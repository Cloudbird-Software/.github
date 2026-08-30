#!/usr/bin/env bash
# test-wave-schema.sh —— 波次 schema v1 解析/校验/wave-check 自测（IR-0006 W2-C3 / 卡 #414）
#
# 覆盖（卡 AC 对应）：
#   parse：h2/h3（issue 表单产 h3）双形态块提取；缺块=空对象（缺省语义）
#   validate：四元组数值/on_exceed 词表/capabilities 两形态 allowlist/evidence 非空
#   负向：非法键/负值/坏 on_exceed/裸 secret 名 → exit 3（fail-closed）
#   wave-check：按 subject.card 聚合（tenant 归因分离）；超限 exit 4；
#              非法 budget 块=行级 error 不炸整批；无预算卡=跳过
# 用法: bash governance/tests/test-wave-schema.sh（gate.yml 自动纳入）
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WS="$DIR/governance/wave_schema.py"
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---- 正向：h2 手写卡形态 ----
cat >"$TMP/card-h2.md" <<'EOF'
> 父意图: #402 | Spec: `specs/IR-0006/spec.md` v1 | 波次: W2 | 依赖: W1

## 任务
调度器 v0。

## budget（波次预算）
usd: 5.0
tokens: 200000
wallclock_sec: 7200
human_minutes: 120
on_exceed: hard-stop

## capabilities（能力 allowlist）
- org-secret:CNB_POOL_KEY
- vault:secret/wave/w2c1

## evidence（证据要求）
- gate.merge-verdict
EOF
python3 "$WS" validate --body-file "$TMP/card-h2.md" >/dev/null \
  && pass "validate h2 形态绿（三块齐全）" || fail "validate h2 形态"
OUT=$(python3 "$WS" parse --body-file "$TMP/card-h2.md" --card "Cloudbird-Software/.github#414")
python3 - "$OUT" <<'PYEOF' && pass "parse h2：wave-meta 三块齐全+card 回填" || fail "parse h2 断言"
import json, sys
m = json.loads(sys.argv[1])
assert m["card"] == "Cloudbird-Software/.github#414", m
assert m["budget"]["usd"] == 5.0 and m["budget"]["on_exceed"] == "hard-stop", m
assert m["capabilities"] == ["org-secret:CNB_POOL_KEY", "vault:secret/wave/w2c1"], m
assert m["evidence"] == ["gate.merge-verdict"], m
PYEOF

# ---- 正向：h3 issue 表单形态 + on_exceed 缺省 hard-stop ----
cat >"$TMP/card-h3.md" <<'EOF'
### 任务
某卡。

### budget（波次预算）
tokens: 1000

### capabilities（能力 allowlist）
- vault:secret/x
EOF
OUT=$(python3 "$WS" parse --body-file "$TMP/card-h3.md")
python3 - "$OUT" <<'PYEOF' && pass "parse h3：表单形态+缺省 on_exceed=hard-stop" || fail "parse h3 断言"
import json, sys
m = json.loads(sys.argv[1])
assert m["budget"] == {"tokens": 1000, "on_exceed": "hard-stop"}, m
assert "evidence" not in m, m
PYEOF

# ---- 缺块=空对象（缺省语义）----
cat >"$TMP/card-none.md" <<'EOF'
> 父意图: #402

## 任务
无预算卡。
EOF
OUT=$(python3 "$WS" parse --body-file "$TMP/card-none.md")
[[ "$OUT" == "{}" ]] && pass "缺块 → 空对象（无预算约束缺省语义）" || fail "缺块应空对象：$OUT"

# ---- 负向：非法形态逐项 exit 3 ----
neg() {  # neg <名> <内容>
  printf '%s\n' "$2" >"$TMP/neg.md"
  python3 "$WS" validate --body-file "$TMP/neg.md" >/dev/null 2>&1
  [[ $? -eq 3 ]] && pass "负向：$1 → exit 3" || fail "负向：$1 未拒绝"
}
neg "非法键" '## budget（波次预算）
usd: 1
euro: 2'
neg "负值" '## budget（波次预算）
usd: -5'
neg "四元组全缺" '## budget（波次预算）
on_exceed: warn'
neg "坏 on_exceed" '## budget（波次预算）
tokens: 1
on_exceed: explode'
neg "裸 secret 名（非 allowlist 形态）" '## capabilities（能力 allowlist）
- CNB_POOL_KEY'
neg "capabilities 非列表" '## capabilities（能力 allowlist）
foo: bar'
neg "evidence 空列表" '## evidence（证据要求）
[]'
neg "budget 坏 YAML 映射" '## budget（波次预算）
- just
- list'

# ---- wave-check：统一账本按 subject 聚合 + 超限判定 ----
cat >"$TMP/cards.json" <<'EOF'
[
  {"number": 500, "body": "## budget（波次预算）\nusd: 10.0\ntokens: 100000\non_exceed: hard-stop"},
  {"number": 501, "body": "## budget（波次预算）\ntokens: 999999\non_exceed: warn"},
  {"number": 502, "body": "## 任务\n无预算卡"},
  {"number": 503, "body": "## budget（波次预算）\neuro: 1"}
]
EOF
mkdir -p "$TMP/ledger"
cat >"$TMP/ledger/shadow-evidence-2026-W35.jsonl" <<'EOF'
{"ts":"2026-08-29T01:00:00Z","kind":"cost","action":"cost.dispatch-burst","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#500","tenant":"cloudbird-internal"},"actor":{"identity":"x","role":"bot","model":null},"cost":{"tokens":40000,"usd":4.0,"wall_sec":600.0},"seq":1,"prev_hash":null,"hash":"aa"}
{"ts":"2026-08-29T02:00:00Z","kind":"cost","action":"cost.dispatch-burst","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#500","tenant":"tenant-b"},"actor":{"identity":"x","role":"bot","model":null},"cost":{"tokens":30000,"usd":7.5,"wall_sec":100.0},"seq":2,"prev_hash":"aa","hash":"bb"}
{"ts":"2026-08-29T03:00:00Z","kind":"cost","action":"cost.dispatch-burst","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#501","tenant":"cloudbird-internal"},"actor":{"identity":"x","role":"bot","model":null},"cost":{"tokens":500,"usd":0.1,"wall_sec":10.0},"seq":3,"prev_hash":"bb","hash":"cc"}
EOF
OUT=$(python3 "$WS" wave-check --cards "$TMP/cards.json" --ledger-dir "$TMP/ledger" 2>"$TMP/wc.err"); RC=$?
python3 - "$OUT" <<'PYEOF' && pass "wave-check 聚合断言（tenant 分离+非法块行级 error+无预算跳过）" || fail "wave-check 聚合断言"
import json, sys
rows = {r["card"]: r for r in json.loads(sys.argv[1])}
c500 = rows["Cloudbird-Software/.github#500"]
assert c500["usage_by_tenant"]["cloudbird-internal"]["usd"] == 4.0, c500
assert c500["usage_by_tenant"]["tenant-b"]["usd"] == 7.5, c500
assert c500["usage_total"] == {"usd": 11.5, "tokens": 70000, "wall_sec": 700.0}, c500
assert c500["exceeded_dims"] == ["usd"], c500
c501 = rows["Cloudbird-Software/.github#501"]
assert c501["exceeded_dims"] == [] and c501["on_exceed"] == "warn", c501
assert "error" in rows["Cloudbird-Software/.github#503"], rows
assert "Cloudbird-Software/.github#502" not in rows, rows
PYEOF
[[ $RC -eq 4 ]] && pass "hard-stop 卡超限 → exit 4（BEH-07 熔断触发位）" || fail "超限应 exit 4（rc=$RC）"

# 无账本目录 → 全零用量不超限
OUT=$(python3 "$WS" wave-check --cards "$TMP/cards.json" --ledger-dir "$TMP/no-such-dir" 2>/dev/null); RC=$?
[[ $RC -eq 0 ]] && grep -q '"exceeded_dims": \[\]' <<<"$OUT" \
  && pass "账本目录缺失 → 零用量不误熔断" || fail "空账本误判（rc=$RC）"

# ---- #470 回归：wallclock_sec 超限 → exit 4（键名映射 wall_sec 修复面） ----
cat >"$TMP/cards-wc.json" <<'EOF'
[
  {"number": 504, "body": "## budget（波次预算）\nwallclock_sec: 7200\non_exceed: hard-stop"},
  {"number": 505, "body": "## budget（波次预算）\nusd: 1.0\nwallclock_sec: 7200\non_exceed: hard-stop"}
]
EOF
mkdir -p "$TMP/ledger-wc"
cat >"$TMP/ledger-wc/shadow-evidence-2026-W36.jsonl" <<'EOF'
{"ts":"2026-08-29T04:00:00Z","kind":"cost","action":"cost.dispatch","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#504","tenant":"t1"},"actor":{"identity":"x","role":"bot","model":null},"cost":{"tokens":1000,"usd":0.1,"wall_sec":8000.0},"seq":1,"prev_hash":null,"hash":"dd"}
{"ts":"2026-08-29T05:00:00Z","kind":"cost","action":"cost.dispatch","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#505","tenant":"t1"},"actor":{"identity":"x","role":"bot","model":null},"cost":{"tokens":1000,"usd":99.0,"wall_sec":8000.0},"seq":2,"prev_hash":"dd","hash":"ee"}
EOF
OUT=$(python3 "$WS" wave-check --cards "$TMP/cards-wc.json" --ledger-dir "$TMP/ledger-wc" 2>"$TMP/wc2.err"); RC=$?
[[ $RC -eq 4 ]] && pass "wallclock_sec 超限 → exit 4（#470：KeyError 修复+维度执法可达）" \
  || fail "wallclock_sec 超限应 exit 4（rc=$RC，stderr：$(head -2 "$TMP/wc2.err" 2>/dev/null)）"
python3 - "$OUT" <<'PYEOF' && pass "wallclock+usd 混合卡：两维同报不互吞（#470：usd 超限不再被 wallclock 键错崩掉）" || fail "混合卡断言"
import json, sys
rows = {r["card"]: r for r in json.loads(sys.argv[1])}
c504 = rows["Cloudbird-Software/.github#504"]
assert c504["exceeded_dims"] == ["wallclock_sec"], c504
c505 = rows["Cloudbird-Software/.github#505"]
assert c505["exceeded_dims"] == ["usd", "wallclock_sec"], c505
PYEOF

# ---- #472 回归：human_minutes 声明 → 行级 unenforced_dims 可见（不静默） ----
cat >"$TMP/cards-hm.json" <<'EOF'
[
  {"number": 506, "body": "## budget（波次预算）\nhuman_minutes: 1\non_exceed: hard-stop"}
]
EOF
OUT=$(python3 "$WS" wave-check --cards "$TMP/cards-hm.json" --ledger-dir "$TMP/ledger-wc" 2>/dev/null); RC=$?
[[ $RC -eq 0 ]] && python3 - "$OUT" <<'PYEOF' && pass "human_minutes → unenforced_dims 行级可见（#472：账本无源不静默放行）" || fail "human_minutes 可见断言"
import json, sys
rows = json.loads(sys.argv[1])
r = rows[0]
assert r["exceeded_dims"] == [], r
assert r.get("unenforced_dims") == ["human_minutes"], r
PYEOF
[[ $? -eq 0 ]] || fail "human_minutes 轮 rc=$RC（应 0——无执法面不误红）"

echo "----------------------------------------"
if [[ $FAILS -eq 0 ]]; then echo "test-wave-schema: PASS"; exit 0; fi
echo "test-wave-schema: $FAILS 处失败"; exit 1
