#!/usr/bin/env bash
# lib.sh —— 演练自测公共助手（W4-C4）
# pick_py: 选出真实可用的 python 解释器（CI 恒有 python3；本地 Git Bash 的
# python3 可能是 Windows 商店 stub——command -v 找得到但执行即败，必须实测）
pick_py() {
  local c
  for c in "${PYTHON:-}" python3 python py -3; do
    [[ -n "$c" ]] || continue
    "$c" -c 'import sys, yaml; print("ok")' >/dev/null 2>&1 || continue
    echo "$c"; return 0
  done
  return 1
}
