# action-authz.rego — DGA-INFRA M4 工具网关鉴权谓词（Action Registry 轨道）
# 规范依据：DGA-INFRA-v1.0
#   R-POL-01 权限检查在工具网关/服务端强制执行（本谓词 = 网关管线阶段③的真实强制点；
#            未注册工具不进本谓词——网关阶段①即 404+审计，registry 见 policies/action-registry.sql）；
#   R-POL-02 子任务权限 ≤ 父任务（scope 集合包含检查：工具声明的 required_scope 必须 ∈ parent_task_scope）；
#   R-POL-04 执行者不得获得校准判定（执行者角色 × judicial=true 工具 → 一律拒绝，判定隔离）；
#   R-POL-05 拒绝原因显名输出（deny_reasons = 审计行/POLICY_DECISION 证据原料）。
#
# 输入契约（网关从注册表信任源装配 tool_decl，调用方不可伪造工具声明）：
# {
#   "tool":   "write_customer_data",
#   "params": { ... },
#   "caller": { "person_id": "PSN-...",
#               "roles": ["execution"|"coordination"|...],
#               "active_authorizations": ["<tool_name>" | "<prefix>*", ...] },
#   "parent_task_scope": ["public" | "internal" | "customer_data", ...],
#   "tool_decl": { "required_scope": "public"|"internal"|"customer_data",
#                  "judicial": true|false,
#                  "idempotency_key_required": true|false }
# }
# 查询面：POST /v1/data/dga/action/tool_invoke（布尔 allow）；
#         POST /v1/data/dga/action/deny_reasons（拒绝原因集合）；
#         POST /v1/data/dga/action/decision（allow + deny_reasons 合并对象）。
package dga.action

import rego.v1

default tool_invoke := false

# ---- scope 词表（与 ar_tools.required_scope 的 CHECK 约束同源）----
scope_known(s) if s in {"public", "internal", "customer_data"}

# ---- 执行者角色（本体 RoleType=EXECUTION；兼容任务书字面 "executor"）----
executor_role if "execution" in input.caller.roles
executor_role if "executor" in input.caller.roles

# ---- 输入合法性（未知 scope / 缺数组一律拒绝，不默认放行）----
input_valid if {
	is_string(input.caller.person_id)
	input.caller.person_id != ""
	is_array(input.caller.roles)
	is_array(input.caller.active_authorizations)
	is_array(input.parent_task_scope)
	count(input.parent_task_scope) > 0
	every s in input.parent_task_scope { scope_known(s) }
	scope_known(input.tool_decl.required_scope)
	is_boolean(input.tool_decl.judicial)
}

# ---- 规则① 授权：active_authorizations 含工具名，或通配受限集（尾缀 * 前缀模式）----
authz_exact if input.tool in input.caller.active_authorizations

authz_prefix if {
	some p in input.caller.active_authorizations
	endswith(p, "*")
	startswith(input.tool, trim_suffix(p, "*"))
}

authz_ok if authz_exact

authz_ok if authz_prefix

# ---- 规则② R-POL-02：required_scope ∈ parent_task_scope（子集检查，缺一即拒）----
scope_ok if input.tool_decl.required_scope in input.parent_task_scope

# ---- 规则③ R-POL-04：执行者角色不得调用 judicial=true 工具（判定隔离，与授权无关地独立拒绝）----
judicial_ok if not input.tool_decl.judicial

judicial_ok if {
	input.tool_decl.judicial
	not executor_role
}

# ---- 判定 ----
tool_invoke if {
	input_valid
	authz_ok
	scope_ok
	judicial_ok
}

# ---- 拒绝原因（审计行 fail_reason / POLICY_DECISION 证据原料，R-EVID-01/R-POL-05）----
deny_reasons contains "R-POL-INPUT-INVALID" if not input_valid
deny_reasons contains "R-POL-AUTHZ-MISSING" if {
	input_valid
	not authz_ok
}
deny_reasons contains "R-POL-02-SCOPE-ESCALATION" if {
	input_valid
	not scope_ok
}
deny_reasons contains "R-POL-04-JUDICIAL-ISOLATION" if {
	input_valid
	not judicial_ok
}

decision := {"allow": tool_invoke, "deny_reasons": deny_reasons}
