#!/usr/bin/env bash
# =============================================================================
# 为 Cloudbird-Software 三个公开仓创建 PR：
#   A. .github         — actions allowlist 放行 harden-runner/scorecard-action
#                        + 本仓 scorecard 周扫
#   B. CI-Workflows    — 4 个 reusable workflow 首步加 Harden-Runner(egress audit)
#                        + 本仓 scorecard 周扫
#   C. template-service— automerge job（持有 AGENT_APP_SECRET）加 Harden-Runner
#                        + 本仓 scorecard 周扫
# 前置：gh CLI 已用【人类账号】登录（workflow 文件改动 App 令牌无权限，
#       见 AGENTS.md 硬规则 2）。所有 action 均按组织惯例 pin 到 commit SHA。
# 用法：bash apply-egress-audit-and-scorecard.sh
# =============================================================================
set -euo pipefail

ORG=Cloudbird-Software
HR_SHA=05e31511f85b41b11d1cf0ef85d0992719546e2c; HR_VER=v2.21.0   # step-security/harden-runner
SC_SHA=2d1146689b8cda280b9bc96326124645441f03bc; SC_VER=v2.4.4    # ossf/scorecard-action
CQ_SHA=c16c0f3f2812ec4bb3750a5ed64873fe2ce0fbef; CQ_VER=codeql-bundle-v2.26.3  # github/codeql-action
CK_V7=3d3c42e5aac5ba805825da76410c181273ba90b1;  CK_V7_VER=v7.0.1 # actions/checkout（CI-Workflows/template-service 现行）
CK_V5=08c6903cd8c0fde910a37f88322edcfb5dd907a8;  CK_V5_VER=v5.0.0 # actions/checkout（.github 仓现行）

command -v gh >/dev/null 2>&1 || { echo "ERROR: 需要 gh CLI"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "ERROR: 需要 git"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: 需要 python3"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh 未登录（用人类账号 gh auth login，勿用 App 令牌）"; exit 1; }

WORK=$(mktemp -d /tmp/cloudbird-changes.XXXXXX)
trap 'echo "工作目录: $WORK"' EXIT
cd "$WORK"

# 在单个 job 的第一个 step 前插入 Harden-Runner（audit 模式：只记录出网，不拦截）
insert_harden_runner() {
  python3 - "$1" "${HR_SHA}" "${HR_VER}" <<'PY'
import sys
path, sha, ver = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding="utf-8").read()
needle = "    steps:\n"
assert needle in s, f"未找到 steps: 于 {path}"
add = (
    "    steps:\n"
    "      - name: Harden Runner (egress audit)\n"
    f"        uses: step-security/harden-runner@{sha} # {ver}\n"
    "        with:\n"
    "          egress-policy: audit\n"
)
open(path, "w", encoding="utf-8").write(s.replace(needle, add, 1))
print("  + harden-runner:", path)
PY
}

# 生成 scorecard 周扫 workflow（$1=文件路径 $2=cron $3=checkout SHA $4=checkout 版本注释）
write_scorecard() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: scorecard
on:
  branch_protection_rule:
  schedule:
    - cron: "$2"
  push:
    branches: [main]

permissions: read-all

jobs:
  analysis:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      id-token: write
      contents: read
      actions: read
    steps:
      - uses: actions/checkout@$3 # $4
        with:
          persist-credentials: false
      - name: Scorecard analysis
        uses: ossf/scorecard-action@$SC_SHA # $SC_VER
        with:
          results_file: results.sarif
          results_format: sarif
          publish_results: true
      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@$CQ_SHA # $CQ_VER
        with:
          sarif_file: results.sarif
EOF
  echo "  + scorecard:   $1 (cron $2)"
}

echo "=================================================================="
echo "PR A: $ORG/.github（allowlist + scorecard）"
echo "=================================================================="
gh repo clone "$ORG/.github" repo-dotgithub -- --depth 1 >/dev/null 2>&1
cd repo-dotgithub
git checkout -q -b chore/egress-audit-and-scorecard

cat > governance/expected-state.json <<'EOF'
{
  "org": "Cloudbird-Software",
  "comment": "组织治理期望状态。drift-check.sh 据此检测漂移；apply.sh 据此幂等修复。ruleset 完整定义在 rulesets/ 目录。",
  "actions_policy": {
    "allowed_actions": "selected",
    "github_owned_allowed": true,
    "verified_allowed": true,
    "patterns_allowed": [
      "zizmorcore/*",
      "astral-sh/*",
      "step-security/harden-runner",
      "ossf/scorecard-action",
      "dependabot/fetch-metadata",
      "softprops/action-gh-release",
      "docker/*",
      "Cloudbird-Software/*"
    ],
    "default_workflow_permissions": "read",
    "default_workflow_permissions_can_approve": false
  },
  "code_security": {
    "configuration_name": "GitHub recommended",
    "default_for_new_repos": "all"
  },
  "repo_baseline": {
    "squash_only": true,
    "delete_branch_on_merge": true,
    "exclude_repos": ["AI_Web_School"]
  },
  "org_secrets_required": ["CB_APP_ID", "AGENT_APP_SECRET"],
  "github_app": {
    "name": "cloudbrid-agent",
    "id": 4632704,
    "permissions": {
      "contents": "write",
      "issues": "write",
      "metadata": "read",
      "pull_requests": "write"
    },
    "must_not_have": ["workflows", "administration"]
  }
}
EOF

write_scorecard ".github/workflows/scorecard.yml" "0 5 * * 1" "$CK_V5" "$CK_V5_VER"

git add -A
git -c user.name="$(gh api user -q .login)" -c user.email="$(gh api user -q .login)@users.noreply.github.com" \
  commit -q -m "chore(governance): allow harden-runner/scorecard-action; add scorecard scan"
git push -q -u origin HEAD
gh pr create --fill-first >/dev/null || true
gh pr edit --title "chore(governance): 放行 harden-runner/scorecard-action + scorecard 周扫" --body "$(cat <<'EOF'
## 为什么
- zizmor 是**静态**审计，挡不住"已放行 action 厂商被投毒后的运行时外联"（tj-actions 模式）；automerge job 持有 `AGENT_APP_SECRET`，需出网监控（supply_chain 敞口）
- Scorecard 补仓库安全姿态公开基线（低频战略性层）

## 内容
1. `expected-state.json`：actions allowlist 增加 `step-security/harden-runner`、`ossf/scorecard-action`（最小粒度，非通配符，符合 identity_scope 姿态）
2. 新增本仓 `scorecard.yml` 周扫（周一 05:00 UTC，与 governance-drift 03:00 错峰），SARIF 进 Security tab

## ADR 草稿（GM-2 C1 要求，合并后回填 agent-registry/decisions/）
```
# ADR-00XX: 放行 step-security/harden-runner 与 ossf/scorecard-action
- 状态: accepted
- 日期: 2026-08-18
- 背景: CI-4(zizmor) 仅静态审计；runner 运行时出网无监控。automerge job 持有
  AGENT_APP_SECRET（组织级写权限凭据），一旦外传=组织失守。
- 决策: allowlist 增加两 action（使用处一律 pin SHA）；Harden-Runner 先 audit
  模式跑基线，稳定后按工作流 allowlist 切 block（确定性、可 blocking）。
- 后果: 每个 job 增加约 5s；需维护每工作流出网域名清单。
```

## 合并后必做（owner）
```bash
bash governance/apply.sh   # 把新 allowlist 推到 org Actions 设置
```
EOF
)" >/dev/null
echo "PR A: $(gh pr view --json url -q .url)"
cd "$WORK"

echo "=================================================================="
echo "PR B: $ORG/CI-Workflows（reusable workflows 加 egress audit + scorecard）"
echo "=================================================================="
gh repo clone "$ORG/CI-Workflows" repo-ciw -- --depth 1 >/dev/null 2>&1
cd repo-ciw
git checkout -q -b chore/harden-runner-audit

for f in hygiene.yml check.yml dep-review.yml release.yml; do
  insert_harden_runner ".github/workflows/$f"
done
write_scorecard ".github/workflows/scorecard.yml" "30 5 * * 1" "$CK_V7" "$CK_V7_VER"

git add -A
git -c user.name="$(gh api user -q .login)" -c user.email="$(gh api user -q .login)@users.noreply.github.com" \
  commit -q -m "feat(ci): add Harden-Runner egress audit to reusable workflows; add scorecard"
git push -q -u origin HEAD
gh pr create --fill-first >/dev/null || true
gh pr edit --title "feat(ci): reusable workflows 加 Harden-Runner egress audit + scorecard" --body "$(cat <<'EOF'
## 内容
1. hygiene / check / dep-review / release 四个 reusable job **首步**加 Harden-Runner（`egress-policy: audit`：只记录出网、不拦截、零风险）
2. 新增本仓 scorecard 周扫（周一 05:30 UTC）
3. 全部 pin SHA（v2.21.0 = `05e31511`），过 zizmor

## audit 跑约 2 周后切 block 的起点 allowlist（按各 job 实际日志收敛）
- **hygiene**: github.com, api.github.com, objects.githubusercontent.com（gitleaks 下载）, astral.sh（uv 安装器）, pypi.org, files.pythonhosted.org（uvx zizmor）
- **check(node)**: 上述 + registry.npmjs.org, nodejs.org
- **dep-review**: api.github.com
- **release**: api.github.com, uploads.github.com, objects.githubusercontent.com, registry.npmjs.org, fulcio.sigstore.dev, rekor.sigstore.dev, tuf-repo-cdn.sigstore.dev（attestation）

## 合并后（owner 手工；v* 受 release-tags ruleset 保护，admin 可 bypass）
```bash
git tag v1.2.0 && git tag -f v1 && git push origin v1.2.0 v1 --force
```
> 注意：本 PR 自身检查不执行新 step（本仓 ci.yml 是内联副本），合并+bump 标签后由调用方（template-service 等）实际生效。

## 前置依赖
依赖 PR A（allowlist）先合并并 `apply.sh`——否则 bump v1 后调用方 CI 会因 action 未放行而失败。
EOF
)" >/dev/null
echo "PR B: $(gh pr view --json url -q .url)"
cd "$WORK"

echo "=================================================================="
echo "PR C: $ORG/template-service（automerge 加 egress audit + scorecard）"
echo "=================================================================="
gh repo clone "$ORG/template-service" repo-tpl -- --depth 1 >/dev/null 2>&1
cd repo-tpl
git checkout -q -b chore/harden-runner-scorecard

insert_harden_runner ".github/workflows/automerge.yml"
write_scorecard ".github/workflows/scorecard.yml" "0 6 * * 1" "$CK_V7" "$CK_V7_VER"

git add -A
git -c user.name="$(gh api user -q .login)" -c user.email="$(gh api user -q .login)@users.noreply.github.com" \
  commit -q -m "chore(ci): harden automerge job with egress audit; add scorecard scan"
git push -q -u origin HEAD
gh pr create --fill-first >/dev/null || true
gh pr edit --title "chore(ci): automerge 加 Harden-Runner egress audit + scorecard 周扫" --body "$(cat <<'EOF'
## 为什么
automerge 是全组织**唯一在 runner 上接触 `AGENT_APP_SECRET`（App 私钥→组织级写权限）的 job**，也是 supply_chain 敞口里最值得监控的单点。`pull_request_target` + secrets 组合正是 2025-2026 Megalodon/GhostAction 攻击的目标形态。

## 内容
1. automerge job 首步加 Harden-Runner（audit 模式），pin SHA v2.21.0
2. 新增本仓 scorecard 周扫（周一 06:00 UTC）

## 切 block 时的起点 allowlist
- automerge: api.github.com:443, github.com:443（create-github-app-token + gh pr merge 仅此两个域）

## 生效说明
- automerge 改动随本仓 main 即刻生效（不依赖 v1 标签）
- ci.yml 引用的 reusable workflows 的 audit 要等 CI-Workflows bump v1 后生效
EOF
)" >/dev/null
echo "PR C: $(gh pr view --json url -q .url)"
cd "$WORK"

echo "=================================================================="
echo "完成。3 个 PR 已创建，请按顺序："
echo "  1. 合并 .github 的 PR → bash governance/apply.sh"
echo "  2. 合并 CI-Workflows 的 PR → bump v1.2.0/v1 标签"
echo "  3. 合并 template-service 的 PR"
echo "=================================================================="
