# 安全策略

## 报告漏洞

请通过仓库 **Security → Report a vulnerability** 提交（Private vulnerability reporting 已开启，[报告入口文档](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately)）。不要在 Issue/PR/讨论中公开披露。

## 响应时限（红队修复：此前无 SLA）

| 级别 | 定义 | 首次响应 | 处置目标 |
|---|---|---|---|
| P0 | 治理防线可被绕过 / 凭据泄露 / 供应链投毒路径 | 24h | 7 天内修复或缓解 |
| P1 | 单仓防线削弱 / 漂移长期未消 | 72h | 14 天 |
| P2 | 加固建议 | 7 天 | 排期 |

- 接收人：owner（randypanding）；owner 缺席超时限由 stewardship curator（team:stewardship）在周报升级。
- 处置记录：P0/P1 修复须附 ADR（flows.governance_change C1）。

## 报告范围

- 本仓治理文件与脚本（governance/ scripts/ .github/）
- 组织 ruleset / App `cloudbrid-agent` / secret 配置异常
- CI-Workflows 可复用工作流与 agent-registry 声明中的安全问题（转对应仓处置，本仓追踪）

## 披露

- 修复发布后，报告者可选择公开致谢；细节披露在修复落地后进行。
- 未修复前不披露利用细节。
