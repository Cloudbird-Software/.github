# 验证者 APP（verifier-app）创建与安装 Runbook

> 关联：ISSUE-263 W2-C1（.github#273）、ADR-0076、ADR-0080、ADR-0081、ADR-0056 DECISION-02、ADR-0061、AG-1 修订。  
> **时序闸**：AG-1/ADR-0056/ADR-0061 修订 ADR 全部合并前，不得实施安装（W2-C1 AC-2）。

## 1. 为什么必须 owner 手动创建

GitHub App 没有 API 创建接口（manifest flow 只能预填、最终提交仍需组织 owner 在浏览器中确认）。因此本卡只交付：

- 预填 manifest 的 HTML 表单：`scripts/create-verifier-app.html`
- 纯 JSON manifest：`scripts/verifier-app-manifest.json`
- 安装后回填脚本：`scripts/register-verifier-app.sh`
- 本 Runbook

## 2. owner 创建 App

1. 使用已登录 **Cloudbird-Software 组织 owner** 账号的浏览器，打开仓库内文件：  
   `scripts/create-verifier-app.html`（本地双击或用 `python -m http.server` 托管后访问）。
2. 页面会自动 POST 到：  
   `https://github.com/organizations/Cloudbird-Software/settings/apps/new`
3. 在 GitHub 页面确认信息，点击 **Create GitHub App**。

### 2.1 创建后务必核对的字段

| 字段 | 期望值 |
|---|---|
| Name | `verifier-app` |
| Homepage URL | `https://github.com/Cloudbird-Software`（占位，可改） |
| Webhook | 可关闭或填占位 URL（本 App 不依赖 webhook） |
| Repository permissions | `contents:write`、`issues:write`、`pull_requests:write`、`metadata:read` |
| 禁止权限 | 必须**没有** `workflows`、`administration` |
| Where can this GitHub App be installed | `Only on this account`（组织内专用） |

> 最小权限原则：验证者 APP 只用于测试/验证路径写权（suite/、holdout、卡测试），不得改动 CI workflow 或组织管理配置。

## 3. owner 安装 App

创建后，进入组织 Settings → GitHub Apps → `verifier-app` → **Install**。

建议至少授权以下仓库：

- `.github`（治理期望状态落盘）
- `holdout`（holdout 测试挂载，ADR-0056 DECISION-02）
- 需要验证者 APP 参与测试判定的实现仓库（如 `template-service` 等）

> 注意：当前 `cloudbrid-agent` 被**禁止**挂载 `holdout`；验证者 APP 是 holdout 的唯一合法写入主体。

## 4. 运行登记脚本回填 expected-state.json

脚本需要可读取 `/orgs/Cloudbird-Software/installations` 的令牌（org admin PAT / `GOVERNANCE_TOKEN`）。`cloudbrid-agent` 的安装令牌会被 403，这是预期边界。

```bash
cd <.github 仓库根目录>
export GH_TOKEN=<org-admin-pat>
bash scripts/register-verifier-app.sh
```

脚本会：

1. 查询 `verifier-app` 的 App ID、Client ID。
2. 校验权限范围与 `governance/expected-state.json` 声明一致。
3. 查询组织级 installation ID 与已授权仓库清单。
4. **幂等**写回 `governance/expected-state.json`：
   - `verifier_app.id`
   - `verifier_app.client_id`
   - `verifier_app.installation_id`
   - `verifier_app.repositories`

若 App 未创建或未安装，脚本会显式失败并提示下一步。

## 5. 提交治理变更 PR

`expected-state.json` 被修改后，需走 C1 治理变更路径：

- PR 标题示例：`governance(ISSUE-263): W2-C1 回填 verifier-app 安装信息 (#273)`
- Body 引用：`Closes Cloudbird-Software/.github#273`
- **必须引用 ADR-NNNN**（如 ADR-0080 / ADR-0081 / ADR-0076 / ADR-0056 / ADR-0061），否则 `gate` / `org-gate` 的 `adr-required` 会判红。
- owner-only review，过 gate 后合并

## 6. 验证清单（AC 证据）

- [ ] `scripts/create-verifier-app.html` 可在浏览器中打开并跳转 GitHub 创建页
- [ ] App 详情页权限仅含 `contents:write`、`issues:write`、`pull_requests:write`、`metadata:read`
- [ ] App 详情页**没有** `workflows`、`administration`
- [ ] `bash scripts/register-verifier-app.sh` 成功，且 `git diff` 显示 `id/client_id/installation_id/repositories` 已回填
- [ ] `governance/drift-check.sh` 运行后，验证者 APP 的 holdout 挂载断言正常输出（未安装时输出 INFO，安装并挂载 holdout 后输出 OK）
