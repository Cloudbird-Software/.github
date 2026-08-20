# Required check 链路规范（路径过滤与结构性跳过）

ADR-0032（自动合并计划 P1-3，#81 §3.1/§3.2）。适用对象：组织内全部仓库的
GitHub Actions workflow。

## 规则 1：required 链路上的 workflow 禁用 workflow 级 `paths:` / `paths-ignore:`

被 ruleset 声明为 required check 的 workflow（当前唯一 required = `gate`，
BP-2）**不得**在 `on:` 层使用 `paths:` / `paths-ignore:` 过滤——路径不匹配时
check 完全不产生，PR 永久 pending，或 ruleset 静默匹配为空导致裸奔合并。

路径过滤只能用于非 required 的建议性 workflow，并须在本文件豁免清单登记理由。

## 规则 2：aggregator 严格断言，结构性跳过须显式登记

gate aggregator 断言为严格 `result == "success"`——skipped、cancelled、
failure、timed_out、startup_failure 一律红。事件互补设计（如 `deps` 仅 PR
事件、`deps-audit` 仅 push 事件）产生的**结构性预期跳过**，须在 aggregator
步骤内以 `EXPECTED_SKIP[事件]` 白名单显式登记；未登记的 skipped 一律红
（fail-closed 方向）。merge queue（P2-7）接入 `merge_group` 事件时同步扩充。

## 规则 3：安全 job 永远不许无条件 skip

hygiene（gitleaks 全历史凭据扫描、zizmor 工作流安全审计）等安全类 job 不
存在合法的永久跳过路径（`if: false` 禁止）；事件互补必须保证两个事件面都
有安全覆盖。任何"跳过安全检查"的诉求都须先以 ADR 修订本规范。

## 豁免清单（非 required workflow 的 workflow 级路径过滤）

| 仓库 / workflow | 用途 | 理由 |
|---|---|---|
| AI_Web_School `contract.yml`（contract-watch） | 冻结契约变更检测（P5 建议性检测） | 非 required check（该仓唯一 required = gate）；paths 过滤省 runner，契约无关 PR 本就无检测意义 |

## 执法

- 静态扫描基线（T4，2026-08-20 全 11 仓）：required 链路零 workflow 级路径
  过滤，唯一豁免如上。P1-4（#85）落地后将此扫描纳入 drift-check 例行对账。