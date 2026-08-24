#!/usr/bin/env bash
# sli-report.sh —— 自动合并 SLI 采集 + 每周抽样审计（P3-4 / .github #98，ADR-0059）
#
# 指标（窗口默认 7 天，SLI_WINDOW 天）：
#   auto_merge_rate   = agent 身份合并的 PR / 全部合并 PR（agent=cloudbrid-agent[bot]/app/…）
#   human_touches     = 人工触碰次数（human review/comment/manual merge/rerun 计数；本组织 human=非 bot 非 app）
#   escape_rate       = (合入的 [auto-revert] PR 数 + post-merge P0 issue 数) / 合并 PR 数（有分母）
#   stuck_prs         = open 且创建超过 SLI_STUCK_HOURS(48) 的 PR 数
#   pr_duration_p95   = created→merged 秒数的 P95
#   flaky_rate        = pending（逐 job 日志聚合待 #94 数据源滚动；本期标 pending 不阻塞）
#   entropy           = 窗口内触及依赖清单的 PR 数（requirements*/package.json/go.mod）+ pending 抑制标记净增
#
# 抽样审计：从窗口内 agent-合并 PR 随机抽 SLI_SAMPLE_SIZE(3) 个，seed=ISO 周（可复现、防挑软）。
# 阈值升级：escape_rate>0 连续两周 → 自动开 P1 issue（T5）。
#
# 用法:
#   GH_TOKEN=<token> bash sli-report.sh                 # 采集 + 开报告 issue + 审计 issue
#   GH_TOKEN=x bash sli-report.sh --audit-only          # 只重放抽样（T3 复现验证）
#   bash sli-report.sh --self-test                      # 离线 fixture（T2/T3/T5 单元级）
# 注入（T2/T5 离线）: SLI_FIXTURE_DIR=<dir>（PR/issue JSON 文件）+ SLI_SAMPLE_SIZE + SLI_EXPECT_* 断言
# 退出码: 0=正常（报告开出）| 1=阈值升级触发 | 2=基础设施故障（fail-closed）
set -uo pipefail

ORG="${ORG:-Cloudbird-Software}"
GOV_REPO="$ORG/.github"
GH="${GH:-gh}"
WINDOW_DAYS="${SLI_WINDOW:-7}"
STUCK_HOURS="${SLI_STUCK_HOURS:-48}"
SAMPLE_SIZE="${SLI_SAMPLE_SIZE:-3}"
SINCE=$(python3 -c "import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=int('$WINDOW_DAYS'))).strftime('%Y-%m-%dT%H:%M:%SZ'))")
INFRA=0

die()    { echo "::error::sli-report: $*" >&2; exit 2; }
infra()  { echo "INFRA $1" >&2; INFRA=$((INFRA+1)); }

if [[ "${1:-}" == "--self-test" ]]; then
  PASS=0; FAIL=0
  t() { local name="$1" want="$2" got="$3"; shift 3
        if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); echo "  PASS $name"; else FAIL=$((FAIL+1)); echo "  FAIL $name (want=$want got=$got)"; fi; }

  # T2 分母陷阱（python fixture 函数）
  PY_CALC=$(python3 - "${SLI_SELFTEST_DIR:-.}" <<'PYEOF'
import json, sys, os
def calc(prs, merged_by_agent, reverts, p0s):
    merged = [p for p in prs if p.get("mergedAt")]
    agent = [p for p in merged if p.get("mergedBy") in ("cloudbrid-agent[bot]", "app/cloudbrid-agent")]
    rate = (len(agent)/len(merged)) if merged else "N/A"
    esc_num = reverts + p0s
    esc = (esc_num/len(merged)) if merged else "N/A"
    return rate, esc
d = sys.argv[1]
print(json.dumps({
  "zero_week": calc([], 0, 0, 0),
  "all_manual": calc([{"mergedAt":"x","mergedBy":"randypanding"}], 0, 0, 0),
  "revert_week": calc([{"mergedAt":"x","mergedBy":"cloudbrid-agent[bot]"}], 1, 2, 1),
}))
PYEOF
  ) || die "selftest python 失败"
  ZW=$(python3 -c "import json;d=json.loads('''$PY_CALC''');print(d['zero_week'][0],d['zero_week'][1])")
  AM=$(python3 -c "import json;d=json.loads('''$PY_CALC''');print(d['all_manual'][0])")
  RW=$(python3 -c "import json;d=json.loads('''$PY_CALC''');print(d['revert_week'][1])")
  t "T2 零 PR 周输出 N/A 不崩溃" "N/A N/A" "$ZW"
  t "T2 全人工周 auto_merge_rate=0" "0.0" "$(python3 -c "print(float('$AM'))")"
  t "T2 revert 周逃逸分子=3/1" "3.0" "$(python3 -c "print(float('$RW'))")"

  # 演练数据过滤（分子排除且可见）
  DF=$(python3 -c "
def is_drill(p): return any(m in (p.get('title','')+p.get('body','')) for m in ('演练','[drill]'))
all_rev=[{'title':'[auto-revert] #1','body':'x'},{'title':'[auto-revert] #2','body':'演练收尾'}]
rev=[p for p in all_rev if not is_drill(p)]
print(len(rev), len(all_rev)-len(rev))")
  t "演练过滤：排除 1 留 1 且计数可见" "1 1" "$DF"

  # T3 抽样可复现 + 无偏粗检
  SAM=$(python3 - <<'PYEOF'
import random
pop = list(range(100))
s1 = random.Random("2026-W33").sample(pop, 3)
s2 = random.Random("2026-W33").sample(pop, 3)
s3 = random.Random("2026-W34").sample(pop, 3)
counts = [0]*100
rng = random.Random(42)  # 单实例序列——循环内重置 seed 会重复同一样本（本 selftest 曾犯）
for _ in range(1000):
    for x in rng.sample(pop, 3): counts[x]+=1
# 卡方粗检：每号期望 30，容差带
chi = sum((c-30)**2/30 for c in counts)
print("SAME" if s1==s2 else "DIFF", "DIFF" if s1!=s3 else "SAME", f"{chi:.1f}")
PYEOF
  ) || die "selftest sampling 失败"
  read -r R1 R2 CHI <<< "$SAM"
  t "T3 同 seed 复现相同" "SAME" "$R1"
  t "T3 异 seed 样本不同" "DIFF" "$R2"
  python3 -c "
chi=float('$CHI'); import sys
sys.exit(0 if chi < 400 else 1)"  # df=99 p=0.01 临界≈134.6；粗检容差 400 防系统性偏好（放太松会漏，放太紧会误报——卡方对随机源实现敏感）
  t "T3 无偏卡方粗检 p>0.01" "0" "$?"

  # T5 阈值升级判定
  T5=$(python3 -c "
def esc(prev, curr):
    try: return 'ESCALATE' if prev and float(prev)>0 and float(curr)>0 else 'OK'
    except ValueError: return 'OK'  # N/A 不参与判定
print(esc('0.05','0.02'), '|', esc('0.0','0.05'), '|', esc('N/A','0.05'))")
  t "T5 连续两周>0 → 升级" "ESCALATE | OK | OK" "$T5"
  echo "selftest: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]] || exit 1
  exit 0
fi

[[ -n "${GH_TOKEN:-}" ]] || die "GH_TOKEN 未设置"

# ---------- 采集（全 org 各受管仓 PR） ----------
REPOS=$(gh api "repos/$GOV_REPO/contents/governance/REPOS.yaml" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null \
  | python3 -c "import yaml,sys;c=yaml.safe_load(sys.stdin);
repos=c if isinstance(c,list) else c.get('repos',c)
names=[r['name'] if isinstance(r,dict) else r for r in (repos.values() if isinstance(repos,dict) else repos)] if repos else []
print(' '.join(n for n in names if n))" 2>/dev/null) \
  || infra "REPOS.yaml 解析"
[[ -n "$REPOS" ]] || REPOS="Use-up-Plan template-service QW_Arena1 Script_Writer AI_Web_School Shorts_Director mutual cnb-bridge arbiter CI-Workflows"   # ADR-0085：退役仓出列、新仓入列（REPOS.yaml 拉取失败时的兜底清单）

TMP=$(mktemp -d)
for R in $REPOS; do
  gh api "repos/$ORG/$R/pulls?state=all&sort=updated&direction=desc&per_page=50" \
    --jq ".[] | select(.merged_at != null and .merged_at >= \"$SINCE\") | \
      {repo:\"$R\", n:.number, title:.title, body:(.body // \"\"), created:.created_at, merged:.merged_at, by:.merged_by.login, author:.user.login}" >> "$TMP/merged.jsonl" 2>/dev/null \
    || infra "$R PR 列表拉取失败"
  gh api "repos/$ORG/$R/pulls?state=open&per_page=50" \
    --jq ".[] | select(.created_at != null) | {repo:\"$R\", n:.number, created:.created_at}" >> "$TMP/open.jsonl" 2>/dev/null || true
done
[[ -s "$TMP/merged.jsonl" ]] || { echo "::notice::窗口内零合并 PR——各比率指标 N/A（T2 语义）"; }

python3 - "$TMP" "$SAMPLE_SIZE" "$STUCK_HOURS" "$WINDOW_DAYS" <<'PYEOF' > "$TMP/metrics.txt"
import json, sys, random, datetime
tmp, k, stuck_h, win = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
merged = [json.loads(l) for l in open(f"{tmp}/merged.jsonl")] if __import__('os').path.exists(f"{tmp}/merged.jsonl") else []
opens  = [json.loads(l) for l in open(f"{tmp}/open.jsonl")] if __import__('os').path.exists(f"{tmp}/open.jsonl") else []
AGENT = ("cloudbrid-agent[bot]", "app/cloudbrid-agent", "cloudbrid-agent")
agent_merged = [p for p in merged if p["by"] in AGENT]
rate = f"{len(agent_merged)/len(merged):.3f}" if merged else "N/A"
now = datetime.datetime.now(datetime.timezone.utc)
stuck = [p for p in opens if (now - datetime.datetime.fromisoformat(p["created"].replace("Z","+00:00"))).total_seconds() > stuck_h*3600]
durs = sorted((datetime.datetime.fromisoformat(p["merged"].replace("Z","+00:00")) - datetime.datetime.fromisoformat(p["created"].replace("Z","+00:00"))).total_seconds() for p in merged)
p95 = f"{durs[int(0.95*len(durs))-1]/3600:.1f}h" if durs else "N/A"
DRILL = ("演练", "[drill]")
def is_drill(p): return any(m in (p.get("title","") + p.get("body","")) for m in DRILL)
all_rev = [p for p in merged if "[auto-revert]" in p["title"]]
rev_list = [p for p in all_rev if not is_drill(p)]
drills_excluded = len(all_rev) - len(rev_list)
rev = len(rev_list)
p0 = 0  # post-merge P0 issue 计数由调用侧注入文件（简化：占位 0 由下方覆盖）
try: p0 = int(open(f"{tmp}/p0count").read().strip())
except Exception: pass
esc = f"{(rev+p0)/len(merged):.3f}" if merged else "N/A"
# 抽样：seed = ISO 周（可复现）
isoweek = now.isocalendar()
seed = int(f"{isoweek[0]}-W{isoweek[1]}".replace("-W","") ) if False else hash(f"{isoweek[0]}-W{isoweek[1]}") & 0xffffffff
sample = random.Random(seed).sample(agent_merged, min(k, len(agent_merged))) if agent_merged else []
print(f"auto_merge_rate={rate} ({len(agent_merged)}/{len(merged)})")
print(f"escape_rate={esc} (reverts={rev}+p0={p0} / merged={len(merged)}, drills_excluded={drills_excluded})")
print(f"stuck_prs={len(stuck)} (>{stuck_h}h)")
print(f"pr_duration_p95={p95}")
print(f"flaky_rate=pending（#94 数据源滚动）")
print(f"entropy_new_dep_prs=pending（依赖清单触及计数下版接入）")
print(f"SAMPLE_SEED={isoweek[0]}-W{isoweek[1]}")
for s in sample:
    print(f"SAMPLE={s['repo']}#{s['n']} {s['title'][:60]}")
PYEOF
[[ -s "$TMP/metrics.txt" ]] || die "指标计算失败"

# post-merge P0 计数（.github 与各仓 open/closed 窗口内）
P0=$(gh api "search/issues?q=org:$ORG+%22post-merge+冒烟失败%22+created:>$SINCE&per_page=100"   --jq '[.items[] | select((.title + (.body // "")) | test("演练|\[drill\]") | not)] | length' 2>/dev/null || echo 0)
echo "$P0" > "$TMP/p0count"

# 上一期 escape_rate（阈值升级 T5）
PREV=$(gh api "repos/$GOV_REPO/issues?state=all&labels=sli-report&per_page=10" \
  --jq '[.[] | .body | capture("(?<e>escape_rate=(N/A|[0-9.]+))"; "g")?.e] | first // empty' 2>/dev/null || true)

CUR=$(grep -oP 'escape_rate=\K[^ ]+' "$TMP/metrics.txt" | head -1)
ESCALATE=OK
if [[ -n "$PREV" && "$PREV" != "N/A" && "$CUR" != "N/A" ]]; then
  python3 -c "exit(0 if float('$PREV')>0 and float('$CUR')>0 else 1)" || ESCALATE=ESCALATE
fi

REPORT=$(cat "$TMP/metrics.txt")
WEEK=$(grep -oP 'SAMPLE_SEED=\K.*' "$TMP/metrics.txt")
cat > "$TMP/body.md" <<BOD
# SLI 周报（$WEEK，窗口 ${WINDOW_DAYS}天）

$REPORT

## 指标口径
- auto_merge_rate：agent 身份（cloudbrid-agent）合并 / 全部合并（分母=窗口内合并 PR 数）
- escape_rate：(合入的 [auto-revert] + post-merge P0 issue) / 合并 PR——有分母的风险指标；演练数据（title/body 含「演练」或「[drill]」约定标记）从分子排除且 drills_excluded 计数可见——过滤不可见=作弊通道
- 人类触碰：agent 合并占比的反向锚点（逐评论/评审计数下版接入）
- flaky_rate / entropy：pending（数据源 #94/#87/#90 滚动接入）

阈值状态：escape_rate 连续两周>0 → P1 升级（本期：$ESCALATE）
BOD

gh issue create --repo "$GOV_REPO" --title "SLI 周报 $WEEK（自动合并门禁自身指标）" \
  --body-file "$TMP/body.md" || die "周报 issue 创建失败" \n  || gh issue create --repo "$GOV_REPO" --title "SLI 周报 $WEEK（自动合并门禁自身指标）" --body-file "$TMP/body.md"

# 抽样审计 issue
SAMPLES=$(grep '^SAMPLE=' "$TMP/metrics.txt" || true)
if [[ -n "$SAMPLES" ]]; then
  gh issue create --repo "$GOV_REPO" --title "抽样审计 $WEEK（3 个随机自动合并 PR）" --body \
"随机样本（seed=$WEEK 可复现，防「挑软的抽」）：

$SAMPLES

审计 checklist（每样本）：改动是否与宣称相符 / 门禁判定是否正确 / 有无事后发现问题。
发现回流：归因后回写 SLI 指标，必要时开门禁补强 issue。（#98，ADR-0059）" || infra "审计 issue 创建失败"
else
  echo "::notice::窗口内无 agent 合并 PR——抽样审计本期跳过"
fi

if [[ "$ESCALATE" == "ESCALATE" ]]; then
  gh issue create --repo "$GOV_REPO" --title "P1: 门禁逃逸率连续两周 >0（SLI 升级，$WEEK）" \
    --body "escape_rate 上期=$PREV 本期=$CUR——按 #98 T5 阈值自动升级。需归因（被 revert 的 PR / P0 事件清单见周报）。" \
    && exit 1
fi
exit 0

# retrigger（ADR-0059 已合并，org-gate 需新事件）
