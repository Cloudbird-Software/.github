#!/usr/bin/env python3
"""env-drift.py —— 云内网环境对账引擎（IR-0006 W4-R1 / 卡 #418 / BEH-04 / ADR-0103 决策 8）

drift 引擎泛化：GitHub org 对账（drift-check.sh）→ 环境对账。env-defs 仓
environments/*.yaml=期望态（IFACE-05 声明面）；reports/<env>.yaml=实况快照
（服务器上报落点，骨架期=零漂移基线快照）；本引擎逐环境深 diff——

- 偏差输出 `DRIFT <env> <字段路径> 期望=… 实况=…`（含偏差面，GM-1 issue 体）
- owner-fill 骨架值跳过（期望态未填真值≠漂移——声明骨架期合法）
- scope 旋钮（AC-8b / R3）：检测面=policy/env-drift.yaml scope（dev/staging）；
  scope 外环境（如 prod）输出 SKIP 行不对账——prod 不在检测面，scope 断言
  进日志（对账 run 日志进账本）
- 审计（INV-12）：每轮经 butler-audit.sh 发射 AUDIT 行+schema v1 影子
  （BUTLER_SHADOW_FILE 可注入；持久化 env-ledger 分支=drill relink 面）

用法:
  python3 governance/env-drift.py                 # 对账（clone env-defs 真源）
  ENV_DEFS_DIR=<dir> python3 governance/env-drift.py   # 测试注入（本地目录）
env:
  GH_TOKEN      必填（clone env-defs 私有仓；ENV_DEFS_DIR 注入时免）
  BUTLER_TRIGGER / BUTLER_CARD / BUTLER_TENANT   影子 subject（drill 绑卡）
退出码: 0=对账绿（零漂移）| 1=漂移检出（GM-1 报警面）| 2=基础设施故障
"""
import importlib.util
import json
import os
import subprocess
import sys

import yaml

DIR = os.path.dirname(os.path.abspath(__file__))
ENV_DEFS_REPO = "https://github.com/Cloudbird-Software/env-defs.git"
POLICY = os.path.join(DIR, "policy", "env-drift.yaml")
TRIGGER = os.environ.get("BUTLER_TRIGGER") or "manual"
# 上报元数据面（实况快照自描述字段）——非环境状态，不对账
REPORT_META = {"reported_at", "reported_by", "schema_version"}


def _audit(outcome, actions):
    """审计代发（butler-audit.sh CLI：AUDIT 行 + schema v1 影子；同 feishu-sync 模式）。"""
    shadow = os.environ.get("BUTLER_SHADOW_FILE") \
        or os.path.join(DIR, "env", "shadow-evidence.jsonl")
    os.makedirs(os.path.dirname(shadow), exist_ok=True)
    payload = json.dumps(actions, ensure_ascii=False)
    if len(payload.encode("utf-8")) > 4096:  # INV-06：超限拒写——降级只记结论
        payload = json.dumps({k: v for k, v in actions.items() if k != "drifts"},
                             ensure_ascii=False)
    if len(payload.encode("utf-8")) > 4096:
        payload = ""
    env = {**os.environ, "BUTLER_SHADOW_FILE": shadow,
           "BUTLER_SHADOW_PAYLOAD": payload}
    r = subprocess.run(["bash", os.path.join(DIR, "butler-audit.sh"),
                        "env-drift", TRIGGER, outcome,
                        json.dumps(actions, ensure_ascii=False)],
                       env=env, check=False)
    return r.returncode


def load_yaml(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def is_skeleton(value):
    """owner-fill 骨架值判定（期望态未填真值——声明骨架期合法，不算漂移）。"""
    return isinstance(value, str) and "owner-fill" in value


# @w4r1-pure-begin —— 对账纯函数区（governance/tests/test-env-drift.sh 离线直查）

def diff_env(want, have, prefix=""):
    """期望态 × 实况深 diff → [(字段路径, 期望, 实况)]。

    - dict 递归；list 逐元素递归（长度差=整体漂移行）
    - 期望值含 owner-fill → 跳过（骨架未填≠漂移）
    - 实况缺失字段 → (path, want, None)
    """
    out = []
    if is_skeleton(want):
        return out
    if isinstance(want, dict) and isinstance(have, dict):
        for k in want:
            out += diff_env(want[k], have.get(k), f"{prefix}.{k}" if prefix else k)
        return out
    if isinstance(want, list) and isinstance(have, list):
        if len(want) != len(have):
            out.append((prefix or "(root)", want, have))
            return out
        for i, (w, h) in enumerate(zip(want, have)):
            out += diff_env(w, h, f"{prefix}[{i}]")
        return out
    if want != have:
        out.append((prefix or "(root)", want, have))
    return out


def plan_check(environments, reports, scope):
    """环境对账计划（纯函数）：scope 内逐环境 diff，scope 外 SKIP。

    environments: {env 名: 期望 dict（environments/<name>.yaml 内容）}
    reports:      {env 名: 实况 dict（reports/<name>.yaml 内容；缺=无快照）}
    scope:        [env 名]（检测面，policy/env-drift.yaml——AC-8b R3 旋钮）
    返回 {"drifts": [(env, path, want, have)], "skipped": [env], "checked": [env]}
    """
    drifts, checked = [], []
    for env in sorted(environments):
        if env not in scope:
            continue  # scope 外环境由 main 输出 SKIP（R3：prod 不在检测面）
        checked.append(env)
        want = environments[env]
        have = reports.get(env)
        if have is None:
            drifts.append((env, "(report)", "实况快照缺失", None))
            continue
        for path, w, h in diff_env(want, have):
            drifts.append((env, path, w, h))
    skipped = [e for e in sorted(environments) if e not in scope]
    return {"drifts": drifts, "skipped": skipped, "checked": checked}
# @w4r1-pure-end


def main():
    import tempfile
    actions = {"scope": [], "checked": 0, "drifts": 0}
    try:
        policy = load_yaml(POLICY)
        scope = policy.get("scope") or []
        if not scope:
            print("FATAL policy/env-drift.yaml 缺 scope（检测面旋钮——AC-8b）", file=sys.stderr)
            return 2
        actions["scope"] = scope
        # 真源拉取：ENV_DEFS_DIR 注入（测试）或 clone（生产）
        envdir = os.environ.get("ENV_DEFS_DIR")
        tmp = None
        if not envdir:
            if not os.environ.get("GH_TOKEN"):
                print("FATAL 需要环境变量 GH_TOKEN（clone env-defs 真源）", file=sys.stderr)
                return 2
            tmp = tempfile.mkdtemp(prefix="envdefs-")
            r = subprocess.run(["git", "clone", "--depth", "1",
                                f"https://x-access-token:{os.environ['GH_TOKEN']}"
                                f"@{ENV_DEFS_REPO[len('https://'):]}",
                                tmp], capture_output=True, text=True)
            if r.returncode != 0:
                print(f"FATAL env-defs clone 失败: {r.stderr[:200]}", file=sys.stderr)
                return 2
            envdir = tmp
        environments = {}
        for fn in sorted(os.listdir(os.path.join(envdir, "environments"))):
            if fn.endswith(".yaml"):
                name = fn[:-5]
                environments[name] = load_yaml(os.path.join(envdir, "environments", fn))
        reports = {}
        rep_dir = os.path.join(envdir, "reports")
        if os.path.isdir(rep_dir):
            for fn in sorted(os.listdir(rep_dir)):
                if fn.endswith(".yaml"):
                    reports[fn[:-5]] = load_yaml(os.path.join(rep_dir, fn))
        plan = plan_check(environments, reports, scope)
        # scope 断言（AC-8b）：检测面边界进日志（对账 run 日志进账本）
        print(f"OK    检测面 scope={scope}（policy/env-drift.yaml，R3 旋钮）")
        for env in plan["skipped"]:
            print(f"SKIP  {env}：scope 外不对账（R3 旋钮——prod 不在检测面，AC-8b）")
        if plan["skipped"]:
            print(f"OK    scope 断言：排除面={plan['skipped']}（检测面幂等边界）")
        actions["checked"] = len(plan["checked"])
        actions["drifts"] = len(plan["drifts"])
        for env, path, w, h in plan["drifts"]:
            print(f"DRIFT {env} {path} 期望={w!r} 实况={h!r}（BEH-04：实况与期望态漂移）")
        if not plan["drifts"]:
            print(f"OK    环境对账零漂移（{len(plan['checked'])} 环境 × 期望态/实况深 diff）")
        if tmp:
            subprocess.run(["rm", "-rf", tmp], check=False)
        if plan["drifts"]:
            print(f"结果: {len(plan['drifts'])} 项环境漂移。修复: env-defs 仓上报面修齐或改期望态（PR）")
            rc = _audit("drift-detected", actions)
            return rc if rc else 1
        rc = _audit("ok", actions)
        return rc if rc else 0
    except Exception as e:  # noqa: BLE001 —— infra 面 fail-closed（exit 2）
        print(f"FATAL {e}", file=sys.stderr)
        rc = _audit("infra-fail", {**actions, "error": str(e)[:300]})
        return rc if rc else 2


if __name__ == "__main__":
    raise SystemExit(main())
