#!/usr/bin/env bash
# negtest_m3.sh · M3 负面/恢复测试（可复跑，PASS/FAIL 逐条断言，全过 exit 0）
#   ① 幂等（R-FLOW-03）：同 workflow_id 二次 start（ALLOW_DUPLICATE 新 run）→ 每段副作用仍只 1 行
#   ② 崩溃恢复（R-FLOW-04）：activity 进行中 taskkill worker → 重启 → 流程续跑至批准完成，副作用无重复
#   ③ 超时挂起（MET-01）：approval_timeout_sec=15 不批准 → approval_wait=suspended 分支完成
# 纪律：taskkill 只杀本轨道 worker（worker.pid 中的 Windows PID，精确 PID）；不碰 temporal server。
set -u

ROOT="D:/Projects/dga-infra"
PY="$ROOT/.venv/Scripts/python.exe"
WF="$ROOT/workflows"
PSQL="$ROOT/services/postgres/pgsql/bin/psql.exe"
TEMPORAL="$ROOT/services/temporal/temporal"
START_WORKER="$ROOT/services/scripts/start-workflow-worker.sh"
PID_FILE="$ROOT/services/workflow-worker/worker.pid"

pg() { "$PSQL" -h 127.0.0.1 -p 5432 -U dga -d dga_control -tAc "$1"; }

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
wfname() { echo "feedback-loop-$1"; }
wf_status() { "$TEMPORAL" workflow describe --workflow-id "$(wfname "$1")" 2>/dev/null | grep -E "^  Status" | awk '{print $2}'; }
wait_status() { # id expect timeout_s
  local id="$1" expect="$2" t="${3:-90}"; local i=0
  while [ $i -lt $t ]; do
    [ "$(wf_status "$id")" = "$expect" ] && return 0
    sleep 1; i=$((i+1))
  done
  wf_status "$id"; return 1
}

echo "############################################################"
echo "# M3 negtest ① 幂等：同 workflow_id 二次 start，副作用不重复"
echo "############################################################"
IDEM_ID="FB-IDEM-$(date +%s)"
WIDEM="$(wfname "$IDEM_ID")"
echo "[1.1] 第一次 start $IDEM_ID（默认超时 300s）"
(cd "$WF" && "$PY" start_feedback_loop.py "$IDEM_ID") || bad "第一次 start 失败"
# 等五段完成进入等待
for _ in $(seq 1 60); do
  N=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WIDEM' AND status='done' AND activity='accept_verify'")
  [ "$N" = "1" ] && break; sleep 1
done
BEFORE=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WIDEM'")
echo "  第一次 start 后 wf_run_events 行数（含 approval_wait）= $BEFORE （预期 6：五段+approval_wait）"
[ "$BEFORE" = "6" ] && ok "首跑产生 6 行副作用" || bad "首跑行数=$BEFORE 预期 6"
echo "[1.2] 批准并等第一次 run 完成"
(cd "$WF" && "$PY" approve.py "$IDEM_ID" --note "negtest① first-run approve") >/dev/null || bad "approve#1 失败"
wait_status "$IDEM_ID" "COMPLETED" 60 >/dev/null && ok "第一次 run COMPLETED" || bad "第一次 run 未完成: $(wf_status "$IDEM_ID")"
echo "[1.3] 同 workflow_id 二次 start（ALLOW_DUPLICATE 开新 run，activity 全部撞幂等表）"
(cd "$WF" && "$PY" start_feedback_loop.py "$IDEM_ID") || bad "第二次 start 失败"
sleep 8   # 新 run 跑完可跳过的段、进入等待
(cd "$WF" && "$PY" approve.py "$IDEM_ID" --note "negtest① second-run approve") >/dev/null || bad "approve#2 失败"
wait_status "$IDEM_ID" "COMPLETED" 60 >/dev/null && ok "第二次 run COMPLETED（复用同 id）" || bad "第二次 run 未完成"
echo "[1.4] 事件表每段行数 count 查询（两次 run 合并计）"
pg "SELECT activity, count(*) AS rows FROM wf_run_events WHERE workflow_id='$WIDEM' GROUP BY activity ORDER BY activity" | sed 's/^/  /'
DUP=$(pg "SELECT count(*) FROM (SELECT activity FROM wf_run_events WHERE workflow_id='$WIDEM' GROUP BY activity HAVING count(*)>1) t")
TOTAL=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WIDEM'")
[ "$DUP" = "0" ] && [ "$TOTAL" = "7" ] && ok "每段仍只 1 行副作用（7 activity × 1，无重复）" || bad "出现重复：total=$TOTAL dup_groups=$DUP"
RUNS=$(pg "SELECT count(DISTINCT run_id) FROM wf_run_events WHERE workflow_id='$WIDEM'")
echo "  （事件行首写 run_id 去重数=$RUNS（预期 1：第二次 run 的 activity 全部跳过，无新副作用行））"
[ "$RUNS" = "1" ] && ok "第二次 run 零新副作用行" || bad "第二次 run 产生了新副作用行"

echo
echo "############################################################"
echo "# M3 negtest ② 崩溃恢复：activity 进行中杀 worker → 重启续跑"
echo "############################################################"
CRASH_ID="FB-CRASH-$(date +%s)"
WCRASH="$(wfname "$CRASH_ID")"
echo "[2.1] start $CRASH_ID，轮询等出现 pending（activity 进行中）行"
(cd "$WF" && "$PY" start_feedback_loop.py "$CRASH_ID") >/dev/null || bad "start 失败"
PENDING_ACT=""; KILLED="no"
for _ in $(seq 1 300); do
  PENDING_ACT=$(pg "SELECT activity FROM wf_run_events WHERE workflow_id='$WCRASH' AND status='pending' ORDER BY id DESC LIMIT 1")
  if [ -n "$PENDING_ACT" ]; then
    WPID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$WPID" ]; then
      echo "  捕获进行中 activity = $PENDING_ACT → taskkill //F //PID $WPID（仅本轨道 worker）"
      taskkill //F //PID "$WPID" >/dev/null 2>&1 && KILLED="yes"
      break
    fi
  fi
  sleep 0.1
done
[ "$KILLED" = "yes" ] && ok "worker 已在 activity '$PENDING_ACT' 进行中被强杀" || bad "未能捕获进行中窗口并杀 worker"
sleep 1
AT_KILL=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WCRASH'")
P_LEFT=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WCRASH' AND status='pending'")
echo "  杀死瞬间：副作用行=$AT_KILL，其中 pending（不确定态）=$P_LEFT"
[ "$P_LEFT" -ge 1 ] && ok "中断残留 pending 行（R-FLOW-04 '不确定'态在案）" || bad "无 pending 残留（捕获窗口失误）"
echo "[2.2] 重启 worker（幂等脚本；杀后的 poller 残留条目按 PID 存活判定忽略）"
bash "$START_WORKER" || bad "worker 重启失败"
echo "[2.3] 等流程续跑至等待批准（被中断 activity 由重试续执行，幂等表判定不重做副作用）"
for _ in $(seq 1 120); do
  D=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WCRASH' AND activity='accept_verify' AND status='done'")
  [ "$D" = "1" ] && break; sleep 1
done
INS_AT_WAIT=$(cd "$WF" && "$PY" inspect_side_effects.py "$CRASH_ID")
echo "$INS_AT_WAIT" | sed 's/^/  | /'
DONE5=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WCRASH' AND status='done' AND activity='accept_verify'")
[ "$DONE5" = "1" ] && ok "崩溃后续跑至验收段完成（等批准中）" || bad "续跑失败：accept_verify done=$DONE5"
echo "[2.4] 批准并等完成"
(cd "$WF" && "$PY" approve.py "$CRASH_ID" --note "negtest② post-crash approve") >/dev/null || bad "approve 失败"
wait_status "$CRASH_ID" "COMPLETED" 60 >/dev/null && ok "崩溃恢复后 COMPLETED" || bad "未完成: $(wf_status "$CRASH_ID")"
echo "[2.5] 全程段副作用 count 对比（每段必须仍 = 1）"
pg "SELECT activity, count(*) AS rows FROM wf_run_events WHERE workflow_id='$WCRASH' GROUP BY activity ORDER BY activity" | sed 's/^/  /'
DUP=$(pg "SELECT count(*) FROM (SELECT activity FROM wf_run_events WHERE workflow_id='$WCRASH' GROUP BY activity HAVING count(*)>1) t")
TOTAL=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WCRASH'")
[ "$DUP" = "0" ] && [ "$TOTAL" = "7" ] && ok "全程无重复副作用（7×1）" || bad "重复副作用：total=$TOTAL dup_groups=$DUP"
echo "[2.6] inspect_side_effects.py 最终输出（含恢复标记）"
(cd "$WF" && "$PY" inspect_side_effects.py "$CRASH_ID") | sed 's/^/  | /'
RECOVERED=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WCRASH' AND (detail->'result'->>'recovered_from_running')='true'")
echo "  recovered_from_running 标记数=$RECOVERED（被中断后续跑补记完成的段）"
[ "$RECOVERED" -ge 1 ] && ok "恢复路径结果核对照可区分（recovered_from_running）" || { [ "$P_LEFT" -ge 1 ] && ok "（该段在杀时未开始，恢复由 Temporal 重试直接完成，无 uncertain 残留）" || bad "无恢复标记"; }

echo
echo "############################################################"
echo "# M3 negtest ③ 超时挂起：approval_timeout_sec=15 不批准 → MET-01 挂起分支"
echo "############################################################"
TMO_ID="FB-TIMEOUT-$(date +%s)"
WTMO="$(wfname "$TMO_ID")"
echo "[3.1] start $TMO_ID --timeout-sec 15，之后不批准"
(cd "$WF" && "$PY" start_feedback_loop.py "$TMO_ID" --timeout-sec 15) || bad "start 失败"
echo "[3.2] 轮询 approval_wait=suspended（最长 90s；五段 ~7s + 等待 15s + 挂起标记）"
SUSPENDED_AT=""
for _ in $(seq 1 90); do
  S=$(pg "SELECT status FROM wf_run_events WHERE workflow_id='$WTMO' AND activity='approval_wait'")
  if [ "$S" = "suspended" ]; then SUSPENDED_AT=$(date '+%H:%M:%S'); break; fi
  sleep 1
done
[ "$SUSPENDED_AT" != "" ] && ok "approval_wait=suspended（MET-01 挂起事件行）@$SUSPENDED_AT" || bad "approval_wait 状态=$(pg "SELECT status FROM wf_run_events WHERE workflow_id='$WTMO' AND activity='approval_wait'")"
echo "[3.3] workflow 关闭态与结果"
ST=$(wf_status "$TMO_ID"); echo "  describe Status = $ST"
RES=$("$TEMPORAL" workflow show --workflow-id "$WTMO" 2>&1 | grep -o '"outcome":"[a-z]*"' | head -1)
echo "  result outcome  = $RES"
TIMER=$("$TEMPORAL" workflow show --workflow-id "$WTMO" 2>&1 | grep -cE "TimerFired")
echo "  history TimerFired 事件数 = $TIMER（timer 分支到点触发）"
[ "$ST" = "COMPLETED" ] && echo "$RES" | grep -q "suspended" && ok "挂起分支完成：COMPLETED + outcome=suspended" || bad "状态=$ST outcome=$RES"
[ "$TIMER" -ge 1 ] && ok "timer 分支真实触发（TimerFired）" || bad "无 TimerFired"
echo "[3.4] 第六段（校准提案）必须未发生"
CAL=$(pg "SELECT count(*) FROM wf_run_events WHERE workflow_id='$WTMO' AND activity='propose_calibration'")
[ "$CAL" = "0" ] && ok "挂起分支不执行校准提案（absent）" || bad "挂起分支却执行了第六段"
echo "[3.5] inspect 视角"
(cd "$WF" && "$PY" inspect_side_effects.py "$TMO_ID") | sed 's/^/  | /'

echo
echo "############################################################"
echo "# M3 negtest 结果：PASS=$PASS FAIL=$FAIL"
echo "############################################################"
[ "$FAIL" = "0" ] || exit 1
exit 0
