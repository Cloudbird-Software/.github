#!/usr/bin/env bash
# test-role-dga-incidence.sh —— DGA-A 增量并线对账（IR-0009 卡 A5；DA-ROLE-1..5；ADR-0107）
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REG="$ROOT/governance/role-dga-incidence.yaml"
command -v cygpath >/dev/null 2>&1 && REG=$(cygpath -m "$REG")  # MSYS 本地；CI(ubuntu) 保持原样
fail=0
sec() { awk -v s="## 治理义务（DGA-A 并线）" 'index($0,s){f=1} f{print}' "$1"; }
for role in ROLE-IR ROLE-SPEC ROLE-IMPLEMENT ROLE-ACCEPT; do
  F="$ROOT/docs/agent/$role.md"
  # DA-ROLE-1 唯一节
  n=$(grep -c '## 治理义务（DGA-A 并线）' "$F")
  [ "$n" -eq 1 ] || { echo "FAIL DA-ROLE-1 $role 治理义务节数=$n（须恰 1）"; fail=1; }
  # DA-ROLE-2 节 hash
  want=$(python3 -c "import yaml,sys;print(yaml.safe_load(open('$REG',encoding='utf-8'))['roles']['$role']['section_sha256'])")
  got=$(sec "$F" | python3 -c "import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())")
  [ "$want" = "$got" ] || { echo "FAIL DA-ROLE-2 $role 节 hash 漂移"; fail=1; }
  # DA-ROLE-3 义务关键词
  for ob in $(python3 -c "import yaml;print(' '.join(yaml.safe_load(open('$REG',encoding='utf-8'))['roles']['$role']['obligations']))"); do
    grep -q "\*\*$ob\*\*" "$F" || { echo "FAIL DA-ROLE-3 $role 缺义务: $ob"; fail=1; }
  done
done
# DA-ROLE-4 AGENTS.md N-8 行 + 块 hash
AG="$ROOT/AGENTS.md"
grep -q '分歧必须申报；未经 owner 指令不得向共识收敛' "$AG" || { echo "FAIL DA-ROLE-4 N-8 行缺失"; fail=1; }
want_blk=$(python3 -c "import yaml;print(yaml.safe_load(open('$REG',encoding='utf-8'))['agents_md']['block_sha256'])")
got_blk=$(awk '/<!-- entry-protocol v2 -->/{f=1;next} /<!-- \/entry-protocol -->/{f=0} f' "$AG" | sed '/^[[:space:]]*$/d' | python3 -c "import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())")
[ "$want_blk" = "$got_blk" ] || { echo "FAIL DA-ROLE-4 协议块 hash 漂移（舰队逐字节对账锚）"; fail=1; }
# DA-ROLE-5 占位符零残留
PAT="<LEVEL-"; PAT="${PAT}ADR>"
if grep -q "$PAT" "$ROOT"/docs/agent/ROLE-*.md "$ROOT/AGENTS.md" "$ROOT/governance/role-dga-incidence.yaml" 2>/dev/null; then
  echo "FAIL DA-ROLE-5 占位符残留"; fail=1
fi
if [ "$fail" -eq 0 ]; then echo "OK   role-dga-incidence（DA-ROLE-1..5 全绿）"; fi
exit $fail
