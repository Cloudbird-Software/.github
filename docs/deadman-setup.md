# Dead-man 心跳配置 Runbook（owner 手工步骤）

> 关联：宪法 §6（缺席即停 / 外部 dead-man 心跳）、§11（唤醒矩阵末行"外部 dead-man 心跳"）；
> ADR-0057（W1-C5 .github#168）、ADR-0074（双层触发修订——hc.io 无法直连回调 GitHub，
> 外部层=检测+owner 告警，仓内层=heartbeat-watch 陈旧度自动 trip）。
>
> **当前状态（2026-08-21）**：healthchecks.io check 已注册（owner）、`DEADMAN_PING_URL`
> org secret 已配置、`butler-heartbeat` 实测 ping 成功（attempt 1/2）、仓内兜底
> `butler-heartbeat-watch` 已上线。**剩余 owner 侧仅 §1.3 的 grace 核对与 §3 的
> 告警通道选择**——自动 trip 已由仓内层承担，外部回调不再是必需项。

## 为什么心跳必须在外部

"心跳是唤醒的唤醒，也必须外部"（宪法 §11）：GitHub cron 全挂（Actions 故障、workflow
被删改、token 失效）时，GitHub 自己无法自我报警——缺席判定只能由独立的第三方服务做出。
GitHub 侧只做两件事：被动 ping（`butler-heartbeat`，每 30min）与被动接收 trip
（`butler-deadman-trip`，`repository_dispatch`）。

## 1. 注册外部 dead-man 服务（以 healthchecks.io 为例，任意同类服务均可）

1. 注册 <https://healthchecks.io>（免费层足够：20 个 check、100 天日志）。
2. 新建 check，命名建议 `cloudbird-butler-heartbeat`。
3. **Grace Time = 60 分钟**（= `governance/policy/butler.yaml` 的
   `thresholds.deadman_grace_minutes`；心跳每 30min 一次，60min grace 容忍一次 ping
   丢失，连续两次丢失即判定缺席）。改阈值须两侧同步改。
4. 记下 check 的 ping URL（形如 `https://hc-ping.com/<uuid>`）。

## 2. 注入 org secret（需 org admin）

```bash
gh secret set DEADMAN_PING_URL --org Cloudbird-Software -b"https://hc-ping.com/<uuid>"
```

- 建议可见性 = All repositories（至少 `.github` 仓可读）。
- 配置后 `butler-heartbeat`（每 30min）自动开始 ping；healthchecks.io 页面应出现
  成功心跳记录（最迟 30min 内）。

## 3. 失败告警配置（grace 超时 → owner 知晓 → 缺席即停）

**ADR-0074 双层触发**（hc.io 的 Webhook 不能带 Authorization header，无法直接回调
GitHub repository_dispatch——这是实测边界，不是配置遗漏）：

- **仓内层（已上线，自动）**：`butler-heartbeat-watch`（6h）检测 heartbeat 成功 run
  陈旧度 > `deadman_stale_hours`（3h）→ 自动执行 `governance/deadman-trip.sh`。
  覆盖"Actions 活着但心跳工作流被禁用/改名/损坏"。
- **外部层（hc.io 账号侧，owner 只需勾告警通道）**：check → **Integrations** 勾选
  邮件/Slack/Telegram 任一。覆盖"Actions 整体静默"（此时仓内层同死，只有外部
  服务能说话）。owner 收到告警后一键 trip：

  ```bash
  gh api -X POST repos/Cloudbird-Software/.github/dispatches     -H "Authorization: Bearer $PAT" -f event_type=deadman-tripped
  ```

若日后想让外部层也全自动（可选）：Cloudflare Worker 一行转发（收到 hc.io 回调
GET 后代发上方 curl，PAT 存 Worker 侧 secret）——非必需，双层已满足宪法 §6。

## 4. 演习步骤（月度正控建议 + 上线验证）

AC-3 的 fail-closed 实证路径 = 手动 dispatch（无需真停心跳）：

1. **触发**：Actions → `.github` 仓 → `butler-deadman-trip` → Run workflow
   （simulate=true，默认）。
2. **验证**：
   - org 变量已置位：`gh api orgs/Cloudbird-Software/actions/variables/AUTO_MERGE_DISABLED --jq .value` → `true`；
   - P0 issue 已开（label `deadman-tripped`）；
   - 运行日志含 `AUDIT | butler=deadman-trip | ... | outcome=tripped` 审计行；
   - 若有 open PR 挂着 auto-merge，应已被撤销。
3. **复位**（仅 owner，留痕）：
   ```bash
   gh api -X PATCH orgs/Cloudbird-Software/actions/variables/AUTO_MERGE_DISABLED \
     -f name=AUTO_MERGE_DISABLED -f value=false
   ```
   然后在 P0 issue 评论"演习复位（who/when）"并关闭。
4. **月度正控**（宪法 §7 审计节奏建议）：每月手动执行一次上述演习，确认 trip 管道
   仍真实可走（dead-man 通道最怕"配置漂移到静默失效"）。

配置了自动回调（§3 方案 A/B）后的**端到端负向演习**（每季度可选）：在 healthchecks.io
手动暂停 check（Pause）→ 等 grace（60min）超时 → 确认 `butler-deadman-trip` 被自动触发
→ 按 §4.3 复位。注意暂停期间 butler-heartbeat 的 ping 会持续失败变红，属预期。

## 5. 已知边界（诚实清单）

- 外部服务注册与回调配置是 owner 手工步骤，代码侧无法替代；未配置期间系统处于
  "可演习、未实连"状态——但 cost-check 熔断（ADR-0040）与 drift-check 的独立告警
  通道仍在，非单点失明。
- `DEADMAN_PING_URL` org secret 未配置时 `butler-heartbeat` 只 WARN 不红：这是刻意
  的（骨架期不因缺外部配置阻塞 CI）；配置完成即自动进入实测模式（失败重试 1 次后红）。
- 心跳 workflow 自身挂掉 = 与管家 cron 同死——这正是外部 dead-man 存在的理由：
  外部服务监督的是"包括 heartbeat 在内的全部 cron 的静默"。
- 复用熔断变量 `AUTO_MERGE_DISABLED`（与 cost-check/ADR-0040 共用）：两个触发源
  （成本超限 / 管家缺席）都会停自动合并，复位路径同一（见 §4.3）。
