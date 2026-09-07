# negtest-m2 — M2 资源池 v0 负面测试记录（证据件）

- 执行：2026-09-06，资源池轨道 agent
- 脚本：`controls/negtest_m2.sh`（可复跑：前置幂等拉起 OPA/LiteLLM，任何断言 FAIL 退出码非 0）
- 规范依据：DGA-INFRA-v1.0 3.2（R-POOL-TRUST）/ 3.3（R-POOL-DATA 硬红线）/ 3.4（R-POOL-COMPLIANCE）/ 3.5（R-POOL-DEGRADE）；R-POL-03（虚拟 key+限额+消费入账三证据）
- 结果：**PASS=9 FAIL=0（ALL PASS）**，以下为实际输出逐字贴入（运行环境：Windows 11 + Git Bash，OPA 1.20.2 @8181，LiteLLM 1.100.0 @4000，PG 16.9 @5432）
- 纪律：全 mock，零真实密钥；master key `sk-dga-local-dev` 为本机占位非凭据

## 判定链总览

```
route_check.py（查 dga_control.pool_* 候选，按 trust↑→cost↑ 排序）
  → 逐端点 POST OPA /v1/data/dga/pool/allow（dga.pool，policies/pool-routing.rego）
  → routed（首个 allow）/ denied（策略全败，合并 deny_reasons）/ queued（可用性全败，3.5）
```

OPA 谓词语义（3.2 表映射 public/internal/customer_sensitive ↔ T0/T1/T2，rank(sensitivity) ≤ rank(trust)）；
灰区规则（tos_risk ∈ {grey-zone, high-risk} 且 sensitivity 非公开 → deny）独立于信任级；
红线显名（customer_sensitive × T0 额外产出 R-POOL-DATA，便于证据流单独检索）。

## 案例①：sensitivity=customer_sensitive → T0 端点被 OPA deny（路由器拒绝+原因）

期望：所有候选 deny；T0 候选拒因含 **R-POOL-DATA**（3.3 红线显名）；v0 拓扑无 T2 → 终态 denied。
实际（`route_check --task-id NT-0001 --sensitivity customer_sensitive`，exit=2）：

```json
{
  "task_id": "NT-0001",
  "sensitivity": "customer_sensitive",
  "decision": "denied",
  "endpoint": null,
  "trust_label": null,
  "routing_policy_id": null,
  "credential_ref": null,
  "evaluated": [
    {
      "endpoint": "free-workhorse",
      "trust_label": "T0",
      "allow": false,
      "reasons": ["R-POOL-DATA", "R-POOL-TRUST"]
    },
    {
      "endpoint": "gray-probe",
      "trust_label": "T0",
      "allow": false,
      "reasons": ["R-POOL-COMPLIANCE", "R-POOL-DATA", "R-POOL-TRUST"]
    },
    {
      "endpoint": "paid-judge",
      "trust_label": "T1",
      "allow": false,
      "reasons": ["R-POOL-TRUST"]
    }
  ],
  "reasons": ["R-POOL-COMPLIANCE", "R-POOL-DATA", "R-POOL-TRUST"],
  "policy": "dga.pool/pool-routing.rego (R-POOL-TRUST/DATA/COMPLIANCE)"
}
```

`>>> [①customer_sensitive→denied 且含 R-POOL-DATA] PASS`

## 案例②：sensitivity=internal → T0 deny、T1 allow

期望：internal 仅 T0 不可承接（rank 1 > rank 0）；T1 可承接；路由器先拒 T0 再落 paid-judge。
实际（OPA 直查两态 + 路由器全程）：

```text
--- OPA 直查 internal×T0 (expect allow=false) ---
{"result":{"allow":false,"deny_reasons":["R-POOL-TRUST"]}}
>>> [②a OPA internal×T0 deny] PASS
--- OPA 直查 internal×T1 (expect allow=true) ---
{"result":true}
>>> [②b OPA internal×T1 allow] PASS
```

路由器全程（T0 两个端点被拒留痕后落 paid-judge）：

```json
{
  "task_id": "NT-0002",
  "sensitivity": "internal",
  "decision": "routed",
  "endpoint": "paid-judge",
  "trust_label": "T1",
  "routing_policy_id": "RTP-0001",
  "credential_ref": null,
  "evaluated": [
    { "endpoint": "free-workhorse", "trust_label": "T0", "allow": false, "reasons": ["R-POOL-TRUST"] },
    { "endpoint": "gray-probe", "trust_label": "T0", "allow": false, "reasons": ["R-POOL-COMPLIANCE", "R-POOL-TRUST"] },
    { "endpoint": "paid-judge", "trust_label": "T1", "allow": true }
  ],
  "reasons": ["R-POOL-COMPLIANCE", "R-POOL-TRUST"],
  "policy": "dga.pool/pool-routing.rego (R-POOL-TRUST/DATA/COMPLIANCE)"
}
```

`>>> [②c 路由器 internal→routed=paid-judge 且 T0 被拒留痕] PASS`

## 案例③：tos_risk=grey-zone 账号端点承接 internal → deny（R-POOL-COMPLIANCE）

期望：ACC-0003（grey-zone，DB 约束强制 T0）承载的 gray-probe 拒绝 internal；且灰区规则独立于
信任级——即使端点被误标 T1 也须 deny、拒因仅 R-POOL-COMPLIANCE。
实际：

```text
--- 路由器 evaluated 中 gray-probe 的拒绝留痕 ---
{ "endpoint": "gray-probe", "trust_label": "T0", "allow": false,
  "reasons": ["R-POOL-COMPLIANCE", "R-POOL-TRUST"] }
>>> [③a 路由器留痕含 R-POOL-COMPLIANCE] PASS

--- OPA 直查：灰区端点即使被误标 T1 也须 deny（灰区规则独立于信任级）---
{"result":{"allow":false,"deny_reasons":["R-POOL-COMPLIANCE"]}}
>>> [③b 灰区误标T1仍deny（仅R-POOL-COMPLIANCE）] PASS
```

（③a 的完整路由器输出与案例②相同结构，gray-probe 拒因行如上摘录。）

## 案例④（阳性对照）：sensitivity=public → T0 allow

期望：公开任务可进 T0 免费作业端点，且最便宜可信端点优先。
实际（`route_check --task-id NT-0004 --sensitivity public`，exit=0）：

```json
{
  "task_id": "NT-0004",
  "sensitivity": "public",
  "decision": "routed",
  "endpoint": "free-workhorse",
  "trust_label": "T0",
  "routing_policy_id": "RTP-0001",
  "credential_ref": null,
  "evaluated": [
    { "endpoint": "free-workhorse", "trust_label": "T0", "allow": true }
  ],
  "reasons": [],
  "policy": "dga.pool/pool-routing.rego (R-POOL-TRUST/DATA/COMPLIANCE)"
}
```

`>>> [④public→routed=free-workhorse] PASS`

## 案例⑤：virtual key 超 max_budget 后调用被拒（预算执法，R-POL-03）

方法：建 max_budget=0.001 的 vkey；mock 定价 input/output_cost_per_token=0.001，
一次调用 30 token → spend 0.03 > 0.001（调用后异步入账）→ 后续调用应被拒。
期望证据链：未超限 200 → 超限 429 budget_exceeded → spend 入 DB（LiteLLM_SpendLogs）。
实际：

```text
key/generate(截取): {"key_alias":"m2-negtest-1788714018","duration":null,"models":[],"spend":0.0,
  "max_budget":0.001,"user_id":null,"team_id":null,"agent_id":null,"max_parallel_requests":null,
  "metadata":{},"tpm_limit":nul...
virtual key prefix: sk-CpnAfTe...
--- 调用 1（expect 200；spend 0.03 > max_budget 0.001 在调用后记账）---
call#1 HTTP 200
>>> [⑤a 未超限前调用 200] PASS
--- 轮询调用至预算拦截（spend 异步入账，最多 6 次×3s）---
attempt 1: HTTP 429
{"error":{"message":"Budget has been exceeded! Key=m2-negtest-1788714018 (sk-...36PQ) Current cost: 0.03000000000000122, Max budget: 0.001","type":"budget_exceeded","param":null,"code":"429"}}
>>> [⑤b 超限调用被拒（budget_exceeded）] PASS
--- 消费入账证据（LiteLLM_SpendLogs 计数与最近行）---
 spend_rows
------------
          5
(1 row)

      model       | spend | prompt_tokens | completion_tokens | total_tokens
------------------+-------+---------------+-------------------+--------------
 mock-free        |     0 |             0 |                 0 |            0
 openai/mock-free |  0.03 |            10 |                20 |           30
 mock-free        |     0 |             0 |                 0 |            0
 openai/mock-free |  0.03 |            10 |                20 |           30
(4 rows)
```

（spend=0 的行是 429 被拒调用的失败日志——被拒请求零消费，亦为执法留痕。）

## 汇总

```text
PASS=9 FAIL=0
NEGTEST-M2: ALL PASS
```

## 覆盖对照与边界登记

| 案例 | 规范锚点 | 判定层 |
|---|---|---|
| ① | R-POOL-DATA（3.3 硬红线） | OPA（策略层拒绝，非提示词级——SEL-05 N-1 对应） |
| ② | R-POOL-TRUST（3.2） | OPA |
| ③ | R-POOL-COMPLIANCE（3.4） | OPA（灰区独立于信任级） |
| ④ | 3.2 阳性对照 | OPA + 路由器 |
| ⑤ | R-POL-03（虚拟 key 限额） | LiteLLM（429 budget_exceeded）+ DB 入账 |

- 案例①同时是"v0 无 T2 ⇒ 客户敏感任务宁可拒绝不降级"的设计验证（pools/README §遗留 6）。
- 排队路径（decision=queued，3.5 可用性全败）不在本套负面测试内，由 route_check.py
  `--mark-unhealthy` 演示（degradation.yaml step4 实现级形态）。
