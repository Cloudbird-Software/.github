---
taskId: IR-0014
specVersion: 1
title: 新治理体系验收 spec
irRef: Cloudbird-Software/.github#?
adr: ADR-0119
acceptanceCriteria:
  - id: AC-1
    given: verify_all.py 全绿
    when: py -3 -X utf8 runtime/bin/verify_all.py
    then: rc=0
  - id: AC-2
    given: verify_receipt_dga.py 全绿
    when: py -3 -X utf8 runtime/bin/test_verify_receipt_dga.py
    then: rc=0
  - id: AC-3
    given: drift_probe.py 全绿
    when: py -3 -X utf8 runtime/bin/test_drift_probe.py
    then: rc=0
nonGoals:
  - 不推送 GitHub
  - 不改 EX-1/cnb-bridge
blastRadius:
  - repo: Cloudbird-Software/.github
    path: specs/IR-0014/
  - repo: Cloudbird-Software/archive
    path: evidence/
