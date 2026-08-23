#!/usr/bin/env bash
# holdout-register.sh —— holdout 注册入口脚本（W2-C4 .github#276，AC-17 / ADR-0068）
#
# 由验证者 APP 令牌调用（非验证者 APP 写入被拒，覆盖跨仓场景）。
# 接线 CI-Workflows pipeline/adversary/holdout_registry.py。
#
# 用法:
#   bash scripts/holdout-register.sh <repo> <entry.json>
# 环境变量:
#   GH_TOKEN / APP_TOKEN = 验证者 APP 令牌（workflow 注入）
#   VERIFIER_APP_SLUG = 验证者 APP slug（缺省 verifier-app[bot]）
#
# 退出码: 0=注册成功 | 1=校验失败/拒绝 | 2=infra 错误

set -euo pipefail

REPO="${1:?用法: holdout-register.sh <repo> <entry.json>}"
ENTRY_PATH="${2:?用法: holdout-register.sh <repo> <entry.json>}"
VERIFIER_SLUG="${VERIFIER_APP_SLUG:-verifier-app[bot]}"

if [[ ! -f "$ENTRY_PATH" ]]; then
  echo "::error::条目文件不存在: $ENTRY_PATH"
  exit 2
fi

# 校验条目 sealed_sha256（ADR-0068 公式，与 unseal_gate.py 同式）
# 使用 CI-Workflows 的 holdout_registry.py 做 hash 校验
CIW_DIR="${CIW_DIR:-CI-Workflows}"
REGISTRY_PY="$CIW_DIR/pipeline/adversary/holdout_registry.py"

if [[ ! -f "$REGISTRY_PY" ]]; then
  echo "::error::holdout_registry.py 不存在: $REGISTRY_PY（需先 checkout CI-Workflows）"
  exit 2
fi

echo "== holdout 注册入口（W2-C4 / ADR-0068）=="
echo "repo: $REPO"
echo "entry: $ENTRY_PATH"
echo "actor: $VERIFIER_SLUG"

# 身份校验（AC-17）：非验证者 APP 写入被拒
ACTOR="${GH_ACTOR:-${ACTOR:-unknown}}"
if [[ "$ACTOR" != "$VERIFIER_SLUG" ]]; then
  # 允许人类 owner 写入（workflow 层 owner 校验兜底）
  if [[ "$ACTOR" == *"[bot]"* ]]; then
    echo "::error::非验证者 APP 写入被拒（AC-17）: actor=$ACTOR 期望=$VERIFIER_SLUG"
    exit 1
  fi
  echo "人类用户写入: $ACTOR（workflow 层 owner 校验兜底）"
fi

# hash 校验
echo "--- hash 校验 ---"
if ! python3 "$REGISTRY_PY" verify-hash --entry "$ENTRY_PATH"; then
  echo "::error::hash 校验失败（ADR-0068）"
  exit 1
fi

# 注册（经 holdout_registry.py）
echo "--- 注册条目 ---"
TOKEN="${APP_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "::error::无验证者 APP 令牌（APP_TOKEN / GH_TOKEN 未设置）"
  exit 2
fi

export GH_TOKEN="$TOKEN"
if python3 "$REGISTRY_PY" register --entry "$ENTRY_PATH" --actor "$VERIFIER_SLUG" --repo "$REPO"; then
  echo "AUDIT | repo=$REPO | actor=$VERIFIER_SLUG | verdict=registered"
  exit 0
else
  echo "::error::注册失败"
  exit 1
fi
