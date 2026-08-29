#!/usr/bin/env python3
"""drill.py —— 周种子缺陷演习引擎（宪法 §4B/§6 / ADR-0069 / .github#223 W4-C4）

子命令（全部 fail-closed：任何失败非零退出，绝不静默降级为"通过"）:
  select   随机选缺陷样本 + 随机目标仓（--seed 注入可复现——测试与事后复盘）
  inject   向目标仓开演习分支（只开分支不开 PR）注入缺陷，输出 head_sha
  decode   owner 审阅用：解码样本缺陷内容（ADR-0069 决策 1 样本库 owner 直管）
  record   演习记录追加 governance/drill/history.jsonl（append-only 台账=dashboard 数据源）
  redrate  聚合红率（目标 ≈100%，AC-4）+ 样本难度按周分布（防"为演习写代码"Goodhart）

红绿判定不在本文件——verify_gate.py 与样本库分离（独立验证步骤，ADR-0069
决策 2"注入者与判定者分离"）。注入物只落在演习分支（隔离执行，不进 agent
工作区，ADR-0069 风险缓解）；分支验后即删。
"""
import argparse
import base64
import hashlib
import json
import os
import random
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

try:
    import yaml
except ImportError:  # pragma: no cover
    print("FATAL 缺少 PyYAML（CI 预装；本地 pip install pyyaml）", file=sys.stderr)
    raise SystemExit(2)

ORG = os.environ.get("DRILL_ORG", "Cloudbird-Software")
OWNER = "randypanding"  # 样本库唯一审批人（org owner，ADR-0069 决策 1）
DIFFICULTIES = ("easy", "medium", "hard")
SCOPES = ("org", "github")
EXCLUDED_TARGETS = ("holdout",)  # owner 直管封存面（ADR-0056 隔离不变量）——演习分支不进
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def die(msg, code=2):
    print(f"::error::{msg}", file=sys.stderr)
    raise SystemExit(code)


def validate_samples(doc):
    """样本库 schema 校验（AC-2：owner 审批记录 + 预期关卡 ID 必须逐条在）。

    返回错误列表（空=合法）。tests/test-samples.sh 与 select/inject 共用本函数——
    校验逻辑单一实现，防"测试过而引擎放行"的分叉。
    """
    errs = []
    if not isinstance(doc, dict) or not isinstance(doc.get("samples"), list) or not doc["samples"]:
        return ["顶层缺非空 samples 列表"]
    seen = set()
    for i, s in enumerate(doc["samples"]):
        w = f"samples[{i}]"
        if not isinstance(s, dict):
            errs.append(f"{w}: 非对象"); continue
        sid = s.get("id", "")
        if not ID_RE.match(str(sid)):
            errs.append(f"{w}: id 非法: {sid!r}")
        if sid in seen:
            errs.append(f"{w}: id 重复: {sid}")
        seen.add(sid)
        if s.get("difficulty") not in DIFFICULTIES:
            errs.append(f"{sid}: difficulty 须为 {DIFFICULTIES} 之一")
        if not str(s.get("gate", "")).strip():
            errs.append(f"{sid}: 缺预期触发关卡 ID（gate）")
        if s.get("scope") not in SCOPES:
            errs.append(f"{sid}: scope 须为 {SCOPES} 之一")
        kind = s.get("payload_kind")
        if kind == "file":
            b64 = str(s.get("defect_b64", "")).strip()
            if not b64:
                errs.append(f"{sid}: file 样本缺 defect_b64")
            else:
                try:
                    base64.b64decode(b64, validate=True)
                except Exception as e:
                    errs.append(f"{sid}: defect_b64 非法 base64: {e}")
        elif kind == "generated":
            size = s.get("size_bytes")
            if not isinstance(size, int) or not 1 <= size <= 20971520:
                errs.append(f"{sid}: generated 样本 size_bytes 须为 1..20MB 整数")
        else:
            errs.append(f"{sid}: payload_kind 须为 file|generated")
        path = str(s.get("payload_path", ""))
        if not path or "{DATE}" not in path:
            errs.append(f"{sid}: payload_path 须含 {{DATE}} 占位: {path!r}")
        ap = s.get("approval")
        if not isinstance(ap, dict) or ap.get("approved_by") != OWNER:
            errs.append(f"{sid}: 缺 owner（{OWNER}）审批记录 approval.approved_by")
        elif not re.match(r"^\d{4}-\d{2}-\d{2}$", str(ap.get("date", ""))):
            errs.append(f"{sid}: approval.date 非 ISO 日期")
        if not isinstance(s.get("pr_title_adr", False), bool):
            errs.append(f"{sid}: pr_title_adr 须为布尔")
    return errs


def load_samples(path):
    try:
        doc = yaml.safe_load(open(path, encoding="utf-8"))
    except Exception as e:
        die(f"样本库 YAML 解析失败: {e}")
    errs = validate_samples(doc)
    if errs:
        for e in errs:
            print(f"::error::样本库校验失败: {e}", file=sys.stderr)
        raise SystemExit(2)
    return doc["samples"]


def load_targets(repos_path, scope):
    """目标池: REPOS.yaml active 仓 − holdout（隔离面）；scope=github 只打治理总仓。"""
    if scope == "github":
        return [".github"]
    doc = yaml.safe_load(open(repos_path, encoding="utf-8"))
    names = [r["name"] for r in doc["repos"]
             if r.get("status") == "active" and r["name"] not in EXCLUDED_TARGETS]
    if not names:
        die("REPOS.yaml 无可用 active 目标仓")
    return names


def cmd_select(a):
    samples = load_samples(a.samples)
    pool = []
    for s in samples:
        if a.sample_id and s["id"] != a.sample_id:
            continue  # 复盘/首演：指定样本仍走同一随机框架（仅固定样本维度）
        targets = load_targets(a.repos, s["scope"])
        if a.target_repo:
            targets = [t for t in targets if t == a.target_repo]
        if targets:
            pool.append((s, targets))
    if not pool:
        die("无可执行样本（样本/目标池为空或 --sample-id/--target-repo 过滤后为空）")
    s, targets = pool[a.rng.randrange(len(pool))]
    target = targets[a.rng.randrange(len(targets))]
    print(json.dumps({"seed": a.seed, "sample_id": s["id"], "difficulty": s["difficulty"],
                      "gate": s["gate"], "scope": s["scope"], "target_repo": target},
                     ensure_ascii=False))


def _git(env_extra, *args, cwd=None, check=True):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", **env_extra)
    p = subprocess.run(["git", *args], cwd=cwd, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if check and p.returncode != 0:
        die(f"git {' '.join(args[:3])} 失败(rc={p.returncode}): {p.stdout.strip()[:400]}")
    return p


def cmd_inject(a):
    samples = {s["id"]: s for s in load_samples(a.samples)}
    if a.sample_id not in samples:
        die(f"样本不存在: {a.sample_id}")
    s = samples[a.sample_id]
    date = a.date or datetime.now(timezone.utc).strftime("%Y%m%d")
    prefix = os.environ.get("DRILL_GIT_PREFIX", "https://github.com")
    push_url = f"https://github.com/{ORG}/{a.repo}.git"  # push 一律直连（镜像仅 fetch）
    auth = {}
    tok = os.environ.get("DRILL_TOKEN")
    if tok:  # CI: GOVERNANCE_TOKEN 经 git env-config 下发 extraheader，不落 remote URL/日志
        hdr = "Authorization: Basic " + base64.b64encode(f"x-access-token:{tok}".encode()).decode()
        auth = {"GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "http.https://github.com/.extraheader",
                "GIT_CONFIG_VALUE_0": hdr}
    branch = a.branch or f"drill/seed-{date}"
    with tempfile.TemporaryDirectory(prefix="drill-") as tmp:
        _git({}, "clone", "--depth", "1", f"{prefix}/{ORG}/{a.repo}.git", tmp)
        _git({}, "checkout", "-B", branch, cwd=tmp)
        path = os.path.join(tmp, *s["payload_path"].format(DATE=date).split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if s["payload_kind"] == "file":
            data = base64.b64decode(s["defect_b64"])
        else:  # generated: 零填充大文件（hygiene >5MB 禁入规则的靶）
            data = b"\0" * s["size_bytes"]
        with open(path, "wb") as f:
            f.write(data)
        _git({}, "add", path, cwd=tmp)
        _git({}, "-c", "user.name=drill-seed-bot", "-c", "user.email=drill-bot@users.noreply.github.com",
             "commit", "-m", f"drill(seed): 注入演习样本 {s['id']}（ADR-0069 周演习，验后即删）",
             cwd=tmp)
        sha = _git({}, "rev-parse", "HEAD", cwd=tmp).stdout.strip()
        last_rc = 1
        for _ in range(3):  # push 间歇失败重试（org 网络现实）
            p = _git(auth, "push", push_url, f"HEAD:refs/heads/{branch}", cwd=tmp, check=False)
            last_rc = p.returncode
            if last_rc == 0:
                break
        if last_rc != 0:
            die(f"演习分支 push 失败（3 次重试后）: {p.stdout.strip()[:400]}")
    print(json.dumps({"branch": branch, "head_sha": sha,
                      "path": s["payload_path"].format(DATE=date), "sample_id": s["id"]},
                     ensure_ascii=False))


def cmd_decode(a):
    samples = {s["id"]: s for s in load_samples(a.samples)}
    if a.id not in samples:
        die(f"样本不存在: {a.id}")
    s = samples[a.id]
    if s["payload_kind"] != "file":
        print(f"#（生成物样本，无静态内容: size_bytes={s['size_bytes']}）")
        return
    sys.stdout.write(base64.b64decode(s["defect_b64"]).decode("utf-8"))


def cmd_record(a):
    """append-only 台账：时间戳严格递增 + 同 run 不重复（AC-4 聚合的数据完整性前提）。"""
    try:
        rec = json.loads(a.json)
    except Exception as e:
        die(f"--json 解析失败: {e}")
    if not rec.get("ts") or not rec.get("kind"):
        die("记录缺 ts/kind 字段")
    lines = []
    if os.path.exists(a.history):
        lines = [l for l in open(a.history, encoding="utf-8").read().splitlines() if l.strip()]
        for l in lines:
            prev = json.loads(l)  # 既有行畸形=台账已损坏，拒绝追加（fail-closed）
            if prev["ts"] >= rec["ts"]:
                die(f"append-only 破坏: 新 ts {rec['ts']} 不晚于末行 {prev['ts']}")
            if (prev.get("kind"), prev.get("run_id")) == (rec["kind"], rec.get("run_id")) \
                    and rec.get("run_id") is not None:
                die(f"同一 run 的 {rec['kind']} 记录已存在（run_id={rec['run_id']}）")
    with open(a.history, "a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
    # ---- 影子双写（IR-0006 W1-B2 / BEH-03）：同一判定按证据 schema v1 落影子账本 ----
    # 原台账只增不改（AC-4b 平移不搬移）；影子事件 kind=gate（演习裁决），
    # card 哨兵 .github#0（基建事件未绑卡——#0 不参与卡聚合）
    import sys as _sys
    _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import evidence_shadow
    shadow = os.path.join(os.path.dirname(os.path.abspath(a.history)), "shadow-evidence.jsonl")
    shadow_ev = {
        "ts": rec["ts"], "kind": "gate", "action": f"drill-{rec['kind']}",
        "verdict": str(rec.get("verdict") or "recorded"),
        "subject": {"card": "Cloudbird-Software/.github#0", "tenant": "cloudbird-internal"},
        "actor": {"identity": "drill-seed-bot", "role": "bot", "model": None},
        "inputs_digest": "sha256:" + hashlib.sha256(
            json.dumps(rec, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest(),
    }
    evidence_shadow.append(shadow, shadow_ev)
    print(f"OK append 1 行（现有 {len(lines) + 1} 行；影子 → {shadow}）")


def cmd_redrate(a):
    """红率（目标 ≈100%）+ 难度按周分布（AC-4；Goodhart 防护=趋势可见而非打分）。"""
    if not os.path.exists(a.history):
        die(f"台账不存在: {a.history}")
    rows = [json.loads(l) for l in open(a.history, encoding="utf-8").read().splitlines() if l.strip()]
    seeds = [r for r in rows if r.get("kind") == "seed-drill"]
    verdicts = {}
    for r in seeds:
        verdicts[r.get("verdict", "?")] = verdicts.get(r.get("verdict", "?"), 0) + 1
    red, green = verdicts.get("red", 0), verdicts.get("green", 0)
    denom = red + green
    # 零分母 → null（诚实口径：不除零不出假 100%，同 dashboard-update SLI 原则）
    rate = round(red / denom, 4) if denom else None
    weeks = {}
    for r in seeds:
        wk = r["ts"][:10]
        d = r.get("difficulty", "?")
        weeks.setdefault(wk, {}).setdefault(d, 0)
        weeks[wk][d] += 1
    fails = [r for r in rows if r.get("kind") == "failclose-drill"]
    out = {"total_records": len(rows), "seed_drills": len(seeds), "verdicts": verdicts,
           "red_rate": rate, "red_rate_note": None if denom else "N/A（尚无可判定演习）",
           "difficulty_trend_by_day": {k: dict(sorted(v.items())) for k, v in sorted(weeks.items())},
           "failclose_drills": len(fails),
           "failclose_last": fails[-1].get("outcome") if fails else None}
    print(json.dumps(out, ensure_ascii=False, indent=2))
    if a.fail_unhealthy and denom and rate < 0.999:
        die(f"红率 {rate} < 100%——存在关卡失灵（green={green}），按 AC-4 告警")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    here = os.path.dirname(os.path.abspath(__file__))

    p = sub.add_parser("select", help="随机选样+目标（seed 可注入）")
    p.add_argument("--samples", default=os.path.join(here, "samples", "registry.yaml"))
    p.add_argument("--repos", default=os.path.join(here, "..", "REPOS.yaml"))
    p.add_argument("--seed", type=int, default=None, help="缺省=run_id+日期能推导的种子")
    p.add_argument("--sample-id", help="跳过随机，指定样本（复盘用）")
    p.add_argument("--target-repo", help="跳过随机，指定目标仓（复盘/首演用）")
    p.set_defaults(func=cmd_select)

    p = sub.add_parser("inject", help="开演习分支注入缺陷")
    p.add_argument("--samples", default=os.path.join(here, "samples", "registry.yaml"))
    p.add_argument("--sample-id", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--branch", default=None, help="缺省 drill/seed-YYYYMMDD")
    p.add_argument("--date", default=None, help="payload {DATE} 占位值（缺省今天）")
    p.set_defaults(func=cmd_inject)

    p = sub.add_parser("decode", help="owner 审阅：解码样本内容")
    p.add_argument("--samples", default=os.path.join(here, "samples", "registry.yaml"))
    p.add_argument("--id", required=True)
    p.set_defaults(func=cmd_decode)

    p = sub.add_parser("record", help="追加 history.jsonl（append-only）")
    p.add_argument("--history", default=os.path.join(here, "history.jsonl"))
    p.add_argument("--json", required=True)
    p.set_defaults(func=cmd_record)

    p = sub.add_parser("redrate", help="红率+难度趋势聚合（AC-4）")
    p.add_argument("--history", default=os.path.join(here, "history.jsonl"))
    p.add_argument("--fail-unhealthy", action="store_true",
                   help="红率<100%% 时非零退出（workflow 告警用）")
    p.set_defaults(func=cmd_redrate)

    a = ap.parse_args()
    if a.cmd == "select":
        if a.seed is None:
            a.seed = int(os.environ.get("GITHUB_RUN_ID", "0") or 0) + int(
                datetime.now(timezone.utc).strftime("%Y%m%d"))
        a.rng = random.Random(a.seed)
    a.func(a)


if __name__ == "__main__":
    main()
