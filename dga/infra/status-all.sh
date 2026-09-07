#!/usr/bin/env bash
# DGA-INFRA 本机全栈巡检——owner 一键看状态（GREEN/RED + 证据指针）
cd "$(dirname "$0")"
echo "===== DGA-INFRA 全栈状态 $(date '+%F %T') ====="
declare -A S=(
  [postgres]="services/postgres/health.sh"
  [temporal]="services/temporal/health.sh"
  [opa]="services/opa/health.sh"
  [openbao]="services/openbao/health.sh"
  [control-plane]="services/scripts/start-control-plane.sh --status 2>/dev/null || curl -s -m 3 http://127.0.0.1:8090/healthz >/dev/null && echo ok || echo down"
  [litellm]="curl -s -m 3 http://127.0.0.1:4000/health/liveliness >/dev/null && echo ok || echo down"
  [action-registry]="curl -s -m 3 http://127.0.0.1:8091/healthz >/dev/null && echo ok || echo down"
  [workflow-worker]="[ -f services/workflow-worker/worker.pid ] && (tasklist //FI \"PID eq $(cat services/workflow-worker/worker.pid 2>/dev/null)\" 2>/dev/null | grep -q python && echo ok || echo down) || echo down"
)
for k in postgres temporal opa openbao control-plane litellm action-registry workflow-worker; do
  r=$(eval "${S[$k]}" 2>/dev/null | tail -1)
  case "$r" in *ok*|*GREEN*|*0*|*accepting*|*active*|*200*|*alive*) st="GREEN";; *down*|"") st="RED  ";; *) st="?????";; esac
  printf "%-18s %s  (%s)\n" "$k" "$st" "$r"
done
echo
echo "一键启动全部：for s in services/postgres/start.sh services/temporal/start.sh services/opa/start.sh services/openbao/start.sh services/scripts/start-control-plane.sh services/scripts/start-litellm.sh services/scripts/start-action-registry.sh services/scripts/start-workflow-worker.sh; do bash \$s; done"
echo "负面测试矩阵：bash gov-infra-repo/controls/negtest_m0.py|m1|m2|m3|m4_ar（详见各 md）"
