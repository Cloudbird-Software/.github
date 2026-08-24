"""specs/ISSUE-263 自有验收套件（T-14 第一面，ADR-0083）。

对 #263「卡绑定测试与红队守门制度」的治理落盘工件做结构化断言——
IR 自身首先受 T-14 约束（此前 specs/ISSUE-263 无 suite/ 是独立验证
发现的违规样本）。unittest 风格、零第三方依赖（yaml 断言用文本锚点，
避免 gate job 依赖面扩大）。
"""
import json
import os
import re
import unittest

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
TRANSITIONS = os.path.join(ROOT, "governance", "transitions.yaml")
TESTING = os.path.join(ROOT, "governance", "policy", "testing.yaml")
GOVERNANCE = os.path.join(ROOT, "governance", "GOVERNANCE.yaml")
MAIN_PROT = os.path.join(ROOT, "governance", "rulesets", "main-protection.json")
EXPECTED = os.path.join(ROOT, "governance", "expected-state.json")
REPOS = os.path.join(ROOT, "governance", "REPOS.yaml")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class TestStateMachine(unittest.TestCase):
    """AC-12：T5/T6 入册且语义齐全。"""

    def test_t5_t6_registered(self):
        t = read(TRANSITIONS)
        for tid in ("T5", "T6"):
            self.assertIsNotNone(
                re.search(rf"^\s*- id: {tid}\b", t, re.M),
                f"transitions.yaml 缺 {tid}")

    def test_t5_suite_ready_predicate(self):
        self.assertIn("suite", read(TRANSITIONS), "T5 须含 suite 就绪谓词")


class TestPolicyClauses(unittest.TestCase):
    """W1-C5 条款入册：T-14/T-15/AR-10。"""

    def test_t14_t15_registered(self):
        t = read(TESTING)
        self.assertRegex(t, r"T-14,\s*name:\s*card_bound_test_required")
        self.assertRegex(t, r"T-15,\s*name:\s*intent_backstop")

    def test_ar10_veto_clause(self):
        g = read(GOVERNANCE)
        self.assertIn("红队守门", g)
        self.assertIn("needs-human", g)
        self.assertIn("EXPECTED_SKIP", g)


class TestRulesetEnforcement(unittest.TestCase):
    """W4-C3：adversary 为 required check 且无非法 integration_id（ADR-0083）。"""

    def setUp(self):
        self.rs = json.loads(read(MAIN_PROT))

    def test_adversary_required_no_integration_id(self):
        checks = None
        for rule in self.rs["rules"]:
            if rule["type"] == "required_status_checks":
                checks = rule["parameters"]["required_status_checks"]
        self.assertIsNotNone(checks, "main-protection 缺 required_status_checks")
        contexts = {c["context"]: c for c in checks}
        self.assertIn("adversary", contexts, "adversary 不在 required checks")
        for ctx, entry in contexts.items():
            self.assertNotIn(
                "integration_id", entry,
                f"required check '{ctx}' 携带 integration_id（非法——ADR-0083 决策 3）")

    def test_gate_and_org_gate_kept(self):
        rule = next(r for r in self.rs["rules"] if r["type"] == "required_status_checks")
        contexts = [c["context"] for c in rule["parameters"]["required_status_checks"]]
        for c in ("gate", "org-gate"):
            self.assertIn(c, contexts)


class TestExpectedState(unittest.TestCase):
    """W2-C1：验证者 APP 登记面。"""

    def test_verifier_app_registered(self):
        d = json.loads(read(EXPECTED))
        va = d.get("verifier_app") or {}
        self.assertTrue(isinstance(va.get("id"), int), "verifier_app.id 须为数值")
        self.assertEqual(va.get("slug"), "verifier-app")

    def test_holdout_repo_declared(self):
        self.assertRegex(read(REPOS), r"name:\s*holdout\b")


class TestSelfSuiteValidity(unittest.TestCase):
    """T-14 自反：本 suite 含真实断言（非摆拍——S1'/S2' 攻击面对象）。"""

    def test_suite_has_real_assertions(self):
        src = read(os.path.abspath(__file__))
        asserts = len(re.findall(r"\bassert", src))
        self.assertGreater(asserts, 10, f"断言过少（{asserts}）——疑似摆拍套件")


if __name__ == "__main__":
    unittest.main()
