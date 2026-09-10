---
taskId: IR-0013
specVersion: 1
title: 退役清单执行波次
irRef: Cloudbird-Software/.github#?
adr: ADR-0119
acceptanceCriteria:
  - id: AC-1
    given: Phase 1 快照完成
    when: 删除 standards/agent/ 五 schema
    then: ls 返回 exit 2
  - id: AC-2
    given: Phase 2 完成
    when: 修正 agent-tools/README.md 首行
    then: head -1 输出 # agent-tools
nonGoals:
  - 不删除 archive/retired 快照
  - 不改 ADR-0119 正文
blastRadius:
  - repo: Cloudbird-Software/.github
    path: standards/agent/
  - repo: Cloudbird-Software/agent-tools
    path: README.md
