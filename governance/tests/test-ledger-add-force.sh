#!/usr/bin/env bash
# test-ledger-add-force.sh —— *-ledger 落盘 git add -f 执法自测（IR-0006 残留 #475/#476）
#
# 背景：影子账本真源在 *-ledger 分支，工作树副本被 .gitignore 忽略——
# workflow 落盘步 `git add` 不带 -f 时被 ignore 拦截 exit 1，push 永不执行，
# 对应源恒 0（butler-reconcile 曾连续 4 次红，butler-ledger 分支从未建出）。
# 本测试机械扫描全部 workflow：凡 add 的目标路径命中 .gitignore 字面路径，
# add 行必须含 -f/--force；另做真实 git 行为复现（无 -f 必失败）锚定判定。
# 用法: bash governance/tests/test-ledger-add-force.sh（gate.yml 自动纳入）
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

# ---- 静态扫描：workflow 中 add gitignore 路径必须 -f ----
python3 - "$DIR" <<'PYEOF' || FAILS=$((FAILS+1))
import glob, os, re, sys

root = sys.argv[1]
# .gitignore 字面路径（无通配符）——忽略注释/空行/否定规则
ignored = set()
with open(os.path.join(root, ".gitignore"), encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("!") or any(c in line for c in "*?[]"):
            continue
        ignored.add(line.lstrip("/"))

bad = 0
for wf in sorted(glob.glob(os.path.join(root, ".github/workflows/*.yml"))
                 + glob.glob(os.path.join(root, ".github/workflows/*.yaml"))):
    text = open(wf, encoding="utf-8").read()
    # 同文件内变量赋值（如 SHADOW="governance/.../shadow-evidence.jsonl"）
    vars_ = dict(re.findall(r'^\s*([A-Z_][A-Z0-9_]*)="([^"\n]+)"', text, re.M))
    for m in re.finditer(r'^\s*git\s+[^\n]*\badd\b([^\n]*)$', text, re.M):
        line, args = m.group(0), m.group(1)
        # 展开 "$VAR" / ${VAR} 引用
        targets = set(re.findall(r'["\']?([\w./-]+|"\$\{?[A-Z_][A-Z0-9_]*\}?")["\']?', args))
        resolved = set()
        for t in targets:
            t = t.strip('"\'')
            vm = re.fullmatch(r'\$\{?([A-Z_][A-Z0-9_]*)\}?', t)
            if vm:
                resolved.add(vars_.get(vm.group(1), ""))
            elif t and not t.startswith("-"):
                resolved.add(t)
        hit = [p for p in resolved if p in ignored]
        if hit and not re.search(r'(?:^|\s)(?:-f|--force)(?:\s|$)', line):
            print(f"FAIL  {os.path.relpath(wf, root)}: git add 命中 .gitignore 路径 {hit} 但缺 -f（ledger 落盘将被 ignore 拦截）")
            print(f"      {line.strip()}")
            bad += 1
if bad == 0:
    print("PASS  全部 workflow：gitignore 内路径的 git add 均带 -f")
else:
    sys.exit(1)
PYEOF
[[ $? -eq 0 ]] || FAILS=$((FAILS+1))

# ---- 行为锚定：真实 git 复现「无 -f 必失败」（判定不依赖静态正则自洽） ----
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/rep/governance/butler"
cp "$DIR/.gitignore" "$TMP/rep/"
( cd "$TMP/rep" && git init -q . && git config user.email t@t && git config user.name t
  : > governance/butler/shadow-evidence.jsonl
  git add governance/butler/shadow-evidence.jsonl 2>/dev/null )
if [[ $? -ne 0 ]]; then
  pass "行为锚定：gitignore 路径 git add（无 -f）真实失败——测试前提成立"
else
  fail "行为锚定失效：无 -f 竟可 add（.gitignore 变更？需复查本测试前提）"
fi
( cd "$TMP/rep" && git add -f governance/butler/shadow-evidence.jsonl ) 2>/dev/null \
  && pass "行为锚定：-f 可 add（修复路径有效）" \
  || fail "行为锚定：-f 亦失败（异常，需人工复查）"

# ---- 修复面直接断言（当前已知落盘点，防扫描器静默漏检） ----
for wfsrc in "butler-reconcile.yml:governance/butler/shadow-evidence.jsonl" \
             "feishu-drill.yml:governance/feishu/shadow-evidence.jsonl" \
             "env-drift.yml:governance/env/shadow-evidence.jsonl" \
             "feedback-edge.yml:governance/feedback/shadow-evidence.jsonl"; do
  wf="${wfsrc%%:*}"; path="${wfsrc#*:}"
  f="$DIR/.github/workflows/$wf"
  [[ -f "$f" ]] || continue
  if grep -q "^governance/.*shadow-evidence.jsonl$" <(grep -v '^#' "$DIR/.gitignore") && \
     grep -q 'git -C ledger add -f' "$f"; then
    pass "$wf 落盘 add -f 在位（$path）"
  else
    fail "$wf 落盘 add -f 缺失（$path）"
  fi
done

if [[ $FAILS -gt 0 ]]; then
  echo "RESULT: $FAILS 项失败"
  exit 1
fi
echo "RESULT: 全部通过"
