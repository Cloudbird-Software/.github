#!/usr/bin/env bash
# 套件执行器（adversary 目标目录契约）：bash run-suite.sh <impl-dir>
# impl-dir 须含 spec.md。ROLE-CEO.md / AGENTS.md 可在 impl 根、impl/docs、或本仓正本。
# exit 0 = 全绿。攻击面=伪造「有标题无条款」的 ROLE/spec 对。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
IMPL="${1:?用法: run-suite.sh <impl-dir>}"
[[ -f "$IMPL/spec.md" ]] || { echo "impl 目录缺 spec.md: $IMPL" >&2; exit 2; }
PY="${METERING_PYTHON:-}"
if [[ -z "$PY" ]]; then
  PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/specs/IR-0011/suite" "$TMP/docs/agent"
cp "$DIR"/suite/*.py "$TMP/specs/IR-0011/suite/"
cp -- "$IMPL/spec.md" "$TMP/specs/IR-0011/spec.md"

pick_role() {
  local c
  for c in \
    "$IMPL/ROLE-CEO.md" \
    "$IMPL/docs/agent/ROLE-CEO.md" \
    "$DIR/ROLE-CEO.md" \
    "$DIR/../../docs/agent/ROLE-CEO.md"
  do
    if [[ -f "$c" ]]; then
      cp -- "$c" "$TMP/docs/agent/ROLE-CEO.md"
      cp -- "$c" "$TMP/specs/IR-0011/ROLE-CEO.md"
      return 0
    fi
  done
  return 1
}
pick_agents() {
  local c
  for c in \
    "$IMPL/AGENTS.md" \
    "$DIR/../../AGENTS.md"
  do
    if [[ -f "$c" ]]; then
      cp -- "$c" "$TMP/AGENTS.md"
      return 0
    fi
  done
  return 1
}
pick_role || echo "WARN: ROLE-CEO.md 未找到，suite 将失败" >&2
pick_agents || echo "WARN: AGENTS.md 未找到，suite 将失败" >&2
cd "$TMP/specs/IR-0011/suite"
"$PY" test_role_ceo_doc.py
