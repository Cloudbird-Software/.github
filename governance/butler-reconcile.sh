#!/usr/bin/env bash
# butler-reconcile.sh —— 管家主收敛循环（唤醒矩阵行 1；ADR-0057，W1-C5 .github#168；宪法 §11）
#
# 每 6h（或 workflow_dispatch 手动）遍历 REPOS.yaml active 仓做三类一致性检查：
#   (a) 僵尸卡：open issue 挂 state:in-progress 且 updated 距今 > stale_in_progress_days
#       → .github 仓开/评论 needs-human issue（label butler:needs-human）；同卡去重：
#         已有 open issue 标题含 "<repo>#<num> " 即评论不重开，且同日已评论则跳过（防灌水）
#   (b) 孤儿标签：已移除（ADR-0074 修订 ADR-0057）——closed issue 退出状态机，
#       其 state:* 标签是历史事实非漂移（closed+state:done 是正常终态形态）；
#       管家不纠正历史（INV-02）。
#   (c) 隔离超时：open issue 挂 state:quarantine 且 updated 距今 > stale_quarantine_days
#       → 升 needs-human（同 (a) 去重）。用 updated 代理"停留时长"：隔离期间仍有人
#       评论/更新 = 有活动，不升级是合理语义；静置才是要抓的滞留。
#
# 令牌分离（最小权限）：
#   - 跨仓读 = GH_TOKEN（CI 注入 org secret GOVERNANCE_TOKEN；缺失 → fail-closed 变红
#     + 审计行，不静默降级——宪法 §6）。
#   - 写 issue/label = GH_WRITE_TOKEN（CI 注入 GITHUB_TOKEN，仅本仓 issues:write）：
#     报告与 needs-human issue 全部开在 .github 仓，无跨仓写需求，用运行级令牌即够
#     （不把 org admin 治理令牌用在 issue 评论上）。
#
# 阈值真源 governance/policy/butler.yaml（脚本读它，不读注释）。
# 注入（演习/预检，同 PR_LIVENESS_HOURS 模式——workflow_dispatch 输入注入，不留常开旁路）：
#   STALE_DAYS_OVERRIDE（0=立即 stale——AC-2 演习用）、STALE_QUARANTINE_DAYS_OVERRIDE、
#   BUTLER_RECONCILE_REPOS（逗号表，聚焦扫描）、BUTLER_DRY_RUN=1（只报告不写）
# 退出码：0=全绿 | 1=有发现（needs-human/报告已动作——变红=可见信号，同 drift-check/
#   cost-check 模式）| 2=基础设施故障（fail-closed）
set -uo pipefail

ORG="${ORG:-Cloudbird-Software}"
DIR="$(cd "$(dirname "$0")" && pwd)"
GOV_REPO="$ORG/.github"
GH="${GH:-gh}"
DRY_RUN="${BUTLER_DRY_RUN:-0}"
INFRA=0
FINDINGS=0
TODAY=$(date -u +%F)
TRIGGER="${BUTLER_TRIGGER:-${GITHUB_EVENT_NAME:-manual}}"

source "$DIR/butler-audit.sh"   # audit_emit（INV-12 审计行唯一来源）

ok()    { echo "OK    $1"; }
act()   { echo "ACT   $1"; }
infra() { echo "INFRA $1" >&2; INFRA=$((INFRA+1)); }
audit() { audit_emit reconcile "$TRIGGER" "$1" "$2" || infra "AUDIT 行输出失败（INV-12 完整性受损）"; }

# ---------- 令牌（fail-closed：读令牌缺失不静默——审计行可见后变红） ----------
if [[ -z "${GH_TOKEN:-}" ]]; then
  audit infra-fail '{"fatal":"GH_TOKEN missing (CI: org secret GOVERNANCE_TOKEN)"}' || true
  echo "::error::GH_TOKEN 未设置（CI=org secret GOVERNANCE_TOKEN，跨仓读）。设置: 组织 Settings → Secrets and variables → Actions → New organization secret" >&2
  exit 2
fi
GH_WRITE_TOKEN="${GH_WRITE_TOKEN:-$GH_TOKEN}"
ghw() { GH_TOKEN="$GH_WRITE_TOKEN" "$GH" "$@"; }   # 本仓写（CI=GITHUB_TOKEN）；读直接用 $GH（读 GH_TOKEN 环境变量）

# ---------- 阈值真源 butler.yaml（python 解析；逐行 KEY=value，无 eval；tr 去 CR 兼容 Windows python） ----------
POLICY_ENV=$(python3 - "$DIR/policy/butler.yaml" <<'PYEOF' | tr -d '\r'
import sys, yaml
try:
    t = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["thresholds"]
    rows = [("STALE_DAYS", t["stale_in_progress_days"]),
            ("STALE_Q_DAYS", t["stale_quarantine_days"]),
            ("DEADMAN_GRACE", t["deadman_grace_minutes"])]
    for kk, vv in rows:
        vv = str(vv)
        assert "=" not in vv and "\n" not in vv, f"policy 值含非法字符: {kk}"
        print(f"{kk}={vv}")
except Exception as e:
    sys.exit(f"butler.yaml 解析失败: {e}")
PYEOF
) || { audit infra-fail '{"fatal":"butler.yaml unparsable"}' || true; echo "FATAL: policy/butler.yaml 解析失败" >&2; exit 2; }
while IFS='=' read -r key val; do declare "$key=$val"; done <<< "$POLICY_ENV"
for v in STALE_DAYS STALE_Q_DAYS DEADMAN_GRACE; do
  [[ -n "${!v:-}" ]] || { audit infra-fail "{\"fatal\":\"butler.yaml 缺 $v\"}" || true; echo "FATAL: butler.yaml 缺 $v" >&2; exit 2; }
done
# 数值校验（fail-closed，须在父 shell 调用——子 shell 里 infra 计数会丢失）
check_num() {  # <varname> <what>
  local __v="__dummy"
  eval "__v=\$${1:?}"
  if [[ "$__v" =~ ^[0-9]+([.][0-9]+)?$ ]]; then return 0; fi
  infra "非数值（$2）: '$__v'——判定输入无效"
  eval "$1=0"
}
# 环境注入优先（演习通道；空=真源值）
STALE_DAYS="${STALE_DAYS_OVERRIDE:-$STALE_DAYS}"
STALE_Q_DAYS="${STALE_QUARANTINE_DAYS_OVERRIDE:-$STALE_Q_DAYS}"
check_num STALE_DAYS "in-progress stale 天数"; check_num STALE_Q_DAYS "quarantine stale 天数"

# ---------- 受管仓清单：REPOS.yaml 全量 active；BUTLER_RECONCILE_REPOS 逗号表覆盖 ----------
if [[ -n "${BUTLER_RECONCILE_REPOS:-}" ]]; then
  REPOS="${BUTLER_RECONCILE_REPOS//,/ }"
else
  REPOS=$(python3 - "$DIR/REPOS.yaml" <<'PYEOF' | tr -d '\r'
import sys, yaml
try:
    repos = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["repos"]
    print(" ".join(r["name"] for r in repos if r.get("status") == "active"))
except Exception as e:
    sys.exit(f"REPOS.yaml 解析失败: {e}")
PYEOF
) || { audit infra-fail '{"fatal":"REPOS.yaml unparsable"}' || true; echo "FATAL: REPOS.yaml 解析失败" >&2; exit 2; }
fi
[[ -n "$REPOS" ]] || { audit infra-fail '{"fatal":"active repo list empty"}' || true; echo "FATAL: 受管仓清单为空" >&2; exit 2; }
REPO_COUNT=$(wc -w <<< "$REPOS" | tr -d ' ')

# stale 判定阈值（epoch 秒；python 算一次容忍小数天。STALE_DAYS=0 → 任何过去时刻都 stale=演习全触发）
stale_ts() {  # <days> → epoch 阈值
  python3 -c "import time,sys; print(int(time.time() - float(sys.argv[1])*86400))" "$1" | tr -d '\r'
}
STALE_TS=$(stale_ts "$STALE_DAYS") || { audit infra-fail '{"fatal":"stale_ts compute failed"}' || true; exit 2; }
STALE_Q_TS=$(stale_ts "$STALE_Q_DAYS") || { audit infra-fail '{"fatal":"stale_q_ts compute failed"}' || true; exit 2; }

audit running "{\"phase\":\"start\",\"repos\":$REPO_COUNT,\"stale_in_progress_days\":$STALE_DAYS,\"stale_quarantine_days\":$STALE_Q_DAYS,\"dry_run\":$DRY_RUN}"

# ---------- helpers ----------
mutate() {  # DRY_RUN 拦截一切写操作（本地验证不产生副作用）
  if [[ "$DRY_RUN" == "1" ]]; then echo "DRY   (skip) $*"; else "$@"; fi
}
label_ensure() {  # <repo> <label> <color> —— 幂等（已存在即成功）
  mutate ghw label create "$2" --repo "$1" \
    --description "管家 butler 标记（勿手工使用）" --color "$3" >/dev/null 2>&1 || true
}
# 当日已有评论/创建则跳过评论（防 6h cron 重复灌水——同 cost-check 模式）
issue_silent_today() {  # <number> → 0=今日已动过（静默），1=需要评论
  local last
  last=$(ghw issue view "$1" --repo "$GOV_REPO" --json createdAt,comments \
    --jq '[.comments[].createdAt, .createdAt] | max' 2>/dev/null) || return 1
  [[ "$last" == "$TODAY"* ]]
}
# 同卡去重键 "<repo>#<num> "（尾空格防前缀碰撞：mutual#200 不误中 mutual#2001）
needs_human_find() {  # <repo> <num> → open needs-human issue 号（无则空）
  ghw issue list --repo "$GOV_REPO" --state open --label butler:needs-human --limit 100 \
    --json number,title --jq ".[] | select(.title | contains(\"$1#$2 \")) | .number" 2>/dev/null | head -1
}
# 单仓 issue 行：num<TAB>updated<TAB>closed<TAB>labels(csv)<TAB>title（API 失败 → 非零退出）
repo_issue_rows() {  # <repo> <state(open|closed)>
  "$GH" api --paginate "repos/$ORG/$1/issues?state=$2&per_page=100" \
    --jq '.[] | select(.pull_request == null) | [.number, .updated_at, (.closed_at // "-"), ([.labels[].name] | join(",")), .title] | @tsv' 2>/dev/null
}

# needs-human 升级（开/评论，双去重：同卡不重开 + 同日不重评）
escalate() {  # <repo> <num> <kind(stale-in-progress|stale-quarantine)> <age_days> <body>
  local r="$1" n="$2" kind="$3" age="$4" body="$5" existing
  FINDINGS=$((FINDINGS+1))
  label_ensure "$GOV_REPO" butler:needs-human fb8c04   # 幂等（已存在即成功）——create --label 前必须先保证标签存在
  local ttl="[butler] $kind: $r#$n （停滞 ${age}d 达阈值）"
  existing=$(needs_human_find "$r" "$n")
  if [[ -n "$existing" ]]; then
    if issue_silent_today "$existing"; then
      ok "needs-human 已开（#$existing）且今日已评论，跳过（防灌水）: $r#$n"
    else
      mutate ghw issue comment "$existing" --repo "$GOV_REPO" --body "$body" >/dev/null 2>&1 || true
      act "needs-human 追评: #$existing（$r#$n 仍超时）"
    fi
  else
    mutate ghw issue create --repo "$GOV_REPO" --title "$ttl" --body "$body" \
      --label butler:needs-human >/dev/null 2>&1 || infra "needs-human issue 开立失败: $r#$n"
    act "needs-human 开立: $ttl"
  fi
  audit needs-human "{\"escalate\":\"$r#$n\",\"kind\":\"$kind\",\"age_days\":$age}"
}

# ---------- 主循环：三类检查 ----------
STALE_COUNT=0; QUAR_COUNT=0
for repo in $REPOS; do
  # ---- open issues：(a) 僵尸卡 + (c) 隔离超时 ----
  if ! OPEN_ROWS=$(repo_issue_rows "$repo" open); then
    infra "open issue 清单拉取失败: $repo"
  else
    while IFS=$'\t' read -r num updated closed labels title; do
      [[ -n "${num:-}" ]] || continue
      upd_ep=""
      case ",$labels," in
        *,state:in-progress,*|*,state:quarantine,*)
          upd_ep=$(_butler_iso2epoch "$updated")
          if [[ -z "$upd_ep" ]]; then infra "updated_at 解析失败: $repo#$num"; continue; fi
          ;;
      esac
      case ",$labels," in
        *,state:in-progress,*)
          if (( upd_ep < STALE_TS )); then
            STALE_COUNT=$((STALE_COUNT+1))
            age_days=$(( ( $(date -u +%s) - upd_ep ) / 86400 ))
            escalate "$repo" "$num" stale-in-progress "$age_days" \
              "僵尸卡检测（ADR-0057，唤醒矩阵行 1，运行 $(date -u +%FT%TZ)，trigger=$TRIGGER）：

- 卡: $ORG/$repo#$num「$title」
- state:in-progress 停滞（updated=${updated}，阈值 ${STALE_DAYS}d）——事件驱动的推进可能已丢失，需人工确认状态。
- 处置：卡仍活着 → 评论/推进（updated 刷新后下轮自愈）；已死 → 改状态标签或关闭。
- 本 issue 由管家自动开立；同卡不重开，同日去重评论。"
          else
            ok "$repo#$num: in-progress 活跃（updated=${updated}）"
          fi
          ;;
        *,state:quarantine,*)
          if (( upd_ep < STALE_Q_TS )); then
            QUAR_COUNT=$((QUAR_COUNT+1))
            age_days=$(( ( $(date -u +%s) - upd_ep ) / 86400 ))
            escalate "$repo" "$num" stale-quarantine "$age_days" \
              "隔离超时检测（ADR-0057，唤醒矩阵行 1，运行 $(date -u +%FT%TZ)，trigger=$TRIGGER）：

- 卡: $ORG/$repo#$num「$title」
- state:quarantine 停留超阈值（updated=${updated}，阈值 ${STALE_Q_DAYS}d）——隔离应有处置 SLA，不应无限期滞留。
- 处置：人工重判（/retry 回 ready 或关闭/归档）。
- 本 issue 由管家自动开立；同卡不重开，同日去重评论。"
          else
            ok "$repo#$num: quarantine 停留中未超时（updated=${updated}）"
          fi
          ;;
      esac
    done <<< "$OPEN_ROWS"
  fi
  # ---- closed issues：不检查（ADR-0074 修订 ADR-0057，原检查 (b) 已移除）----
  # closed issue 退出状态机，其 state:* 标签是历史事实（label 真相源只约束在制
  # 工作）非漂移对象：#130-134 的 closed+state:done 是正常终态形态，原检查只产
  # 噪音（run 32484413154 报 6 条全噪音，owner 裁决"不重要"）。管家不纠正历史
  # （INV-02：状态标签写须 App 令牌经仲裁）。closed 清单因此不再拉取。
done
ok "扫描完成：$REPO_COUNT 仓，僵尸卡 $STALE_COUNT / 隔离超时 $QUAR_COUNT（closed 历史标签不检——ADR-0074）"

# ---------- 报告 issue（label butler:reconcile 固定去重；全绿不新开防灌水） ----------
REPORT_ACTION="green-silent"
REPORT_EXISTING=$(ghw issue list --repo "$GOV_REPO" --state open --label butler:reconcile \
  --json number --jq '.[0].number' 2>/dev/null)
if [[ $FINDINGS -gt 0 ]]; then
  label_ensure "$GOV_REPO" butler:reconcile 1d76db
  REPORT_BODY="管家 reconcile 报告（唤醒矩阵行 1，ADR-0057，运行 $(date -u +%FT%TZ)，trigger=$TRIGGER）：

- 僵尸卡（state:in-progress 停滞 > ${STALE_DAYS}d）: $STALE_COUNT
- 隔离超时（state:quarantine 停滞 > ${STALE_Q_DAYS}d）: $QUAR_COUNT

（closed issue 的历史 state:* 标签不检——ADR-0074：退出状态机即为历史事实。
僵尸卡/隔离超时的明细见 label butler:needs-human 的 issue；本报告聚合计数。）"
  if [[ -n "$REPORT_EXISTING" ]]; then
    if ! issue_silent_today "$REPORT_EXISTING"; then
      mutate ghw issue comment "$REPORT_EXISTING" --repo "$GOV_REPO" --body "$REPORT_BODY" >/dev/null 2>&1 || true
      REPORT_ACTION="commented"
      act "reconcile 报告追评: #$REPORT_EXISTING"
    else
      REPORT_ACTION="commented-today-skip"
      ok "报告 issue #$REPORT_EXISTING 今日已评论，跳过（防灌水）"
    fi
  else
    mutate ghw issue create --repo "$GOV_REPO" \
      --title "管家 reconcile 报告：$REPO_COUNT 仓一致性扫描（僵尸卡/孤儿标签/隔离超时）" \
      --body "$REPORT_BODY" --label butler:reconcile >/dev/null 2>&1 \
      || infra "reconcile 报告 issue 开立失败"
    REPORT_ACTION="opened"
    act "reconcile 报告 issue 已开立"
  fi
elif [[ -n "$REPORT_EXISTING" ]]; then
  # 全绿但存在 open 报告（曾有问题）→ 当日首次补"全绿"评论收口；无报告则不新开（防灌水）
  if ! issue_silent_today "$REPORT_EXISTING"; then
    mutate ghw issue comment "$REPORT_EXISTING" --repo "$GOV_REPO" \
      --body "全绿（运行 $(date -u +%FT%TZ)，trigger=$TRIGGER）：$REPO_COUNT 仓无僵尸卡/孤儿标签/隔离超时。历史问题已消化则可关闭本报告 issue。" \
      >/dev/null 2>&1 || true
    REPORT_ACTION="green-commented"
    act "全绿评论: #$REPORT_EXISTING"
  else
    REPORT_ACTION="green-today-skip"
    ok "报告 issue #$REPORT_EXISTING 今日已评论，全绿不重复评论"
  fi
fi

# ---------- 汇总 AUDIT + 退出码 ----------
if [[ $INFRA -gt 0 ]]; then
  audit infra-fail "{\"repos\":$REPO_COUNT,\"stale_in_progress\":$STALE_COUNT,\"stale_quarantine\":$QUAR_COUNT,\"report\":\"$REPORT_ACTION\",\"infra_failures\":$INFRA}"
  exit 2
fi
if [[ $FINDINGS -gt 0 ]]; then
  audit findings "{\"repos\":$REPO_COUNT,\"stale_in_progress\":$STALE_COUNT,\"stale_quarantine\":$QUAR_COUNT,\"report\":\"$REPORT_ACTION\"}"
  exit 1
fi
audit ok "{\"repos\":$REPO_COUNT,\"stale_in_progress\":0,\"orphan_state_labels\":0,\"stale_quarantine\":0,\"report\":\"$REPORT_ACTION\"}"
exit 0
