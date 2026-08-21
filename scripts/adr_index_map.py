#!/usr/bin/env python3
"""adr_index_map.py —— 墓碑索引 → 关卡消费的两路映射（W1-C1 .github#164 交付 3）。

gate.yml adr-required 索引世界（ADR-0053）的 INDEX.yaml 解析器：
  adr_map.txt      "NNNN archive_path" 行（lifecycle != archived 的 entries；
                   #96 实质校验扩展点：后续 substantive 字段不影响本映射——
                   number/archive_path/lifecycle 是关卡消费的键）
  adr_archived.txt "NNNN" 行（lifecycle == archived——引用即拒：历史回填不可
                   作为新决策依据，#164 交付 3）

抽成仓内脚本而非 workflow 内联 python 的原因：`python3 -c '…'` 的多行代码
继承 YAML 缩进，首语句带缩进即 IndentationError（#174 引入、索引世界上线后
首个 C1 PR 实测暴露）；独立脚本可本地测试（对 live INDEX 演练见 #207 body）。

用法：python3 scripts/adr_index_map.py [INDEX.yaml] [map.txt] [archived.txt]
默认路径与 gate.yml 运行环境一致（/tmp）。fail-closed：解析失败/entries 空
非零退出，由调用方报错。
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

DEFAULTS = ["/tmp/adr_index.yaml", "/tmp/adr_map.txt", "/tmp/adr_archived.txt"]


def main(argv: list[str]) -> int:
    index_path, map_path, archived_path = (argv[1:4] + DEFAULTS[len(argv) - 1:])[:3]
    data = yaml.safe_load(Path(index_path).read_text(encoding="utf-8"))
    entries = (data or {}).get("entries") or []
    valid = archived = 0
    with open(map_path, "w", encoding="utf-8") as m, \
            open(archived_path, "w", encoding="utf-8") as a:
        for e in entries:
            p = e.get("archive_path")
            if not p:
                continue
            num = f"{int(e['number']):04d}"
            if e.get("lifecycle") == "archived":
                print(num, file=a)
                archived += 1
            else:
                print(num, p, file=m)
                valid += 1
    if valid == 0:
        print("FATAL: INDEX.yaml entries 为空/无有效 archive_path——索引世界不可判定",
              file=sys.stderr)
        return 1
    print(f"OK adr-index-map: valid={valid} archived={archived}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
