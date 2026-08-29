#!/usr/bin/env bash
# test-blob-store.sh —— 轨迹层指针协议·内网最小实现自测（IR-0006 W1-B3 / 卡 #408）
#
# 覆盖（卡 AC 对应）：
#   AC-3d put：git 侧只见指针（sha256+store+retention），本体入库内容寻址地址；
#             指针形态对齐 standards/evidence/pointer.schema.yaml（pointer@1）
#   AC-3e get：按指针回取重算 sha256 比对；不符/缺失=exit 3 零输出（宁红勿假）
#   不可变：同地址异内容=红；幂等：同内容重 put 不重复
#   retention 只增不减；sweep 只删过期（30d 过/90d 留/forever 留）
#   端到端：>4KB payload 经 put→payload_ref→判定层 append（git 零本体）
# 用法: bash governance/tests/test-blob-store.sh（gate.yml 自动纳入）
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BLOB="$DIR/governance/blob-store.sh"
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/store"
export BLOB_STORE_ROOT="$ROOT" BLOB_STORE_NAME="evidence-hot"

# ---- AC-3d put：指针 + 内容寻址入库 ----
printf 'trajectory-data-v1' >"$TMP/big.bin"
PTR=$(bash "$BLOB" put --file "$TMP/big.bin" --retention 90d) || fail "put 失败"
SHA=$(printf '%s' "$PTR" | sed -n 's/.*"sha256":"\([0-9a-f]*\)".*/\1/p')
[[ -f "$ROOT/objects/${SHA:0:2}/$SHA" ]] \
  && pass "AC-3d 内容寻址入库（objects/${SHA:0:2}/<sha>）" || fail "AC-3d 对象未落内容寻址地址"
cmp -s "$ROOT/objects/${SHA:0:2}/$SHA" "$TMP/big.bin" && pass "blob 本体与源一致" || fail "blob 本体损坏"

# 指针形态对齐 pointer@1（PyYAML 可用时按 schema 泛检，否则结构断言）
PTR_JSON="$TMP/ptr.json" SCHEMA="$DIR/standards/evidence/pointer.schema.yaml"
printf '%s\n' "$PTR" >"$PTR_JSON"
python3 - "$PTR_JSON" "$SCHEMA" <<'PYEOF' && pass "指针对齐 pointer.schema.yaml（pointer@1）" || fail "指针形态断言"
import json, re, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
try:
    import yaml
    sc = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
    props = sc["properties"]
    assert set(p) <= set(props), f"多余字段: {set(p) - set(props)}"
    for k in sc["required"]:
        assert k in p, f"必填缺失: {k}"
    for k, v in p.items():
        d = props[k]
        if "pattern" in d:
            assert re.fullmatch(d["pattern"], str(v)), f"{k} 不匹配 pattern: {v!r}"
        if "enum" in d:
            assert v in d["enum"], f"{k} 不在词表: {v!r}"
        if d.get("type") == "integer":
            assert isinstance(v, int) and v >= d.get("minimum", 0), f"{k} 非法整数"
except ImportError:
    assert set(p) <= {"sha256", "store", "retention", "bytes", "stored_at"}, p
    assert re.fullmatch(r"[0-9a-f]{64}", p["sha256"])
    assert p["store"] == "self-cloud-blob://evidence-hot"
    assert p["retention"] in {"30d", "90d", "180d", "1y", "3y", "forever"}
    assert p["bytes"] == len(b"trajectory-data-v1")
assert "trajectory-data-v1" not in json.dumps(p), "指针泄漏 payload 本体（AC-3d：git 侧零本体）"
PYEOF

# ---- 幂等 + retention 只增不减 ----
bash "$BLOB" put --file "$TMP/big.bin" --retention 30d >/dev/null \
  && grep -q '"retention":"90d"' "$ROOT/meta/$SHA.json" \
  && pass "幂等重 put 且 retention 只增不减（30d 不降 90d）" || fail "retention 被降级"
bash "$BLOB" put --file "$TMP/big.bin" --retention 1y >/dev/null \
  && grep -q '"retention":"1y"' "$ROOT/meta/$SHA.json" \
  && pass "retention 升级（90d→1y）" || fail "retention 未升级"
N=$(find "$ROOT/objects" -type f | wc -l | tr -d ' ')
[[ "$N" -eq 1 ]] && pass "同内容不重复入库（1 对象）" || fail "对象重复（$N）"

# ---- 不可变执法：同地址异内容=红 ----
CORRUPT="$ROOT/objects/${SHA:0:2}/$SHA"
printf 'tampered-content' >"$TMP/tamper.bin"
sha256sum "$CORRUPT" | cut -d' ' -f1 > /dev/null
# 直接改对象本体模拟地址冲突（内容寻址纪律破坏）
printf 'different-content' >"$CORRUPT"
bash "$BLOB" put --file "$TMP/big.bin" --retention 90d >/dev/null 2>&1
[[ $? -eq 3 ]] && pass "同地址异内容 → exit 3（不可变执法）" || fail "不可变纪律未执法"
printf 'trajectory-data-v1' >"$CORRUPT"  # 还原，供后续用例

# ---- AC-3e get：校验回取 ----
bash "$BLOB" get --sha256 "$SHA" --out "$TMP/roundtrip.bin" \
  && cmp -s "$TMP/roundtrip.bin" "$TMP/big.bin" \
  && pass "AC-3e 按指针回取一致（sha256 校验通过）" || fail "AC-3e 回取不一致"

# 篡改 → exit 3 零输出
printf 'corrupted' >"$CORRUPT"
OUT=$(bash "$BLOB" get --sha256 "$SHA" 2>"$TMP/g.err"); RC=$?
[[ $RC -eq 3 && -z "$OUT" ]] && pass "AC-3e 回取校验不符 → exit 3 零输出" || fail "回取篡改未拦截（rc=$RC）"
printf 'trajectory-data-v1' >"$CORRUPT"

# 缺失 → exit 3
bash "$BLOB" get --sha256 "$(printf 'a%.0s' {1..64})" >/dev/null 2>&1
[[ $? -eq 3 ]] && pass "缺失对象 → exit 3" || fail "缺失未 fail-closed"

# verify
bash "$BLOB" verify --sha256 "$SHA" >/dev/null && pass "verify 绿" || fail "verify 红（应绿）"

# ---- sweep：只删过期 ----
printf 'old-30d' >"$TMP/old.bin"
BLOB_STORE_NOW="2026-07-01T00:00:00Z" bash "$BLOB" put --file "$TMP/old.bin" --retention 30d >/dev/null
printf 'keep-90d' >"$TMP/keep.bin"
BLOB_STORE_NOW="2026-07-01T00:00:00Z" bash "$BLOB" put --file "$TMP/keep.bin" --retention 90d >/dev/null
printf 'keep-forever' >"$TMP/fv.bin"
BLOB_STORE_NOW="2026-07-01T00:00:00Z" bash "$BLOB" put --file "$TMP/fv.bin" --retention forever >/dev/null
BLOB_STORE_NOW="2026-08-29T00:00:00Z" bash "$BLOB" sweep | grep -q "SWEEP 1 删除 3 保留" \
  && pass "sweep 只删过期（30d 删，90d/forever/新对象 留）" || fail "sweep 语义不符"
OLD_SHA=$(sha256sum "$TMP/old.bin" | cut -d' ' -f1)
[[ ! -f "$ROOT/objects/${OLD_SHA:0:2}/$OLD_SHA" ]] && pass "过期对象已删" || fail "过期对象未删"

# ---- 端到端：>4KB payload 经指针进判定层（git 侧零本体） ----
python3 - "$TMP/huge.bin" <<'PYEOF'
import sys
open(sys.argv[1], "w", encoding="utf-8").write("x" * 8192)
PYEOF
PTR2=$(bash "$BLOB" put --file "$TMP/huge.bin" --retention 180d)
SHA2=$(printf '%s' "$PTR2" | sed -n 's/.*"sha256":"\([0-9a-f]*\)".*/\1/p')
python3 - "$TMP/ev.json" "$PTR2" <<'PYEOF'
import json, sys
ptr = json.loads(sys.argv[2])
ev = {
    "ts": "2026-08-29T00:00:00Z", "kind": "gate", "action": "test-trajectory-ref",
    "verdict": "pass",
    "subject": {"card": "Cloudbird-Software/.github#408", "tenant": "cloudbird-internal"},
    "actor": {"identity": "test-runner", "role": "bot", "model": None},
    "payload": None, "payload_ref": {"sha256": ptr["sha256"], "store": ptr["store"],
                                      "retention": ptr["retention"]},
}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(ev, ensure_ascii=False))
PYEOF
python3 "$DIR/governance/evidence_shadow.py" append --file "$TMP/shadow.jsonl" --event-file "$TMP/ev.json" >/dev/null \
  && python3 "$DIR/governance/evidence_shadow.py" verify --file "$TMP/shadow.jsonl" >/dev/null \
  && pass "端到端：>4KB 本体走轨迹层，判定层只存指针（append+验链绿）" || fail "端到端指针链失败"
grep -q "\"sha256\":\"$SHA2\"" "$TMP/shadow.jsonl" \
  && ! grep -q 'xxxxxxxx' "$TMP/shadow.jsonl" \
  && pass "判定层记录零 payload 本体（只有 payload_ref）" || fail "判定层泄漏本体"

echo "----------------------------------------"
if [[ $FAILS -eq 0 ]]; then echo "test-blob-store: PASS"; exit 0; fi
echo "test-blob-store: $FAILS 处失败"; exit 1
