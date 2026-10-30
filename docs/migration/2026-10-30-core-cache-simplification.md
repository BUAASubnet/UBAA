# Rust Core 缓存刷新精简

日期：2026-10-30。范围是 facade 的本地缓存生命周期、重复结果包装和失效实现。学校协议、写入资格、持久加密、账号与路线隔离保持原有实现。

## 来源与操作对照

冻结来源为 `ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 与 `buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。读取旧版对应的 `api/feature`、`api/local`、`model/dto` 和 `commonTest/.../api/Local*BackendTest.kt`。共享认证读取 `LocalConnectionAuth.kt`，第二来源读取 `api/user/auth.rs`、`request.rs`、`store/cookies.rs`、`store/cred.rs` 和 `error.rs`。

下面每行按本轮操作列出两个来源。表中的“不适用”只针对本轮本地 ticket 生命周期；不得据此补齐上游协议。已有逐操作协议事实继续由[原缓存来源记录](source-parity-offline-recovery-2026-09-17.md)及[来源索引](source-parity.md)维护。

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

两个来源都没有本项目的持久 `CacheReadTicket`。本轮退出与被取代规则以现有[缓存合同](../contracts/offline-cache-and-recovery.md)和跨连接测试为依据，不从来源的会话缓存类比构造新字段。

## 修复与保留边界

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


## 验证记录

新增今日/希冀各两种竞态反例：读取过程中退出账号，以及另一数据库连接开始同范围新读取。RED 日志保存在本地忽略目录 `.ubaa_local/core_simplification/cache-red.log`。原有网络参数、精确范围、身份、完整/部分结果、容量、跨连接和只读持久化安全覆盖继续保留。旧格式转换测试的删除项及替代覆盖见上表。

本节聚焦验证使用合成 transport。缓存格式的第二组 RED 日志为 `.ubaa_local/core_simplification/cache-format-red.log`，证实旧 schema v6 在修改前会被普通打开接受。整合后的真实双路线只读结果由主记录汇总。

聚焦验证通过：`cargo test --locked -p ubaa-core --features test-contract --lib cache::` 通过 80 项，facade 集成测试通过 121 项。补齐未来版本 99 后，版本拒绝测试再次通过。Core 全目标 Clippy 使用 `--features test-contract -- -D warnings` 通过。日志分别为 `.ubaa_local/core_simplification/cache-format-green.log`、`cache-facade-final.log`、`cache-version-final.log` 和 `cache-clippy-final.log`。全量确定性门禁由本轮主记录统一登记。
