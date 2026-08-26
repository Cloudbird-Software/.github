# ROLE-IR —— 开 IR（意图受理角色）

> 你带着一个新意图落地（想加 feature / 改产品行为），本文件是你的完整指引。
> 依据：ADR-0095（IR 挂靠产品仓）/ ADR-0085（PM 优先四道门禁）/ IFACE-01（IR schema）。
> 全流程总览见 [NAVIGATION.md](../NAVIGATION.md)；PM 深度手册见 [PLAYBOOK.md](../pm/PLAYBOOK.md)。

## 一句话

**IR 只是一个 issue**：开在对应的产品仓上，填全字段，等 owner 签署。不需要任何 PR。

## 开在哪

- **产品/feature 意图** → 开在**对应的产品仓**（如 `Cloudbird-Software/<产品仓>`）。
  issue 模板 `intent.yml` 经 org 级 `.github/ISSUE_TEMPLATE` 自动被 org 内全部仓继承——
  在产品仓 New issue 即可选用；若模板/`type:intent` 标签在本仓缺失，属治理漂移，
  报 owner（apply.sh §7 同步治理标签），不要手工绕过。
- **治理意图**（改治理面：governance/ 政策、门禁、流程本身）→ 开在 `.github` 治理仓。
- 历史先例：`Viral_Radar#1`（产品仓 IR）。废止的旧规定「IR 一律在 .github 仓开」
  已由 ADR-0095 移除——不要把 feature IR 开到治理仓。

## 怎么开（九字段全必填，IFACE-01）

1. **编号**：标题以 `IR-NNNN` 前缀开头，编号全局唯一——开立前用
   `bash ghcb board`（各活跃仓轮查）核对已用编号，避免撞号。机器侧（conductor /
   ghcb）从标题提取编号；无前缀时会退化为 issue 号兜底，勿依赖兜底。
2. **字段**：intent.yml 模板九项全部必填——job / 触发场景 / 痛点证据 /
   期望可观察变化 / 非目标 / 约束 / 验收证据 / 可逆性偏好 / 质量速度旋钮。
   「期望可观察变化」是将来验收（ROLE-ACCEPT）的对账基准，写成可观察、可回查的
   事实，不写实现方案。
3. **标签**：`type:intent`（模板自动带）。

## 签署（不是你的动作）

- owner 评论 `/start` 或打 `state:ir-signed` ——**只有 owner 能签，你不代签**。
- 机器面（ADR-0097）：conductor 事件面已覆盖全部活跃仓（.github + 8 产品仓 +
  template-service，同字节部署）——owner 在 IR 所在仓评论/打标签即自动换签，
  产品仓无需手动干预。

## 开完之后

- IR 是 append-only 意图账本：签署后只追加评论/erratum，**不编辑正文**。
- 签署后的下一步是 **spec**——指引换到 [ROLE-SPEC.md](ROLE-SPEC.md)。
- **开 IR 的 agent 不得直接实现**：从意图到代码必须经 spec PR + 红队 + 开卡
  四道门禁（ADR-0085）；跳门直做=违约。

## 红线速查

- 不代签、不撞号、不改别人 IR 正文、不开 PR（IR 阶段无 PR 面）。
- 治理意图 IR 若涉及决策变更，后续 spec PR 需引用 ADR（见 ROLE-SPEC.md）。
