# pools/ — DGA-INFRA 资源池（M2 资源池 v0）

权威源=控制面 DB `dga_control.pool_*`（INFRA 3.1 / 第 1 章权威源表）。本目录是该账本的
Git 侧定义物：DDL+种子、路由器、降级链、LiteLLM 网关配置。

## 文件清单

| 文件 | 内容 |
|---|---|
| `ledger.sql` | 池账本 DDL（pool_providers/pool_accounts/pool_routing_policies/pool_endpoints）+ 全 mock 种子；幂等（IF NOT EXISTS + ON CONFLICT） |
| `route_check.py` | 池路由器 v0（**未来 MCP 网关 Action Registry 的路由入口**，见其头部登记注释） |
| `degradation.yaml` | 降级链权威定义（3.5；T0 不作客户链路降级终点已注释钉死） |
| `litellm.config.yaml` | LiteLLM Proxy 配置（端口 4000；零真实 key，mock_response 短路） |

启动：`bash services/scripts/start-litellm.sh`（幂等；master key 占位 `sk-dga-local-dev`，
**本机占位非凭据**）。

## 1. 池账本（ledger.sql）

本体映射登记：`schemas/generated/dga-ontology.sql` 虽含 LinkML 生成的
`PoolAccount/LogicalEndpoint/RoutingPolicy` 表，但不直接复用——(a) 列类型 DATETIME 为生成器
通用型，PG 16 不能装载；(b) quota_state/health 被拆标量表而非 JSON 值对象；(c) 无降级链数组。
故建 `pool_*` 权威表，字段与本体类一一对应（PRV/ACC/EPL/RTP 前缀不变）；投影同步待名词
运行时落位（S5-PENDING-DEFAULTS 追加项 B）。

种子（全 mock，零真实密钥；credential_ref 按 SEL-06 默认格式 `openbao://kv/dga/pool/<alias>`，
OpenBao dev inmem 尚未写入对应 secret——缺口见 §遗留）：

| ID | 对象 | 关键标签 |
|---|---|---|
| PRV-0001 | mock-freelayer | mode=mock_response；模拟"数据可能用于训练"条款（T0 依据） |
| PRV-0002 | mock-paidlayer | mode=mock_response；模拟"数据不用途+SLA"条款（T1 依据） |
| ACC-0001 | mock-free-01 | free/T0/clear；quota_state+health JSON 全 mock |
| ACC-0002 | mock-paid-01 | low-paid/T1/clear |
| ACC-0003 | mock-gray-01 | free/T0/**grey-zone**（3.4 灰区场景 mock 复现；DB 约束 `grey_zone_forced_t0` 钉死灰区必 T0） |
| RTP-0001 | pool-v0-default | 成本白名单 [free,low-paid]；fallback_chain 数组；budget_cap；virtual_key_isolated=true（R-POL-03） |
| EPL-0001 | free-workhorse | T0，绑 [ACC-0001]，litellm_model=mock-free |
| EPL-0002 | paid-judge | T1，绑 [ACC-0002]，litellm_model=mock-paid |
| EPL-0003 | gray-probe | T0，绑 [ACC-0003]，**仅负面测试/合规演示**（任务种子只列两端点，此为负面测试③所需新增，已登记） |

责任人字段 `accountable_person` 暂为角色槽引用 `S5(...)`，具名 PSN 登记属本体轨道（登记不阻塞）。

## 2. OPA 池路由谓词（policies/pool-routing.rego，package dga.pool）

输入 `{task:{sensitivity}, endpoint:{trust_label, tos_risk}}`；`tos_risk` 由路由器从端点绑定
账号集合聚合（任一 grey-zone/high-risk ⇒ 端点按灰区处理）。

| # | sensitivity | trust_label | tos_risk | allow | deny_reasons |
|---|---|---|---|---|---|
| 1 | public | T0 | clear | true | — |
| 2 | internal | T0 | clear | false | R-POOL-TRUST |
| 3 | internal | T1 | clear | true | — |
| 4 | customer_sensitive | T0 | clear | false | **R-POOL-DATA**+R-POOL-TRUST（红线显名，3.3） |
| 5 | customer_sensitive | T1 | clear | false | R-POOL-TRUST |
| 6 | customer_sensitive | T2 | clear | true | — |
| 7 | internal | T0 | grey-zone | false | R-POOL-COMPLIANCE+R-POOL-TRUST |
| 8 | internal | T1 | grey-zone | false | 仅 R-POOL-COMPLIANCE（灰区规则独立于信任级，即使误标 T1 也拦） |
| 9 | public | T0 | grey-zone | true | —（灰区只禁非公开任务） |
| 10 | 非法枚举 | — | — | false | R-POOL-INPUT-INVALID（未知值拒绝，不默认放行） |

查询面：`POST /v1/data/dga/pool/allow`、`/deny_reasons`、`/decision`。
加载方式：OPA 1.20.2 多文件/目录参数——`services/opa/start.sh` 追加 `policies/` 目录
（最小改动已登记）。v0 不实现 3.3"合同显式允许+已脱敏"例外（无合同/脱敏证据对象，缺口 §遗留）。

## 3. 路由器（route_check.py）

```bash
D:/Projects/dga-infra/.venv/Scripts/python.exe \
  D:/Projects/dga-infra/gov-infra-repo/pools/route_check.py \
  --task-id T-0001 --sensitivity public   # internal | customer_sensitive
```

流程：psql 查池表候选（trust 升序→成本层级升序=满足策略的最便宜可信端点优先）→ 逐个
POST OPA `/v1/data/dga/pool/allow` → 首个 allow 即 routed；不可用端点跳过（3.5 故障转移）。

裁决语义：`routed` / `denied`（所有候选均被策略拒绝——红线不排队，排队不改变策略判定，
输出合并 deny_reasons 作 POLICY_DECISION 证据原料）/ `queued`（存在可承接的候选但全部
不可用或账本不可达——3.5 队列等待，超决断时距挂起 MET-01）。任务书"全败返回 queued"按
策略性/可用性两种全败细化，理由如上；退出码 routed=0 否则 2。`--mark-unhealthy <端点名>`
可在本进程内模拟健康下线（不写账本），演示 queued 路径。

## 4. LiteLLM Proxy（SEL-05 推荐形态 A：OSS 单实例+PG，无 Redis）

- `model_list`：mock-free / mock-paid（`mock_response` 短路——安装版 1.100.0 `main.py` L475
  实证支持；`api_key` 为本机占位非凭据）；自定义 `input/output_cost_per_token`（mock 无官方
  价目，显式定价使 spend 可算——R-POL-03 预算执法与 R-POOL-QUOTA 校准的前提）。
- `general_settings.master_key: os.environ/DGA_LITELLM_MASTER_KEY`（启动脚本 export
  `sk-dga-local-dev`，**本机占位非凭据**）。
- `general_settings.database_url: postgresql://dga@localhost:5432/dga_litellm`
  （1.100.0 实测该键必须在 general_settings 下，顶层不生效——首次踩坑已登记）。
- `litellm_settings`：max_budget 100.0/30d（占位）、default_fallbacks [mock-free]（v0 mock
  拓扑演示链，非 degradation.yaml 定义）、num_retries=2。
- 状态库依赖：`prisma` Python 包需显式安装（litellm[proxy] 1.100.0 未带，缺它则
  /key/generate 500 "DB not connected"——已登记）。

## TOS 风险矩阵 v0（3.4）

| Provider | 多账号条款 | 免费层用途限制 | 数据使用条款 | 定级结论 |
|---|---|---|---|---|
| mock-freelayer | 灰区（ACC-0003 复现多账号条款未明确场景） | 模拟存在 | 模拟"可能用于训练" | 账号一律 T0；灰区仅灰区隔离端点+负面测试 |
| mock-paidlayer | clear（模拟） | — | 模拟"数据不用途+SLA" | T1 |

灰区可否使用由 S5 裁决；agent 发现灰区即升级，不得自行判定（3.4）。

## 遗留缺口（登记）

1. credential_ref 指向的 OpenBao secret 未落库（dev inmem 重启即清空）——M3+ 凭据管道接线后回填。
2. 降级链 step2/3（t1-backup、low-cost-paid）NOT_PROVISIONED——账本无第二 T1 端点。
3. 3.3 例外路径（合同显式允许+脱敏至证据级）未实现——需 Authorization/Evidence 对象先行（M4+）。
4. 具名责任人（PSN-xxxx）待本体轨道登记后回填 accountable_person。
5. max_data_sensitivity 与 OPA 谓词的一致性靠种子纪律维持，无 DB 约束联动 OPA（谓词强制在 OPA 层，M0 诚实边界）。
6. T2 端点 v0 无实例（enterprise 层未接入），customer_sensitive 路由在 v0 拓扑下必然 denied——符合设计（宁可拒绝不降级红线）。
