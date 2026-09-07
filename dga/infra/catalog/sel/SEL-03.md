# SEL-03 调研报告：OPA 集成模式（sidecar/库嵌入/独立服务 · bundle 签名 · decision log 入证据层）

- 任务来源：DGA-INFRA 8.2 SEL-03；CMP-03（OPA，S5 已定全量建设）；本机现状：OPA 1.20.2 独立服务 127.0.0.1:8181 已跑（services/opa/HEALTH.txt，2026-09-06 核验）
- 核实日期：2026-09-06/07（OPA v1.20.2 发布于 2026-09-03，为撰写时 latest）
- 引用基准说明：官方文档站（www.openpolicyagent.org）对本环境自动化抓取返回 404（反爬/结构待核，2026-09-07 两端点实测），故引用**官网文档的构建源文件**——GitHub `open-policy-agent/opa` 仓 `docs/docs/*`（main 分支 raw，逐字行号）。两者为同一内容，源文件更可核。

## 1. 任务范围与强制约束

- R-POL-01：权限检查在工具网关/服务端强制执行——OPA 形态必须支撑"真实拒绝"，不能停在提示词级。
- R-POL-05：OPA decision log 入证据流（策略判定记录=一等公民证据）——本报告 §3-4 给管道拓扑。
- R-POL-02/03：子任务权限≤父任务、虚拟 key 限额联动——决策输入需含授权上下文。
- 第 0 章修正声明②：**"OPA 内嵌代码替代方案"已被推翻**，全量建设=含管理面（bundle/status/decision log）的完整 OPA，不是裸求值库。
- CMP-03 定位原文："策略与执行点分离。策略进 Git，bundle 分发，decision log 作为证据流的一部分"。
- 本机约束：Windows x64、无 Docker（BUILD-LOG 环境侦察）。

## 2. 候选集（引擎已定，候选=集成形态）

| 候选 | 形态 | 官方文档出处 |
|---|---|---|
| A | **独立服务 / host-level daemon / sidecar（REST API 求值）** | docs/docs/integration.md（"Integrating with the REST API"节）；docs/docs/deploy/index.mdx |
| B | Go SDK 嵌入（库级进程内，**含管理面**：bundle/decision log 插件） | integration.md "Integrating with the Go SDK"节 |
| C | Go rego 库嵌入（仅求值，无管理面）/ Wasm | integration.md "Integrating with the Go API"节、"WebAssembly"节 |

## 3. 评估矩阵

### 3.1 许可证原文结论

- 来源：[open-policy-agent/opa LICENSE](https://raw.githubusercontent.com/open-policy-agent/opa/main/LICENSE)（raw 逐字核对，2026-09-07）："Apache License / Version 2.0, January 2004"。
- 结论：**Apache-2.0**。客户可复刻四问：①可合法部署（无使用领域限制）；②部署文档/单机起步=官方 docs 全套（本报告 §3 各出处）；③无强制云绑定（二进制自托管，`opa run -s` 即服务）；④复刻缺失项=无（企业版不存在；Styra DAS 是外部服务非二进制功能锁）。四问全过。

### 3.2 三形态官方对比（integration.md L488-493，表格逐字）

| Dimension | REST API | Go Lib | Wasm |
|---|---|---|---|
| Evaluation | Fast | Faster | Fastest |
| Language | Any | Only Go | Any with Wasm |
| Operations | Update just OPA | Update entire service | Update service rarely |
| Security | Must secure API | Enable only what is needed | Enable only what is needed |

部署面补充（deploy/index.mdx L28-34 表格逐字，Sidecar/VM Node Agent vs Centralized OPA Service）：

| | Sidecar or VM Node Agent | Centralized OPA Service |
|---|---|---|
| Latency | Very Low, decisions are local | Higher latency, decisions involve network hops |
| Fault Tolerance | More fault tolerant, works without network connectivity | Failure point if not highly available |
| Use Cases | Containers, Service Mesh, Authorizing Proxy/Gateway, IoT/Edge | Large data volumes, Serverless, Batch/CI Jobs |

官方倾向性原文（integration.md L40-42）："deploy OPA as a **host-level daemon or sidecar container**. Running OPA locally on the same host as your application or service helps ensure policy decisions are fast and highly-available."；L495-498："OPA is most often deployed either as a **sidecar or less commonly as an external service**."

### 3.3 形态裁决（对照 DGA 栈）

- **候选 B/C（Go SDK / Go rego 库）出局**：只适用 Go 宿主（"Only Go"），而 DGA 控制面=Python（SEL-01：FastAPI+psycopg3）；且 C 无管理面（bundle/decision log 全要自实现，integration.md L506-508）直接违反修正声明②的"全量建设"。
- **候选 A 胜出**：语言无关、独立升级（"Update just OPA"）、bundle/decision log 原生。服务器形态取 **per-host 独立服务**（与工具网关/MCP 网关同机，本地 127.0.0.1 回路得低延迟）而非集中式：R-POL-01 的执行点是网关，"OPA is generally best located as close as possible to the PEPs"（deploy/index.mdx L17-19）；集中式单点故障与 R-IR/验收"撤权演练"相性差。
- 本机现状=候选 A 的 Windows 落地（`opa_windows_amd64.exe v1.20.2`，`opa run -s`，:8181，HEALTH.txt 两态判定 GREEN）——**形态无需切换，仅需补 bundle 签名与 decision log 管道（§3.4/§3.5）**。

### 3.4 bundle 分发与签名（management-bundles/index.md）

- 分发（L70-101）：Bundle Service API=静态可下载 tarball（"GET /<service path>/<resource>"，"a gzipped tarball in the message body"），配置 `services`+`bundles` 两节即拉取；`opa build -b foo/` 构建（L47-52），`--optimize` 可选。**Git 仓库即 bundle 服务源**（GitHub Raw/自托管静态文件均可承载），对照 R-CFG-01"策略进 Git"。
- **签名机制=JWT/JWS，非 cosign**（L474-485 逐字）：

> "a signed bundle is a normal OPA bundle that includes a file named `.signatures.json` … The signatures file is a JSON file with an array of **JSON Web Tokens (JWTs)** that encapsulate the signatures for the bundle."

> "When OPA receives a new bundle, it checks that it has been properly signed using a (public) key that OPA has been configured with out-of-band. Only if that verification succeeds does OPA activate the new bundle; otherwise, OPA **continues using its existing bundle** and reports an activation failure via the status API."

- 载荷=文件名+SHA-256 哈希清单（L520-535）；验证矩阵（L584-589）：无签名+未配置验签=直接激活（弱默认！）；有 `.signatures.json`+未配置=**fail**（防降级）。命令：`opa build --verification-key public.pem --signing-key private.pem --bundle foo/`（L65）。
- **cosign 答案**：OPA 原生不集成 Sigstore/cosign；想换验证逻辑走 Signature Plugin 扩展点（L616-630，自写 Go Signer/Verifier 注册同 key）。结论：**默认用原生 JWT 签名**（私钥入 OpenBao，R-SEC-02），cosign 不引入——避免为签名而新增 Sigstore 依赖链。Filesystem bundle 验签走 `--verification-key` 指向 PEM（L488 warning 节，本机 `--bundle` 模式适用）；`opa eval/test` 等预生产子命令**不验签**（同 warning 节原文）——负面测试须用 `opa run -s` 真实路径。
- 弱默认加固：必须给每个 bundle 配 `keys` 强制验签（L586-587 行为），否则签名体系形同虚设——进 M4 验收。

### 3.5 decision log 管道（management-decision-logs.md）→ 入证据层拓扑

- 事件面：OPA 周期批量上报（"OPA can periodically report decision logs to remote HTTP servers, using custom plugins, or to the console output; or any combination thereof." L5-6）；远程端点=`POST /[decision_logs.resource]` 默认 `/logs`，"gzip compressed JSON array"（L20-31）。
- 字段（L63-84，审计要点）：`decision_id`（"Unique identifier generated for each decision for traceability"）、`bundles.authz.revision`（**判定所用 bundle 版本**——证据自带策略版本）、`path`（决策路径）、`input`、`result`、`timestamp`、`erased/masked`（脱敏指针）、`trace_id/span_id`（W3C trace-context，可关联 OTel——R-OBS-01）。
- 可靠性（L86-89 逐字）："If the service responds with a non-2xx status, OPA will **requeue** the last chunk containing decision log events and upload it during the next upload event. OPA also performs an **exponential backoff**…"→ **at-least-once**，证据侧须按 `decision_id` 去重。
- 本机通道：`decision_logs.console=true`（L115-118）→ stdout 落 services/opa/run.log，零依赖起步。
- **推荐拓扑（对照 R-POL-05/R-EVID-03，M4 落地）**：

```
OPA(:8181) ──decision_logs──> 控制面 POST /v1/opa/logs（唯一写者）
   ├─ 本机：console→run.log（现状）+ M4 起控制面接收端
   ├─ PG 表 opa_decisions：decision_id 主键去重 + 七元组
   │   (principal/action/resource/decision/policy_ids/request_id/latency — SEL-13e P4 字段集)
   │   + bundles.revision + input 摘要（敏感字段 masking 后）
   ├─ 每日归档：JSONL → B2 对象（版本+对象锁定，SEL-07 主选）+ SHA-256 入 PG
   └─ 审计阅读路径：控制面 API 按 closure/authorization 关联查询
```

- 证据纪律对照：R-EVID-03 防篡改证明"记录未被改"——归档件哈希在 PG、PG 行以 decision_id 幂等、对象锁定兜底；R-EVID-02 提醒：decision log=策略判定证据，≠Trace≠业务证据。

### 3.6 Windows 支持现状（逐 asset 核实，2026-09-07）

- GitHub releases/latest（api.github.com/repos/open-policy-agent/opa/releases）：**v1.20.2**（published 2026-09-03），Windows 资产=`opa_windows_amd64.exe`（64,005,120 B）+ `.sha256`。
- 本机实测：v1.20.2（Rego v1）:8181 两态判定通过、policies/ 目录多文件加载（M2 池路由谓词 10 项实测）——**Windows 原生支持为一等公民**（官方发布资产含 exe，非附带）。

## 4. 推荐与理由

**推荐：候选 A（独立服务）双阶段同形**——本机=Windows 原生 exe `opa run -s`（已就位），服务器=同形态 Linux 化 per-host 部署、与工具网关同机；bundle 从 Git 仓库构建+JWT 签名分发；decision log 经控制面接收端入 PG 证据表+对象锁定归档。

推导链：①修正声明②+控制面 Python（SEL-01）⇒库嵌入无路（§3.3）；②R-POL-01 执行点在网关⇒per-host 近 PEP 部署（deploy/index.mdx 原文判据）；③R-POL-05⇒decision log 是管道工程不是开关（§3.5 拓扑）；④PR-INF-01.e 客户可复刻⇒Apache-2.0+官方部署文档+无云绑定（§3.1 四问全过）；⑤M4 验收"越权调用被真实拒绝"⇒保持现有 `opa run -s`+policies/ 装载路径不变，增量只加签名与日志两端。

## 5. PoC 计划与对应负面测试清单

PoC 前置（M4 前，本机可做）：`opa build --signing-key/--verification-key` 生成签名 bundle；`opa run -s` 配 `bundles.keys` 验签加载；控制面 `/v1/opa/logs` 接收端+opa_decisions 表。

| # | 负面测试 | 期望 |
|---|---|---|
| N-1 | 篡改 bundle 内 policy 文件后投喂 | 验签失败，OPA **继续用旧 bundle 服务**且 status API 报 activation failure（对照 §3.4 原文行为） |
| N-2 | 已签名 bundle + OPA 未配置验签 | 拒绝激活（L588 "fail" 行为，防降级半吊子） |
| N-3 | 无签名 bundle + 配置了强制验签 | 拒绝激活（L587 行为，堵"弱默认"） |
| N-4 | 停控制面 /logs 端点 → 制造判定 → 恢复 | OPA requeue+退避（§3.5 原文），恢复后补投，按 decision_id 去重后零丢失零重复 |
| N-5 | 越权工具调用（MCP 网关→OPA deny） | HTTP 层真实拒绝且 deny 事件入 opa_decisions（M4 验收主项；M2 已有 OPA 谓词层前置验证） |
| N-6 | `opa eval` 直接跑"已签名"bundle | 不验签照跑（官方 warning §3.4）——登记为纪律：**验签结论只在 `opa run -s` 真实路径下有效**，防止测试假阳性 |

## 6. 待 S5 裁决点（每点附默认方案）

| # | 裁决点 | 默认方案（先行，待追认） |
|---|---|---|
| 1 | 服务器部署形态：per-host 独立服务 vs 集中式 OPA 集群 | **per-host**（近 PEP、无网络跳、故障域=单机；与 M4 工具网关同机 systemd 服务） |
| 2 | bundle 签名算法与密钥托管 | 原生 JWT 签名（RSA/ECDSA PEM），私钥入 OpenBao（R-SEC-02），公钥 out-of-band 配置；不引入 cosign/Sigstore |
| 3 | decision log 采样：全采 vs Deny 全采+Allow 采样（SEL-13e P4 模式） | **全采**（本机与早期量级小；Allow 采样会削弱 R-EVID-05"没有失败证据≠成功"的排查面）；量级超限再升 S5 |
| 4 | decision log 证据落点形态 | 控制面唯一写者→PG `opa_decisions`（decision_id 幂等）→每日 JSONL 归档 B2（对象锁定）+SHA-256 回写 PG（SEL-07 主选联动） |
| 5 | bundle 载体：Git 仓库直出 vs 专用 bundle 服务 | **Git 仓库直出**（GitHub Raw/静态托管），CI 侧 `opa build`+签名产物另存；R-CFG-01 权威源纪律不变 |

## 7. 回滚与迁移成本

- OPA 版本升级/回滚：独立进程换二进制即可（形态红利）；策略行为回归=新旧版本影子跑同 input 比对 decision log（R-IR-03 影子运行）。
- 策略回滚：Git revert→重建重签 bundle→OPA 拉取新 revision（decision log 自带 revision 可审计到秒级切换点）。
- 签名体系故障：验签失败=沿用旧 bundle（官方行为）⇒服务不中断但策略冻结；私钥丢失=换 keypair+全量重签（runbook 项）。
- 引擎替换（若未来引入 Cedar 等）：Rego 策略不可移植，迁移=谓词重写+影子比对+单写切换（R-IR-03 全流程）；当前成本约束下不构成风险（CMP-03 已终裁）。

---

*引用清单（核实于 2026-09-06/07）：raw.githubusercontent.com/open-policy-agent/opa/main/{LICENSE, docs/docs/integration.md, docs/docs/deploy/index.mdx, docs/docs/management-bundles/index.md, docs/docs/management-decision-logs.md}；api.github.com/repos/open-policy-agent/opa/releases/latest（v1.20.2 Windows 资产逐 asset）；本机 services/opa/HEALTH.txt（2026-09-06）。*
