# 自动化反馈通道规范（bot / agent）

适用对象：一切以机器身份在组织仓库产出反馈的自动化——GitHub App
（cloudbrid-agent）、Actions workflow、任何未来接入的 bot / reviewer agent。

## 规则 1：机器不得创建 review comment / review thread

机器意见只允许两种通道：

1. **check run annotation**（首选——随 required check 状态进入合并判据）
2. **普通 PR comment**（issue comment，不产生 review 状态）

禁止机器调用 `POST /pulls/{n}/comments`（review comment）、
`POST /pulls/{n}/reviews`（含 COMMENT 结论的 review）——这两类操作产生
review thread。

理由（自动合并计划 #81 §2.2 / P1-2 #83）：`required_review_thread_resolution`
曾经为 true 时，任何 bot 留下的 unresolved thread 都是无人值守下的永久
pending 死锁——没有人去点 resolve。该 required 条件已在 P1-2 移除；本规范
保证 thread 通道未来重新启用时（如转为 required），机器不会重新制造死锁。

## 规则 2：机器不得 resolve / dismiss 人类的 review thread

被审者（无论人还是 agent）关闭审计意见在语义上不可接受（#81 §2.2
三选一中的反例）。thread 的 resolve 只属于人类 owner。

## 规则 3：机器不得自我授权

机器不得 approve PR、不得把红 check 变绿、不得替代任何确定性检查。
未来引入 reviewer agent（#97）时必须是 veto-only：只能把绿变红。
机器身份不得调用 rerun 类 API 洗掉红灯（#81 §3.4）。