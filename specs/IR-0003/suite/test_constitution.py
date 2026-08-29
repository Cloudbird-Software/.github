#!/usr/bin/env python3
"""IR-0003 宪法 suite——v2.4 §14 总纲吸收的结构校验（T-14 第一面）。

卡 #405 / PR #426：宪法吸收治理总纲 v1.0 三组扩展条款（I3/I4/I7）。
测试锚点全为机械文本断言（无 LLM 判定——INV-01）：
  - §14 三小节结构（14a 证据账本三层 / 14b Wave 对象 / 14c 三面分离）
  - §5 硬谓词+shadow 逐字不动（ADR-0103 决策 1 的硬边界）
  - risk_class 语义约束（参数包选择器，永不是裁决输入）
  - GOVERNANCE.yaml evidence_ledger 域随附（EL-1/EL-2）
"""
import re
import unittest
from pathlib import Path

SPEC_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = SPEC_DIR.parent.parent
CONSTITUTION = SPEC_DIR / "constitution.md"
GOVERNANCE = REPO_ROOT / "governance" / "GOVERNANCE.yaml"


def constitution_text() -> str:
    self_ = CONSTITUTION.read_text(encoding="utf-8")
    return self_


def section(text: str, num: str, next_prefix: str) -> str:
    """提取 `## <num>.` 到下一个 `## <next_prefix>.` 之间的正文。"""
    pat = re.compile(
        r"^## " + re.escape(num) + r"\..*?(?=^## " + re.escape(next_prefix) + r"\.)",
        re.S | re.M,
    )
    m = pat.search(text)
    assert m, f"找不到宪法 §{num}"
    return m.group(0)


class TestConstitutionV24(unittest.TestCase):
    def test_version_note_v24(self):
        """版本注记含 v2.4 且声明 §5 逐字未动。"""
        t = constitution_text()
        self.assertIn("v2.4（IR-0006 W1-A2，卡 #405）", t)
        self.assertIn("§5 逐字未动", t)
        self.assertIn("ADR-0103 决策 1", t)

    def test_section14_exists_with_three_subsections(self):
        """§14 存在且含 14a/14b/14c 三小节。"""
        t = constitution_text()
        m = re.search(r"^## 14\..*", t, re.M)
        self.assertIsNotNone(m, "§14 缺失")
        for sub in ("### 14a.", "### 14b.", "### 14c."):
            self.assertIn(sub, t, f"{sub} 小节缺失")

    def test_14a_evidence_ledger_three_layers(self):
        """14a：判定/轨迹/丢弃三层 + 4KB 上限 + tenant 必含 + 链断=红。"""
        t = constitution_text()
        m = re.search(r"^### 14a\..*?(?=^### 14b\.)", t, re.S | re.M)
        self.assertIsNotNone(m, "14a 缺失")
        body = m.group(0)
        for kw in ("判定层", "轨迹层", "丢弃层", "append-only", "hash 链", "4KB，超限拒写", "tenant"):
            self.assertIn(kw, body, f"14a 缺关键词: {kw}")
        self.assertIn("链断=红", body)

    def test_14b_wave_object_extension(self):
        """14b：Wave ≡ card issue + wave-plan.md；卡模板三字段；预算超限硬停。"""
        t = constitution_text()
        m = re.search(r"^### 14b\..*?(?=^### 14c\.)", t, re.S | re.M)
        self.assertIsNotNone(m, "14b 缺失")
        body = m.group(0)
        self.assertIn("Wave ≡ card issue + wave-plan.md", body)
        for field in ("budget:", "capabilities:", "evidence:"):
            self.assertIn(field, body, f"14b 缺卡模板字段: {field}")
        self.assertIn("超限硬停", body)
        self.assertIn("id@sha8", body)

    def test_14c_three_planes(self):
        """14c：声明面/执行面/判定面三面 + 判定锚点永不外置 + 飞书第四投影。"""
        t = constitution_text()
        m = re.search(r"^### 14c\..*?(?=^## )", t, re.S | re.M)
        self.assertIsNotNone(m, "14c 缺失")
        body = m.group(0)
        for plane in ("声明面", "执行面", "判定面"):
            self.assertIn(plane, body, f"14c 缺面: {plane}")
        self.assertIn("判定锚点永不外置", body)
        self.assertIn("outbound-only", body)
        self.assertIn("label 唯一真源", body)

    def test_section5_hard_predicate_untouched(self):
        """§5 硬谓词+shadow 核心句逐字在位（ADR-0103 决策 1 硬边界）。"""
        t = constitution_text()
        s5 = section(t, "5", "6")
        for kw in (
            "硬谓词白名单（fail-closed）+ 常设 shadow 模式",
            "缺证据=拒绝，不是中性",
            "连续 ≥50 例一致且零逃逸",
            "成本熔断只准降级为人签，**不准降级为少验**",
        ):
            self.assertIn(kw, s5, f"§5 关键句被改动: {kw}")

    def test_risk_class_is_parameter_package_only(self):
        """risk_class 仅参数包选择器，禁止成为裁决输入（红线）。"""
        t = constitution_text()
        m = re.search(r"^## 14\..*?(?=^## )", t, re.S | re.M)
        self.assertIsNotNone(m, "§14 缺失")
        self.assertIn("参数包选择器", m.group(0))
        self.assertIn("永不是裁决输入", m.group(0))
        # §5 本体不引入 risk_class（裁决语义不参数化）
        s5 = section(t, "5", "6")
        self.assertNotIn("risk_class", s5, "§5 出现 risk_class=裁决语义被参数化（红线）")


class TestGovernanceEvidenceLedger(unittest.TestCase):
    def test_evidence_ledger_domain_declared(self):
        """GOVERNANCE.yaml 随附 evidence_ledger 域（EL-1/EL-2，advised 起步）。"""
        self.assertTrue(GOVERNANCE.exists(), "GOVERNANCE.yaml 缺失")
        t = GOVERNANCE.read_text(encoding="utf-8")
        self.assertIn("evidence_ledger:", t)
        for mid in ("- id: EL-1", "- id: EL-2"):
            self.assertIn(mid, t, f"缺措施 {mid}")
        self.assertIn("4KB", t)
        self.assertIn("tenant", t)


if __name__ == "__main__":
    unittest.main()
