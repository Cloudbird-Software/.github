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
env_code=$(curl -sS -o /dev/null -w '%{http_code}' \
  -X PUT \
  -H "Authorization: Bearer $(gh auth token)" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$ORG/$REPO/environments/production" \
  -d "{\"reviewers\": [{\"type\": \"User\", \"id\": $USER_ID}], \"deployment_branch_policy\": {\"protected_branches\": true, \"custom_branch_policies\": false}}")
echo "environment: $env_code"
[[ "$env_code" =~ ^2 ]] || { echo "错误：production environment 创建失败（HTTP $env_code）——RL-1 未落地，新仓不可用" >&2; exit 1; }

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
  # 红队 #17-K：挂载失败曾只 echo 手动路径后照常打"完成"（exit 0）——
  # 新仓表面初始化成功实际 agent 无写权限。现在 fail-loud：
  echo "错误：app installation 失败（HTTP $code）——AG-4 未落地" >&2
  echo "  手动修复路径：GitHub → Settings → Applications → cloudbrid-agent → Configure → Repository access 勾选 $REPO" >&2
  echo "  修复后重跑本脚本（幂等）验证。" >&2
  exit 1
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
  # 用固定引用执行（红队 #17-L：main 未 pin 的远端脚本在 admin 上下文执行=供应链风险）：
  #   1) 先取当前 main 的 commit sha 并记录
  #   2) bash <(curl -sS https://raw.githubusercontent.com/$ORG/.github/<sha>/scripts/new-repo-init.sh) <name>
  # 本脚本自检（改动后）: bash -n scripts/new-repo-init.sh
  # 然后开第一个 PR，确认 gate 跑绿后合并
EOF
