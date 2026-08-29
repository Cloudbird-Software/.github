# PM 凭证收敛与应急回退通道（IR-0006 W2-C2 / 卡 #413）

> 目标态（ADR-0103 决策 5 / ADR-0044 机制上收）：PM 会话在云电脑上**零长期凭据**——
> 日常写仓令牌由内网服务器用 cloudbrid-agent App 私钥（Vault 注入）**代签**：
> 单仓作用域 + 短 TTL≤波次（240 分钟上限）。个人 PAT 退出日常流程，仅作为
> 应急回退通道存在（见 §3）。实现面：`cnb-bridge/selfcloud`（`gh-token` 系列
> 子命令）；运维手册：cnb-bridge `RUNBOOK.md` §6。
>
> 维护契约：本文件是 AC-6a「应急回退通道文档化」的落盘件——回退触发条件、
> 24h 窗口约束、恢复判定修改须同步更新（C1 面：PR 引 ADR + owner review）。

## 1. 日常流程（无个人 PAT）

```bash
selfcloud gh-token --app-id "$CB_APP_ID" --key-file /vault/cloudbrid-agent.pem \
  --repo <仓> --card <org>/<repo>#<卡号> \
  --ledger /var/lib/selfcloud/tickets.jsonl --expect-token
```

- 令牌值仅 stdout 一次性交付（`--expect-token`）；台账 `token.grant` 事件
  payload **零令牌值**（INV-04：凭据永不进 agent/PM 上下文与账本）。
- 作用域强制单仓（`repositories` 限定，无全安装作用域模式）；TTL 断言
  `0 < TTL ≤ 240min`，越界拒签。
- 签发/收回事件按 schema v1 入 `tickets.jsonl`（cnb-bridge `tickets-ledger`
  分支），统一账本第 5 源可按 `subject.card` 查询（`governance/evidence-query.sh`）。
- 到期收回实测断言：`selfcloud gh-token-check --expect-401`（探活 401=已收回）；
  真实演练走 cnb-bridge `tokenagent-drill.yml`（revoke=提前收回 / expiry=等 TTL）。

## 2. 失效判定（何时触发回退）

满足任一即认定 App 代签通道失效：

1. `gh-token` 连续签发失败（installation 定位 404 / JWT 被拒 401 / 换令牌非 201）。
2. `tokenagent-drill` 工作流红且日志含签发步骤失败（非网络抖动）。
3. App 被 owner 挂起/删除，或私钥轮换未同步到 Vault。

## 3. 应急回退通道（App 失效 → owner PAT，24h 窗口）

**这条通道只对 owner 开放**：PAT 属长期凭据，agent/PM 永不持有（INV-04）。

1. **触发**：owner 按§2 判定代签通道失效，在 .github 仓开 issue
   `fallback: credential-channel` 记录判定证据（drill run 链接/错误日志）。
2. **授权**：owner 在自己的本地环境（非 agent 上下文）用个人 PAT 临时执行
   写仓操作，或将 PAT 注入 **org secret** `EMERGENCY_OWNER_PAT` 供指定工作流
   借道使用（工作流面消费，key 不入任何 agent 上下文——与 CNB 池同纪律）。
3. **24h 窗口约束**：
   - 回退自触发起**最多 24 小时**；到期仍未恢复代签通道=升级 owner 事故面
     （P1：所有写仓操作停摆，先修通道再干活）。
   - 窗口内每笔写仓操作在回退 issue 追加评论留痕（append-only）。
   - 窗口关闭（通道恢复或到期）后 owner **立即撤销** `EMERGENCY_OWNER_PAT`
     secret 或本地吊销 PAT，并在 issue 评论 `fallback: closed`。
4. **恢复判定**（回退退出条件）：`tokenagent-drill`（revoke 模式）全绿——
   代签→探活 200→收回→探活 401→事件入账 push 成功。
5. **审计**：回退 issue 全程留痕；窗口内令牌签发数为 0（PAT 通道不经
   selfcloud 台账，以 issue 评论为审计真源）。

## 4. 相关面

- 实现：cnb-bridge `selfcloud/ghtoken.go`（代签/收回/探活/入账）
- 演练：cnb-bridge `.github/workflows/tokenagent-drill.yml`（org secrets 面）
- 删除语义：cnb-bridge `REMOVAL.md`（代签面可删；org secrets 不随删）
- 依据：ADR-0044（App 令牌机制）· ADR-0103 决策 5（凭证收敛决策）·
  spec `specs/IR-0006/spec.md` AC-6a/6b
