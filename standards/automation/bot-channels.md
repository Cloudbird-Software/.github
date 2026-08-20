# 自动化反馈通道规范（bot / agent）

适用对象：一切以机器身份在组织仓库产出反馈的自动化——GitHub App
（cloudbrid-agent）、Actions workflow、任何未来接入的 bot / reviewer agent。

## 规则 1：机器不得创建 review comment / review thread

机器意见只允许两种通道：

1. **check run 的失败 conclusion**（首选——合并阻塞由 required check 的 check run
   整体 `conclusion` 决定；annotation 只是 check run 的行级附属输出，单独发布
   annotation 不阻塞合并，机器否决必须把 job 判为 failure）
2. **普通 PR comment**（issue comment，不产生 review 状态）

禁止机器调用 `POST /pulls/{n}/comments`（review comment），以及
`POST /pulls/{n}/reviews` 携带行级 `comments` 数组的形态——后者才产生 review
comment / review thread（仅带 body 的 COMMENT review 不产生 thread，但为通道
统一同样禁用）。

理由（自动合并计划 #81 §2.2 / P1-2 #83）：`required_review_thread_resolution`
曾经为 true 时，任何 bot 留下的 unresolved thread 都是无人值守下的永久
pending 死锁——没有人去点 resolve。该条件已在 P1-2 将 ruleset 定义改为
`false`（PR 合并并由 apply.sh 应用后生效）；本规范保证 thread 通道未来重新
启用时（如转为 required），机器不会重新制造死锁。

## 规则 2：机器不得 resolve / dismiss 人类的 review thread

被审者（无论人还是 agent）关闭审计意见在语义上不可接受（#81 §2.2
三选一中的反例）。thread 的 resolve 只属于人类 owner。

## 规则 3：机器不得自我授权

机器不得 approve PR、不得把红 check 变绿、不得替代任何确定性检查。
未来引入 reviewer agent（#97）时必须是 veto-only：只能把绿变红。
机器身份不得调用 rerun 类 API 洗掉红灯（#81 §3.4）。