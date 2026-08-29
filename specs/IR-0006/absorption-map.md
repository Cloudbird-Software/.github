# 总纲 v1.0 吸收落位表 + 词汇归并表（IR-0006 附件一）

> 状态口径：**已覆盖**=现有机制直接映射，总纲该章吸收为引用（不新建）；
> **本 IR 吸收**=六波次内落盘；**延后**=明确非目标，触发条件成熟后另行立项。
> 铁律：凡标"已覆盖"的章，禁止平行新建同类对象（防双 SSOT——ADR-0103 决策 6）。

## 一、18 部分落位表

| 总纲部分 | 落点 | 状态 | 说明 |
|---|---|---|---|
| 第一部分 背景（三条产品线/两铁律/基础设施盘点） | REPOS.yaml 各仓 role + GOVERNANCE risk_posture | 已覆盖 | 公司形态与资产盘点=组织地图既有职责；两铁律吸收为本表注释 |
| 第二部分 目标函数（注意力最小化/风险旋钮/两支柱） | 宪法 §0/§7 + metrics.yaml | 已覆盖 | 注意力会计已在跑（签署耗时/needs-human p90）；注意力硬预算=W2-C3（human_minutes 入卡） |
| 第三部分 整体架构（五层平面+五回路+三横切） | ADR-0103 决策 2（三面分离） | 本 IR 吸收 | 五层平面收编为声明/执行/判定三面；五回路中 R3/R5=R4/R5 波次补建 |
| 第四部分 宪法八条 I1-I8 | constitution.md v2.3 条款 | 已覆盖（I3/I7 扩展） | I1=AR-3+runs；I2=ghcb/arbiter/conductor；I3=W2-C3/C4（票据入卡）；I4=GOVERNANCE 分域表 W1 增补；I5=holdout 仓+红队+诱饵；I6=portability 段+EX-1；I7=W2-C3+metrics；I8=C1/ADR/元测试/drill |
| 第五部分 对象模型（Wave+六 manifest） | card issue+wave-plan（扩展非新建） | 本 IR 吸收 | Wave≡卡+波次计划（schema 扩展）；Tenant=tenant tag；AgentRole≡ROLE-*.md；Gate≡policy/testing.yaml+g060；Sandbox≡env 定义仓；Channel≡投影体系第四投影；>6 kind 维持暂缓 |
| 第六部分 控制平面（broker 六职能/propose-dispose/JIT/污点） | ADR-0103 决策 2/4/5 + providers.yaml+dispatch+gh-app-token | 本 IR 吸收 | broker=逻辑契约非物理咽喉；propose-dispose 已覆盖；JIT=W2-C2/C4；污点标记延后（随 inbound） |
| 第七部分 执行基座（Job Contract/放置策略/云电脑池/否决多账号） | ADR-0103 决策 4 + providers.yaml 新条目 | 本 IR 吸收 | 织物分界=GitHub 能启动的不自建；池化以服务器为锚；多账号轮换维持否决 |
| 第八部分 门禁体系（分类+元治理+路书治理） | gate.yml/adversary/holdout/drill/metrics.yaml | 已覆盖 | 门禁四列指标=metrics 北极星对既有体系扩展（W6-M1 评审）；docs-as-tests 承 test-navigation.sh |
| 第九部分 AI 能力开发 MLOps（两类交付物/优化波次/合成数据血统） | holdout 仓扩展（eval registry） | 本 IR 吸收（W5） | 复用 wave/gate/evidence 三件套；评测基建先于优化循环（投资顺序纪律不变） |
| 第十部分 Harness 与 Swarm（四条缝/conformance/swarm 编制） | 暂缓清单 + W6-M1 语料种子 | 已覆盖（暂缓不变） | 四条缝=AGENTS.md/MCP/Wave+证据包/broker 票据——前三已在位；conformance suite 种子 W6；自建判据 ≥3 次妥协不变 |
| 第十一部分 界面层飞书（三职责/铁律/声明方式） | W3-F（outbound 多维表格） | 本 IR 吸收 | outbound-only；inbound/污点/审批回写延后另行立项 |
| 第十二部分 多租户与潮玩公司 | tenant tag（W1-B2）+资产登记簿 | 本 IR 吸收（窄面） | 仅计量先行+登记簿；分家工程/可分离部署验收测试延后 |
| 第十三部分 治理外输产品化（三层/编译器/签名证据包） | 延后 | 延后 | 内部跑通后另行立项；签名证据包 v0 承 SC-4 在 W4-R3 先落地基 |
| 第十四部分 R3 运行回路（环境管理/SLO/值班/反馈边） | W4-R + sli-weekly | 本 IR 吸收 | drift 模式泛化；责任边界文件在首个托管客户前写死 |
| 第十五部分 治理元环（学习机制/continuity） | runs 报告+ADR+drill 已覆盖；决策语料 W1-D1 | 已覆盖（+1 新件） | 治理回归测试=drill 既有语义；决策语料=唯一新增资产 |
| 第十六部分 风险清单 | SECURITY.md+risk_posture+本表 | 已覆盖 | 各风险行均有既有缓解机制锚点（见 governance 各条款） |
| 第十七部分 路线图 P0-P3 | wave-plan.md（六波次重排） | 本 IR 吸收 | 按内部跑通优先重排；原 P0-P3 与 W1-W6 映射见波次计划头部 |
| 第十八部分 待决参数（风险刻度/分钟预算/责任边界） | ADR-0103（已裁决）+W2/W4 | 本 IR 吸收 | 裁决模型已裁决；分钟预算先跑数据后定（W2-C3 前提）；责任边界 W4-R2 |

## 二、词汇归并表（总纲词汇 → 现有机制，防双 SSOT）

| 总纲词汇 | 归并到 | 动作 |
|---|---|---|
| Wave | card issue + wave-plan.md | 扩展 schema（budget/capabilities/evidence 字段），不新建 kind |
| Capability Broker / Egress Proxy | providers.yaml + dispatch 经纪人 + gh-app-token + 内网服务器路由 | 升级不重建（逻辑契约，分域物理适配） |
| 证据账本 | metering（ADR-0062）+ butler audit + drill history 三源统一 → archive 仓 evidence/ | 合并不另立（hash 链平移） |
| Channel manifest | label→board 投影体系第四投影（飞书多维表格） | 延用 label 唯一真源 |
| Sandbox manifest | env 定义仓（新建） | 新建（三面分离的声明面载体） |
| AgentRole | docs/agent/ROLE-*.md + ghcb 入口协议 | 已覆盖，不新建 kind |
| Gate 注册表 | governance/policy/testing.yaml + g060 锁 | 已覆盖 |
| 风险等级 risk_class / Profile | 参数包选择器（门禁集/entitlement 档/介入点） | 新概念吸收为参数包，非裁决输入（ADR-0103 决策 1） |
| Holdout / eval registry | holdout 仓（扩展四元组 pin+非劣性 gate） | 扩展不新建 |
| 收件箱（五类决策+SLA） | metrics 注意力会计 + 飞书投影 | 部分已覆盖，human_minutes 入卡补全 |
| Job Contract | 内网调度器契约（W2-C1） | 新建（执行面基础设施，非 harness） |
| 决策语料 | archive 仓 append-only 文件 + 链式 hash | 新建（本 IR 唯一无先例资产） |

## 三、退役规则

总纲 v1.0 原文不进 git（git 外文档不具权威）；其内容经本表全部映射后，讨论过程中的
任何总纲副本视为草稿，权威以落点文件为准。本表自身是 C1 资产：修正走 PR+ADR。
