# W4-C3 adversary-gate.yml 参考实现（本地完整实现，待 workflows 权限补推）

> **状态**：本文件为 `.github/workflows/adversary-gate.yml` 的参考副本。
> 实际 workflow 文件位于 CI-Workflows `.github/workflows/adversary-gate.yml`，
> 因当前 cloudbrid-agent App 无 workflows 权限（ADR-0045），暂无法向上游推送。
> rulesets JSON（main-protection.json / org-required-workflows.json）已在本 PR 登记
> adversary check context，待 workflow 文件权限到位后补推即可生效。

## 功能
specs/** 路径 PR 必须含 adversary check（漏配/摘除/跳过即红）；开发路径豁免谓词
由 diff 路径集确定性派生（pipeline/adversary/expected_skip.py，禁人工打标）。

## 关键逻辑
1. 每 PR 运行，产出 check 名 = "adversary"（与 main-protection.json required_status_checks 一致）
2. 调 expected_skip.py judge --paths <diff路径JSON>：
   - dev 路径 → EXPECTED_SKIP=True → 写 success check run
   - specs/** 实质变更 → 检查 adversary check run 是否存在且 survived（fail-closed 阻断）
3. App 令牌（checks:write，INV-02）写回 check run

## 文件位置（本地完整实现）
- `w4-c2/ciw-repo/.github/workflows/adversary-gate.yml`
- `w4-c2/ciw-repo/pipeline/adversary/expected_skip.py`（已推至 CI-Workflows PR #88）
- `w4-c2/ciw-repo/pipeline/adversary/tests/test-expected-skip.sh`

Card: Cloudbird-Software/.github#284
