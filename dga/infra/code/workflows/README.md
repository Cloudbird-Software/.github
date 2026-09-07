# workflows · FeedbackLoopWorkflow（M3 首条流程）

客户反馈 → 修复 → CI/Eval → 发布 → 验收 → **[人类批准闸门]** → 校准提案。
规则锚点：R-FLOW-01（等待在 Temporal 不依赖会话）/ R-FLOW-02（唯一重试责任方+心跳）/ R-FLOW-03（幂等键+结果核对）/ R-FLOW-04（副作用三态可区分）/ MET-01（时距到期自动挂起）。

## 文件

| 文件 | 角色 |
|---|---|
| `ddl.sql` | 幂等建 `wf_run_events`（副作用证据，pending/done/suspended）+ `wf_activity_idem`（幂等权威源）；UNIQUE(workflow_id, activity) 硬保每段 1 行 |
| `defs.py` | 六段定义、signal 名、`FeedbackLoopInput`（approval_timeout_sec 默认 300，env `DGA_APPROVAL_TIMEOUT_SEC` 可覆盖） |
| `db.py` | PG 访问层（psycopg3）；幂等表/事件表读写；`ensure_ddl()` |
| `activities.py` | 6 段 mock activity + 3 个审批标记 activity；统一幂等骨架：首行查幂等表 → 写 pending → 心跳+mock 工作 → done；`running` 残留走结果核对补记（recovered_from_running） |
| `feedback_loop.py` | `FeedbackLoopWorkflow`：五段自动 → `approval_wait`（wait_condition+approval_signal，timer 分支=超时 MET-01 挂起）→ 批准则第六段 → 完成 |
| `worker.py` | worker（task_queue=`dga-main`，活动线程池）；自写 Windows PID 到 `services/workflow-worker/worker.pid` |
| `start_feedback_loop.py` | client 发起（id=feedback-loop-<feedback_id>，ALLOW_DUPLICATE） |
| `approve.py` | 发 `approval_signal`（批准人/备注入证据行） |
| `inspect_side_effects.py` | R-FLOW-04 三态清单：done=已发生 / pending=不确定 / suspended=挂起 / absent=未发生（`--json` 机器可读） |

## 运行（本机）

```bash
services/scripts/start-workflow-worker.sh                        # 幂等后台起 worker（连 7233）
.venv/Scripts/python.exe workflows/start_feedback_loop.py FB-1001   # 发起（五段自动后停在等批准）
.venv/Scripts/python.exe workflows/inspect_side_effects.py FB-1001  # 看副作用三态
.venv/Scripts/python.exe workflows/approve.py FB-1001 --approver S5  # 批准 → 第六段 → COMPLETED
# 超时分支：start_feedback_loop.py FB-X --timeout-sec 15 不批准 → 15s 后 approval_wait=suspended
```

环境变量：`DGA_PG_DSN`（默认 host=127.0.0.1 port=5432 user=dga dbname=dga_control）、`DGA_APPROVAL_TIMEOUT_SEC`（默认 300）。

## 证据

- `SMOKE.txt`：start→五段→等批准→approve→COMPLETED 全程，含 `temporal workflow list`/`describe`/history 尾部截获。
- `gov-infra-repo/controls/negtest-m3.md` + `negtest_m3.sh`：①幂等二次 start ②杀 worker 崩溃恢复 ③15s 超时挂起（PASS=15 FAIL=0 两轮）。

## 遗留缺口（登记 M5+）

六段均为 mock（副作用=事件行本身）；真实段（控制面登记、池路由调用、外部发布/验收通道）待执行单元接入后替换 `activities.py` 的 result builder，幂等/三态骨架不变。
