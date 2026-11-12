# 本机账号、安全材料与身份生命周期

本文件收录同机账号索引、平台安全材料、共享恢复、身份撤销、CLI 账号登记与同账号资料缓存的来源对照。

## 当前规则

### Android 首次安全存储初始化

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/CredentialStore.kt` 使用 Settings 保存凭据。固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/store/cred.rs` 使用 JSON 文件。两源没有 Android Keystore 或 flutter_secure_storage 算法标记的等价初始化操作。此本机操作的 CAS/service、重定向与最终 URL、Cookie/Session/Token、HTTP 方法和参数、请求头和编码、上游加密/签名、DTO 各列均不适用；学校认证、读取和写入保持原协议。

Android 使用锁定 `flutter_secure_storage 10.0.0` 的 `migrateOnAlgorithmChange=true` 和 `resetOnError=true`。首次空存储通过插件初始化当前 RSA-OAEP 与 AES-GCM 算法；已有材料优先迁移，正常重开保留材料。单项密文解密失败时插件删除该项，算法或密钥迁移失败时允许清空安全存储并重新初始化。清理可能要求重新登录和重新获取加密缓存，不退回明文。能力探测继续验证读取、写入和删除。iOS/macOS 的 Keychain、Windows 的 DPAPI、Linux 的 Secret Service 和 OHOS 的 HUKS 不使用这些 Android 标记，错误处理保持各平台原规则。

### H1-b3b：共享句柄关闭与持久身份撤销

改生产代码前核对冻结旧版 `1f4b8f8` 的 `api/storage/CredentialStore.kt`、`api/local/LocalConnectionAuth.kt`、`GradeScoreCacheStore.kt` 及其测试，以及冻结 buaa-api `a63712fa` 的 `src/store/{cred,cookies}.rs`、`src/api/user/auth.rs`。普通句柄释放、跨进程缓存/日程事务和交付、持久写资格撤销均为本机操作，两源没有同等协议。因此这些操作的 CAS/service、重定向和最终 URL、Cookie/Session/Token、HTTP 方法和参数、请求头和编码、上游加密/签名、DTO 各列不适用。已有学校认证、读取和写入继续沿用本索引各领域的逐操作对照，URL、参数、路线与错误语义保持。

本机并发与错误语义：普通关闭释放本进程句柄，显式退出与换号撤销共享旧身份。旧本地操作在提交和结果交付边界核对捕获的身份，已交付事务按实际提交或回滚记账。学校写入不恢复、不换客户端、不自动重试，发送后不能确认的结果保留 OutcomeUnknown。协议回归使用固定路线 Mock。新增原生全局退出红灯曾误入生产 SSO logout GET 路径，使用新 UUID 合成目录和空学校会话，日志无法确认请求是否发送或到达学校。该路径已停止，后续原生通过客户端 RPC 白名单工厂隔离远端调用，生产受限注销 RPC 另由 Rust Mock 验证。标准完整验收另获授权运行既有真实 Keychain 合成回归，仅操作本次新 UUID 目录派生的精确 account 并删除该条目，不访问已有真实账号或凭据。

### H1-b3a：持久恢复 scope 与客户端继任

生产修改前重新读取冻结旧版 `1f4b8f8` 的 `api/storage/CredentialStore.kt`、`api/local/LocalConnectionAuth.kt`，以及冻结 buaa-api `a63712fa` 的 `src/store/{cred,cookies}.rs`、`src/api/user/auth.rs`。所需路线校验、凭据登录仍逐操作沿用下方 H1-b1 的协议列，CAS/service、重定向与最终 URL、Cookie/Session/Token 作用域、方法和精确参数、请求头与编码、加密常量和 DTO 解析均无变化。

持久 scope 捕获与核对、恢复操作锁、连续身份代次、恢复发布、结果交付和客户端重建是本机协调操作，两源没有等价操作，上游协议各列均不适用。账号索引继续使用原材料键、alias 和 CacheKey。恢复发布只推进 generation，显式登录、退出、切号和撤销许可同时改变连续身份代次。旧索引首次更新时以原 generation 建立连续身份代次。网络期间仅持有独立恢复操作锁，材料锁只覆盖短事务。等待者重新核对身份与许可，并先验证当前会话，再决定是否提交密码。Core 外部 revision 冲突仍是旧客户端终态，继任在应用服务边界创建。旧写资格不得通过恢复续接。凭据被拒时只用密码提交所属快照条件撤销持久许可，旧失败不得重新捕获新快照后撤销。

审查修复前再次核对上述两源凭据存储、旧版 `LocalConnectionAuth.kt` 和示例 `api/user/auth.rs`。交付停止合并、单消费者取消隔离、GUI 最终状态发布与被拒凭据的后续清理均为本机协调操作，两源无对应的跨进程身份协议，上游协议各列不适用。学校认证、读取、路线与 Cookie 规则继续沿用下方 H1-b1 对照表。共享恢复已按提交所属快照撤销许可，GUI 不再追加无归属的凭据清理。最终 profile/ready 在最后一次路线设置等待后，通过原恢复 scope 的短材料事务核对身份和许可再发布。

本单元只运行合成材料和固定路线 Mock，不进行真实学校请求。普通消费者关闭、缓存/日程句柄和写资格完整生命周期继续由 b3b 处理。

### H1-b2：同机账号与安全材料协调

生产修改前核对冻结旧版 `1f4b8f8` 的 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/CredentialStore.kt`、`api/local/LocalConnectionAuth.kt`，以及冻结 buaa-api `a63712fa` 的 `src/store/cred.rs`、`src/store/cookies.rs`。旧版保存记住密码与自动登录偏好，关闭记住密码会清除密码并关闭自动登录。buaa-api保存 API 凭据期限与 Cookie，没有本机随机 alias、CacheKey 或跨进程恢复许可协议。

本单元逐操作涉及索引读取、保留已核实账号、取得待建密钥、退出、删除账号、凭据读写/清除、能力探测及持久代次条件校验。两源均无这些 UBAA2 安全材料操作的等价协议，因此 CAS/service、重定向/最终 URL、HTTP 方法/参数、请求头/正文编码、上游加密/签名和 DTO 字段全部不适用，不新增或推断学校字段。Cookie/Session/Token 的既有路线与作用域保持。仅调整本机锁、失败阻断和代次：索引/凭据继续保存于既有安全后端，禁止网络期间持有材料锁，写入不自动重试。退出先撤销许可，普通句柄释放不改共享许可。H1-a scope 的跨进程接线留给 b3。本轮仅合成材料，学校请求与真实材料访问为零。

Windows 接续核对纠正：锁定 `flutter_secure_storage 10.0.0` 的 `WindowsOptions.defaultOptions` 默认 `useBackwardCompatibility=false`，门面 `_selectOptions` 实际传入该值，当前 App 没有开启 legacy Credential Manager 迁移。本轮不新增迁移能力。插件内部省略选项时的迁移路径不能作为当前默认缺陷。实际缺口是锁定 `flutter_secure_storage_windows 4.1.0` 的 `DpapiJsonFileMapStorage.load` 在 DPAPI、UTF-8、JSON 或非对象错误时删除原件，并把读取异常解释为空 map；后续写入还会无限重试。

Windows 文件适配保留 `getApplicationSupportDirectory`、`flutter_secure_storage.dat`、用户级 DPAPI（无 entropy、flags=0）和全部材料键。读取不写入或迁移，严格拒绝损坏及未知条目，只有明确的 OS 文件不存在错误允许空 map。写入先生成同目录临时密文，已有目标使用带备份的 `ReplaceFileW(flags=0)` 保留原安全描述符，失败保留备份与未完成标记，不自动重试。`GetFileAttributesW` 查询失败时，通过 Dart I/O 只读打开目标取得系统错误。只有明确不存在的错误 2/3 才允许使用不带覆盖标志的 `MoveFileExW(WRITE_THROUGH)` 首次创建，目标后来出现时直接失败。其他查询错误、目录或重解析点均阻断。Windows 11 x64 已用合成材料验证真实 DPAPI、首次创建、替换、删除与读回；真实旧材料连续性、DACL、原生共享冲突与替换中途崩溃仍待专项验收。

锁域候选的纯 Dart 桌面解析器改用系统用户目录接口，忽略 HOME/USERPROFILE/XDG/config 覆盖，macOS 纯 Dart 环境变量反例已转绿。当前 macOS 宿主启用 App Sandbox，因此 Flutter 默认材料工厂继续通过原生应用支持目录接口选择沙箱可达目录，避免把 GUI 锁移到 POSIX 用户 home 的容器外目录。macOS 正式命令路线与 GUI 使用同一 App 的 Flutter Engine。私有 Bundle ID 样机复用候选目录代码和生产相同的 Sandbox entitlement，实际 GUI/无窗口 Engine 取得相同 support/material 路径，分别采用两个业务目录覆盖，并完成随机合成子目录双向读写、清理及正常退出。GUI 有窗口和 Dart view，无窗口 Engine 原生窗口数为 0、viewController 为空，但仍有默认 Dart view。样机只包含目录插件，不访问钥匙串，因此原有安全材料连续性和 Windows 跨入口后端路径连续性仍待验证。

事务入口直接读取 `transaction.v1`，仅明确不存在的 OS 错误 2（Windows 另含 3）允许初始化。存在查询吞掉错误后的读取失败、空 OS 错误和 UTF-8 损坏均以 `uncertain` 阻断。实际协调决策的失败反例与修复回归检查业务回调和材料变更次数为零，原 B 标记保持，错误消失后仍阻断。嵌套、迟到写和进程恢复覆盖保留。

Linux Debian arm64 在 `ubaa-h0:validated` 固定镜像、nobody、断网、无显示、无特权及只读容器中，通过当前精确源码副本的 35 项纯 Dart 测试和 9 组 AOT 组合验证，覆盖同/异账号、并发 probe、四种外部状态变更后的旧快照拒绝、kill 解锁和密钥写入后崩溃阻断。仅私有 tmpfs 运行目录允许执行 AOT，输入为只读挂载，50 个纯 Dart 依赖按当前锁定版本离线解算。材料后端使用实际 Windows 文件层加合成 codec，没有访问真实材料或学校。该结果不填补 Windows 原生及移动/OHOS 缺口。本节仍为 H1-b2 候选，H1-a scope 的持久代次接线留 b3。

原生测试原先只替换锁域，Windows/Linux 整 map 后端仍可能访问默认材料。合成默认域预置 B 且旧 target 移至备份时，实际测试组合的失败反例确认默认 target 被创建。测试组合现同时隔离数据与协调域，默认传输构造次数为零，原 target（存在或缺失）、backup 和 B 保持不变。Windows 私有文件保留真实 DPAPI/替换函数，Apple 使用独立 Keychain service，Android 使用独立 Debug 应用 `cn.edu.ubaa.synthetic.materials`，在访问安全存储前核对设备报告的实际包名，Linux 原生材料转由专用隔离 Secret Service 入口执行。macOS 真实材料与凭据专项共 4 项通过，Linux 专用入口的实际原生运行和 Windows 原生运行仍待验。遗漏 await 的子写落地后失败回归另确认：根事务返回 uncertain，子 Future 独立报告异常，B 保留且后续访问阻断，未改写异常吞并规则。Android 锁定插件 10.0.0 仍使用固定配置、包装 key 和按应用包名生成的 Keystore alias，因此仅更换 preferences 名称不足以隔离。实际旧辅助的合成反例触发 3 次插件调用并写入固定配置标记，修复后的 7 项聚焦用例通过，独立 Debug APK 的实际包名与 debuggable 校验通过。设备清单为空，私有 AVD 创建未能识别已安装镜像，Android 原生正向读写尚待执行。完整相关分段验收与本地主题提交已完成，P2 候选等待监督最终复核。

### 同账号展示连续性与资料缓存

2026-11-10，冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 与 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本轮读取旧版 `api/auth/AuthApi.kt`、`model/dto/UserInfo.kt`、`api/local/LocalConnectionAuth.kt` 及 `commonTest/kotlin/cn/edu/ubaa/api/LocalAuthSessionStoreTest.kt`，并读取 buaa-api `api/user/{mod,auth,opt}.rs`、`request.rs` 与 `store/cred.rs`。

| 操作 | 引导与 service、重定向 | Cookie 与身份范围 | 方法与参数、头与编码、加密 | DTO 与解析 | 缓存、并发与重试 | 错误、退出与产品语义 |
|---|---|---|---|---|---|---|
| 用户资料读取与缓存 | 旧版 UC 激活后读取 `https://uc.buaa.edu.cn/api/uc/userinfo`，保留“用户资料”九列矩阵的既有引导、最终地址与重定向规则。buaa-api 只有 UC status 与激活接口，没有等价 userinfo 操作，其资料协议列不适用。 | 沿当前 Core 的 SSO 验票、响应身份核对及路线会话隔离。展示缓存不提供认证身份或写资格。 | 旧版 GET，无查询参数、请求正文或额外加密；当前请求、头及编码保持。buaa-api 不适用。 | 旧版 nullable String 的 username/name/schoolid/phone/email 与已有 Bridge 投影一致。只缓存这五个展示字段；手机、邮箱保留上游返回值，不推测被遮盖部分。证件号码、证件类型与原始响应不进入新增载荷。 | 在现有 AES-GCM 账号缓存中新增 DisplayProfile 标签，SQLite schema v8 不变；旧 MaskedProfile 可读，新在线成功结果保存展示投影。复用请求票据、成功时间、调度与重试。旧版和示例均无等价加密离线投影，持久化策略为本产品决定。 | 保留既有身份冲突、退出与迟到结果处理。普通读取失败保留上次内容。首次升级的旧遮罩资料在成功在线刷新后更新为展示资料。 |

同账号分页恢复沿已有查询重新读取已展示的页数，整批成功后替换列表。逐操作复用下表所链接的九列协议，CAS/引导、重定向、Cookie/令牌范围、方法与参数、请求头与编码、加密、DTO 和错误映射均保持；变化只在 UI 的只读查询顺序与展示缓存。旧内容在恢复期间撤销动作资格，失败或页码不前进时保留旧列表并等待手动重试。

| 操作 | 本次核对的冻结实现 | 现有完整协议对照 |
|---|---|---|
| 博雅课程列表 | 旧版 `LocalBykcApi.getCourses/queryStudentSemesterCourseByPage` 与 buaa-api `boya/opt.rs::query_courses` 均使用 `pageNumber/pageSize`；筛选、加密及返回映射沿当前 Core。 | [博雅课程只读查询](bykc.md#博雅课程只读查询) |
| 场馆订单 | 旧版 `LocalCgyyApi.getMyOrders/getMineOrders` 使用 GET `/api/orders/mine` 和 page/size，保留零基请求与 UI 一基页码的既有转换。buaa-api 无同等模块，协议列不适用。 | [场馆预约只读查询](cgyy.md#场馆预约只读查询) |
| 图书馆预约 | 旧版 `LocalLibBookApi.getBookings` 使用 `member/seat`，正文 type/page/limit，保留 current_page/per_page/total 解析。buaa-api 无同等模块，协议列不适用。 | [图书馆座位只读查询](libbook.md#图书馆座位只读查询) |
| 阳光打卡记录 | 旧版 `LocalYgdkApi.getRecords/fetchRecords` 使用 page/limit/classify_id/user_id 和既有表单入口，保留分页与 hasMore 计算。buaa-api 无同等模块，协议列不适用。 | [阳光打卡只读查询](ygdk.md#阳光打卡只读查询) |

其余调整改变已取得资料、页面状态和本地偏好的持有方式，不增加学校接口、参数或自动写入。

## 专项记录

### 2026-11-01 H1-b1：派生读取与登录身份撤销

已用 `just refs` 核对当前两个固定来源。旧版路径前缀为 `examples/ubaa_old/shared/src/`，提交 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；示例路径前缀为 `examples/buaa-api/src/`，提交 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。

旧版读取 `commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt` 的会话校验、资料查询、登录成功及退出，`api/auth/AuthApi.kt`、`model/dto/UserInfo.kt` 和 `commonTest/kotlin/cn/edu/ubaa/api/LocalAuthSessionStoreTest.kt`。示例读取 `api/user/{auth,opt,mod}.rs`、`request.rs`、`store/cred.rs`，其用户接口返回原始文本、各 API 组共享上下文与 Cookie。逐操作结论如下，所有请求协议均继续使用现有 Core 实现。

| 操作 | CAS/service、重定向与最终 URL | Cookie/Session/Token | 方法与精确参数 | 请求头与编码 | 加密/签名 | DTO 与解析 | 缓存/并发/重试 | 错误/退出与产品语义 |
|---|---|---|---|---|---|---|---|---|
| 校验所需路线与正常活动时间刷新 | 旧版直接 GET UC `/api/uc/status`，无 service；示例加 `selfTimestamp`，激活使用 UC `/api/login?target=…`。沿用现有 Core URL 与最终地址分类，不增加引导 | 旧版按 Direct/WebVPN 隔离 Cookie 与会话；示例共享上下文。Core 双槽 CAS 保持 | 旧 GET 无参数；示例 GET 时间戳参数。沿用当前无参数 GET | 旧 Accept JSON 与 XHR；示例默认 UA。保持 Core 既有头，无新正文 | 无新增 | 旧 `code=0`、`data.schoolid/username/name`；示例原始文本。保持 Core 白名单解析 | 旧校验成功保存活动时间，5xx 保留会话；示例刷新凭据过期时间。正常刷新不撤销能力，不增加重试 | 仅沿当前已分类 `AuthenticationRequired` 清理路径传播撤销，503 保持临时错误 |
| 显式登录成功后签发身份、退出后撤销 | 沿现有 SSO/UC 激活与校验；旧退出 GET SSO `/logout`。本次不改 URL/service 或跳转 | 保留路线隔离、双槽所有权与本机身份校验；成功登录建立新认证代次 | 沿现有登录表单与退出 GET，无新增参数 | 沿现有表单编码、请求头 | 沿既有 SSO/WebVPN，无新增常量 | 沿当前一致 `school_id` 身份能力规则；旧 DTO 和示例没有该不可伪造能力 | 成功登录更新认证代次；退出撤销旧代次，不恢复旧票据 | 两源均无 UBAA2 身份能力，能力签发/验证本地规则不适用协议类比；退出仍走既有清理 |
| 派生读取同代失效传播、旧派生迟到、普通句柄释放 | 两源没有等价的派生身份能力协议，不适用，无 HTTP 新增 | 仅同一认证代次共享内存撤销标记；旧代次与新登录分离，不写持久会话 | 不适用，本机检查 | 不适用 | 不适用 | 不适用，不添加上游字段 | 并行/嵌套派生共享认证归属；业务状态保留既有隔离，迟到清理检查原功能代次，释放句柄不等于退出 | 同代明确失效阻断父已取/未取能力；不扩大网络错误语义。共享账号索引和跨进程代次留 H1-b2/b3 |

当前基线 `64840201` 的新 Mock 反例与修复验证保存在实施检出私有 `.ubaa_local/command_mode_h1b_identity/`。固定 Direct/WebVPN、`NeverProbe`、合成身份和 Mock HTTP，学校请求与真实材料访问均为零。旧主仓库实验只作四个 Core 候选的审查输入，未整体迁入旧 CLI 补丁。

条件清理并发补充：再次核对旧版 `LocalConnectionAuth.kt` 的会话失效分类与 `buaa-api` 的 `api/user/{auth,opt}.rs`、`store/cred.rs`，两者均没有 Core 只读组的父功能代次与条件清理协议，因此此本机同步操作不适用上游协议类比，表内 HTTP 各列保持。受支持反例仅重叠派生读取：A 观察 Direct 代次 G 后暂停，B 清理到 G+1，C 经公开 fork 捕获 (G+1, W)，A 继续清理。原候选实际把 Direct 推进到 G+2，使 C 的 WebVPN 读取在双路线所有权检查中失败并误清 WebVPN。修复让代次读取、条件比较、推进与全部业务清理共用路线生命周期锁，普通清理遵守相同规则。父认证及学校写入与子请求互斥的公开约定保持。

### CLI 独立日程账号登记（2026-11-01）

冻结引用：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`，buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本次保留学校请求协议，仅在显式登录完成后增加 Core 身份能力及 CLI 本机登记。

| 操作与比较项 | 冻结旧版 | 固定 buaa-api | 本次处理 |
|---|---|---|---|
| 显式认证：CAS/service、跳转与最终 URL | `LocalConnectionAuth.kt` 的 login/prepareLogin、activateUserCenter、validateLocalConnectionSession；`AuthApi.kt` 接口及 `LocalAuthServiceBackendTest.kt` 的 UC Cookie/身份回归；SSO login → UC activation → status | `src/api/sso/auth.rs` 与 `src/api/user/auth.rs`；SSO、WebVPN 专用 service、UC activation | 沿用现有 Core URL、嵌套编码、白名单、TLS 与跳转上限，不增加认证请求 |
| 方法、精确参数、请求头、编码与加密 | `LocalCasParser.buildCasLoginParameters` 使用页面隐藏字段、用户名密码、execution，表单编码；status 的 Accept/X-Requested-With | SSO POST 表单 username/password/submit/type/execution/_eventId，UC GET 带 selfTimestamp | 现有请求构建、加密/签名常量均不变，本地登记无学校参数或密码学协议 |
| Cookie/Session/Token 作用域、缓存/并发/重试 | `LocalAuthSessionStoreTest.kt` 证明路线隔离；本地会话记录认证及活动时间 | `src/store/cred.rs` 为 SSO/VPN 分开有效期，`context.rs` 共享 Cookie/凭据，`request.rs` 使用 reqwest Cookie provider 和默认重定向 | 保留 Core 双槽 revision/CAS、Cookie 路线与重试语义。CLI 外层配置作用域锁串行化登记、退出与本地日程操作 |
| DTO 与身份字段 | `model/dto/UserInfo.kt`：code 为 Int、data 可空，身份字段可空字符串；status `code=0` 且 data 非空，schoolid 优先、username 后备；姓名仅展示 | `src/api/user/opt.rs` 返回 status 原始字符串，没有 typed 已核实能力 | 在 Core 登录内部逐成功路线核对非空 schoolid，同一显式输入须与 schoolid 或 username 匹配。字段缺失或路线身份不一致时不签发登记能力。首个 profile 仍只供既有认证输出 |
| 状态查询 | validateLocalConnectionSession 发起 UC status | get_state 发起 UC status | auth_status 保持联网，不能产生本机登记能力，本机命令不调用它 |
| 退出、错误与产品语义 | logout 请求 SSO 并清本地；无有效 status 时拒绝认证 | SSO 错误与独立凭据有效期 | 既有远程退出保留。CLI 先在同一锁内撤销本机 active，再执行原退出。登记失败与认证成功分开报告 |
| 独立安全索引、随机别名、代次、学校缓存读取 | 不适用：没有同等日程 CLI 协议 | 不适用：没有同等日程 CLI 协议 | 新增宿主本地机制，只消费 Core 已核实能力及现有 AgendaStore/OfflineCache facade，不类比新增学校 URL/字段。只读缓存仍 schema7，日程仍 schema2 |

来源没有跨宿主离线身份票据。CLI 索引保存于独立平台安全材料命名空间，与规范化 config-dir 绑定；普通 profile、JSON、用户名与旧会话均不能建立登记。真实 Direct/WebVPN 认证及读取在本会话未获授权，保留未运行状态，确定性验证使用合成账号和 Mock transport。


#### CLI-a 审查修复的实施前对照（2026-11-01）

本轮重读上述固定来源的 `LocalConnectionAuth.kt` 中 validateLocalConnectionSession、authStatus、logout 与 `UserInfo.kt`，以及 buaa-api 的 `api/user/auth.rs`、`api/user/opt.rs`。旧版明确区分无效认证与 5xx 临时错误，活动时间刷新保留原 authenticatedAt；buaa-api 沿 UC status 和既有 Cookie/凭据工作，不提供本机身份能力。两者均无 CLI 日程材料接口，平台材料、原生 Keychain 和身份票据绑定对此记为不适用。

| 操作 | CAS/service、重定向、最终 URL、Cookie/Session/Token | 方法、参数、头、编码、加密/签名 | DTO、缓存、并发、重试、错误与产品语义 |
|---|---|---|---|
| 交互式准备 | 沿既有双路线认证，旧来源没有离线能力 | 完全复用既有请求，不新增学校参数或常量 | 新交互意图立即撤销旧票据，保留当前句柄；成功、失败、验证码状态均适用 |
| 所需路线恢复与读取收尾 | 沿既有 UC 失效判断和清槽行为 | status/userinfo 请求与解析字段不变 | 票据绑定双路线认证代次，任何依赖会话清理后失效；同身份正常刷新与临时错误保留原行为 |
| 不支持日程 provider 的原认证 | 普通聚合/诊断登录和退出继续走既有 Core | 请求、重试与错误不变 | 只允许无日程登记痕迹的作用域继续，登记独立报告不可用；已有或异常材料继续失败关闭 |
| Keychain 索引写读 | 两冻结来源不适用，无学校网络 | 无学校请求或加密变更 | 保留原 service、scope、alias、CacheKey 与索引格式，替换交互命令解析接口；完整字节写读、容量预检与中断栅栏继续生效 |

### macOS 系统凭据存储的双来源核对

日期：2026-09-15。此记录先于生产代码修改；`just refs` 已核验冻结旧版
`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 与示例
`efb7976bf513f38364b88aeb83d704586cff9b2a`。

#### 来源与范围

- 旧版 UI：`composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/LoginScreen.kt`
  与同目录 `AuthViewModel.kt`。记住密码恢复用户名和密码；开启自动登录会开启记住密码，
  取消记住密码会关闭自动登录；只有业务认证成功后才保存选项与凭据。
- 旧版本地实现：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/storage/CredentialStore.kt`。
  `Settings` 分别保存两个字符串和两个布尔值；`clear()` 只清除自身四键。
  `AuthViewModel.logout()` 负责认证/表单复位，不等同于此存储的 `clear()`；本次不改变当前
  App 区分退出与清除本机账号的生命周期。
- 旧版测试：`composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/AuthViewModelTest.kt`
  验证表单与认证状态数据；`AuthViewModelInitializeAppTest.kt` 验证初始化、持久会话和
  上游超时不重登，并在前后清除旧版凭据。它们不构成 Keychain、原子保存或安全存储失败证明。
- 示例：`src/store/cred.rs` 的 `CredentialStore` 用 `Option<String>` 保存用户名/密码，
  `from_file/to_file` 使用普通 JSON 文件；`src/context.rs` 以 `AtomicCell` 持有凭据，
  `set_account/get_cred/load_auth/save_auth` 访问它。没有当前的记住/自动开关、Keychain
  或清除单个安全条目的接口；不可类比补出不存在的协议。
- 当前边界：`packages/ubaa_platform/lib/src/credentials.dart` 已定义
  `credentials.capability/read/write/clear`，默认命名空间为
  `com.buaa.ubaa.credentials.v1`。此前 macOS `PhotoChannel` 仅处理照片与权限，能力探测
  因方法缺失安全返回 `false`。本次只补平台实现，不改 AppController、Bridge 或上游协议。

#### 逐操作九列

| 操作 | CAS/bootstrap 与 service | 重定向与最终 URL | Cookie/session 范围 | HTTP 方法与精确参数 | 请求头与正文编码 | 加密/签名常量 | DTO 与解析字段/类型 | 缓存与并发 | 错误与退出语义 |
|---|---|---|---|---|---|---|---|---|---|
| 保存/更新 | 两来源此本地操作无 URL；沿既有认证合同，不新增 service | 本地存储无跳转 | 旧版仅自身 Settings；示例凭据与 Cookie 分容器；当前 Keychain 不接触 Core session | 不发 HTTP；旧版 username/password 加独立开关；当前方法参数为 namespace、username、password、autoLogin | 无请求头；旧版 Settings、示例 JSON；当前三字段二进制 plist 仅交给 Keychain | 两来源无系统 Keychain 协议；使用 macOS 系统密钥链，不复制明文存储或添加业务加密常量 | username/password 必须为 String；用户名 trim 后非空、密码非空；autoLogin 必须为真正 Bool，数字 0/1 不代替 Bool | 旧版依序写四键，示例 AtomicCell 后整文件序列化；当前原生串行队列，精确更新同一条目，不存在才新增，重复新增竞争只重试一次更新；无明文缓存 | 缺字段/错类型/无效值返回稳定输入错误；系统拒绝返回不可用或存储失败；真实写入成功才回复成功，不影响既有业务认证语义 |
| 读取 | 两来源无 URL；不调用登录 | 无跳转 | 不读取或导入 Cookie、Token、旧 Settings、示例文件或 Core 会话 | 不发 HTTP；只接受明确 namespace 字符串，不回退默认值 | 无请求头；从 Keychain 的数据字段解码二进制 plist | 由 macOS Keychain 解密；不自造密钥/算法 | 无记录为 null；有记录只返回 username:String、password:String、autoLogin:Bool；损坏/不匹配拒绝 | 旧版按 remember 恢复表单，示例访问 AtomicCell；当前每次精确查询，不保留跨调用明文缓存；新适配器可读取同一条目 | 无记录不是错误；损坏数据为稳定存储失败；锁定/拒绝为稳定不可用；不自动清除、重登或记录正文 |
| 清除 | 两来源无 URL；不追加注销 HTTP | 无跳转 | 旧版只移除四键；示例无对应安全条目删除接口；当前只删除 namespace 对应的本应用条目，不清系统 Keychain/其他账号 | 不发 HTTP；只接受明确 namespace 字符串 | 不涉及正文编码 | 使用系统 SecItemDelete，不操作密钥材料 | 无返回凭据；缺失/无效 namespace 拒绝，不能成为宽查询 | 串行、幂等；存在时删除精确条目，无记录视为已清除；无内存影子记录 | errSecItemNotFound 为成功；其他系统失败归约并返回，不能虚报删除完成；App 退出/清除失败恢复由独立任务处理 |

实际业务认证九列继续以 [主对照](../README.md) 为准。UI 的联动与失败恢复另见
[登录选项对照](auth-session.md#登录选项与凭据失败恢复的双来源核对)，本任务不修改这些状态机行为。

#### 系统实现决策与验证边界

采用 macOS 系统 Keychain 的 generic-password 条目；固定应用服务
`cn.edu.buaa.ubaa.credentials` 与调用者传入的 namespace 作为 account，所有查询、更新、
新增、删除均精确带上两者及 `synchronizable=false`。不启用 iCloud 同步，不查询整个密钥链，
不将真实用户名作为可检索属性，不提供文件回退。macOS 登录 Keychain 采用系统现有保护与
应用访问控制；操作禁止弹出认证界面，受锁定/访问拒绝影响时明确失败。能力探测仅说明原生
实现已注册，不读取任何已保存凭据，也不保证某次系统操作必然获准。

统一 `PlatformChannel` 拥有 `cn.edu.buaa.ubaa/platform`，组合照片处理器和凭据处理器；
不重复注册同名 handler。Keychain 接线不依赖照片的 macOS 11 最低版本，保留项目 macOS 10.15
构建目标；照片仍仅在 macOS 11+ 注册。原生失败类别固定为 `credentials_invalid_input`、
`credentials_unavailable`、`credentials_storage_failure`，不返回 OSStatus、原始错误或秘密。
上层 `PlatformCredentialVault` 仍使用现有稳定领域错误归约。

先运行原生 integration 测试，预期旧实现的 `probe()` 为 false；再最小实现并重跑同一测试。
真实测试只使用本次唯一的 `com.buaa.ubaa.credentials.test.<unique>` 与合成值，所有写入均
由 finally 精确清除；覆盖新适配器读取、更新、无记录、输入拒绝及照片探测。系统错误和精确
寻址另由注入 Security 调用的原生测试验证。真实 native、确定性测试、锁屏状态与真实 App
业务验收分开记录，不能互相替代。

#### 独立审查修复轮 1：legacy 交互策略与版本证据

审查基点 `708a6250f08f7c1d6072427fd136b19354e37e88`。本轮先观察两个行为 RED：查询没有明确
限定 legacy 后端；照片测试对 macOS 10.15 仍要求 true。本节在修复生产包装器前补充决策。

复核本机 SDK `LAContext.h` 的 `interactionNotAllowed` 与 `SecItem.h` 的
`kSecUseNoAuthenticationUI` 说明后，确认先前 context 标记不能禁止 legacy Keychain 的 UI。
同时读取 Apple Security 固定提交 `db15acbe6a7f257a859ad9a3bb86097bfe0679d9` 的
[SecItemCategorizeQuery](https://github.com/apple-oss-distributions/Security/blob/db15acbe6a7f257a859ad9a3bb86097bfe0679d9/OSX/libsecurity_keychain/lib/SecItem.cpp#L4095)、
[SecItemAdd](https://github.com/apple-oss-distributions/Security/blob/db15acbe6a7f257a859ad9a3bb86097bfe0679d9/OSX/libsecurity_keychain/lib/SecItem.cpp#L5023)
和 [SecKeychain 交互接口](https://github.com/apple-oss-distributions/Security/blob/db15acbe6a7f257a859ad9a3bb86097bfe0679d9/OSX/libsecurity_keychain/lib/SecKeychain.cpp#L867)：
显式 false 会只选择 legacy；未指定时新增优先 legacy；get/set 操作的是进程内共享交互策略。

保留现有登录 Keychain、私有服务、namespace 与 Debug 签名条件，显式设置
`kSecUseDataProtectionKeychain=false`。不引入 Data Protection Keychain 或新 entitlement。
使用 SDK 已 deprecated 的 `SecKeychainGetUserInteractionAllowed` /
`SecKeychainSetUserInteractionAllowed` 是该 legacy 兼容决策的局部依赖，不扩大到业务层。

系统 API 包装器在所有实例共享的锁内取得原值、临时关闭交互、执行单次 SecItem 操作并恢复。
读取策略失败时不执行存储；关闭失败时也尝试恢复已知原值。原值 true/false 均原样保留。
恢复失败会报告稳定错误，并进行一次有界恢复补偿；若系统仍拒绝恢复，保留仅含策略原值的
待恢复状态，后续调用必须先恢复，不能把暂时的 false 当作新基线或继续存储。该异常不能宣称
系统策略已恢复，也不通过无限等待或永久关闭交互掩盖失败。

照片测试从 `/usr/bin/sw_vers -productVersion` 独立取得版本，并以
`SYSTEM_VERSION_COMPAT=0` 避免兼容版本投影。10.15 要求照片不可用，11+ 要求可用；凭据测试
不因此跳过。畸形或缺失版本明确失败，不用待测 capability 反向决定期望。不进行真实锁定或
授权弹窗实验；异常恢复顺序由注入系统 API 的原生测试证明，正常路径仍以唯一合成 namespace
及 finally 清理做真实 native 验证。
