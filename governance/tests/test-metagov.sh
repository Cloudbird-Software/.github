#!/usr/bin/env bash
# test-metagov.sh —— W6-M1（#423）conformance 语料三元组+四列元治理+晋级账本自测
#
# 离线自足：fixture 语料/policy/工作流清单全部临时生成；真实面（metrics.yaml
# 四列声明 vs 本仓 workflows job 清单）机械对账断言。
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL  $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CORPUS="$DIR/governance/conformance-corpus.py"
METAGOV="$DIR/governance/metagov.py"

# ---- fixture：已完成卡 issue+评论（三元组原料） ----
D="$TMP/c"
mkdir -p "$D"
cat > "$D/cards.json" <<'EOF'
[{"number": 9001, "title": "T: 演示卡甲", "created_at": "2026-08-01T00:00:00Z",
  "closed_at": "2026-08-02T00:00:00Z", "labels": [{"name": "type:card"}, {"name": "state:done"}],
  "body": "> 父意图: #402\n\n## 任务\ndemo task A\n\n## AC\n- AC-1b: demo"},
 {"number": 9002, "title": "T: 演示卡乙", "created_at": "2026-08-01T00:00:00Z",
  "closed_at": "2026-08-02T00:00:00Z", "labels": [{"name": "type:card"}, {"name": "state:done"}],
  "body": "> 父意图: #402\n\n## 任务\ndemo task B\n\n## AC\n- AC-1b: demo\n- AC-1c: demo"}]
EOF
cat > "$D/9001.json" <<'EOF'
[{"body": "state:done（T8）——PR #1 合并+实测全绿"}]
EOF
: > "$D/9002.json"   # 无 done 评论 → 密封验收缺=跳过

python3 "$CORPUS" harvest --cards-file "$D/cards.json" --comments-dir "$D" --out "$TMP/corpus.jsonl" >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "harvest 绿（甲卡三元组落盘）" || bad "harvest 红"
N=$(grep -c . "$TMP/corpus.jsonl")
[[ $N -eq 1 ]] && ok "无 done 评论卡被跳过（乙卡=密封验收缺=不可回放）" || bad "跳过语义坏（n=$N）"

# 三元组结构机械校验
python3 "$CORPUS" validate --corpus "$TMP/corpus.jsonl" --min 1 >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "validate 绿（三元组结构可机械校验，AC-1b）" || bad "validate 红"

# 负向：三元组残缺 → 红（三条逐一）
jq -c '.triple.initial_snapshot.body_sha256="zz"' "$TMP/corpus.jsonl" > "$TMP/bad1.jsonl"
jq -c 'del(.triple.goal.ac_ids, .triple.goal.ac_section_sha256, .triple.goal.ac_count)' "$TMP/corpus.jsonl" > "$TMP/bad2.jsonl"
jq -c '.triple.sealed_acceptance.done_comment_sha8="mismatch"' "$TMP/corpus.jsonl" > "$TMP/bad3.jsonl"
for f in bad1 bad2 bad3; do
  python3 "$CORPUS" validate --corpus "$TMP/$f.jsonl" --min 1 >/dev/null 2>&1
  [[ $? -eq 1 ]] || bad "$f 漏检"
done
ok "三元组残缺三形态 → 红（digest 形状/AC 空/密封不一致）"

# 最低条数执法：--min 30 而 1 条 → 红
python3 "$CORPUS" validate --corpus "$TMP/corpus.jsonl" --min 30 >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "低于最低条数 → 红（30-50 卡下限执法）" || bad "条数下限漏检"

# ---- 四列元治理评审 ----
# 真实面：metrics.yaml 四列声明 vs 本仓 workflows job 清单（机械对账）
python3 "$METAGOV" review --policy "$DIR/governance/policy/metrics.yaml" \
  --workflows-dir "$DIR/.github/workflows" --out "$TMP/review.json" >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "四列评审绿（声明门禁全对账在册，AC-1c）" || bad "四列评审红"
jq -e '.four_columns==["gate","judge","data_source","red_line"] and (.gates|length>=7)
  and (.gates[]|select(.gate=="eval-wave:eval-wave")|.judge=="mechanical")' \
  "$TMP/review.json" >/dev/null && ok "评审产物四列结构+门禁行数（含 eval-wave 锚）" || bad "评审产物结构坏"

# 负向：声明幽灵门禁 → 红（漂移执法）
P="$DIR/governance/policy/metrics.yaml" python3 - "$TMP" <<'PY' && ok "幽灵门禁声明构造（追加 ghost:job）" || bad "fixture 构造失败"
import os, sys, yaml
tmp = sys.argv[1]
p = yaml.safe_load(open(os.environ["P"], encoding="utf-8"))
p["gate_metagovernance"]["gates"].append(
    {"gate": "ghost:job", "judge": "mechanical", "data_source": "x", "red_line": "y"})
open(f"{tmp}/pbad.yaml", "w").write(yaml.safe_dump(p, allow_unicode=True))
sys.exit(0)
PY
python3 "$METAGOV" review --policy "$TMP/pbad.yaml" \
  --workflows-dir "$DIR/.github/workflows" --out "$TMP/r2.json" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "幽灵门禁 → 红" || bad "幽灵门禁漏检"

# ---- 晋级账本（append-only+hash 链） ----
REG="$TMP/promotions.jsonl"
cat > "$TMP/rec.json" <<'EOF'
{"practice": "fail-closed 双层验证（write 宽松+verify 严格）",
 "goal": "错误事件进不了账本主链，生成器缺陷早暴露",
 "evidence": ["run 33263613945", "PR Cloudbird-Software/.github#460"],
 "promoted_by": "metagov-review-bot"}
EOF
python3 "$METAGOV" promote --registry "$REG" --record "$TMP/rec.json" >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "晋级追加绿（evidence 非空+链字段独占计算）" || bad "晋级追加红"

# 记录自带链字段 → 拒（infra）
cat > "$TMP/rec-chain.json" <<'EOF'
{"practice": "x", "goal": "y", "evidence": ["z"], "promoted_by": "b", "hash": "pretyped"}
EOF
python3 "$METAGOV" promote --registry "$REG" --record "$TMP/rec-chain.json" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "自带链字段 → 拒（写入器独占，防伪造链）" || bad "链字段伪造未拒"

# 空证据 → 拒（自封防御）
echo '{"practice":"x","goal":"y","evidence":[],"promoted_by":"b"}' > "$TMP/rec-empty.json"
python3 "$METAGOV" promote --registry "$REG" --record "$TMP/rec-empty.json" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "空证据晋级 → 拒（胜出须有证据——自封防御）" || bad "空证据未拒"

# 追加第二条 → 链续接+verify 绿；改历史 → 断链红
echo '{"practice":"p2","goal":"g2","evidence":["e2"],"promoted_by":"b"}' > "$TMP/rec2.json"
python3 "$METAGOV" promote --registry "$REG" --record "$TMP/rec2.json" >/dev/null 2>&1
python3 "$METAGOV" verify --registry "$REG" >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "两记录链完整（verify 绿）" || bad "链验红"
python3 - "$REG" <<'PY'
import json, sys
lines = open(sys.argv[1]).read().splitlines()
rec = json.loads(lines[0]); rec["practice"] = "tampered"
open(sys.argv[1], "w").write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n" + lines[1])
PY
python3 "$METAGOV" verify --registry "$REG" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "改历史 → 断链红（append-only 执法）" || bad "篡改漏检"

echo "----------------------------------------"
echo "test-metagov: $([[ $FAIL -eq 0 ]] && echo PASS || echo "FAIL（$FAIL）")"
exit $([[ $FAIL -eq 0 ]] && echo 0 || echo 1)
