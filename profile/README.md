# Cloudbird Software

一人软件公司，AI Agent 驱动开发。所有仓库公开，质量与安全靠制度 + 自动化门禁，不靠人盯。

**运行范式（ADR-0085）**：强模型 = 项目经理（PM），公司只规定四道阶段门禁——IR→spec → spec 过红队→开卡 → 卡完成+全 gate 绿 → IR 全面验收；门禁之间怎么干由 PM 自主。常规实现默认派 CNB 免费算力池，PM 处理上升问题。PM 入口：[.github 仓 AGENTS.md](https://github.com/Cloudbird-Software/.github/blob/main/AGENTS.md) + [PM Playbook](https://github.com/Cloudbird-Software/.github/blob/main/docs/pm/PLAYBOOK.md)。每次 run 的经验沉淀在 [archive/runs](https://github.com/Cloudbird-Software/archive/tree/main/runs)（周度 digest 消费）。

**任何入口进来先读**：[全入口路由表 NAVIGATION.md](https://github.com/Cloudbird-Software/.github/blob/main/docs/NAVIGATION.md)——入口矩阵 + 高频困惑 FAQ（spec 放哪 / 治理变更要不要开卡 / g060 拦截怎么办等，#362 审计收口）。

## 我们的工程制度

- 每个仓库唯一的必需 check 是 **`gate`**：聚合 hygiene（密钥/大文件扫描）+ `make check`（lint + test）+ 依赖审查。
- 所有 CI 逻辑集中在 [CI-Workflows](https://github.com/Cloudbird-Software/CI-Workflows)，业务仓只引用 `@v1`，一份维护、全部复用。
- 新项目从 [template-service](https://github.com/Cloudbird-Software/template-service) 一键创建，自动继承全部护栏。
- 组织级开启：CodeQL default setup、Secret scanning + Push protection、Dependabot 安全更新与自动合并。
- AI 与人的行为契约见各仓库 `AGENTS.md`：提交前 `make check` 必须全绿。

## 仓库

组织地图（结构层导航的唯一真源）：[governance/REPOS.yaml](https://github.com/Cloudbird-Software/.github/blob/main/governance/REPOS.yaml)

| 仓库 | 层 | 用途 |
|---|---|---|
| [.github](https://github.com/Cloudbird-Software/.github) | L0 | 治理总仓：GOVERNANCE / 标准 schema / 漂移检测 / 全入口路由 |
| [CI-Workflows](https://github.com/Cloudbird-Software/CI-Workflows) | L0 | 可复用工作流（唯一真相源）+ bug 复现/红队执行层 |
| [archive](https://github.com/Cloudbird-Software/archive) | L1 | 记忆层：ADR 家园（正本+INDEX）+ PM 运行报告 runs/ + 退役快照 |
| [holdout](https://github.com/Cloudbird-Software/holdout) | L1 | 试卷层：封存验收场景（owner 直管，agent 只读） |
| [template-service](https://github.com/Cloudbird-Software/template-service) | L2 | 新项目模板（入口协议块下发真源） |
| [arbiter](https://github.com/Cloudbird-Software/arbiter) | L2 | 仲裁内核：确定性裁决 / CAS 租约（无 LLM） |
| [cnb-bridge](https://github.com/Cloudbird-Software/cnb-bridge) | L2 | CNB 免费算力桥接（可删除层，ADR-0085） |
| 产品仓（AI_Web_School / mutual / QW_Arena1 / Shorts_Director / Script_Writer / Use-up-Plan） | L2 | 业务实现——全量与状态见 REPOS.yaml |

## 意图→交付链路

- **Feature 流（签署前置）**：[intent 表单](https://github.com/Cloudbird-Software/.github/issues/new?template=intent.yml)提交 IR → owner 签署 → spec（PM 自著或 spec-author 快速通道）→ 红队审计 → 开卡 → 实现（CNB 默认）→ 验收。规格与波次计划见 [`specs/`](https://github.com/Cloudbird-Software/.github/tree/main/specs)。
- **Bug 流（复现前置，签署点后移——ADR-0064）**：[bug 表单](https://github.com/Cloudbird-Software/.github/issues/new?template=bug.yml)提交即机器复现，三值判定（reproduced / cannot-reproduce / inconclusive），reproduced 后修复合入自动回写状态。
