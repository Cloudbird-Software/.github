#!/usr/bin/env bash
# test-cost-llm-channel.sh —— cost-check LLM 预算通道单测（W2-C3 .github#216，ADR-0062）
#
# 从 cost-check.sh 按 @w2c3-llm-channel 标记对提取 llm_channel_account 函数体
# （不复制实现——防"测试测影子"，同 test-ir0002.sh 模式；标记对缺失=fail-closed 红），
# 用桩 metering.py（行为受 STUB_MODE 控制）与桩 gh 断言通道契约：
#   DATA    归账成功 → "DATA<TAB>当月token<TAB>角色档json"（调用方据此算 PCT_TOK）
#   空账本  aggregate rc=2 → ZERO（账本分支已建但无周片 = 零用量，不是 infra）
#   链断    aggregate rc=3 → INFRA（不可信数据不入账，fail-closed）
#   引擎缺失 / tarball 拉取失败（分支在）/ 分支未建 → INFRA / ZERO
# 真实归账数值（角色档聚合、验链、hash 链）由 CI-Workflows 仓
# pipeline/metering/selftest T1/T3/T5 覆盖；本测试锁 cost-check 侧消费契约与
# fail-closed 方向。用法：bash governance/tests/test-cost-llm-channel.sh（零网络零真实 gh）
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

# --- 提取被测函数（标记对缺失=fail-closed：测试与实现脱钩即红） ---
SRC="$DIR/cost-check.sh"
[[ -f "$SRC" ]] || { echo "FATAL: cost-check.sh 不存在"; exit 2; }
EXTRACTED=$(awk '/@w2c3-llm-channel-begin/{f=1} f{print} /@w2c3-llm-channel-end/{exit}' "$SRC")
if ! grep -q '^llm_channel_account()' <<<"$EXTRACTED"; then
  echo "FATAL: 标记对内未找到 llm_channel_account 定义（提取失效——实现与测试脱钩）"; exit 2
fi

# --- 桩环境（函数在命令替换子 shell 外定义；ok/infra 桩防实现漂移误伤主脚本计数） ---
INFRAS=0
infra() { echo "INFRA $1"; INFRAS=$((INFRAS+1)); }
ok() { echo "OK $1"; }
GH=gh
LT_M_REPO="Cloudbird-Software/CI-Workflows"
LT_M_BRANCH="metering-ledger"
LT_M_CODE="pipeline/metering"
eval "$EXTRACTED"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/ledger"
# python3 本地垫片（Windows 商店 stub 环境）；CI（ubuntu）python3 直用不受影响
if ! python3 -c 'import sys' >/dev/null 2>&1; then
  printf '#!/usr/bin/env bash\nexec python "$@"\n' >"$TMP/bin/python3"; chmod +x "$TMP/bin/python3"
  export PATH="$TMP/bin:$PATH"
fi
# 桩 metering.py：与真实 metering.py aggregate 的退出码契约一致（0=数据 2=无账本 3=链断）
STUB_MODE_PATH="$TMP/mode"
cat >"$TMP/bin/metering.py" <<'EOF'
import os, sys
mode = open(os.environ["STUB_MODE_PATH"], encoding="utf-8").read().strip()
if mode == "data":
    print('{"roles": {"probe": {"invokes": 2, "total_tokens": 165}, '
          '"spec-author": {"invokes": 1, "total_tokens": 42}}, '
          '"totals": {"invokes": 3, "total_tokens": 207}}')
    sys.exit(0)
if mode == "empty":
    print("账本目录无 records-*.jsonl", file=sys.stderr); sys.exit(2)
if mode == "broken":
    print("CHAIN records-2026-W34.jsonl:1: record_sha256 重算不符", file=sys.stderr); sys.exit(3)
print(f"未知桩模式 {mode}", file=sys.stderr); sys.exit(9)
EOF

run_chan() {  # 捕获函数输出（真实数据源路径由 gh 桩 + 已 unset 的注入变量控制）
  LLINE=$(llm_channel_account)
}
export STUB_MODE_PATH
export COST_LLM_METERING_DIR="$TMP/ledger"

# 1) DATA：归账成功 → 标签+当月 token+角色档 json
echo data >"$STUB_MODE_PATH"
COST_LLM_METERING_PY="$TMP/bin/metering.py"
run_chan
if [[ "${LLINE%%$'\t'*}" == "DATA" ]] && grep -q '207' <<<"$LLINE" && grep -q '"probe"' <<<"$LLINE"; then
  pass "DATA 形态：当月 token=207 + 角色档 json 透传（$LLINE）"
else fail "DATA 形态不符：$LLINE"; fi

# 2) 空账本（分支已建、尚无周片）→ ZERO（零用量不是 infra）
echo empty >"$STUB_MODE_PATH"
run_chan
if [[ "${LLINE%%$'\t'*}" == "ZERO" ]] && grep -q "用量记 0" <<<"$LLINE"; then
  pass "空账本 → ZERO（零用量声明）"
else fail "空账本应 ZERO，得到：$LLINE"; fi

# 3) 链断 → INFRA（不可信数据不入账——fail-closed 方向）
echo broken >"$STUB_MODE_PATH"
run_chan
if [[ "${LLINE%%$'\t'*}" == "INFRA" ]] && grep -q "不可信数据不入账" <<<"$LLINE"; then
  pass "链断 → INFRA（归账拒绝，fail-closed）"
else fail "链断应 INFRA，得到：$LLINE"; fi

# 4) 归账引擎缺失 → INFRA（配置面残缺可见）
COST_LLM_METERING_PY="$TMP/nope.py"
run_chan
if [[ "${LLINE%%$'\t'*}" == "INFRA" ]] && grep -q "归账引擎不可用" <<<"$LLINE"; then
  pass "引擎缺失 → INFRA（sparse checkout 缺失可见）"
else fail "引擎缺失应 INFRA，得到：$LLINE"; fi

# 5) 分支未建（tarball 与 branches 查询都 404）→ ZERO
unset COST_LLM_METERING_DIR COST_LLM_METERING_PY
gh() { return 1; }
run_chan
unset -f gh
if [[ "${LLINE%%$'\t'*}" == "ZERO" ]] && grep -q "未建" <<<"$LLINE"; then
  pass "账本分支未建 → ZERO（尚无 LLM 调用落账）"
else fail "分支未建应 ZERO，得到：$LLINE"; fi

# 6) tarball 拉取失败但分支存在 → INFRA（用量不可知，不盲熔断不静默归零）
gh() { case "$*" in *tarball*) return 1 ;; *) return 0 ;; esac; }
run_chan
unset -f gh
if [[ "${LLINE%%$'\t'*}" == "INFRA" ]] && grep -q "tarball 拉取失败" <<<"$LLINE"; then
  pass "tarball 失败+分支在 → INFRA（fail-closed 出口 2 的判定输入）"
else fail "tarball 失败应 INFRA，得到：$LLINE"; fi

echo "----------------------------------------"
if [[ $FAILS -eq 0 ]]; then echo "test-cost-llm-channel PASS（6/6）"; exit 0; fi
echo "test-cost-llm-channel FAIL：$FAILS 处"; exit 1
