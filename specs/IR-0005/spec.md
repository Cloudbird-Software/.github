---
taskId: IR-0005
specVersion: 1
title: PM 优先范式转变条款级规格——四道门禁制度化、编排层退役、CNB 默认开发主力、运行报告闭环
irRef: Cloudbird-Software/.github#348
adrRef: archive/adr/ADR-0085-pm-first-paradigm-shift.md
acceptanceReport: specs/IR-0005/acceptance.md
amendments:
- rev: 1
  reason: 首版——owner 2026-08-24 夜全量授权直执行形态（ADR-0085 决策背书），AC 与验收证据同批落盘；
    本 spec 为事后追认性条款化（实现已合并、证据已在 acceptance.md），红队审计按 ADR-0082 常规执行
acceptanceCriteria:
- id: AC-1
  given: agent-registry/agent-platform/agent-tools 三仓已按 ADR-0085 决策 2 处置
  when: 检查三仓状态与组织地图
  then: 三仓 GitHub archived=true 且 REPOS.yaml status=retired；声明层 87 文件快照在 archive/retired/；语言/契约政策残留条款已清理（languages.yaml PY 准入回归默认拒绝）
- id: AC-2
  given: ADR 家园单仓化（ADR-0085 决策 3）已执行
  when: 任一 C1 路径 PR 引用 ADR-NNNN
  then: gate.yml / org-gate.yml / drift-check §10 三处校验均解析 archive/adr/INDEX.yaml 且正本可达性核验通过；新 ADR 直接 PR 至 archive/adr/ 并更新 INDEX（ADR-0085 本身即首例）
- id: AC-3
  given: transitions.yaml 含 T7/T8/T9 且 conductor 谓词生效
  when: 一张 type:card 卡从 wave-planned 推进至 done
  then: T7 置 ready、T3 认领（arbiter CAS）、T8 置 done 前机械核验"绑定本卡且已合并的 PR"（跨仓 search 主通道+本仓回退，双通道皆不可用 fail-closed）；无绑定 PR 的卡置 done 被拒绝并回滚标签（DENIED-no-merged-pr）
- id: AC-4
  given: 一张 type:intent IR 处于 wave-planned 且全部子卡 state:done
  when: 置 label:state:done
  then: T9 谓词核验"无 open 子卡引用本 IR（父意图: #N）+ specs/<IR-NNNN>/acceptance.md 存在"后放行；任一不满足即拒绝并回滚
- id: AC-5
  given: CNB 免费算力池（EX-1 三接缝）在位
  when: PM 发起派单（ghcb dispatch 或 cnb-dispatch 工作流）
  then: 档位校验以 automation-limits.yaml cnb 节为准（light=1C 默认/std 须 tier-reason/heavy 须 tier-adr/8C 禁）；token 仅存 org secret 且仅经纪工作流内使用，PM 上下文与任务文本零凭据（嗅探拒发）；沙箱自报数字不采信、产物须锚串核对
- id: AC-6
  given: PM 完成一轮工作
  when: run 收口
  then: 三节式运行报告（事实/体感/改进点，[followup] 行为唯一机械抓手）追加至 archive/runs/YYYY-WNN.md；runs-digest 周一自动聚合开 digest issue；报告是经验输入不是验收证据
- id: AC-7
  given: 范式类变更 affecting PM 入口面
  when: 冷上下文六问协议复测
  then: a-f 六问（第一天干什么/进行中工作/IR→spec 路径/可调资源/复盘落点/key 获取）全部有真实来源可答，主链路零假链；实测记录留档
inv: |
  INV-01 判定语义不随范式转移改变：生成/裁决分离（LLM/沙箱仅生成侧）、fail-closed、
  append-only 账本、凭据纪律四条红线恒定（ADR-0085 决策 1）。
  INV-02 CNB 可整体删除（三接缝外零操作性引用；删除后 gate/org-gate/conductor 语义不变）。
  INV-03 T8/T9 谓词不信标签载荷，运行时 API 重查；状态写序语义=事件标签是新态、
  并存的另一态是转移前态（双态窗口收敛，PR#353）。
budget: |
  BUDGET-01 CNB 档位与配额参数真源=automation-limits.yaml cnb 节（IR-0004 AC-15 承接）。
  BUDGET-02 报告环仅两个机械件（append 校验+周度 digest），不建指标面（范式稳定后再议）。
decision: |
  DECISION-01 本 IR 为 owner 直授权直执行形态：ADR-0085 即决策背书，spec 为事后条款化
  追认；IR#348 生命周期收口（是否补签署→spec→红队仪式或直接关单）留 owner 裁决，
  三选项见 acceptance.md 残留节。
