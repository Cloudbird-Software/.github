#!/usr/bin/env python3
"""drill.py —— 周种子缺陷演习引擎·读面（宪法 §4B/§6 / ADR-0069 / .github#223 W4-C4）

子命令（全部 fail-closed：任何失败非零退出，绝不静默降级为"通过"）:
  select   随机选缺陷样本 + 随机目标仓（--seed 注入可复现——测试与事后复盘）
  decode   owner 审阅用：解码样本缺陷内容（ADR-0069 决策 1 样本库 owner 直管）

注入/独立验证/台账（inject/record/redrate）随后续 PR 落地——红绿判定与样本库
分离（verify_gate.py，ADR-0069 决策 2"注入者与判定者分离"）。注入物只落在
演习分支（隔离执行，不进 agent 工作区，ADR-0069 风险缓解）；分支验后即删。
"""
import argparse
import base64  # decode 用（样本 defect_b64）
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


def cmd_decode(a):
    samples = {s["id"]: s for s in load_samples(a.samples)}
    if a.id not in samples:
        die(f"样本不存在: {a.id}")
    s = samples[a.id]
    if s["payload_kind"] != "file":
        print(f"#（生成物样本，无静态内容: size_bytes={s['size_bytes']}）")
        return
    sys.stdout.write(base64.b64decode(s["defect_b64"]).decode("utf-8"))


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

    p = sub.add_parser("decode", help="owner 审阅：解码样本内容")
    p.add_argument("--samples", default=os.path.join(here, "samples", "registry.yaml"))
    p.add_argument("--id", required=True)
    p.set_defaults(func=cmd_decode)


    a = ap.parse_args()
    if a.cmd == "select":
        if a.seed is None:
            a.seed = int(os.environ.get("GITHUB_RUN_ID", "0") or 0) + int(
                datetime.now(timezone.utc).strftime("%Y%m%d"))
        a.rng = random.Random(a.seed)
    a.func(a)


if __name__ == "__main__":
    main()
