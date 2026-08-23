#!/usr/bin/env bash
# register-verifier-app.sh —— 验证者 APP 安装信息落盘（ISSUE-263 / ADR-0080）
#
# 前提：
#   - AG-1/ADR-0056/ADR-0061 修订 ADR 已合并（时序闸，W2-C1 AC-2）
#   - owner 已在组织设置页手动创建 verifier-app 并安装到目标仓库
#   - 运行者持有可读取 /orgs/<org>/installations 的令牌（GOVERNANCE_TOKEN 或等效 org admin PAT）
#
# 用法：
#   cd <.github repo root>
#   GH_TOKEN=<org-admin-pat> bash scripts/register-verifier-app.sh
#
# 行为：
#   - 幂等查询 verifier-app 的 App ID、Client ID、组织级 installation ID 及仓库清单
#   - 校验权限范围与 governance/expected-state.json 声明一致，禁止 workflows/administration
#   - 将 id/client_id/installation_id/repositories 写回 expected-state.json
#   - 若 App 未创建/未安装，显式失败并给出下一步

set -euo pipefail

ORG="${ORG:-Cloudbird-Software}"
APP_SLUG="${APP_SLUG:-verifier-app}"
EXPECTED="${EXPECTED:-governance/expected-state.json}"
API="${CB_GITHUB_API:-https://api.github.com}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "错误：需要 GH_TOKEN（可读取 /orgs/<org>/installations 的 org admin 级令牌）" >&2
  exit 1
fi

if [[ ! -f "$EXPECTED" ]]; then
  echo "错误：找不到 $EXPECTED（请在 .github 仓库根目录运行）" >&2
  exit 1
fi

api_get() {
  local path="$1"
  curl -sS -H "Authorization: Bearer $GH_TOKEN" \
       -H "Accept: application/vnd.github+json" \
       "$API$path"
}

# ---------- JSON 降级工具：优先 python（Windows Git Bash 通常无 jq） ----------
PY_BIN=""
for _cand in python3 python; do
  if command -v "$_cand" >/dev/null 2>&1 && "$_cand" -c 'print(1)' >/dev/null 2>&1; then
    PY_BIN="$_cand"; break
  fi
done
if [[ -z "$PY_BIN" ]]; then
  echo "错误：需要 python3/python 以解析/写回 JSON" >&2
  exit 1
fi

json_field() {
  local json="$1" key="$2"
  "$PY_BIN" -c 'import json,sys
j=json.loads(sys.argv[1])
print(j.get(sys.argv[2],"") if isinstance(j,dict) else "")' "$json" "$key"
}

json_array_select() {
  local json="$1" arr="$2" mkey="$3" mval="$4" rkey="$5"
  "$PY_BIN" -c 'import json,sys
j=json.loads(sys.argv[1])
for it in j.get(sys.argv[2],[]):
    if str(it.get(sys.argv[3],"")) == sys.argv[4]:
        print(it.get(sys.argv[5],"")); break' "$json" "$arr" "$mkey" "$mval" "$rkey"
}

json_repo_names() {
  local json="$1"
  "$PY_BIN" -c 'import json,sys
j=json.loads(sys.argv[1])
print("\n".join(r["name"] for r in j.get("repositories",[])))' "$json"
}

# ---------- 1) 查询 App 公共信息 ----------
echo "==> 查询 App '$APP_SLUG' 公共信息 ..."
APP_JSON=$(api_get "/apps/$APP_SLUG")
APP_ID=$(json_field "$APP_JSON" "id")
CLIENT_ID=$(json_field "$APP_JSON" "client_id")

if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
  MSG=$(json_field "$APP_JSON" "message")
  echo "错误：未找到 App '$APP_SLUG'${MSG:+：$MSG}。" >&2
  echo "请让 owner 在浏览器中打开 scripts/create-verifier-app.html 完成创建。" >&2
  exit 1
fi
echo "    App ID: $APP_ID"
echo "    Client ID: $CLIENT_ID"

# ---------- 2) 校验权限范围 ----------
echo "==> 校验权限范围 ..."
PERM_CHECK=$("$PY_BIN" -c 'import json,sys
app=json.loads(sys.argv[1])
actual=app.get("permissions",{})
expected={"contents":"write","issues":"write","pull_requests":"write","metadata":"read"}
forbidden={"workflows","administration"}
errs=[]
for k,v in expected.items():
    if actual.get(k)!=v:
        errs.append(f"缺少/等级不符: {k}={actual.get(k)} (期望 {v})")
for k in actual:
    if k in forbidden:
        errs.append(f"禁止权限: {k}")
if errs:
    print("\n".join(errs))
    sys.exit(1)
print("OK")' "$APP_JSON")
if [[ "$PERM_CHECK" != "OK" ]]; then
  echo "错误：权限范围校验未通过：" >&2
  echo "$PERM_CHECK" >&2
  exit 1
fi
echo "    权限范围 OK（contents:write / issues:write / pull_requests:write / metadata:read；无 workflows/administration）"

# ---------- 3) 查询组织级 installation ----------
echo "==> 查询 $ORG 的 installations ..."
INST_JSON=$(api_get "/orgs/$ORG/installations?per_page=100")
MSG=$(json_field "$INST_JSON" "message")
if [[ -n "$MSG" ]]; then
  echo "错误：无法读取组织 installations：$MSG" >&2
  echo "当前 GH_TOKEN 权限不足（需 org admin 级 PAT，cloudbrid-agent App 令牌会被 403）。" >&2
  exit 1
fi

INSTALLATION_ID=$(json_array_select "$INST_JSON" "installations" "app_id" "$APP_ID" "id")
if [[ -z "$INSTALLATION_ID" || "$INSTALLATION_ID" == "null" ]]; then
  echo "错误：App '$APP_SLUG' 已存在（id=$APP_ID），但尚未安装到 $ORG。" >&2
  echo "请在组织 Settings → GitHub Apps → verifier-app → Configure 中安装并授权仓库。" >&2
  exit 1
fi
echo "    Installation ID: $INSTALLATION_ID"

# ---------- 4) 查询 installation 仓库清单 ----------
echo "==> 查询 installation #$INSTALLATION_ID 的仓库清单 ..."
REPOS_JSON=$(api_get "/user/installations/$INSTALLATION_ID/repositories?per_page=100")
REPOS=$(json_repo_names "$REPOS_JSON")
if [[ -z "$REPOS" ]]; then
  echo "警告：installation #$INSTALLATION_ID 未授权任何仓库（请至少授权 .github 与 holdout）" >&2
fi
echo "    已授权仓库："
printf '%s\n' "$REPOS" | sed 's/^/      - /'

# ---------- 5) 幂等写回 expected-state.json ----------
echo "==> 写回 $EXPECTED ..."
"$PY_BIN" - "$EXPECTED" "$APP_ID" "$CLIENT_ID" "$INSTALLATION_ID" "$APP_SLUG" "$REPOS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

app = data.setdefault("verifier_app", {})
old = json.dumps(app, sort_keys=True)

app["id"] = int(sys.argv[2])
app["client_id"] = sys.argv[3] if sys.argv[3] != "null" else None
app["installation_id"] = int(sys.argv[4])
app["slug"] = sys.argv[5]
app["repositories"] = sys.argv[6].split("\n") if sys.argv[6] else []

new = json.dumps(app, sort_keys=True)
if old == new:
    print("INFO  expected-state.json 已是最新，无需修改")
    sys.exit(0)

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("OK    已更新 verifier_app 信息")
PY

echo "==> 完成。下一步："
echo "    1. git diff $EXPECTED 确认回填字段"
echo "    2. 提交 PR 走 C1 治理变更路径（引用 ADR-0080 / ISSUE-263）"
