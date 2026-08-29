# 统一证据账本·标准（v1）

> IR-0006 W1-B1 / ADR-0103。判定层记录 schema：[record.schema.yaml](record.schema.yaml)
> （`$id: cloudbird/evidence-standard/record@1`）。

## 三层纪律（宪法 §14a / INV-06）

| 层 | 载体 | 内容 | 纪律 |
|---|---|---|---|
| 判定层 | archive 仓 `evidence/` | gate 裁决/成本/审批/决策四类事件（BEH-01） | append-only + 链式 hash（INV-03）；payload 内联 ≤4096 字节，超限拒写 |
| 轨迹层 | 云内网 blob | 大体积原始数据 | git 侧只存 `payload_ref`（sha256+store+retention，W1-B3） |
| 丢弃层 | GitHub 事件面 | transient 事件 | 不承诺持久 |

## OTel gen_ai.* 映射（字段命名对齐语义约定）

| 本 schema 字段 | OTel 语义约定对应 | 说明 |
|---|---|---|
| `ts` | event timestamp（ISO 8601 UTC） | 事件时间戳 |
| `subject.card` | `gen_ai.conversation.id`（关联语义） | 卡 issue 三源统一 join key（AC-4） |
| `subject.commit` | `github.pull_request.head.sha`（拉 PR head） | 被判定对象 |
| `actor.identity` | `gen_ai.system`（责任主体语义） | 行为者 |
| `actor.model` | `gen_ai.request.model` | LLM 判定模型；非 LLM 判定为 null（INV-01 机械锚点） |
| `cost.tokens` | `gen_ai.usage.input_tokens`+`output_tokens` 汇总 | token 归账 |
| `cost.usd` / `cost.wall_sec` | metering 归账口径 | 成本/墙钟 |
| `inputs_digest` | provenance 锚点 | 判定输入摘要 sha256 |

命名对齐目的：W1-B2 三源（metering/butler/drill）按 schema v1 双写时可直接复用
OTel 采集面，无需字段翻译层。

## 写入与验证（执法面在 archive 仓）

- 写入：`archive scripts/write_evidence.py`——唯一合法写入器。执法项：
  payload ≤4096 字节（UTF-8）超限拒写；`subject.tenant` 必填；append-only
  （行内禁改，纠错追加 erratum 事件）；prev_hash 链式续接。
- 验证：`archive scripts/verify_evidence.py`——独立复算（不信任写入器自报）：
  seq 连续、prev_hash 链、hash 重算、tenant 字段在场；任一断裂=红（fail-closed）。
- checkpoint：月度快照 `evidence/checkpoints/YYYY-MM.json`（当月链头 hash + 记录数），
  验证脚本对账 checkpoint 与链头——不匹配=红（BEH-02）。

## 消费方

- cost-check 波次视图（W2-C3）：`subject` 聚合自本账本。
- 三源统一查询（W1-B2）：`subject.card` 为 join key。
- 飞书投影/SLI 周报（W3/W4）：只读消费。
