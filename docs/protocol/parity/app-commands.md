# 公共命令、CLI 与配置

本文件收录 App 命令、共享本机服务、CLI 配置与命令实现抽取的来源对照。

## 当前规则

### App 命令与共享本机服务

当前冻结引用仍为旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。共享恢复与账号生命期沿用下方 H1 的逐操作来源。命令层重新核对旧版 `LocalBykcApi/LocalSigninApi/LocalLibBookApi/LocalYgdkApi/LocalCgyyApi/LocalEvaluationService`，以及 buaa-api 的 `api/boya/opt.rs`、`api/tes/opt.rs`、`request.rs`。现有来源冲突和不适用项继续按各领域专项处理。

| 操作 | 协议与 DTO | 本机执行与错误语义 |
|---|---|---|
| 用户及各只读功能的所需路线校验 | CAS/service、重定向、Cookie/Session/Token、方法/参数、请求头/编码、加密常量和字段均复用既有 Core facade。User 使用原用户操作，其他目标使用各自功能配置。 | 命令核实安全索引中的实际账号；仅明确认证过期或受支持的同账号会话继任允许一次完整重跑。网络错误和异账号不提交密码。 |
| 十类学校写入 | 原 facade 的 fresh authority、精确请求和 typed 回执保持。Cgyy 内部验证码仍由 Core 管理，CLI 输入拒绝这些字段。 | GUI 与命令共享同一准备、一次性意图、固定路线提交和回读。发送后取消或 Future 丢弃保留未知结果和核对提示，不重放请求。 |
| 共享日程、数量比较清除和 ICS 文件交付 | 两个来源没有同等本机协议，CAS/service、重定向、会话作用域、HTTP、编码、签名和学校 DTO 列不适用。 | 保留原 alias、CacheKey 和明文日程 schema。比较数量与清除在同一写事务完成，交付文件和排队正文均核对固定共享代次。 |
| 原生入口和系统材料传输 | 两个来源没有 Flutter Engine、Dart AOT 或跨进程系统材料适配，各 HTTP 列不适用。 | macOS/Windows 分离 GUI 角色与命令消费者；Linux 复用锁定插件的 account/JSON item，直接连接 Secret Service，不使用明文材料或 portal 降级。 |

来源支持的学校 URL、请求参数和解析器没有通过命令层复制。确定性证据使用固定路线 Mock、NeverProbe 和独立合成材料。真实账号、真实学校读写和默认真实材料连续性分别按授权与平台证据记录。

## 逐操作基线矩阵

以下矩阵沿用[逐操作历史矩阵](general.md#逐操作历史矩阵)的取证说明：原始取证版本、换钉后的适用方式和重新核对要求以该节为准。

### CLI 与配置

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**宿主 UI 选择 `ConnectionMode`，没有等价 UBAA2 CLI/配置。**示例：**只有库上下文，没有 CLI/配置/schema。**决策：**上游 URL 不适用，普通路由由聚合 Core facade 负责。 | **旧版/示例：**没有等价 CLI 跳转合同。**决策：**宿主只接收 facade 结果。 | **旧版：**按模式保存设置，切换会清会话。**示例：**调用方管理 `cookies.json`/`cred.json`。**决策：**Core 加载严格的 `config.toml` 版本 1 和 schema-v2 双路线 `session.json`；CLI 不读取存储内部。 | **旧版/示例：**无等价命令。**决策：**CLI 解析文档命令/参数，调用不带 `ConnectionMode` 的 facade 并负责渲染；隐藏模式仅用于诊断/测试。 | **旧版/示例：**无信封。**决策：**stdout 只输出一个 JSON 值，诊断仅写 stderr，不输出敏感值或原始上游数据。 | **旧版/示例：**不适用。**决策：**当前 CLI envelope 只使用 schema v16；配置/会话磁盘版本独立。历史 v3 显式承载 Bykc 可空 `checkin`、三态签到/签退资格和 `outcome_unknown`；v4 再承载 Signin 可空 `signStatus`、三态资格/目标与确定业务结果；v5 承载 LibBook seat 可空整数 `status`、typed `reserveEligibility/reserveTarget` 和确定的 `LibBookReserveResult`；v6 再承载 LibBook booking 可空整数 `status`、typed `cancelEligibility/cancelTarget` 与取消结果；v7 承载 Cgyy 可空 canonical 状态、typed `reservationEligibility/reservationTarget` 与安全预约结果/收据；v8 承载 Cgyy typed `cancelEligibility/cancelTarget/cancelledTarget` 与固定安全取消结果；v9 承载 Ygdk typed `submitEligibility/submitTarget`、完整请求、安全结果和 caller-pinned 回读；v10 再承载 Evaluation typed `submitEligibility/submitTarget`、仅含 targets 的请求、四态批量结果与 caller-pinned 回读，均不在旧版本号下静默改变合同。聚合路线数组固定 Direct 后 WebVPN；`all_ready`/`partial` 必须有完整资料，`none_ready` 禁止存在资料。路线错误只含稳定安全错误，不含挑战/图片字段或验证码错误码。单路线信封不能带聚合字段，解析前错误只带功能名。 | **旧版：**全局模式/运行时。**示例：**调用方拥有上下文。**决策：**配置、探测缓存、路由、会话和业务状态由 facade 拥有；CLI 不持有路由缓存。配置写入拒绝符号链接/非普通文件并使用唯一原子临时文件。 | **旧版/示例：**没有等价退出分类。**决策：**使用稳定退出码 0/2/3/5/6/7/8；新配置目录支持 JSON 登录；交互验证页映射为 `upstream_changed`（退出 6），缺少本地用户/功能会话时在网络前失败。

2026-08-24 的配置持久化证据：Unix 测试证明加载和保存会拒绝符号链接 `config.toml`，不会读取
或改变其目标。八个并发保存使用唯一独占临时文件发布一份完整可解析配置，不遗留临时文件，
并保持目录/文件权限 `0700`/`0600`。这仅是本地文件系统证据。

2026-08-24 的验证器证据同样仅为确定性证据。Shell harness 拒绝非 2 的 CLI Schema、危险稳定错误、
非严格 Direct 后 WebVPN 的聚合路线数组、暴露不支持交互验证字段的路线/错误状态、没有权威全局
页却声称 SPOC 空结果、资料不完整/因果矛盾/未脱敏、Rust 整数字段为小数或越界、跨请求课表/成绩
学期漂移、SPOC 详情身份或冻结状态文本漂移、Judge ID/题目/计数/分数/状态语义矛盾、解析路线
矛盾、不完整或多余 DTO 字段、重复 Judge 键，以及包含凭据、会话或原始响应别名、完整 HTML 文档
或 CAS 表单的输出。不会用任意尖括号文本推断来源；严格 DTO 闭合和确定性解析测试证明原始 HTML
字段不存在。上一段描述的是已取代的验证器设计。当前 `core-live` 只输出路线、操作、状态、
稳定错误、耗时、计数和依赖/来源字段，不执行 jq 聚合，也没有 `UBAA_VERIFY_DIGEST_SALT` 前置
条件。当前 Direct/WebVPN 证据按操作记录在 `docs/project/status.md`，`auto` 仍仅确定性验证。

## 专项记录

### 2026-11-01：H2-common-a 命令实现抽取

冻结引用仍为 `ubaa_old@1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和 `buaa-api@a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。实施前核对旧版 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/CgyyApi.kt`、`api/local/LocalConnectionAuth.kt`、`model/dto/UserInfo.kt`，以及 buaa-api `src/api/user/{auth,opt}.rs`，并沿用本索引各业务的逐操作记录。

| 操作 | 两来源适用性 | 本次处理 |
|---|---|---|
| 既有各业务认证、读取和学校写入 | 沿用各操作已有来源记录 | backend/facade 调用机械迁移，业务 CAS/service、重定向/最终 URL、Cookie/Session/Token、方法/精确参数、头/编码、加密签名常量、DTO 类型、缓存/并发/重试均不改 |
| 命令计划、执行结果暂存和最终渲染 | 两者无同等 App 命令运行时，均不适用 | 分类不按 HTTP 方法推断，仅 readonly 明确认证过期且有路线时暴露 AuthExpired；本单元不实际恢复或重跑 |
| 研讨室 stdin 注入、短写与 flush、命令取消和期限 | 两者无同等终端接口，均不适用 | 既有 typed JSON 校验和写确认顺序保留，修复宿主输入绕过；停止投影沿 v13，见[决定](../decision-log.md#2026-11-01h2-命令骨架平台分发与停止规则) |

不新增学校协议，也不依据来源缺失补猜参数。验证仅用合成输入、Mock transport 和 NeverProbe；真实 Direct/WebVPN 本轮均不运行。

2026-11-02 补充本地登录输入审查：按上述固定提交重读旧版 `LocalConnectionAuth.kt` 的 login、`model/dto/Auth.kt` 的 LoginRequest、`storage/CredentialStore.kt` 及 `LocalAuthServiceBackendTest.kt`、`AuthServiceTest.kt`，以及 buaa-api 的 `src/api/sso/auth.rs`、`src/api/user/auth.rs`、`src/store/cred.rs`。旧版接收完整用户名和密码，buaa-api 从凭据存储依次取用户名和密码，两者均无终端 stdin 快照接口。该接口的读取顺序、UTF-8 错误与退出码对两冻结来源均不适用，依据本项目已有固定路线与聚合登录输入实现保持兼容。

| 操作 | CAS/service、重定向、最终 URL、Cookie/Session/Token | 方法、精确参数、头、编码、加密/签名 | DTO、缓存、并发、重试、错误与产品语义 |
|---|---|---|---|
| 登录 stdin 输入快照 | 只调整本地输入准备，上游各项沿用既有认证来源记录 | 无学校请求变化，无新增字段或常量 | 复用既有用户名读取与校验后才读取密码；空行、全空白与无效 UTF-8 首行立即返回原 InvalidInput，退出码保持 2，正常输入只读所需行；CLI schema 保持 v13，缓存、并发、重试与凭据存储不变 |

三项合成失败回归先证明准备入口读取后续密码时的错误遮蔽。修复与验收仅使用合成材料和 Mock，本次本地输入变化不发起学校请求。
