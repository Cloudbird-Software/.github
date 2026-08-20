#!/usr/bin/env bash
# flaky-sweep.sh —— 隔离清单到期回炉检测（P2-9，ADR-0043）
# 每日扫描全部受管仓的 tests/quarantine.yaml：
#   - 条目结构校验（test/owner/expires/adr 齐备；expires ≤ quarantine_max_days）
#   - expires 已过 → 该条目自动回炉（过期隔离不豁免）+ 开升级 issue（人工按 ADR 移除条目）
#   - 清单拉取失败 = fail-closed
# 用法: GH_TOKEN=<org admin> bash flaky-sweep.sh（CI 由 flaky-sweep.yml 调度）
set -uo pipefail
ORG="${ORG:-Cloudbird-Software}"
DIR="$(cd "$(dirname "$0")" && pwd)"
MAX_DAYS=$(python3 -c "import yaml;print(yaml.safe_load(open('$DIR/policy/testing.yaml',encoding='utf-8'))['flaky_governance']['quarantine_max_days'])")
api() { curl -sS -H "Authorization: Bearer ${GH_TOKEN:?}" -H "Accept: application/vnd.github+json" "$@"; }
REPOS=$(python3 -c "import yaml;print(' '.join(r['name'] for r in yaml.safe_load(open('$DIR/REPOS.yaml',encoding='utf-8'))['repos'] if r.get('status')=='active'))")
ISSUES=0; EXPIRED=0; MALFORMED=0
for r in $REPOS; do
  RESP=$(api "https://api.github.com/repos/$ORG/$r/contents/tests/quarantine.yaml")
  CONTENT=$(jq -r '.content // empty' <<<"$RESP" | base64 -d 2>/dev/null)
  if [[ -z "$CONTENT" ]]; then
    jq -e '.message == "Not Found"' <<<"$RESP" >/dev/null 2>&1 && continue
    echo "DRIFT repo '$r' tests/quarantine.yaml 读取失败（fail-closed，ADR-0043）"; MALFORMED=$((MALFORMED+1)); continue
  fi
  OUT=$(python3 - "$r" "$MAX_DAYS" <<'PYEOF'
import sys, yaml, datetime
repo, max_days = sys.argv[1], int(sys.argv[2])
d = yaml.safe_load(sys.stdin) or {}
today = datetime.date.today()
expired, malformed = [], []
for e in d.get("quarantined", []):
    for k in ("test", "owner", "expires", "adr"):
        if not e.get(k):
            malformed.append(f"{e} 缺 {k}")
    try:
        exp = datetime.date.fromisoformat(str(e["expires"]))
        if (exp - today).days > max_days:
            malformed.append(f"{e['test']} expires 距今超 quarantine_max_days={max_days}")
        elif exp < today:
            expired.append(f"{e['test']}（owner={e['owner']}，过期于 {e['expires']}，adr={e['adr']}）")
    except ValueError:
        malformed.append(f"{e} expires 非法")
print("EXPIRED\n" + "\n".join(expired) if expired else "EXPIRED\n-")
print("MALFORMED\n" + "\n".join(malformed) if malformed else "MALFORMED\n-")
PYEOF
  ) <<<"$CONTENT"
  EXP_LIST=$(sed -n '/^EXPIRED$/,/^MALFORMED$/p' <<<"$OUT" | sed '1d;$d' | grep -v '^-$' || true)
  MAL_LIST=$(sed -n '/^MALFORMED$/,$p' <<<"$OUT" | sed '1d' | grep -v '^-$' || true)
  if [[ -n "$EXP_LIST" || -n "$MAL_LIST" ]]; then
    TITLE="[flaky] $r 隔离清单待处置（过期回炉/结构违规，ADR-0043）"
    BODY="flaky-sweep 每日检测（ADR-0043）：\n\n## 过期条目（已自动回炉——过期隔离不豁免，须修复测试或走 ADR 重新隔离）\n${EXP_LIST:--}\n\n## 结构违规\n${MAL_LIST:--}\n\n处置：修复测试后经 PR 移除条目（引用 ADR）；或新 ADR 重新隔离。"
    api -X POST "https://api.github.com/repos/$ORG/$r/issues" -d "$(jq -n --arg t "$TITLE" --arg b "$BODY" '{title:$t,body:$b,labels:["flaky-quarantine"]}')" >/dev/null 2>&1 || \
      api -X POST "https://api.github.com/repos/$ORG/$r/issues" -d "$(jq -n --arg t "$TITLE" --arg b "$BODY" '{title:$t,body:$b}')" >/dev/null
    echo "ISSUE repo '$r': 过期 $(grep -c . <<<"$EXP_LIST" || true) / 违规 $(grep -c . <<<"$MAL_LIST" || true)"
    ISSUES=$((ISSUES+1)); EXPIRED=$((EXPIRED+$(grep -c . <<<"$EXP_LIST" || true)))
  fi
done
echo "结果: 开 issue=$ISSUES 过期条目=$EXPIRED 违规仓=$MALFORMED（无输出=全部健康）"
[[ $EXPIRED -eq 0 && $MALFORMED -eq 0 ]]
