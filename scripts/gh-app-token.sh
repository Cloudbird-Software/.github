#!/usr/bin/env bash
# gh-app-token.sh —— 用 cloudbird-agent App 私钥换取 1 小时有效的安装令牌
#
# 这是 agent 与 GitHub 交互的唯一推荐认证方式：
#   - 权限最小：Contents / Pull requests / Issues 读写，无 admin、无 Workflows 改动权
#   - 令牌 1 小时自动过期，磁盘上不落任何长期凭据（私钥妥善保管即可）
#   - 所有操作以 cloudbird-agent[bot] 身份进入审计日志，与人类账号区分
#   - ruleset 照样生效：App 不能直推 main，必须走 PR 过 gate
#
# 依赖：bash curl openssl jq（无需任何 GitHub SDK）
#
# 用法：
#   export CB_APP_ID=123456                                # App 详情页的 App ID
#   export CB_APP_KEY_FILE=~/.config/cloudbird/cloudbird-agent.pem
#   # CI / secret 场景改用字面量： export CB_APP_KEY="<PEM 全文>"
#
#   GH_TOKEN=$(bash gh-app-token.sh)                        # 作用域=安装的全部仓库
#   GH_TOKEN=$(REPO=template-service bash gh-app-token.sh)  # 作用域=单仓库（推荐）
#   gh api user                                             # 验证：应显示 cloudbird-agent[bot]
set -euo pipefail

API="${CB_GITHUB_API:-https://api.github.com}"
ORG="${ORG:-Cloudbird-Software}"
APP_ID="${CB_APP_ID:?需要环境变量 CB_APP_ID（GitHub App 设置页的 App ID）}"

# 私钥：优先文件，其次字面量（CI secret 里通常存 PEM 全文）
if [[ -n "${CB_APP_KEY_FILE:-}" && -f "$CB_APP_KEY_FILE" ]]; then
  KEY=$(cat "$CB_APP_KEY_FILE")
elif [[ -n "${CB_APP_KEY:-}" ]]; then
  KEY="$CB_APP_KEY"
else
  echo "错误：需要 CB_APP_KEY_FILE（私钥文件路径）或 CB_APP_KEY（PEM 内容）" >&2
  exit 1
fi

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '=\n'; }

# 1) 生成 App JWT（RS256 签名，9 分钟有效，容忍时钟偏差）
now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 480))" "$APP_ID" | b64url)
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign <(printf '%s\n' "$KEY") | b64url)
JWT="$header.$payload.$signature"

gh_api() { curl -sS -H "Authorization: Bearer $JWT" -H "Accept: application/vnd.github+json" "$@"; }

# 2) 定位组织内的 installation id
INSTALL_ID=$(gh_api "$API/app/installations?per_page=100" \
  | jq -r --arg org "$ORG" '.[] | select((.account.login | ascii_downcase) == ($org | ascii_downcase)) | .id' | head -1)
if [[ -z "$INSTALL_ID" ]]; then
  echo "错误：找不到 $ORG 的 installation。请先安装 App：Settings → Applications → cloudbird-agent → Configure" >&2
  exit 1
fi

# 3) JWT 换安装令牌；REPO 非空时把令牌限定到单仓库（最小权限）
BODY='{}'
[[ -n "${REPO:-}" ]] && BODY=$(jq -nc --arg r "$REPO" '{repositories: [$r]}')
RESP=$(curl -sS -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  -d "$BODY" "$API/app/installations/$INSTALL_ID/access_tokens")

TOKEN=$(jq -r '.token // empty' <<<"$RESP")
if [[ -z "$TOKEN" ]]; then
  echo "错误：换令牌失败：$RESP" >&2
  exit 1
fi

echo "令牌有效至 $(jq -r .expires_at <<<"$RESP")（作用域：${REPO:-全部已安装仓库}，身份 cloudbird-agent[bot]）" >&2
echo "$TOKEN"
