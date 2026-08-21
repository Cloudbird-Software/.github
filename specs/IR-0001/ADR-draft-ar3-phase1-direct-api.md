# ADR-XXXX: 第一期允许直连 provider API（AR-3 的第一期形态）

> 状态：草案（随 spec IR-0001 评审；批准后编号并正式落于 agent-registry/decisions/）
> 修订对象：GOVERNANCE.yaml AR-3（"模型接入一律经 LLM Gateway；provider key 仅存 gateway secret store"）
> 关联：IR-0001 spec DECISION-01；ADR-0002 rev1（llm-gateway 部署）

## 上下文

AR-3 的意图有三：① agent 声明与 provider 解耦（alias 间接层）；② 明文 key 不出现在仓库/配置；
③ 用量可按团队计量、配额可控。llm-gateway（LiteLLM）是满足全部三条的实现，但它要求一台
常驻机器（VPS/家用盒/NAS）。GitHub 生态内不存在免费托管持久服务的途径（Actions 不能当服务器）；
免 VM 的 serverless 替代品（如 Cloudflare AI Gateway）缺少 per-team 虚拟 key 配额能力，
且仍引入新的外部服务依赖。owner 裁定：第一期的运维成本大于收益。

## 决定

第一期（自本 ADR 生效起，至"回切触发条件"任一满足止）：

1. 模型接入允许直连 provider API；provider key 只存 org secret `LLM_API_KEY`，
   仓库/agent 配置/声明中零明文 key 的要求**不变**（AR-3 的意图②保留）。
2. 一切 LLM 调用必须经计量 wrapper，逐次落盘 model/prompt 版本/采样参数/用量
   （意图③降级为"只计量不熔断"，数据保留供后续预算化）。
3. alias 间接层（意图①）以 `pipeline/models.yaml` 的"角色档 → 具体模型 + 采样参数"
   解析表实现，版本化、改动走 PR；agent 声明仍只引用角色档，不直写 provider 模型名。
4. registry/models.yaml 的 alias 语义与 AR-8 族级独立要求**继续有效**，作为角色档的定义源。

## 回切触发条件（任一满足即重启 gateway 评估）

- 需要 per-team/per-agent 配额或预算熔断；
- 需要多 provider failover；
- 需要按角色档的成本归账（wrapper 计量显示成本结构失控）；
- 组织有了事实上的常驻机器（家用盒/便宜 VPS 被用于其他目的，gateway 可搭车）。

## 后果

- 正面：零新增基础设施，编排闭环可立即开工；计量数据不丢，回切无障碍。
- 负面：无集中 kill switch（只能靠轮换 org secret）；无配额硬限制（只有事后计量）；
  provider key 的暴露面从"gateway secret store"变为"GitHub org secrets + Actions runner 内存"。
- 缓解：key 轮换流程文档化；cost-check 的 LLM 预算通道数据源从 gateway usage 端点
  改为 wrapper 落盘的 artifact 汇总（原定 pending 项的替代实现）。
