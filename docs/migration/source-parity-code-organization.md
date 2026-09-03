# 复杂业务模块目录化来源对照

日期：2026-09-03

本记录只授权 `crates/ubaa-core/src/features` 下 Cgyy、Judge、SPOC、Bykc、LibBook、Ygdk
六个既有实现的物理拆分。协议事实仍以 [`source-parity.md`](source-parity.md) 的逐操作九列矩阵为
准；本记录把那些行为列映射到目标文件，防止目录整理时顺手改动 URL、参数、解析或错误语义。

冻结引用必须保持在 [`references.md`](references.md) 记录的提交：

- `ubaa_old/ @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`；
- `examples/buaa-api/ @ efb7976bf513f38364b88aeb83d704586cff9b2a`。

## 执行边界

- 本阶段允许移动函数、类型、常量和原有单元测试，允许为兄弟模块调用把私有项最小提升为
  `pub(super)`；禁止扩大到 crate 或外部公开面。
- 每个领域的现有 `pub`/`pub(crate)` 符号集合、请求顺序、重试次数、缓存所有权和 facade 调用路径
  必须保持不变。
- 任一请求字面量、表单键、Header、密码学常量、DTO 字段、解析回退、缓存代数或错误分类发生变化，
  都不再是物理拆分；必须停止并另立来源对照、RED 测试与行为提交。
- `examples/buaa-api` 有 SPOC 等价模块；其 `src/api/boya` 还为 Bykc 的同一业务端点提供交叉证据，
  但不能替代冻结 Bykc 加密与学期选择。其余四个领域明确记为“无等价实现”，不得从相似模块类比
  URL、字段、加密、Cookie 或错误。
- 测试移动到领域目录后仍在原 integration/unit target 中运行，不通过增加测试 binary 改变并发环境。

## Cgyy

操作范围：站点、用途、日期与时段、订单列表、订单详情、锁码、预约、取消，以及预约内部使用的
验证码挑战/求解/校验。

冻结实现与测试：`LocalCgyyApi.kt`、`LocalCgyyCaptchaSupport.kt`、`LocalCgyySigner.kt`、
`model/dto/Cgyy.kt`、`LocalCgyyApiBackendTest.kt`、`LocalCgyyCaptchaSolverTest.kt`、
`LocalCgyySignerTest.kt`。固定示例没有等价 Cgyy 协议。

逐操作权威段落：[`场馆预约只读查询`](source-parity.md#场馆预约只读查询) 与
[`Cgyy 预约提交`](source-parity.md#cgyy-预约提交)。

| 行为列 | 目录化决定 |
|---|---|
| 启动/服务 URL | 站点/用途/日期/订单/锁码/预约/取消全部保留权威段落中的既有地址；分别归入 `read.rs` 或 `write.rs`，不得拼成新的通用端点。 |
| 重定向/最终 URL | SSO 识别、允许主机和当前路线保持在 `auth.rs`/`http.rs`；不得新增透明 fallback。 |
| Cookie/会话范围 | 路线内 Cgyy token 仍由 `internal/route_state` 所有；目录化文件只借用，不持久化。 |
| HTTP 方法与精确参数 | 每个读写函数连同原参数构造整体移动；字段、空值、顺序和重复参数不改。 |
| Header/正文编码 | 签名 Header、表单编码、验证码 challenge/check 正文保持逐操作原状。 |
| 加密/签名常量 | `cgyy_crypto.rs` 与 `cgyy_sign.rs` 分别原样迁为 `crypto.rs`、`sign.rs`；向量测试随模块迁移。 |
| DTO/解析字段 | `parser.rs` 只承接现有 envelope、站点、用途、日期、订单和动作结果解析；不得合并不同响应的 fallback。 |
| 缓存/并发 | 登录单飞、token 清理、验证码尝试次数和调用顺序不改。 |
| 错误/退出语义 | 认证失效、上游变化、输入错误和写失败分类保持不变；安全日志仍只输出形状摘要。 |

目标：`cgyy/{mod,auth,http,captcha,read,write,parser,crypto,sign,tests}.rs`。

## Judge

操作范围：课程列表、课程作业列表、单项详情、批量详情、历史课程筛选、worker 隔离与缓存。

冻结实现与测试：`LocalJudgeApi.kt`、`model/dto/Judge.kt`、`LocalJudgeApiBackendTest.kt`。
固定示例没有等价 Judge 协议。

逐操作权威段落：[`Judge 列表`](source-parity.md#judge-列表)、
[`Judge 详情`](source-parity.md#judge-详情) 与
[`Judge 批量与缓存`](source-parity.md#judge-批量与缓存)。

| 行为列 | 目录化决定 |
|---|---|
| 启动/服务 URL | 激活、课程、作业和详情 URL 原样归入 `service.rs`。 |
| 重定向/最终 URL | Judge 业务认证识别和已记录的最终地址规则不改。 |
| Cookie/会话范围 | worker fork、Judge Cookie 筛选与 WebVPN path 规则整体迁入 `batch.rs`，不得扩大 Cookie 范围。 |
| HTTP 方法与精确参数 | `includeExpired` 仍只影响本地筛选；课程、作业、详情请求参数和顺序不改。 |
| Header/正文编码 | 既有 Judge Header 和无正文 GET 形状保持不变。 |
| 加密/签名常量 | 两份冻结来源均无该领域自定义加密；不得引入。 |
| DTO/解析字段 | 课程、作业、题目、分数和提交状态解析整体迁入 `parser.rs`；公开 DTO 继续来自 `domain::judge`。 |
| 缓存/并发 | generation、TTL、容量、历史标记、去重输入顺序和 worker 上限保持既有测试语义。 |
| 错误/退出语义 | 必需/可选 worker 结果、认证失败和 not-found 分类不改。 |

目标：`judge/{mod,service,batch,parser,calendar,tests}.rs`。

## SPOC

操作范围：CAS/SPOC 登录、当前学期、课程列表、作业分页、作业详情、可选提交内容与安全诊断。

冻结实现与测试：`LocalSpocApi.kt`、`LocalSpocSupport.kt`、`model/dto/Spoc.kt`、
`LocalSpocApiBackendTest.kt`、`LocalSpocSupportTest.kt`。固定示例的等价补充为
`src/api/spoc/{core,data,mod,opt}.rs`；发生冲突时仍以实时证据或适用冻结本地实现为准。

逐操作权威段落：[`SPOC 认证`](source-parity.md#spoc-认证)、
[`SPOC 列表`](source-parity.md#spoc-列表)、[`SPOC 安全诊断`](source-parity.md#spoc-安全诊断)
与 [`SPOC 详情`](source-parity.md#spoc-详情)。

| 行为列 | 目录化决定 |
|---|---|
| 启动/服务 URL | CAS token、登录、学期、课程、分页、详情与提交 URL 保持权威段落值。 |
| 重定向/最终 URL | token 只接受预期 host/path/route；`auth.rs` 原样承接现有解析。 |
| Cookie/会话范围 | SPOC token/role 继续只驻留路线状态，不复用或持久化为主认证凭据。 |
| HTTP 方法与精确参数 | 登录、全局分页、详情和提交查询参数及默认空过滤整体移动，不删“看似冗余”字段。 |
| Header/正文编码 | `Inco-*` Header、JSON/表单形状和字段顺序保持不变。 |
| 加密/签名常量 | `spoc_crypto.rs` 原样迁为 `crypto.rs`，冻结零填充和向量测试不改。 |
| DTO/解析字段 | envelope、role、分页、详情、提交状态、HTML plain-text 分别归入解析职责；summary identity 不被 detail 覆盖。 |
| 缓存/并发 | 登录代数、强制刷新、单次认证重试和同路线状态所有权不改。 |
| 错误/退出语义 | 只把完整 envelope 的冻结认证标记归为认证失败；畸形 JSON、可选 submission 和业务错误规则不改。 |

目标：`spoc/{mod,auth,list,detail,parser,crypto,calendar,tests}.rs`。

## Bykc

操作范围：登录、用户资料、学期/课程列表、课程详情、已选课程、统计、选课、退选和签到。

冻结实现与测试：`LocalBykcApi.kt`、`LocalBykcCrypto.kt`、`model/dto/Bykc.kt`、
`model/dto/BykcSerialization.kt`、`LocalBykcApiBackendTest.kt`、`LocalBykcCryptoTest.kt`。
固定示例 `src/api/boya/{core,data,mod,opt}.rs` 提供同一业务端点的交叉证据，但其包装和加密不能
替代冻结旧版决定。

逐操作权威段落：[`博雅课程只读查询`](source-parity.md#博雅课程只读查询) 与
[`UBAA2 直接写操作与评教`](source-parity.md#ubaa2-直接写操作与评教2026-08-28) 的 Bykc 行。

| 行为列 | 目录化决定 |
|---|---|
| 启动/服务 URL | OAuth/业务 API 及选课、退选、签到端点保持原常量和路线转换。 |
| 重定向/最终 URL | token 提取、Direct/WebVPN 还原和相对 Location 解析整体归入 `auth.rs`。 |
| Cookie/会话范围 | 独立业务 token 继续挂在路线状态，不进入 session 文件。 |
| HTTP 方法与精确参数 | profile/course/chosen/statistics 与三项写操作的 encrypted request 内容不改。 |
| Header/正文编码 | timestamp、摘要、加密载荷包装和现有 Header 保持逐操作原样。 |
| 加密/签名常量 | 加解密函数与冻结向量归入 `auth.rs` 或独立算法文件；不得重算或替换常量。 |
| DTO/解析字段 | `data.courseList` 包装兼容、学期选择、状态/分类/签到点与时间窗口解析整体迁入 `parser.rs`。 |
| 缓存/并发 | token 登录锁和路线清理语义不改；UI eligibility 不在本机械阶段实现。 |
| 错误/退出语义 | envelope、非法响应、输入和业务失败分类不改，写操作仍需 facade/宿主确认。 |

目标：`bykc/{mod,auth,read,write,parser,tests}.rs`。

## LibBook

操作范围：馆区、区域、区域详情、座位、预约列表、预约和取消。

冻结实现与测试：`LocalLibBookApi.kt`、`LocalLibBookCrypto.kt`、`LocalLibBookHttpClient.kt`
及各平台 actual、`model/dto/LibBook.kt`、`LocalLibBookApiBackendTest.kt`、
`LocalLibBookCryptoTest.kt`。固定示例没有等价 LibBook 协议。

逐操作权威段落：[`图书馆座位只读查询`](source-parity.md#图书馆座位只读查询) 与
[`UBAA2 直接写操作与评教`](source-parity.md#ubaa2-直接写操作与评教2026-08-28) 的 LibBook 行。

| 行为列 | 目录化决定 |
|---|---|
| 启动/服务 URL | CAS、馆区/区域/座位/预约及取消地址保持原样，归入 `service.rs`。 |
| 重定向/最终 URL | CAS 提取、过期识别和路线 URL 转换规则不改。 |
| Cookie/会话范围 | 独立 LibBook token 仍在路线状态内存中，日志只保留 URL/body 形状。 |
| HTTP 方法与精确参数 | 只读与 reserve/cancel 参数、日期和目标标识不改。 |
| Header/正文编码 | JSON/form/加密请求正文、Content-Type 与安全摘要不改。 |
| 加密/签名常量 | `libbook_crypto.rs` 原样迁为 `crypto.rs`，冻结 golden 向量保持。 |
| DTO/解析字段 | primitive 文本兼容、area detail、seat、booking 状态与分页字段整体归入 `parser.rs`。 |
| 缓存/并发 | token 获取、失效清理和最多一次重试保持不变。 |
| 错误/退出语义 | 认证过期、解析、上游变化和写错误分类不改。 |

目标：`libbook/{mod,service,parser,crypto,tests}.rs`；`tests.rs` 是保留现有单元测试所需的明确
补充，不改变目标生产职责。

## Ygdk

操作范围：OAuth/业务登录、分类/项目/统计/学期概览、记录分页、照片上传和打卡提交。

冻结实现与测试：`LocalYgdkApi.kt`、`model/dto/Ygdk.kt`、`LocalYgdkApiBackendTest.kt`。
固定示例没有等价 Ygdk 协议。

逐操作权威段落：[`阳光打卡只读查询`](source-parity.md#阳光打卡只读查询) 与
[`UBAA2 直接写操作与评教`](source-parity.md#ubaa2-直接写操作与评教2026-08-28) 的 Ygdk 行。

| 行为列 | 目录化决定 |
|---|---|
| 启动/服务 URL | OAuth、`campusAppLogin`、分类、项目、统计、学期、记录、上传和提交地址保持原样。 |
| 重定向/最终 URL | 十次有界跳转及 query/fragment code 提取原样归入 `service.rs`。冻结实现和当前 Core 均未校验每跳 host；主矩阵曾写入的主机限制尚无完整允许集合证据，已在 decision log 标记为既有未决 parity gap，本机械阶段不得顺手猜测修复或宣称满足。 |
| Cookie/会话范围 | `{uid,token}` 仍为路线内存状态，不复用主认证 Cookie、不持久化。 |
| HTTP 方法与精确参数 | 概览固定分页、记录分页、上传 multipart 和提交表单全部保持冻结字段。 |
| Header/正文编码 | `X-Requested-With`、form 编码、multipart boundary/filename/MIME 与 query/body 双写不改。 |
| 加密/签名常量 | 两份来源均无自定义加密；不得引入。 |
| DTO/解析字段 | envelope、primitive 文本、上海时区时间、图片字符串/数组和分页字段整体归入 `parser.rs`。 |
| 缓存/并发 | 路线内登录单飞与失效代数保持 2026-09-03 决策；旧登录结果不得越过 `clear` 回写。 |
| 错误/退出语义 | `code=1`、`-98`、非法分页/输入、可选统计和写失败分类与一次认证重试不改。 |

目标：`ygdk/{mod,service,parser,upload,tests}.rs`。

## 每个物理拆分提交的验收

1. 先运行该领域现有 parser/request/cache/crypto/concurrency focused tests并记录测试叶集合。
2. 只移动一个领域；用明确 pathspec 暂存，确认没有冻结引用、fixture、凭据或生成物。
3. 结构测试确认该领域所有手写文件少于 1000 行、父 `features` 直属文件数只降不升。
4. 再运行同一 focused 集合，测试名与数量不减少；随后运行 `just refs`、`just check-sensitive`、
   `just layout-check` 与 `just check`。
5. 对请求常量、公开符号和 facade 调用点做文本差异复核；除模块路径/可见性外若出现行为 diff，停止该提交。
