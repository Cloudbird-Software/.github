# 责任边界——SLO 定义 · 值班范围 · 破线升级路径 · break-glass

> IR-0006 W4-R2 / 卡 #419 / AC-8d。本文件在第一个托管客户出现之前写死责任边界
> （"没有 SLO 的事故响应是吵架，有了 SLO 才是工程"）。SLO 骨架期：指标已接入
> sli-weekly 周报（环境面 env_face_*），破线判定=人工归因，不自动升级——
> 托管客户签约时按本文件逐节评审后再接入自动化升级（届时改 sli-report.sh
> 阈值通道，本文件同步 rev）。
>
> 指标数据源真源：`scripts/sli-report.sh`（周报 issue，label sli-report）；
> 环境面对账引擎：`governance/env-drift.py`（每日 07:33 UTC，漂移→issue→消除自动关）。

## 1. SLO 定义

| ID | 面向 | 指标 | 目标 | 数据源 | 状态 |
|---|---|---|---|---|---|
| SLO-1 | 环境对账收敛 | env_face convergence（窗口内零漂移轮/总轮）+ 末轮 drifts | 骨架期：末轮 drifts=0；托管期：月收敛率 ≥99%（允许 1 漂移轮/月） | env-ledger 影子账本（每日对账事件） | 骨架 |
| SLO-2 | 环境对账新鲜度 | env_face freshness（末轮对账距今） | ≤48h（cron 每日一次，容忍一日缺失） | 同上 | 骨架 |
| SLO-3 | 门禁逃逸 | escape_rate（周报） | 连续两周=0（>0 即 P1 升级，已自动化） | sli-report 周报 | 已执法 |
| SLO-4 | PR 停滞 | stuck_prs（>48h open PR） | 每周 ≤2（一人公司容量锚点） | 同上 | 骨架 |

骨架期语义：SLO-1/2/4 为"可见性先行"——周报呈现 + 人工归因，不自动开单；
SLO-3 已接阈值自动升级（escape_rate 连续两周>0 → P1）。

## 2. 值班范围

一人公司（owner=唯一人类值班面，@randypanding）：

- **值班面=检测器自动 + owner 归因**：governance-drift（每小时）/ env-drift（每日）
  / butler-deadman / cost-check 全部自动开 issue 并 @owner——owner 的值班动作
  只有一项：按 issue 指引处置（不是盯 dashboard）。
- **响应时限（骨架期约定）**：P0（成本熔断/凭据失效/deadman trip）≤24h；
  P1（门禁逃逸/环境漂移）≤72h；骨架期无 SLA 承诺对客户外泄。
- **agent 不值守判定**：LLM 只在生成侧，一切判定锚点机械（INV-01/02）——
  值班归因是 owner 保留权，agent 只准备证据（账本可查：evidence-query 七源）。
- **托管客户出现时**：值班范围从"org 内部"扩至"客户租户面"，须先走 ADR
  修订本节 + sli-report.sh 破线自动升级，再对外承诺 SLA 数值。

## 3. 破线升级路径

破线= SLO 表内任一指标越限。路径（骨架期人工、结构固定）：

1. **检出**：周报（sli-report）/ env-drift issue 自动呈现越限指标与上下文
   （DRIFT 行 / convergence / freshness）。
2. **归因**（owner，≤时限）：区分三通道——
   a. 真实漂移（实况面修齐或期望态 PR）；
   b. 检测器/infra 故障（token 失效、clone 失败——env-drift 分通道已隔离，
      勿把 infra 当漂移修环境）；
   c. 期望态过时（policy scope 调整，走 PR）。
3. **修复验证**：处置后 dispatch 对应 workflow 复核绿（env-drift 全绿=自动关
   issue，即回探证据）。
4. **留痕**：处置结论回写 issue；每轮处置进运行报告（archive runs/）。
5. **升级**：时限内未处置 → deadman/butler 通道已有 fail-closed 兜底
   （AUTO_MERGE_DISABLED 等）；连续两周期破线 → 开 P1 并入 PM 周报复盘。

## 4. break-glass

> 红线总纲：破玻璃=例外通道，不是快捷方式。每次使用必须留痕可审计。

- **允许的场景（穷举）**：①org secret 失效需 owner 面轮换（凭据永不经 agent，
  INV-04）；②ruleset 阻塞止血且 automerge 已熔断；③平台级事故（GitHub 侧故障）
  需 Git Data API 替代推送。**其余一律走 PR+gate**。
- **使用规则**：
  1. 破玻璃直推（绕 ruleset/直推 main）必须 @owner 发起或 owner 明示授权——
     agent 自发破玻璃=违规。
  2. 每次使用 48h 内回填：ADR 或 expected-state 豁免登记（§8 (c) 类先例），
     否则 governance-drift 每小时会检出并开 issue（豁免回填时限执法）。
  3. 破玻璃期间的合并/变更必须事后补跑对应 gate（复现验证），证据入卡或 issue。
- **禁止**：用 break-glass 规避门禁红（如测试失败、CodeRabbit 未过）；
  规避红=失败失败（fail-fail），按宪法视为最严重治理违规。
