#!/usr/bin/env bash
# test-providers-schema.sh —— providers.yaml 信任分级 schema 执法（IR-0010 卡 B1 门禁的持续形态；FR-08）
# 谓词：①每条目有 trust_level ∈ E1|E2|E3；②data_classes_allowed ⊆ {D-公开,D-内部,D-客户敏感}；
#       ③D-客户敏感 仅允许出现在 kind=repo-private 条目（宪法触发器前禁入）。
set -u
F="$(dirname "$0")/../providers.yaml"
fail=0
while IFS= read -r -d '' block; do
  name=$(printf '%s' "$block" | sed -n 's/^  - name: \(\S\+\).*/\1/p' | head -1)
  [ -z "$name" ] && continue
  tl=$(printf '%s' "$block" | grep -oE 'trust_level: (E1|E2|E3)' | head -1 | cut -d' ' -f2)
  if [ -z "$tl" ]; then echo "FAIL $name 缺 trust_level"; fail=1; fi
  bad_dc=$(printf '%s' "$block" | grep -oE 'data_classes_allowed: .*' | grep -vE '^data_classes_allowed: \[(D-公开|D-内部|D-客户敏感|, )*\]' || true)
  cust=$(printf '%s' "$block" | grep -c 'D-客户敏感' || true)
  kind=$(printf '%s' "$block" | grep -oE 'kind: \S+' | head -1 | cut -d' ' -f2)
  if [ "$cust" -gt 0 ] && [ "$kind" != "repo-private" ]; then
    echo "FAIL $name 含 D-客户敏感但 kind=$kind（宪法触发器前禁入）"; fail=1
  fi
done < <(awk 'BEGIN{RS="  - name: "} NR>1{print RS $0 "\0"}' "$F" | tr -d '\n' | awk 'BEGIN{RS="\\0"}{print}')
# 逐块法（可移植）：python 兜底执法
python3 - "$F" <<'PYEOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
bad = 0
for e in d["entries"]:
    n = e.get("name")
    tl = e.get("trust_level")
    if tl not in ("E1", "E2", "E3"):
        print(f"FAIL {n} trust_level 非法: {tl!r}"); bad = 1
    dcs = e.get("data_classes_allowed") or []
    if not set(dcs) <= {"D-公开", "D-内部", "D-客户敏感"}:
        print(f"FAIL {n} data_classes_allowed 非法: {dcs}"); bad = 1
    if "D-客户敏感" in dcs and e.get("kind") != "repo-private":
        print(f"FAIL {n} 含 D-客户敏感但 kind={e.get('kind')}（宪法触发器前禁入）"); bad = 1
sys.exit(bad)
PYEOF
[ $? -ne 0 ] && fail=1
if [ "$fail" -eq 0 ]; then echo "OK   providers schema（trust_level/data_classes_allowed 全绿）"; fi
exit $fail
