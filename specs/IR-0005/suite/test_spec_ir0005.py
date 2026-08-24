#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""IR-0005 套件——PM 优先范式（ADR-0085）条款与验收文档的结构+语义锚断言。

被审"实现"= impl-dir 下的 spec.md（与 acceptance.md，若在）。断言分四层：
  L1 结构：frontmatter 字段、AC 编号完备（AC-1..AC-7）、INV/BUDGET/DECISION 齐备
  L2 语义锚：真实产物才含的机制短语（T8 谓词/跨仓检索/双态窗口/三接缝/报告环……）
  L3 负向锚：攻击者偷懒实现最易缺的深水位标志（密度/规模/具体编号）
  L4 一致性：AC 数与 IR#348 期望变化数对齐、specVersion 数字锚
防"最偷懒实现"（judge-deep）口径：同义模板句无法同时命中 20+ 异质锚。
"""
import os
import re
import sys
import unittest

# impl 目录定位（三通道等价）：IMPL_DIR env（run-suite.sh/直跑）优先；
# 否则从 cwd 向上探测 spec.md（gate 的 unittest discover 会把 __file__
# 解析到不可预期的层级——弃用 __file__，2026-08-25 实测教训）
_cwd = os.path.abspath(os.getcwd())
IMPL = None
if os.environ.get("IMPL_DIR"):
    IMPL = os.path.normpath(os.environ["IMPL_DIR"])
elif os.path.isfile(os.path.join(_cwd, "spec.md")):
    IMPL = _cwd
elif os.path.isfile(os.path.join(_cwd, "..", "spec.md")):
    IMPL = os.path.normpath(os.path.join(_cwd, ".."))
if IMPL is None:
    raise AssertionError("无法定位 impl 目录（IMPL_DIR 未设且 cwd 上下文无 spec.md）")
SPEC = os.path.normpath(os.path.join(IMPL, "spec.md"))
ACC = os.path.normpath(os.path.join(IMPL, "acceptance.md"))


def read(path, required=True):
    if not os.path.isfile(path):
        if required:
            raise AssertionError(f"缺文件: {path}")
        return ""
    with open(path, encoding="utf-8") as f:
        return f.read()


class L1Structure(unittest.TestCase):
    def test_frontmatter(self):
        head = read(SPEC)[:600]
        for k in ("taskId: IR-0005", "specVersion:", "irRef:", "adrRef:", "acceptanceReport:"):
            self.assertIn(k, head, f"frontmatter 缺 {k}")

    def test_ac_complete(self):
        s = read(SPEC)
        for i in range(1, 8):
            self.assertIn(f"- id: AC-{i}", s, f"缺 AC-{i}")

    def test_sections(self):
        s = read(SPEC)
        for sec in ("inv:", "budget:", "decision:", "amendments:"):
            self.assertIn(sec, s, f"缺条款段 {sec}")


class L2SemanticAnchors(unittest.TestCase):
    ANCHORS = [
        "T7", "T8", "T9",                              # 状态机新转移
        "跨仓",                                          # T8 谓词通道（PR#355）
        "双态",                                          # 窗口收敛语义（PR#353）
        "fail-closed",                                  # 红线语义
        "arbiter",                                      # T3 租约
        "父意图",                                        # T9 子卡判定字段
        "acceptance.md",                                # T9 验收报告谓词
        "三接缝",                                        # CNB 隔离（EX-1）
        "org secret",                                   # 凭据纪律
        "light", "std",                                 # CNB 档位
        "[followup]",                                   # 报告环机械抓手
        "runs-digest",                                  # 周度聚合件
        "经验输入不是验收证据",                            # 报告定位铁律
        "生成/裁决分离",                                  # INV-01
        "append-only",                                  # 红线三
        "archive/retired/",                             # 退役快照落点
        "INDEX.yaml",                                   # ADR 家园单仓化
    ]

    def test_spec_semantic_anchors(self):
        s = read(SPEC)
        missing = [a for a in self.ANCHORS if a not in s]
        self.assertFalse(missing, f"spec.md 缺语义锚: {missing}")

    def test_ac3_then_depth(self):
        # AC-3 的 then 必须含四要素：T7/T3/T8/拒绝回滚——攻击者缩写必缺其一
        s = read(SPEC)
        m = re.search(r"- id: AC-3\n(.*?)(?=- id: AC-4)", s, re.S)
        self.assertTrue(m, "AC-3 块缺失")
        body = m.group(1)
        for kw in ("T7", "T3", "T8", "DENIED-no-merged-pr"):
            self.assertIn(kw, body, f"AC-3 缺 {kw}")


class L3DeepAnchors(unittest.TestCase):
    def test_acceptance_evidence(self):
        a = read(ACC)
        for kw in ("#349", "#350", "#351", "archive#17", "cnb-bridge#1",
                   "DENIED-no-merged-pr", "207", "edd02570",
                   "state:done", "跨仓", "残留"):
            self.assertIn(kw, a, f"acceptance.md 缺证据锚 {kw}")

    def test_scale_floor(self):
        # 规模锚：真身 acceptance >= 1200 字、spec >= 1500 字（含条款展开）
        self.assertGreaterEqual(len(read(ACC)), 1200, "acceptance.md 规模不足")
        self.assertGreaterEqual(len(read(SPEC)), 1500, "spec.md 规模不足")

    def test_residual_honesty(self):
        # 诚实申报锚：残留节必含 rev6 与 xuemei——全绿假报告最难伪造的让步性内容
        a = read(ACC)
        self.assertIn("rev6", a, "残留节缺 rev6 申报")
        self.assertIn("xuemei", a, "残留节缺 xuemei pending 申报")


class L4Consistency(unittest.TestCase):
    def test_spec_version_anchor(self):
        m = re.search(r"specVersion:\s*(\d+)", read(SPEC))
        self.assertTrue(m and int(m.group(1)) >= 1, "specVersion 缺失/非数值")

    def test_t9_predicate_words(self):
        # T9 谓词语义在 AC-4 的 then 里必须双要素齐全
        m = re.search(r"- id: AC-4\n(.*?)(?=- id: AC-5)", read(SPEC), re.S)
        self.assertTrue(m, "AC-4 块缺失")
        for kw in ("子卡", "acceptance.md"):
            self.assertIn(kw, m.group(1), f"AC-4 缺谓词要素 {kw}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
