# IR-0004 验收报告（rev6 语义，Gate-4/T9 谓词消费件）

- IR: Cloudbird-Software/.github#315（验证体系缺口闭环 + spec 质量测量 + fan-out 生命周期 + CNB 底座）
- 验收人: PM 会话（GLM-5.3，owner 2026-08-25 授权"以 PM 优先范式重写并全量开发交付"）
- 验收日期: 2026-08-25
- 判据: spec rev6（.github#359 合并版）21 条 AC + 20 张波次卡

## 子卡清单（20/20 全部 state:done + #358 rev6 卡）

| 波次 | 卡 | 交付 PR |
|---|---|---|
| W0 | #316 cnb-bridge 建仓/调度器/EX-1 | cnb-bridge#1 |
| W0 | #317 配额账本/1C 档 | cnb-bridge#2 |
| W0 | #318 账号生命周期 runbook | cnb-bridge#2 |
| W0 | #319 work-inbox 自起协议 | cnb-bridge#2 |
| W0 | #320 token 决策 ADR | archive#19（ADR-0086 归档+INDEX 84 条） |
| W0 | #321 周审计五项 | cnb-bridge#2 |
| W1 | #322 变异实跑+定向管线 | CI-Workflows#104（55 自测） |
| W1 | #323 属性推断+变异裁判 | CI-Workflows#104 |
| W1 | #324 模糊种子+深跑 | CI-Workflows#102（42 自测） |
| W1 | #325 蜕变盘点 | CI-Workflows#102 |
| W1 | #326 符号执行试点 | CI-Workflows#102 |
| W1 | #327 SAST 分诊台账 | CI-Workflows#102 |
| W1 | #328 形式化条件触发 | CI-Workflows#102 |
| W2 | #329 验收 DSL 编译器+spec CI 关卡 | CI-Workflows#100（28 自测） |
| W2 | #330 骨架 fan-out 仪器 | CI-Workflows#100 |
| W3 | #331 实现 racing 机制 | CI-Workflows#103（44 自测） |
| W3 | #332 champion/oracle 生命周期接口 | CI-Workflows#103 |
| W3 | #333 红队燃料管道 | CI-Workflows#103+#105 |
| W4 | #334 自举试点 | CI-Workflows#105（试点链实测：熵→哈希链产物→消费 exit 0） |
| W4 | #335 演练与退休 runbook | CI-Workflows#103+#105 |
| 补 | #358 rev6 语义修订 | .github#359 |

## 逐条证据（rev6 口径）

| AC | 结论 | 证据 |
|---|---|---|
| 1 变异 | ✅ 仪器+自测 | run_mutation 8 AST 算子降级路径+mutmut 探测；55 自测含弱套件存活算术验证；weekly 入口 mutation-weekly.yml |
| 2 属性+裁判 | ✅ | 四属性×七生成器；裁判零杀死=平凡拒收；judge_log 逐条 |
| 3 模糊 | ✅ | 15 类边界生成器+corpus 台账+栈哈希去重 |
| 4 蜕变 | ✅ | catalog 15 条（3 implemented 可执行） |
| 5 符号 | ✅ | pynguin 探测+AST 近似（proxy 标注）+adopt/reject 报告带复算命令 |
| 6 SAST | ✅ | ledger sha256 链+sweep 未处置清单 |
| 7 形式化触发 | ✅ | checklist 4正4反+trigger risk_level fail-closed+语义留痕位 |
| 8 DSL | ✅ 真跑 | 真实 spec 编译→校验→篡改红全链（runtime-evidence.md） |
| 9 骨架仪器 | ✅ 真跑 | 试点 convergence 20%/零串通/契约路线分解 |
| 10 PM 裁量+CNB 默认 | ✅ | rev6 决策矩阵降 PLAYBOOK；CNB 实弹全链（窗口 207/退出码 0/锚串回收，IR-0005 报告） |
| 11 改进 PR 通道 | ✅ 接口 | 未注册 oracle 时空转不红（rev6 条件适用语义） |
| 12 oracle 接口 | ✅ 真跑 | registry validate OK+diffbench 硬区 exit 2/软区 0/缺输入 1 |
| 13 燃料管道 | ✅ 真跑 | consumer 空目录 exit 0+哈希链校验+攻击查询生成 |
| 14-18 CNB 底座 | ✅ | 三接缝+配额配置化+runbook+work-inbox+周审计（cnb-bridge#1/#2） |
| 19 演练 | ✅ 真跑 | 静态干跑双真仓 green；functional runbook 输出模式 |
| 20 试点 | ✅ | #334 仪器链实测（rev6 诠释：多路实现 racing 为 PM 可选，试点证明仪器可用） |
| 21 token 决策 | ✅ | ADR-0086 归档+三层缓解+RUNBOOK 执行细则 |

## 残留与移交（诚实申报）

1. **IR#315 生命周期**：卡全 done 但 IR 停在 state:spec——T5/T6 的红队 survived 记录因
   LLM 通道 infra 故障未能产生（三次实弹 run 32793862619/32794290751/32795149375，
   kimi-for-coding 与 glm-4.5-air 均 2xx 异常体；连通性小探针正常——供应商/metering 层
   待 owner 排查）。**owner 三选一**：修通道后补红队走完 T9 / 认可本报告+卡全 done 直
   接关单 / 留 open。
2. **X-04 正式修订 ADR**：checklist/trigger 仪器已就位（#328），testing.yaml 的 X-04
   条款文本修订（rejected→triggered）需小 PR+ADR——半天工作量，建议醒后第一张卡。
3. **mutation weekly 对 AI_Web_School 首跑**：workflow 就绪，首次真实 run 建议在
   owner 在场时触发（30 分钟预算，观察 mutmut 在真实仓的行为）。
4. **A2 幻觉勘误记录**：子代理曾虚构 api-gateway/billing-core/web-console 三仓名，
   集成时以 REPOS.yaml 勘误（CIW#102 修复提交）——多代理开发的已知风险，运行报告
   已记 [followup]（集成审查必须对照 SSOT）。
5. **zizmor 艺术品级反复**：artipacked 在 4 个 workflow 上共暴露 7 次（裸块/with 块/
   第三处），全部 persist-credentials 修复——子代理工作流模板应预置该字段（已记 followup）。
