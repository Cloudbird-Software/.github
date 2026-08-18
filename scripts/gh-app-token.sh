#!/usr/bin/env bash
# gh-app-token.sh —— 用 cloudbrid-agent App 私钥换取 1 小时有效的安装令牌
#
# 这是 agent 与 GitHub 交互的唯一推荐认证方式：
#   - 权限最小：Contents / Pull requests / Issues 读写，无 admin、无 Workflows 改动权
#   - 令牌 1 小时自动过期，磁盘上不落任何长期凭据（私钥妥善保管即可）
#   - 所有操作以 cloudbrid-agent[bot] 身份进入审计日志，与人类账号区分
#   - ruleset 照样生效：App 不能直推 main，必须走 PR 过 gate
#
# 依赖：bash curl openssl jq（无需任何 GitHub SDK）
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
#   gh api user                                             # 验证：应显示 cloudbrid-agent[bot]
set -euo pipefail

API="${CB_GITHUB_API:-https://api.github.com}"
ORG="${ORG:-Cloudbird-Software}"
APP_ID="${CB_APP_ID:?需要环境变量 CB_APP_ID（GitHub App 设置页的 App ID）}"
# REPO 强制（评审项）：不设 REPO 时令牌作用域=安装的全部仓库，违反最小权限——
# agent 只应以单仓作用域取令牌（AG-1：agent 的写权限以仓为单位显式授予）
REPO="${REPO:?需要环境变量 REPO（目标仓库名——令牌强制单仓作用域，不提供全安装作用域模式）}"

# 私钥：优先文件，其次字面量（CI secret 里通常存 PEM 全文）
if [[ -n "${AGENT_APP_SECRET_FILE:-}" && -f "$AGENT_APP_SECRET_FILE" ]]; then
  KEY=$(cat "$AGENT_APP_SECRET_FILE")
elif [[ -n "${AGENT_APP_SECRET:-}" ]]; then
  KEY="$AGENT_APP_SECRET"
else
  echo "错误：需要 AGENT_APP_SECRET_FILE（私钥文件路径）或 AGENT_APP_SECRET（PEM 内容）" >&2
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
  echo "错误：找不到 $ORG 的 installation。请先安装 App：Settings → Applications → cloudbrid-agent → Configure" >&2
  exit 1
fi

# 3) JWT 换安装令牌；令牌限定到单仓库（REPO 必填——最小权限，评审项）
BODY=$(jq -nc --arg r "$REPO" '{repositories: [$r]}')
RESP=$(curl -sS -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  -d "$BODY" "$API/app/installations/$INSTALL_ID/access_tokens")

TOKEN=$(jq -r '.token // empty' <<<"$RESP")
if [[ -z "$TOKEN" ]]; then
  echo "错误：换令牌失败：$RESP" >&2
  exit 1
fi

echo "令牌有效至 $(jq -r .expires_at <<<"$RESP")（作用域：单仓库 $REPO，身份 cloudbrid-agent[bot]）" >&2
echo "$TOKEN"
