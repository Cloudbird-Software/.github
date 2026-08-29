"""IR-0006 spec 结构自测（suite/——T-14：spec PR 必含非空测试文件且含真实断言）。

零第三方依赖（frontmatter 用正则解析，不 import yaml——本地 gates-pr 与 CI 同语义）。
校验：frontmatter 完整、AC 十条三段俱全且带运行时证据、条款唯一、三附件在场
（spec/wave-plan/absorption-map）、落位表 18 行、词汇归并四等价、波次六段各带退出判据。
"""
import re
import unittest
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
SPEC = BASE / "spec.md"
MAP = BASE / "absorption-map.md"
PLAN = BASE / "wave-plan.md"
IR_ITEM_COUNT = 10  # IR #402 期望变化十条 → AC-1..AC-10


def _fm_text():
    text = SPEC.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    assert m, "frontmatter 定界符缺失或未闭合"
    return m.group(1), text


def _fm_key(fm, key):
    m = re.search(rf"^{key}: (.+)$", fm, re.M)
    assert m, f"frontmatter 缺 {key}"
    return m.group(1).strip()


def _fm_block(fm, key):
    m = re.search(rf"^{key}: \|\n(.*?)(?=^\w[\w-]*: |\Z)", fm, re.M | re.S)
    assert m, f"frontmatter 缺 {key} 块"
    return m.group(1)


def _fm_list_block(fm, key):
    """捕获顶层 key 下的多行列表块（条目可跨行），止于下一个顶层键。"""
    m = re.search(rf"^{key}:\n((?:(?!^\w[\w-]*: ).*\n?)*)", fm, re.M)
    assert m, f"frontmatter 缺 {key} 列表块"
    return m.group(1)


class TestFrontmatter(unittest.TestCase):
    def test_identity(self):
        fm, _ = _fm_text()
        self.assertEqual(_fm_key(fm, "taskId"), "IR-0006")
        self.assertTrue(int(_fm_key(fm, "specVersion")) >= 1)
        self.assertEqual(_fm_key(fm, "irRef"), "Cloudbird-Software/.github#402")
        self.assertIn("ADR-0103", _fm_key(fm, "adrRef"))

    def test_blocks_nonempty(self):
        fm, _ = _fm_text()
        for key in ("inv", "budget", "decision"):
            block = _fm_block(fm, key)
            self.assertGreaterEqual(len(block.strip()), 40, f"{key} 块过薄")
        self.assertIn("INV-01", _fm_block(fm, "inv"))
        self.assertGreaterEqual(
            len(re.findall(r"DECISION-\d+", _fm_block(fm, "decision"))), 6,
            "decision 块不足 6 条")

    def test_nongoals(self):
        fm, _ = _fm_text()
        items = [l for l in _fm_list_block(fm, "nonGoals").splitlines() if l.startswith("- ")]
        self.assertGreaterEqual(len(items), 5, "nonGoals 过少")

    def test_blastradius(self):
        fm, _ = _fm_text()
        items = [l for l in _fm_list_block(fm, "blastRadius").splitlines()
                 if l.startswith("- repo:")]
        self.assertGreaterEqual(len(items), 3, "blastRadius 仓面过少")
        for l in items:
            self.assertIn("path:", _fm_list_block(fm, "blastRadius"), "blastRadius 条目缺 path")


class TestAcceptanceCriteria(unittest.TestCase):
    def _ac_block(self):
        fm, _ = _fm_text()
        return _fm_list_block(fm, "acceptanceCriteria")

    def test_count_and_ids(self):
        ids = re.findall(r"^- id: (AC-\d+)$", self._ac_block(), re.M)
        self.assertEqual(len(ids), IR_ITEM_COUNT, f"AC 数 {len(ids)} != {IR_ITEM_COUNT}")
        self.assertEqual(ids, [f"AC-{i}" for i in range(1, IR_ITEM_COUNT + 1)],
                         "AC 编号不连续")

    def test_three_segments_and_evidence(self):
        blocks = re.split(r"(?=^- id: AC-\d+$)", self._ac_block(), flags=re.M)
        acs = [b for b in blocks if b.startswith("- id:")]
        self.assertEqual(len(acs), IR_ITEM_COUNT)
        for b in acs:
            aid = re.match(r"- id: (AC-\d+)", b).group(1)
            for seg in ("given", "when", "then"):
                self.assertRegex(b, rf"{seg}: .+", f"{aid} 的 {seg} 段为空")
            then = re.search(r"then: (.+)", b).group(1)
            self.assertIn("运行时证据", then, f"{aid} 缺运行时证据子句")
            self.assertTrue(
                any(w in then for w in ("run", "日志", "JSON", "JSONL", "记录", "diff", "issue")),
                f"{aid} 运行时证据未指向具体工件类型")


class TestBodyClauses(unittest.TestCase):
    def test_clauses_unique(self):
        _, text = _fm_text()
        body = text.split("---", 2)[2]
        # 兼容两种仓内样式：`- **INV-01** 标题…` 与 `- **INV-01 标题**…`
        defs = re.findall(
            r"^- \*\*((?:INV|BEH|IFACE|BUDGET|DECISION|ASSUMPTION)-\d+)(?:[^*\n]*)\*\*",
            body, re.M)
        self.assertGreaterEqual(len(defs), 20, f"正文条款过少: {len(defs)}")
        self.assertEqual(len(defs), len(set(defs)),
                         f"条款定义重复: {[k for k in defs if defs.count(k) > 1]}")

    def test_key_clauses_present(self):
        _, text = _fm_text()
        for anchor in (
            "INV-01 裁决语义恒定", "INV-06 payload 指针纪律", "BEH-02 月度 checkpoint",
            "BEH-07 波次预算硬停", "IFACE-01 证据记录 schema v1",
        ):
            self.assertIn(anchor, text, f"缺关键条款 {anchor}")

    def test_test_design_covers_categories(self):
        _, text = _fm_text()
        self.assertIn("测试设计", text, "缺测试设计节（ADR-0095 一等公民）")
        self.assertIn("holdout 测试设计", text, "缺 holdout 设计节")
        for cat in ("T-01", "T-02", "T-03", "T-04", "T-05", "T-08", "T-09",
                    "T-10", "T-12", "T-13", "T-14", "T-15"):
            self.assertIn(cat, text, f"测试设计缺 active_now 类 {cat}（逐类讨论不完整）")
        for fam in ("L-05", "R-02", "G-01"):
            self.assertIn(fam, text, f"测试设计缺条件激活族 {fam}")


class TestAbsorptionMap(unittest.TestCase):
    def test_exists_and_sections(self):
        self.assertTrue(MAP.is_file(), "absorption-map.md 缺失")
        text = MAP.read_text(encoding="utf-8")
        self.assertIn("落位表", text)
        self.assertIn("词汇归并表", text)
        rows = re.findall(r"^\| 第\w+部分", text, re.M)
        self.assertGreaterEqual(len(rows), 18, f"落位表仅 {len(rows)} 行（须 18）")
        for status in ("已覆盖", "本 IR 吸收", "延后"):
            self.assertIn(status, text, f"落位表缺状态类 {status}")

    def test_vocabulary_equivalences(self):
        text = MAP.read_text(encoding="utf-8")
        m = re.search(r"## 二、词汇归并表.*?(?=\n## )", text, re.S)
        self.assertIsNotNone(m, "词汇归并表节缺失")
        for word in ("Wave", "Capability Broker", "证据账本", "Channel"):
            self.assertIn(word, m.group(0), f"词汇归并缺 {word}")
        self.assertIn("扩展 schema", text, "Wave 归并未声明扩展现有对象（防新建 kind）")


class TestWavePlan(unittest.TestCase):
    def test_six_waves_with_exit(self):
        self.assertTrue(PLAN.is_file(), "wave-plan.md 缺失")
        text = PLAN.read_text(encoding="utf-8")
        for i in range(1, 7):
            self.assertIn(f"## W{i} ", text, f"缺波次 W{i}")
        self.assertEqual(text.count("退出判据"), 6, "每波次须有退出判据")

    def test_card_count(self):
        text = PLAN.read_text(encoding="utf-8")
        cards = re.findall(r"^\| W\d-[A-Z]\d", text, re.M)
        self.assertGreaterEqual(len(cards), 15, f"波次卡仅 {len(cards)} 张（须 ≥15）")

    def test_w1_covers_four_tracks(self):
        text = PLAN.read_text(encoding="utf-8")
        m = re.search(r"## W1 .*?(?=\n## W2)", text, re.S)
        for track in ("W1-A", "W1-B", "W1-C", "W1-D"):
            self.assertIn(track, m.group(0), f"W1 缺 {track} 线")


if __name__ == "__main__":
    unittest.main()
