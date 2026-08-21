# .github 治理仓 Makefile（W1-C3 #166 / ADR-0055 决策 11）
# 入口协议块第 4 步（make card-test / make gates-pr）在"卡实际所在仓"的兑现面。
# 治理仓无产品测试镜像——两目标是诚实薄封装：card-test 拉卡 AC 列表提醒测试先行；
# gates-pr 真实执行 gate.yml 的本地可等价部分（bash -n / yaml 解析），CI 关卡语义
# 仍以 .github/workflows/gate.yml 为准，不伪装已运行 CI。
CARD ?=
# 卡所在仓（W1 波次卡都在治理仓；产品仓自有卡时 REPO=... 覆盖）。
# 注释须独立成行：行尾注释会把 # 前的尾随空格并入 REPO 值，gh -R 解析失败且被吞。
REPO ?= Cloudbird-Software/.github

.PHONY: card-test gates-pr
card-test: ## 读卡 AC 列表并提示测试先行：make card-test CARD=<issue#>
	@test -n "$(CARD)" || { echo "用法: make card-test CARD=<issue#>（缺 CARD）" >&2; exit 2; }
	@echo "== 卡 $(REPO)#$(CARD) 的 AC（测试先行：先按 AC 写红测试再实现）=="
	@gh issue view "$(CARD)" -R "$(REPO)" --json number,title,body \
	  --jq '"#\(.number) \(.title)\n\n\(.body)"' 2>/dev/null \
	  | awk 'NR==1{print;print ""} /^## AC/{f=1} f{print} f && /^## / && !/^## AC/{exit}' | head -60
	@echo "(空=拉取失败或卡无 AC 节——手动: gh issue view $(CARD) -R $(REPO))"
	@echo "== 提示：治理仓改动无产品测试面；用 make gates-pr 自检后再开 PR =="

gates-pr: ## 本地等价关卡清单（gate.yml 语义）：make gates-pr
	@echo "== gates-pr：gate.yml 的本地可等价部分（真实执行；CI 关卡仍以 gate.yml 为准）=="
	@bash -n scripts/ghcb scripts/gh-app-token.sh scripts/new-repo-init.sh \
	  governance/apply.sh governance/drift-check.sh governance/cost-check.sh \
	  governance/auto-fix-limit.sh governance/butler-reconcile.sh governance/butler-audit.sh \
	  && echo "OK   bash -n 治理脚本"
	@for t in governance/tests/test-*.sh; do bash "$$t"; done \
	  && echo "OK   治理自测（governance/tests；需 jq）"
	@python3 -c "import glob,yaml;[yaml.safe_load(open(f,encoding='utf-8')) for f in glob.glob('governance/**/*.yaml',recursive=True)+glob.glob('standards/**/*.yaml',recursive=True)+glob.glob('.github/workflows/*.yml')];print('OK   yaml 解析（governance/standards/workflows）')"
	@echo "== 开 PR 前检查单（机器不可判部分）：PR body 引用 ADR-NNNN（C1）/ body 带 Card: 元数据行 / diff<400 行 =="
