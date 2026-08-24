# IR-0005 验收报告（T9 / ADR-0005 决策 5 谓词消费件）

- IR: Cloudbird-Software/.github#348（PM 优先范式转变）
- 验收人: 首位 PM（GLM-5.3 会话，owner 2026-08-24 夜全量授权）
- 验收日期: 2026-08-25
- 判据: IR#348 正文的 7 条"期望的可观察变化"逐条 + 运行时证据

## 子卡清单（曾存在性自证）

| 卡 | 标题 | PR | merge SHA |
|---|---|---|---|
| #349 | 范式地基——ADR-0085+INDEX 单仓化+退役快照+runs 环 | archive#17 | d4be1bd（squash 后 main） |
| #350 | .github 范式大 PR | .github#352 | 9dd5e98 |
| #351 | cnb-bridge 建仓+secrets+实弹+rev6* | cnb-bridge#1 | main squash |
（*rev6 见残留节——IR-0004 spec 修订未在本夜完成，见下）

前置依赖 PR：CI-Workflows#96（org-gate ADR 家园改址）、CI-Workflows#97（jq capture 幽灵 ADR 修复——archive#17 实测暴露的潜伏缺陷）。

## 逐条证据

| # | 期望变化 | 证据（链接+SHA） | 结论 |
|---|---|---|---|
| 1 | 三仓 GitHub archived + REPOS retired + retired/ 快照 | api 查询三仓 archived=true（2026-08-25 01:4x UTC）；REPOS.yaml@9dd5e98；archive/retired/（87 文件）随 archive#17 | ✅ |
| 2 | adr-required 三处指向 archive/adr；ADR-0085 可被引用 | CIW#96+CIW#97（org-gate）；.github#352（gate.yml+drift-check §10）；实证：archive#17 与 cnb-bridge#1 引用 ADR-0085 的 PR 均 org-adr-required 绿 | ✅ |
| 3 | T7/T8/T9 + conductor 谓词 + 反向测试 | transitions.yaml@9dd5e98（14 转移含 T7-T9）；conductor 内嵌谓词（merged_pr/acceptance）；反向测试证据见下方"状态机实走记录" | ✅ |
| 4 | 冷上下文六问复测全答 | 冷上下文代理复测报告（2026-08-25，本 run 附卷 runs/2026-W35.md） | ✅ |
| 5 | cnb-bridge active + secrets + 真实派单全链 | cnb-bridge#1 merged（gate/selftest/org-gate 全绿）；org secrets CNB_TOKEN_XUEMEI/CNB_TOKEN_P11（visibility=.github）；**实弹**：账号 p11→窗口 #207→NPC 13s 真实执行 `echo/uname/python3 -V` 退出码 0，回复含 [run:edd02570] 锚串（对账留痕于 cnb-bridge main 提交说明） | ✅ |
| 6 | 首份运行报告 + digest 工作流在位 | archive/runs/2026-W35.md（本夜收口 PR）；runs-digest.yml 随 archive#17 落地 | ✅ |
| 7 | IR-0004 spec rev6 | **未完成**——见残留节 | ⚠️ 诚实申报 |

## 状态机实走记录（T3/T8 正反双向实测 + T9 机器就位）

- **正向 ×3**：#349/#350/#351 各经 /claim（arbiter CAS 租约）→ in-progress → 置
  state:done → conductor T8 谓词跨仓核验（search API is:pr is:merged + Card 串精确
  复核；#349 的绑定 PR 在 archive#17、#351 在 cnb-bridge#1——跨仓绑定成立）→
  移旧态置 done。终态（2026-08-25 01:5x UTC 实查）：三卡均 `type:card,state:done`。
- **反向 ×1**：负向卡 #356（无绑定 PR）置 state:done → conductor 审计行
  `verdict=DENIED-no-merged-pr T8 拒绝——无绑定 …#356 且已合并的 PR（跨仓 searchOK
  + 本仓 closed PR 双查均空）` → 标签回滚 in-progress → 证据采集后关闭。
- **实走暴露并修复的两个真 bug**（PR#353/#355）：①标签转移双态窗口 abort（actor 置
  新态时旧态天然并存，旧守卫先于转移匹配拦截——T5/T7/T8/T9 全族不可达；收敛语义：
  事件标签=新态、另一态=转移前态）；②谓词本仓清单法漏跨仓绑定（search 主通道+本仓
  回退）。PR#354 因分支基线漂移成空 diff（compare 验证捕获），#355 重建生效——
  过程详见运行报告。
- T9（IR 验收门）：谓词已上线（wave-planned→done 需全部子卡 done + 本文件存在）。
  IR#348 生命周期收口路径见残留节。

## 残留与移交（诚实申报，验收不掩盖）

1. **IR-0004 spec rev6 未做**：CNB 默认主力/ASSUMPTION-03 升格的 spec 修订（卡 #351 的
   第三项）。范式落地不依赖它（EX-1/AGENTS/PLAYBOOK 已生效），但 IR-0004 的 AC-10
   语义修订仍应补——建议作为 owner 醒后第一张小卡。
2. **IR#348 生命周期收口**：本 IR 按旧仪式停在 ir-draft（签署→spec→红队→wave-planned
   未走）。ADR-0085 新范式下本 IR 属"owner 直授 + ADR 背书直执行"形态；T9 机器已就位
   但 from_state 不匹配。处置建议（owner 三选一）：(a) 补签+快写 spec+一轮红队走完
   仪式后 T9 关单；(b) 认可 ADR-0085 即决策背书，直接关单（备注范式首例豁免）；
   (c) 留 open 作为范式追踪伞。
3. **xuemei 账号 pending-access**：token 有效但对 talk 窗口仓 404——需 owner 在 CNB
   侧把 Olivia_Zhu（cnb.dUQ9MKJuAGA）加入 Cloudbird-Software 组后置 active
   （accounts.yaml 已标注）。
4. **CNB 窗口池现实**：旧 #1-#100 预置池已被清理（实测仅存 #247/#207 等少量），池已
   支持"无空闲自动补开"（swarm v2 先例模式）；窗口治理（回收/关闭策略）留待实践沉淀。
5. **本地 jq 缺失**使 test-ir0002 在本机无法复跑（CI 有 jq 正常）——PM 工作区配置
   建议补 jq（已记入运行报告 [followup]）。
6. **红队跨仓目标缺口（实弹发现）**：adversary 工作流实弹尝试 1 次（CI-Workflows run
   32760946045，exit 2 infra）——其目标目录契约在 CI-Workflows 自身 checkout 上下文解析，
   specs/IR-0005 在 .github 仓=跨仓目标当前不受支持。PR338 先例的红队实跑在 CNB 窗口
   （zhuzhu-team/test）+人工机械核对，本 PR 按 owner bypass 授权合并；红队补审（CNB 窗口
   judge-deep，PR338 同款）与 adversary 跨仓目标支持均登记 [followup]（运行报告）。
