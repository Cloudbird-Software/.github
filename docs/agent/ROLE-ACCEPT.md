# ROLE-ACCEPT —— 验收与 bug 修复（issues 处理角色）

> 触发条件：**人类让你处理 issues**（检查完成度 / 验收 / 修 bug / 处理 incident）。
> 本文件是你的完整指引。依据：ADR-0095 / ADR-0085（T9 验收谓词）/ ADR-0064（bug 流
> B1–B5 机器复现）。深度手册：[PLAYBOOK.md](../pm/PLAYBOOK.md) §5。

## 一句话

两类工作：①**盘点完成度**——对所有工作卡和 IR 检查是否完成，未完成的开 bug issue
后修复；②**处理 bug/incident**——先复现，无法复现的关闭，能复现的修复、推 PR、
合并、关闭 issue。判定锚点全部机械，自述不算证据。

## 一、检查工作卡与 IR 完成度

1. **盘点**：`bash ghcb board`（逐活跃仓）列出全部 `state:*` 的卡与 `type:intent`
   的 IR——不只看 ready；对每张卡 / 每条 IR 判定「是否真的完成」：
   - 卡：T8 判据=存在 body 含 `Card: <repo>#<n>` 且**已合并**的 PR（合并事实即
     全 gate 绿的载体）；`gh pr list --state merged` / issue 评论可核对。
   - IR：T9 判据=全部子卡 `state:done` + `specs/<IR-NNNN>/acceptance.md` 存在
     （子卡=body 含 `父意图: #<n>` 的 issue）。
2. **未完成的**：开 bug issue（模板 `bug.yml`，org 级继承各仓可用；写明缺口事实：
   哪张卡/哪条 IR、缺什么证据/哪项 AC 未满足）→ 按「二、bug 流」修复 →
   修复 PR 合并后关闭 bug issue。
3. **IR 级验收**（全部子卡 done 后）：写 `specs/<IR-NNNN>/acceptance.md`——
   逐 AC 列运行时证据（gate run / build log / 红队报告链接）+ SHA 锚；
   骨架用 `bash ghcb accept <IR#> [repo]` 生成。打 `state:done` 由 conductor T9
   谓词机械校验（全部子卡 done + acceptance.md 存在，缺一即拒绝）。

## 二、bug / incident 流（复现前置，ADR-0064）

```
bug issue 提交（bug.yml）→ B1–B5 机器复现，三值判定
  ├─ reproduced        → 修复：先写复现失败测试（B2 锚定 base 红）
  │                      → 推 PR → 处理完全部 CI 与 review 问题 → 合并
  │                      → 合入后复现测试转绿、状态自动回写 → 关闭 issue
  ├─ cannot-reproduce  → 关闭 issue（留复现尝试记录：环境/步骤/差异假设）
  └─ inconclusive      → 留待 owner 裁决，不强关
```

- **无法复现的关闭**：关闭评论写清你尝试了什么（环境、步骤、版本、与报告者的
  差异假设），可复活的线索留给后来者；不做无证据的「顺手修」。
- **能复现的修复**：修复 PR 同样必须**解决完全部 CI 与 review 问题方可合并**
  （required check 全绿 + owner review；永不自批自合）；PR body 关联 bug 单
  （B3 状态回写靠它；卡派生工作另带 `Card:` 元数据行）。合并后关闭 issue。
- incident（线上事件类）：先固化复现/时间线证据（事件不可复现也保留证据链），
  修复路径同上。

## 红线速查

- 自述不算证据：完成度判定只认机械可回查的运行时证据（PR 合并事实 / gate run /
  SHA 锚定）。
- 修 bug 不许删/改/弱化既有测试；复现失败测试是修复 PR 的一部分。
- holdout 相关失败的处理见 [ROLE-IMPLEMENT.md](ROLE-IMPLEMENT.md)（修实现不修试卷，
  quarantine + needs-human）。
- 每次 run 结束写运行报告（`bash ghcb report` → archive runs/，三节式）。
