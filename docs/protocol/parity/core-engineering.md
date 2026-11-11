# Core 与工程整理

本文件收录 Rust Core 精简、模块目录化、传输诊断、依赖收敛、分支整合和独立工程审查整改的来源对照；这些整理不改变学校协议。

## 专项记录

### Rust Core 精简与缺陷修复

基线：`7348b8b3693d2254aa72c160911317955123a0f9`。本轮保留开始时的 OHOS、工具链及状态文档改动，所有实现只按明确路径提交。用户在当前会话授权必要的真实账号、网页及可撤销写操作检查。只有验证需要时才执行学校请求，写请求发送后的未知结果仍先只读核对。

#### 修复方案与完成条件

| 发现 | 实施方案 | 验收条件 |
|---|---|---|
| 七处缓存刷新重复且退出/替代处理不同 | 先证明 Judge/今日课表迟到结果问题，再共享准备和发布收尾 | 失效结果拒绝返回，普通磁盘失败仍允许在线结果，各领域缓存测试通过 |
| RouteClient 与 UbaaClient 重复安全编排 | 共用已选路线的会话检查、清理和写入收尾，保留公共入口 | Direct/WebVPN 隔离、会话 CAS、写后结果保护和全部 CLI 合同通过 |
| SPOC 两套学期/分页/投影/排序 | 共享协议读取步骤与投影，分别保留一次性和分段调度 | 精确请求、原容错策略和分页完整度覆盖保留 |
| 评教重复遍历且计算无消费者的完整度 | 共享任务、问卷与课程读取步骤，删除无效累计 | 显示容错、fresh authority 和单次写入保护保持 |
| 博雅 JSON 反复序列化/解析 | 已验证 data 直接传给领域解析器 | Fixture 与请求合同保持，移除内存中的伪响应包装 |
| LibBook 重复解析正文 | 一次 JSON 解码同时产生 DTO 与完整度 | 缺列表/畸形内容不覆盖旧完整缓存，预约/取消资格不放宽 |
| 多种业务凭据重复锁与生命周期代码 | 共享小型私有凭据状态，保留各领域 typed 值、独立登录锁和失效范围 | 原并发、失效代次、脱敏测试通过 |
| 旧单路线磁盘写入参与生产编译 | 生产只保留双路线写入和旧格式读取迁移，旧造数入口留在测试 | 旧数据迁移、CAS、权限和冲突测试通过 |
| 首页旧分支、重复守卫和重复测试 | 删除不可达分支，收敛重复检查，保留一份相同测试 | 删除项逐项登记对应保留覆盖 |
| 无效 legacy_priority 与历史格式 | 按用户后续决定移除旧缓存迁移、兼容列和策略计算；格式升级后旧版本明确要求重建 | 当前格式可重开，旧版本安全拒绝，显式重建及当前加密/隔离覆盖保留 |
| Cgyy 记录敏感正文 SHA1 | 先增加日志失败反例，再删除正文摘要及专用函数 | 登录、订单、写响应和门锁日志均不含正文或摘要 |

来源比较由[缓存专项](#rust-core-缓存刷新精简)、[协议专项](#core-读取实现精简的来源对照)、[边界专项](#rust-core-路线边界精简)及下文记录。公共 CLI/Bridge 合同保持，FRB 重生成必须零漂移。完整确定性检查采用[开发命令](../../development/commands.md#检查选择与完成条件)，按改动计划始终使用本页基线。

#### 凭据与日志来源比较

冻结引用经本轮 `just refs` 确认：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

旧版对应实现位于 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/Local{Cgyy,Bykc,LibBook,Ygdk,Signin,Spoc}Api.kt`，各客户端分别拥有登录锁、业务令牌与缓存清除。buaa-api 已读取 `src/store/cred.rs`、`src/cell.rs`、`src/request.rs` 和对应 `api/boya`、`api/spoc`、`api/class` 实现。buaa-api 的 iClass 凭据及路径与适用旧版不同，维持既有来源裁决，不能在本轮复用其字段。buaa-api 无同一 Cgyy、LibBook、Ygdk 协议，相关列不适用。

| 操作范围 | CAS/service 与最终 URL | Cookie/业务凭据 | HTTP 方法/参数 | Header/编码 | 加密/签名 | DTO/解析 | 缓存/并发/重试 | 错误/退出与产品语义 |
|---|---|---|---|---|---|---|---|---|
| Cgyy 登录及全部响应日志 | 沿用 LocalCgyyApi 与当前 auth 引导；不变更 URL/跳转 | 独立路线内存 token，登录解析仍取 access_token | 日志删减不改发送 | 签名请求和正文不变 | 业务签名保留，仅删除日志 SHA1 | 不改业务解析；日志只保留安全元数据 | 独立登录锁及原重试边界保留 | 只减少日志字段，不改错误结果 |
| Bykc/LibBook 凭据槽位 | 各自 feature 继续拥有原 CAS 与回调校验 | 保留 typed token，账号/路线不共享 | 不改 feature 请求 | 不改原 header 与正文 | 不改业务密码学 | 不改 DTO | 只共用内存锁、取值、清除；独立单飞锁 | 原清除入口及会话错误保留 |
| Ygdk/Signin/Spoc 凭据槽位 | 各自原登录流程不变；不采用 buaa-api 不同 iClass 路径 | 保留 uid/token、user_id/session_id、token/role 的各自类型 | 不改请求 | 不改 header/编码 | 不改密码学 | 不改字段及类型 | generation 与存入比较、清除递增、独立登录锁保留 | 旧代次登录不能恢复已清除凭据 |
| iHome 凭据 | 原引导与最终 URL 不变 | 原内存 token 不变 | 不变 | 不变 | 不变 | 不变 | 原子快照与 mutation 锁有独立用途，按实现收益决定复用范围 | 原清除/迟到保护保留 |

#### 执行结果

日志保存在被忽略的 `.ubaa_local/core_simplification/`，其中不得归档凭据、原始真实响应或个人资料。

日志失败反例先在 `business_login.api` 触发“泄露了敏感正文摘要”，删除正文 SHA1 后通过。合成登录、订单列表、详情、取消和预约响应共同验证正文及其 SHA1 不进入日志，门锁原有低熵秘密保护继续覆盖。

首次完整严格检查在 CLI 的命令锁定测试失败，原因是协议专项记录中的三个 Cargo 命令漏写 `--locked`。文档已修正，三组命令按锁定依赖重新执行通过，命令锁定测试转为通过。首轮失败保留在 `strict-first.log`，没有修改检查规则。

六种凭据状态已复用一个私有 `CredentialState<T>`，typed 凭据、每个实例的登录锁和失效代次分别保留。原 Signin 与 Ygdk 的两种竞争时序仍由测试钩子验证，生产构建不包含钩子。iHome 自身还有串行修改锁及同时取得代次/token 的原子快照，保留该小型实现，避免为了统一类型增加转发层。

#### 代码规模与验收

按 `crates/ubaa_core` 下全部 Rust 文件的物理行数统计，基线为 297 个文件、68,000 行，修复后为 300 个文件、67,353 行，净减少 647 行。统计包含注释、空行、内联测试及本轮新增回归测试。新增文件用于共享刷新逻辑和集中测试适配。记录位于本地忽略目录的 `size.json`。

当前 `tests/` 目录占 20,961 行，`src/` 下按文件名识别的测试及测试支持文件占 10,070 行，两者合计 31,031 行。其余 36,322 行仍含内联测试。评估业务实现规模时需要计入这种组成差异。

本轮把重复的生命周期和解析步骤集中到现有模块，没有增加公共调度框架。路线隔离、会话 CAS、失效代次、写前资格复核和写入未知结果保护都有实际安全用途，继续保留。代码量统计不能单独判断这些机制是否应该删除。

| 检查 | 结果 |
|---|---|
| `just refs` | 两个冻结来源校验通过 |
| `just layout-check`、`just docs-link-check`、`just check-sensitive` | 通过，严格入口也包含布局和文档检查 |
| `just check-strict` | 完整严格入口通过，Rust 测试汇总为 1110 次通过、3 次按既有设置忽略，包含不同构建配置的重复执行 |
| `just flutter-check` | 八个 workspace 成员的格式、静态分析及 1531 项测试全部通过 |
| `just integration-test` | macOS 默认五组原生集成通过，共 7 项，覆盖宿主 smoke、网络恢复、插件、FFI 缓存和跨进程启动锁 |
| `CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check` | FRB 2.13.0 重生成零漂移 |
| `CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just check-changed base=7348b8b3693d2254aa72c160911317955123a0f9` | 审阅完整计划后执行通过，包含 Rust/脚本、八成员 Flutter 和再次 FRB 零漂移检查 |
| `git diff --check` | 通过；提交前另外检查每组暂存差异并重新执行敏感扫描 |

真实只读验证使用 `just verify-live mode=direct` 与 `just verify-live mode=webvpn`。Direct 首次 50 项全部通过。WebVPN 首次 45 项通过，Judge 的同一次诊断调用超时导致 2 项失败，另外 3 项按依赖关系阻断。复用同一生产二进制单独重跑 Judge，5 项在约 13 秒内全部通过；随后完整 WebVPN 单次复跑在约 35 秒内通过全部 50 项。两条路线均已有完整通过记录。

Judge 的协议实现和只读脚本本轮没有差异，两次复跑间也未修改生产代码。观察结果支持首次为偶发网络或上游超时，现有摘要无法确定发生超时的具体请求。原失败保留在 `live-webvpn.stdout`，模块复跑和完整复跑分别在 `judge-webvpn-retry.stdout`、`live-webvpn-rerun.stdout`。本轮没有执行真实业务写入，也没有遇到需要浏览器核对的协议疑点。

本轮仅完成本机工程修复和验证，没有触发远端 CI、签名发布或实体设备验收。旧缓存需要用户在设置中显式重建，当前开发阶段不提供旧缓存迁移。

实现按主题提交如下，方案、来源比较和验证记录另作一次文档提交。所有提交均保留在本地，未推送。开始时已有的 OHOS、工具链和两份状态文档末尾改动未纳入本轮提交。

| 提交 | 内容 |
|---|---|
| `92fcc22f` | 删除场馆响应正文 SHA1 日志并保留敏感日志回归 |
| `c8719fe6` | 合并私有凭据状态，保留并发失效保护，删除重复测试 |
| `b1bc2f38` | 共享路线安全收尾，清理未完成登录残留状态，限定旧会话写入口 |
| `0f90d442` | 共享缓存刷新，拒绝迟到结果，删除历史开发格式迁移 |
| `05f93ecf` | 复用博雅、SPOC、评教及图书馆的解析与读取步骤 |

#### 测试整理登记

| 删除或调整项 | 保留覆盖 |
|---|---|
| `route_state/mod.rs` 重复的 `concurrent_classroom_bootstraps_use_one_double_checked_sync` | 同名测试在 `route_state/classroom.rs` 原样保留，继续验证并发双重检查只执行一次引导 |
| `route_state/mod.rs` 重复的 `failed_or_cleared_classroom_sync_remains_retryable` | 同名测试在 `route_state/classroom.rs` 原样保留，继续验证失败可重试及清除后重新引导 |
| Ygdk 测试专用 `set` 的带代次写入 | 原竞态测试改为直接调用生产 `store_credential`，继续在旧登录存入前暂停并验证清除后不能回写 |

其余缓存格式和解析适配的测试调整见各专项记录。

### Rust Core 缓存刷新精简

日期：2026-10-30。范围是 facade 的本地缓存生命周期、重复结果包装和失效实现。学校协议、写入资格、持久加密、账号与路线隔离保持原有实现。

#### 来源与操作对照

冻结来源为 `ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 与 `buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。读取旧版对应的 `api/feature`、`api/local`、`model/dto` 和 `commonTest/.../api/Local*BackendTest.kt`。共享认证读取 `LocalConnectionAuth.kt`，第二来源读取 `api/user/auth.rs`、`request.rs`、`store/cookies.rs`、`store/cred.rs` 和 `error.rs`。

下面每行按本轮操作列出两个来源。表中的“不适用”只针对本轮本地 ticket 生命周期；不得据此补齐上游协议。已有逐操作协议事实继续由[原缓存来源记录](offline-cache.md#离线恢复逐操作来源对照)及[来源索引](../README.md)维护。

| 操作 | 旧版实现、DTO 与测试 | buaa-api 最近模块 | CAS/引导与 service | 重定向与最终 URL | Cookie/Session/Token | HTTP 方法与参数 | 请求头与正文编码 | 加密/签名 | DTO、缓存/并发/重试、错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 希冀摘要刷新 | `LocalJudgeApi.kt`、`feature/JudgeApi.kt`、`dto/Judge.kt`、`LocalJudgeApiBackendTest.kt` | 无 Judge 模块，不适用 | 本轮不变 | 本轮不变 | 仍由原路线 runtime 使用 | 仍调用原 `judge::get_assignments(include_expired)` | 本轮不变 | 本轮不变 | 保留原摘要；修复退出/被取代后仍返回旧成功的问题，不增加重试 |
| 今日课表刷新 | `LocalScheduleApi.kt`、`feature/ScheduleApi.kt`、`dto/Schedule.kt`、`LocalScheduleApiBackendTest.kt` | `api/aas/core.rs`、`opt.rs`、`data.rs` | 本轮不变 | 本轮不变 | 仍由原路线 runtime 使用 | 仍调用 `get_today_for_date`，精确日期同时用于请求和缓存键 | 本轮不变 | 本轮不变 | 保留完整/空课表；迟到发布遵守同一硬失败规则 |
| 学期、周次、周课表、考试、成绩、空教室刷新 | `LocalScheduleApi.kt`、`LocalClassroomApi.kt` 及对应 feature/DTO/Mock 测试 | `api/aas`；空教室无相同模块，不适用 | 本轮不变 | 本轮不变 | 原认证、路线和作用域不变 | 原 `AcademicQuery` 分发和精确参数不变 | 本轮不变 | 本轮不变 | 缓存键、保留完整结果和导入课表回退不变，共享本地准备/收尾 |
| 博雅资料、课程、目录、详情、完整详情、已选、统计刷新 | `LocalBykcApi.kt`、`feature/BykcApi.kt`、`dto/Bykc.kt`、`LocalBykcApiBackendTest.kt` | `api/boya/core.rs`、`opt.rs`、`data.rs` | 本轮不变 | 本轮不变 | Token 仍留在原协议层 | 原 `BykcCacheQuery::read` 不变 | 本轮不变 | 既有 RSA/请求编码不变 | 在线资格和落盘白名单继续分离，不增加请求或重试 |
| 场馆站点、用途、日期、订单页和订单详情刷新 | `LocalCgyyApi.kt`、`feature/CgyyApi.kt`、`dto/Cgyy.kt`、`LocalCgyyApiBackendTest.kt` | 无相同场馆模块，不适用 | 本轮不变 | 本轮不变 | 原业务认证不变 | 原 `CgyyCacheQuery::read` 不变 | 本轮不变 | 原签名实现不变 | 保留来源/日期/ID 校验与部分结果保护，结果包装改为兼容类型别名 |
| 图书馆楼馆、分区、详情、座位和预约页刷新 | `LocalLibBookApi.kt`、`feature/LibBookApi.kt`、`dto/LibBook.kt`、`LocalLibBookApiBackendTest.kt` | 无相同座位模块，不适用 | 本轮不变 | 本轮不变 | 原业务认证不变 | 原 `LibBookCacheQuery::read` 不变 | 本轮不变 | 原密码学不变 | 写资格不落盘，保留 exact scope 和部分结果语义 |
| 首页课堂、阳光概览刷新与 SPOC 分发整理 | `LocalSigninApi.kt`、`LocalYgdkApi.kt`、`LocalSpocApi.kt` 及对应 feature/DTO/Mock 测试 | `api/class/core.rs`、`api/spoc/core.rs`；阳光无相同协议模块，不适用 | 本轮不变 | 本轮不变 | 原会话和 Token 不变 | Signin 日期、阳光周期发布不变；SPOC 继续调用现有 scan | 本轮不变 | 既有 SPOC 常量不变 | 删除已被提前 return 排除的两个旧分支，父子票据与周期判断不变 |
| 评教刷新结果包装 | `LocalEvaluationService.kt`、`feature/EvaluationService.kt`、`model/evaluation/EvaluationModel.kt`、对应 Mock 测试 | `api/tes/auth.rs`、`opt.rs`、`data.rs` | 不修改认证 | 不修改跳转 | 不修改作用域 | 不修改 scan 及固定任务分页 | 不修改编码 | 不修改常量 | 仅合并相同 Rust 结构，公开名字和字段保持 |
| 本地数据库旧优先级处理 | `repository/ScheduleSnapshotStorage.kt` 与测试；没有相同 SQLite ticket 协议 | 无相同本地数据库，不适用 | 不适用 | 不适用 | 不读取认证材料 | 仅本地 SQLite 操作 | 不适用 | AES-GCM、HMAC 与 AAD 不变 | 当前格式及旧版本拒绝方案见下文 |

两个来源都没有本项目的持久 `CacheReadTicket`。本轮退出与被取代规则以现有[缓存合同](../../contracts/offline-cache-and-recovery.md)和跨连接测试为依据，不从来源的会话缓存类比构造新字段。

#### 修复与保留边界

刷新统一准备和收尾：先检查持久代次、验证查询，再沿原 feature 认证并核对账号。网络完成后的 `Inactive/Superseded` 必须返回失败，普通存储失败继续允许在线显示并报告保存错误。部分结果不覆盖既有完整结果，保存失败记录本次尝试。

`HomeRefresh`、`CgyyRefresh`、`LibBookRefresh`、`EvaluationRefresh` 通过类型别名复用相同的结果结构。Bridge 继续读取原来的字段。SPOC 的现有扫描、分段取消、父子票据和持久范围保留。

用户确认应用为全新开发，无需迁移旧缓存。缓存 schema 提升为 v7，删除 v1–v5 控制记录迁移、旧请求表迁移、priority 列及其计算，并删除仅供旧库读取的无学期 SPOC/无周期阳光查询变体。普通打开只接受空库和 v7，旧版及未知版本在写入前返回 UnsupportedVersion，原文件保持。设置中的用户显式重建继续可用，清空旧开发缓存后创建当前格式。

AES-GCM、HMAC、AAD、数据库身份、epoch、generation、revision、请求范围认证、写后核对提示和跨连接栅栏保留。当前格式不保存任何学校写资格。

删除的兼容测试与保留覆盖如下。旧格式转换已取消，原安全性质继续由当前格式测试验证。

| 删除或调整的测试 | 保留或替代的覆盖 |
|---|---|
| v1 控制记录事务升级且旧格式不能重新写回 | 新增“旧开发格式一律拒绝且普通打开不改原库”，覆盖 1–6 与未来版本 99 的逐版拒绝、文件不变与显式重建；当前格式错误密钥由 encrypted_content_survives_reopen_without_network_or_plaintext 保留 |
| 错误密钥不迁移 v1 而正确迁移保留退出状态 | 同上版本拒绝；当前格式退出与重登由 logout_clear_and_another_handle_invalidate_late_publications、提示退出测试保留 |
| v2 升级保留业务与退出状态且旧 AAD 不能重用 | 版本拒绝替代转换；当前格式密文互换、错误密钥和数据库身份测试继续保留 |
| v3 升级保留内容和退出状态、旧连接不能参与新格式回收 | 版本拒绝替代转换；用量清理测试、跨连接退出/清理、重建旧数据库同计数票据测试继续保留 |
| v4 迁移保留业务密文和退出状态、旧连接和旧票据均失效 | 新增“请求范围密文保存且失效撤销对应票据”，保留原测试中的范围加密断言；跨连接、按资源失效与生命周期测试保留 |
| 五版迁移保留旧业务与退出状态并拒绝已打开旧句柄 | 版本拒绝替代转换；提示退出隐藏、重新登录读取、清理代次阻断旧收尾和重开保留加密线索测试继续保留 |
| 阳光旧单例不猜周期 | 删除旧单例准备；同一测试继续验证未知学期不完整、载荷/范围不符拒绝、周起始日期验证和当前格式重开 |


#### 验证记录

新增今日/希冀各两种竞态反例：读取过程中退出账号，以及另一数据库连接开始同范围新读取。RED 日志保存在本地忽略目录 `.ubaa_local/core_simplification/cache-red.log`。原有网络参数、精确范围、身份、完整/部分结果、容量、跨连接和只读持久化安全覆盖继续保留。旧格式转换测试的删除项及替代覆盖见上表。

本节聚焦验证使用合成 transport。缓存格式的第二组 RED 日志为 `.ubaa_local/core_simplification/cache-format-red.log`，证实旧 schema v6 在修改前会被普通打开接受。整合后的真实双路线只读结果由主记录汇总。

聚焦验证通过：`cargo test --locked -p ubaa-core --features test-contract --lib cache::` 通过 80 项，facade 集成测试通过 121 项。补齐未来版本 99 后，版本拒绝测试再次通过。Core 全目标 Clippy 使用 `--features test-contract -- -D warnings` 通过。日志分别为 `.ubaa_local/core_simplification/cache-format-green.log`、`cache-facade-final.log`、`cache-version-final.log` 和 `cache-clippy-final.log`。全量确定性门禁由本轮主记录统一登记。

### Core 读取实现精简的来源对照

本轮只合并重复读取原语和内存解析步骤，保留公开 DTO、错误、请求顺序、分页停止条件、路线隔离及写前 fresh authority。没有执行真实认证、读取或写入。

冻结旧版为 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，冻结 buaa-api 为 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，已运行 `just refs` 校验。以下文件均已只读核对：

- 旧版 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalBykcApi.kt`、`LocalSpocApi.kt`、`LocalSpocSupport.kt`、`LocalEvaluationService.kt`、`LocalLibBookApi.kt`，以及对应 `api/feature` 接口、DTO 和 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/Local*BackendTest.kt`。
- buaa-api 的 `src/api/boya/{core,opt,data}.rs`、`src/api/spoc/{core,opt,data}.rs`、`src/api/tes/{auth,opt,data}.rs`。图书馆无等价模块，不适用。
- 既有逐操作结论见[来源对照索引](../README.md)的博雅、SPOC、评教和图书馆章节。本轮不选择另一套来源行为，也不扩大其授权或发布结论。

#### 九列逐操作核对

表中“保持”表示继续使用当前实现与既有来源记录；转换后的 `Value` 只在同一操作的内存中传递，完整度不能兑换写入权限。

| 操作、CAS/引导 URL 与 service | 重定向及最终 URL | Cookie、Session、Token 作用域 | HTTP 方法与精确参数 | 请求头与正文编码 | 加密/签名 | DTO 字段及类型 | 缓存、并发、重试 | 错误、退出及产品语义 |
|---|---|---|---|---|---|---|---|---|
| 博雅资料 `getUserProfile`；旧版 `https://bykc.buaa.edu.cn/sscv/cas/login`，buaa-api 使用 SSO service 到该地址 | 两源均从业务回调取得 token；保持当前白名单、八跳和路线转换 | 两源业务 token；当前按路线内存保存 | POST `/sscv/getUserProfile`，JSON `{}` | 保持当前 JSON、Accept、双 token 头、Origin、Referer | 两源 RSA 包装 AES key/SHA1 和 AES-ECB；常量与加密器保持 | `id` 整数，身份/学院等可选字符串；直接消费已校验 data | 保持业务登录锁与既有请求策略 | 保持读取信封容错和错误映射；删除伪造成功信封的内存往返 |
| 博雅课程分页 `queryStudentSemesterCourseByPage` | 与资料相同 | 与资料相同 | POST，`pageNumber/pageSize` 整数；两源确认分页接口 | 与资料相同 | 与资料相同 | `content` 数组，分页整数；课程映射、过期过滤和完整目录投影保持 | 不合并两种公开 DTO，只共享同一次 data 解析 | 保持 `all` 过滤与无效课程错误 |
| 博雅详情 `queryCourseById` | 与资料相同 | 与资料相同 | POST，`id` 整数 | 与资料相同 | 与资料相同 | 保持详情 ID 校验、完整显示投影和写前严格计数字段校验 | 显示与写前读取继续分别请求 | 写前严格信封和 fresh 校验继续保留，显示配置不授予写权限 |
| 博雅当前学期 `getAllConfig` 与已选 `queryChosenCourse` | 与资料相同 | 与资料相同 | POST `{}`，随后 `startDate/endDate`；以冻结旧版精确字段为准 | 与资料相同 | 与资料相同 | 学期起止字符串、已选列表及嵌套课程；配置优先级保持 | 保持当前学期解析和请求顺序 | 显示配置标准化与写前 authority 分开；不沿用示例的估算学期 |
| 博雅统计 `queryStatisticByUserId` | 与资料相同 | 与资料相同 | POST `{}` | 与资料相同 | 与资料相同 | 保持统计 map、数量与分类投影 | 无新增缓存/请求 | 保持统计解析失败语义 |
| SPOC 当前学期 `inco/ht/queryOne`；CAS `/spocnewht/cas` 与 `/sys/casLogin` | 两源 CAS 相同，旧版另激活角色；保持当前八跳、最终 URL 和业务认证仲裁 | 旧版 token/role，示例仅 token；保持路线内 token/role | POST 固定 `param`；示例 queryOne 的最近操作不替代旧版常量 | JSON、XHR、`Token: Inco-...`、RoleCode；示例缺 RoleCode，保持旧版 | 固定 AES key/IV；本操作固定密文保持 | `mrxq/dqxq` 可空字符串；旧读取与 scan 各自校验保留 | 共享请求，保留登录锁与一次认证恢复 | 旧入口非空检查和 scan 空白/长度检查分别保留 |
| SPOC 课程 `jxkj/queryKclb` | 同上 | 同上 | GET，`kcmc=""`、`xnxq` | XHR、Token、RoleCode | 无 | 课程 ID/名称字符串，可选教师 | 共享课程请求/映射；旧入口仍容忍课程元数据失败，scan 保留仲裁 | 不改变元数据失败后的列表请求与完整度 |
| SPOC 全局分页 `inco/ht/queryListByPage` | 同上 | 同上 | POST，加密明文含 `pageSize=15/pageNum/sqlid/xnxq/kcid=""/yzwz=""`；示例按课程 GET 不等价 | JSON param、XHR、Token、RoleCode | 保留旧版 CBC 零填充规则；示例对齐填充不同，不采用 | 共享摘要映射/排序；分页整型默认值与 scan 回显检查分别保留 | 停止条件仍为无下一页、达到页数或空页；保持旧入口诊断计数 | scan 范围检查不隐式加入旧入口；解析失败和认证恢复保持 |
| 评教激活 `/pjxt/cas` | 旧版直接业务激活，示例 SSO service；保持当前终点 `/pjxt` 检查 | 同路线 Cookie，未新增持久 token | GET，无新增参数 | 保持现有请求头，无正文 | 无 | 无公开新增字段 | 显示容忍非认证错误，严格 authority 失败即止 | 不改变主认证失效、上游错误和显示空结果合同 |
| 评教 tasks → questionnaires → courses | 两源均为相同三个端点；保持每次精确最终 URL | 与激活相同 | GET；tasks `yhdm/pageNum=1/pageSize=10`，forms `rwid`，courses `wjid` | 无新增请求头/正文 | 无 | 保持 result/list/数组、rwid/wjid/msid 与课程字段；示例只取首任务，保持旧版遍历全部任务 | 共享 URL 与行解析，scan 保留分段游标；写前仍 fresh 全量读取 | 删除旧路径无人消费的完整度累计；显示容错与写前严格错误策略保持 |
| LibBook 楼馆 `space/pcTopFor`、分区 `space/pick` | 旧版 CAS service `https://booking.lib.buaa.edu.cn/v4/login/cas`，最多八跳；示例无等价模块 | 旧版独立业务 token；当前仍路线内存保存 | POST JSON；楼馆 `day`；分区 `premisesIds/categoryIds/storeyIds/boutiqueIds/date` | 保持固定 Accept/User-Agent、XHR、Authorization、Origin、Referer | 读取无加密 | 保持列表别名、原语兼容、楼层与父 ID；同一次 data 解析返回 DTO 和完整度 | 一次失效恢复；不改变请求数/顺序 | 缺失或丢项列表不可覆盖完整缓存；显式空数组可覆盖 |
| LibBook 分区详情/日程 `Space/map` | 同上 | 同上 | POST JSON `id` | 同上 | 无 | 一次解析 data，复用日期/时段结构；旧展平时段与逐日日程语义分别保留 | 不新增学校请求 | 保持日程关联检查、重复日期错误与详情容错 |
| LibBook 座位 `Space/seat` | 同上 | 同上 | POST `id/day/label_id=[]/start_time/end_time/begdate=""/enddate=""` | 同上 | 无 | 保持 nullable status、typed 写资格和座位排序；与完整度共享已解析 data | 失效恢复保持 | 完整度仅用于缓存，写前 fresh 座位校验保留 |
| LibBook 预约记录 `member/seat` | 同上 | 同上 | POST `type="1"/page/limit` | 同上 | 无 | 保持列表与分页回退、严格写 authority 的元数据检查 | 显示读取共享解析；取消前仍 fresh 同页读取 | 保持取消资格与未知结果保护；本轮不修改任何最终写请求 |

#### 验证范围

本轮复用既有请求、解析、分页、完整度、扫描、写入资格及不可重放测试。字符串 Fixture 仍先经过真实信封检查，随后调用与生产相同的 data 解析器。生产代码没有为复用 Fixture 重新构造成功信封。

首页不可达旧分支移除后，SPOC 普通列表和详情的 observed 完整度也已没有消费者，因此连同内部包装一起删除。扫描的分页回显、范围和完整度检查继续保留。评教严格写前读取依然重新请求 authority，显示读取的错误容忍和分段扫描分别保持原有行为。

聚焦验证结果：

- `cargo check --locked -p ubaa-core --all-features` 通过。
- `cargo test --locked -p ubaa-core --all-features --lib features::` 通过 221 项，1 项手动性能基准忽略。
- `cargo test --locked -p ubaa-core --all-features --test bykc --test libbook --test evaluation --test facade` 整合后复核通过 184 项。
- 重构途中将 LibBook JSON 解码前移后，新增畸形 JSON 反例发现取消列表错误绕过固定安全文案。RED 显示实际文案为“图书馆响应无法解析”。将取消资格请求和解析的整个结果经既有安全错误映射后，prepare/commit 均返回固定资格核对错误，并且最终取消请求为零。该用例复跑通过。公开错误分类和可重试标记保持。
- Core Clippy 的协议与缓存变量命名诊断均已修复。最终完整门禁结果由[整合记录](#rust-core-精简与缺陷修复)统一登记。

以上聚焦结果均来自脱敏 Fixture/Mock。整合后的真实账号 Direct/WebVPN 只读结果见[整合记录](#rust-core-精简与缺陷修复)。检查日志仅保存在 Git 忽略的 `.ubaa_local/core_simplification/`。

### Rust Core 路线边界精简

日期：2026-10-30。本文记录 facade 操作收尾和旧会话写入路径的整理。

#### 冻结来源与范围

开始修改生产代码前，已经通过 `just refs` 校验两个冻结提交：旧版 UBAA 为
`1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api 为
`a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

本轮读取的旧版来源为 `LocalConnectionAuth.kt`、`ConnectionRuntime.kt`、
`LocalAuthSessionStoreTest.kt` 和 `ConnectionRuntimeTest.kt`，目录均位于冻结
`examples/ubaa_old/shared/src/`。对照 buaa-api 的 `src/context.rs`、`src/request.rs`、
`src/api/user/auth.rs`、`src/store/cookies.rs`、`src/store/cred.rs` 和 `src/error.rs`。
具体业务操作继续使用[来源对照索引](../README.md)中的既有九列结论，本轮不修改任何
feature 请求、解析、DTO 或上游常量。

| 操作 | CAS/引导 URL 与 service | 重定向与最终 URL | Cookie/Session/Token 范围 | 方法与精确参数 | 请求头与正文编码 | 加密/签名常量 | DTO 与解析 | 缓存/并发/重试 | 错误/退出与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| 会话所有权预检 | 本地操作，不发送引导请求。两来源没有进程 CAS 协议。 | 不发请求。 | 旧版按 `ModeScopedSessionStore` 隔离路线；示例 Context 持有 Cookie/凭据。继续保留 Core 的双路线槽位和进程 CAS。 | 不发 HTTP。 | 不发 HTTP。 | 不涉及。 | 不改会话格式、字段或 revision。 | 合并紧邻的重复预检；最终非幂等发送前的 revision 检查保留。发现外部变更不采用外部快照。 | 冲突后清内存并返回原错误，保留旧版认证失效的清理范围。 |
| 普通读取收尾 | 不改变原 feature 的 URL/service。 | feature 内原逻辑保留。 | 旧版业务认证失败通过 `resolveLocalBusinessAuthenticationFailure` 仲裁主会话；示例没有等价仲裁。仅 `authentication_required` 清当前路线，网络及解析错误保留会话。 | 原委托不变。 | 原委托不变。 | 原委托不变。 | 原委托不变。 | 不增加读取、缓存或重试。共享收尾保留原错误优先级。 | 保留普通路由元数据和固定路线 `FeatureResult` 两种公开结果。 |
| 学校写入收尾 | 不改变原 feature 的 URL/service。 | feature 内原逻辑保留。 | 复用当前路线，保留发出前 fresh authority 和会话 CAS。 | 原委托不变。 | 原委托不变。 | 原委托不变。 | 原委托不变。 | 两冻结来源没有 Core 的 non-idempotent 结果保护；继续采用现有更严格规则。跨发送边界后禁止重放。 | 发送后的确定结果或 `outcome_unknown` 不能被清理失败覆盖，读取核对和公开错误保持原合同。 |
| 旧格式磁盘写入 | 本地操作，两来源均不适用 Core schema-v1/v2。 | 不发请求。 | 生产仅写双路线 schema-v2。旧格式加载迁移继续保留。 | 不发 HTTP。 | JSON 编码不变。 | 不涉及。 | 测试构造器仍可生成旧格式；生产不保留独立旧格式写 API。 | 继续使用同一文件锁、原子替换和 CAS。 | 旧格式迁移失败保持原安全错误。 |

buaa-api 传输构造器允许调用方关闭 TLS，且错误日志支持原始内容。这些行为与本项目安全规则冲突，
本轮不采用。旧版和示例均没有等价的 Core 文件 CAS、只读工作实例代次和写发送边界，因此这些机制
继续由现有合同与确定性测试验证。

#### 实现与验证

`UbaaClient` 和 `RouteClient` 现在共用 `RouteExecution` 的路线所有权检查、认证失效清理和
写发送边界收尾。普通 facade 继续拥有双路线全局清理，固定路线客户端继续在操作收尾时核对本路线
revision。两种公开结果和所有公开操作签名保留。

原审查用 `RouteClient` 的 1126 行说明重复维护范围，其中也包括必要的公开签名、文档和固定路线
结果转换，不能把这 1126 行全部计为可删除代码。本轮集中共享安全逻辑，没有引入通用命令注册表
或改变 feature 的协议所有权。

新反例证明，未完成认证的固定路线客户端在 `InternalError` 后仍保留登录过程取得的 `SESSION`
Cookie。该反例先失败，随后通过共用普通 facade 已有的完整内存清理规则修复。初次失败与通过日志
分别保存在本地忽略目录 `.ubaa_local/core_simplification/` 的 `boundary-red.log` 和
`boundary-green.log`。

旧 `FileSessionStore` 单路线写入实现仅在 `test` 或 `test-contract` 构建中存在。生产继续加载并迁移
旧格式，只通过双路线协调器写 schema-v2。两种格式复用同一个带长度限制的 JSON 编码器。

`RouteClient` 的紧邻重复预检已经移除。`ClientRuntime::request_non_idempotent_with_pre_send_check`
仍在交给 transport 前核对 revision，之后的传输错误和清理失败仍保留已发送结果。
场馆取消原有测试按“第 3 次检查”注入故障，受重复预检次数影响。本轮改为在 fresh 详情读取完成后
注入会话存储错误，继续要求保留原错误、读取详情一次、取消请求零次。该测试保留发送前失败覆盖，
不再绑定内部检查次数。

聚焦检查结果：

- Core 默认关闭 `test-contract` 的 `cargo check --locked -p ubaa-core` 通过。
- Core lib，以及 facade、session、route_matrix、cgyy、libbook、bykc、evaluation、signin、ygdk
  九个 integration test 目标共 652 项通过，1 项按既有设置忽略。
- 本次差异空白检查通过。完整工程验收由本轮主记录汇总。

本节聚焦验证使用合成 transport，没有发起学校请求。完整确定性验收和整合后的真实双路线只读
验证结果见[本轮主记录](#rust-core-精简与缺陷修复)。

### 2026-10-11 工程边界整改

[F03/F04/F05/F06 的本地初始化、会话锁、写入异常与状态所有权对照](#f03f04f05f06-实施前来源对照)。不改变校园协议，冻结目录保持只读。

### F03/F04/F05/F06 实施前来源对照

日期：2026-10-11。纯 refs 通过，冻结 old 为 1f4b8f8412272b6a423d4ad92b396e3db721e6f3，buaa-api 为 a63712fa2ae0a6c8066197063ddee98e3a6b5b81。本轮不改变校园 HTTP 协议，不发真实请求。

已读取 old 的 shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt（LocalAuthSessionStore、LocalCookieStore、PersistentLocalCookieStorage）、commonTest 对应 Session/Cookie 测试及 repository/TermRepository.kt；读取 buaa-api 的 src/context.rs、store/cred.rs、store/cookies.rs。old 使用按路线分隔的 Settings 与协程 Mutex；示例从 cred.json/cookies.json 读取并返回 typed io/parse 错误。两者都没有 FRB 启动、UBAA2 双槽修订文件锁或 UI 初始化合同，不能借其同步加载方式证明 Flutter UI 允许无界阻塞。

| 本地操作 | CAS/bootstrap/service | 跳转/最终 URL | Cookie/Session 范围 | HTTP 方法/参数 | Header/正文 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 打开后端/读取会话 | 不发网络请求，不涉及 | 不涉及 | 保留双路线、schema v2、CAS 修订 | 不涉及 | 不涉及 | 不改变磁盘材料保护 | 不改变会话字段及解析 | 保留进程 Mutex+内核排他锁；一次获取总预算 2 秒；FRB 异步线程打开 | 超时保留 typed 资源忙原因；不删锁、不清坏会话，失败可重新打开 |
| 后端重建 | 不新增认证请求，既有恢复按原协议 | 原规则不变 | 不复用已关闭 opaque handle；迟到新实例必须释放 | 既有恢复入口不变 | 不变 | 不变 | 后端工厂变为 FutureOr，Bridge 合同升级 | 等待工厂时 UI 可绘制；退出/销毁/换代后禁止安装迟到实例 | 安全分类配置、会话、组件、资源忙、合同不兼容 |
| 成绩基线/缓存生命周期 | 本地加密读取，不新增业务请求 | 不涉及 | 保留账号、后端、会话与缓存代次隔离 | 不涉及 | 不涉及 | 加密缓存合同不变 | 原 GradeScoreBaseline 字段不变 | 生命周期所有者统一 scope，业务所有者独立持有在途与有效性 | 失效返回原 OperationConflict，不写旧账号结果 |
| 提交后异常/核对提示 | 继续使用现有 Core 原子路线绑定 | 原规则不变 | 原路线 Cookie 与 Session 修订检查不变 | 以下十种操作均沿既有请求 | 原编码不变 | 原常量不变 | 原 DTO 不变；本地 Bridge 结果增加核对票据确认 | 一次性意图不重放，发送边界独立观察；成功结果投影前保留持久线索 | 发送前已知失败保持原错误；发送后 panic/未分类跨语言异常保留 OutcomeUnknown 并回读 |

写操作逐项协议沿用 [2026-10-07 九列矩阵](#独立工程审查-rust-修复实施前来源裁决)：博雅选课、退选、签到/签退、课堂签到、图书馆预约、图书馆取消、阳光打卡、场馆预约、场馆取消、教学评教。此次只增加本地边界观察与结果确认，不调整任何 URL、service、重定向、字段、头、签名、DTO 或重试次数。old 某些方法的认证重放不用于恢复非幂等重试；buaa-api 没有等价的 FRB 意图/核对票据，不能类推。详细已有来源仍见 source-parity.md。

#### 提交后的固定路线读取

F04 进一步核对发现，原通用回读没有接收 intent 路线；场馆取消、阳光打卡、评教已有专用固定路线入口，其余补充 caller-pinned 读取。每次先验证指定路线的 Session 与修订，再复用同一个 feature 请求实现，绝不暂改全局策略或 Auto 回退。

| 操作 | CAS/bootstrap/service | 跳转/最终 URL | Cookie/Session | 方法/精确参数 | Header/编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误 |
|---|---|---|---|---|---|---|---|---|---|
| 博雅已选回读 | 原 LocalBykcApi bootstrap/service，沿原 feature 保持 | 原有界跳转保持 | 指定已认证路线 | 原 queryChosenCourse/startDate/endDate | 原 JSON 与 token 头保持 | 原博雅加密签名保持 | 原 courseList DTO 与资格投影 | 绕过新增离线恢复，不并发改策略 | 固定路线不可用即失败，不改另一条路线 |
| 图书馆预约列表回读 | 原 LocalLibBookApi 登录引导保持 | 原最终 URL 规则 | 指定已认证路线 | 原 member/seat，type=1/page/limit | 原 requestJson 编码保持 | 不新增加密字段 | 原 bookings DTO | 同上 | 同上 |
| 课堂今日回读 | 原 currentSession 引导保持 | 原规则 | 指定路线 Session/sessionId | 原 get_stu_course_sched.action，id/dateStr | 原 GET 与 sessionId 头 | 无新增签名 | 原 SigninClass | 同上 | 同上 |
| 场馆预约列表回读 | 复用已有 cgyy_orders_on_route | 原规则 | 原指定路线 | 原 get_orders/page/size | 原实现 | 原签名 | 原 CgyyOrdersPage | 不改已有取消双回读 | 原 typed 错误 |

补充读取 old LocalBykcApi.kt:393、LocalLibBookApi.kt:247、LocalSigninApi.kt:71 与示例 boya/opt.rs:51。示例只存在博雅等价请求；未实现图书馆/课堂等价协议，不借用示例 Class。其余列的具体来源继续引用主 source-parity.md 与此前逐操作矩阵。以上生产入口只复用现有 features，不重新实现请求或解析。

### 2026-10-07 独立工程审查整改

- [Rust路线/错误/日期逐操作矩阵](#独立工程审查-rust-修复实施前来源裁决)
- [Dart认证/恢复/学期状态矩阵](#独立工程审查修复dart-认证终态与状态所有权来源对照)
- [本地普通偏好/平台验证矩阵](#工程修复本地普通偏好与平台验证来源对照)

### 独立工程审查 Rust 修复：实施前来源裁决

日期：2026-10-07。基线：`06e4dfdb`。范围：七类写入的确认路线原子化、十类共同回归、私有会话冲突原因、Judge/SPOC 日期运算复用。主审线程已运行纯校验 `just refs`；本阶段不运行 bootstrap，不发学校请求，不修改冻结目录。

#### 来源与裁决

冻结旧版为 `examples/ubaa_old @ 1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；独立示例为 `examples/buaa-api @ a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。直接读取旧版 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/{feature,local}/` 的 Bykc/Signin/LibBook/Cgyy 接口与实现、对应 `model/dto` 及 `commonTest`；日期读取 `LocalJudgeApi.kt`、`LocalSpocSupport.kt` 及其测试。读取示例 `src/api.rs`、`api/boya/{core,opt,data}.rs`、`api/spoc/{core,opt,data}.rs`、`store/{cookies,cred}.rs`、`crypto` 及 `error.rs`。完整既有协议对照继续以 [source-parity.md](../README.md) 为依据；以下逐项限定本次变更。

日期补充核对冻结旧版 `gradle/libs.versions.toml` 的 Kotlin 2.3.20 与 `kotlin.time.Instant` import，读取 [Kotlin v2.3.20 Instant.kt](https://github.com/JetBrains/kotlin/blob/v2.3.20/libraries/stdlib/src/kotlin/time/Instant.kt) 的 `parseIso`。其大小写 T/Z、1–9 位小数、±HH/±HH:MM/±HH:MM:SS、最大 ±18:00 与拒绝闰秒规则不能直接等同于 Chrono RFC3339 的接受集合；因此保留很小的语法适配，将日期有效性、月份及跨日/时区运算交给已有库。超出 Chrono 可表示范围的文本保持原回退，不产生 panic；校园协议的既有四位年份及新增合成边界均覆盖。

交叉复核补充：同版本 `parseIso` 允许带符号、十位且首位为 0/1 的年份文本；`+0000002026` 的数值仍为 2026。正式合成 RED 证明先前 4–9/5–9 位正则错误回退该输入。修复只恢复这种词法兼容：先校验长度/符号/首位，再把数值规范化给 Chrono；不新增大年份运算，对超过 Chrono 范围、十一位或十位首位大于 1 的输入继续明确回退。

旧版部分写方法会认证重放，场馆还在重试块内发送最终提交；这不构成安全重放依据。本次遵守现行单次写入/unknown 合同，不恢复旧版重放。两个冻结实现均无 FRB 两阶段 intent，也无跨进程双槽修订冲突，因此不能从其 URL 或错误文字推断 intent 原子性。本次采用审查中当前代码的合成复现修复：确认 Direct 后不得因第二次 Auto 解析转到 WebVPN。

#### 逐操作九列

“保持”表示本次只移动路线匹配/私有错误分类，不改变列内已冻结的请求或解析；不是省略核对。B 表示旧版 `LocalBykcApi/LocalBykcCrypto` 与示例 Boya；L 表示旧版 `LocalLibBookApi/LocalLibBookCrypto`；C 表示旧版 `LocalCgyyApi/LocalCgyySigner`；I 表示旧版 `LocalSigninApi`。示例 `api.rs` 未提供与 L/C/I 的座位、场馆、课堂签到等价模块，不借用名称近似的 Class 接口。

| 操作 | CAS/bootstrap 与 service | 跳转与最终 URL | Cookie/Session | 方法与参数 | Header/正文 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 博雅选课 | B：SSO service 指向 `/sscv/cas/login` | B：从最终 URL/Location 提取 token；保持当前有界主机校验 | 当前路线 Cookie 与内存业务 token | POST `/sscv/choseCourse`，`courseId` | JSON 类型、双 token 头、ak/sk/ts | 冻结 AES-ECB、RSA PKCS1、SHA1 | 同 ID fresh detail 的 typed 资格；选课结果保持 | Core 单次路线解析绑定资格与 final；去掉 Bridge 重复详情复核 | 变化在 HTTP 前拒绝；最终最多一次、unknown 不重发 |
| 博雅退选 | B，同上 | B，同上 | B，同上 | POST `/sscv/delChosenCourse`，`id` | B 同上 | B 同上 | 同 ID fresh detail 与退选截止资格 | 与选课相同，保持 Core authority | 同上；资格冲突继续映射 OperationConflict |
| 博雅签到/签退 | B，同上 | B，同上 | B，同上 | POST `/sscv/signCourseByUser`，courseId/signLat/signLng/signType | B 同上 | B 同上；不更改坐标算法 | 当前学期 chosen/config，checkin/pass/时间窗/坐标 | 保留 fresh authority，绑定 intent 路线 | 输入与资格错误保持；final 不重放 |
| 课堂签到 | I：教室站点登录与 `/iclass` 既有 bootstrap | Direct `/eschool` 与 WebVPN 已冻结路径分别保留 | 内存 userId/sessionId，所属路线隔离 | GET timestamp；POST stu_scan_sign；query courseSchedId/timestamp，form id | sessionId Header，URL encoded | 无新增加密 | STATUS 与 result.stuSignStatus；保留 success=false | 原子路线内 fresh authority、时间戳及单次 final | 保留当前发送边界分类，不复制旧认证重试 |
| 图书馆预约 | L：图书馆 CAS 与独立 bearer token | 保持既有有界跳转/final 校验；示例无等价 | 路线 token 与主 Cookie 分离 | POST `/v4/space/confirm`，aesjson | JSON，Authorization bearer | 日期数字及逆序派生 key；固定 IV，CBC/PKCS7 | map/seat fresh 唯一座位、时段；结果布尔保持 | 同一路线预检和 final；不复用旧资格 | 同上，未知不得重试 |
| 图书馆取消 | L 同上 | L 同上 | L 同上 | POST `/v4/space/cancel`，正文仅 id；page/limit 仅 authority 查询 | L 同上 | 无额外加密 | 原分页同 ID active 记录、typed cancel target | 同一路线 fresh 查询和 final | 资格变化拒绝；不因回读重发 |
| 场馆预约 | C：manageLogin→`/api/login`；不新增 service | 保持当前路线包装，拒绝 final 跳转；不复制旧固定 Direct | cgAuthorization 与预约 token/challenge 各自范围保持 | day/info→order/info→captcha get/check→order/submit；现有字段集合不变 | 固定 Accept/Referer/app-key/timestamp/sign，URL encoded | 冻结 MD5 signer、验证码 AES-ECB | 同日期/空间/时段 fresh typed target；安全 receipt | final 之前有限验证码流程不变；新增 expected-route 原子匹配 | final 至多一次，任何发送后歧义 unknown |
| 场馆取消（共同回归） | C，同上 | 当前有界规则 | 当前路线 credential generation | GET orders/id；POST new/cancel/id，空表单 | C 同上 | C signer，无 captcha | canonical ID、状态及上海时间截止保持 | 保留已有 expected-route 原子入口，纳入共同合同 | 现行 strict success/unknown 不变 |
| 阳光打卡（共同回归） | 旧 LocalYgdkApi OAuth→campusAppLogin；示例无等价 | 既有有界 code 跳转，允许主机集合的旧 gap 不在本次猜测 | uid/token 当前用户与路线 generation | classify/item→upload→clockin；既有字段不变 | URL encoded/XHR；upload multipart | 无新增加密 | 正数唯一 typed target；上海日期和照片校验 | 保留已有原子路线；upload/final 各一次 | 现行成功、失败、unknown 与回读不变 |
| 教学评教（共同回归） | 既有 LocalEvaluationService 与示例 TES 对照沿主来源表 | 既有 CAS service/final 规则不变 | 当前 route/session 及内部 questionnaire | 既有按课程 typed 有序目标与问卷 final，不改正文 | 既有表单编码保持 | 不新增算法 | 四态逐课程结果，问卷不越 Core | 保留已有原子路线，无跨路线重放 | success/failure/unknown/unattempted 不变 |
| Judge 六个月截止 | 无新增请求；既有 Judge 激活/列表/详情 | 不变 | 不变 | 无新增参数 | 不变 | 无 | 月末钳制、时分秒保留；非法日期保持 None/false | 使用已锁定 Chrono 月减法；当前上海时钟策略不变 | 无新公开错误；示例无 Judge 等价截止算法 |
| SPOC 时间规范化 | 原 query/list/detail 不变 | 不变 | 不变 | 不变 | 不变 | 原零填充 CBC 不变 | 旧 Instant.parse→Asia/Shanghai；失败后 T 替空格、截断小数点；示例 Homework 保留字符串而非等价规范化 | 复用 Chrono/chrono-tz；不改变非标准字符串回退 | 不把兼容文本改成报错；非敏感合成边界用例先行 |
| 本地 Session 冲突 | N/A，本地修订 CAS | N/A | 当前双槽版本比较及清理保持 | 无 HTTP | 无 | 无 | UbaaError 四个 wire 字段不变；内部增加私有原因 | cause 随内存错误传播，不从 message 推断 | 真正 SessionConflict 才映射 OperationConflict；普通同文案错误不误判 |

#### 兼容与实现约束

`UbaaError` 内部原因使用 `#[serde(skip)]`，不出现在 CLI、FRB 或磁盘数据。Core 错误公开构造函数 `UbaaError::new` 保留，code/kind/retryable/message 保留；仓库未发现结构体字面量构造或反序列化错误后参与写入控制流。新增私有字段意味着外部 Rust 调用者须用 `new`，不能继续自行构造结构体字面量；现行合同没有保证这种构造形式。补真实构造/JSON 兼容回归，并保证反序列化不能伪造可信内部原因。公开 JSON/FRB/磁盘版本不因此升级。

Chrono/chrono-tz 已存在于锁文件，不新增依赖。标准日期运算参考 [Chrono checked_sub_months](https://docs.rs/chrono/latest/chrono/struct.NaiveDate.html#method.checked_sub_months)、[RFC3339 解析](https://docs.rs/chrono/latest/chrono/struct.DateTime.html#method.parse_from_rfc3339)、[chrono-tz](https://docs.rs/chrono-tz/latest/chrono_tz/)。迁移保留协议 wrapper 和格式门禁，避免库解析器更宽松导致接受集合变化。

#### RED/GREEN 记录

- 生产修改前：`cargo test --offline --locked -p ubaa_flutter_bridge api::write::tests -- --quiet` 编译成功后 103 通过、3 失败：完整博雅链最终路线 WebVPN 与已确认 Direct 不符；共同矩阵准确报出七类重复解析；普通同文案错误误判 OperationConflict。不是缺 API 的编译失败。
- 生产修改前：`cargo test --offline --locked -p ubaa-core 非法时区前缀 -- --nocapture` 的合成 `...15:59:59junkZ` 被错误转换为 `23:59:59`，未按冻结解析失败规则保留文本，1 项行为失败。
- 迁移中：补 Kotlin 标准偏移兼容用例并运行 `cargo test --offline --locked -p ubaa-core 冻结Instant -- --nocapture`，小写分隔被错误回退，1 项行为失败；随后按准确版本源码保留语法适配。原始安全日志位于 `<private-evidence>/legacy-tmp/ubaa2-engineering-rust-red.log`，不含学校账号或真实响应。
- 最终聚焦 GREEN：Bridge 写入 106 项通过（2.41 秒），SPOC 21 项（0.01 秒）、Judge 9 项（0.02 秒）、公开合同 7 项通过；日志 `<private-evidence>/legacy-tmp/ubaa2-engineering-rust-final-focused.log`。共同路线矩阵是 Rust Bridge 分派单元合同，合成 intent 只用于覆盖十类共有边界；另保留真实 prepare→commit 的博雅链及各领域现有准备/资格/正文测试，不将注入合同称为 UI 证据。
- 扩大验证：Core+Bridge 的 test-contract 运行先通过 Core 单测 340、Bykc 20、Cgyy 39、配置 3、连接 6、公开合同 7、评教 15、facade 116、公开边界 22、交互认证 19、内部边界 7、图书馆 26；随后旧 route_matrix 不能识别新的共享执行器而失败。保留原有计数守恒与原三类检查，将新七类逐函数验证放进 `tests/route_matrix/atomic_write.rs`；修正后 `cargo test --offline --locked -p ubaa-core --features test-contract --test route_matrix -- --quiet` 9 项全部通过（0.33 秒）。这次中途退出不记作完整工作区测试通过。
- `cargo clippy --offline --locked -p ubaa-core -p ubaa_flutter_bridge --all-targets --features ubaa-core/test-contract -- -D warnings` 通过（15.59 秒）。首次运行提醒私有 cause 未在 Debug 中说明省略，改为 `finish_non_exhaustive`，没有输出内部原因或放宽 lint。日志 `<private-evidence>/legacy-tmp/ubaa2-engineering-rust-green.log`。
- 最终只读复核：七类入口在 expected-route 比对后进入原 feature fresh authority；原发送前 Session 修订检查、非幂等边界和 `finish_routed_write` 未被绕过。Bridge 不再用 `message` 决策；内存 typed 原因不经 JSON roundtrip，外部 JSON 即使提供 cause 也不能伪造可信原因。
- 本阶段未调用真实账号、Direct/WebVPN 验证或任何学校写入。完整工作区门禁、FRB 机械生成检查和各平台证据由主修复记录另记，不继承既往通过。
- 十位前导零年份补修：`cargo test --offline --locked -p ubaa-core 带符号前导零 -- --nocapture` 编译成功后实际得到回退文本，1 项失败；修复后 `cargo test --offline --locked -p ubaa-core features::spoc::tests -- --quiet` 22 项全部通过（0.01 秒），Core 全目标、test-contract 的 Clippy `-D warnings` 通过（12.14 秒）。日志分别为 `<private-evidence>/legacy-tmp/ubaa2-engineering-rust-year-red.log`、`<private-evidence>/legacy-tmp/ubaa2-engineering-rust-year-green.log`。

### 独立工程审查修复：Dart 认证终态与状态所有权来源对照

日期：2026-10-07。改动前基线 `06e4dfdb91303d1d723cbf570bd0fc49b55bf73e`。本记录只覆盖 I03/I04 与 I06 的有限状态边界收敛；不调整 Core/FRB 协议、DTO、持久格式、真实账户或学校请求。

#### 冻结核对与权威

实现前 `just refs` 通过：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，独立示例 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`，目录均只读。

直接核对旧版：`composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/AuthViewModel.kt` 的登录/失败/退出终态，`composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/{AuthViewModelTest,AuthViewModelInitializeAppTest}.kt`；`shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt`、`api/feature/{GradeApi,ScheduleApi}.kt`、`api/local/{LocalGradeApi,LocalScheduleApi}.kt`、`model/dto/{Auth,Grade,Schedule}.kt`，以及 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/{LocalAuthServiceBackendTest,LocalAuthSessionStoreTest,LocalScheduleApiBackendTest}.kt`。旧 ViewModel 在普通失败退出 loading；其单模式界面没有当前双路线完成 token 或安全材料失败后的原位换号合同，不能照搬其全局重置。

直接核对独立示例：`src/api/sso/auth.rs`、`src/api/user/{auth,opt}.rs`、`src/api/aas/{core,opt,data}.rs`、`src/context.rs`、`src/request.rs`、`src/store/{cookies,cred}.rs`。示例没有同构 Flutter 交互完成、加密业务仓库或当前 buaascore 成绩接口；其 Cookie/凭据文件及可选忽略证书开关不能移植。未发现本次需选择的新上游冲突；现有协议差异仍由下列现行逐操作矩阵决定。

完整既有协议依据：[主矩阵](../README.md)、[离线/恢复矩阵](offline-cache.md#离线恢复逐操作来源对照)、[交互认证矩阵](auth-session.md#交互验证码整合前来源与生命周期约束)。此处逐操作列出九项边界，N/A 仅表示本次纯本地动作不发相应请求，不表示来源可省略。

#### 逐操作对照

| 操作 | CAS/bootstrap/service | 重定向/最终 URL | Cookie/Session | 方法与精确参数 | Header/正文编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|---|
| 非交互登录最终完成 | 旧 SSO `/login` 与 UC 激活；示例同 SSO、用户模块仅激活；本次继续既有 backend.login/userInfo，不增 URL/service | Core 既有同路线跳转/最终 UC 验证不变；Dart 不解析 URL | 旧模式隔离，示例共享上下文；当前 Core 双槽位不变 | 原 username/password/execution/_eventId/submit/type 及当前认证流程均不变；不新增参数 | 旧/示例 form-urlencoded；本次不接触 HTTP | 登录无新增加密；WebVPN 编解码不变 | 保留 UserSummary username/schoolId 与既有字段，身份不符不接纳 | 新完成 scope 只接受同 backend/生命周期；不创建第二客户端、缓存或写状态机 | 明确错配回 login，失败可重试输入但不自动重发认证；旧成功路径与凭据保存顺序保持 |
| 交互登录最终完成/原位换账号 | 沿交互专项既有 SSO/UC；旧支持 captcha，示例无同构验证，不借其流程 | 原 Core 有界路线与 ready 选择不变 | 挑战仍仅原后端/路线使用，完成 token 与已释放挑战分离 | 原 begin/submit/continue 参数不变；不重复提交验证码/密码 | 原编码不变，像素/答案不落盘 | 不新增算法/常量 | 仍用 InteractiveLoginCompletion(user,settings)，不公开挑战内部 | 旧账号关闭后才换本地身份；scope 隔离迟到成功/失败；原位页面与草稿保留 | 关闭旧安全索引/缓存失败必须报告并结束 loading，禁止把当前错误当过期挑战吞掉；不得冒充登录成功 |
| 注销及恢复后路线设置投影 | routeSettings 是 Core 本地状态，不发 CAS；旧有切模式重置，示例无同构双槽位 | N/A：本地 DTO 读取不产生跳转 | 不改变 Core 清 Session；仅阻止已退出/换代后的 DTO 写回 UI | routeSettings() 参数不变；logout 调用次数及顺序不变 | N/A：本地 DTO | N/A：无新增加密 | defaultPolicy/activeRoutes 类型不变 | scope 统一核对 backend/生命周期；路线变更推进该生命周期，成功和异常都不能污染新状态 | 旧快照不恢复活动路线/策略；当前读取失败仍清不确定槽位并记安全诊断；CLI 不改 |
| 学期索引与当前学期消费 | 旧 LocalScheduleApi 的 AAS 激活/currentUser，示例有另一 AAS 配置；沿现有 Core，不借示例 service | 原 AAS 最终 URL/本科判断不变 | 当前实际路线单会话 | 旧 GET schoolCalendars.do，无业务参数；请求与调用次数不变 | 既有 AJAX Accept/X-Requested-With/Referer | 无新增加密 | Term itemCode/itemName/selected/itemIndex 不变；唯一 selected 才作当前学期，不猜第一项 | 由明确 CurrentTermsReader/cache owner 持有结果与读取 scope；同代在途合并、force 绕过已完成缓存保持 | 原认证/不支持/解析错误不变；失效返回 operationConflict，不借过期学期 |
| 成绩按学期读取/聚合 | 旧 GET `https://app.buaa.edu.cn/buaascore/wap/default/index` 激活；示例 AAS 非同协议，无等价成绩实现 | 原 SSO/401/登录 HTML 仲裁不变 | 原账号/实际路线，不从展示缓存赋予会话 | 同 URL POST，xq/year 沿 term 解析，完全不改 | 原 HTML/AJAX Accept、XHR、Referer、form-urlencoded | 无新增加密 | e/m/d 与 courseName/code/score/credit/courseType/scoreType/term 映射不变 | 成绩仅消费窄学期读取能力与 ReadScope；在途共享、优先级提升、完整统计、离线证据不变 | 错学期/不完整/认证失败不成为出分基线，原 UiError/CLI 语义保持 |
| 业务内存缓存清理与 backend 重建 | N/A：本地失效，无学校请求；旧 ScheduleRepository/缓存为领域级，示例只有认证存储 | N/A | 清业务缓存保留账号/会话；重建沿既有 backend 释放顺序，不迁移 Cookie | N/A：不添加网络请求；只统一既有清单到 owner.invalidate | N/A | SQLite/AES-GCM/安全密钥及清理次序完全不改 | 现有 FeatureSnapshot/展示字段、查询位置不变 | 集中领域缓存 owner 及 academic owner 失效，取消旧计划、serial 防晚到清理；保留原 stale/空投影策略差异 | 原清理失败保旧、事务/维护错误区分不变；不自动补发读取或真实写入 |

#### 行为与验证约束

正式回归从独立审查的五个纯 fake 反例开始，必须先记录 RED。另覆盖完成阶段退出/销毁/关闭缓存失败、迟到路线失败不清新状态、学期 owner 失效和成绩查询共享、清理/重建字段保持。测试不读取凭据、不启动原生设备、不联网。

保留公开 AppController 构造/方法、ChangeNotifier 实例、WriteCoordinator 单一权威、Bridge contract v40、CLI v11 与 cache schema v6。新内部 scope/owner 不由 package barrel 导出。UI/Host 行为通过既有 package suites 验证；此次确定性通过不替代原 B2/C2/C3/D 真实/设备欠验。

#### 落地范围与本轮确定性证据

- `session/completion.dart` 是认证完成终态的唯一局部实现，私有 token 与挑战 engaged 分离。身份不符结束 loading、清活动路线并关闭本地旧账号入口；旧完成或存储错误不影响退出后新表单。已明确区分“关闭旧账号失败”与“成功在线登录但保存本机材料失败”，后者沿原合同保留成功及反馈。
- `state/read_scope.dart` 集中后端/会话/读缓存代次有效性；路线快照的成功及异常均先核对同一 SessionScope。退出/销毁独立释放 loading 和表单密码，不等待迟到任务。
- `state/academic_terms.dart` 私有持有学期结果、在途 Future、优先级 demand 与 serial；成绩只经 `CurrentTermsReader` 和 `ReadScope` 获取当前学期。`state/read_caches.dart` 提供唯一内存缓存失效入口，业务清理和 backend 重建继续分别控制空投影与 stale 投影。
- 生产改动仅在 `packages/ubaa_app/lib/src/controller/`。新增测试为 `test/session/completion_boundary_test.dart`、`test/reads/cache_ownership_test.dart`；既有 `test/session/preferences_test.dart` 仅增加两项“销毁立即清密码”断言，没有删除旧断言。没有 Host/Platform/UI/FRB/Core 生产改动来自本阶段。

日志根目录：仓库外 `<private-evidence>/legacy-tmp/ubaa2-engineering-dart-fix-20261007`，只含合成身份与安全断言。

| 阶段/命令（在 packages/ubaa_app 下） | 实际结果 |
|---|---|
| 原五个正式反例 `flutter test --no-pub --reporter expanded test/session/completion_boundary_test.dart` | RED，5 失败；`red.log` |
| 仅补充“迟到错误不能覆盖退出后的新表单” | RED，拒绝身份清理/保存账号两项失败；`red-completion-late.log` |
| 身份拒绝后的活动路线断言 | RED，交互错配仍显示两个旧活动路线；`red-rejected-routes.log` |
| 初始修复 + 原 auth/interactive 测试 | 23 项通过，五个原反例全部 GREEN |
| 新反例、独立缓存 owner、academic、grades、cache/management、recovery/backend_rebuild | 120 项通过；`focused-green.log` |
| `flutter test --no-pub --reporter expanded` | 首轮 645 通过/2 失败；原有销毁后密码释放断言发现原 finally 被 scope 取消后销毁尚未主动清密码，记录 `app-full.log`，没有删改失败断言 |
| 修正销毁立即释放后，preferences + completion_boundary | 35 项通过；`session-final.log`。新边界文件现共 8 场景，缓存 owner 3 场景 |
| `flutter analyze --no-pub` | 最终通过，无诊断 |
| `git diff --check` | 通过 |

完整工作区 Flutter、Rust/Shell/敏感检查及原生集合由主任务在合并候选上统一执行并记录；本表不预先声称它们通过。未执行真实账号、Direct、WebVPN、学校写入或设备验收。App 既有原位草稿、写资格、单次写入、失效/重建与成绩来源测试均保留。

### 工程修复：本地普通偏好与平台验证来源对照

日期：2026-10-07。生产修改前记录。基线 `06e4dfdb`；`just refs` 已验证旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、示例 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

旧版来源：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/BykcCourseFilterStore.kt` 的 StoredBykcCourseFilters/save/get/clear、`YgdkReminderStore.kt` 的 clear/clearWeekDone/clearTermDone；对应 commonTest 的 BykcCourseFilterStoreTest 和 YgdkReminderStoreTest。两个 clear 均只按账号键删除，不以旧内容解码成功为前提。当前 Dart 更严格的普通读取/保存拒绝坏数据规则继续保留。

示例来源：`src/store/mod.rs` 只有 cookies/cred，`src/api/boya/{mod,data,opt,core}.rs` 为学校业务接口，无同构本地 UI 筛选/提醒偏好。不能借其学校 URL、字段或凭据规则推断本地恢复。

| 操作 | CAS/service | 跳转/最终URL | Cookie/会话 | 方法/精确参数 | 头/编码 | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 明确清除博雅普通偏好 | 本地，不适用 | 本地，不适用 | 不访问会话；现有scope/账号键不变 | 旧Settings.remove；现Plugin remove精确键，不做整表清空 | 无HTTP；删除无需JSON解码 | 无密码学协议；现有账号键哈希不变 | 保留三集合严格读写解析；clear不需要旧DTO | 保留全实例串行尾链和账号隔离，删除后允许重新保存 | 坏旧值不阻止明确删除；插件删除失败仍固定storageFailure；普通读写invalidData不变 |
| 明确清除提醒普通偏好 | 本地，不适用 | 本地，不适用 | 不访问会话/凭据 | 旧清三个账号键；现单一JSON键remove，不改键结构 | 无HTTP；删除无需解析旧内容 | 无；不涉及系统安全材料 | enabled/weekDoneKey/termDoneKey读写不变 | 保留scope/账号隔离、串行顺序和默认开启语义 | 删除失败仍传播；不隐式覆盖坏内容 |
| 原生插件通道验证 | 无CAS/学校服务 | 无学校跳转 | 不访问账号会话 | 读取系统连接类型、订阅系统变化；使用合成scope读写删除普通偏好 | 标准插件通道 | 不写凭据/密钥 | 标准结果列表/去重，不能当校园可达证据 | 显式取消订阅/清理合成键 | 缺注册/通道失败必须令测试失败；设备切网另行验收 |

本次 I05 恢复为用户明确删除损坏普通偏好的最小修复，有冻结旧版清除语义支持；不是扩大登录清理权限，不改学校读取、认证、写入、公开DTO或持久格式。正式用例先观察失败，后实现remove并验证账号隔离/插件错误/Host清除链。

### 通用依赖收敛：实施前来源裁决

2026-10-07，基线 2eae5549。用户要求按审计建议实施收敛，开发阶段不承担旧数据迁移；本文件在生产修改前建立。冻结 old 为 1f4b8f8412272b6a423d4ad92b396e3db721e6f3，buaa-api 为 a63712fa2ae0a6c8066197063ddee98e3a6b5b81。完整请求层对照沿 [source-parity.md](../README.md)，以下按本次替换操作补九列。

来源：old 的 LocalConnectionAuth.kt、LocalWebVpnSupport.kt、LocalSpocSupport.kt、LocalLibBookCrypto.kt、LocalCgyyCaptchaSupport.kt 及 jvmMain/androidMain 的 PlatformAes 实现和既有 fixture 测试；示例的 store/cookies.rs、crypto/aes.rs、api/spoc/core.rs。old 接口/DTO 沿原逐业务对照；示例没有 Cgyy/LibBook 等价业务，不借用其他业务参数。

| 操作 | CAS/入口与 service | 跳转/最终 URL | Cookie/会话 | 方法/参数 | 头/正文 | 加密/签名 | DTO/字段 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| Cookie 接收/发送 | 两来源挂在各 HTTP 客户端，本次无新增入口 | 保持手动逐跳，以请求 URL 匹配 | old 自写过期，示例忽略过期；用户已批准标准优先级修复，保留双路线隔离 | Set-Cookie 多值逐项，Cookie 头发送 | 保留 name=value 组合 | 无 | 保留 StoredCookie 格式与注入时钟，库仅内部使用 | 保留快照/CAS/代次，不启用全局 Jar | 格式错误安全错误；无效域忽略；Max-Age 优先，非正值删除；不记录材料 |
| WebVPN 主机编解码 | old 固定 d.buaa.edu.cn，示例无同等业务入口 | scheme[-port]/主机段/path/query/fragment 不变 | 仍按网关 URL 匹配 | 无独立请求 | 十六进制与截断长度不变 | old AES/CFB/NoPadding，key/IV wrdvpnisthebest!；改用 cfb-mode/hex | UTF-8 主机和既有返回值 | 无新缓存 | 畸形输入安全错误，避免切片 panic |
| SPOC 参数加密 | 两来源 spocnewht/cas，service 沿原对照 | 原 auth/final 校验 | 原 Inco token/路线代次 | 原 JSON param 包装 | Base64 不变 | 两来源 key inco12345678ocni、IV ocni12345678inco；CBC 零填充，整块不加块；cbc/ZeroPadding | 原参数/响应 DTO | 无新缓存/重试 | 原业务错误 |
| LibBook 预约编码 | old 原入口，示例无等价协议 | 原 final 校验 | 原路线凭据 | seat_id/segment/day/start_time/end_time，后两项空 | JSON 顺序/Base64 不变 | old 日期数字+逆序 key、IV ZZWBKJ_ZHIHUAWEI、CBC/PKCS7；cbc | 原 EncryptedReserveBody | 不发真实提交 | 原 invalidInput/internal |
| Cgyy 验证码编码 | old 原入口，示例无等价协议 | 原 final 校验 | 原 challenge/token 代次 | x/y=5 与 token---pointJson | 原 JSON/Base64 | old ECB/PKCS5Padding，AES 等价 PKCS7，16/24/32 字节 key；ecb/cipher | 原 DTO | 原一次性 challenge | 无效 key 安全错误，不记录验证码 |
| 平台照片/目录/偏好/网络/关于 | 本地，无 CAS/service | 外链沿 old AppLink，学校跳转不变 | 本地账号/注销代次保留 | 插件 API，不增学校请求 | 照片字节/元信息与 10 MiB 上限 | 普通偏好不放密码，成绩仍 Core 加密 | 现有平台接口，宿主能力组合扩展 | 插件生命周期/去重/持久化集中平台层 | 取消/拒绝/不可用稳定错误，原始路径与异常不进 UI |

Cookie 冲突裁决：上轮实际代码合成 RED 证实 Expires 错误覆盖 Max-Age，无真实上游触发证据。用户“按你的建议”明确接受该已披露标准修复，按 RFC 6265 实施，不复制冻结简化/缺陷。保留来源支持的请求/持久化边界，不额外加入公共后缀策略。

照片：old composeApp/androidMain 的 PlatformImagePicker 使用 TakePicturePreview。插件替换仍保留照片/表单代次/内存上限，不增加 UI 操作；临时文件与拍照尺寸差异另在平台阶段明确记录。

### 2026-10-01至02：分支整合与当前冻结版本复核

博雅目录/完整详情、图书馆逐日日程、登录选项/Keychain和导航的旧专项来源先按两个当前固定SHA复核，再纳入离线首页，见[整合前逐操作对照](#分支整合前的冻结来源复核)。新旧缓存链不复制Cookie、联系人或写资格；当前Bridge v37和组合验证见[整合证据](../../archive/evidence/project-consolidation-2026-10-02.md)。

当前GSMIS研究生课表与节次时间轴的逐操作九列见[source-parity-gsmis-2026-10-02.md](gsmis.md#gsmis研究生课表逐操作对照)。


2026-10-07本机账号初始化异常的页面边界见[分支裁决](../../archive/history/2026-10-30-decisions-through-quality-phase3.md#2026-10-07未确认本机账号时启动必须进入登录页)：对照冻结旧版App状态机及示例Context/存储；不修改学校认证协议，未知本机身份回登录页，不开放离线首页。

2026-10-07统一安全存储插件及开发阶段无迁移范围见[实施前九列裁决](../../archive/history/2026-10-30-decisions-through-quality-phase3.md#2026-10-07开发阶段统一安全存储插件)与[验证记录](../../archive/evidence/unified-secure-storage-2026-10-07.md)。

#### 2026-10-30：OHOS 首次创建安全存储密钥

实施前复核冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/CredentialStore.kt` 与 `composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/AuthViewModel.kt`：本地开关联动与成功登录后保存凭据沿原规则。固定 `buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/store/cred.rs` 使用 JSON 文件，没有 HUKS 实现，该平台接口不适用，不借用其明文存储方式。

当前 API 26 SDK 的 `ets/api/@ohos.security.huks.d.ts` 明确规定：`isKeyItemExist` 在密钥缺失时以 `12000011` 拒绝 Promise；`hasKeyItem` 在相同情况下返回 `false`，自 API 11 提供。现有模拟实现错误地让前者返回 `false`，补成真实接口语义后，首次写入在创建密钥前失败。插件改用 `hasKeyItem`，其他 HUKS 异常继续传播。

| 操作 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 首次写入与后续读取安全材料 | 不适用，本地操作 | 不适用 | 不访问学校会话 | 无学校请求；插件键值接口不变 | 原插件参数不变 | RSA-OAEP、AES-256-GCM、别名和存储空间不变；仅更正密钥存在性查询 | 公共 DTO 不变 | 保留串行、写入读回与删除探测 | 仅缺失密钥按原规则允许首次创建；已有密文丢失密钥仍拒绝替换，其他异常不降级明文 |

2026-10-07通用依赖收敛实施前对照见[九列裁决](#通用依赖收敛实施前来源裁决)。

### 分支整合前的冻结来源复核

日期：2026-10-01。先于按钮分支生产代码合并完成本记录。当前两源为 `ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、`buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

#### 历史来源能否复用

已逐文件比较旧按钮专项固定的 `6e75e120`→当前旧版、`efb7976`→当前示例。旧版变更集中在课表/研究生课表、签到、登录到课表账号关联、Android widget 和发布；博雅/图书馆/研讨室的接口、DTO、local、crypto、store、UI和测试未出现在差异清单。示例变化仅在 class、wifi、context、net；SSO、request.rs、Cookie/credential store 内容未变化。

因此按钮分支 `31a7d750` 中以下逐操作九列来源记录仍适用于相同业务操作：`source-parity-ui-bykc-details.md`、`source-parity-ui-libbook-dates.md`、`source-parity-ui-login-options.md`、`source-parity-ui-macos-credentials.md`、`source-parity-ui-navigation-actions.md`。这些记录随对应已提交代码纳入；其中历史证据、旧 SHA/Bridge v10 等不改写成新证据，当前 Bridge v36 及后续版本独立核对。

#### 逐操作整合规则

| 操作 | CAS/bootstrap/service | 重定向与最终URL | Cookie/session | 方法/参数 | Header/编码 | 加密/签名 | DTO/parser | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 博雅课程目录与三维筛选 | 沿已对照旧LocalBykcApi | 不变 | 单客户端当前路线 | 旧分页参数不变；UI当前页本地筛选 | 不变 | 旧LocalBykcCrypto不变 | 纳入目录category/subCategory/campus等typed字段 | 与离线精确范围缓存合并；不缓存联系人或写资格 | 保持旧CLI形状/exit与本地缓存错误独立 |
| 博雅普通/已选完整详情 | 沿已对照入口 | 不变 | 不能跨路线拼接列表/详情 | 主详情→配置→已选补查；严格同ID显示 | 不变 | 不变 | 完整显示与资格分离；主配置优先，仅纯文本简介 | 在线完整详情与既有离线显示分开；迟到/身份栅栏保留 | 补查失败不伪装成功，旧API不增请求 |
| 图书馆逐日日程与座位 | 沿LocalLibBookApi及HTTP client | 不变 | 同账号/路线 | 以响应逐日时段配对；日期/seat参数取真实候选 | 不变 | 旧LocalLibBookCrypto不变 | 新typed日程与旧接口兼容 | 保留精确日期缓存；不把一天时段套用其他日期 | 空日/营业窗口保留，不把上游不可用当空座位 |
| 登录选项与macOS凭据 | 学校协议不变 | 不变 | 延续现有会话 | 仅本机Keychain接线和选项 | 不变 | 系统安全存储，不增加学校加密 | 非交互访问与可用性探测 | 与新的安全材料写入/读回/删除探测并存，退出栅栏不可丢 | 安全存储失败不得误报登录成功或降级明文 |
| 语义按钮、详情返回及筛选偏好 | 不新增请求 | 不变 | 账号隔离 | 本地参数及回调恢复 | 不变 | 不适用 | typed选择不推断上游字段 | 跨启动偏好与账号清理、恢复代次同时保留 | 保存失败保留当次编辑并明确反馈 |

示例未实现同一博雅/图书馆协议的操作继续明确不适用，不借用其字段、URL、加密或错误。context 新增校园网探测只证明示例自身行为，本轮显式 WebVPN 不引入它，也不复制关闭TLS验证的配置。

#### 当前冻结旧版新增差异

`AuthViewModel`新增 `ScheduleStore.useAccount/forgetAccount`，登录页新增可选“查看已保存的离线课表”；`MainAppScreen`新增跨日更新、账号变化重置与课表周缓存/更新/整学期导入接线。离线分支已有相应缓存首页/账号隔离/整学期导入，但仍需逐项验收，不能从同名推断完全一致。`LocalScheduleApi`和研究生协议变化留待专项核对；课堂签到继续保留主目录已经按当前冻结源完成的 `acd49c27`，绝不从旧按钮分支回退。

交互验证码和门锁专用显示尚未纳入已提交按钮分支；其方案另行按当前源码、来源冲突和失败测试核实，不能以本次合并关闭该缺口。


#### 2026-10-02 平台范围复核

当前冻结旧版 `composeApp/src/androidMain/kotlin/cn/edu/ubaa/widget/` 的 `ScheduleWidgetProvider.kt`、`ScheduleWidgetRenderer.kt`、`ScheduleWidgetActivity.kt` 实现周课表、今日和未来三天三个 Android 启动器 widget。它们读取按账号保存的 ScheduleStore，通过 owner/anchor/term/week 保存选择；切账号不沿用旧目标，点击进入同一周的离线课表。`buaa-api` 没有 Android UI 或等价 widget；不能借其协议补这项宿主功能。当前 Flutter Android Manifest/原生宿主没有对应 receiver、RemoteViews 或跳转接线。这是明确的旧功能差异，尚未实现或设备验收，不能把 Android APK 构建成功写为全功能对齐。后续需复用已加密的账号课表投影与失效机制，不能另存明文课程副本来绕过安全材料。

研究生协议差异已经按 [GSMIS 专项](gsmis.md#gsmis研究生课表逐操作对照) 完成实现和确定性门禁；上述初始段落中的“待专项核对”保留为历史记录。交互验证码与门锁显示的当前状态同理以各自 10 月阶段证据为准。

### Reqwest 传输诊断来源与行为边界

日期：2026-09-07；生产修改前记录，当前源码基线
`2f56a4530e6e2a590df4b415b9674363f6e9f72f`。

冻结引用已通过 `just refs`：`ubaa_old`
`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，`examples/buaa-api`
`efb7976bf513f38364b88aeb83d704586cff9b2a`。

#### 已核对来源

- 现行 `crates/ubaa_core/src/ports/reqwest_transport.rs` 与
  `crates/ubaa_core/src/ports/mod.rs`：生产传输启用 TLS 校验、禁用自动重定向，
  连接/整体超时为 10/30 秒，单次发送 GET 或 POST，并以 8 MiB 为完整响应预算。
- 旧版
  `shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/NetworkUtils.kt` 及其测试：
  `ApiCallException` 保留状态与机器码；只把 Ktor 的三类明确超时异常映射为超时文案，
  其余异常使用稳定网络文案。它没有当前 Rust `HttpTransport` 的等价端口或
  Reqwest 错误分类。
- 旧版
  `server/src/main/kotlin/cn/edu/ubaa/auth/api/UserFacingErrors.kt`：服务端日志会记录
  完整请求 URI 和原始异常。这属于服务端受控环境的诊断，不等价于本机客户端安全日志，
  本轮不复制 URI、异常或服务端错误映射。
- 示例 `src/error.rs` 与 `src/request.rs`：示例错误包含 source 链，格式化和日志会输出
  原始 source 或响应体；客户端也允许调用方通过 `danger_accept_invalid_certs` 关闭 TLS
  校验。两项都违反现行安全合同，本轮不采用。
- 现行 `crates/ubaa_flutter_bridge/src/api/simple.rs` 只在 FRB 初始化时调用
  `setup_default_user_utils()`。锁定的 `flutter_rust_bridge 2.13.0`
  `src/misc/user_utils.rs` 表明该函数只初始化 `log` 门面和 backtrace，不安装
  `tracing` subscriber；仓库中只有 CLI 与 `core-live` 安装 subscriber。因此新增
  `ubaa::transport` 事件在当前 App 进程没有接收器，必须由 Bridge 初始化补齐。

#### 九列保持约束

| 对照列 | 现行 Reqwest 传输合同 | 本轮保持约束 |
|---|---|---|
| CAS/bootstrap/service | 传输接收 Core 已解析的完整 URL，不选择业务入口或 service。 | 不增加、替换或推断 URL/service，不新增学校请求。 |
| 重定向/最终 URL | Reqwest 使用 `Policy::none()`；返回 `response.url()`，重定向由 Core 处理。 | 不改变重定向策略、跳数、白名单或最终 URL 语义。 |
| Cookie/session | 此传输不配置 Cookie store；会话、账号与路线范围由 Core 管理。 | 不读取或记录 Cookie/Session，不改变隔离和仲裁。 |
| HTTP 方法/参数 | `HttpMethod::Get/Post` 一一映射；请求恰好发送一次。 | 不改方法、参数、顺序、发送次数或重试策略。 |
| headers/编码 | 逐项传递现有 headers，非空 body 原样发送；固定浏览器 UA。 | 不改 header、UA、正文编码或表单内容，不记录值和正文。 |
| 加密/签名 | 传输不实现业务加密/签名；Reqwest 默认 TLS 校验保持开启。 | 不改算法/常量，不加入关闭 TLS 校验的入口。 |
| DTO/parser | 返回原始状态、最终 URL、多值 headers 和有界字节正文，不做业务解析。 | 不改 `HttpRequest`、`HttpResponse`、FRB wire DTO 或 parser。 |
| 缓存/并发 | 克隆 Reqwest client；无业务缓存、fallback、自动重试或额外锁。 | 诊断只发 tracing 事件，不参与结果、并发或路线决策。 |
| 错误/退出 | 明确超时为 `timeout/network/true/上游请求超时`；其它 Reqwest 失败为 `network_error/network/true/上游网络请求失败`；超预算为 `upstream_changed/upstream/false/上游响应体超过允许大小`。 | `UbaaError` 的 code/kind/retryable/message 与宿主退出语义全部不变。 |

#### 私有诊断合同

传输失败事件只包含以下白名单字段：

- `message`：固定为 `HTTP 传输失败`；
- `stage`：`send` 或 `receive`；
- `reason`：由稳定的 Reqwest 判断方法或有限错误链中的
  `std::io::ErrorKind` 得出的保守类别；
- `elapsed_ms`：从本次 `execute` 开始计算的饱和毫秒值。

分类不检查错误字符串。无法由上述类型信息确认的 DNS、TLS 或代理细节统一保持
`unknown` 或 Reqwest 的宽泛阶段类别，不按文案猜测。事件不得包含 URL、header 值、
请求/响应正文、Cookie、token、原始 `reqwest::Error`、source 的 `Display/Debug` 输出或
个人数据。

Flutter Bridge 只安装默认安全 subscriber：精确允许 target 为 `ubaa::transport`、级别为
DEBUG 的四字段事件，写入标准错误输出，不读取 `RUST_LOG`，不启用其它 Core 或第三方
target，不写文件、不上传。
安装使用 `set_global_default` 的失败关闭语义；宿主已经安装 subscriber 时保持宿主配置，
不得替换。

本轮只用本地回环 TCP 与断开的本地端口验证传输和诊断，不读取凭据/Session，
不访问学校。

#### RED/GREEN 与确定性验证

首次 Core RED 的历史执行记录为：程序 `cargo`，子命令 `test`，参数
`-p ubaa-core ports::reqwest_transport::tests -- --nocapture --test-threads=1`。该次执行未显式
传入锁定参数，只作为当时 TDD 失败证据，不作为当前锁定依赖门禁。生产代码尚未发出诊断
事件时退出码为 101：7 项中 5 项通过，发送失败和截断收包两项均因捕获事件为空而按预期
失败。独立日志：`<private-evidence>/legacy-tmp/ubaa-maintainability-task3-red.log`。

首次 focused GREEN 复用了上述程序、子命令和参数，同样未显式传入锁定参数；退出码为
0，7 项全部通过，只作为历史实现证据。独立日志：
`<private-evidence>/legacy-tmp/ubaa-maintainability-task3-green-focused.log`。

扩展确定性验证：

| 命令 | 结果 | 独立日志 |
|---|---|---|
| 程序 `cargo`；子命令 `test`；参数 `-p ubaa-core --features test-contract`；首次未显式锁定 | 退出码 0；Core 单元、集成与文档测试通过；仅为历史证据。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-core.log` |
| 程序 `cargo`；子命令 `test`；参数 `-p ubaa-test-support`；首次未显式锁定 | 退出码 0；96 项 Mock/fixture 合同测试通过；仅为历史证据。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-mock.log` |
| 程序 `cargo`；子命令 `clippy`；参数 `-p ubaa-core --all-targets --features test-contract -- -D warnings`；首次未显式锁定 | 退出码 0；仅为历史证据。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-clippy.log` |
| 程序 `cargo`；子命令 `fmt`；参数 `--all -- --check` | 退出码 0。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-fmt.log` |
| `just check-sensitive` | 退出码 0；执行时 825 个仓库文件通过。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-final-sensitive.log` |
| `just layout-check` | 退出码 0；0 个精确 baseline 违例。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-layout.log` |

这些结果只证明当前本地源码的确定性合同与安全诊断；真实 App、Core-live、Direct、
WebVPN、学校上游和正式发布均未执行、未验证。

本地回环 GET/POST/截断响应测试显式构造禁用系统代理的测试客户端，仍执行真实
`ReqwestTransport::execute` 链路，避免 `HTTP(S)_PROXY` 改变本地证据。断开端口使用
不可监听的 `127.0.0.1:0`；平台可将其分类为 `address_unavailable` 或
`connection_refused`，测试只接受这两个具体 `std::io::ErrorKind` 类别。

Bridge subscriber RED 的历史执行记录为：程序 `cargo`，子命令 `test`，参数
`-p ubaa_flutter_bridge api::simple::tests::bridge_initialization -- --nocapture`。该次执行未显式
传入锁定参数，只作为当时 TDD 失败证据。接线前退出码为 101：两项中宿主 subscriber
保留测试通过，安全 transport 输出测试因 stderr 不含事件而按预期失败。独立日志：
`<private-evidence>/legacy-tmp/ubaa-maintainability-task3-bridge-red.log`。

Bridge subscriber 首次 focused GREEN 复用了上述未显式锁定的历史程序和参数，退出码为
0，2 项全部通过；当时精确验证 `ubaa::transport` 的 WARN 四字段事件可见，其它 Core、
第三方及同 target 额外字段事件均不可见，且已有宿主 subscriber 不被替换。独立日志：
`<private-evidence>/legacy-tmp/ubaa-maintainability-task3-bridge-green.log`。

补充验证：

| 命令 | 结果 | 独立日志 |
|---|---|---|
| 程序 `cargo`；子命令 `test`；参数 `-p ubaa_flutter_bridge`；首次未显式锁定 | 退出码 0；110 项通过，2 项隔离子进程用例按声明忽略；仅为历史证据。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-bridge-full.log` |
| 程序 `cargo`；子命令 `clippy`；参数 `-p ubaa_flutter_bridge --all-targets -- -D warnings`；首次未显式锁定 | 退出码 0；仅为历史证据。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-bridge-clippy.log` |
| 程序 `cargo`；子命令 `test`；参数 `-p ubaa-core ports::reqwest_transport::tests`；首次未显式锁定 | 退出码 0；禁代理后的 7 项通过；仅为历史证据。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-core-no-proxy.log` |
| 程序 `cargo`；子命令 `fmt`；参数 `--all -- --check` | 退出码 0。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-final-fmt.log` |
| `just check-sensitive` | 退出码 0；执行时 828 个仓库文件通过。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-bridge-sensitive.log` |
| `just layout-check` | 退出码 0；0 个精确 baseline 违例。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-bridge-layout.log` |

Bridge 只引用锁文件中已有的 `tracing 0.1.44` 与 `tracing-subscriber 0.3.23`；
`Cargo.lock` 仅增加当前 workspace 包对这两项的依赖边，没有新增解析版本。FRB 方法、DTO、
Bridge v9 和生成文件保持不变。已有宿主 subscriber 的过滤与输出策略归宿主所有，Bridge
无法且不会覆盖；Bridge 自己安装默认值时才应用上述严格安全过滤。

##### DEBUG 兼容回归

完整 `just check-strict` 首次验证发现 CLI JSON 登录/登出的三个既有二进制合同因 stderr
出现 transport WARN 而失败；CLI 默认 subscriber 级别为 `info`，因此会输出 WARN。
失败探测是路线决策的正常输入，默认 JSON stderr 应保持为空，安全传输诊断改为 DEBUG；
CLI 只在显式设置 `RUST_LOG=ubaa::transport=debug` 时输出该诊断。原始失败保留在
该整轮日志路径随后用于最终复验，不作为独立保留的 RED；下方两个锁定定向用例分别保存了修复前证据。

级别 RED 均使用锁定依赖：

- `cargo test --locked -p ubaa-core ports::reqwest_transport::tests::send_failure_emits_redacted_diagnostic_and_preserves_public_error -- --nocapture`：退出码 101，实际 WARN、期望 DEBUG；日志 `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-debug-core-red.log`。
- `cargo test --locked -p ubaa_flutter_bridge api::simple::tests::bridge_initialization_只接收安全传输_target -- --nocapture`：退出码 101，Bridge 的 WARN 过滤拒绝 DEBUG 测试事件；日志 `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-debug-bridge-red.log`。

实现只把 Core 安全事件和 Bridge 精确过滤同步改为 DEBUG，不改四字段 schema、错误分类、
CLI 代码或公开输出合同。当前推荐复验必须使用下列锁定命令，并以本节后续记录的实际结果
为准：

- `cargo test --locked -p ubaa-core ports::reqwest_transport::tests`
- `cargo test --locked -p ubaa_flutter_bridge api::simple::tests::bridge_initialization -- --nocapture`
- `cargo test --locked -p ubaa-cli --test binary_e2e`
- `cargo test --locked -p ubaa_flutter_bridge`
- `cargo clippy --locked -p ubaa_flutter_bridge --all-targets -- -D warnings`

锁定 GREEN 与兼容结果：

| 命令 | 结果 | 独立日志 |
|---|---|---|
| `cargo test --locked -p ubaa-core ports::reqwest_transport::tests` | 退出码 0；7 项通过，事件级别为 DEBUG。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-debug-core-green.log` |
| `cargo test --locked -p ubaa_flutter_bridge api::simple::tests::bridge_initialization -- --nocapture` | 退出码 0；2 项通过，Bridge 接收 DEBUG 安全事件并保留宿主 subscriber。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-debug-bridge-green.log` |
| `cargo test --locked -p ubaa-cli --test binary_e2e` | 退出码 0；16 项通过，包含三项 JSON stderr 合同和仓库 Cargo 锁定扫描。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-debug-cli-binary-e2e.log` |
| `cargo test --locked -p ubaa_flutter_bridge` | 退出码 0；110 项通过，2 项隔离子进程用例按声明忽略。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-debug-bridge-full.log` |
| `cargo clippy --locked -p ubaa_flutter_bridge --all-targets -- -D warnings` | 退出码 0。 | `<private-evidence>/legacy-tmp/ubaa-maintainability-task3-debug-bridge-clippy.log` |

另以无凭据、无 Session 的本地代理 `auth logout` 验证 CLI 显式诊断：所有代理变量均指向
`127.0.0.1` 的临时监听器，未访问学校。设置 `RUST_LOG=ubaa::transport=debug` 后退出码为
0，stdout 为 schema v10 成功 JSON，stderr 恰有两条 DEBUG 事件且只含安全 target、固定
message、`stage/reason/elapsed_ms`；不含 URL、header 或正文。证据分别为
`<private-evidence>/legacy-tmp/ubaa-maintainability-task3-cli-debug.stdout` 与
`<private-evidence>/legacy-tmp/ubaa-maintainability-task3-cli-debug.stderr`。本地监听器已终止。

### 可维护性治理来源与行为边界

日期：2026-09-07；生产修改前记录，源码基线 `95705fdcf1095ad42d1c85b25e208ca302263a0f`。

冻结引用已通过 just refs：ubaa_old `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，buaa-api `efb7976bf513f38364b88aeb83d704586cff9b2a`。

已读取旧版 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/NetworkUtils.kt` 的 ApiErrorDetails/ApiCallException 和展示映射、对应 `shared/src/commonTest/kotlin/cn/edu/ubaa/api/NetworkUtilsTest.kt`，以及服务端 `server/src/main/kotlin/cn/edu/ubaa/auth/api/UserFacingErrors.kt`。旧版区分机器错误代码与展示文本，并保留异常处理上下文，但其服务器错误码和请求 URI 日志不能直接移植到当前本地客户端。

已读取示例 `src/error.rs` 和 `src/request.rs`：示例具有 kind/source 链，但会打印原始响应，客户端也存在可关闭 TLS 验证的配置。两者与当前安全合同不等价，本轮不复制原始日志、TLS 配置、请求重定向和错误码。

本次 Dart 修复的权威是现行 [Bridge 错误合同](../../contracts/flutter-bridge.md#3-错误合同)：已有 code/kind/retryable/resolved_route 被宿主丢弃。本轮恢复这些字段的传播，保持 CLI v10/Bridge v9，不发明新的上游错误。

#### 操作级覆盖

认证准备/登录/状态、用户资料、课表、考试、成绩、空教室、SPOC 列表/详情、Judge 列表/详情/批量、Bykc、Signin、LibBook、Cgyy、Ygdk、Evaluation 各操作的来源分别沿用 [逐操作矩阵](../README.md) 与 [入口模块来源](#core-入口职责整理来源对照)。没有等价协议的参考继续保持不适用，不按类似名称借用。

| 对照列 | 每个上述操作的保持约束 |
|---|---|
| CAS/bootstrap/service | URL、service 和现有业务入口不改。 |
| 重定向/最终 URL | 不改跳数、白名单、WebVPN 转换、禁用自动跳转规则。 |
| Cookie/session | 不改存储、账号、路线范围、世代仲裁与锁。 |
| HTTP 方法/参数 | 不改方法、参数、请求顺序和发送次数；不新增学校请求。 |
| headers/编码 | 不改 UA、头、正文编码与响应读取预算。 |
| 加密/签名 | 不改常量和算法，保持 TLS 校验开启。 |
| DTO/parser | 不改 Rust/FRB wire DTO 或解析；Dart 内部模型增加可选诊断和既有错误字段。 |
| 缓存/并发 | 不新增业务缓存/重试/fallback；诊断为有界本机内存，不参与业务锁和路线决策。 |
| 错误/退出 | Core/CLI/Bridge 的 code/kind/retryable/message 不变；Dart 保留其原始意义和失败路线，不以文案反推。 |

Rust 传输诊断的具体前置比较和 RED/GREEN 另记 `source-parity-maintainability-transport.md`。本轮新增的诊断并不证明任何上游功能或真实 App 已通过验证。

### Core 入口职责整理来源对照

日期：2026-09-05。

移动基线：`b6ff2c7d`（Phase 11K）。本记录先于生产文件移动建立；本阶段只整理两个入口，
不改变协议、公开 DTO、宿主 API、schema、fixture、写入授权或任何请求表达式。

#### 移动范围

| 原实现 | 目标实现 | 保留边界 |
|---|---|---|
| `crates/ubaa_core/src/features/mod.rs` | `features/http.rs` | 整体移动 `require_session/get_with_headers/get_with_redirects/post_form/post_json/body/check_response` 及私有 `safe_feature_url/resolve_feature_redirect/feature_redirect_error`；原 `crate::features::*` 路径以相同可见性重导出，调用方不改。 |
| `crates/ubaa_core/src/ports/mod.rs` | `ports/reqwest_transport.rs` | 整体移动 `ReqwestTransport`、其构造和 `HttpTransport` 实现、响应预算、收包与错误映射、3 个既有测试；`crate::ports::ReqwestTransport` 继续重导出同一类型。 |
| `features/mod.rs` 留存 | 原位置 | 领域声明、路线状态导出及只组合 `FeatureResult` 的 `feature_result` 保持原样。 |
| `ports/mod.rs` 留存 | 原位置 | `HttpMethod/HttpRequest/HttpResponse/HttpTransport`、DTO 构造方法和脱敏 `Debug` 实现保持原样；不拆出无独立职责的 DTO 层。 |

两个新子模块均为私有模块；所有原函数签名、返回类型、trait 约束、常量、函数体、错误文案和
执行顺序均保持。新增内容仅为模块声明、导入/重导出和中文模块说明，不新增通用协议抽象。

#### 冻结来源适用边界

两份引用以 [references.md](../references.md) 为准，移动前 `just refs` 已纯校验通过：

- `ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`。
- `examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a`。

本轮沿用 [source-parity.md](../README.md) 的逐操作九列和
[source-parity-code-organization.md](#复杂业务模块目录化来源对照) 的冻结文件映射。
冻结来源实现的是具体认证或业务操作，不存在与当前 Rust helper 拆分一一对应的公共模块合同；
不能仅因共用 HTTP helper 就把一个领域的 URL、Cookie、加密或错误规则借给另一个领域。

| 现行使用范围 | 旧版参考的适用性 | 示例参考的适用性与限制 |
|---|---|---|
| SSO、用户资料与所选路线的本地会话预检 | 沿用“准备/登录”“用户资料”“双路线加载/保存/退出”的普通认证和模式隔离对照。 | 沿用同表的 SSO、请求和共享 Cookie/凭据证据；示例的自动重定向、共享存储和用户状态接口不等价于当前固定路线资料查询，不复制。 |
| 课表、考试、成绩、空教室 | 沿用对应只读操作和空教室同步的冻结 URL、参数、UA 与会话证据。 | 严格保留原矩阵的适用/不等价结论；iClass 示例不替代旧版空教室协议。 |
| SPOC、Judge | 沿用“认证/列表/详情/批量与缓存”及既有复杂领域文件映射。 | SPOC 示例缺少等价角色建立和主会话仲裁；Judge 无等价协议。不能由共享 helper 弥补这些差异。 |
| Bykc、Cgyy、LibBook、Ygdk、Signin、Evaluation | 现有 session guard、共享 HTTP 调用及专属实现继续使用各自操作级来源，不改专属 helper。 | 沿用各领域原矩阵：Cgyy、Ygdk 等无等价协议项保持不适用；Bykc/Evaluation 等部分等价实现仍受原差异约束，不混用请求、加密或提交顺序。 |
| Reqwest 具体传输 | 冻结实现的路线/业务行为仅按上方操作对照适用，不把旧客户端实现细节视为当前 Rust adapter 的替换方案。 | 示例使用 reqwest 并不证明其重定向、Cookie 或错误策略与 Core 相同；本轮不采用其默认策略。8 MiB 缓冲上限、10 秒连接/30 秒请求预算是当前 Core 实现预算，不声称来自上游协议。 |

#### 九列保持条件

以下条件分别适用于上表每个现有操作；具体字段值仍以既有逐操作矩阵为准，本表不另造字段。

| 协议列 | 本次移动约束 |
|---|---|
| CAS/bootstrap URL 与 service | 原业务调用方与 URL 常量不动；helper 仍接收原调用参数。 |
| 重定向与最终 URL | 原 8 跳上限、主机白名单、相对地址解析、WebVPN 转换及日志条件逐字移动；Reqwest 继续禁用自动跳转。 |
| Cookie/session 范围 | 原 `ClientRuntime` 会话检查、请求调用和路线归属不动；adapter 不新增 Cookie 存储。 |
| HTTP 方法与精确参数 | GET/POST、参数顺序、正文构造、空正文处理和 request 次数不动。 |
| headers/body 编码 | 原 header 插入、表单序列化、JSON Content-Type、UA 与响应头提取不动。 |
| 加密/签名 | 本次不移动或修改任何领域加密/签名函数或常量；TLS 校验保持开启。 |
| DTO/parser 字段与类型 | 所有端口和公开 DTO 原位；`body/check_response` 的既有字符串、状态和 URL 判定逐字移动。 |
| 缓存/并发 | 不新增状态、锁、缓存、重试或 fallback；同一 runtime 和 transport 继续执行原调用。 |
| 错误/退出语义 | 原 code/kind/retryable/中文消息、响应大小拒绝与超时映射不动；CLI 退出策略仍由宿主拥有。 |

#### 验证记录

- 前置：四个 Rust 目标路径相对 Phase 11K 基线无差异；`just refs` 通过。
- 本次是机械移动，不新增行为，不伪造业务 RED；以原函数/测试块逐字比较和现有行为测试证明等价。
- 逐字比较通过：10 个共享 HTTP helper、`feature_result`、端口 DTO/trait 与其构造/`Debug`、脱敏 header helper、响应预算、Reqwest 实现、3 个原测试，共 7 组原始源码块；仅忽略块尾空行，不归一化表达式或函数体。
- 四个 Rust 目标文件的定向 `rustfmt --check --edition 2024 --config skip_children=true` 通过；`git diff --check` 通过。整理后 `features/mod.rs` 为 34 行、`features/http.rs` 为 221 行、`ports/mod.rs` 为 130 行、`ports/reqwest_transport.rs` 为 216 行。
- `cargo test --locked -p ubaa-core --lib ports::reqwest_transport::tests`：原 Reqwest 3 项单测通过，0 失败。
- `cargo test --locked -p ubaa-test-support --test auth --test readonly`：认证 28 项、只读 61 项通过，0 失败。
- refs、零例外 layout、敏感扫描和完整 `just check` 已通过；Flutter 374 项、FRB 零漂移和 macOS integration 复跑 7 项通过，独立 Rust/Dart 复审无高/中问题。
- 首次全量 Rust 检查因旧 Debug 缓存的严重启动延迟而主动终止，退出 143；保留原日志与完整缓存后，在新缓存中从头执行 `just check`，最终退出 0。中断运行不记为通过。
- 以上为本地阶段证据，不宣称最终候选、实时 Direct/WebVPN、真实写入或正式发布通过；冻结输入未改动。

### 复杂业务模块目录化来源对照

日期：2026-09-03

本记录只授权 `crates/ubaa_core/src/features` 下 Cgyy、Judge、SPOC、Bykc、LibBook、Ygdk
六个既有实现的物理拆分。协议事实仍以 [`source-parity.md`](../README.md) 的逐操作九列矩阵为
准；本记录把那些行为列映射到目标文件，防止目录整理时顺手改动 URL、参数、解析或错误语义。

冻结引用必须保持在 [`references.md`](../references.md) 记录的提交：

- `examples/ubaa_old/ @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`；
- `examples/buaa-api/ @ efb7976bf513f38364b88aeb83d704586cff9b2a`。

#### 执行边界

- 本阶段允许移动函数、类型、常量和原有单元测试，允许为兄弟模块调用把私有项最小提升为
  `pub(super)`；禁止扩大到 crate 或外部公开面。
- 六个领域入口模块对 crate 内其它调用者提供的现有 `pub`/`pub(crate)` 符号集合、请求顺序、重试次数、
  缓存所有权和 facade 调用路径必须保持不变。原 `cgyy_crypto`、`cgyy_sign`、`spoc_crypto`、
  `libbook_crypto`、`ygdk_upload` 辅助模块只供所属领域使用，迁入领域目录后允许旧模块路径消失；
  不得借此扩大可见性或新增跨领域调用。
- 任一请求字面量、表单键、Header、密码学常量、DTO 字段、解析回退、缓存代数或错误分类发生变化，
  都不再是物理拆分；必须停止并另立来源对照、RED 测试与行为提交。
- `examples/buaa-api` 有 SPOC 等价模块；其 `src/api/boya` 还为 Bykc 的同一业务端点提供交叉证据，
  但不能替代冻结 Bykc 加密与学期选择。其余四个领域明确记为“无等价实现”，不得从相似模块类比
  URL、字段、加密、Cookie 或错误。
- 测试移动到领域目录后仍在原 integration/unit target 中运行，不通过增加测试 binary 改变并发环境。

#### Cgyy

操作范围：站点、用途、日期与时段、订单列表、订单详情、锁码、预约、取消，以及预约内部使用的
验证码挑战/求解/校验。

冻结实现与测试：`api/feature/CgyyApi.kt`、`LocalCgyyApi.kt`、`LocalCgyyCaptchaSupport.kt`、
`LocalCgyySigner.kt`、`model/dto/Cgyy.kt`、`CgyyApiTest.kt`、`LocalCgyyApiBackendTest.kt`、`LocalCgyyCaptchaSolverTest.kt`、
`LocalCgyySignerTest.kt`。固定示例没有等价 Cgyy 协议。

逐操作权威段落：[`场馆预约只读查询`](cgyy.md#场馆预约只读查询) 与
[`Cgyy 预约提交`](write-actions.md#cgyy-预约提交)。

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

#### Judge

操作范围：课程列表、课程作业列表、单项详情、批量详情、历史课程筛选、worker 隔离与缓存。

冻结实现与测试：`api/feature/JudgeApi.kt`、`LocalJudgeApi.kt`、`model/dto/Judge.kt`、
`JudgeApiTest.kt`、`LocalJudgeApiBackendTest.kt`。
固定示例没有等价 Judge 协议。

逐操作权威段落：[`Judge 列表`](coursework.md#judge-列表)、
[`Judge 详情`](coursework.md#judge-详情) 与
[`Judge 批量与缓存`](coursework.md#judge-批量与缓存)。

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

#### SPOC

操作范围：CAS/SPOC 登录、当前学期、课程列表、作业分页、作业详情、可选提交内容与安全诊断。

冻结实现与测试：`api/feature/SpocApi.kt`、`LocalSpocApi.kt`、`LocalSpocSupport.kt`、
`model/dto/Spoc.kt`、`SpocApiTest.kt`、`LocalSpocApiBackendTest.kt`、
`LocalSpocSupportTest.kt`。固定示例的最近交叉来源为 `src/api/spoc/{core,data,mod,opt}.rs`，
但逐操作行为存在差异；发生冲突时仍以实时证据或适用冻结本地实现为准。

逐操作权威段落：[`SPOC 认证`](coursework.md#spoc-认证)、
[`SPOC 列表`](coursework.md#spoc-列表)、[`SPOC 安全诊断`](coursework.md#spoc-安全诊断)
与 [`SPOC 详情`](coursework.md#spoc-详情)。

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

#### Bykc

操作范围：登录、用户资料、学期/课程列表、课程详情、已选课程、统计、选课、退选和签到。

冻结实现与测试：`api/feature/BykcApi.kt`、`LocalBykcApi.kt`、`LocalBykcCrypto.kt`、`model/dto/Bykc.kt`、
`model/dto/BykcSerialization.kt`、`LocalBykcApiBackendTest.kt`、`LocalBykcCryptoTest.kt`。
固定示例 `src/api/boya/{core,data,mod,opt}.rs` 提供同一业务端点的交叉证据，但其包装和加密不能
替代冻结旧版决定。

逐操作权威段落：[`博雅课程只读查询`](bykc.md#博雅课程只读查询) 与
[`UBAA2 直接写操作与评教`](write-actions.md#ubaa2-直接写操作与评教2026-08-28) 的 Bykc 行。

| 行为列 | 目录化决定 |
|---|---|
| 启动/服务 URL | CAS/业务 API 及选课、退选、签到端点保持原常量和路线转换。 |
| 重定向/最终 URL | token 提取、Direct/WebVPN 还原和相对 Location 解析整体归入 `auth.rs`。 |
| Cookie/会话范围 | 独立业务 token 继续挂在路线状态，不进入 session 文件。 |
| HTTP 方法与精确参数 | profile/course/chosen/statistics 与三项写操作的 encrypted request 内容不改。 |
| Header/正文编码 | timestamp、摘要、加密载荷包装和现有 Header 保持逐操作原样。 |
| 加密/签名常量 | 加解密函数与冻结向量归入 `auth.rs` 或独立算法文件；不得重算或替换常量。 |
| DTO/解析字段 | `data.courseList` 包装兼容、学期选择、状态/分类/签到点与时间窗口解析整体迁入 `parser.rs`。 |
| 缓存/并发 | token 登录锁和路线清理语义不改；UI eligibility 不在本机械阶段实现。 |
| 错误/退出语义 | envelope、非法响应、输入和业务失败分类不改，写操作仍需 facade/宿主确认。 |

目标：`bykc/{mod,auth,crypto,read,write,parser,tests}.rs`。

#### LibBook

操作范围：馆区、区域、区域详情、座位、预约列表、预约和取消。

冻结实现与测试：`api/feature/LibBookApi.kt`、`LocalLibBookApi.kt`、`LocalLibBookCrypto.kt`、`LocalLibBookHttpClient.kt`
及各平台 actual、`model/dto/LibBook.kt`、`LocalLibBookApiBackendTest.kt`、
`LocalLibBookCryptoTest.kt`。固定示例没有等价 LibBook 协议。

逐操作权威段落：[`图书馆座位只读查询`](libbook.md#图书馆座位只读查询) 与
[`UBAA2 直接写操作与评教`](write-actions.md#ubaa2-直接写操作与评教2026-08-28) 的 LibBook 行。

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

#### Ygdk

操作范围：OAuth/业务登录、分类/项目/统计/学期概览、记录分页、照片上传和打卡提交。

冻结实现与测试：`api/feature/YgdkApi.kt`、`LocalYgdkApi.kt`、`model/dto/Ygdk.kt`、
`YgdkApiTest.kt`、`LocalYgdkApiBackendTest.kt`。
固定示例没有等价 Ygdk 协议。

逐操作权威段落：[`阳光打卡只读查询`](ygdk.md#阳光打卡只读查询) 与
[`UBAA2 直接写操作与评教`](write-actions.md#ubaa2-直接写操作与评教2026-08-28) 的 Ygdk 行。

| 行为列 | 目录化决定 |
|---|---|
| 启动/服务 URL | OAuth、`campusAppLogin`、分类、项目、统计、学期、记录、上传和提交地址保持原样。 |
| 重定向/最终 URL | 十次有界跳转及 query/fragment code 提取归入 `auth.rs`。2026-10-30 复核后只允许冻结已证的 HTTPS app/ygdk 默认端口，WebVPN 内层同样验证，未知主机拒绝。code 只取 ygdk 已证回调并单次百分号解码；真实完整跳转链兼容性尚未验证。行为修改与结构整理分开记录，见[认证安全复核](auth-session.md#认证安全修复复核)。 |
| Cookie/会话范围 | `{uid,token}` 仍为路线内存状态，不复用主认证 Cookie、不持久化。 |
| HTTP 方法与精确参数 | 概览固定分页、记录分页、上传 multipart 和提交表单全部保持冻结字段。 |
| Header/正文编码 | `X-Requested-With`、form 编码、multipart boundary/filename/MIME 与 query/body 双写不改。 |
| 加密/签名常量 | 两份来源均无自定义加密；不得引入。 |
| DTO/解析字段 | envelope、primitive 文本、上海时区时间、图片字符串/数组和分页字段整体归入 `parser.rs`。 |
| 缓存/并发 | 路线内登录单飞与失效代数保持 2026-09-03 决策；旧登录结果不得越过 `clear` 回写。 |
| 错误/退出语义 | `code=1`、`-98`、非法分页/输入、可选统计和写失败分类与一次认证重试不改。 |

目标：`ygdk/{mod,auth,http,read,write,parser,upload,tests}.rs`；认证、底层请求、读取编排与写入编排保持
单向依赖，不把所有网络职责重新堆回一个 `service.rs`。

#### 每个物理拆分提交的验收

1. 先运行该领域现有 parser/request/cache/crypto/concurrency focused tests并记录测试叶集合。
2. 只移动一个领域；用明确 pathspec 暂存，确认没有冻结引用、fixture、凭据或生成物。
3. 结构测试确认该领域所有手写文件少于 1000 行、父 `features` 直属文件数只降不升。
4. 再运行同一 focused 集合，测试名与数量不减少；随后运行 `just refs`、`just check-sensitive`、
   `just layout-check` 与 `just check`。
5. 对请求常量、公开符号和 facade 调用点做文本差异复核；除模块路径/可见性外若出现行为 diff，停止该提交。
