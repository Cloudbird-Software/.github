# 组织语言生态政策（agent 按需读取）

> 本文件是组织级政策，不放在任何仓库的 AGENTS.md 里（惜上下文）。
> agent 在以下场景必须读它：新建项目、新增模块选型、引入新依赖、写架构文档。
> 违规 = gate 拦截或 PR 打回。最后更新: 2026-08。

## 分层选型

| 层 | 允许 | 禁止 | 为什么（选型理由） |
|---|---|---|---|
| 主力应用/服务 | Go（服务/CLI 优先）；受约束的 TypeScript（需要前端同构时） | Rust/Java/C++/新语言 | 训练数据海量、写法单一、编译反馈快——LLM 产出可靠 |
| LLM/Prompt 层 | BAML + Python | 裸 prompt 字符串拼接 | BAML 是"深接口"的教科书实现：prompt 即类型化契约 |
| 数据层 | SQL + 类型生成（如 sqlc / kysely） | 重 ORM（Prisma/Hibernate 类） | SQL 是史上最成功的深接口 DSL；重 ORM 挡住 agent 对生成的控制 |
| 配置/基建 | 声明式（Terraform / Compose） | 脚本化基建（bash 造 infra） | 无逻辑 = AI 不会写错 |
| 验证层 | property-based test（fast-check/proptest）+ schema 契约 + dependency-cruiser 依赖规则 | 只写 happy-path 单测 | 这是组织的真正护城河 |

## 每层的硬性要求

1. **Go**：`gofmt` 零 diff；错误必须显式处理（`errcheck` 进 gate）；模块入口 `cmd/`，包间禁止循环依赖。
2. **TypeScript**：`strict: true`；禁止 `any`（eslint 进 gate）；跨模块只 import 入口 `index.ts`（depcruise 检查）。
3. **BAML**：prompt 改动必须跑 golden test（输入→输出快照）；禁止在 TS/Go 里内嵌 prompt 字符串。
4. **SQL**：迁移文件只增不改（up + down）；查询经类型生成器，禁止手写拼接。
5. **Terraform/Compose**：`plan`/`config -q` 进 CI；禁止 `local` 值参与资源命名。
6. **验证层**：对外接口必须有 property-based test；`.dependency-cruiser.cjs` 的 TODO 边界规则在模块落地当周补全。

## 新仓库初始化（agent 必须遵循）

```
gh repo create Cloudbird-Software/<name> --template Cloudbird-Software/template-service --public --clone
cd <name> && bash <(curl -sS https://raw.githubusercontent.com/Cloudbird-Software/.github/main/scripts/new-repo-init.sh) <name>
```

然后第一个 PR：按本层表选型填 `.dependency-cruiser.cjs` 的 TODO 规则 + 建模块 AGENTS.md。
语言一旦选定，中途换语言 = 重新立项，不是重构。

## 违规处理

- gate 拦住的（lint/depcruise/类型）→ agent 自行修复，不许绕过
- gate 拦不住的（选型违规、引入 ORM）→ PR 打回，理由引用本文件对应行
