#!/usr/bin/env bash
# 套件执行器（adversary 目标目录契约）：bash run-suite.sh <impl-dir>
# impl-dir 须含 spec.md（被审"实现"= spec+acceptance 文档对）；exit 0 = 全绿。
# IR-0005 形态特殊性：owner 直执行（ADR-0085 决策背书），本套件断言条款文档与
# 验收证据的语义一致性——攻击面=伪造"看起来验收过"的文档对。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
IMPL="${1:?用法: run-suite.sh <impl-dir>}"
[[ -f "$IMPL/spec.md" ]] || { echo "impl 目录缺 spec.md: $IMPL" >&2; exit 2; }
PY="${METERING_PYTHON:-}"
if [[ -z "$PY" ]]; then
  PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/specs/IR-0005/suite"
cp "$DIR"/suite/*.py "$TMP/specs/IR-0005/suite/"
cp -- "$IMPL/spec.md" "$TMP/specs/IR-0005/spec.md"
[[ -f "$IMPL/acceptance.md" ]] && cp -- "$IMPL/acceptance.md" "$TMP/specs/IR-0005/acceptance.md" || true
cd "$TMP/specs/IR-0005/suite"
IMPL_DIR="$TMP/specs/IR-0005" "$PY" test_spec_ir0005.py
