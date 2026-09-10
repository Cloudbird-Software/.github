---
taskId: IR-0012
specVersion: 1
title: DGA 本体论 schema 定案
irRef: Cloudbird-Software/.github#?
adr: ADR-0119
acceptanceCriteria:
  - id: AC-1
    given: _repos/.github/governance/dga/closed-loop-schema.yaml
    when: python -m jsonschema 校验
    then: exit 0
  - id: AC-2
    given: _repos/.github/governance/dga/calibration-domain.yaml
    when: python -m jsonschema 校验
    then: exit 0
nonGoals:
  - 不改 DGA-human-v1.1 正本
  - 不改 runtime/bin/verify_receipt.py 既有判定
blastRadius:
  - repo: Cloudbird-Software/.github
    path: governance/dga/
