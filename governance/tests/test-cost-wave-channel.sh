#!/usr/bin/env bash
# test-cost-wave-channel.sh —— cost-check 波次预算通道单测（W2-C3 .github#414，BEH-07 / ADR-0103）
#
# 从 cost-check.sh 按 @w2c3-wave-channel 标记对提取 wave_channel_check 函数体
# （不复制实现——防"测试测影子"，同 test-cost-llm-channel.sh 模式；标记对缺失=fail-closed 红），
# 用注入卡清单/本地统一账本（T2 注入通道）断言通道契约：
#   WAVE-EXCEEDED  hard-stop 卡超限 → 标签+超限行 JSON（含 tenant 分离聚合）
#   WAVE-OK        无超限（warn-only 只报告；无预算卡不计约束）
#   INFRA          卡清单拉取失败 / 波次块非法（预算面盲区，fail-closed）
# 另含全脚本集成段（桩 gh 记录调用日志，非 DRY——桩吸收全部写操作）：波次超限 →
# 硬停档三件套真实调用路径（PATCH 熔断变量 + label cost-circuit-breaker + P0 issue
# create）+ exit 1 + 审计尾行 outcome=tripped 落影子账本（AC-9b：超限硬停实测记录
# 进账本——机制面）。
# 真实三源账本拉取/验链由 evidence-query.sh 既有测试与 CI 覆盖；本测试锁
# cost-check 侧消费契约与 fail-closed 方向。用法：bash governance/tests/test-cost-wave-channel.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

# --- 提取被测函数（标记对缺失=fail-closed：测试与实现脱钩即红） ---
SRC="$DIR/cost-check.sh"
[[ -f "$SRC" ]] || { echo "FATAL: cost-check.sh 不存在"; exit 2; }
EXTRACTED=$(awk '/@w2c3-wave-channel-begin/{f=1} f{print} /@w2c3-wave-channel-end/{exit}' "$SRC")
if ! grep -q '^wave_channel_check()' <<<"$EXTRACTED"; then
  echo "FATAL: 标记对内未找到 wave_channel_check 定义（提取失效——实现与测试脱钩）"; exit 2
fi

# --- 桩环境（函数在命令替换子 shell 外定义；ok/infra 桩防实现漂移误伤主脚本计数） ---
INFRAS=0
infra() { echo "INFRA $1"; INFRAS=$((INFRAS+1)); }
ok() { echo "OK $1"; }
GH=gh
GOV_REPO="Cloudbird-Software/.github"
eval "$EXTRACTED"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# python3 本地垫片（Windows 商店 stub 环境）；CI（ubuntu）python3 直用不受影响
if ! python3 -c 'import sys' >/dev/null 2>&1; then
  mkdir -p "$TMP/bin"
  printf '#!/usr/bin/env bash\nexec python "$@"\n' >"$TMP/bin/python3"; chmod +x "$TMP/bin/python3"
  export PATH="$TMP/bin:$PATH"
fi

run_chan() {  # 捕获函数输出（注入变量控制数据源）
  WOUT=$(wave_channel_check)
}

# ---- 1) WAVE-EXCEEDED：hard-stop 卡超限 → 标签+超限行 JSON（tenant 分离聚合） ----
cat >"$TMP/cards.json" <<'EOF'
[
  {"number": 500, "body": "## budget（波次预算）\nusd: 10.0\ntokens: 100000\non_exceed: hard-stop"},
  {"number": 501, "body": "## budget（波次预算）\ntokens: 999999\non_exceed: warn"},
  {"number": 502, "body": "## 任务\n无预算卡"}
]
EOF
mkdir -p "$TMP/ledger"
cat >"$TMP/ledger/shadow-evidence-unified.jsonl" <<'EOF'
{"ts":"2026-08-29T01:00:00Z","kind":"cost","action":"cost.dispatch-burst","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#500","tenant":"cloudbird-internal"},"cost":{"tokens":40000,"usd":4.0,"wall_sec":600.0},"seq":1,"prev_hash":null,"hash":"aa"}
{"ts":"2026-08-29T02:00:00Z","kind":"cost","action":"cost.dispatch-burst","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#500","tenant":"tenant-b"},"cost":{"tokens":30000,"usd":7.5,"wall_sec":100.0},"seq":2,"prev_hash":"aa","hash":"bb"}
{"ts":"2026-08-29T03:00:00Z","kind":"cost","action":"cost.dispatch-burst","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#501","tenant":"cloudbird-internal"},"cost":{"tokens":500,"usd":0.1,"wall_sec":10.0},"seq":3,"prev_hash":"bb","hash":"cc"}
EOF
COST_WAVE_CARDS_FILE="$TMP/cards.json" COST_WAVE_LEDGER_DIR="$TMP/ledger" run_chan
if [[ "${WOUT%%$'\t'*}" == "WAVE-EXCEEDED" ]]; then
  pass "hard-stop 超限 → WAVE-EXCEEDED 标签"
else fail "应 WAVE-EXCEEDED，得到：$WOUT"; fi
python3 - "$WOUT" <<'PYEOF' && pass "超限行 JSON 断言（tenant 分离聚合 AC-9b + warn 卡不入 hard 列表）" || fail "超限行 JSON 断言"
import json, sys
hard = json.loads(sys.argv[1].split("\t", 1)[1])
assert len(hard) == 1, hard
h = hard[0]
assert h["card"] == "Cloudbird-Software/.github#500", h
assert h["usage_by_tenant"]["cloudbird-internal"]["usd"] == 4.0, h
assert h["usage_by_tenant"]["tenant-b"]["usd"] == 7.5, h
assert h["usage_total"]["usd"] == 11.5, h
assert h["exceeded_dims"] == ["usd"], h
assert h["on_exceed"] == "hard-stop", h
PYEOF

# ---- 2) WAVE-OK：无 hard-stop 超限（warn-only 报告；无预算卡不构成约束） ----
cat >"$TMP/cards2.json" <<'EOF'
[
  {"number": 501, "body": "## budget（波次预算）\ntokens: 100\non_exceed: warn"},
  {"number": 502, "body": "## 任务\n无预算卡"}
]
EOF
COST_WAVE_CARDS_FILE="$TMP/cards2.json" COST_WAVE_LEDGER_DIR="$TMP/ledger" run_chan
if [[ "${WOUT%%$'\t'*}" == "WAVE-OK" ]] && grep -q "warn 超限" <<<"$WOUT" \
   && grep -q "501" <<<"$WOUT"; then
  pass "warn-only 超限 → WAVE-OK（只报告不判定）"
else fail "warn-only 应 WAVE-OK+warn 报告，得到：$WOUT"; fi

# ---- 3) 空账本目录 → WAVE-OK 零超限（无记录=无用量，不是 infra） ----
mkdir -p "$TMP/ledger-empty"
COST_WAVE_CARDS_FILE="$TMP/cards.json" COST_WAVE_LEDGER_DIR="$TMP/ledger-empty" run_chan
if [[ "${WOUT%%$'\t'*}" == "WAVE-OK" ]]; then
  pass "空账本目录 → WAVE-OK（零用量非 infra）"
else fail "空账本应 WAVE-OK，得到：$WOUT"; fi

# ---- 4) INFRA：波次块非法（预算面盲区——fail-closed 方向） ----
cat >"$TMP/cards-bad.json" <<'EOF'
[
  {"number": 503, "body": "## budget（波次预算）\neuro: 1"}
]
EOF
COST_WAVE_CARDS_FILE="$TMP/cards-bad.json" COST_WAVE_LEDGER_DIR="$TMP/ledger" run_chan
if [[ "${WOUT%%$'\t'*}" == "INFRA" ]] && grep -q "块非法" <<<"$WOUT"; then
  pass "波次块非法 → INFRA（fail-closed：预算面盲区可见）"
else fail "块非法应 INFRA，得到：$WOUT"; fi

# ---- 5) INFRA：卡清单拉取失败（无注入 + 桩 gh 失败） ----
GHFAIL="$TMP/ghfail"
printf '#!/usr/bin/env bash\necho "gh: failure" >&2\nexit 1\n' >"$GHFAIL"; chmod +x "$GHFAIL"
GH="$GHFAIL"
run_chan 2>/dev/null
GH=gh
if [[ "${WOUT%%$'\t'*}" == "INFRA" ]] && grep -q "卡清单拉取失败" <<<"$WOUT"; then
  pass "卡清单拉取失败 → INFRA（预算面不可知）"
else fail "清单失败应 INFRA，得到：$WOUT"; fi

# ---- 5b) #470/#472 回归：wallclock_sec 超限 → WAVE-EXCEEDED；human_minutes → 可见未执法 ----
cat >"$TMP/cards-wc.json" <<'EOF'
[
  {"number": 504, "body": "## budget（波次预算）\nwallclock_sec: 7200\non_exceed: hard-stop"},
  {"number": 506, "body": "## budget（波次预算）\nhuman_minutes: 1\non_exceed: hard-stop"}
]
EOF
mkdir -p "$TMP/ledger-wc"
cat >"$TMP/ledger-wc/shadow-evidence-unified.jsonl" <<'EOF'
{"ts":"2026-08-29T04:00:00Z","kind":"cost","action":"cost.dispatch","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#504","tenant":"t1"},"cost":{"tokens":1000,"usd":0.1,"wall_sec":8000.0},"seq":1,"prev_hash":null,"hash":"dd"}
{"ts":"2026-08-29T05:00:00Z","kind":"cost","action":"cost.dispatch","verdict":"pass","subject":{"card":"Cloudbird-Software/.github#506","tenant":"t1"},"cost":{"tokens":900000,"usd":99.0,"wall_sec":8000.0},"seq":2,"prev_hash":"dd","hash":"ee"}
EOF
COST_WAVE_CARDS_FILE="$TMP/cards-wc.json" COST_WAVE_LEDGER_DIR="$TMP/ledger-wc" run_chan
if [[ "${WOUT%%$'\t'*}" == "WAVE-EXCEEDED" ]] && grep -q '"wallclock_sec"' <<<"$WOUT"; then
  pass "wallclock_sec 超限 → WAVE-EXCEEDED 含超限维（#470：执法面可达）"
else fail "wallclock 超限应 WAVE-EXCEEDED 含维度，得到：$WOUT"; fi

cat >"$TMP/cards-hm.json" <<'EOF'
[
  {"number": 506, "body": "## budget（波次预算）\nhuman_minutes: 1\non_exceed: hard-stop"}
]
EOF
COST_WAVE_CARDS_FILE="$TMP/cards-hm.json" COST_WAVE_LEDGER_DIR="$TMP/ledger-wc" run_chan
if [[ "${WOUT%%$'\t'*}" == "WAVE-OK" ]] && grep -q "未执法维度" <<<"$WOUT" && grep -q "human_minutes" <<<"$WOUT"; then
  pass "human_minutes 声明 → WAVE-OK+摘要可见未执法维度（#472：不静默）"
else fail "human_minutes 应 WAVE-OK+可见未执法，得到：$WOUT"; fi

# ---- 5c) #470 兜底：wave-check 异常退出（任何非 0/4 rc）→ INFRA（fail-closed） ----
mkdir -p "$TMP/bin-wc"
printf '#!/usr/bin/env bash\nexit 1\n' >"$TMP/bin-wc/python3"; chmod +x "$TMP/bin-wc/python3"
# 前置桩 python3 使 wave-check 退出 1（未处理异常语义）；调用后复原 PATH
PREVPATH="$PATH"
PATH="$TMP/bin-wc:$PATH"
COST_WAVE_CARDS_FILE="$TMP/cards-hm.json" COST_WAVE_LEDGER_DIR="$TMP/ledger-wc" run_chan
PATH="$PREVPATH"
if [[ "${WOUT%%$'\t'*}" == "INFRA" ]] && grep -q "rc=1" <<<"$WOUT"; then
  pass "wave-check 异常退出 → INFRA 兜底（#470 方案 C：预算面不可信不静默）"
else fail "异常退出应 INFRA rc=1，得到：$WOUT"; fi

# ---- 6) 集成段：全脚本（桩 gh 记录调用日志，吸收全部写操作）—— 波次超限 → 硬停三件套 ----
# 桩 gh：billing=0 用量（数值已按 --jq 口径）、熔断变量 404、issue/pr 清单空；
# 全部调用落 $GHSTUB_LOG 供三件套调用路径断言（BEH-07：置变量+P0 issue）。
# 匹配按子命令位置精确判（$1/$2）——宽通配会把 P0 issue body 里的
# "actions/variables/AUTO_MERGE_DISABLED" 复位说明误判成变量读调用。
GHSTUB="$TMP/ghstub"
export GHSTUB_LOG="$TMP/ghstub.log"
cat >"$GHSTUB" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GHSTUB_LOG:-/dev/null}"
if [[ "$1" == "api" ]]; then
  case "$2" in
    *settings/billing/usage*) echo 0 ;;
    *actions/variables/AUTO_MERGE_DISABLED*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    *) echo "{}" ;;
  esac
else
  echo "[]"
fi
EOF
chmod +x "$GHSTUB"
OUT2=$(mktemp)
COST_WAVE_CARDS_FILE="$TMP/cards.json" \
COST_WAVE_LEDGER_DIR="$TMP/ledger" \
COST_USAGE_MINUTES_OVERRIDE=0 \
COST_LLM_TOKENS_USED_OVERRIDE=1000 \
GH="$GHSTUB" \
GH_TOKEN=stub-token \
BUTLER_SHADOW_FILE="$TMP/butler-shadow.jsonl" \
bash "$SRC" >"$OUT2" 2>"$OUT2.err"; RC2=$?
if [[ $RC2 -eq 1 ]]; then
  pass "波次超限全脚本（桩写面）→ exit 1（运行变红=可见信号）"
else fail "全脚本应 exit 1（rc=$RC2）"; tail -n 20 "$OUT2" "$OUT2.err"; fi
if grep -q "硬停档触发" "$OUT2" && grep -q "波次超限=True" "$OUT2"; then
  pass "硬停档 act 行含波次超限标记（BEH-07 进三件套）"
else fail "缺硬停档触发/波次超限 act 行"; fi
if grep -q "PATCH" "$GHSTUB_LOG" && grep -q "actions/variables/AUTO_MERGE_DISABLED" "$GHSTUB_LOG"; then
  pass "三件套①：org 熔断变量 PATCH 置位调用已发（set_breaker）"
else fail "熔断变量置位调用未见"; fi
if grep -q "issue create" "$GHSTUB_LOG" && grep -q "cost-circuit-breaker" "$GHSTUB_LOG"; then
  pass "三件套③：P0 issue 开立调用已发（label cost-circuit-breaker）"
else fail "P0 issue 开立调用未见"; fi
if grep -q "pr list" "$GHSTUB_LOG"; then
  pass "三件套②：auto-merge 撤销清单拉取已发（strip_all_automerge 扫描面）"
else fail "auto-merge 撤销扫描未见"; fi
if grep -q '"verdict":"tripped"' "$TMP/butler-shadow.jsonl" 2>/dev/null \
   || grep -q '"verdict": "tripped"' "$TMP/butler-shadow.jsonl" 2>/dev/null; then
  pass "超限硬停审计尾行落影子账本（AC-9b：outcome=tripped 记录进账本——机制面）"
else fail "影子账本未见 tripped 尾行"; fi

[[ $FAILS -eq 0 ]] && echo "== test-cost-wave-channel.sh 全绿 ==" || { echo "== test-cost-wave-channel.sh 失败 $FAILS 处 =="; exit 1; }
