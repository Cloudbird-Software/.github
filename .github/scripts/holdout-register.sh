#!/usr/bin/env bash
# holdout-register.sh —— holdout 注册入口脚本（W2-C4 .github#276 / AC-17 / IFACE-01）
#
# 由验证者 APP（verifier-app）令牌调用，向 holdout 仓注册一条已封存的验收测试条目，
# 并校验 sealed_sha256（复用 ADR-0068 揭封 hash 校验）。
#
# 调用约定：
#   令牌 = 验证者 APP 单仓作用域 App 令牌（REPO=holdout scripts/gh-app-token.sh 铸造）；
#   验证者 APP 未创建（expected-state.json#verifier_app.id=null）时，
#      VERIFIER_APP_ID 未配置则降级为「留痕待补验」（不阻断，IFACE-01 时序约束）。
#
# 用法：
#   bash scripts/holdout-register.sh --entry <HO-NNNN> --sealed-sha256 <64-hex> \
#       [--actor <app-or-owner>] [--holdout-root <dir>] [--record-out <file>]
#
# 环境变量：
#   VERIFIER_APP_ID       验证者 APP id（未配置=降级留痕）
#   ORG_OWNER             owner login（owner 路径豁免）
#   GITHUB_REPOSITORY     当前仓（默认 Cloudbird-Software/.github）
#
# 退出码：0=注册留痕 | 1=拒绝/校验失败 | 2=参数/环境错误（fail-closed）
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-Cloudbird-Software/.github}"
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOV="$(dirname "$SCRIPTDIR")/governance"

ENTRY=""
SEALED_SHA=""
ACTOR="${HOLDOUT_REG_ACTOR:-}"
HOLDOUT_ROOT=""
RECORD_OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --entry) ENTRY="$2"; shift 2;;
    --sealed-sha256) SEALED_SHA="$2"; shift 2;;
    --actor) ACTOR="$2"; shift 2;;
    --holdout-root) HOLDOUT_ROOT="$2"; shift 2;;
    --record-out) RECORD_OUT="$2"; shift 2;;
    *) echo "错误：未知参数 $1" >&2; exit 2;;
  esac
done

if [[ -z "$ENTRY" || -z "$SEALED_SHA" ]]; then
  echo "错误：必填 --entry 与 --sealed-sha256" >&2; exit 2
fi
if [[ ! "$SEALED_SHA" =~ ^[0-9a-f]{64}$ ]]; then
  echo "错误：sealed_sha256 须为 64 位 hex（ADR-0056 canonical）" >&2; exit 2
fi
if [[ ! "$ENTRY" =~ ^HO-[0-9]{4}$ ]]; then
  echo "错误：entry id 格式须为 HO-NNNN" >&2; exit 2
fi

echo "=== holdout-register: $ENTRY ==="
echo "repo=$REPO sealed_sha256=${SEALED_SHA:0:16}..."

# ---- 身份解析 ----
if [[ -z "$ACTOR" ]]; then
  # 从 GitHub event 上下文推断：App 令牌调用者即 sender
  ACTOR="${GITHUB_ACTOR:-unknown}"
fi
echo "actor=$ACTOR"

# ---- 可选：自动 clone 公开 holdout 仓（公开只读）作 hash 独立校验 ----
CLONE_ROOT=""
if [[ -z "$HOLDOUT_ROOT" ]]; then
  CLONE_ROOT="$(mktemp -d -t holdout-register-XXXXXX)"
  echo "clone holdout 公开仓 → $CLONE_ROOT（公开只读，独立 hash 校验）"
  git clone --depth 1 --filter=blob:none --sparse \
    "https://github.com/Cloudbird-Software/holdout" "$CLONE_ROOT" >/dev/null 2>&1 || true
  if [[ -d "$CLONE_ROOT/entries" ]]; then
    git -C "$CLONE_ROOT" sparse-checkout set entries >/dev/null 2>&1 || true
  fi
  HOLDOUT_ROOT="$CLONE_ROOT"
fi

# ---- 本地 hash 校验（有 checkout 则独立验；否则以入参 sealed_sha256 为准）----
if [[ -f "$HOLDOUT_ROOT/entries/$ENTRY.json" ]]; then
  echo "本地校验 $ENTRY sealed_sha256（ADR-0068 揭封公式）..."
  PYOUT="$(python3 - "$ENTRY" "$SEALED_SHA" "$HOLDOUT_ROOT" <<'PYEOF'
import json, hashlib, sys
eid, given, root = sys.argv[1], sys.argv[2], sys.argv[3]
with open(f"{root}/entries/{eid}.json", encoding="utf-8") as f:
    e = json.load(f)
payload = e.get("payload", {})
canon = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
computed = hashlib.sha256(canon.encode("utf-8")).hexdigest()
for f in payload.get("files", []):
    import base64
    raw = base64.b64decode(f.get("content_b64", ""), validate=True)
    if hashlib.sha256(raw).hexdigest() != f.get("sha256"):
        print(f"FAIL file {f.get('name')} sha256 不符"); sys.exit(1)
if computed != given:
    print(f"FAIL sealed_sha256 不符 computed={computed[:16]}… given={given[:16]}…"); sys.exit(1)
print(f"OK sealed_sha256={computed}")
PYEOF
  )"
  echo "$PYOUT"
  if [[ "$PYOUT" == FAIL* ]]; then
    echo "::error::holdout $ENTRY sealed_sha256 校验失败（试卷被篡改，fail-closed）" >&2
    exit 1
  fi
else
  echo "本地无 $ENTRY checkout（public clone 失败或未 checkout），跳过独立 hash 校验（以入参为准）"
fi

# ---- 注册留痕 ----
RECORD="holdout-register-${ENTRY}-$(date -u +%Y%m%dT%H%M%SZ).json"
cat > "$RECORD" <<EOF_RECORD
{
  "schema": "holdout-register/v1",
  "ts": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repo": "$REPO",
  "entry_id": "$ENTRY",
  "sealed_sha256": "$SEALED_SHA",
  "actor": "$ACTOR",
  "note": "验证者 APP 注册入口（IFACE-01）；verifier_app.id=null 时降级留痕待补验"
}
EOF_RECORD
echo "注册留痕 → $RECORD"
if [[ -n "$RECORD_OUT" ]]; then
  cp "$RECORD" "$RECORD_OUT"
  echo "记录输出 → $RECORD_OUT"
fi

# ---- 清理 ----
if [[ -n "$CLONE_ROOT" && -d "$CLONE_ROOT" ]]; then
  rm -rf "$CLONE_ROOT"
fi

echo "holdout-register 完成：$ENTRY by $ACTOR"
exit 0
