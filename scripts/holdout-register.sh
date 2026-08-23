#!/usr/bin/env bash
# holdout-register.sh —— holdout 注册入口（W2-C4 .github#276 / ADR-0068 / AC-17 / AC-18）
#
# 由验证者 APP 执行（IFACE-01 时序闸：验证者 APP 未就绪时本脚本 dry-run 占位）。
# 经 verifier APP 令牌调用 pipeline/adversary/holdout_registry.py register，
# 将 holdout 条目注册到 registry（hash 落盘，供 PR 引用一致性检查消费）。
#
# 凭据：
#   - 验证者 APP 私钥：VERIFIER_APP_SECRET_FILE（PEM 路径）或 VERIFIER_APP_SECRET（PEM 字面量）
#   - 验证者 APP_ID：VERIFIER_APP_ID（从 expected-state.json#verifier_app.id 读取）
#   - 未就绪时 HOLDOUT_REGISTRY_MODE=dry-run（占位注册，不落 push）
#
# 用法：
#   VERIFIER_APP_ID=<id> VERIFIER_APP_SECRET_FILE=<pem> \
#     bash scripts/holdout-register.sh <card-id> <entry-id> <sha256> <registry-path>
#
# 退出码：0=注册成功 | 1=参数错误 | 2=registry/环境错误 | 3=非验证者 APP 写入被拒
set -euo pipefail

ORG="${ORG:-Cloudbird-Software}"
CARD="${1:?用法: holdout-register.sh <card-id> <entry-id> <sha256> <registry-path>}"
ENTRY="${2:?用法: holdout-register.sh <card-id> <entry-id> <sha256> <registry-path>}"
SHA256="${3:?用法: holdout-register.sh <card-id> <entry-id> <sha256> <registry-path>}"
REGISTRY="${4:?用法: holdout-register.sh <card-id> <entry-id> <sha256> <registry-path>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOV_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY_PY="$GOV_ROOT/../CI-Workflows/pipeline/adversary/holdout_registry.py"

# 验证者 APP 身份解析
VERIFIER_APP_ID="${VERIFIER_APP_ID:-}"
if [[ -z "$VERIFIER_APP_ID" || "$VERIFIER_APP_ID" == "null" ]]; then
  # 尝试从 expected-state.json 读取
  EXPECTED_STATE="$GOV_ROOT/governance/expected-state.json"
  if [[ -f "$EXPECTED_STATE" ]]; then
    PY_BIN=""
    for _c in python3 python py; do
      if command -v "$_c" >/dev/null 2>&1 && "$_c" -c 'print(1)' >/dev/null 2>&1; then PY_BIN="$_c"; break; fi
    done
    if [[ -n "$PY_BIN" ]]; then
      VERIFIER_APP_ID=$("$PY_BIN" -c "import json; print(json.load(open('$EXPECTED_STATE')).get('verifier_app',{}).get('id') or '')" 2>/dev/null || true)
    fi
  fi
fi

if [[ -z "$VERIFIER_APP_ID" || "$VERIFIER_APP_ID" == "null" ]]; then
  echo "信息：验证者 APP 未就绪（verifier_app.id=null）— 以 dry-run 占位注册（不落 push）" >&2
  export HOLDOUT_REGISTRY_MODE=dry-run
else
  # 取验证者 APP 令牌（单仓作用域=holdout）
  if [[ -n "${VERIFIER_APP_SECRET_FILE:-}" || -n "${VERIFIER_APP_SECRET:-}" ]]; then
    export CB_APP_ID="$VERIFIER_APP_ID"
    export REPO="holdout"
    echo "==> 铸验证者 APP 令牌（单仓作用域=holdout）" >&2
    VERIFIER_TOKEN=$(VERIFIER_APP_SECRET_FILE="${VERIFIER_APP_SECRET_FILE:-}" \
                     VERIFIER_APP_SECRET="${VERIFIER_APP_SECRET:-}" \
                     bash "$SCRIPT_DIR/gh-app-token.sh" 2>/tmp/verifier-token-err.log) || {
      echo "警告：验证者 APP 令牌铸币失败（$(head -1 /tmp/verifier-token-err.log 2>/dev/null)）— 降级为 dry-run" >&2
      export HOLDOUT_REGISTRY_MODE=dry-run
    }
    if [[ -n "${VERIFIER_TOKEN:-}" ]]; then
      export HOLDOUT_REGISTRY_MODE=verifier
      echo "验证者 APP 身份就绪（id=$VERIFIER_APP_ID）" >&2
    fi
  else
    echo "警告：未提供验证者 APP 私钥（VERIFIER_APP_SECRET_FILE/VERIFIER_APP_SECRET）— 降级为 dry-run" >&2
    export HOLDOUT_REGISTRY_MODE=dry-run
  fi
fi

# 定位 registry 创建脚本
if [[ ! -f "$REGISTRY_PY" ]]; then
  # 备选：仓内相对路径（CI-Workflows 与 .github 同级目录结构）
  ALT="$GOV_ROOT/../CI-Workflows/pipeline/adversary/holdout_registry.py"
  [[ -f "$ALT" ]] && REGISTRY_PY="$ALT"
fi

if [[ ! -f "$REGISTRY_PY" ]]; then
  echo "错误：找不到 holdout_registry.py（$REGISTRY_PY）" >&2
  exit 2
fi

echo "==> 注册 holdout 条目：$CARD/$ENTRY = ${SHA256:0:11} (mode=${HOLDOUT_REGISTRY_MODE})" >&2
py "$REGISTRY_PY" register --card "$CARD" --entry "$ENTRY" --sha256 "$SHA256" --registry "$REGISTRY"
