#!/usr/bin/env bash
# test-drill.sh —— W4-C4 活体演习链路自测入口（.github#223 / ADR-0069）
# gate"治理脚本自测"自动纳入 governance/tests/test-*.sh；本入口聚合
# governance/drill/tests/ 下全部 test-*.sh（样本库 schema/选样随机性/红绿判定/
# 台账 append-only/缺席 fail-closed dry-run）。目录为空=测试面丢失，fail-closed。
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../drill/tests" && pwd)"
shopt -s nullglob; tests=("$HERE"/test-*.sh); shopt -u nullglob
if [[ ${#tests[@]} -eq 0 ]]; then
  echo "::error::governance/drill/tests 无 test-*.sh——演习测试面丢失（fail-closed）"
  exit 1
fi
for t in "${tests[@]}"; do echo "-- $t"; bash "$t" || exit 1; done
echo "drill 全部自测通过（${#tests[@]} 套）"
