#!/usr/bin/env bash
# evidence-query.sh —— 七源统一证据查询（IR-0006 W1-B2/W3-F1/W4-R1 / BEH-03 / ADR-0103，AC-4a）
#
# 一条命令跨源拉取 schema v1 影子账本、逐源验链（fail-closed：链断=红）、
# 按时间归并输出统一 JSONL（stdout）+ 分源统计（stderr）：
#   源 1  metering   Cloudbird-Software/CI-Workflows @ metering-ledger   shadow-evidence-*.jsonl（根）
#   源 2  drill      Cloudbird-Software/.github      @ drill-ledger     governance/drill/shadow-evidence.jsonl
#   源 3  butler     Cloudbird-Software/.github      @ butler-ledger    governance/butler/shadow-evidence.jsonl
#   源 4  elevation  Cloudbird-Software/.github      @ elevation-ledger governance/elevation/shadow-evidence.jsonl
#   （W2-C4 JIT 提权裁决/收回记录——subject 可查询即 AC-9c 锚点）
#   源 5  tickets    Cloudbird-Software/cnb-bridge   @ tickets-ledger  tickets.jsonl
#   （W2-C1 内网调度器短票据 grant/revoke——AC-5b 统一账本；Go 发射器产出，
#    链形态与 evidence_shadow.py 逐字节兼容，金向量锚定）
#   源 6  feishu     Cloudbird-Software/.github      @ feishu-ledger   governance/feishu/shadow-evidence.jsonl
#   （W3-F1 飞书多维表格投影同步/对账/重建演练事件——payload 带每轮 api_calls
#    计数=AC-7a 调用账本可查询锚点；日常 15min 轮影子随 runner 销毁=丢弃层，
#    本源只含 drill 持久化轮）
#   源 7  env        Cloudbird-Software/.github      @ env-ledger      governance/env/shadow-evidence.jsonl
#   （W4-R1 云内网环境对账事件——每轮 scope 断言+漂移计数=AC-8b 对账日志
#    可查询锚点）
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
  # 源缺席按 HTTP 状态码判定（"HTTP 404"）：GitHub 404 报文变体多——路径不存在=
  # "Not Found"、分支未建="No commit found for the ref"、ref 解析失败="No ref found"
  # ——报文猜谜必漏（2026-08-29 波次通道实测连环抓出两变体）；gh 末尾必打 "(HTTP 404)"
  if grep -q 'HTTP 404' "$TMP/api.err" 2>/dev/null; then
    return 1   # 源缺席（尚无影子记录/账本分支未建）——过渡期合法，非红
  fi
  echo "FATAL: $repo@$branch $path 拉取失败（非 404）：" >&2; cat "$TMP/api.err" >&2; exit 2
}

SRC_METER="$TMP/metering"; mkdir -p "$SRC_METER"
if "$GH" api "repos/Cloudbird-Software/CI-Workflows/contents?ref=metering-ledger" >"$TMP/list.json" 2>"$TMP/api.err"; then
  # #471 修复：目录列表条目不含 content 字段（base64 正文）——只取文件名清单，
  # 逐文件走 fetch_file（单文件 contents API 含 content；404=并发删除按缺席跳过）
  python3 - "$TMP/list.json" > "$TMP/meter-files.txt" <<'PYEOF'
import json, sys
for ent in json.load(open(sys.argv[1], encoding="utf-8")):
    name = ent.get("name") or ""
    if ent.get("type") == "file" and name.startswith("shadow-evidence-") and name.endswith(".jsonl"):
        print(name)
PYEOF
  while IFS= read -r mname; do
    [[ -n "$mname" ]] || continue
    fetch_file "Cloudbird-Software/CI-Workflows" "metering-ledger" "$mname" "$SRC_METER/$mname" \
      || { echo "WARN: metering $mname 并发缺席（404）——跳过" >&2; true; }
  done < "$TMP/meter-files.txt"
else
  # 同 fetch_file：按 "HTTP 404" 状态码判源缺席（报文变体猜谜必漏——见上方注释）
  if ! grep -q 'HTTP 404' "$TMP/api.err" 2>/dev/null; then
    echo "FATAL: metering-ledger 目录拉取失败：" >&2; cat "$TMP/api.err" >&2; exit 2
  fi
fi
DRILL_OK=0; fetch_file "Cloudbird-Software/.github" "drill-ledger" "governance/drill/shadow-evidence.jsonl" "$TMP/drill.jsonl" && DRILL_OK=1 || [[ $? -eq 1 ]] || exit 2
BUTLER_OK=0; fetch_file "Cloudbird-Software/.github" "butler-ledger" "governance/butler/shadow-evidence.jsonl" "$TMP/butler.jsonl" && BUTLER_OK=1 || [[ $? -eq 1 ]] || exit 2
ELEV_OK=0; fetch_file "Cloudbird-Software/.github" "elevation-ledger" "governance/elevation/shadow-evidence.jsonl" "$TMP/elev.jsonl" && ELEV_OK=1 || [[ $? -eq 1 ]] || exit 2
TICKET_OK=0; fetch_file "Cloudbird-Software/cnb-bridge" "tickets-ledger" "tickets.jsonl" "$TMP/tickets.jsonl" && TICKET_OK=1 || [[ $? -eq 1 ]] || exit 2
FEISHU_OK=0; fetch_file "Cloudbird-Software/.github" "feishu-ledger" "governance/feishu/shadow-evidence.jsonl" "$TMP/feishu.jsonl" && FEISHU_OK=1 || [[ $? -eq 1 ]] || exit 2
ENVD_OK=0; fetch_file "Cloudbird-Software/.github" "env-ledger" "governance/env/shadow-evidence.jsonl" "$TMP/envd.jsonl" && ENVD_OK=1 || [[ $? -eq 1 ]] || exit 2

# ---- 逐源验链 + 归并输出（链断=exit 3：不可信数据不出结果） ----
export CARD_FILTER JSON_ONLY DRILL_OK BUTLER_OK ELEV_OK TICKET_OK FEISHU_OK ENVD_OK
python3 - "$DIR/evidence_shadow.py" "$SRC_METER" "$TMP/drill.jsonl" "$TMP/butler.jsonl" "$TMP/elev.jsonl" "$TMP/tickets.jsonl" "$TMP/feishu.jsonl" "$TMP/envd.jsonl" "$TMP" <<'PYEOF'
import glob, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))
import evidence_shadow  # noqa: E402  验链与 CI-Workflows 侧同源语义

metering_dir, drill_f, butler_f, elev_f, tickets_f, feishu_f, envd_f, tmp = sys.argv[2:10]
sources = {"metering": sorted(glob.glob(os.path.join(metering_dir, "shadow-evidence-*.jsonl"))),
           "drill": [drill_f] if os.environ.get("DRILL_OK") == "1" else [],
           "butler": [butler_f] if os.environ.get("BUTLER_OK") == "1" else [],
           "elevation": [elev_f] if os.environ.get("ELEV_OK") == "1" else [],
           "tickets": [tickets_f] if os.environ.get("TICKET_OK") == "1" else [],
           "feishu": [feishu_f] if os.environ.get("FEISHU_OK") == "1" else [],
           "env": [envd_f] if os.environ.get("ENVD_OK") == "1" else []}
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
    "by_source": {s: sum(1 for r in out if r["source"] == s) for s in ("metering", "drill", "butler", "elevation", "tickets", "feishu", "env")},
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
