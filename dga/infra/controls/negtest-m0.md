# negtest-m0 — M0 验收负面测试报告

- doc-id: negtest-m0
- date: 2026-09-06
- 轨道: DGA-INFRA 本体论轨道（M0：对象模型/ID/权威源定稿 + LinkML 声明层落地）
- 依据: DGA-INFRA v1.0 第 7 章（负面测试优先——测坏情况，不测正常流程）、R-GOV-03、R-POOL-TRUST/DATA；DGA-human v1.1 §2.1（六元组）、§5.8（单向信息梯度）
- 被测对象: `schemas/generated/dga-ontology.schema.json`（由 `schemas/dga-ontology.yaml` 生成）
- 工具: jsonschema 4.26.0（Draft 2020-12，closed world）
- 可复跑: `D:/Projects/dga-infra/.venv/Scripts/python.exe controls/negtest_m0.py`（退出码 0=全部符合预期）

## 案例设计

| # | 案例 | 锚点 | 预期 |
|---|---|---|---|
| 0 | 阳性对照：六元组齐备的 ClosureUnit | R-GOV-02 | 通过 |
| 1 | 缺 `accountability` 的 ClosureUnit | **R-GOV-03**（新闭环缺具名责任人 ⇒ 拒绝生产执行资格） | **必须失败** |
| 2 | `trust_label=T0` 的 PoolAccount 承接 `sensitivity=客户敏感` 的路由判定 | R-POOL-DATA / R-POOL-TRUST | **纯 schema 无法表达拒绝 → 诚实边界登记**：schema 只保证字段在位（通过），不等式谓词属 OPA 层 |
| 3 | `trust_label=T9`（枚举外值） | 枚举封闭性（TrustLevel=T0/T1/T2） | **必须失败** |

## 实际命令输出（2026-09-06 运行，逐字贴入）

```
$ D:/Projects/dga-infra/.venv/Scripts/python.exe controls/negtest_m0.py
[PASS] 案例0 阳性对照：六元组齐备的 ClosureUnit（预期：通过）
       0 个错误
[PASS] 案例1 缺 accountability 的 ClosureUnit（R-GOV-03）（预期：校验失败）
       拒绝理由：'accountability' is a required property
       诚实边界声明：任务 sensitivity(S2_客户敏感) ≤ 端点 trust(T0) 的不等式
       是跨对象谓词，JSON Schema（单实例结构校验）无法表达其拒绝；schema 保证
       trust_label / max_data_sensitivity / trust_level 字段在位且取值合法，拒绝动作
       由 OPA 策略强制（policies/routing.rego，M4 验收：越权路由被真实拒绝）。
[PASS] 案例2 T0 账号 × 客户敏感路由：字段在位校验（诚实边界）（预期：通过（字段在位）+ 登记 OPA 边界）
       三个对象全部通过 schema 校验（0 个错误）——证明字段在位；不等式谓词登记为 OPA 层职责
[PASS] 案例3 trust_label=T9（枚举外值）（预期：校验失败）
       拒绝理由（path=['trust_label']）：'T9' is not one of ['T0', 'T1', 'T2']

jsonschema 版本：4.26.0
schema 文件：D:\Projects\dga-infra\gov-infra-repo\schemas\generated\dga-ontology.schema.json
结论：全部案例行为符合预期 —— M0 负面测试通过
（退出码 0）
```

注：结果行的 `[PASS]` 表示"案例行为符合设计预期"——对案例 1/3 而言，符合预期即**实例校验被拒绝**（拒绝理由已在输出中逐字给出）。

## 诚实边界登记（案例 2，不做能力夸大）

**登记内容**：路由规则"任务 sensitivity ≤ 端点 trust"（DGA-INFRA 3.2）是一个**跨对象、跨实例的不等式谓词**。JSON Schema（以及 LinkML 声明层）只能保证：

1. 端点侧字段在位且取值合法：`LogicalEndpoint.trust_level ∈ {T0,T1,T2}`；
2. 账号侧字段在位且取值合法：`PoolAccount.trust_label ∈ {T0,T1,T2}`；
3. 策略侧字段在位且取值合法：`RoutingPolicy.max_data_sensitivity ∈ {S0_公开,S1_内部,S2_客户敏感}`。

它**不能**表达"引用了 T0 端点的路由不得承接 S2 任务"这一跨实体约束——该谓词属于 **OPA 策略层**（DGA-INFRA CMP-03，策略与执行点分离；R-POL-01：权限检查在服务端强制执行，"模型被告知不能做"不算权限控制）。这与 human v1.1 §5.10 的理论/实例分层判据一致：谓词的执行语义属运行时治理，schema 只承诺"词汇表"（§5.2 推导二：本体论是治理语言的词汇表）。

**OPA 层谓词草案**（策略进 Git，bundle 分发；真实强制在 M4 验收——"敏感任务被 T0 端点拒绝"）：

```rego
# policies/routing.rego（草案，M0 仅登记谓词语义）
deny_routing if {
  input.task.sensitivity_rank > input.endpoint.trust_rank   # sensitivity ≤ trust
}
# 数据红线（R-POOL-DATA，硬红线）：
deny_routing if {
  input.task.data_class == "D_CUSTOMER_SENSITIVE"
  input.endpoint.trust_label == "T0"
}
```

**不诚实声明（显式否认）**：本 M0 schema **不**声称"T0 端点会拒绝敏感任务"。该保证的验收在 M2（T0/T1 标签生效）与 M4（越权调用被真实拒绝，非提示词级）。

## 附：schema 侧的对应锚点（抽查记录）

- `ClosureUnit.required = ["id", "accountability"]`（JSON Schema `$defs.ClosureUnit`）
- `AccountabilityLink.required = ["id", "closure", "responsible_person"]`，且 `responsible_person` 类型为 Person 引用——类型系统层面排除 agent 充当责任锚点（责任守恒律，human v1.1 §1.4）
- `TrustLevel.enum = ["T0","T1","T2"]`
- SQL DDL（`schemas/generated/dga-ontology.sql`）对应行：`ClosureUnit` 表内 `accountability_id TEXT NOT NULL` + `FOREIGN KEY(accountability_id) REFERENCES "AccountabilityLink" (id)`——R-GOV-03 约束在关系投影中同样不可空

## 结论

四案例全部按预期行为，M0 负面测试通过；案例 2 的诚实边界已登记，路由谓词强制责权归 OPA 层（M4 验收），本 schema 承诺止于"字段在位 + 取值合法 + accountability 必填"。
