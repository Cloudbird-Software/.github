#!/usr/bin/env bash
# 新仓库初始化脚本 —— 从 template-service 生成仓库后运行一次。
# 模板只复制文件；仓库设置和 production environment 必须逐仓配置，本脚本一键完成。
#
# 用法: ./new-repo-init.sh <repo-name>
# 前提: gh 已登录，且对组织有 admin 权限。

set -euo pipefail

ORG="${ORG:-Cloudbird-Software}"
REPO="${1:?用法: $0 <repo-name>}"
USER_LOGIN=$(gh api user -q .login)
USER_ID=$(gh api user -q .id)

echo "==> 1/3 仓库基线设置（squash-only / 删分支 / auto-merge / 关 wiki+projects）"
gh repo edit "$ORG/$REPO" \
  --enable-auto-merge --delete-branch-on-merge \
  --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false \
  --enable-wiki=false --enable-projects=false

echo "==> 2/4 production environment（B 档：required reviewer + 仅受保护分支）"
curl -sS -o /dev/null -w "environment: %{http_code}\n" \
  -X PUT \
  -H "Authorization: Bearer $(gh auth token)" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$ORG/$REPO/environments/production" \
  -d "{\"reviewers\": [{\"type\": \"User\", \"id\": $USER_ID}], \"deployment_branch_policy\": {\"protected_branches\": true, \"custom_branch_policies\": false}}"

echo "==> 3/4 把新仓库挂到 cloudbrid-agent 安装（agent 才能写这个仓库）"
INSTALL_ID=$(gh api "/orgs/$ORG/installations?per_page=100" \
  --jq '.installations[] | select(.app_slug == "cloudbrid-agent") | .id')
NEW_RID=$(gh api "repos/$ORG/$REPO" --jq .id)
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
  -H "Authorization: Bearer $(gh auth token)" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/user/installations/$INSTALL_ID/repositories/$NEW_RID")
if [[ "$code" == "204" ]]; then
  echo "app installation: OK (repo#$NEW_RID -> installation#$INSTALL_ID)"
else
  echo "app installation: HTTP $code —— 手动路径：GitHub → Settings → Applications →"
  echo "  cloudbrid-agent → Configure → Repository access 勾选 $REPO"
fi

echo "==> 4/4 验证"
echo "environment:"
curl -sS -H "Authorization: Bearer $(gh auth token)" \
  "https://api.github.com/repos/$ORG/$REPO/environments/production" | jq -c '{rules: [.protection_rules[].type]}'
echo "repo:"
gh repo view "$ORG/$REPO" --json name,deleteBranchOnMerge,mergeCommitAllowed,rebaseMergeAllowed

cat <<EOF

完成。后续新仓标准流程：
  gh repo create $ORG/<name> --template $ORG/template-service --public --clone
  cd <name> && bash <(curl -sS https://raw.githubusercontent.com/$ORG/.github/main/scripts/new-repo-init.sh) <name>
  # 然后开第一个 PR，确认 gate 跑绿后合并
EOF
