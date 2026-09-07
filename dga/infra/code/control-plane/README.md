# DGA 控制面 v0（M1）

薄服务（CMP-01：核心资产 = 承诺→闭环→授权→执行→证据→判定→责任的连接关系）。
技术栈与理由见 `gov-infra-repo/catalog/sel/SEL-01.md`：Python 3.11 + FastAPI + uvicorn +
psycopg3（同步薄层，无 ORM）。DB DDL = `gov-infra-repo/schemas/generated/dga-ontology.sql`
（PG 兼容补丁见 `gov-infra-repo/catalog/sel/SEL-01-ddl-patch.sql`）。

## 运行

```bash
# 常驻（幂等：端口占用即跳过；日志 services/control-plane/run.log）
services/scripts/start-control-plane.sh
services/scripts/stop-control-plane.sh

# 前台调试（工作目录 = control-plane/）
D:/Projects/dga-infra/.venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8090
```

- 端口 8090；连接串默认 `postgresql://dga@localhost:5432/dga_control`（环境变量 `DGA_CONTROL_DSN` 覆盖）。
- OpenAPI 自文档：`http://127.0.0.1:8090/docs`。

## 结构（三层，换框架只动 api.py —— SEL-01 回滚成本）

| 文件 | 职责 |
|---|---|
| `app/main.py` | FastAPI 组装 + `GET /healthz`（DB 连通/表数/版本，故障 → 503） |
| `app/api.py` | 路由 + pydantic 入参校验（422 出口）+ R 条目锚点 |
| `app/db.py` | 唯一 SQL 触点：连接管理、发号（LinkML ID pattern）、外键目标存在性校验 |

## API 清单

| 端点 | 说明 | 治理锚点 |
|---|---|---|
| `GET /healthz` | DB 连通 + public 表数 + PG 版本 | — |
| `POST /closures` | 六元组闭环登记。**缺 `accountability` → 422**（pydantic required + `ClosureUnit.accountability_id NOT NULL+FK` 双层）；引用的 Intent/Capability/Person/ContextAsset/ActionType/EvidenceEntity 不存在 → 422 | R-GOV-03 |
| `GET /closures/{id}` | 单条（含 accountability 归属人 + 三分量挂接清单） | R-GOV-01 |
| `GET /closures?state=&limit=` | 列表 | — |
| `POST /decisions` | S5 决策卡片入队。**任一必填字段缺失 → 422**（object/evidence/options/recommendation/deadline/consequences + addressee） | R-GOV-04 |
| `GET /decisions/queue` | pending 队列（按 deadline 排序） | R-GOV-07 |
| `GET /decisions/{id}` | 单卡（含 options/evidence/裁决状态） | — |
| `POST /decisions/{id}/resolve` | 裁决 `{"decision":"approved"|"rejected","decided_by":"PSN-xxxx"}`。**`X-S5-Person` 头缺失/≠卡片 addressee/≠decided_by → 403**；已裁决 → 409 | R-SEC-04 |
| `POST /authorizations` | 授权签发：scope/budget{currency,amount_cap,period}/decision_timespan 强制在位 | R-POL-02、R-POOL-BUDGET |
| `GET /authorizations`、`GET /authorizations/{id}` | 授权查询（含预算与 scope 展开） | — |

字段名 = LinkML 槽位名；状态/等级枚举（ClosureState、AutonomyLevel、TrustLevel 等）
与 `schemas/generated/dga-ontology.schema.json` 同源键名。决策时距用 ISO 8601
duration（`PT8H`/`P1D`，= base.yaml DecisionTimespan pattern）。

## 诚实边界（v0 不假装的部分）

1. **身份体系是占位**：`X-S5-Person` 头是 R-SEC-04 的最小形态——只证明"调用方
   声称的身份 = 卡片 addressee"。真实身份体系（应用身份/OIDC，R-SEC-01/02）待
   服务器阶段（M6+）设计；在那之前任何知道 PSN id 的本机调用方都能通过该头冒充，
   本机单用户环境下可接受，不得延伸到生产。
2. **主数据无 CRUD**：Person/Intent/CapabilityEntity/ContextAsset/ActionType/
   EvidenceEntity 等 master data v0 经 SQL 直接登记（负面测试脚本含幂等 seed）；
   管理界面随飞书工作台/资产目录阶段补。
3. **飞书四工作台未做真实集成**（无凭据）：字段映射与前置条件见
   `gov-infra-repo/connectors/feishu/README.md`。
4. **谓词级授权不在本服务**：权限/预算/时距的强制执行点是 OPA + 工具网关
   （R-POL-01，M4）；本服务只保证授权**记录**的权威性与结构完整。
5. `cp_decision_addressee` 是控制面自有运行时表（`SEL-01-ddl-patch.sql` [F3]）：
   S5DecisionCard 本体无 addressee 槽位，本体加槽属 S5 裁决，待升级后迁移。
