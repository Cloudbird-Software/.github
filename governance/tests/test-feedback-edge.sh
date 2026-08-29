#!/usr/bin/env bash
# test-feedback-edge.sh —— W6-M2（#424）R3→R1 反馈边自测
#
# 离线自足：dashboard 信号 fixture（机器可读 JSON 形态同 dashboard-update.py
# 写入面）+ 去重面 fixture；全链零 gh 调用（--dry-run+注入文件）。断言：
# 越阈→候选（R1 门形态）/阈内→OK/pending→诚实跳过/去重→DUPLICATE/
# policy 非法→exit 2 fail-closed/候选无 ir-signed 旁路（AC-8h 红线）。
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
EDGE="$DIR/governance/feedback-edge.py"
# 审计影子重定向进 TMP（离线测试不污染工作树）
export BUTLER_SHADOW_FILE="$TMP/feedback-shadow.jsonl"

# ---- fixture：dashboard 机器可读 JSON（真实形态：marker+8 反引号围栏） ----
mkdash() {  # $1=p90值 $2=p90停摆线 $3=escape状态
  cat > "$TMP/dash.txt" <<EOF
管家账本 dashboard（演示区）
<!-- dashboard-json -->
\`\`\`\`\`\`\`\`json
{"generated_at": "2026-08-29T12:00:00Z",
 "north_star": {"guardrails": {"escape_rate_sustained": {"status": "$3"},
                               "revert_rate": {"status": "green"},
                               "drill_red_rate": {"status": "green"},
                               "false_allow": {"status": "green"}}},
 "metrics": {"attention": {"needs_human_p90_hours": $1,
                           "needs_human_stop_hours": $2},
             "cost": {"per_ir_usd": 25.8}}}
\`\`\`\`\`\`\`\`
EOF
}

# ---- 正向：SLO 越阈 → 候选生成（AC-8g） ----
mkdash 30.39 24 green
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" > "$TMP/out1.txt" 2>&1
[[ $? -eq 0 ]] && ok "反馈边轮次绿（越阈=产出非故障）" || bad "越阈轮次 exit 码红"
grep -q "^SIGNAL needs-human-p90-stop value=30.39 gt 24" "$TMP/out1.txt" \
  && ok "SLO 信号越阈检出（p90 30.39 > 停摆线 24）" || bad "SLO 越阈漏检"
grep -q "^CANDIDATE needs-human-p90-stop labels=type:intent+state:ir-draft" "$TMP/out1.txt" \
  && ok "候选 spec 生成（labels 锚=type:intent+state:ir-draft——R1 门起点形态）" || bad "候选 labels 锚缺失"

# AC-8h 红线：CANDIDATE 行（labels 面）结构性无 ir-signed 旁路——body 门描述
# 合法提及签署流程，不作红线判定面
if grep "^CANDIDATE" "$TMP/out1.txt" | grep -q "ir-signed"; then
  bad "候选 labels 出现 state:ir-signed——自动签署旁路（AC-8h 违约）"
else
  ok "候选 labels 无 state:ir-signed（签署门禁不豁免——AC-8h）"
fi
# 候选 body 带证据锚（机器可追溯）
grep -q "feedback-signal: key=needs-human-p90-stop value=30.39" "$TMP/out1.txt" \
  && ok "候选 body 带信号证据锚（feedback-signal 标记）" || bad "证据锚缺失"

# ---- 阈内 → OK 不开卡 ----
mkdash 10.0 24 green
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" > "$TMP/out2.txt" 2>&1
grep -q "^OK     needs-human-p90-stop" "$TMP/out2.txt" \
  && ok "阈内信号 → OK 不开卡" || bad "阈内误报"
grep -q "^CANDIDATE" "$TMP/out2.txt" \
  && bad "阈内轮次误开候选" || ok "阈内零候选"

# ---- 错误面：护栏 red → 候选（eq 语义） ----
mkdash 10.0 24 red
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" > "$TMP/out3.txt" 2>&1
grep -q "^SIGNAL escape-sustained value=red eq red" "$TMP/out3.txt" \
  && ok "错误面信号越阈（护栏 red=eq 判定）" || bad "错误面越阈漏检"

# ---- pending → 诚实跳过（不造数，ADR-0073 决策 7） ----
mkdash null 24 green
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" > "$TMP/out4.txt" 2>&1
grep -q "^PENDING needs-human-p90-stop" "$TMP/out4.txt" \
  && ok "观测值 pending → 诚实跳过" || bad "pending 误判"
mkdash 30.39 null green
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" > "$TMP/out5.txt" 2>&1
grep -q "^PENDING needs-human-p90-stop" "$TMP/out5.txt" \
  && ok "阈值源 pending → 诚实跳过（停摆线缺≠越阈）" || bad "阈值缺误判"
# pending 字串形态（"pending:…" 标注）
cat > "$TMP/dash-p.txt" <<'EOF'
<!-- dashboard-json -->
```json
{"generated_at": "t", "north_star": {"guardrails": {}},
 "metrics": {"attention": {"needs_human_p90_hours": "pending:数据源未落",
                           "needs_human_stop_hours": 24},
             "cost": {"per_ir_usd": 25.8}}}
```
EOF
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash-p.txt" 2>&1 | grep -q "^PENDING needs-human-p90-stop" \
  && ok "pending 标注字串 → 诚实跳过（字串口径同判）" || bad "pending 字串误判"

# ---- 去重：open 候选已存在 → DUPLICATE 跳过（RB-B2） ----
mkdash 30.39 24 green
cat > "$TMP/existing.json" <<'EOF'
[{"number": 901, "labels": ["type:intent", "state:ir-draft", "feedback:needs-human-p90-stop"]}]
EOF
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" \
  --existing-file "$TMP/existing.json" > "$TMP/out6.txt" 2>&1
grep -q "^DUPLICATE needs-human-p90-stop open 候选已存在 #901" "$TMP/out6.txt" \
  && ok "去重命中 → DUPLICATE 跳过（不重复刷卡）" || bad "去重漏检"
grep -q "^CANDIDATE needs-human-p90-stop" "$TMP/out6.txt" \
  && bad "去重失败仍开候选" || ok "去重后零新候选"

# ---- 用量面：内联阈值 gt 语义 ----
cat > "$TMP/dash-cost.txt" <<'EOF'
<!-- dashboard-json -->
```json
{"generated_at": "t", "north_star": {"guardrails": {}},
 "metrics": {"attention": {"needs_human_p90_hours": 10, "needs_human_stop_hours": 24},
             "cost": {"per_ir_usd": 80.5}}}
```
EOF
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash-cost.txt" 2>&1 \
  | grep -q "^SIGNAL per-ir-cost value=80.5 gt 60.0" \
  && ok "用量面信号越阈（内联阈值 gt）" || bad "用量越阈漏检"

# ---- 负向：policy 非法 → exit 2 fail-closed（三形态） ----
# 形态1：op 非法
sed 's/op: gt/op: xor/; s/needs-human-p90-stop/needs-x/' "$DIR/governance/policy/feedback.yaml" > "$TMP/p1.yaml" 2>/dev/null || true
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" --policy "$TMP/p1.yaml" >/dev/null 2>&1
# sed 可能因结构差异不生效——直接构造最小非法 policy 保证确定性
cat > "$TMP/pbad1.yaml" <<'EOF'
schema: feedback-edge/v1
backlog_repo: a/b
dashboard_issue: {repo: a/b, label: dashboard}
signals:
  - {key: k, class: slo, description: d, metric_path: a.b, op: xor, threshold: 1, spec_title: t}
EOF
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" --policy "$TMP/pbad1.yaml" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "非法 op → exit 2（fail-closed）" || bad "非法 op 未拒"
# 形态2：threshold/threshold_path 双缺
cat > "$TMP/pbad2.yaml" <<'EOF'
schema: feedback-edge/v1
backlog_repo: a/b
dashboard_issue: {repo: a/b, label: dashboard}
signals:
  - {key: k, class: slo, description: d, metric_path: a.b, op: gt, spec_title: t}
EOF
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" --policy "$TMP/pbad2.yaml" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "阈值缺声明 → exit 2" || bad "阈值缺未拒"
# 形态3：schema 头错
cat > "$TMP/pbad3.yaml" <<'EOF'
schema: feedback-edge/v2
EOF
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash.txt" --policy "$TMP/pbad3.yaml" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "schema 头错 → exit 2" || bad "schema 头未拒"

# ---- 负向：dashboard 不可解析 → exit 2（信号源断=无默认绿） ----
echo "{broken json" > "$TMP/dash-bad.txt"
env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run --dashboard-file "$TMP/dash-bad.txt" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "dashboard JSON 损坏 → exit 2" || bad "损坏 JSON 未拒"

# ---- dry-run 离线无信号源 → exit 2（不可缺省造绿） ----
GH_TOKEN= env -u GH_TOKEN -u GITHUB_TOKEN python3 "$EDGE" --dry-run >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "离线 dry-run 缺 dashboard 注入 → exit 2" || bad "缺信号源未拒"

# ---- 真实 policy 全量：本仓 feedback.yaml 可装载（漂移面） ----
python3 - "$DIR/governance/policy/feedback.yaml" <<'PY'
import sys, yaml
p = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert p["schema"] == "feedback-edge/v1"
classes = {s["class"] for s in p["signals"]}
assert classes == {"error", "usage", "slo"}, classes
assert len({s["key"] for s in p["signals"]}) == len(p["signals"])
sys.exit(0)
PY
[[ $? -eq 0 ]] && ok "真实 feedback.yaml 声明面完整（三分类+键唯一）" || bad "真实 policy 声明坏"

# ---- 工作流面：feedback-edge.yml 存在+定时+去重串行化声明 ----
WF="$DIR/.github/workflows/feedback-edge.yml"
[[ -f "$WF" ]] && ok "feedback-edge.yml 在位" || bad "workflow 缺失"
grep -q "cron:" "$WF" && ok "定时面在位（每日）" || bad "无 cron"
grep -q "group: feedback-edge" "$WF" && ok "并发串行化在位（防重复开卡）" || bad "无 concurrency"

echo "----------------------------------------"
echo "test-feedback-edge: $([[ $FAIL -eq 0 ]] && echo PASS || echo "FAIL（$FAIL）")"
exit $([[ $FAIL -eq 0 ]] && echo 0 || echo 1)
