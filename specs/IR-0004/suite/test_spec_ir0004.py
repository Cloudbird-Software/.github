"""IR-0004 spec 结构自测（suite/——#263 T-14：spec PR 必含非空测试文件且含有效断言）。

校验 specs/IR-0004/spec.md 的结构完整性：frontmatter 可解析、AC 三段俱全、
id 唯一且映射 IR 20 条期望变化、blastRadius/nonGoals 非空、正文条款 ID 唯一。
"""
import re
from pathlib import Path

import yaml

SPEC = Path(__file__).resolve().parents[1] / "spec.md"
IR_ITEM_COUNT = 21  # IR #315 期望变化 20 条；IR 条 11 拆为 AC-11/12、IR 条 20 补为 AC-21（R1-A H-1）


def load_fm():
    text = SPEC.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    assert m, "frontmatter 定界符缺失或未闭合"
    fm = yaml.safe_load(m.group(1))
    assert fm["taskId"] == "IR-0004"
    assert isinstance(fm["specVersion"], int) and fm["specVersion"] >= 1
    aml = fm.get("amendments") or []
    if aml:
        assert aml[-1]["rev"] == fm["specVersion"], "amendments 末条 rev 须等于 specVersion"
    assert fm["irRef"] == "Cloudbird-Software/.github#315"
    return fm, text


def test_frontmatter_parses():
    load_fm()


def test_acs_complete_and_unique():
    acs = load_fm()[0]["acceptanceCriteria"]
    assert len(acs) == IR_ITEM_COUNT, f"AC 数 {len(acs)} != IR 期望变化数 {IR_ITEM_COUNT}"
    ids = [a["id"] for a in acs]
    assert ids == [f"AC-{i}" for i in range(1, IR_ITEM_COUNT + 1)], "AC 编号不连续"
    for a in acs:
        for seg in ("given", "when", "then"):
            assert str(a.get(seg, "")).strip(), f"{a['id']} 的 {seg} 段为空"
        assert "运行时证据" in a["then"], f"{a['id']} 缺运行时证据子句"
        # 语义级断言（R1-C H-3）：证据须指向具体可机检工件，不许空泛措辞交差
        assert any(w in a["then"] for w in ("run", "日志", "JSON", "JSONL", "记录", "diff", "issue")),             f"{a['id']} 运行时证据未指向具体工件类型"


def test_blastradius_and_nongoals():
    fm = load_fm()[0]
    assert fm["blastRadius"], "blastRadius 为空"
    for b in fm["blastRadius"]:
        assert set(b) >= {"repo", "path"}, f"blastRadius 条目缺字段: {b}"
    assert len(fm["nonGoals"]) >= 5, "nonGoals 过少"


def test_clauses_unique_and_referenced():
    text = SPEC.read_text(encoding="utf-8")
    body = text.split("---", 2)[2]
    ids = re.findall(r"^\s*[-\s]*\*{0,2}(INV|BEH|IFACE|BUDGET|DECISION|ASSUMPTION)-\d+\*{0,2}", body, re.M)
    assert len(ids) >= 30, f"正文条款过少: {len(ids)}"
    flat = re.findall(r"(?:INV|BEH|IFACE|BUDGET|DECISION|ASSUMPTION)-\d+", body)
    assert len(flat) == len(set(flat)), "正文条款 ID 有重复定义"
    # BEH 条款须引用其承接的 AC
    for m in re.finditer(r"BEH-\d+（(AC-[0-9/, ]+)）", body):
        for ref in re.findall(r"AC-\d+", m.group(1)):
            assert ref in text


def test_negative_assertions_present():
    """R1-C H-1/H-2/H-4：关键 fail-open 面必须有负向断言（异常/缺失即红）。"""
    fm = load_fm()[0]
    acs = {a["id"]: a["then"] for a in fm["acceptanceCriteria"]}
    negative_words = ("红", "不通过", "作废", "失败", "拦截")
    for ac_id in ("AC-1", "AC-3", "AC-5", "AC-14", "AC-18"):
        assert any(w in acs[ac_id] for w in negative_words), f"{ac_id} 缺负向断言（fail-open 缝隙）"


def test_no_exemption_of_governance():
    text = SPEC.read_text(encoding="utf-8")
    for bad in ("跳过 gate", "绕过 gate", "豁免 gate", "无视 ADR"):
        assert bad not in text, f"出现治理豁免措辞: {bad}"
