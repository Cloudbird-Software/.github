# pool-routing.rego — DGA-INFRA 池路由谓词（M2 资源池 v0）
# 规范依据：DGA-INFRA-v1.0 3.2 信任标签路由（R-POOL-TRUST：任务 sensitivity ≤ 端点 trust）；
#           3.3 数据红线（R-POOL-DATA：客户业务数据禁 T0；v0 不实现"合同显式允许+已脱敏"例外——
#               无合同/脱敏证据对象，例外路径登记为缺口）；
#           3.4 TOS 合规（R-POOL-COMPLIANCE：tos_risk 灰区/高风险账号不得承接非公开任务；
#               灰区可否使用由 S5 裁决，agent 发现即升级）。
# 对照 3.2 表：public<internal<customer_sensitive ↔ T0<T1<T2，即 D-公开→T0 可，
#           D-内部→需 ≥T1，D-客户敏感→仅 T2（任务指令明确按此实现）。
#
# 输入契约：
# {
#   "task":     { "task_id": "...", "sensitivity": "public" | "internal" | "customer_sensitive" },
#   "endpoint": { "endpoint_name": "...", "trust_label": "T0"|"T1"|"T2",
#                 "tos_risk": "clear"|"grey-zone"|"high-risk" }
# }
# tos_risk 由路由器从端点绑定账号集合聚合（任一账号灰区/高风险 ⇒ 端点按灰区处理）。
# 查询面：POST /v1/data/dga/pool/allow（布尔）；
#         POST /v1/data/dga/pool/deny_reasons（拒绝原因集合，R-EVID-01 策略判定记录原料）；
#         POST /v1/data/dga/pool/decision（allow+deny_reasons 合并对象）。
package dga.pool

import rego.v1

default allow := false

# ---- 分级映射（3.2：S0≤T0、S1≤T1、S2≤T2）----
sensitivity_rank("public") := 0
sensitivity_rank("internal") := 1
sensitivity_rank("customer_sensitive") := 2

trust_rank("T0") := 0
trust_rank("T1") := 1
trust_rank("T2") := 2

# ---- 输入合法性（未知枚举值一律拒绝，不默认放行）----
known_sensitivity if input.task.sensitivity in {"public", "internal", "customer_sensitive"}
known_trust if input.endpoint.trust_label in {"T0", "T1", "T2"}

# ---- R-POOL-TRUST 主谓词：任务敏感度 rank ≤ 端点信任 rank（3.2 表）----
rank_ok if {
	sensitivity_rank(input.task.sensitivity) <= trust_rank(input.endpoint.trust_label)
}

# ---- R-POOL-COMPLIANCE：灰区/高风险账号承载的端点不得承接非公开任务（3.4）----
gray_block if {
	input.endpoint.tos_risk in {"grey-zone", "high-risk"}
	sensitivity_rank(input.task.sensitivity) > 0
}

# ---- 判定 ----
allow if {
	known_sensitivity
	known_trust
	rank_ok
	not gray_block
}

# ---- 拒绝原因（策略判定记录/EvidenceType=POLICY_DECISION 的原料，R-EVID-01/R-POL-05）----
deny_reasons contains "R-POOL-INPUT-INVALID" if not known_sensitivity
deny_reasons contains "R-POOL-INPUT-INVALID" if not known_trust
deny_reasons contains "R-POOL-TRUST" if {
	known_sensitivity
	known_trust
	not rank_ok
}
# R-POOL-DATA（3.3 硬红线）：客户敏感任务打 T0 端点——在 R-POOL-TRUST 之外单独显名，
# 使红线违规在证据流中可单独检索（3.3：违反=RULE-02 级别违规）。
deny_reasons contains "R-POOL-DATA" if {
	input.task.sensitivity == "customer_sensitive"
	trust_rank(input.endpoint.trust_label) == 0
}
deny_reasons contains "R-POOL-COMPLIANCE" if gray_block

decision := {"allow": allow, "deny_reasons": deny_reasons}
