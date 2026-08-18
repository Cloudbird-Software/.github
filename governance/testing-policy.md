# 组织测试政策（决策记录 2026-08）

> 加法穷举 + 减法裁决的完整记录。想引入新测试时先读本文件：已否决的有否决理由，待定的有触发条件。
> 原则：gate 快（PR <5 分钟）重的周跑；每个测试必须对应一个真实风险敞口。

## 三大风险敞口（裁决的排序依据）

1. **客户升级炸**：产品是客户本地部署（Release 附件交付），升级/回滚/迁移是收入保护
2. **LLM 行为悄悄变差**：产品核心是 LLM，无 eval 即盲飞
3. **agent 写的测试演戏**：同义反复测试比没测试更危险（mutation score 是照妖镜）

## 立即生效（gate，近零成本）

| 测试 | 工具/手法 | 说明 |
|---|---|---|
| 竞态检测 | `go test -race` | Go 并发 bug 最难排查，检测器免费 |
| goroutine 泄漏 | uber-go/goleak | 服务类项目一个 import |
| Fuzz 种子 | `go test -fuzz`（短跑）+ 周 cron 深跑 | 解析器/导入器/协议处理必备；语料入库 |
| 文档即测试 | Go Example 函数 | 文档代码段进 CI，防文档腐烂 |
| 许可证扫描 | license-checker | 政策（禁 AGPL/GPL-3/SSPL）自动化 |
| SBOM | syft 附 Release | 已有 provenance attestation，补齐供应链 |
| Flaky 治理 | 流程规则 | 重跑一次过≠通过；两次飘=隔离+issue，修好才回 |

## 重写项目落地时生效（release 前置）

| 测试 | 说明 |
|---|---|
| 升级路径测试 | 旧版本→新版本真机升级+smoke（客户模拟） |
| 回滚测试 | 升级后回滚，数据无损 |
| 迁移测试 | up+down 在真实数据快照上，幂等验证 |
| 配置兼容 | 旧版配置文件喂新版二进制，行为可预期 |
| 全新安装 smoke | 干净环境装 Release 附件，模拟客户第一天 |

## LLM 输出进产品时生效

| 测试 | 放哪 | 说明 |
|---|---|---|
| Eval harness（promptfoo 类） | 小回归集进 gate，全量周跑 | prompt/模型变更必须过 |
| 语义 golden | gate | embedding 距离阈值判漂移，不做精确 diff |
| 蜕变测试 | gate | LLM 无 oracle：输入重排结果集等价、重试幂等 |
| 对抗语料库 | 周跑 | 注入/越狱样本，LLM 产品的安全测试 |
| 成本/延迟预算 | 周跑趋势 | token 成本+p95 延迟回归报警 |
| 模型升级差分 | 变更时 | 换模型=换实现，同 golden 集对比 |

## 触发式（写明触发器，防止"听起来好就上"）

| 测试 | 触发器 | 工具 |
|---|---|---|
| 契约测试+API 漂移 | 第一个对外 API | oapi-diff / Pact |
| 真实依赖集成 | SQL 层落地 | testcontainers |
| 基准回归 | 出现数据密集路径 | Go bench + benchstat 周跑趋势 |
| DAST | compose 栈稳定 | Nuclei 周跑 |
| IaC 扫描 | Terraform 真实使用 | checkov |
| 压测 | 客户报性能问题 | k6 手动 |
| 状态机模型测试 | 出现复杂状态实体 | rapid (Go) / fast-check (TS) |
| 治理金丝雀 | —（直接上，周跑） | 自动验证 App 直推 main 被 ruleset 拒；守门人自身的健康检查 |

## 明确否决（含理由，翻案需新证据）

| 测试 | 否决理由 | 替代 |
|---|---|---|
| 覆盖率门槛 gate | 数字可游戏；AI 时代尤其假 | mutation score 趋势 |
| 金丝雀发布 | 客户本地部署，无在线流量可切 | release smoke |
| 混沌工程全套 | 无 k8s 舰队；投入产出失衡 | 失败模式写成单测（磁盘满/断网/超时） |
| TLA+/形式化 | 无调度器/共识类组件 | — |
| 长跑 soak | 重投入 | goleak + bench 趋势覆盖大部分意图 |
| a11y/i18n 测试 | 无 UI | 出现 UI 再议 |

## 已有（勿重复建设）

单测+属性测试+golden（gate）｜差分测试（重写项目 gate 必选项）｜mutation 周跑｜CodeQL｜zizmor｜dependency review｜hygiene（大文件/密钥文件）｜Dependabot+automerge｜provenance attestation｜治理漂移检测周跑
