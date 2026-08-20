#!/usr/bin/env bash
# gh-app-token.sh —— 用 cloudbrid-agent App 私钥换取 1 小时有效的安装令牌
#
# 这是 agent 与 GitHub 交互的唯一推荐认证方式：
#   - 权限最小：Contents / Pull requests / Issues 读写，无 admin、无 Workflows 改动权
#   - 令牌 1 小时自动过期，磁盘上不落任何长期凭据（私钥妥善保管即可）
#   - 所有操作以 cloudbrid-agent[bot] 身份进入审计日志，与人类账号区分
#   - ruleset 照样生效：App 不能直推 main，必须走 PR 过 gate
#
# 依赖（ADR-0044）：bash、curl、openssl 必需；JSON 工具 jq / python3(python) /
#   node 任一即可（无 jq 环境不再中断——Windows Git Bash 默认无 jq）。
#   全部缺失时报错并列安装建议。
#
# Windows 兼容（ADR-0044）：
#   - 签名用临时文件而非进程替换（Windows openssl 读不了 /proc/<pid>/fd/N）
#   - jq 输出统一剥 CRLF（Windows 版 jq 行尾带 \r，会污染令牌）
#
# 令牌缓存（ADR-0044）：
#   - ~/.cache/cloudbird/gh-app-token-<org>-<repo>.json（权限 600；XDG_CACHE_HOME
#     可重定向）。距过期 >5 分钟直接命中（零网络请求）。
#   - 缓存含短期凭据：权限必须 600，路径不得改到仓库或共享目录。
#   - --refresh 强制刷新（排查权限问题时用）。
#
# 用法：
#   export CB_APP_ID=123456                                # App 详情页的 App ID
#   # 私钥注入（评审项）：本地优先 AGENT_APP_SECRET_FILE（文件路径，不进 shell history）；
#   # CI 中由 Actions secret 机制以环境变量注入 AGENT_APP_SECRET（等效 secret manager）。
#   # 禁止在交互 shell 里 `export AGENT_APP_SECRET="-----BEGIN..."`——命令会进
#   # history 且被子进程环境继承；确需临时注入用 read -s 或 secret manager。
#   export AGENT_APP_SECRET_FILE=~/.config/cloudbird/cloudbrid-agent.pem
#
#   GH_TOKEN=$(REPO=template-service bash gh-app-token.sh)  # 作用域=单仓库（强制最小权限）
#   GH_TOKEN=$(REPO=template-service bash gh-app-token.sh --refresh)  # 强制刷新
#   gh api user                                             # 验证：应显示 cloudbrid-agent[bot]
set -euo pipefail

API="${CB_GITHUB_API:-https://api.github.com}"
ORG="${ORG:-Cloudbird-Software}"
APP_ID="${CB_APP_ID:?需要环境变量 CB_APP_ID（GitHub App 设置页的 App ID）}"
# REPO 强制（评审项）：不设 REPO 时令牌作用域=安装的全部仓库，违反最小权限——
# agent 只应以单仓作用域取令牌（AG-1：agent 的写权限以仓为单位显式授予）
REPO="${REPO:?需要环境变量 REPO（目标仓库名——令牌强制单仓作用域，不提供全安装作用域模式）}"

REFRESH=0
for arg in "$@"; do
  case "$arg" in
    --refresh) REFRESH=1 ;;
    *) echo "错误：未知参数 $arg（仅支持 --refresh）" >&2; exit 2 ;;
  esac
done

# 私钥：优先文件，其次字面量（CI secret 里通常存 PEM 全文）
if [[ -n "${AGENT_APP_SECRET_FILE:-}" && -f "${AGENT_APP_SECRET_FILE:-}" ]]; then
  KEY=$(cat "$AGENT_APP_SECRET_FILE")
elif [[ -n "${AGENT_APP_SECRET:-}" ]]; then
  KEY="$AGENT_APP_SECRET"
else
  echo "错误：需要 AGENT_APP_SECRET_FILE（私钥文件路径，如 ~/.config/cloudbird/cloudbrid-agent.pem）或 AGENT_APP_SECRET（PEM 内容）。两者都未提供——检查私钥注入方式（见脚本头注释）。" >&2
  exit 1
fi

# ---------- JSON 工具降级链（ADR-0044：jq → python3/python → node） ----------
have_jq()   { command -v jq >/dev/null 2>&1; }
# python 探测须验证可执行（Windows 商店的 python3 是无功能占位 stub——
# 存在于 PATH 但运行即 exit 49 无输出，按 command -v 误判可用）
PY_BIN=""
for _cand in python3 python; do
  if command -v "$_cand" >/dev/null 2>&1 && "$_cand" -c 'print(1)' >/dev/null 2>&1; then
    PY_BIN="$_cand"; break
  fi
done
have_node() { command -v node >/dev/null 2>&1; }
json_env_error() {
  echo "错误：未找到任何 JSON 工具（jq / python3 / node 均不可用）——脚本四处 JSON 操作无法执行。" >&2
  echo "安装建议：Windows: winget install jqlang.jq 或 scoop install jq；macOS: brew install jq；Debian/Ubuntu: sudo apt install jq；或任一 python3 / node 运行时。" >&2
  exit 1
}

# 取顶层字符串字段：json_field <json> <key>（缺失输出空串）
json_field() {
  local json="$1" key="$2"
  if have_jq; then jq -r --arg k "$key" '.[$k] // empty' <<<"$json" | tr -d '\r'
  elif [[ -n "$PY_BIN" ]]; then "$PY_BIN" -c 'import json,sys
try: d = json.loads(sys.argv[1])
except Exception: sys.exit(3)
v = d.get(sys.argv[2]) if isinstance(d, dict) else None
print("" if v is None else v)' "$json" "$key"
  elif have_node; then node -e 'try{const d=JSON.parse(process.argv[1]);const v=d[process.argv[2]];process.stdout.write(v==null?"":String(v))}catch(e){process.exit(3)}' "$json" "$key"
  else json_env_error; fi
}

# installation 查询：find_install_id <installations-json> <org>（大小写不敏感；无则输出空）
find_install_id() {
  local json="$1" org="$2"
  if have_jq; then jq -r --arg o "$org" '.[] | select((.account.login | ascii_downcase) == ($o | ascii_downcase)) | .id' <<<"$json" | tr -d '\r' | head -1
  elif [[ -n "$PY_BIN" ]]; then "$PY_BIN" -c 'import json,sys
try: arr = json.loads(sys.argv[1])
except Exception: sys.exit(3)
if not isinstance(arr, list): sys.exit(3)
for it in arr:
    if str(it.get("account", {}).get("login", "")).lower() == sys.argv[2].lower():
        print(it["id"]); break' "$json" "$org"
  elif have_node; then node -e 'const a=JSON.parse(process.argv[1]);const m=a.find(x=>String((x.account||{}).login||"").toLowerCase()===process.argv[2].toLowerCase());process.stdout.write(m?String(m.id):"")' "$json" "$org"
  else json_env_error; fi
}

# ISO8601(Z) → epoch 秒：iso_to_epoch <iso>（缓存过期判定用）
iso_to_epoch() {
  local iso="$1"
  if [[ -n "$PY_BIN" ]]; then "$PY_BIN" -c 'import sys,datetime
print(int(datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))' "$iso"
  elif have_node; then node -e 'process.stdout.write(String(Math.floor(Date.parse(process.argv[1])/1000)))' "$iso"
  elif have_jq; then jq -r --arg i "$iso" '$i | sub("\\.[0-9]+Z$";"Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime' <<<"$iso" | tr -d '\r'
  else json_env_error; fi
}

# ---------- 令牌缓存（ADR-0044） ----------
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cloudbird"
CACHE_FILE="$CACHE_DIR/gh-app-token-${ORG}-${REPO}.json"
CACHE_MIN_REMAINING=300   # 距过期 ≤5 分钟即视为失效

cache_load() { # → 0=命中可用（TOKEN/EXPIRES_AT 已设），1=未命中/失效，2=损坏
  [[ -f "$CACHE_FILE" ]] || return 1
  local body
  body=$(cat "$CACHE_FILE" 2>/dev/null) || return 1
  TOKEN=$(json_field "$body" token)
  EXPIRES_AT=$(json_field "$body" expires_at)
  if [[ -z "$TOKEN" || -z "$EXPIRES_AT" ]]; then
    # 非法 JSON（json_field 解析失败/字段缺失）与空文件都按损坏处理
    return 2
  fi
  local exp now
  exp=$(iso_to_epoch "$EXPIRES_AT" 2>/dev/null) || return 2
  now=$(date -u +%s)
  [[ $((exp - now)) -gt $CACHE_MIN_REMAINING ]] || return 1
  return 0
}

cache_store() { # $1=token $2=expires_at
  mkdir -p "$CACHE_DIR" 2>/dev/null || { echo "警告：缓存目录 $CACHE_DIR 不可写，跳过缓存" >&2; return 0; }
  if have_jq; then jq -nc --arg t "$1" --arg e "$2" '{token:$t,expires_at:$e}' > "$CACHE_FILE"
  else printf '{"token":"%s","expires_at":"%s"}' "$1" "$2" > "$CACHE_FILE"
  fi
  chmod 600 "$CACHE_FILE" 2>/dev/null || true   # Windows 无 POSIX 权限，尽力而为
}

if [[ $REFRESH -eq 0 ]]; then
  CRS=0; cache_load || CRS=$?
  if [[ $CRS -eq 0 ]]; then
    echo "令牌（缓存命中）有效至 $EXPIRES_AT（作用域：单仓库 $REPO，身份 cloudbrid-agent[bot]）——距过期 >5min，零网络请求" >&2
    echo "$TOKEN"
    exit 0
  fi
  [[ $CRS -eq 2 ]] && echo "警告：缓存文件 $CACHE_FILE 损坏（非 JSON 或字段缺失）——忽略缓存并强制刷新" >&2
fi

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '=\n'; }

# 1) 生成 App JWT（RS256 签名，9 分钟有效，容忍时钟偏差）
#    签名经临时文件（ADR-0044：Windows/MSYS2 的 openssl 读不了进程替换 /proc/N/fd）
now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 480))" "$APP_ID" | b64url)
KEYFILE=$(mktemp) || { echo "错误：mktemp 失败，无法安全落盘私钥做签名" >&2; exit 1; }
ERRFILE="$KEYFILE.err"
trap 'rm -f "$KEYFILE" "$ERRFILE"' EXIT
chmod 600 "$KEYFILE" 2>/dev/null || true
printf '%s\n' "$KEY" > "$KEYFILE"
if ! signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$KEYFILE" 2>"$ERRFILE" | b64url); then
  echo "错误：JWT 签名失败（openssl）：$(head -2 "$ERRFILE" 2>/dev/null || true)——常见原因：私钥 PEM 格式损坏 / openssl 版本过旧" >&2
  exit 1
fi
rm -f "$KEYFILE"
JWT="$header.$payload.$signature"

gh_api() { curl -sS -H "Authorization: Bearer $JWT" -H "Accept: application/vnd.github+json" "$@"; }

# 2) 定位组织内的 installation id
INSTALL_JSON=$(gh_api "$API/app/installations?per_page=100")
INSTALL_ID=$(find_install_id "$INSTALL_JSON" "$ORG")
if [[ -z "$INSTALL_ID" ]]; then
  # 区分"安装清单拉取失败"与"确实未安装"（fail-loud：报错指向具体原因）
  MSG=$(json_field "$INSTALL_JSON" message 2>/dev/null || true)
  if [[ -n "$MSG" ]]; then
    echo "错误：installation 清单查询失败：$MSG——检查 CB_APP_ID 是否正确 / JWT 签名 / 网络连通" >&2
  else
    echo "错误：找不到 $ORG 的 installation。请先安装 App：Settings → Applications → cloudbrid-agent → Configure（或 ORG 变量指向了错误组织：ORG=$ORG）" >&2
  fi
  exit 1
fi

# 3) JWT 换安装令牌；令牌限定到单仓库（REPO 必填——最小权限，评审项）
BODY=$(printf '{"repositories":["%s"]}' "$REPO")
RESP=$(curl -sS -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  -d "$BODY" "$API/app/installations/$INSTALL_ID/access_tokens")

TOKEN=$(json_field "$RESP" token)
if [[ -z "$TOKEN" ]]; then
  echo "错误：换令牌失败：$RESP——常见原因：REPO 未安装该 App / App 权限被组织侧吊销" >&2
  exit 1
fi
EXPIRES_AT=$(json_field "$RESP" expires_at)

cache_store "$TOKEN" "$EXPIRES_AT"
echo "令牌有效至 $EXPIRES_AT（作用域：单仓库 $REPO，身份 cloudbrid-agent[bot]；已缓存至 $CACHE_FILE，权限 600）" >&2
echo "$TOKEN"
