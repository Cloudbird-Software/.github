#!/usr/bin/env python3
"""verify_gate.py —— 周演习的独立验证步骤（与样本库分离；ADR-0069 / .github#223）

职责单一：断言"该缺陷应触发关卡 X 失败"。不读样本库（关卡名由调用方传参），
不做注入——注入者与判定者分离，被审者不能组织对自己的审计的同款精神。

判定（红=演习成功——关卡活着；绿=演习失败——关卡死了，宪法 §4B）:
  RED          目标关卡 check conclusion == failure
  GREEN        目标关卡 success（→ 调用方开 P0 + 该关卡标 suspect）
  NO-SURFACE   该 SHA 上没有任何 check-run（目标仓 workflow 不跑 push 分支——已知
               局限，如实记录；调用方决定是否走 draft PR 面补救）
  MISSING-GATE / TIMEOUT   中间态，不计入红率分母（诚实口径，防"没看到=绿"）

check-runs 数据源: GitHub API（GH_TOKEN 必须提供）或 --checkruns-file
（测试注入用，不碰网络——选样随机性/判定逻辑可离线自测）。
"""
import argparse
import json
import os
import sys
import time
import urllib.request

API = "https://api.github.com"


def fetch_check_runs(org, repo, sha, token):
    req = urllib.request.Request(
        f"{API}/repos/{org}/{repo}/commits/{sha}/check-runs?per_page=100",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                 "User-Agent": "seed-drill-verify"})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or b"{}").get("check_runs", [])


def match_gate(checks, gate):
    """关卡 check 匹配: 精确名优先；子串兜底须唯一（歧义=MISSING-GATE，不猜）。"""
    exact = [c for c in checks if c.get("name") == gate]
    if exact:
        return exact
    sub = [c for c in checks if gate in c.get("name", "")]
    return sub if len(sub) == 1 else []


def verdict(org, repo, sha, gate, deadline_s, token, offline_file):
    checks, waited = [], 0.0
    # 静默期（可注入缩短——自测试用）：空 check 需过静默期才判 NO-SURFACE（push 后
    # workflow 排队中也会呈现为空，立即判=假阴性）；目标关卡缺席判定取其半
    grace = int(os.environ.get("DRILL_VERIFY_GRACE_S", "120"))
    while True:
        if offline_file:
            checks = json.load(open(offline_file, encoding="utf-8")).get("check_runs", [])
        else:
            checks = fetch_check_runs(org, repo, sha, token)
        hits = match_gate(checks, gate)
        if hits and hits[0].get("status") == "completed":
            c = hits[0]
            v = "RED" if c.get("conclusion") == "failure" else "GREEN"
            return {"verdict": v, "check_name": c.get("name"),
                    "conclusion": c.get("conclusion"), "waited_s": int(waited),
                    "checks_seen": {x.get("name"): x.get("conclusion")
                                    for x in checks if x.get("status") == "completed"}}
        if not checks:
            # 一个 check 都没有：须先过静默期再判 NO-SURFACE
            if waited >= grace:
                return {"verdict": "NO-SURFACE", "check_name": None, "conclusion": None,
                        "waited_s": int(waited), "checks_seen": {}}
        elif not hits and waited >= max(grace // 2, 1):
            # 有其他 check 而目标关卡迟迟未现身 → 名字漂移，不硬等
            return {"verdict": "MISSING-GATE", "check_name": None, "conclusion": None,
                    "waited_s": int(waited),
                    "checks_seen": {x.get("name"): x.get("status") for x in checks}}
        if waited >= deadline_s:
            return {"verdict": "TIMEOUT", "check_name": gate, "conclusion": None,
                    "waited_s": int(waited),
                    "checks_seen": {x.get("name"): x.get("conclusion")
                                    for x in checks if x.get("status") == "completed"}}
        time.sleep(0.05 if offline_file else 20)  # 离线注入模式快进（自测试）
        waited += 0.05 if offline_file else 20


def main():
    ap = argparse.ArgumentParser(description="演习独立验证：断言关卡 X 应红")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--sha", required=True)
    ap.add_argument("--gate", required=True, help="预期触发失败的关卡 check 名")
    ap.add_argument("--org", default=os.environ.get("DRILL_ORG", "Cloudbird-Software"))
    ap.add_argument("--timeout", type=int, default=600, help="轮询上限秒（默认 600）")
    ap.add_argument("--checkruns-file", default=None,
                    help="离线注入 check-runs JSON（自测试用；设置时不访问网络）")
    a = ap.parse_args()
    token = os.environ.get("GH_TOKEN", "")
    if not a.checkruns_file and not token:
        print("::error::缺 GH_TOKEN（API 模式必需；离线测试用 --checkruns-file）", file=sys.stderr)
        raise SystemExit(2)
    out = verdict(a.org, a.repo, a.sha, a.gate, a.timeout, token, a.checkruns_file)
    print(json.dumps(out, ensure_ascii=False))
    # RED=演习成功（0）；GREEN=演习失败（1，调用方须开 P0）；中间态（3）不装绿
    raise SystemExit({"RED": 0, "GREEN": 1}.get(out["verdict"], 3))


if __name__ == "__main__":
    main()
