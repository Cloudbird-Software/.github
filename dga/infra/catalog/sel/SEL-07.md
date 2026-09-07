# SEL-07 调研报告：对象存储（版本化 + WORM 对象锁定）

- 任务来源：DGA-INFRA 第 8.2 节 SEL-07；CMP-09（候选：R2 / B2 / MinIO / S3）
- 调研执行：SEL 轨道执行 agent
- 核实日期：2026-09-06（全部事实当日核实；定价/能力均引自官方文档/定价页，未核实处显式标注）

## 1. 任务范围与强制约束

- **R-EVID-03（硬要求）**：重要证据 = 对象版本 + 内容摘要 + 独立写入权限 + **对象锁定**；防篡改证明"记录未被改"，不证明"记录为真"。
- R-EVID-01/R-EVID-02：证据契约独立定义；Trace ≠ Evidence——对象存储承载的是**证据本体**（执行收据/验收判定/签发记录/校准资产），不是观测 trace。
- 第 6 章 M6：证据层 = 证据契约 + 对象存储版本锁定，验收点含"对象锁定验证"。
- 第 9 章第 6 项：证据对象锁定保留期 = 待 S5（S5-PENDING-DEFAULTS 第 6 项默认：无限期+锁定）。
- 8.4：客户可复刻四问；出口费与锁定语义必须官方文档核实。

## 2. 候选集（CMP-09 指定四候选）

| 候选 | 形态 | WORM 语义 |
|---|---|---|
| A | Backblaze B2（云） | S3 Object Lock（governance/compliance/legal hold） |
| B | Cloudflare R2（云） | Bucket Locks（R2 专有 API） |
| C | MinIO（自托管） | S3 Object Lock（社区版现仅源码分发） |
| D | Amazon S3（云） | S3 Object Lock（语义基准） |

## 3. 评估矩阵

### 3.1 版本化支持（官方文档，2026-09-06）

| 候选 | 版本化 | 来源 |
|---|---|---|
| B2 | **桶天然永远版本化**（无法关闭；S3 删除产生 hide/delete marker 而非物理删除；生命周期规则管旧版本清理，每桶至多 100 条规则） | [File Versions](https://www.backblaze.com/docs/cloud-storage-file-versions)、[S3 API Bucket Versions](https://www.backblaze.com/docs/cloud-storage-s3-compatible-api-bucket-versions)、[Lifecycle Rules](https://www.backblaze.com/docs/cloud-storage-lifecycle-rules) |
| R2 | 支持（S3 兼容 API 列出 `PutBucketVersioning`/`ListObjectVersions`；专用 object-versioning 文档页存在于文档树） | [R2 S3 API 兼容表](https://developers.cloudflare.com/r2/api/s3/api/)（核实 2026-09-06） |
| MinIO | 需启用桶版本化（对象锁定前提，S3 语义） | [AIStor 对象锁定文档](https://docs.min.io/aistor/administration/object-locking-and-immutability/)（经搜索定位，2026-09-06） |
| S3 | 对象锁定仅在启用 Versioning 的桶上工作（原文："Object Lock works only in buckets that have S3 Versioning enabled"） | [S3 Object Lock 用户指南](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)（全文核实 2026-09-06） |

### 3.2 对象锁定 / WORM 细节（官方文档原文核实，2026-09-06）

**B2** — [Object Lock 文档](https://www.backblaze.com/docs/cloud-storage-object-lock)：

- **Governance mode**：有相应 app key 能力者可修改/覆盖保留设置。
- **Compliance mode**："cannot be removed by any user"——任何人不可移除（保留期可由授权客户端延长）；**启用后桶设置不可关闭**（"you cannot disable this setting"）。
- **Legal hold**：独立于保留期，无到期日。
- 保留期 **1–3,000 天**；只能延长不能缩短；使用 S3 兼容 API 与 Native API 双通道（含 `aws s3api` 示例）；"There is no extra cost to use Object Lock"。
- 风险披露（文档原话警示）：compliance 锁定过量 → 只能关户 escape。

**R2** — [Bucket locks 文档](https://developers.cloudflare.com/r2/buckets/bucket-locks/)（2025-03-06 上线，[changelog](https://developers.cloudflare.com/changelog/post/2025-03-06-r2-bucket-locks/)）：

- 语义："prevent the deletion and overwriting of objects in an R2 bucket for a specified period — or indefinitely"。
- **R2 专有 API**（PUT `.../lock` + wrangler `r2 bucket lock`），**非 S3 Object Lock API**；规则按前缀作用，`Age`（maxAgeSeconds）与 `Indefinite` 两型；最多 1,000 条规则；多规则取最长保留；规则优先于生命周期；**配置了规则的桶不能被清空**。
- **无 governance/compliance 模式之分**（页面未出现该二分），锁定由桶规则表达而非逐对象元数据。
- 无 S3 逐对象 Retention/LegalHold 等价 API（该页未声称兼容）。

**MinIO** — 文档现位于 AIStor 域：[Object Locking and Immutability](https://docs.min.io/aistor/administration/object-locking-and-immutability/)：

- 支持 governance/compliance/legal hold，引用 Cohasset 对 SEC 17a-4(f)/FINRA 4511(c)/CFTC 的合规评估（搜索定位该页，2026-09-06；S3 API 语义与 AWS 对齐）。

**S3** — [Object Lock 用户指南](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)（全文核实）：

- Compliance mode：**root 在内任何用户不可删不可改，保留期不可缩短**（"The only way to delete an object under the compliance mode before its retention date expires is to delete the associated AWS account."）。
- Governance mode：持 `s3:BypassGovernanceRetention` 可绕过（用于演练/纠错）。
- Legal hold：无到期、独立生效；版本级粒度；Cohasset 合规评估（SEC 17a-4/CFTC/FINRA）。

### 3.3 出口费与存储价（官方定价页，2026-09-06）

| 候选 | 出口费 | 存储价 | 来源 |
|---|---|---|---|
| R2 | **全免**（"no charges for egress bandwidth for any storage class"） | $0.015/GB-月（Standard）；免费层 10GB-月 + 100 万 Class A + 1000 万 Class B | [R2 Pricing](https://developers.cloudflare.com/r2/pricing/) |
| B2 | **免费至平均月存储量 3 倍**；超出 $0.01/GB；伙伴 CDN（Cloudflare/Fastly/bunny 等）全免；前 10GB 存储免费 | $6.95/TB-月 起（≈$0.0068/GB-月） | [B2 Pricing](https://www.backblaze.com/cloud-storage/pricing) |
| S3 | 出口收费：每月前 100GB 跨服务免费额度；超出按档计费（页面表格为 JS 渲染未出全量数字；页内示例：Europe(Ireland)→internet $0.09/GB） | 未能在本轮渲染出 S3 Standard 每档单价（页面占位符）——**未核实，不引用数字** | [S3 Pricing](https://aws.amazon.com/s3/pricing/) |
| MinIO | 自托管：出口流量成本=自己的带宽，无云出口费 | 自托管：硬件成本 | （自托管属性推论，非定价页） |

### 3.4 MinIO Windows 原生可跑性（本机建设关键项，逐项核实 2026-09-06）

- [minio/minio LICENSE](https://github.com/minio/minio/blob/master/LICENSE)：**GNU AGPL v3**（原文逐字核对头部）。
- [README](https://github.com/minio/minio/blob/master/README.md) 原文（逐字核对）："**The MinIO community edition is now distributed as source code only. We will no longer provide pre-compiled binary releases for the community version.**" 安装路径 = `go install github.com/minio/minio@latest` 或自行 Docker 构建；"Production environments using compiled-from-source MinIO binaries do so at their own risk."
- GitHub API [releases/latest](https://github.com/minio/minio/releases)（2026-09-06）：最新社区 release **RELEASE.2025-10-15T17-29-55Z**（2025-10-16 发布），**资产数 = 0**（无任何预编译二进制，含 Windows）——与 README 声明互证。
- README 亦指路：**AIStor Free**（"Full-featured, standalone edition for community use (free license)"，下载页 min.io/download）。该下载页本轮抓取超时，**AIStor Free 是否提供 Windows 原生构建未核实**——登记 §6。
- **本机结论：MinIO Windows 原生 = 只能 Go 源码自建（理论可行、无官方支持、AGPL 义务）；预编译路径不存在。** 对"无 Docker 本机"是最差的四候选。

### 3.5 客户可复刻四问（按候选）

| 四问 | B2 | R2 | MinIO（社区） | S3 |
|---|---|---|---|---|
| ① 合法部署/使用 | 能（商用云服务条款） | 能 | **有条件**：AGPL v3——网络服务使用亦触发开源义务（AGPL 第 13 条语义），商用需过 AGPL 合规评估（README 自己警告"Any commercial/proprietary usage ... at your own risk"） | 能 |
| ② 部署文档/单机起步 | 有（docs 站 + S3 兼容示例） | 有（R2 docs + wrangler） | 社区=源码自建，文档移至 AIStor 域；单机起步路径恶化 | 有（完整文档体系） |
| ③ 强制云绑定/锁定 | 云服务（数据可 S3 API 全量搬出；锁定合规桶注意不可关设置） | 云服务（专有 lock API 是迁移摩擦点） | 无（自托管即卖点） | 云服务（最深的生态引力） |
| ④ 复刻缺失项 | — | S3 Object Lock API 不兼容（§3.2） | 企业功能（AIStor）缺失；预编译/支持缺失 | 企业级（对象归档深冷/跨区强一致选件）按需 |

### 3.6 对照 R-EVID-03 的语义覆盖（版本+摘要+独立写入权限+锁定）

- **版本**：四者均满足（B2 天然版本化；R2/S3/MinIO 开启版本化）。
- **锁定**：B2/S3/MinIO = 完整 S3 Object Lock 语义（governance/compliance/legal hold，compliance 不可撤销）；**R2 = 桶级 WORM（可用但非标）**：无逐对象 legal hold、无 governance/compliance 二分、锁规则随桶配置而非对象元数据走——证据随桶迁移时锁定语义**不随对象走**，这是 R2 相对硬伤。
- **内容摘要**：由证据契约层承担（写入时 SHA 校验与清单，见 §5 PoC），与厂商无关。
- **独立写入权限**：S3/B2/R2 均可用 IAM/app key 做只写执行单元账号（执行单元无删读全权）；B2 的 key capability 模型 + governance mode 可把"绕过权"与"写入权"分离给 S5 角色——映射 R-EVID-03"独立写入权限"最顺。

### 3.7 证据对象写入权限矩阵与命名纪律（设计判断）

R-EVID-03"独立写入权限"的落位设计（能力依据见 §3.2/§3.5-独立写入权限行）：

| 角色 | B2 侧凭据 | 权限 | 依据 |
|---|---|---|---|
| 执行单元 | 只写 app key（无删除/无列出全权） | PUT 对象 + 附 retention/legal-hold | 写入即锁定，杜绝"先写后锁"窗口 |
| 证据服务（控制面） | 读写 key（无 bypass） | PUT/GET/清单核对 | 摘要清单维护（R-EVID-01） |
| S5 | 独立 key + governance bypass 能力（仅 governance 桶演练用；compliance 桶无 bypass） | 审计、延长保留 | 绕过权与写入权分离（§3.6） |
| 公示管道 | 只读 key | GET | R-OBS-02 公示读侧 |

命名纪律（证据契约的一部分，R-EVID-01）：`evidence/<闭环ID>/<步骤>/<对象ID>-<SHA256前16>`；版本 ID 与摘要入控制面 DB 清单（§5 PoC-2）。B2 生命周期规则只对**非 evidence 前缀**生效——evidence 前缀无清理规则，锁定语义与生命周期零耦合。

### 3.8 风险矩阵

| 风险 | 等级 | 依据 | 缓解 |
|---|---|---|---|
| B2 compliance 锁定过量（误锁） | 中 | 官方警示：只能关户 escape（§3.2） | 演练/测试桶用 governance mode；compliance 仅 evidence 前缀 |
| 保留期表达"无限期"依赖 legal hold | 中 | B2 保留期上限 3,000 天（§3.2） | 双保险=legal hold + 3,000 天兜底（§6-2）；S5 定解除时点 |
| R2 锁定 API 非标（若启用冷副本） | 中 | §3.2 R2 专有 API | 副本仅投影（§4-4），不承载锁定权威 |
| MinIO 若被客户指定 | 中 | AGPL + 源码分发（§3.4） | 走 AIStor Free/商业授权另裁（§6-4） |
| S3 出口费未知项 | 低 | §3.3 未核实标注 | §6-6 补核后再评估 S3 为主的后备成本 |

## 4. 推荐与理由

**推荐：主选型 = 候选 A（Backblaze B2，compliance mode Object Lock）；S3 作为"客户已有 AWS"场景的对等适配目标（同一 S3 API 语义）；R2 降为"纯归档冷副本"次选；MinIO 移出默认候选（降级登记）。**

推导链（DGA-CORE 未交付，语义对应登记）：

1. R-EVID-03 硬要求逐字满足：B2 compliance mode = "cannot be removed by any user"，S3 API 原生语义，锁定元数据随对象走 → 客户复刻时换任何 S3 Object Lock 兼容后端（含 S3/MinIO AIStor）语义不变——**复刻叙事最硬**（PR-INF-01.a）。
2. 成本相权（PR-INF-01.c）：B2 $6.95/TB-月 + 3 倍存储量免费出口 + 无锁定附加费，覆盖证据层"写多读少"的访问形态；R2 出口全免费但 WORM 语义非标（资产侧让位于成本侧不符合 PR-INF-01.c 的"资产侧优先"）。
3. 风险不对称：MinIO 社区版停发二进制（§3.4）+ AGPL 对未来产品化的传染义务 → 与 PR-INF-02.b 产品化路径冲突，移出默认候选（保留为"客户要求数据完全本地"时的自托管选项，走 AIStor Free 或商业授权，届时另行裁决）。
4. R-IR-04/R-EVID-05：证据层唯一权威源原则——多副本（B2 主 + 可选 R2 冷备）中只有 B2 compliance 锁定副本为"证据本体"，R2 副本标注为投影，防双权威源。

## 5. PoC 计划与对应负面测试清单

PoC（M6 证据层前置，本机用 S3 API + b2 官方工具）：

1. 开 B2 账号建 Object Lock 桶（创建时启用、compliance mode、默认保留期按 S5-PENDING-DEFAULTS 第 6 项=无限期语义的替代实现：**超长保留期 + legal hold**，因 B2 保留期上限 3,000 天，"无限期"以 legal hold 表达——PoC 验证该组合）。
2. 写入证据对象：对象版本 ID + SHA-256 摘要入控制面 DB（证据契约 R-EVID-01）；执行单元用只写 key。
3. `aws s3api` 全链（put-object retention/legal-hold/list-object-versions）脚本化入 runbook。

负面测试：

| # | 负面测试 | 期望 |
|---|---|---|
| N-1 | 只写 key 尝试删除/覆盖已锁对象 | 拒绝（403）；尝试事件入证据（R-EVID-03"独立写入权限"） |
| N-2 | S5 key 尝试缩短 compliance 保留期 | 拒绝（只能延长；文档语义实测） |
| N-3 | 篡改演练：改写已有证据对象内容 | 原版本仍在（版本化），篡改产生新版本且摘要不匹配 → 治理异常（R-EVID-05） |
| N-4 | 关闭桶 Object Lock 设置 | 操作失败（"cannot disable"，文档语义实测） |
| N-5 | 摘要核对：抽历史证据重算 SHA-256 与 DB 清单比对 | 一致；不一致 = 证据完整性事故入公示（R-OBS-02） |

## 6. 待 S5 裁决点（每点附默认方案）

| # | 裁决点 | 默认方案（先行，待追认） |
|---|---|---|
| 1 | 证据存储主选型 | **B2**（compliance Object Lock + legal hold 组合表达"无限期"） |
| 2 | 保留期定稿（第 9 章第 6 项） | legal hold（无到期）+ 3,000 天 compliance 保留兜底；S5 改判即触发重锁流程 |
| 3 | R2 冷副本是否启用 | 暂不启用；触发条件 = 证据量/可用性要求升级时再评估（R2 仅作投影副本，不承载锁定权威） |
| 4 | MinIO 定位 | 移出默认候选；仅当客户要求数据完全本地化时重启评估（AIStor Free Windows 可用性届时核实——本轮下载页超时未核） |
| 5 | 客户环境适配 | S3 API 语义为契约：客户 AWS → S3 同语义落位；客户私有云 → 届时按其 Object Lock 兼容性出适配矩阵 |
| 6 | S3 定价补核 | 建设期用 AWS Pricing Calculator 或 API 核实 S3 Standard 各档单价与出口档位，回填 §3.3（本轮页面 JS 未渲染全表，已如实标注） |

## 7. 回滚与迁移成本

- B2 → S3：同 S3 API 语义，`aws s3 cp`/同步工具全量搬迁；**锁定的 compliance 对象在保留期内不可删** → 迁移是"复制+双存至到期"而非"搬家"，双存期成本需预算（默认保留期=legal hold，须 S5 决定解除时点，R-IR-02 语义）。
- B2 → R2：锁定语义降级（桶规则重写为前缀规则），需证据契约层重登记锁定状态；成本中。
- → 自托管 MinIO：客户本地部署场景（DER-11 语义）的终态路径：数据物理拷出 + AIStor/商业授权重锁；成本高但仅在客户侧发生。
- 防呆：证据写入路径单向（只写 key + 独立 S5 治理 key），任何后端切换不开放执行单元的删除面——切换期间旧后端只读。

---

*引用清单（核实于 2026-09-06）：backblaze.com（object-lock / file-versions / s3-api-bucket-versions / lifecycle-rules / pricing）；developers.cloudflare.com（r2/buckets/bucket-locks、r2/pricing、r2/api/s3/api、changelog 2025-03-06）；docs.aws.amazon.com（S3 Object Lock 用户指南全文）；aws.amazon.com/s3/pricing（JS 渲染受限，已标注）；github.com/minio/minio（LICENSE raw、README raw 逐字、releases API 资产数=0）；docs.min.io/aistor（object-locking 页经搜索定位）。*
