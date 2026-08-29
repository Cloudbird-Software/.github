#!/usr/bin/env bash
# evidence-query.sh —— 三源统一证据查询（IR-0006 W1-B2 / BEH-03 / ADR-0103，AC-4a）
#
# 一条命令跨三源拉取 schema v1 影子账本、逐源验链（fail-closed：链断=红）、
# 按时间归并输出统一 JSONL（stdout）+ 分源统计（stderr）：
#   源 1  metering   Cloudbird-Software/CI-Workflows @ metering-ledger   shadow-evidence-*.jsonl（根）
#   源 2  drill      Cloudbird-Software/.github      @ drill-ledger     governance/drill/shadow-evidence.jsonl
#   源 3  butler     Cloudbird-Software/.github      @ butler-ledger    governance/butler/shadow-evidence.jsonl
#
# 用法:
#   bash governance/evidence-query.sh [--card owner/repo#n] [--json]   # --json=汇总行也走 stdout
# env:
#   GH_TOKEN  必填（读私有仓 contents；org token 或对两仓可读的 PAT）
# 退出码: 0=查询成功（输出统一 JSONL）| 2=参数/环境 | 3=任一源链断（fail-closed，
#   不可信数据不出结果——宁红勿假）
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
GH="${GH:-gh}"

CARD_FILTER=""; JSON_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --card) CARD_FILTER="${2:?}"; shift 2 ;;
    --json) JSON_ONLY=1; shift ;;
    *) echo "未知参数 $1（用法见文件头）" >&2; exit 2 ;;
  esac
done
[[ -n "${GH_TOKEN:-}" ]] || { echo "GH_TOKEN 未设置（需对两仓 contents 读权限）" >&2; exit 2; }
command -v "$GH" >/dev/null 2>&1 || { echo "gh 不可用" >&2; exit 2; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# ---- 拉源（404=该源尚无影子记录：过渡期合法，跳过留痕；其余 API 错=fail-closed） ----
fetch_file() {  # fetch_file <repo> <branch> <path> <out>；rc=1=源缺席（404，非红）
  local repo="$1" branch="$2" path="$3" out="$4"
  if "$GH" api "repos/$repo/contents/$path?ref=$branch" >"$TMP/api.json" 2>"$TMP/api.err"; then
    python3 - "$TMP/api.json" "$out" <<'PYEOF'
import base64, json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(
    base64.b64decode(d["content"]).decode("utf-8"))
PYEOF
    return 0
  fi
  # 404 两种报文都算源缺席：路径不存在="Not Found"；ref（分支）不存在=
  # "No ref found for ..."（不含 "not found" 字样——2026-08-29 波次通道实测抓出：
  # butler-ledger 分支未建被误判"非 404 拉取失败"→ INFRA exit 2，源缺席本应合法跳过）
  if grep -qiE 'not found|no ref found' "$TMP/api.err" 2>/dev/null; then
    return 1   # 源缺席（尚无影子记录/账本分支未建）——过渡期合法，非红
  fi
  echo "FATAL: $repo@$branch $path 拉取失败（非 404）：" >&2; cat "$TMP/api.err" >&2; exit 2
}

SRC_METER="$TMP/metering"; mkdir -p "$SRC_METER"
if "$GH" api "repos/Cloudbird-Software/CI-Workflows/contents?ref=metering-ledger" >"$TMP/list.json" 2>"$TMP/api.err"; then
  python3 - "$TMP/list.json" "$SRC_METER" <<'PYEOF'
import base64, json, sys
for ent in json.load(open(sys.argv[1], encoding="utf-8")):
    if ent["type"] == "file" and ent["name"].startswith("shadow-evidence-") and ent["name"].endswith(".jsonl"):
        open(f"{sys.argv[2]}/{ent['name']}", "w", encoding="utf-8", newline="\n").write(
            base64.b64decode(ent["content"]).decode("utf-8"))
PYEOF
else
  if ! grep -qiE 'not found|no ref found' "$TMP/api.err" 2>/dev/null; then
    echo "FATAL: metering-ledger 目录拉取失败：" >&2; cat "$TMP/api.err" >&2; exit 2
  fi
fi
DRILL_OK=0; fetch_file "Cloudbird-Software/.github" "drill-ledger" "governance/drill/shadow-evidence.jsonl" "$TMP/drill.jsonl" && DRILL_OK=1 || [[ $? -eq 1 ]] || exit 2
BUTLER_OK=0; fetch_file "Cloudbird-Software/.github" "butler-ledger" "governance/butler/shadow-evidence.jsonl" "$TMP/butler.jsonl" && BUTLER_OK=1 || [[ $? -eq 1 ]] || exit 2

# ---- 逐源验链 + 归并输出（链断=exit 3：不可信数据不出结果） ----
export CARD_FILTER JSON_ONLY DRILL_OK BUTLER_OK
python3 - "$DIR/evidence_shadow.py" "$SRC_METER" "$TMP/drill.jsonl" "$TMP/butler.jsonl" "$TMP" <<'PYEOF'
import glob, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))
import evidence_shadow  # noqa: E402  验链与 CI-Workflows 侧同源语义

metering_dir, drill_f, butler_f, tmp = sys.argv[2:6]
sources = {"metering": sorted(glob.glob(os.path.join(metering_dir, "shadow-evidence-*.jsonl"))),
           "drill": [drill_f] if os.environ.get("DRILL_OK") == "1" else [],
           "butler": [butler_f] if os.environ.get("BUTLER_OK") == "1" else []}
errs, recs = [], []
for src, files in sources.items():
    for f in files:
        if not os.path.isfile(f) or os.path.getsize(f) == 0:
            continue
        errs.extend(evidence_shadow.verify_file(f))
        for ln in evidence_shadow.read_lines(f):
            recs.append({"source": src, **json.loads(ln)})
if errs:
    for e in errs:
        print(f"CHAIN {e}", file=sys.stderr)
    print("FATAL: 任一源链断——统一查询拒绝出结果（fail-closed，宁红勿假）", file=sys.stderr)
    sys.exit(3)

card = os.environ.get("CARD_FILTER") or None
recs.sort(key=lambda r: (r.get("ts", ""), r.get("source")))
out = [r for r in recs if not card or r.get("subject", {}).get("card") == card]
for r in out:
    print(json.dumps(r, ensure_ascii=False, sort_keys=True, separators=(",", ":")))

summary = {
    "total": len(out),
    "by_source": {s: sum(1 for r in out if r["source"] == s) for s in ("metering", "drill", "butler")},
    "by_tenant": {},
    "by_card_top": {},
}
for r in out:
    t = r.get("subject", {}).get("tenant", "?")
    c = r.get("subject", {}).get("card", "?")
    summary["by_tenant"][t] = summary["by_tenant"].get(t, 0) + 1
    summary["by_card_top"][c] = summary["by_card_top"].get(c, 0) + 1
summary["by_card_top"] = dict(sorted(summary["by_card_top"].items(), key=lambda kv: -kv[1])[:10])
line = json.dumps(summary, ensure_ascii=False, sort_keys=True)
if os.environ.get("JSON_ONLY") == "1":
    print(line)
else:
    print(f"SUMMARY {line}", file=sys.stderr)
PYEOF
