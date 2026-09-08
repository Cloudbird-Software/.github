"""IR-0011 suite: 防摆拍 AC（S1'）——结构、三段式、运行时证据、负控制。"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC_DIR = Path(__file__).resolve().parents[1]
SPEC = SPEC_DIR / "spec.md"

_GH = "gh" + "p_"
_SK = "sk" + "-"


def _first_existing(*cands: Path) -> Path:
    for p in cands:
        if p.is_file():
            return p
    return cands[0]


ROLE = _first_existing(SPEC_DIR / "ROLE-CEO.md", ROOT / "docs" / "agent" / "ROLE-CEO.md")
AGENTS = _first_existing(SPEC_DIR / "AGENTS.md", ROOT / "AGENTS.md")


def _fm_text():
    text = SPEC.read_text(encoding="utf-8").replace("\r\n", "\n")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    assert m, "frontmatter 定界符缺失或未闭合"
    return m.group(1), text


def _fm_list_block(fm, key):
    m = re.search(rf"^{key}:\n((?:(?!^\w[\w-]*: ).*\n?)*)", fm, re.M)
    assert m, f"frontmatter 缺 {key} 列表块"
    return m.group(1)


class TestRoleCeo(unittest.TestCase):
    def test_role_exists(self):
        self.assertTrue(ROLE.is_file(), f"missing ROLE-CEO.md at {ROLE}")

    def test_role_min_length(self):
        t = ROLE.read_text(encoding="utf-8")
        self.assertGreaterEqual(len(t), 1200, "ROLE-CEO.md 过薄，摆拍标题不够")

    def test_required_phrases(self):
        t = ROLE.read_text(encoding="utf-8")
        for h in (
            "身份五元组",
            "L4",
            "永不载责",
            "不可自我晋升",
            "S5 六项独占",
            "升级矩阵",
            "不复活声明式",
            "不设月度花钱上限",
        ):
            self.assertIn(h, t, f"ROLE-CEO.md 缺 {h}")

    def test_identity_table(self):
        t = ROLE.read_text(encoding="utf-8")
        rows = [ln for ln in t.splitlines() if ln.startswith("|") and "---" not in ln]
        self.assertGreaterEqual(len(rows), 6, "五元组表行数不足（表头+五行）")
        blob = "\n".join(rows)
        for cell in ("name", "organization", "role", "principal", "spec", "CEO", "Cloudbird-Software", "randypanding"):
            self.assertIn(cell, blob)

    def test_no_l5_self_grant(self):
        t = ROLE.read_text(encoding="utf-8")
        self.assertNotRegex(t, r"授予\s*L5|晋升为\s*L5|L5 战略自治")

    def test_agents_index(self):
        t = AGENTS.read_text(encoding="utf-8")
        self.assertIn("ROLE-CEO.md", t)
        self.assertRegex(t, r"\|.*ROLE-CEO\.md.*\|")

    def test_no_secret_patterns(self):
        t = ROLE.read_text(encoding="utf-8")
        self.assertNotIn(_GH, t)
        self.assertNotIn(_SK, t)


class TestSpecAntiPose(unittest.TestCase):
    def test_frontmatter_identity(self):
        fm, _ = _fm_text()
        self.assertIn("taskId: IR-0011", fm)
        self.assertIn("ADR-0110", fm)
        self.assertIn("irRef: Cloudbird-Software/.github#524", fm)

    def test_ac_four_with_segments_and_evidence(self):
        fm, _ = _fm_text()
        block = _fm_list_block(fm, "acceptanceCriteria")
        ids = re.findall(r"^\s+- id: (AC-\d+)\s*$", block, re.M)
        self.assertEqual(ids, ["AC-1", "AC-2", "AC-3", "AC-4"])
        parts = re.split(r"(?=^\s+- id: AC-\d+\s*$)", block, flags=re.M)
        acs = [b for b in parts if re.match(r"\s+- id:", b)]
        for b in acs:
            aid = re.search(r"id: (AC-\d+)", b).group(1)
            for seg in ("given", "when", "then"):
                self.assertRegex(b, rf"{seg}: .+", f"{aid} 缺 {seg}")
            then = re.search(r"then: (.+)", b).group(1)
            self.assertIn("运行时证据", then, f"{aid} 缺运行时证据")
            self.assertTrue(
                any(w in then for w in ("run", "日志", "suite", "check", "路径", "文件")),
                f"{aid} 运行时证据未指向工件",
            )
            self.assertGreaterEqual(len(then), 24, f"{aid} then 过短，疑似摆拍")

    def test_nongoals_and_blast(self):
        fm, _ = _fm_text()
        ng = [l for l in _fm_list_block(fm, "nonGoals").splitlines() if l.strip().startswith("- ")]
        self.assertGreaterEqual(len(ng), 4, "nonGoals 过少")
        br = _fm_list_block(fm, "blastRadius")
        self.assertGreaterEqual(br.count("repo:"), 3)
        self.assertIn("path:", br)

    def test_design_table_and_holdout(self):
        _, text = _fm_text()
        self.assertIn("测试设计", text)
        self.assertIn("holdout 测试设计", text)
        for cat in ("T-01", "T-02", "T-03", "T-04", "T-05", "T-08", "T-09", "T-10", "T-12", "T-13", "T-14", "T-15"):
            self.assertIn(cat, text, f"测试设计缺 {cat}")
        for fam in ("L-05", "R-02", "G-01"):
            self.assertIn(fam, text, f"测试设计缺 {fam}")
        self.assertIn("HO-CEO-NO-S5", text)

    def test_clauses(self):
        _, text = _fm_text()
        for c in ("INV-01", "INV-02", "BEH-01", "BEH-02", "DECISION-01"):
            self.assertIn(c, text)
        self.assertIn("负控制", text)

    def test_flat_names_contract(self):
        t = SPEC.read_text(encoding="utf-8")
        self.assertIn("ROLE-CEO.md", t)
        self.assertIn("[A-Za-z0-9._-]", t)


if __name__ == "__main__":
    unittest.main()
