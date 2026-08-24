# Cloudbird Software

一人软件公司，AI Agent 驱动开发。所有仓库公开，质量与安全靠制度 + 自动化门禁，不靠人盯。

**运行范式（ADR-0085）**：强模型 = 项目经理（PM），公司只规定四道阶段门禁——IR→spec → spec 过红队→开卡 → 卡完成+全 gate 绿 → IR 全面验收；门禁之间怎么干由 PM 自主。常规实现默认派 CNB 免费算力池，PM 处理上升问题。PM 入口：[.github 仓 AGENTS.md](https://github.com/Cloudbird-Software/.github/blob/main/AGENTS.md) + [PM Playbook](https://github.com/Cloudbird-Software/.github/blob/main/docs/pm/PLAYBOOK.md)。每次 run 的经验沉淀在 [archive/runs](https://github.com/Cloudbird-Software/archive/tree/main/runs)（周度 digest 消费）。

## 我们的工程制度

- 每个仓库唯一的必需 check 是 **`gate`**：聚合 hygiene（密钥/大文件扫描）+ `make check`（lint + test）+ 依赖审查。
- 所有 CI 逻辑集中在 [CI-Workflows](https://github.com/Cloudbird-Software/CI-Workflows)，业务仓只引用 `@v1`，一份维护、全部复用。
- 新项目从 [template-service](https://github.com/Cloudbird-Software/template-service) 一键创建，自动继承全部护栏。
- 组织级开启：CodeQL default setup、Secret scanning + Push protection、Dependabot 安全更新与自动合并。
- AI 与人的行为契约见各仓库 `AGENTS.md`：提交前 `make check` 必须全绿。

## 仓库

组织地图（结构层导航的唯一真源）：[governance/REPOS.yaml](../governance/REPOS.yaml)

| 仓库 | 层 | 用途 |
|---|---|---|
| [.github](https://github.com/Cloudbird-Software/.github) | L0 | 治理总仓：GOVERNANCE / 标准 schema / 漂移检测 |
| [CI-Workflows](https://github.com/Cloudbird-Software/CI-Workflows) | L0 | 可复用工作流（唯一真相源） |
| [agent-registry](https://github.com/Cloudbird-Software/agent-registry) | L1 | agent/skill/tool/team 声明 + 模型注册表 + ADR（私有） |
| [template-service](https://github.com/Cloudbird-Software/template-service) | L2 | 新项目模板 |
| [AI_Web_School](https://github.com/Cloudbird-Software/AI_Web_School) | L2 | 产品仓库 |

## 自治流水线（W0）

组织已具备意图→规格的无人值守链路：用意图表单提交 IR，owner 打 `state:ir-signed` 后，conductor（状态机）自动调用 spec-author 起草条款级规格并开出 spec PR，全程计量落盘。规格与波次计划见 [`specs/IR-0001/`](../specs/IR-0001/)。
