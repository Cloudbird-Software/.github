# ROLE-SPEC —— 把已签署的 IR 写成 spec（spec 撰写角色）

> 触发条件：一条 `state:ir-signed` 的 IR 在你手上。本文件是你的完整指引。
> 依据：ADR-0095（测试设计逐类讨论 + holdout 必备）/ ADR-0085 / ADR-0082（红队守门）/
> ADR-0083（suite 门）/ ADR-0061/0081（g060 测试锁定）/ ADR-0056/0080（holdout）。
> 阶段深度手册：[PLAYBOOK.md](../pm/PLAYBOOK.md) §2–§3。

## 一句话

从 IR 到 spec **必须走 spec PR 流程**：spec 文档 + 测试设计（逐类讨论，含 holdout）
+ 红队审计，全部过了才能开卡。**你（spec agent）不得直接实现**——实现是
[ROLE-IMPLEMENT.md](ROLE-IMPLEMENT.md) 的职责，spec PR 合并不等于开工许可。

## spec 放哪

- **产品 feature**：产品仓本仓 `specs/<IR-NNNN>/`（IR 也开在该仓，ADR-0095）。
- **治理意图**：`.github` 仓 `specs/IR-XXXX/`。
- 模板：CI-Workflows `pipeline/spec-template.md`（正文条款结构 / AC given-when-then /
  INV-BEH-IFACE 分节）。可选快速通道：spec-author 流水线生成骨架你再修
  （与自著制度等价，ADR-0085 决策 5）。

## spec PR 必带（缺一即红）

1. **spec 正文**：AC 从 IR「期望的可观察变化」逐条派生，given-when-then。
2. **suite/ 目录**：至少一个非空、可解析、含有效断言的测试文件
   （T-14 / T5 谓词现场重查）。注意 `specs/*/suite/**` 在 g060 锁定集内——你的
   suite 变更会被 g060 拦下（exit 2）并自动开裁决 issue，owner 以
   `/g060-adopt <证据>` 采纳（TTL 72h）。**这不是故障，是设计**；首次创建 suite
   同样走此路径，无豁免通道。
3. **测试设计逐类讨论（ADR-0095，spec 的一等公民）**：spec 必须含「测试设计」节，
   对 [testing.yaml](../../governance/policy/testing.yaml) 的清单**逐类过一遍**，
   每类明确 adopt 或 reject 并给一句理由（讨论留痕，供红队攻击）：
   - **active_now**：T-01 属性（unit_property_golden）/ T-02 race / T-03 泄漏 /
     T-04 模糊（fuzz）/ T-05 文档示例 / T-08 flaky / **T-09 差分**（重写项目=gate
     必选）/ T-10 变异 / T-12 diff 覆盖 / T-13 测试完整性 / T-14 卡绑定+suite 门 / T-15 意图回探
   - **条件激活族**：LLM 产品族 L-01..L-06（eval / semantic golden / **L-03 蜕变** /
     对抗语料 / 成本时延 / 换模型差分）；重写项目族 R-01..R-06（升级/回滚/迁移幂等/
     抓 golden）；触发式族 G-01..G-08（契约漂移/真实依赖集成/bench/DAST…）
   - **rejected 清单**（X-01..X-06，如全局覆盖率门槛）不许私自启用——要启用先走治理变更（ADR）
   - 判断口径：每个测试必须映射三类风险之一（customer_upgrade_failure /
     llm_behavior_drift / fake_tests）；「不需要」也要写明为什么不需要。
4. **holdout 测试设计（必备，ADR-0095）**：spec 必须包含 holdout 测试设计——
   封存验收场景条目，经验证者 APP 注册到 holdout 仓（注册入口
   `scripts/holdout-register.sh`，由 verifier-app 令牌调用；**cloudbrid-agent 严禁
   挂载 holdout**，DECISION-02 隔离不变量）。spec/卡/PR 对 holdout 只能引用
   `id@sha8`（如 `HO-0001@a1b2c3d4`），**禁止引用 payload 内容**（=提前泄题）。
5. **红队审计**：spec/测试设计路径 PR 必须经红队（ADR-0082）——required check
   `adversary`，`verdict=survived` 才绿，漏配/摘除/跳过即红。**红队会攻击你的
   测试设置是否合理**：恶意合规（写一套故意弱的 AC 套件骗过全部测试）、模板句
   复用（then 两两 4-gram 查重）、given/when 深度不足、测试种类该开没开
   （差分/属性/模糊/蜕变缺位即 insufficient）。红队判 insufficient = 阻断，
   修测试设计后重审计。
6. **C1 面**：spec PR 引用 ADR-NNNN（新决策=新写 ADR 至 archive，先合并；
   执行性变更=引既有 ADR），owner-only review。

## 流程位置

```
IR（state:ir-signed，开在产品仓）
  └─ spec PR（本文档：正文 + suite + 测试设计逐类讨论 + holdout 设计）
       └─ 红队 survived（adversary check + adversary:survived 标签 → T6）
            └─ 开卡（AC 逐条派生，type:card + state:ready）
                 └─ 交给 ROLE-IMPLEMENT.md（你到此为止）
```

## 边界（再次强调）

- **不得直接实现**：spec PR 合并 ≠ 开工许可。开卡后实现由实现角色（PM）承担——
  通常先派弱模型（子 agent / CNB 池），见 ROLE-IMPLEMENT.md。
- 你可以同时是下一角色的 PM（同一 agent 换角色），但必须**显式换帽子**：先收口
  spec 门禁，再按实现角色指引开工。
