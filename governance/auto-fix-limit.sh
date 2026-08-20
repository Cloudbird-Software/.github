#!/usr/bin/env bash
# auto-fix-limit.sh —— agent 修复循环上限执法（ADR-0040，P2-8 .github#93）
#
# 扫描受管仓 open PR：统计每个 PR 各 commit 上 gate check run 的最新失败结论数。
# 计数真源 = Checks API（commit 元数据）——无内存态/状态文件，runner 崩溃或 workflow
# 重启后计数天然续接而非清零（工作卡 T3 持久性由构造保证）。
#
# 达上限（policy/automation-limits.yaml auto_fix.max_attempts，默认 3）：
#   撤 auto-merge → 关闭 PR → 打 exhausted 标签 → 在 .github 仓开说明 issue（含失败 run 链接）。
# 带 exhausted 标签被 reopen 的 PR 由下一轮再次关闭（计数是历史事实，不因 reopen 归零）。
#
# 熔断置位（org 变量 AUTO_MERGE_DISABLED，由 cost-check.sh 负责"置"）时：
# 本脚本每轮撤所有 open PR 的 auto-merge——硬停的机器执法，新 enable 旁路窗口 ≤ 扫描周期。
#
# 用法: GH_TOKEN=<org admin token> bash auto-fix-limit.sh
# 注入（测试/聚焦，T1）: AUTOFIX_MAX_ATTEMPTS / AUTOFIX_CHECK_NAME / AUTOFIX_AUTHOR /
#   AUTOFIX_REPOS（逗号表）/ AUTOFIX_ALL_PRS=1（全量 open PR）/ AUTOFIX_DRY_RUN=1（只报告不写）
# 退出码: 0=无超限 | 1=本轮关闭了超限 PR（运行变红=可见信号）| 2=基础设施故障（fail-closed）
set -uo pipefail

ORG="${ORG:-Cloudbird-Software}"
DIR="$(cd "$(dirname "$0")" && pwd)"
GOV_REPO="$ORG/.github"
GH="${GH:-gh}"
DRY_RUN="${AUTOFIX_DRY_RUN:-0}"
EXHAUSTED_CLOSED=0
INFRA=0

ok()    { echo "OK    $1"; }
act()   { echo "ACT   $1"; }
infra() { echo "INFRA $1" >&2; INFRA=$((INFRA+1)); }

[[ -n "${GH_TOKEN:-}" ]] || { echo "FATAL: GH_TOKEN 未设置（需 org admin token）" >&2; exit 2; }

# ---------- policy 读取（python 解析 YAML；逐行 KEY=value，无 eval；tr 去 CR 兼容 Windows python）----------
POLICY_ENV=$(python3 - "$DIR/policy/automation-limits.yaml" <<'PYEOF' | tr -d '\r'
import sys, yaml
try:
    c = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
    a, k = c["auto_fix"], c["circuit_breaker"]
    rows = [("AF_MAX_ATTEMPTS", a["max_attempts"]), ("AF_CHECK_NAME", a["check_name"]),
            ("AF_AUTHOR", a["author"]), ("AF_OPT_IN_LABEL", a["opt_in_label"]),
            ("AF_EXHAUSTED_LABEL", a["exhausted_label"]), ("AF_ISSUE_LABEL", a["issue_label"]),
            ("AF_FAILED_CONCLUSIONS", ",".join(a["failed_conclusions"])),
            ("CB_VARIABLE", k["variable"])]
    for kk, vv in rows:
        vv = str(vv)
        assert "=" not in vv and "\n" not in vv, f"policy 值含非法字符: {kk}"
        print(f"{kk}={vv}")
except Exception as e:
    sys.exit(f"policy 解析失败: {e}")
PYEOF
) || { echo "FATAL: policy/automation-limits.yaml 解析失败" >&2; exit 2; }
while IFS='=' read -r key val; do declare "$key=$val"; done <<< "$POLICY_ENV"
for v in AF_MAX_ATTEMPTS AF_CHECK_NAME AF_AUTHOR AF_OPT_IN_LABEL AF_EXHAUSTED_LABEL AF_ISSUE_LABEL AF_FAILED_CONCLUSIONS CB_VARIABLE; do
  [[ -n "${!v:-}" ]] || { echo "FATAL: policy 缺 $v" >&2; exit 2; }
done
# 环境注入优先（T1 负向注入通道）
MAX_ATTEMPTS="${AUTOFIX_MAX_ATTEMPTS:-$AF_MAX_ATTEMPTS}"
CHECK_NAME="${AUTOFIX_CHECK_NAME:-$AF_CHECK_NAME}"
AUTHOR="${AUTOFIX_AUTHOR:-$AF_AUTHOR}"

# ---------- 受管仓清单：REPOS.yaml 全量 active；AUTOFIX_REPOS 逗号表覆盖 ----------
if [[ -n "${AUTOFIX_REPOS:-}" ]]; then
  REPOS="${AUTOFIX_REPOS//,/ }"
else
  REPOS=$(python3 - "$DIR/REPOS.yaml" <<'PYEOF' | tr -d '\r'
import sys, yaml
try:
    repos = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["repos"]
    print(" ".join(r["name"] for r in repos if r.get("status") == "active"))
except Exception as e:
    sys.exit(f"REPOS.yaml 解析失败: {e}")
PYEOF
) || { echo "FATAL: REPOS.yaml 解析失败" >&2; exit 2; }
fi
[[ -n "$REPOS" ]] || { echo "FATAL: 受管仓清单为空" >&2; exit 2; }

# ---------- helpers ----------
mutate() {  # DRY_RUN 拦截一切写操作（本地验证不产生副作用）
  if [[ "$DRY_RUN" == "1" ]]; then echo "DRY   (skip) $*"; else "$@"; fi
}
label_ensure() {  # <repo> <label> <color> —— 幂等（已存在即成功）
  mutate "$GH" label create "$2" --repo "$1" \
    --description "auto-fix-limit 执法标记（勿手工使用）" --color "$3" >/dev/null 2>&1 || true
}
gov_issue_find() {  # <label> <title-fragment> → issue number（无则空）
  "$GH" issue list --repo "$GOV_REPO" --state open --label "$1" --limit 100 \
    --json number,title --jq ".[] | select(.title | contains(\"$2\")) | .number" 2>/dev/null | head -1
}

# ---------- 熔断状态（只读；置位在 cost-check.sh，复位仅人工——ADR-0040 决策 4） ----------
BREAKER_SET=0
VERR=$("$GH" api "orgs/$ORG/actions/variables/$CB_VARIABLE" --jq .value 2>&1) || true
if [[ "$VERR" == *"true"* && "$VERR" != *"Not Found"* ]]; then
  BREAKER_SET=1
  ok "熔断标志 $CB_VARIABLE=true（本轮附带撤销全部 auto-merge）"
elif grep -q "Not Found" <<<"$VERR"; then
  ok "熔断标志 $CB_VARIABLE 未置位"
else
  # 读失败 ≠ 未置位：fail-closed 出口 2（不假置位——假熔断要求人工复位，会把流水线停摆）
  infra "org 变量 $CB_VARIABLE 读取失败（非 404）：$(head -c 200 <<<"$VERR")"
fi

# ---------- 逐仓扫描 ----------
for repo in $REPOS; do
  PRJSON=$("$GH" pr list --repo "$ORG/$repo" --state open --limit 200 \
    --json number,author,labels,autoMergeRequest 2>/dev/null)
  if [[ -z "$PRJSON" ]]; then
    # 仓库无 open PR 时 gh pr list 输出 "[]"；空串=拉取失败（fail-closed，不静默跳过）
    if ! PRCHECK=$("$GH" pr list --repo "$ORG/$repo" --state open --limit 1 --json number 2>&1); then
      infra "PR 清单拉取失败: $repo（$(head -c 120 <<<"$PRCHECK")）"
    else
      ok "$repo: 无 open PR"
    fi
    continue
  fi
  while IFS=$'\t' read -r num prauthor labelcsv amflag; do
    [[ -n "${num:-}" ]] || continue
    # 熔断执法（不分作者——硬停是全局语义）：撤 auto-merge
    if [[ "$amflag" == "1" && $BREAKER_SET -eq 1 ]]; then
      if mutate "$GH" api -X DELETE "repos/$ORG/$repo/pulls/$num/auto-merge" >/dev/null 2>&1; then
        act "熔断执法: 撤销 $repo#$num 的 auto-merge"
      fi
    fi
    # 作用域：agent PR（默认）/ opt-in 标签 / AUTOFIX_ALL_PRS 注入
    # 作者匹配兼容两种 API 形态：REST pulls = "<slug>[bot]"，GraphQL(gh pr list) = "app/<slug>"
    if [[ "${AUTOFIX_ALL_PRS:-0}" != "1" && "$prauthor" != "$AUTHOR" && "$prauthor" != "${AUTHOR}[bot]" \
          && "$prauthor" != "app/$AUTHOR" && ",$labelcsv," != *",$AF_OPT_IN_LABEL,"* ]]; then
      continue
    fi
    # ---- 修复尝试计数（真源 = Checks API）----
    COMMITS=$("$GH" api "repos/$ORG/$repo/pulls/$num/commits?per_page=100" --jq '.[].sha' 2>/dev/null)
    if [[ -z "$COMMITS" ]]; then
      infra "commit 清单拉取失败: $repo#$num"
      continue
    fi
    mapfile -t SHAS <<< "$COMMITS"
    HEAD_SHA="${SHAS[-1]}"
    if [[ "${#SHAS[@]}" -ge 100 ]]; then
      # >100 commit 的 agent PR 本身即失控形态——直接按超限处置（fail-closed 方向）
      FAILS=$MAX_ATTEMPTS; FAIL_ROWS="(commit 数 ≥100，逐条省略——按失控处置)"
    else
      FAILS=0; FAIL_ROWS=""
      for sha in "${SHAS[@]}"; do
        # 该 commit 上最新一次 gate run（同名多次取 id 最大——rerun 语义）；无 gate run → absent。
        # 退出码非 0 = API 故障（fail-closed 记账）；jq 保证正常时总有输出
        if ! ROW=$("$GH" api "repos/$ORG/$repo/commits/$sha/check-runs" \
          --jq "([.check_runs[] | select(.name == \"$CHECK_NAME\")] | sort_by(.id) | last | [.conclusion // \"none\", (.html_url // \"-\")]) // [\"absent\", \"-\"] | @tsv" 2>/dev/null); then
          infra "check-runs 拉取失败: $repo#$num @${sha:0:8}"
          continue
        fi
        IFS=$'\t' read -r concl url <<< "$ROW"
        # 失败判定：结论在 failed_conclusions；非头 commit 上的未完成（none）/从未上报（absent）
        # = 陈旧残留或不可验证，亦计（fail-closed 方向：多计早关优于少计烧额度）
        if [[ ",$AF_FAILED_CONCLUSIONS," == *",$concl,"* ]] \
           || { [[ "$concl" == "none" || "$concl" == "absent" ]] && [[ "$sha" != "$HEAD_SHA" ]]; }; then
          FAILS=$((FAILS+1))
          FAIL_ROWS+="- ${sha:0:8} $concl: $url"$'\n'
        fi
      done
    fi
    if [[ $FAILS -lt $MAX_ATTEMPTS ]]; then
      ok "$repo#$num ($prauthor): 修复尝试 $FAILS/$MAX_ATTEMPTS"
      continue
    fi
    # ---- 超限处置：撤 auto-merge → 关 PR → 标签 → issue ----
    if [[ "$amflag" == "1" ]]; then
      mutate "$GH" api -X DELETE "repos/$ORG/$repo/pulls/$num/auto-merge" >/dev/null 2>&1 || true
    fi
    label_ensure "$ORG/$repo" "$AF_EXHAUSTED_LABEL" b60205
    mutate "$GH" pr edit "$num" --repo "$ORG/$repo" --add-label "$AF_EXHAUSTED_LABEL" >/dev/null 2>&1 || true
    mutate "$GH" pr close "$num" --repo "$ORG/$repo" --comment \
      "auto-fix 上限触发（ADR-0040）：$CHECK_NAME 失败 $FAILS 次 ≥ 上限 $MAX_ATTEMPTS。自动关闭并不再重试；失败历史见 .github 仓说明 issue。人工续作：修复后新开 PR（勿 reopen 本 PR）。" \
      >/dev/null 2>&1 || true   # 竞态（本轮已被关/合）不算 infra；issue 通道已有去重兜底
    EXHAUSTED_CLOSED=$((EXHAUSTED_CLOSED+1))
    act "超限关闭: $repo#$num（$FAILS 次失败 ≥ $MAX_ATTEMPTS）"
    # 说明 issue（.github 仓，幂等）
    label_ensure "$GOV_REPO" "$AF_ISSUE_LABEL" b60205
    TITLE="auto-fix 上限触发：$repo#$num 修红 $FAILS 次未过（上限 $MAX_ATTEMPTS）"
    EXISTING=$(gov_issue_find "$AF_ISSUE_LABEL" "$repo#$num ")
    BODY="无人值守修复循环超限自动报告（ADR-0040，运行于 $(date -u +%FT%TZ)）。

- PR: $ORG/$repo#$num（作者 $prauthor）
- 失败 $FAILS 次（上限 $MAX_ATTEMPTS，policy/automation-limits.yaml#auto_fix）
- PR 已自动关闭并打标签 \`$AF_EXHAUSTED_LABEL\`——不得 reopen（重开会被下轮扫描再关）

失败历史（每次尝试的 $CHECK_NAME run）：
$FAIL_ROWS
处置建议：人工检查该 PR 根因（修不好通常是判据/环境问题而非代码问题）；如需续作，修复后新开 PR。"
    if [[ -n "$EXISTING" ]]; then
      mutate "$GH" issue comment "$EXISTING" --repo "$GOV_REPO" --body "$BODY" >/dev/null 2>&1 || true
    else
      mutate "$GH" issue create --repo "$GOV_REPO" --title "$TITLE" --body "$BODY" \
        --label "$AF_ISSUE_LABEL" >/dev/null 2>&1 || infra "说明 issue 开立失败: $repo#$num"
    fi
  done < <("$GH" pr list --repo "$ORG/$repo" --state open --limit 200 \
    --json number,author,labels,autoMergeRequest \
    --jq '.[] | [.number, .author.login, (if (.labels | length) > 0 then (.labels | map(.name) | join(",")) else "-" end), (if .autoMergeRequest != null then "1" else "0" end)] | @tsv' 2>/dev/null)
  # 注：空 labels 用 "-" 占位——tab 属 IFS 空白类，read 会折叠连续 tab 使空列塌缩错位（实测）
done

# ---------- 基础设施故障通道（exit 2 + 专属 issue，与超限通道分离——ADR-0040 决策 5） ----------
if [[ $INFRA -gt 0 ]]; then
  label_ensure "$GOV_REPO" auto-fix-infra 9a6700
  EXISTING=$(gov_issue_find auto-fix-infra "auto-fix-limit 扫描基础设施故障")
  BODY="auto-fix-limit 扫描出现 $INFRA 处 API 读失败（运行 $(date -u +%FT%TZ)）——计数/执法可信度受损，须排查（限流/凭据/端点变更）。fail-closed：本次运行按 exit 2 变红。"
  if [[ -n "$EXISTING" ]]; then
    mutate "$GH" issue comment "$EXISTING" --repo "$GOV_REPO" --body "$BODY" >/dev/null 2>&1 || true
  else
    mutate "$GH" issue create --repo "$GOV_REPO" --title "auto-fix-limit 扫描基础设施故障（非超限）" \
      --body "$BODY" --label auto-fix-infra >/dev/null 2>&1 || true
  fi
  exit 2
fi

[[ $EXHAUSTED_CLOSED -gt 0 ]] && exit 1
ok "扫描完成：$(wc -w <<<"$REPOS") 仓，超限关闭 $EXHAUSTED_CLOSED 个 PR"
exit 0
