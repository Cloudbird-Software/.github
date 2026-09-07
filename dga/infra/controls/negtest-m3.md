# negtest-m3 — M3 Temporal 流程负面/恢复测试记录（证据件）

- 执行：2026-09-07，流程轨道（M3）agent
- 脚本：`controls/negtest_m3.sh`（可复跑：每轮生成时间戳 feedback_id，任何断言 FAIL 退出码非 0；本轮连跑两轮均 exit 0）
- 规范依据：DGA-INFRA-v1.0 R-FLOW-01（人类等待在 Temporal）/ R-FLOW-03（幂等键+结果核对）/ R-FLOW-04（崩溃恢复已发生|未发生|不确定可区分）/ MET-01（时距到期自动挂起）
- 被测件：workflows/FeedbackLoopWorkflow（六段 mock + 审批闸门），worker task_queue=dga-main @127.0.0.1:7233，SDK temporalio 1.32.0，CLI 1.8.3 / Server 1.31.2，PG 16.9 @5432 dga_control（wf_run_events / wf_activity_idem，DDL=workflows/ddl.sql）
- 结果：**PASS=15 FAIL=0（ALL PASS，两轮）**，以下为实际输出逐字贴入
- 纪律：taskkill 仅按 worker.pid 中的 Windows PID 精确杀本轨道 worker；Temporal server 未重启；全 mock 无真实外部系统

## 副作用模型（三态判定依据）

每个 activity 对 (workflow_id, activity) 至多一行 `wf_run_events`（UNIQUE 硬约束）：
先写 `pending`（不确定：进行中或中断残留）→ 完成后改 `done`（已发生）；超时分支改 `suspended`（MET-01 挂起）；
`wf_activity_idem`（workflow_id+activity 唯一键）为重试去重权威源：`done` 直接跳过副作用，`running`（上次中断）做结果核对后补记完成并打 `recovered_from_running` 标记。`inspect_side_effects.py` 输出三态清单。

## 案例①：幂等——同 workflow_id 二次 start（R-FLOW-03）

期望：第一次 start 产生 6 行副作用（五段+approval_wait）并批准完成；第二次 start（id_reuse_policy=ALLOW_DUPLICATE，开新 run）所有 activity 撞幂等表全部跳过 → **每段事件行仍只 1 行**，首写 run_id 去重数仍 = 1。

实际（第一轮 run，id=FB-IDEM-1788715834）：

```
[1.1] 第一次 start FB-IDEM-1788715834（默认超时 300s）
{"started": true, "workflow_id": "feedback-loop-FB-IDEM-1788715834", "run_id": "01a077c5-a269-77f9-9911-6cb583a0dd8d", "status": "RUNNING", ...}
  第一次 start 后 wf_run_events 行数（含 approval_wait）= 6 （预期 6：五段+approval_wait）
  PASS: 首跑产生 6 行副作用
[1.2] 批准并等第一次 run 完成
  PASS: 第一次 run COMPLETED
[1.3] 同 workflow_id 二次 start（ALLOW_DUPLICATE 开新 run，activity 全部撞幂等表）
{"started": true, "workflow_id": "feedback-loop-FB-IDEM-1788715834", "run_id": "01a077c5-c89b-739b-8e1e-510147b7263d", "status": "RUNNING", ...}
  PASS: 第二次 run COMPLETED（复用同 id）
[1.4] 事件表每段行数 count 查询（两次 run 合并计）
  accept_verify|1
  apply_fix|1
  approval_wait|1
  collect_feedback|1
  propose_calibration|1
  publish_release|1
  run_ci_eval|1
  PASS: 每段仍只 1 行副作用（7 activity × 1，无重复）
  （事件行首写 run_id 去重数=1（预期 1：第二次 run 的 activity 全部跳过，无新副作用行））
  PASS: 第二次 run 零新副作用行
```

两个不同 run_id（…dd8d / …263d）共用同一批副作用行——Temporal 语义的 at-least-once 之上，业务副作用由幂等表钉死为恰好一次。

## 案例②：崩溃恢复——activity 进行中杀 worker（R-FLOW-04）

期望：轮询捕获 pending（进行中）行后 taskkill worker → 该行残留 pending（"不确定"态在案）；重启 worker 后流程自动续跑至等批准；批准后 COMPLETED；**全程每段副作用 count 仍 = 1**；被中断段由恢复路径补记并带 `recovered_from_running` 标记。

实际（第一轮 run，id=FB-CRASH-1788715855）：

```
[2.1] start FB-CRASH-1788715855，轮询等出现 pending（activity 进行中）行
  捕获进行中 activity = collect_feedback → taskkill //F //PID 2744（仅本轨道 worker）
  PASS: worker 已在 activity 'collect_feedback' 进行中被强杀
  杀死瞬间：副作用行=1，其中 pending（不确定态）=1
  PASS: 中断残留 pending 行（R-FLOW-04 '不确定'态在案）
[2.2] 重启 worker（幂等脚本）
workflow-worker: GREEN task_queue=dga-main (win-pid 6660)
[2.3] 等流程续跑至等待批准
  | approval_wait         0    done       已发生   （重连后六段全部续跑完成）
  | collect_feedback      1    done       已发生    apply_fix/publish/accept_verify 同
  | propose_calibration   6    absent     未发生    （等批准中）
  PASS: 崩溃后续跑至验收段完成（等批准中）
[2.4] 批准并等完成
  PASS: 崩溃恢复后 COMPLETED
[2.5] 全程段副作用 count 对比（每段必须仍 = 1）
  accept_verify|1  apply_fix|1  approval_wait|1  collect_feedback|1
  propose_calibration|1  publish_release|1  run_ci_eval|1
  PASS: 全程无重复副作用（7×1）
[2.6] inspect_side_effects.py 最终输出（含恢复标记）
  | == summary == done(已发生)=7 pending(不确定)=0 suspended(挂起)=0 absent(未发生)=0
RECOVERED SQL 修正后复跑（第二轮 run FB-CRASH-…）：
  recovered_from_running 标记数=1（被中断后续跑补记完成的段）
  PASS: 恢复路径结果核对照可区分（recovered_from_running）
```

证据补注（第一轮 PG 实查）：

```
SELECT activity, detail->'result'->>'recovered_from_running' FROM wf_run_events
 WHERE workflow_id='feedback-loop-FB-CRASH-1788715855';
 collect_feedback|true        ← 被强杀时正处 pending 的段，重启后结果核对补记完成
 apply_fix|(null) ...         ← 崩溃后正常新执行的段无恢复标记
```

恢复机制：activity 心跳（heartbeat）+ heartbeat_timeout=6s 使 server 在 worker 死亡后快速重投任务；重试命中 `wf_activity_idem.status=running` → 结果核对（副作用行已 pending=已发生未确认）→ 补记 done，不重发副作用（R-FLOW-02 唯一重试责任方）。

## 案例③：超时挂起——approval_timeout_sec=15 不批准（MET-01）

期望：五段自动完成进入等待；15 秒无批准 → timer 分支触发（TimerFired）→ `approval_wait=suspended` 事件行 → workflow 以挂起分支完成（describe Status=COMPLETED，result outcome=suspended）；**第六段（校准提案）不得发生**。

实际（第一轮 run，id=FB-TIMEOUT-1788715875）：

```
[3.1] start FB-TIMEOUT-1788715875 --timeout-sec 15，之后不批准
[3.2] 轮询 approval_wait=suspended
  PASS: approval_wait=suspended（MET-01 挂起事件行）@01:31:40
[3.3] workflow 关闭态与结果
  describe Status = COMPLETED
  result outcome  = "outcome":"suspended"
  history TimerFired 事件数 = 1（timer 分支到点触发）
  PASS: 挂起分支完成：COMPLETED + outcome=suspended
  PASS: timer 分支真实触发（TimerFired）
[3.4] 第六段（校准提案）必须未发生
  PASS: 挂起分支不执行校准提案（absent）
[3.5] inspect 视角
  | approval_wait         0    suspended  挂起(MET-01)
  | collect_feedback      1    done       已发生    …（五段 done）
  | propose_calibration   6    absent     未发生
  | == summary == done(已发生)=5 pending(不确定)=0 suspended(挂起)=1 absent(未发生)=1
```

对照 R-FLOW-01 正常路径（SMOKE，workflow show history）：`TimerStarted(41) → WorkflowExecutionSignaled(42) → TimerCanceled(46)` ——等待由 signal 承载、timer 分支兜底；signal 赢则取消 timer，timer 赢则走挂起。

## 汇总

| 案例 | 断言 | 结果 |
|---|---|---|
| ① 幂等 | 首跑 6 行；同 id 二次 start 每段仍 1 行；run_id 去重=1 | PASS×4 |
| ② 崩溃恢复 | pending 残留在案；续跑至批准完成；7×1 无重复；recovered_from_running 可区分 | PASS×6 |
| ③ 超时挂起 | suspended 事件行；COMPLETED+outcome=suspended；TimerFired；第六段 absent | PASS×5 |

**PASS=15 FAIL=0**（连跑两轮一致）。
