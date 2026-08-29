#!/usr/bin/env bash
# 套件执行器（adversary 目标目录契约）：bash run-suite.sh <impl-dir>
# impl-dir 须含 spec.md（被审"实现"= spec+附件文档对）；exit 0 = 全绿。
# IR-0006 形态：治理总纲吸收 spec（条款+落位表+六波次总图），本套件断言
# spec 结构完整性（AC 三段/条款唯一/附件在场/落位 18 行/波次六段）——
# 攻击面=伪造"结构齐全但内容空洞"的文档对（红队 S1'/S2' 语义）。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
IMPL="${1:?用法: run-suite.sh <impl-dir>}"
[[ -f "$IMPL/spec.md" ]] || { echo "impl 目录缺 spec.md: $IMPL" >&2; exit 2; }
PY="${METERING_PYTHON:-}"
if [[ -z "$PY" ]]; then
  PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/specs/IR-0006/suite"
cp "$DIR"/suite/*.py "$TMP/specs/IR-0006/suite/"
cp -- "$IMPL/spec.md" "$TMP/specs/IR-0006/spec.md"
for f in absorption-map.md wave-plan.md; do
  [[ -f "$IMPL/$f" ]] && cp -- "$IMPL/$f" "$TMP/specs/IR-0006/$f" || true
done
cd "$TMP/specs/IR-0006/suite"
IMPL_DIR="$TMP/specs/IR-0006" "$PY" test_spec_ir0006.py
