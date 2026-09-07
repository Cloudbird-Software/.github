# negtest-m1 · 控制面负面测试（负面优先，M1 验收件）

- 日期：2026-09-06/07（本机建设当夜批次）| 轨道：控制面 M1
- 被测：DGA 控制面 v0 @ http://127.0.0.1:8090（FastAPI，见 `catalog/sel/SEL-01.md`）
- 依据：DGA-INFRA 第 5 章 R-GOV-03（缺具名责任人拒绝创建）/ R-GOV-04（S5 决策卡片固定结构）
  / R-SEC-04（签发不可代）；里程碑 M1 验收要点"缺责任人的闭环被拒绝创建"
- 复跑：`bash controls/negtest_m1.sh`（前置：`services/scripts/start-control-plane.sh`；
  幂等 seed 主数据，行数断言用相对值，重复跑全绿、退出码 0——本文件写作时已连跑两遍）
- 双层校验声明：accountability 的拒绝在 API 层（pydantic required → 422）与 DB 层
  （`ClosureUnit.accountability_id TEXT NOT NULL + FK→AccountabilityLink`）各自成立；
  案例①实测 API 层拒绝并核查 DB 行数不变，DB 层 NOT NULL 由 DDL（`\d "ClosureUnit"`）与
  `catalog/sel/SEL-01-ddl-patch.sql` 背书。

## 结果总览

| 案例 | 断言 | 实测 | 结果 |
|---|---|---|---|
| ① 缺 accountability 的 closure | HTTP 422 且 DB 无新增行 | 422，行数 1→1 | PASS |
| ② 决策卡缺任一必填字段（7 例逐字段） | HTTP 422 | 7/7 = 422 | PASS |
| ③ resolve 错人 / 缺 X-S5-Person 头 | HTTP 403，卡片保持 pending | 403 + 403 + pending | PASS |
| ④ 阳性对照：合法闭环 | 201 + GET 200 + DB +1 | 201/200，1→2 | PASS |

## 案例①：缺 accountability 的 closure → 422 且 DB 无行

请求体（六元组其余分量齐全，唯独去掉 accountability）：

```bash
$ curl -s -X POST http://127.0.0.1:8090/closures -H "Content-Type: application/json" -d '{
  "intent_id":"INT-0001","capability_id":"CAP-0001","context_asset_id":"CTX-0001",
  "action_type_ids":["ACT-0001"],"evidence_ids":["EVD-0001"],
  "state":"DRAFT","decision_timespan":"PT8H"}'
```

实际响应（HTTP 422，pydantic 指明 `body.accountability` Field required）：

```json
{"detail":[{"type":"missing","loc":["body","accountability"],"msg":"Field required","input":{"intent_id":"INT-0001","capability_id":"CAP-0001","context_asset_id":"CTX-0001","action_type_ids":["ACT-0001"],"evidence_ids":["EVD-0001"],"state":"DRAFT","decision_timespan":"PT8H"}}]}
```

DB 侧证据（请求前后 `SELECT count(*) FROM "ClosureUnit"`）：`1 → 1`，无行落库。
脚本 PASS 行：`PASS: 案例① HTTP 422 且 ClosureUnit 行数不变（1 → 1）`

## 案例②：决策卡缺任一必填字段 → 422

必填集合 = R-GOV-04 六字段（object/evidence/options/recommendation/deadline/consequences）
+ addressee（R-SEC-04 校验所需；任务书称"七字段"而清单列六项，差异即 addressee，
逐字段登记不靠猜）。逐次去掉一个字段重发：

```
缺 [object] → HTTP 422
缺 [evidence] → HTTP 422
缺 [options] → HTTP 422
缺 [recommendation] → HTTP 422
缺 [deadline] → HTTP 422
缺 [consequences] → HTTP 422
缺 [addressee] → HTTP 422
```

实际响应样例（缺 deadline）：

```json
{"detail":[{"type":"missing","loc":["body","deadline"],"msg":"Field required","input":{...}}]}
```

## 案例③：resolve 时 X-S5-Person 错人 → 403

先经 `POST /decisions` 建立合法待裁决卡片 `DC-0002`（addressee=PSN-0001），然后：

```bash
$ curl -s -X POST http://127.0.0.1:8090/decisions/DC-0002/resolve \
    -H "Content-Type: application/json" -H "X-S5-Person: PSN-0002" \
    -d '{"decision":"approved","decided_by":"PSN-0002"}'
```

实际响应（HTTP 403，R-SEC-04 代签防护）：

```json
{"detail":"X-S5-Person='PSN-0002' 不是该卡片的 addressee（'PSN-0001'），拒绝代签"}
```

追加变体：完全不带 `X-S5-Person` 头 → HTTP 403（`缺少 X-S5-Person 头（R-SEC-04：签发不可代）`）。
DB 侧证据：两张请求后卡片 `decided_by IS NULL`（保持 pending，未发生任何裁决写入）。
对照：`X-S5-Person: PSN-0001`（= addressee = decided_by）→ HTTP 200
`{"id":"DC-0002","state":"resolved","decision":"approved","decided_by":"PSN-0001"}`；
重复 resolve → HTTP 409（防旧批准重放，R-SEC-04 同族）。

## 案例④：阳性对照——合法闭环登记成功且可查询

```bash
$ curl -s -X POST http://127.0.0.1:8090/closures -H "Content-Type: application/json" -d '{
  "intent_id":"INT-0001","capability_id":"CAP-0001","context_asset_id":"CTX-0001",
  "action_type_ids":["ACT-0001"],"evidence_ids":["EVD-0001"],
  "accountability":{"responsible_person_id":"PSN-0001","role":"ACCOUNTABLE"},
  "state":"REGISTERED","decision_timespan":"P1D","name":"negtest④ 合法闭环",
  "trust_level":"T1","data_class":"D_内部","boundary":"company-cloud"}'
```

实际响应（HTTP 201）：

```json
{"id":"CU-0002","accountability_link_id":"ALK-0002","state":"REGISTERED"}
```

```bash
$ curl -s http://127.0.0.1:8090/closures/CU-0002   # → HTTP 200
{"id":"CU-0002","name":"negtest④ 合法闭环","created_at":"2026-09-07T00:46:37.892516",
 "capability":"CAP-0001","state":"REGISTERED","decision_timespan":"P1D",
 "trust_level":"T1","data_class":"D_内部","boundary":"company-cloud",
 "intent_id":"INT-0001","accountability_id":"ALK-0002",
 "accountability_responsible_person_id":"PSN-0001","accountability_role":"ACCOUNTABLE",
 "accountability_responsible_person_name":"S5（公司所有者）",
 "context_asset_ids":["CTX-0001"],"action_type_ids":["ACT-0001"],"evidence_ids":["EVD-0001"],...}
```

DB 侧证据：`ClosureUnit` 行数 `1 → 2`（第二轮复跑 `2 → 3`，CU-0003，同绿）。
本案例同时验证了 `ClosureUnit ↔ AccountabilityLink` 环插（两条 DEFERRABLE FK 同事务
COMMIT 校验，见 `catalog/sel/SEL-01-ddl-patch.sql` [F1]/[F2]）。

## 脚本退出码

```
== 结果：PASS=10 FAIL=0 ==
negtest-m1: ALL GREEN     # exit 0（连续两轮）
```
