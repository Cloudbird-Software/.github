# SEL-01 调研报告：控制面技术栈（M1 控制面 v0）

- 日期：2026-09-06（本机建设当夜批次）
- 决策级别：**可逆实现选择**（DGA-INFRA 8.1 裁决权分配表第一行："库级选型、客户端、格式细节、可逆实现选择 → 执行 agent 可定（记录理由）"）。不触碰架构分层（CMP-01 已由 S5 定：自研薄服务 + PostgreSQL），故不升级 S5。
- 强制约束（引用 R 条目）：
  - CMP-01：薄服务 + PostgreSQL，禁止自研通用工作流引擎（Temporal 已另立，SEL-02）。
  - 六元组 schema 直映射：控制面对象结构必须与 M0 产物 `schemas/dga-ontology.yaml`（→ gen-json-schema / gen-sqlddl）一致，不允许第二套手写模型漂移。
  - R-GOV-01：控制面 DB 是"已接受承诺/有效授权/判定状态/闭环登记"的唯一权威源，服务只是薄壳。
  - R-GOV-03：缺具名责任人的闭环必须在创建入口被拒绝（API 校验 + DB NOT NULL 双层）。
  - R-GOV-04 / R-SEC-04：S5 决策卡片固定结构；签发不可代（M1 以 addressee 头校验做最小形态）。
  - PR-INF-01：客户可复刻四问——组件须可合法部署、有单机起步路径、无强制云绑定。

## 1. 候选集

| 候选 | 许可证（核实日期 2026-09-06，本地 pip 元数据） | 形态 |
|---|---|---|
| Python 3.11 + FastAPI + uvicorn + psycopg3（同步） | FastAPI/uvicorn/starlette=BSD-3/PSF 系，psycopg3=LGPL-3.0（pip show License 字段，本机 .venv 实装） | 单进程 ASI，路由函数直映射端点 |
| Python 3.11 + Flask + psycopg3 | Flask=BSD-3 | WSGI，需自拼校验/文档 |
| Python 3.11 + Django + DRF | Django=BSD-3 | 全家桶：自带 ORM/迁移/admin，形成第二套模型层 |
| Node 24 + Express/Fastify | MIT | 与 gen-python 产物不同语言，schema 对齐需另建链路 |

版本快照（本机 `.venv` 实装，`pip list` 2026-09-06）：Python 3.11.9、fastapi 0.141.1、uvicorn 0.52.4、starlette 1.6.0、psycopg 3.3.5（psycopg-binary 3.3.5）、pydantic 2.13.5（linkml 1.11.1 已引入）。

## 2. 评估矩阵（逐项本地可验证事实）

| 维度 | FastAPI 薄层 | Flask | Django+DRF | Node |
|---|---|---|---|---|
| 六元组 schema 直映射 | **pydantic v2 模型可由 linkml 产物对齐**（`gen-json-schema` 的 $defs 已在位；必要时 datamodel-code-gen 从 JSON Schema 生成 pydantic，无手写漂移源） | 手写 marshmallow/pydantic 自拼 | DRF Serializer = 第二套模型定义，漂移风险最高 | 需换语言重新生成（gen-python 产物不可用） |
| 校验与错误码 | pydantic 缺字段天然返回 **422**（R-GOV-03/04 API 层校验零成本） | 手写 | 可做但绕 ORM | 手写 |
| 部署复杂度 | **单进程 `uvicorn` 单命令**，Windows 原生无服务化依赖 | 同级低 | 较高（迁移/settings/admin 表面大） | 低但异构 |
| 团队形态（一人 + agent） | 类型注解 + OpenAPI 自文档，agent 可机械核对 | 无自文档 | 约定魔法多 | 异构栈分摊注意力 |
| 与 PG 权威源的关系 | psycopg3 同步薄查询，SQL 即映射（gen-sqlddl 的表就是 API 的表），**无 ORM 中间层** | 同 | ORM 反向遮蔽 gen-sqlddl 产物 | pg 驱动另选 |
| 客户可复刻四问 | ①许可证可商用部署 ②单文件 main.py 起步路径 ③无云绑定 ④开源版无功能缺失 | 同 | 同 | 同 |

## 3. 推荐与理由

**Python 3.11 + FastAPI + uvicorn + psycopg[binary]（同步薄层）**，推导链：

- CMP-01"薄服务"→ 拒绝 Django（ORM/admin 是第二套权威模型，违 R-GOV-01 单一主写者精神）；选路由函数 + 裸 SQL 的直映射。
- 六元组 schema 直映射 → pydantic v2 与 linkml `gen-json-schema` 同源（JSON Schema 为交汇格式），请求模型逐字段对齐 $defs；DB 侧直接使用 gen-sqlddl 的表（`ClosureUnit`/`AccountabilityLink`/`S5DecisionCard`/`Authorization`…），API 字段名 = schema 槽位名。
- 团队 = 一人 + agent → 同步 psycopg（不做 async），代码路径线性、易审计；单进程部署（本机阶段无水平扩展需求，扩容是 M6+ 服务器阶段议题）。
- R-GOV-03 双层拒绝：pydantic `required` → FastAPI 自动 422；DDL `ClosureUnit.accountability_id NOT NULL + FK` 兜底。

## 4. PoC 与负面测试

M1 控制面 v0 即 PoC。负面测试四案例见 `controls/negtest-m1.md`（缺 accountability→422+DB 无行、决策卡缺字段→422、错人 resolve→403、阳性对照闭环）。全部通过后本选型生效。

## 5. 待 S5 追认点（默认方案先行，不阻塞）

1. 身份体系占位：R-SEC-04 以 `X-S5-Person` 头 = 卡片 addressee 的最小形态落位，真实身份体系（OIDC/应用身份）待服务器阶段（M6+）设计。
2. pydantic 模型当前手工对齐 gen-json-schema 的 $defs；是否引入 datamodel-code-gen 自动生成属格式细节，随本体演进再定。
3. 端口 8090 / 库 dga_control 为本机约定，服务器阶段重排。

## 6. 回滚与迁移成本

- 换框架（FastAPI→Flask/Litestar 等）：**只动 adapter 层**。结构刻意三层——`app/db.py`（唯一 SQL 触点）/`app/api.py`（路由+pydantic 入参）/`app/main.py`（组装）。路由函数体是纯"校验→SQL→JSON"，换框架=重写 api.py 的装饰器与错误映射（估数百行级），db.py 与 DDL 不动。
- 换驱动（psycopg3→async/连接池）：仅 db.py。
- 换语言/运行时：需重走 schema 对齐链路（gen-json-schema→目标语言代码生成），成本最高，仅在 S5 裁决架构变更时发生。
- DDL 侧回滚见 `catalog/sel/SEL-01-ddl-patch.sql` 头注（生成物三处 PG 兼容性修正可由 gen-sqlddl 重放）。
