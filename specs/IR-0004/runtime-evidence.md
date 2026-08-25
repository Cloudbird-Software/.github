# IR-0004 rev6 运行时证据卷宗（本地真跑记录，2026-08-25T01:2x-01:4x UTC）

> 记录人：PM 会话（GLM-5.3）。仪器全部位于 CI-Workflows main（PR#100/#102/#103/#104/#105）与 cnb-bridge main（PR#1/#2）。

## AC-8 DSL 编译器（对真实 spec 全链）
- 编译：`compile.py --spec specs/IR-0005/spec.md` → GREEN（AC×7, spec-hash 2f14564830c7…）
- 校验：`verify.py` → GREEN（spec-hash/逐 AC hash/应然内容三重一致）
- 篡改：追加一行注释后 verify → **exit 1**（手改检出 ✓）
- 过程中修复真缺陷：IR-0005 spec frontmatter 未闭合（缺结束 ---，已随本 PR 修）

## AC-9/AC-13 + #334 自举试点（仪器链全通）
- 熵仪器：三骨架 → convergence 20%、疑似串通 0、契约分歧 3、路线分歧 3、假设并集 4
- 燃料产物：fanout-products.jsonl 哈希链（B/C 两代理契约不一致的集成缝已修复对齐）
- 消费者：`consumer.py --products-dir pilot-out` → **exit 0**（链校验+字段+type 枚举全过）
- 空目录模式：`--empty-ok` → consumed:0 非红（rev6 消费者常在语义 ✓）

## AC-11/12 oracle 接口
- 注册表演示条目 validate → OK（1 条目合法）
- diffbench：硬区分歧（score/case-2 champion=7 vs oracle=9）→ **exit 2** + 裁决路由文案 ✓

## AC-19 静态干跑（双真仓）
- `.github` 仓 → **exit 0 green**（三接缝外零操作性引用；EX-1 节 YAML 列表项识别修复）
- `cnb-bridge` 仓 → **exit 0 green**（自层模式：桥形判定+REMOVAL.md 在位）

## 子代理离线自测汇总
A1=55、A2=42、B=28、C=44、D=32（合并布局仿真 51 含既有 19）——合计 201 用例全绿。
