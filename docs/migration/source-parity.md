# 协议来源对照矩阵

更新日期：2026-09-01

本文件逐操作审计行为。`旧版` 指冻结的 `ubaa_old/` 提交
`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`；`示例` 指固定的
`examples/buaa-api/` 提交 `efb7976bf513f38364b88aeb83d704586cff9b2a`。每个单元格均记录两份
来源与 UBAA 2 决策。标记为不等价的来源不得通过类比提供 URL、字段、加密或错误语义。只有在
决策日志记录脱敏观察后，实时证据才可以取代冻结协议事实。

历史记录（2026-08-29）：当时的 `verify-live` 曾按独立 CLI 子操作执行，并有一笔单独授权的
Cgyy Direct 写探针。本记录仅保留来源证据，不属于当前执行合同；当前唯一真实网络入口是
`core-live`，只验证 Direct 和 WebVPN 的读操作，任何写操作均只做 Mock/Fixture 验证。

Bykc 已选课程解析修复：冻结 `LocalBykcApi` 的 `queryChosenCourse` 返回
`data.courseList` 对象包装，而不是直接数组。Rust 现同时接受该冻结包装和既有数组
兼容形状；`features/bykc.rs` 单元测试先复现旧实现失败，再验证 `id`、`courseInfo.id`
和列表长度。2026-08-29 Direct、WebVPN、auto 的 Bykc 逐项复测均退出 0。

生产代码变更前，每个认证或只读操作都必须填写下方九列。

## Flutter bridge 产品投影

P1 的 `docs/contracts/flutter-bridge.md` 只把本文件已审计的 facade 方法映射为 typed FRB
DTO，不修改任何 URL、service、跳转、Cookie/Session、HTTP 参数、Header、正文、加密、
缓存、并发、重试或 Core 错误语义。逐操作仍使用下列已有九列证据：

| bridge 领域 | 本文件权威段落 | Flutter 仅新增的产品语义 |
|---|---|---|
| 认证、用户、路线 | 网关探测；双路线加载/保存/退出；准备/登录；用户资料；CLI 与配置 | opaque client、资料白名单、typed error、策略切换后重开 |
| 课表、考试、成绩、空教室 | 未改变的课表/考试证据；未改变的成绩证据；空教室会话同步/查询 | typed DTO 与 `RouteDecision`；考试“已安排/未安排”仅投影同一 `examArrangement(term)` 信封的冻结两列表；成绩“已出/待出”仅按冻结 `score` 字段非空性本地投影；空教室楼层按 `floorid`/分组名、节次按冻结逗号分隔 `kxsds` 令牌本地精确过滤，均不新增请求 |
| SPOC、Judge | SPOC 认证/列表/详情；Judge 列表/详情/批量与缓存 | 不生成诊断入口，只生成列表/详情 DTO；Judge 列表的“包含已过期”仅传递冻结 `includeExpired` 本地截止时间筛选参数 |
| Signin、Ygdk、LibBook | 课堂签到今日查询；阳光打卡只读查询；图书馆座位只读查询；直接写操作表 | typed prepare、一次性 intent、commit 后读取核对 |
| Bykc、Cgyy、Evaluation | 博雅课程只读查询；场馆预约只读查询；直接写操作表 | Cgyy 用途来源明示；待评由 `is_evaluated=false` 派生；原始评教 payload 不暴露 |

`set_default_route_policy` 是本地配置/facade 能力，不是上游协议：它只能原子保存已存在的
`RoutePolicy`，清空 App 不开放的 feature override，使 bridge intent 失效并从同一应用私有
目录重开 `UbaaClient`；不得触发登录、业务请求、Cookie 复制或透明路线回退。每项写 intent
只保存已审计的 typed facade 请求，commit 不接收任意 JSON。若实现需要改变上述任一协议列，
必须先停止并回到对应操作的来源对照与失败测试，不得以 bridge 需要为由推断字段。

冻结 WebVPN 编解码使用网关 `d.buaa.edu.cn`、密钥/初始向量文本
`wrdvpnisthebest!`、无填充 AES-128-CFB，以及 `scheme[-port]/encrypted-host/path` 布局，UBAA 2
与这些线路值一致。为保持边界行为，空查询和片段分隔符按冻结 Kotlin 实现省略；Rust URL/运行时
路径表示保留显式根斜杠，因此路线请求和最终 URL 语义不变。Cookie 匹配仍针对网关 URL。两项
选择均有脱敏连接测试覆盖，本对照不会新增重定向主机，当前白名单仍以实时观察为依据。

## 网关探测

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**不适用，没有校园探测。**示例：**`utils/net.rs` 目标为 `gw.buaa.edu.cn:80`。**决策：**严格使用该主机和端口，不使用 IP 段。 | **旧版/示例：**不适用，此操作不是 HTTP。**决策：**不处理重定向或最终 URL。 | **旧版/示例：**不使用 Cookie 或凭据。**决策：**仅保留进程内探测状态。 | **示例：**先执行 `ToSocketAddrs`，再循环 `TcpStream::connect_timeout` 直到成功。**决策：**解析和全部地址尝试共用 500 毫秒总期限。 | **旧版/示例：**无请求头或正文。**决策：**只建立 TCP 连接，不发送 HTTP/TLS 数据。 | **旧版/示例：**不适用。**决策：**不使用加密或签名。 | **示例：**返回校园布尔结果。**决策：**任一连接成功为 `Campus`；普通解析、无地址、连接失败或超时为 `OffCampus`；仅内部/注入探测失败为 `Unknown`。 | **示例：**无缓存且每地址 500 毫秒。**决策：**产品合同收窄为一次总预算，并增加可注入时钟/探测器和进程内 60 秒缓存。 | **示例：**普通失败均返回 false。**决策：**`OffCampus -> WebVPN`，`Unknown ->` 功能的 `unknown_default`；探测本身不产生 CLI 失败。

2026-08-24 的确定性实现证据：`route_policy` 覆盖固定 500ms 预算、三种网络状态、显式策略不探测、
缓存过期和并发缺失时的单飞行为；`facade` 覆盖 facade 所有缓存、默认与功能策略、成功诊断及
缺少会话时零请求。CLI 二进制边界测试禁止 `main.rs` 持有配置、探测或解析器。这些测试不证明
实时校园网络可达性或任何业务端点结果。

## 双路线加载/保存/退出

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**远端注销为 `https://sso.buaa.edu.cn/logout`，持久化无 URL。**示例：**没有等价的双路线注销。**决策：**各路线使用转换后的 SSO 注销地址，存储操作仅在本地执行。 | **旧版：**先远端注销再清本地，不校验最终 URL。**示例：**不适用。**决策：**远端请求只做尽力尝试，不能单独授权删除持久化数据。 | **旧版：**`ModeScopedSessionStore` 按模式隔离认证/Cookie，但切换或重置会清理全部范围。**示例：**共享 `cookies.json` 与 `cred.json`，不是双槽位。**决策：**一个双路线快照，包含独立路线槽位和路线业务状态。 | **旧版：**settings get/put/remove，无 CAS。**示例：**分别截断写文件。**决策：**在同一锁内加载快照和修订；路线保存、聚合清理各执行一次完整快照 CAS。 | **旧版/示例：**JSON 持久化，本地操作无 HTTP 正文。**决策：**schema-v2 `session.json`，仅支持旧单路线读取；使用唯一原子临时文件和仅所有者权限。 | **旧版/示例：**不适用。**决策：**不为本地持久化臆造加密。 | **旧版：**用户名、用户资料、时间戳和 Cookie 记录。**示例：**Cookie 及凭据/令牌过期时间。**决策：**只持久化路线、过滤后的 Cookie 和时间戳，绝不保存用户名、密码、execution、challenge 或业务令牌。 | **旧版：**各存储有互斥锁但没有跨文件事务，重置会清缓存。**示例：**进程内原子单元，没有文件锁/CAS。**决策：**一个协调器拥有双路线快照和修订；冲突后不重新加载或采用外部修订；本地失效/注销时清理全部路线业务状态。 | **旧版：**远端错误仍清本地状态。**示例：**普通 I/O/解析错误。**决策：**陈旧 CAS 返回可重试的 `internal_error`，只清当前进程并保留更新后的两个槽位；聚合注销成功时只推进一次修订。

## 准备/登录（UBAA2 不支持交互验证码）

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**GET/POST `https://sso.buaa.edu.cn/login`，随后访问 `https://uc.buaa.edu.cn/api/login?target=...` 激活用户中心；冻结流程还可能出现 `config.captcha` 并读取 `/captcha?captchaId=...`。**示例：**只有 SSO `/login`，无等价验证码协议。**决策：**Direct 与 WebVPN 各自保留普通登录和激活顺序，明确不实现可选交互验证分支。 | **旧版：**手动解析绝对、协议相对、根相对和路径相对跳转，密码风险页最多继续一次；用户中心状态证明激活完成。**示例：**reqwest 自动跟随跳转，`verify_url` 为用户中心或网关根。**决策：**所有跳转锁定路线，并要求主机和最终用户中心地址通过白名单校验。 | **旧版：**按模式保存 Cookie，execution 仅是内存请求状态。**示例：**共享上下文 Cookie/凭据存储。**决策：**路线 Cookie jar 和临时 execution 独立保存，绝不持久化 execution 或交互验证材料。 | **旧版：**表单复制隐藏字段并增加 `username`、`password`、`execution`、`_eventId=submit`、`submit=登录`、`type=username_password`；旧验证码分支还会发送 `captcha`/`captchaResponse`。**示例：**同样的普通基础字段和风险表单。**决策：**只发送有证据支持的普通表单；含 `config.captcha` 的页面在取图或提交凭据前返回 `upstream_changed`。 | **旧版/示例：**表单 URL 编码。**决策：**保留隐藏字段语义和编码，不把表单值写入日志或错误。 | **旧版/示例：**无额外登录加密。**决策：**不增加；WebVPN 主机编解码属于独立连接证据。 | **旧版：**execution、`config.captcha {type,id}`、提示/错误文本和 `UserInfoResponse code/data`。**示例：**只说明 execution 和风险页标记，不支持验证码。**决策：**只公开稳定资料/错误 DTO，不公开挑战 ID、图片状态或验证字节。 | **旧版：**各路线后端通过自己的 Cookie 存储保留准备状态。**示例：**无验证码生成。**决策：**各路线只保留自己的 execution，不存在跨路线或跨进程验证状态。 | **旧版：**缺少验证码可能返回 captcha-required，错误凭据、风险页或激活失败有用户错误。**示例：**缺少 execution/服务器和登录失败错误。**决策：**任何交互验证标记都返回 `upstream_changed`，不重试或提示；普通认证、网络和解析错误保留稳定分类。

当前分类器还会拒绝额外的可见输入、`textarea`/`select`、冻结验证码字段名
`captcha`/`captchaResponse`，以及仅拒绝型 `config.*` 标记（`captcha`、`mfa`、`otp`、
`verification`、`verify` 或 `challenge`）。这是从冻结普通输入解析器导出的封闭世界安全边界，
可防止凭据被提交到未知验证界面，同时不声称这些新字段或标记属于协议。

## 用户资料

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**用户中心激活属于登录流程，查询地址为 `https://uc.buaa.edu.cn/api/uc/userinfo`。**示例：**`api/user` 只激活用户中心并返回状态，不是同一资料查询。**决策：**在 facade 解析的路线使用旧版资料地址。 | **旧版：**SSO/最终 HTML 表示会话过期。**示例：**用户中心激活会跟随跳转。**决策：**WebVPN 转换和跳转始终锁定路线，不跨路线重试。 | **旧版：**当前模式的 Cookie/认证会话；`getUserInfo` 本身缺少所需本地预检。**示例：**共享上下文。**决策：**只使用所选路线槽位；通过校验/持久化登录得到的 `authenticated_at` 才是本地凭据，准备页 Cookie 不能授权业务请求。 | **旧版：**GET `/api/uc/userinfo`，无参数。**示例：**不等价的 GET `/api/uc/status?selfTimestamp=...`。**决策：**不能用状态接口替代资料接口。 | **旧版：**默认 GET。**示例：**默认 GET。**决策：**不臆造正文或请求头。 | **旧版/示例：**不适用。 | **旧版：**`code` 和可选 `data`；资料字段为 `idCardType`、`idCardTypeName`、`phone`、`schoolid`、`name`、`idCardNumber`、`email`、`username`。**示例：**返回原始状态文本，不等价。**决策：**稳定的可选资料 DTO，展示时遮罩敏感字段。 | **旧版/示例：**无资料缓存。**决策：**聚合 facade 负责路线解析和预检；没有有效路线槽位（包括准备后、登录前）时零 HTTP 请求。 | **旧版：**401/SSO HTML 清理当前本地会话；非零/缺少 data 为 `user_info_failed`。**决策：**缺少槽位返回 `authentication_required`；明确失效只清所选路线；瞬时 5xx/超时保留两条路线。

## 空教室会话同步

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**`LocalClassroomApi.kt::classroomSyncUrl` 中的精确 SSO 服务地址，包含编码的 `a_buaa/api/cas/index`、redirect、`from=wap`、`login_from=` 和 `noAutoRedirect=1`。**示例：**`api/class/*` 是 iClass 地址，不适用且不等价。**决策：**只使用旧版空教室引导。 | **旧版：**共享跟随跳转的客户端，任意 200..399 均标记同步成功。**示例：**不适用。**决策：**完整地址按路线转换；在实时证据改变前保留旧接受范围。 | **旧版：**所选模式的 Cookie jar，`sessionSynced` 属于单个后端。**示例：**`Sessionid` 是无关的 iClass 令牌。**决策：**每路线/客户端一份同步状态，绝不全局或跨路线共享。 | **旧版：**GET 精确服务地址。**示例：**不适用。 | **旧版：**精确的长 Android/WeCom `User-Agent`，无正文。**示例：**不适用。**决策：**保持旧版 UA。 | **旧版/示例：**不适用。 | **旧版：**只由 HTTP 状态驱动同步标志。**示例：**不适用。**决策：**不向宿主暴露响应 DTO。 | **旧版：**双重检查 `Mutex`，在清缓存/会话重置前每个后端只执行一次。**示例：**不适用。**决策：**复现每路线一次同步，并在失效、注销、重新登录时清理。 | **旧版：**异常由 `runCatching` 吞掉，查询继续并在后续分类认证/上游。**示例：**不适用。**决策：**保留尽力同步边界，不把同步成功单独报告为业务成功。

## 空教室查询

当前实现补充：`crates/ubaa-core/src/features/classroom.rs::parse_response` 与冻结
`LocalClassroomApi` 一致，仅要求完整 `e/m/d.list` 信封和教室字符串字段；`e` 的具体数值
不作为额外成功门控，而是原样保留在 `ClassroomQuery.code`。脱敏回归测试覆盖 `e=1`
的兼容解析，避免引入旧版不存在的非零状态码拒绝。

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**需要先同步教室，GET `https://app.buaa.edu.cn/buaafreeclass/wap/default/search1`。**示例：**iClass 查询不适用且不等价。**决策：**只使用旧版空教室地址。 | **旧版：**查询使用不跟随跳转的客户端，SSO Location/HTML 表示会话过期。**示例：**不适用。**决策：**两条路线都关闭本次请求的跳转。 | **旧版：**当前路线 Cookie jar 和本地认证预检。**示例：**不适用。**决策：**所选路线槽位及其同步状态。 | **旧版：**GET 查询 `xqid=<int>`、`floorid=""`、`date=yyyy-mm-dd`。**示例：**不适用。**决策：**保留精确参数。 | **旧版：**精确长 UA、`Accept: application/json, text/javascript, */*; q=0.01`、路线转换后的 Referer `https://app.buaa.edu.cn/site/classRoomQuery/index`、`X-Requested-With: XMLHttpRequest`，无正文。**示例：**不适用。 | **旧版/示例：**不适用。 | **旧版：**必需 `e:int`、`m:string`、`d` 和 `d.list: Map<String,List<ClassroomInfo>>`；教室要求字符串 `id`、`floorid`、`name`、`kxsds`。**示例：**不适用。**决策：**缺少 `d/list` 是解析错误，不是空成功；真实空 map 仍算成功。 | **旧版：**无结果缓存，同步互斥锁同上。**示例：**不适用。**决策：**保持一致。 | **旧版：**缺少认证、SSO/401 失效、非 200 上游或解析失败；日期校验由宿主 API 负责。**决策：**使用稳定的 `invalid_input`、`authentication_required`、上游和解析错误；除非矩阵明确允许，否则不回退。

2026-08-24 的确定性实现证据：解析测试拒绝缺失 `e/m/d/list` 任一必需层和非字符串教室字段，同时
保留真实空映射。传输测试断言冻结完整移动端 `User-Agent`、XHR/Accept 请求头、路线转换后的
Referer、每客户端一次且路线隔离的同步、尽力失败后的重试，以及一次不跟随重定向的业务请求。
原始 SSO Location、401 和登录 HTML 均返回 `authentication_required`，清理选定的持久化路线及
功能状态；成功替换会话会强制后续再次同步。状态级并发测试证明双重检查异步互斥锁只执行一次
同步。固定示例 Classroom API 不等价，未向本实现提供协议值。

## SPOC 认证

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**GET `https://spoc.buaa.edu.cn/spocnewht/cas`，再 POST `/spocnewht/sys/casLogin`。**示例：**只有 GET `/spocnewht/cas`，没有 `sys/casLogin`/角色设置，认证不完整且不等价。**决策：**旧版本地流程是唯一权威。 | **旧版：**最多手动跟随 8 次路线转换跳转，只从 `/spocnew/cas?token=...&refreshToken=...` 提取令牌；`sys/casLogin` 的原始 SSO 跳转表示认证过期。**示例：**客户端跟随跳转并读取第一个 `token` 查询项。**决策：**保留旧版上限，并在状态解析前识别不跟随传输返回的 SSO Location。 | **旧版：**路线 Cookie jar；按缓存客户端用户名保存内存令牌和角色码。**示例：**共享 Cookie 存储和 3 小时凭据令牌。**决策：**令牌、角色和登录锁只存在路线业务状态，并随会话清理。 | **旧版：**GET CAS；向 `sys/casLogin` POST JSON `{token}`。**示例：**没有等价角色 POST。 | **旧版：**JSON、`X-Requested-With: XMLHttpRequest`、`Token: Inco-<token>`，后续请求增加 `RoleCode`。**示例：**只有 `Token: Inco-<token>`。**决策：**保持旧版角色建立步骤。 | **旧版/示例：**CAS 登录本身无加密。 | **旧版：**URL 中的令牌/可选 refreshToken；`code/content` 角色字段 `jsdm`、`rolecode`、`jsdmList`；content 为空或找不到角色即认证失败。**示例：**只有令牌。**决策：**角色是必需项，不从示例推断字段。 | **旧版：**登录互斥锁、令牌/角色复用，业务认证失败后强制刷新一次。**示例：**凭据过期刷新。**决策：**每路线串行登录且恰好刷新/重试一次；可选课程/提交调用保留旧版 `runCatching` 边界。 | **旧版：**业务认证耗尽后调用 `resolveLocalBusinessAuthenticationFailure` 校验用户中心：只有明确 Invalid 才清选定主会话，Valid、瞬时或不确定结果保留会话并返回 `spoc_error`。**示例：**无等价主会话仲裁。**决策：**必需操作执行同样校验；只有 `authentication_required` 清所选路线，其它结果返回可重试 `upstream_unavailable` 且不清理。

## SPOC 列表

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**认证当前学期后 POST `/inco/ht/queryOne`；可选课程元数据 GET `/jxkj/queryKclb`；权威全局作业 POST `/inco/ht/queryListByPage`。**示例：**当前周/课程接口不同，作业列表是按课程 GET `/kczy/queryXsZyList`，协议不等价。**决策：**即使课程查询失败或为空，也使用旧版全局列表。 | **旧版：**路线转换且不跨路线跳转/重放。**示例：**普通同主机请求。**决策：**整个学期/列表序列锁定一条路线。 | **旧版：**同一令牌、RoleCode 和路线 Cookie；课程元数据失败可选。**示例：**共享令牌状态。**决策：**使用路线内 SPOC 状态。 | **旧版：**queryOne POST 加密 `param`；课程 GET 参数 `kcmc=""`、`xnxq`；列表 POST JSON `{param}`，明文顺序为 `pageSize=15`、`pageNum`、固定 `sqlid=1713252980496efac7d5d9985e81693116d3e8a52ebf2b`、`xnxq`、`kcid=""`、`yzwz=""`。**示例：**GET `flag=1`、`sflx=2`、`sskcid=<course>`，不等价。 | **旧版：**JSON、XHR、`Token`、`RoleCode`。**示例：**query 加 `Token`，无 RoleCode。**决策：**采用旧版精确编码/请求头。 | **旧版：**AES-128-CBC 零填充并 Base64，密钥 `inco12345678ocni`，IV `ocni12345678inco`；对齐明文不增加额外块，`LocalSpocSupportTest` 有固定向量。**示例：**虽确认常量，却总是追加 1-16 个零字节，对齐明文也追加整块。**决策：**使用冻结本地无额外块行为，覆盖对齐和未对齐向量；示例仅作补充。 | **旧版：**当前学期 `dqxq/mrxq`；分页整数 `total/pageNum/pageSize/pages`、布尔 `hasNextPage` 和列表，默认 `0/1/15/1`、false、空列表；作业必需字符串 `zyid/zymc`，可选字符串 `tjzt/zyjzsj/zykssj/sskcid/xnxq/mf/kcmc`；课程元数据可选。**示例：**不同的按课程 `Homework` 字段。**决策：**保留默认值和可选性，但已出现字段类型错误时拒绝。 | **旧版：**从第 1 页开始直到 `!hasNextPage`、达到上限或列表为空；路线客户端缓存，课程查询使用 `runCatching`。**示例：**调用方循环课程，无等价全局分页。**决策：**保留旧版分页和可选元数据；即使课程为空也必须发送全局列表请求。 | **旧版：**业务认证触发一次刷新；畸形 JSON 分支扫描原文，可能因出现 `token` 一词误判认证。**示例：**类型化 JSON 错误，无等价全局列表。**决策：**当前合同禁止重放解析/未知失败，畸形 JSON 始终为 `parse_error`；有证据的认证信封仍刷新一次；真实全局空页算成功。

## SPOC 安全诊断

| 引导/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**无诊断 API，始终执行上述当前学期/全局列表操作。**示例：**无等价全局列表诊断。**决策：**诊断不增加 URL 或请求。 | **旧版：**同一条路线锁定的 SPOC 流程。**示例：**列表协议不等价。**决策：**复用普通最终 URL 和原始 SSO 检查。 | **旧版：**同一条路线 Cookie/令牌/角色状态。**示例：**不等价。**决策：**不暴露凭据或会话状态。 | **旧版：**同样的 `kcid=""` 加密分页 POST，无诊断参数。**示例：**按课程 GET，不等价。**决策：**普通读取和诊断读取共用一次操作，不发送证据专用请求。 | **旧版：**同样的 JSON/XHR/Token/RoleCode 请求头和加密正文。**示例：**不等价。**决策：**不变。 | **旧版：**同一 AES-CBC 操作。**示例：**仅提供常量。**决策：**不变。 | **旧版：**无诊断 DTO。**示例：**不适用。**决策：**只返回 `globalPageCount` 和普通 `result`；计数只在权威全局页成功解析后递增，至少为 1 才能区分真实空页和跳过请求；不暴露原始分页、参数、令牌或新作业字段。 | **旧版：**普通路线状态和分页。**示例：**无等价。**决策：**复用同一序列和状态；诊断不增加缓存或并发行为。 | **旧版：**全局页认证/上游/解析错误仍失败。**示例：**不适用。**决策：**使用同一路线错误；计数只是证据元数据，不能单独建立实时成功。

## SPOC 详情

| 引导/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**激活和选课后 GET `assignment/index.jsp?assignID=<id>`。**示例：**不适用且不等价。**决策：**使用冻结列表发现的 ID。 | **旧版：**SSO 页面会重新激活并重试，路线保持不变。**示例：**不适用。**决策：**详情仍锁定所选路线。 | **旧版：**选课互斥锁和独立 worker Cookie。**示例：**不适用。**决策：**只使用同一路线/客户端状态。 | **旧版：**GET，使用列表发现的数字/字符串课程和作业 ID。**示例：**不适用。 | **旧版：**Judge 浏览器请求头，无正文。**示例：**不适用。 | **旧版/示例：**不适用。 | **旧版：**解析开始/截止时间、最高/本人分数、总数/提交数、题目表、每题分数/上限/状态、`PARTIAL`、提交数回退和纯文本。**示例：**不适用。**决策：**字段和状态语义都必需，固定空 `problems`/`myScore` 不是 parity。 | **旧版：**选课锁；详情缓存 2 分钟，按用户+路线+课程+作业分组。**示例：**不适用。**决策：**不设全局缓存，会话重置清理。 | **旧版：**缺少作业/课程为 not found，认证页会重激活，非 200/认证耗尽返回稳定错误；业务认证最终失败时先校验用户中心。**决策：**只在顶层详情执行一次仲裁，不在每个内部请求中执行；历史退出 0 在完整解析断言前不构成语义证据。

2026-08-24 的确定性 SPOC 实现证据：CAS 引导最多跟随八次不自动跳转且受主机白名单限制的
重定向，只接受 HTTPS `spoc.buaa.edu.cn` 主机精确 `/spocnew/cas` 路径中的令牌，并要求最终
表示与 Direct 或 WebVPN 路线一致；不会请求令牌落地页。原语和数组角色形态遵循冻结
`JsonPrimitive` 行为。凭据只在单一路线状态内序列化和缓存，`Debug` 已脱敏，状态生成号失效后
不能重新写入，每个业务调用至多刷新一次认证。必需学期/页面/详情操作第二次认证失败时会校验
主 UC 会话：明确失效只清理选定路线，有效或不可用 UC 保留主会话及兄弟槽位并返回非认证类
SPOC 可用性错误。即使传输不跟随重定向，解析到 SSO 的业务 Location 也触发同一有界刷新。
`sys/casLogin` 的原始 SSO Location、空 content 和缺角色进入同一主会话仲裁。课程元数据即使
重试耗尽仍为可选。冻结客户端独立的“权限”认证标记与当前禁止无条件重试的合同冲突，UBAA 2
已在决策日志记录，不重放 code-403 权限信封。

列表传输测试会捕获第 1 页和第 2 页的真实 JSON POST 正文，只在测试进程内解密 Base64 AES-CBC
的 `param`，并断言包含空 `kcid`、`yzwz` 的完整有序明文；同时证明多个课程共用一条分页序列，
课程元数据为空或不可用时仍会继续翻页。解析测试覆盖整数分页字段、可选字符串 `xnxq`、必需
字符串详情字段 `zymc`、可选字符串 `sskcid`，以及包含 `token` 但不得触发隐藏重登录的畸形
JSON。详情测试保留上游 ID 校验、摘要回退、可选提交信息、纯文本解码和不暴露原始 HTML。
这些只是确定性协议结果，当前 Direct/WebVPN/auto 的实时证据另行记录。

## Judge 列表

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：** SSO `https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F`，随后访问 `judge.buaa.edu.cn/courselist.jsp?courseID=0`。**示例：** 不适用且不等价，固定提交中没有 Judge 模块。**决策：** 旧版是唯一冻结协议来源。 | **旧版：** 解析一次激活跳转后再做路线转换；SSO 页面最多触发 3 次重新激活。**示例：** 不适用。**决策：** 所有跳转和地址均锁定当前路线。 | **旧版：** 按用户/模式使用客户端；独立 worker 从非 Judge 父客户端复制 Cookie，并保持 Judge Cookie 本地。**示例：** 不适用。**决策：** 状态归路线和客户端所有，不混用全局缓存或 Cookie。 | **旧版：** GET 课程列表；GET `courselist.jsp?courseID=<id>` 选择课程；GET `assignment/index.jsp`；`includeExpired` 只影响本地截止时间，不是上游参数。**示例：** 不适用。 | **旧版：** 浏览器 `Accept`、`Accept-Language: zh-CN,zh;q=0.9` 和精确 Chrome 58 UA，无正文。**示例：** 不适用。**决策：** 保持不变。 | **旧版/示例：** 不适用。 | **旧版：** 解析排除课程 0 的课程链接；按 `assignID` 解析作业链接，排除 `problemContent` 和 `judgeDetails`，并去重。**示例：** 不适用。**决策：** 实时对齐前必须保留完整过滤规则。 | **旧版：** 列表缓存按用户和路线分组，作业处理最多 4 个并发 worker，列表 TTL 5 分钟；除非 `includeExpired`，只保留六个月内课程。**示例：** 不适用。**决策：** 状态由路线客户端拥有并随会话生命周期清理。 | **旧版：** 本地未登录、SSO 重激活失败、非 200、无权限或不存在均映射为稳定错误。Judge 业务认证重试耗尽后先校验 UC，仅 UC 明确 Invalid 才清理主会话；Valid、5xx、网络或不确定结果保留会话并返回业务失败。**示例：** 不适用。**决策：** 顶层沿用该仲裁，保留会话时使用 `upstream_unavailable`；列表退出 0 或数量本身不能证明解析一致，Direct/WebVPN 数量差异继续保留。 |

| **旧版：**无诊断 API，使用上述 Judge 列表引导。**示例：**不适用且不等价。**决策：**诊断不增加上游请求或 URL。 | **旧版：**同一列表激活和有界重激活。**示例：**不适用。**决策：**复用精确列表链和路线解析。 | **旧版：**同一用户/模式客户端及独立 worker。**示例：**不适用。**决策：**facade 只公开计数，不暴露 worker/会话状态。 | **旧版：**同一课程、选择、作业列表和详情 GET，无诊断参数。**示例：**不适用。**决策：**普通和诊断读取共用同一路径与缓存。 | **旧版：**同一浏览器请求头和空正文。**示例：**不适用。 | **旧版/示例：**不适用。 | **旧版：**先匹配数字 `assignID` 锚点，再排除 `problemContent`/`judgeDetails`，拒绝空标题并去重；没有计数 DTO。**示例：**不适用。**决策：**`courseCount` 为跳过历史课程前的课程数；`rawAnchorCount` 汇总操作触达的作业列表中数字 `assignID` 的 `a[href]` 匹配（新取或缓存均可），在排除、标题过滤、去重前统计；创建 worker 前跳过的历史课程不贡献任何计数；`filteredUniqueCount` 汇总最终非空唯一作业列表；`summaries` 与普通 `includeExpired` 结果完全一致。不增加原始 HTML、新 ID、现有摘要之外的标题、Cookie 或令牌。 | **旧版：**列表 TTL 5 分钟，空作业列表不缓存。**示例：**不适用。**决策：**每个非空作业列表解析时原子缓存两个安全计数，普通读取后诊断不重复请求或推断；保留四 worker 上限和生命周期失效。 | **旧版：**列表认证/上游错误不变。**示例：**不适用。**决策：**诊断 facade 返回与普通 Judge 列表相同的错误和路线语义；计数是证据元数据，不能单独证明实时成功。

| 引导/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**激活/选课后 GET `assignment/index.jsp?assignID=<id>`。**示例：**不适用且不等价。** **决策：**使用冻结列表发现的 ID。 | **旧版：**SSO 页面重新激活并重试，路线保持不变。**示例：**不适用。** **决策：**详情仍锁定所选路线。 | **旧版：**选课互斥锁和独立 worker Cookie。**示例：**不适用。** **决策：**只使用同一路线/客户端状态。 | **旧版：**GET，使用列表发现的数字/字符串课程和作业 ID。**示例：**不适用。 | **旧版：**Judge 浏览器请求头，无正文。**示例：**不适用。 | **旧版/示例：**不适用。 | **旧版：**解析开始/截止时间、最高/本人分数、总数/提交数、题目表、每题分数/上限/状态、`PARTIAL`、提交数回退和纯文本。**示例：**不适用。** **决策：**字段和状态语义都必需，固定空 `problems`/`myScore` 不是 parity。 | **旧版：**选课锁；详情缓存 2 分钟，按用户+路线+课程+作业分组。**示例：**不适用。** **决策：**不设全局缓存，会话重置清理。 | **旧版：**缺少作业/课程为 not found，认证页会重激活，非 200/认证耗尽返回稳定错误；业务认证最终失败时先校验用户中心。** **决策：**只在顶层详情执行一次仲裁，不在每个内部请求中执行；历史退出 0 在完整解析断言前不构成语义证据。

## Judge 详情

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：** 激活/选课后 GET `assignment/index.jsp?assignID=<id>`。**示例：** 不适用且不等价。 | **旧版：** SSO 页面重新激活并重试，路线保持不变。**示例：** 不适用。 | **旧版：** 选课互斥锁和独立 worker Cookie 状态。**示例：** 不适用。**决策：** 使用同一路线/客户端范围。 | **旧版：** GET，使用列表发现的精确数字/字符串课程和作业 ID。**示例：** 不适用。 | **旧版：** Judge 浏览器请求头，无正文。**示例：** 不适用。 | **旧版/示例：** 不适用。 | **旧版：** 解析开始/截止时间、最高/本人分数、总数/提交数、嵌套或顶层题目表、每题分数/上限/状态、`PARTIAL`、提交数回退和纯文本。**示例：** 不适用。**决策：** 所有字段和状态语义均为必需，固定空 `problems`/`myScore` 不算对齐。 | **旧版：** 选课锁；详情缓存 2 分钟，键为用户+路线+课程+作业。**示例：** 不适用。**决策：** 不设全局缓存，会话重置时清理。 | **旧版：** 缺少作业/课程为不存在，认证页会重激活，非 200 或认证耗尽返回稳定错误。业务认证最终失败后先校验 UC，再决定主会话是否失效。**决策：** 该仲裁只包住顶层详情操作，不在每个内部请求重复执行；完整解析断言通过前，历史详情退出 0 不构成语义证据。 |

## Judge 批量与缓存

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：** 复用 Judge 激活、列表和详情地址，没有单独的批量上游 API。**示例：** 不适用且不等价。 | **旧版：** 每个 worker 激活后保持在自己的路线。**示例：** 不适用。 | **旧版：** 缓存范围为 `(mode,username)`；worker Cookie 隔离 Judge 会话；重置清理 `LocalJudgeApiCache`。**示例：** 不适用。**决策：** 使用运行时拥有的 `RouteFeatureState`，绝不使用进程全局状态。 | **旧版：** 规范化非空 `(courseId,assignmentId)` 键，去重后按课程分组，执行同样的详情 GET 序列。**示例：** 不适用。 | **旧版：** 使用相同的浏览器请求头。**示例：** 不适用。 | **旧版/示例：** 不适用。 | **旧版：** 分组遍历返回完整详情 DTO 和公开的 `historicalCutoffCourseIds`；规范化输入为空时返回空详情。**示例：** 不适用。**决策：** UBAA 2 将截止课程 ID 保留在路线状态内部，分组处理后恢复规范化后的调用方顺序。 | **旧版：** 最多 4 个并发课程 worker；列表 TTL 5 分钟、详情 TTL 2 分钟；不缓存空作业列表；截止范围保留当天时分并钳制目标月份日期；重置清空全部状态。**示例：** 不适用。**决策：** 在所属 facade 内复现并发上限、缓存键和生命周期。 | **旧版：** 一个课程/作业不存在会使批量操作返回不存在；认证/上游错误不会隐藏。业务认证最终失败仍先经过 UC 仲裁再清理主会话。**示例：** 不适用。**决策：** 顶层批量操作共享 Judge 仲裁边界，注销或账号/路线变更后不得复用旧状态。 |

## CLI 与配置

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**宿主 UI 选择 `ConnectionMode`，没有等价 UBAA2 CLI/配置。**示例：**只有库上下文，没有 CLI/配置/schema。**决策：**上游 URL 不适用，普通路由由聚合 Core facade 负责。 | **旧版/示例：**没有等价 CLI 跳转合同。**决策：**宿主只接收 facade 结果。 | **旧版：**按模式保存设置，切换会清会话。**示例：**调用方管理 `cookies.json`/`cred.json`。**决策：**Core 加载严格的 `config.toml` 版本 1 和双路线 `session.json`；CLI 不读取存储内部。 | **旧版/示例：**无等价命令。**决策：**CLI 解析文档命令/参数，调用不带 `ConnectionMode` 的 facade 并负责渲染；隐藏模式仅用于诊断/测试。 | **旧版/示例：**无信封。**决策：**stdout 只输出一个 JSON 值，诊断仅写 stderr，不输出敏感值或原始上游数据。 | **旧版/示例：**不适用。**决策：**CLI 只使用 schema v2；配置/会话磁盘版本独立。聚合路线数组固定 Direct 后 WebVPN；`all_ready`/`partial` 必须有完整资料，`none_ready` 禁止存在资料。路线错误只含稳定安全错误，不含挑战/图片字段或验证码错误码。单路线信封不能带聚合字段，解析前错误只带功能名。 | **旧版：**全局模式/运行时。**示例：**调用方拥有上下文。**决策：**配置、探测缓存、路由、会话和业务状态由 facade 拥有；CLI 不持有路由缓存。配置写入拒绝符号链接/非普通文件并使用唯一原子临时文件。 | **旧版/示例：**没有等价退出分类。**决策：**使用稳定退出码 0/2/3/5/6/7；新配置目录支持 JSON 登录；交互验证页映射为 `upstream_changed`（退出 6），缺少本地用户/功能会话时在网络前失败。

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
条件。当前 Direct/WebVPN 证据按操作记录在 `docs/migration/status.md`，`auto` 仍仅确定性验证。

## 未改变的课表/考试证据

`LocalScheduleApi.kt` 探测 `currentUser.do`；`Schedule.kt` 和
`LocalScheduleApiBackendTest.kt` 证明学期/教学周/今日/考试 GET 请求，以及周课表表单字段
`termCode`、`type=week`、`week`。固定的 `api/aas/core.rs` 证明相同的 AAS 专用 CAS 激活和最终
落地 URL。固定的 `api/aas/opt.rs` 使用包含 `campusCode` 的不同查询正文，UBAA 2 没有本地或
实时证据时不借用该字段。不涉及加密；路线锁定、本科不支持分类和脱敏解析器 Fixture 仍是必需项。

2026-08-25 Direct 和 WebVPN 实时结构检查返回成功的 `WeeklySchedule` 信封，包含冻结的
`arrangedList`、`code`、`name` 字段；列表为空，`data.code` 是非空字符串且不同于选定学期。冻结
DTO/解析器只解码 `WeeklyScheduleResponse.datas`，不要求两者相等。因此实时验证器仅检查
`data.code` 为非空字符串；请求学期仍从学期响应选择并原样发送，不得凭空增加两份冻结来源均未
支持的相等规则。

## 未改变的成绩证据

`LocalGradeApi.kt` 证明先在 `https://app.buaa.edu.cn/buaascore/wap/default/index` 激活，再以
表单 POST 发送 `xq` 和 `year`；`Grade.kt` 证明 `e/m/d` 信封及标量映射。固定 App 模块不适用且
不等价，未提供本地成绩 URL、DTO 或错误语义。旧版独立成绩缓存不能作为上游请求缓存证据。UBAA 2
保留严格的 `yyyy-yyyy-semester` 解析，以及稳定的输入无效/上游/解析错误。

## 课堂签到今日查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**先访问 `https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter`，再调用 8347 的 `app/user/login.action` 和 `app/course/get_stu_course_sched.action`。**示例：**等价 Class 模块在固定提交中将登录更新为 8346 的 `eschool/app/user/login_buaa.do`，今日查询仍使用 8347 的 `app/course/get_stu_course_sched.action`。**决定：**2026-08-28 Direct 真实运行证明旧登录入口返回 `upstream_changed`，采用示例中更晚且等价的登录入口；查询入口保持旧版。 | **旧版：**最多跟随 8 次跳转，从最终 URL 或 `Location` 中提取大小写不敏感的 `loginName`，并进行百分号解码；Direct/WebVPN 始终保持当前路线。**示例：**登录前同样从 8346 跳转结果提取 `loginName`。**决定：**使用 Core 的手动、允许主机列表跳转，不接受未知主机。 | **旧版：**主认证 Cookie 与 iClass `id/sessionId` 分离；业务会话按学生标识缓存。**示例：**同样维护独立 Class 凭据。**决定：**iClass 会话是每个路线/客户端的进程内状态，不能写入 `session.json`，也不能跨路线复用。 | **旧版：**登录 GET 参数为 `password=""`、`phone=loginName`、`userLevel=1`、`verificationType=2`、`verificationUrl=""`；今日查询 GET 参数为 `id=userId`、`dateStr=yyyyMMdd`。**示例：**登录和查询参数与旧版一致。**决定：**保持完整参数和值，不增加字段。 | **旧版：**今日查询使用 `sessionId` 请求头；请求无正文。**示例：**使用等价会话值作为 `Sessionid`，查询为 POST 并将 `dateStr` 放在 query；**决定：**本轮仅由真实失败证明登录入口变化，查询方法仍保持冻结旧版 GET，除非后续真实证据要求调整。 | **旧版/示例：**无加密。**决定：**不得引入自定义加密或签名。 | **旧版：**`STATUS` 接受字符串或整数；成功值为 `0`、`200`、`success`。课堂字段为 `id`、`courseName`、`classBeginTime`、`classEndTime`、`stuSignStatus`，状态兼容字符串或整数。**示例：**`STATUS=2` 表示空列表。**决定：**公共 DTO 仅暴露对应稳定字段，不暴露包装、业务会话或原始响应；空列表语义需以真实响应确认。 | **旧版：**按学生标识缓存业务会话；会话失效后最多刷新一次。**示例：**Class 凭据独立缓存。**决定：**使用路线内登录锁和失效代数，主会话清理时同步清除；并发失效后旧任务不得重新写入。 | **旧版：**未认证返回认证错误；iClass 登录失败时查询退化为空成功，这是旧 UI 的容错行为。**示例：**业务失败上抛。**决定：**Core 不伪造空成功；无法建立业务会话返回稳定上游错误，业务会话失效只清除签到状态，只有 User Center 明确失效才清除主认证。 |

当前实现证据：`crates/ubaa-core/tests/signin.rs` 已覆盖冻结响应的字符串/整数状态解析及独立 iClass 会话；Core facade 和 `signin today` CLI 已接入。固定 `examples/buaa-api` 的 Class 模块提供补充登录入口证据，但其查询方法/请求头与冻结旧版不等价；Rust Core 按冻结旧版使用 GET、`sessionId` 头并将 `id/dateStr` 放在 query。`STATUS=2` 表示今日无课程的合法空结果。2026-08-28 Direct 与 WebVPN 实时验证均通过并返回空列表。

## 阳光打卡只读查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：** OAuth 入口为 `https://app.buaa.edu.cn/uc/api/oauth/index`，交换地址为 `https://ygdk.buaa.edu.cn/api/Front/Clockin/User/campusAppLogin`；**示例：**无等价模块；**决定：**仅采用冻结旧版证据。 | **旧版：**最多跟随 10 次跳转，从 query 或 fragment query 提取并解码 `code`；**决定：**仅允许已记录的 BUAA 主机。 | **旧版：**按学生标识缓存独立 `uid/token`，不复用主认证 Cookie；**决定：**挂在路线隔离的业务会话状态中，不持久化敏感令牌。 | **旧版：**先分类、项目、汇总/学期，再记录查询；记录使用 `page`、`limit`、`classify_id`、`user_id`，概览固定 `page=1`、`limit=1000`；**决定：**保持分页与体育分类选择语义。 | **旧版：**POST `application/x-www-form-urlencoded`，所有请求附加 `uid/token` 和 `X-Requested-With: XMLHttpRequest`；**决定：**不记录令牌值。 | **旧版/示例：**无加密；**决定：**不引入签名或自定义加密。 | **旧版：**概览包含学期汇总、分类、默认项目和项目列表；记录包含记录标识、项目、时间、地点、图片、状态及分页字段；时间按上海时区格式化。 | **旧版：**按学生标识缓存业务会话，认证失效时清除并重试一次；**决定：**使用路线内单飞登录与失效代数。 | **旧版：**外层 `code=1` 成功，`-98` 清会话并认证失败，其余使用 `msg` 映射上游错误；非法分页参数为输入错误；**决定：**禁止把失败伪装为空结果。 |

当前实现证据：`crates/ubaa-core/tests/ygdk.rs` 已覆盖概览、记录分页和令牌业务会话，Core facade 与 `ygdk overview`/`ygdk records` CLI 已接入；`ygdk submit` 现已接入照片 multipart 上传和固定字段表单提交，要求 CLI 显式 `--confirm-write`，实时验证永不调用。OAuth code 同时从普通 query 与 `#/home?code=...` fragment query 提取；项目和记录参数按冻结实现同时发送至 query 与表单正文；业务 token 作为单独 URL 值解码，`-98` 会清除业务凭据并完整重登一次。概览统计与学期请求按冻结 `runCatching` 语义作为可选步骤，失败时保留分类/项目结果并回退空统计。上传正文的 `uid`、`token`、`file` 字段、固定边界、文件名和 MIME 已有确定性向量测试。`examples/buaa-api` 没有等价实现，不能从其模块类比 URL、字段或令牌流程。2026-08-28 Direct/WebVPN 实时验证均通过并解析到 11 个项目。实时验证永不调用写操作。

## 图书馆座位只读查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**业务基址 `https://booking.lib.buaa.edu.cn/v4/`；**示例：**无等价模块；**决定：**只采用冻结旧版。 | **旧版：**SSO 最多 8 跳，从最终 URL、Location 或 fragment 提取 `cas`；**决定：**手动跟随并限制已知主机。 | **旧版：**独立图书馆 token，不复用教务 Cookie；**决定：**路线内存储，禁止持久化令牌。 | **旧版：**所有查询 POST JSON：`space/pcTopFor`、`space/pick`、`Space/map`、`Space/seat`、`member/seat`，参数含日期、区域、时段和分页；**决定：**保持原始 JSON 字段。 | **旧版：**Authorization、Origin、Referer、固定 UA、`X-Requested-With`；**决定：**不输出 token。 | **旧版：**AES 仅用于预约写操作；**决定：**只读查询不引入加密。 | **旧版：**图书馆、楼层、区域、时段、座位及预约分页 DTO；座位 `status == 1` 表示可用。 | **旧版：**token 按用户缓存，失效后清理并重试一次；**决定：**路线隔离状态。 | **旧版：**业务 code 0/1 成功，其他映射错误；**决定：**区分上游错误、未找到和座位不可用，不伪造空结果。 |

当前实现证据：UBAA2 Core 已完成五类图书馆只读查询及独立路线内 token 会话，CLI 已接入五个对应子命令，并有 Mock/CAS 回归测试。预约、取消现已接入 Core/CLI，并以冻结 golden 向量覆盖日期派生 AES-128-CBC、PKCS#7 和固定 IV；CLI 写入口要求显式确认，verify-live 永不调用。`examples/buaa-api` 没有等价实现。历史 Direct 与 WebVPN `feature=libbook` 只读验证曾成功并返回 2 个馆区；分区详情的当前实时验收必须在每日 08:30–23:00（`Asia/Shanghai`）开放窗口内进行，非营业时间的 `code=500` 不作为协议变化结论。

补充证据（`24acd8b`）：`crates/ubaa-core/tests/libbook.rs` 的 Mock 端到端测试按冻结顺序调用预约确认和取消接口，断言 `aesjson` 非空、取消请求携带预约标识，并复用路线内 bearer 会话。测试仅使用合成会话与脱敏响应，不产生真实预约或取消。

## 变更审查规则

## UBAA2 直接写操作与评教（2026-08-28）

### Cgyy 预约提交

取消操作的直接 Facade 证据：`RouteClient::cgyy_cancel_order` 已补齐正数订单校验，并通过合成传输断言 `/api/orders/new/cancel/{id}` 的 POST 签名请求；不跨路线复用令牌，也不执行真实取消。

冻结 `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalCgyyApi.kt` 的 `submitReservation` 要求先读取 `/api/reservation/day/info`，取得预约上下文 `token`，校验所有选择属于同一空间且时段可预约，再以表单 POST `/api/reservation/order/info` 创建订单上下文。验证码获取与校验分别使用 `/api/captcha/get`、`/api/captcha/check`，旧实现由注入的验证码求解器提供 `pointJson` 和 `captchaVerification`，失败最多重试三次。最终表单 POST `/api/reservation/order/submit`，字段为 `venueSiteId`、`reservationDate`、`reservationOrderJson`、`weekStartDate`、`phone`、`theme`、`purposeType`、`joinerNum`、`activityContent`、`joiners`、`isPhilosophySocialSciences`、`isOffSchoolJoiner`、`captchaVerification`、`token`。Rust Core 已实现上下文创建、选择校验、受控图片求解和最终表单构造；CLI 默认禁止写操作，`verify-live` 永远只读，独立用户授权例外另行记录。`examples/buaa-api` 未提供同一场馆预约协议，未借用其 URL、字段或错误语义。

Signin perform 已由 Rust Core 和 CLI 暴露。冻结的本地顺序为：取得 iClass 业务会话，GET `app/common/get_timestamp.action`，再向 `eschool/app/course/stu_scan_sign.action` 发送带 `id` 的表单，并携带 `courseSchedId`、`timestamp` 查询参数和 `sessionId` 请求头。CLI 要求 `--confirm-write`，verify-live 永远不会调用它。响应必须同时满足冻结成功状态和 `result.stuSignStatus=1`；畸形或非成功响应映射为稳定的上游错误。

补充证据：`crates/ubaa-core/tests/signin.rs` 的合成传输按上述四步顺序返回脱敏响应，并断言最终 URL、表单和会话头；测试不会访问真实 iClass，也不持久化业务会话材料。

Ygdk 写入口的输入边界也已固定：照片必须存在且非空，开始和结束时间必须同时提供；这些检查发生在 OAuth/业务令牌请求之前。`features/ygdk.rs` 单元测试使用禁止网络的传输验证无效请求直接返回 `invalid_input`。

`crates/ubaa-core/tests/ygdk.rs` 进一步以合成传输验证完整写链顺序：OAuth code、`campusAppLogin`、分类/项目/统计/学期概览、`Upload/File/post` multipart 和 `Clockin/clockin` 表单；断言 `uid`、业务 token、文件元数据及打卡字段均按冻结协议发送，且不产生真实副作用。

下表是其余直连上游操作的必填对照边界。`ubaa_old` 以 `references.md` 记录的提交为准；除
Evaluation 的 SPOC 端点外，`examples/buaa-api` 对所有行均明确不等价。除非决策日志记录了独立的
用户授权和脱敏结果，否则任何一行都不授权在迁移验证期间执行真实写操作。

| 操作 | 引导/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密/签名常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|---|
| Bykc 选课 | CAS `bykc.buaa.edu.cn/sscv/cas/login`，API `/sscv/choseCourse` | 与读取相同的 CAS 令牌跳转和路线封装 | 路线内 BYKC 令牌 | POST 加密 JSON `{courseId}` | 加密正文、`auth_token`/`authtoken`、`ak`、`sk`、`ts`、JSON 类型 | AES-128-ECB PKCS7；RSA PKCS#1 v1.5；SHA-1 摘要；冻结公钥见 `LocalBykcCrypto.kt` | 从信封读取 `BykcSuccessResponse.message` | 登录单飞；令牌过期后重试 | 输入错误在本地返回；上游非成功映射为稳定写错误 |
| Bykc 退选 | 同上 | 同上 | 同上 | POST 加密 JSON `{id}` 到 `/sscv/delChosenCourse` | 同上 | 同上 | 成功消息 | 同上 | 同上 |
| Bykc 签到/签退 | 同上 | 同上 | 同上 | POST 加密 JSON `{courseId,lat,lng,signType}` 到 `/sscv/signCourseByUser`；`signType` 为 1 或 2 | 同上 | 同上 | 成功消息 | 写入前查询已选课程和签到配置；不使用全局缓存 | 缺少课程/位置或不在可用时间窗映射为输入/上游错误 |
| Signin 执行签到 | iClass 中心 `?type=jumpMyCenter`；业务登录 `8347/app/user/login.action` | 有界白名单跳转；提取解码后的 `loginName` | 路线内 `{userId,sessionId}`；登录过期后重试一次 | GET 时间戳 `app/common/get_timestamp.action`，再 POST 表单 `app/course/stu_scan_sign.action`，正文含 `id`，查询含 `courseSchedId`、`timestamp` | `sessionId` 请求头；URL 编码表单 | 无 | `{code,success,message}`；成功要求 `STATUS` 成功且 `result.stuSignStatus=1` | 按学生单飞业务会话 | 绝不静默成功；失败状态映射为稳定写结果/错误 |
| Ygdk 提交打卡 | OAuth 首页后调用 `campusAppLogin` | 从查询串/片段有界提取 code | 路线内 `{uid,token}` | multipart `Upload/File/post`（`uid`、`token`、`file`），再提交 `Clockin/clockin` 表单（`start_time`、`end_time`、`place_type`、`place`、`isopen`、`form_time_fmt`、`images`、`classify_id`、`item_id`、`item_name`、`uid`、`token`） | 先发照片 multipart，再发带 `X-Requested-With` 的 `application/x-www-form-urlencoded` | 无 | `{success,message,recordId,summary}` | 会话单飞；令牌不持久化 | `-98` 清理并重试一次；上传/打卡失败为写失败 |
| LibBook 预约 | CAS 服务 `booking.lib.buaa.edu.cn/v4/login/cas` 后调用 `/v4/login/user` | 有界 SSO 跳转并提取 `cas` | 路线内 bearer 令牌 | POST JSON `{aesjson}` 到 `/v4/space/confirm`；AES 明文为预约请求 `{areaId,seatId,day,segment,startTime,endTime}` | `Authorization: bearer<token>`、Origin/Referer/X-Requested-With | 冻结 `LocalLibBookCrypto.encryptReserveRequest` 的 AES 常量 | `{success,message,booking?}` | 令牌单飞；过期后清理并重试一次 | 非成功信封映射为稳定写错误 |
| LibBook 取消预约 | 同上 | 同上 | 同上 | POST JSON `{id}` 到 `/v4/space/cancel` | 同上 | 请求封装外无额外加密 | `{success,message}` | 同上 | 无效预约和过期会话保持可区分 |
| Cgyy 锁码 | SSO `manageLogin`，再调用 `/api/login` | 路线内有界跳转 | 路线内 `cgAuthorization` 业务令牌 | GET `/api/orders/lock/code` | 使用现有 Cgyy 客户端的签名查询/请求头 | 现有 Cgyy MD5 签名常量 | 不透明锁码 JSON 数据 | 令牌单飞 | 信封 code/message 决定稳定错误 |
| Cgyy 预约提交 | 同上 | 同上 | 同上 | POST `/api/reservation/order/info`；验证码 GET `/api/captcha/get`、POST `/api/captcha/check`；再 POST 表单 `/api/reservation/order/submit`，字段为 `venueSiteId,reservationDate,reservationOrderJson,weekStartDate,phone,theme,purposeType,joinerNum,activityContent,joiners,isPhilosophySocialSciences,isOffSchoolJoiner,captchaVerification,token` | URL 编码表单和 JSON 选项列表 | 现有 Cgyy 请求签名；验证码求解输入不持久化 | `{success,message,order?}` | 不缓存写操作；验证码最多重试 3 次 | 槽位/输入错误在本地返回；验证码耗尽和上游失败映射为稳定写错误；CLI 可省略验证码材料，由 Core 完成挑战获取、求解和校验 |
| Cgyy 取消预约 | 同上 | 同上 | 同上 | POST `/api/orders/new/cancel/{id}` | 签名请求，空正文 | 现有签名 | 操作消息/订单 | 令牌单飞 | CLI 必须显式确认；提交后等待旧版要求的落库窗口，订单列表状态 2 才是最终取消证据 |
| Evaluation 列表/待评 | GET `spoc/pjxt/cas`，再读取任务、问卷列表和待评课程 | 路线内有界 SPOC 跳转 | 路线内 SPOC Cookie/会话 | GET 任务参数 `yhdm,pageNum=1,pageSize=10`；问卷 `rwid`；课程 `wjid`；题目字段严格来自 `EvaluationCourse` | JSON 信封和 GET 查询；问卷模式更新为尽力 JSON POST | 无 | 任务/问卷/课程字段来自冻结 `EvaluationModel.kt`；待评筛选 `!isEvaluated` | 激活互斥锁；课程键 `${rwid}_${wjid}_${kcdm}_${bpdm}` | 信封畸形/认证失败为稳定错误；只有上游明确成功时空结果才有效 |
| Evaluation 提交评教 | 同上 | 同上 | 同上 | 尽力 POST `/reviseQuestionnairePattern` `{rwid,wjid,msid}`，GET 题目，再 POST `/submitSaveEvaluation` `{pjidlist:[],pjjglist:[...],pjzt:"1"}` | JSON | 无额外加密；正文遵循冻结 `LocalEvaluationService.kt` | 每课程 `EvaluationResult`；正文保留 `pjdf=93`、题目 ID/选项和教师/课程 ID | 按课程有界串行提交；不缓存 | 提交响应 code/message 映射每课程成功/失败；CLI 必须显式确认 |

固定的 `examples/buaa-api` 中，Evaluation 模块（`src/api/tes`）确认相同的 SPOC 任务/表单/提交
URL，但不能作为其它功能 URL、字段或加密的证据。旧版本地代码使用随机答案时，Core 为测试提供
显式确定性答案策略，验证过程中从不执行真实提交。

## 博雅课程只读查询

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**CAS 登录服务为 `https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbykc.buaa.edu.cn%2Fsscv%2Fcas%2Flogin`；业务接口位于 `https://bykc.buaa.edu.cn/sscv/`。**示例：**`examples/buaa-api/src/api/boya` 提供同一业务端点的交叉证据，但不替代旧版加密实现。 | **旧版：**登录后从 `cas-login?token=` 重定向提取令牌；必须手动限制允许主机和跳转次数。**WebVPN：**先把最终地址及 `Location` 还原为直连语义，再解析相对跳转、校验 `sso/bykc` 主机，发请求时重新按当前路线包装。 | **旧版：**按用户缓存独立业务令牌，不复用主认证 Cookie；**决定：**令牌仅保存在路线内存状态，不写入 `session.json`。 | **旧版五项只读：**`getUserProfile {}`、`queryStudentSemesterCourseByPage {pageNumber,pageSize}`、`queryCourseById {id}`、`getAllConfig {}` 后接 `queryChosenCourse {startDate,endDate}`、`queryStatisticByUserId {}`。已选课程的公开接口不接收日期：先选择首个包含当前时间的学期，否则按可解析的结束时间选择最新学期；空列表或选中项缺少起止时间均报“无法获取当前学期信息”。`all=false` 时只在本地过滤状态为“已过期”或“选课结束”的当前页项目，`all=true` 时保留全部项目，请求参数和上游分页统计均不改变。**示例：**同样请求课程分页和学期配置，但其配置包装只取首项，学期选择顺序仍以冻结旧版为准。 | **旧版：**所有接口 POST JSON 外层加密；请求携带 `auth_token`/`authtoken` 及 `ak`、`sk`、`ts` 头；不得记录密文、令牌或请求体。 | **旧版：**随机 AES-128-ECB 加密正文，RSA PKCS#1 v1.5 加密 AES key 与 SHA-1 正文摘要；公钥来自冻结 `LocalBykcCrypto.kt`。**决定：**实现前必须逐常量添加向量测试，禁止凭示例代码猜测。 | **旧版 DTO：**用户资料、课程分页/状态、课程详情、已选课程和统计；列表课程包含课程、选课与退选时间及稳定状态；状态顺序固定为已过期、已选、选课结束、人数已满、预告、可选。必填字段与时间/枚举兼容规则以 `Bykc.kt` 及冻结测试为准，公共层不得暴露原始密文或上游包装。 | **旧版：**业务令牌按用户缓存；课程详情/已选课程需要学期配置，查询失败不得写入空缓存；并发登录只能产生一个有效路线令牌。 | **旧版：**CAS/令牌失效清理业务状态并最多刷新一次；非零业务码、解密失败、字段缺失分别映射稳定上游/解析错误；不得把失败伪装为空列表。**实时证据：**2026-08-28 Direct 与 WebVPN 均通过并解析到 1 条课程。 |

当前实现证据：UBAA2 已实现 Bykc Core、路线独立会话、facade 和 CLI 五项只读查询，并完成 Direct/WebVPN 真实验证。已选课程按冻结 `courseInfo` 嵌套结构展开课程标识、名称、地点、教师、时间、分类、考勤、考核、签到配置、作业与备注；缺失课程信息沿用旧版的标识零值和“未知课程”，签到可用性按考核状态、考勤状态和时间窗口计算。旧版 DTO 虽保留作业附件名称与路径，但本地实现没有从该只读响应赋值，因此 UBAA2 同样返回空值。`examples/buaa-api` 仅作端点交叉证据，不能替代冻结旧版的 AES、RSA、SHA-1 常量和错误语义。选课、退选、签到及附件写请求已接入 Core/CLI，并由显式确认保护；实时验证永不调用。

Bykc 写链 Mock 证据：`crates/ubaa-core/tests/bykc.rs` 按冻结顺序返回 CAS token，并依次校验 `/sscv/choseCourse`、`/sscv/delChosenCourse`、`/sscv/signCourseByUser` 的非空加密正文、`auth_token`/`authtoken` 和 `ak`/`sk`/`ts` 头。测试不记录密文内容、不使用真实会话。

URL、Service 值、重定向、Cookie/会话范围、方法、参数、请求头、正文编码、加密常量、DTO
字段/类型、缓存键、并发上限或错误映射的任何变更，都必须在生产代码修改前更新对应操作行。
仅有 Fixture 不能关闭实时对照，认证成功不能关闭业务操作，退出码为零的列表也不能证明详情或
解析语义。

## Flutter bridge 实现对照记录（2026-09-01）

本轮生产代码只调用已在本文件逐操作固定的 `ubaa-core` facade 方法；`2faa753` 的
`crates/ubaa-flutter-bridge/src/api/client.rs`、`read.rs`、`write.rs` 仅做 typed 字段白名单、
路线结果投影和一次性意图保存，不复制 URL、Cookie、Header、加密、重试或解析逻辑。认证、读取
和写入的 URL、参数、常量、DTO 缺失值、缓存/并发及错误语义分别沿用本文件对应表格，并由
`docs/contracts/flutter-bridge.md` 的方法/字段表约束；`examples/buaa-api` 无等价协议的行继续
标记为“不适用”，没有类比借用字段。

桥接新增的失败测试先验证相对配置目录、销毁后调用、重复意图和随机摘要在网络前拒绝，再实现
最小投影。真实账号、Cookie、挑战材料和上游响应没有进入 bridge、fixture 或生成绑定。

## 场馆预约只读查询

| 操作 | 引导/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|---|
| 场馆站点 | **旧版：** 先 GET `https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin`，再 POST `/api/login`，最后 GET `/api/front/website/venues?page=-1&size=-1&reservationRoleId=3`。**示例：** 无等价场馆接口。**决策：** 仅采用旧实现 URL。 | **旧版：** `manageLogin` 使用跟随跳转的客户端；业务请求若最终落到 SSO、返回 401 或登录表单即判定业务认证失效。**示例：** 不适用。**决策：** 跳转仅允许 SSO 与场馆主机；每次请求统一使用 facade 解析出的当前路线 runtime，WebVPN 不回退 Direct。 | **旧版：** 从基址 Cookie `sso_buaa_zhjs_token` 取值，以 `Sso-Token` 头调用 `/api/login`，再从 `data.token.access_token` 取得业务令牌；令牌按用户缓存。**示例：** 不适用。**决策：** 业务 Cookie/令牌只保存在当前路线 runtime，不从另一路线槽位复制，也不写入 `session.json`。 | **旧版：** 业务登录为无表单字段 POST；站点为 GET，固定 `page=-1`、`size=-1`、`reservationRoleId=3`；所有 GET 自动增加当前毫秒 `nocache`。**示例：** 不适用。**决策：** 保留全部参数、名称与类型。 | **旧版：** 所有调用带 `Accept: application/json, text/plain, */*`、场馆移动预约页 `Referer`、`app-key`、`timestamp`、`sign`；业务查询另带 `cgAuthorization`；POST 使用表单编码。**示例：** 不适用。**决策：** 保持这些头和编码，禁止记录 Cookie、令牌与签名原文。 | **旧版：** `app-key=8fceb735082b5a529312040b58ea780b`；签名为 `MD5(prefix + 规范化路径 + 按键名排序的原始标量参数 + timestamp + 空格 + prefix)`，其中 `prefix=c640ca392cd45fb3a55b00a63a86c618`；空字符串、集合及审计字段不参与签名。**示例：** 不适用。**决策：** 以冻结向量测试固定算法，不增加其他加密。 | **旧版：** `data` 可能是场馆对象数组，旧版递归将每个对象的 `siteList` 展开为扁平站点并继承 `venueName/campusName`；扁平数组也可直接映射。响应信封 `code/data` 且所有 `requestJson` 响应严格要求 `code=200`。**示例：** 不适用。**决策：** 公共 DTO 仅映射这些冻结字段，缺失或非 200 代码拒绝成功。 | **旧版：** 登录使用互斥锁，令牌复用；业务认证失效时清令牌并且最多强制刷新一次。**示例：** 不适用。**决策：** 当前路线业务状态内单飞，失效后只刷新当前路线业务会话一次。 | **旧版：** 缺少主会话、SSO Cookie 或访问令牌均为认证失败；业务 `code != 200`、非 JSON 与网络错误分别映射上游/解析错误。**示例：** 不适用。**决策：** 只有 User Center 明确失效才能清主会话，业务失败不能伪装为空成功；Direct 与 WebVPN 的实时结果均逐操作记录。 |
| 用途类型 | **旧版：** GET `/api/codes`，从树形数据递归提取用途；旧实现已有主会话时对动态请求或解析异常均使用固定用途回退。**示例：** 无等价接口。**决策：** 保留递归提取与已验证静态回退。 | 与站点相同；失效后最多重登并重放一次，始终使用当前路线 URL。 | 与站点相同，复用当前路线的 `access_token`。 | GET，无业务参数，自动加入 `nocache`。 | 与站点相同，无请求体。 | 与站点相同的 MD5 签名。 | 用途 `key/name`；空响应、请求失败或解析异常按旧回退规则处理。 | 与场馆会话同域；不单独缓存跨用户数据。 | 主会话缺失仍为认证错误；已有主会话后的动态请求/解析失败回退静态列表并成功返回，不伪造上游数据。 |
| 日期可用性 | **旧版：** GET `/api/reservation/day/info?searchDate=<日期>&venueSiteId=<站点>`。**示例：** 无等价接口。**决策：** 保留查询参数名称与编码。 | 与站点相同；失效后最多重登并重放一次。 | 与站点相同，复用当前路线的 `access_token`。 | GET，`searchDate` 与 `venueSiteId` 均必填，并自动加入 `nocache`。 | 与站点相同，无请求体。 | 与站点相同，查询参数与 `nocache` 均参与 MD5 签名。 | 日期信息包含时间段、空间及槽位状态；状态非 `1`、已有流水号/订单号或占用标志均判定不可预约；旧版对每个空间的槽位按 `timeId` 升序输出；成功信封的 `data` 必须存在且为 JSON 对象（允许空对象），缺失、`null` 或标量均拒绝。 | 路线会话内请求；不跨日期缓存。 | 参数缺失为 `invalid_input`；业务认证失效只刷新业务令牌；响应结构错误为 `upstream_changed`。 |
| 我的订单 | **旧版：** GET `/api/orders/mine`。**示例：** 无等价接口。**决策：** 仅采用旧实现接口。 | 与站点相同；失效后最多重登并重放一次。 | 与站点相同，复用当前路线的 `access_token`。 | GET，精确参数 `page`、`size`，自动加入 `nocache`。 | 与站点相同，无请求体。 | 与站点相同，分页参数与 `nocache` 均参与签名。 | 分页 `content`、`totalElements`、`totalPages`、`size`、`number`；订单字段按冻结 `Cgyy.kt` 映射；成功信封 `data=null` 按旧版映射为空页。 | 不缓存订单结果。 | 页码小于 0 或每页数量不为正数是 `invalid_input`；主会话/业务认证失败仍返回认证错误，成功信封的空数据才回退为空页。 |
| 订单详情 | **旧版：** GET `/api/orders/{id}`。**示例：** 无等价接口。**决策：** 仅采用旧实现接口。 | 与站点相同；失效后最多重登并重放一次。 | 与站点相同，复用当前路线的 `access_token`。 | GET，订单 ID 只进入路径，自动加入 `nocache`。 | 与站点相同，无请求体。 | 与站点相同，规范化详情路径和 `nocache` 参与签名。 | 单个订单字段按冻结 `Cgyy.kt` 映射；成功信封 `data=null` 按旧版映射为空对象 DTO，数组/标量仍拒绝。 | 不缓存详情结果。 | 非正订单 ID 是 `invalid_input`；业务认证失败保持认证错误；仅成功信封空数据按冻结旧实现映射默认字段。 |
| 锁码 | **旧版：** 先完成 `manageLogin`/`api/login`，再 GET `/api/orders/lock/code`；**示例：** 无等价接口。**决策：** 仅采用冻结旧实现 URL。 | 与站点相同，允许路线内重定向和最终 URL 校验。 | 复用当前路线业务令牌，不跨路线复制 Cookie。 | GET，无业务参数，自动加入 `nocache`。 | 与站点相同的签名头和空请求体。 | 与站点相同的 MD5 签名；不增加加密。 | **旧版：** `code=200` 才是成功，`data` 可空且不透明；Core 与 CLI 均只投影 `{available: boolean}`，不输出锁码内容。 | 业务令牌路线内单飞，锁码结果不缓存。 | 缺少会话/令牌、网络或非成功 envelope 保持认证/上游错误；CLI 验证只校验安全摘要，不把敏感原始 data 视为公共输出。 |

当前实现补充：Cgyy 业务请求不会自动跟随重定向。收到 3xx 时，`Location` 经当前最终地址解析并还原 WebVPN 包装；若目标为统一认证主机则分类为 `authentication_required`，由业务请求循环清理令牌并最多重登一次；其它 3xx 分类为 `upstream_changed`。`CgyyDayInfo` 不包含预约上下文令牌，验证码材料字段为 `pub(crate)`，宿主只能通过构造方法注入完整验证码并查询布尔存在性。日志只记录操作名、参数键/长度、状态、主机、脱敏路径和响应摘要。

2026-08-31 WebVPN Cgyy HAR 交叉证据（`examples/BUAA-CGYY/d.buaa.edu.cn.cgyy.har`，仅读、未纳入提交）：浏览器完成 Cgyy SSO 后，`manageLogin` 经两次 302 到 `/venue-zhjs`；响应没有 `Set-Cookie`。随后 WebVPN 网关的只读接口 `GET /wengine-vpn/cookie` 使用 `method=get`、`host=cgyy.buaa.edu.cn`、`scheme=https`、`path=/venue-zhjs` 和当前 `vpn_timestamp` 查询参数，返回纯文本 Cookie 快照，快照仅包含 `_zte_fp_`、`sso_buaa_zhjs_token`、`logout_flag` 等名称。前端从快照取得 `sso_buaa_zhjs_token`，向 WebVPN 包装后的 `POST /venue-zhjs-server/api/login` 发送 `Sso-Token`、`app-key`、`timestamp`、`sign`，成功信封仍为 `code/data/message`，`data.token` 含 `access_token`；随后浏览器以 `roleid` 表单和 `cgAuthorization` 访问 `roleLogin`，再以 `cgAuthorization` 读取 `website/init` 等接口。HAR 未提供 `examples/buaa-api` 的等价 Cgyy 实现，也不改变冻结旧版的 Direct URL、参数、签名或错误语义；它只补充 WebVPN 网关 Cookie 同步适配。Core 通过先失败的脱敏 Mock `webvpn_从网关_cookie接口取得_cgyy_sso令牌` 固化该行为，令牌仅在内存中作为 `Sso-Token` 使用，不写入 Session、日志或文件。

`examples/buaa-api` 在锁定提交中未实现 `venue-zhjs-server` 场馆预约协议，因此没有提供 URL、字段、令牌或错误语义；以上所有协议值均来自冻结 `ubaa_old/shared/.../CgyyApi.kt`、`LocalCgyyApi.kt`、`LocalCgyySigner.kt` 及对应服务测试。取消、锁码和预约提交已分别接入 Core/CLI 或 Core；预约提交现在还会按冻结协议 POST `/api/captcha/check`，发送 `pointJson` 与验证码挑战 `token`，并要求响应 `data.success=true` 后才提交最终表单。验证码挑战 GET 的 `captchaType=blockPuzzle`、`clientUid=slider-<毫秒时间>`、`ts=<毫秒时间>` 参数及 `secretKey/token/originalImageBase64/jigsawImageBase64` 解析已固化测试；受控图像求解器已迁移到 Core，实时验证永不调用写操作。锁码原始 `data` 只在 Core 请求解析的短生命周期内使用，facade 与 CLI 均仅返回 `{available: boolean}`，避免打印或持久化锁码内容。

验证码位移凭据的加密已由 Core 提供：输入冻结挑战 `secretKey`、`token` 和外部图像求解器得到的横向位移，输出 AES-ECB/PKCS#7 的 `pointJson` 与 `captchaVerification`；确定性 golden 向量已覆盖 16 字节密钥。Rust 现已使用受控 PNG/JPEG 解码复刻旧版灰度、边缘、掩码和滑动匹配算法，挑战缺失或图片解析失败会失败关闭；预约链最多获取并校验三次，禁止默认位移。此前段落中的“求解端口尚未迁移”仅为历史记录，当前实现已完成该 Core 算法；WebVPN 场馆业务现在和其它公共操作一样使用 facade 解析出的 WebVPN runtime，日期/订单/锁码的实时失败仍单独保留，不能由会话路由问题替代解释。

本轮 Cgyy 写链对照证据：上下文、验证码校验和最终提交三次 POST 的 `cgAuthorization` 均来自缓存的业务 `access_token`，而上下文返回的预约 `token` 仅进入冻结表单字段；业务认证失效时按旧版清理并最多重建一次会话后重放。WebVPN facade 的 Cgyy 操作均固定使用解析出的 WebVPN runtime；实时验证永不调用写操作。CLI 请求省略验证码字段时，Core 复刻旧版自动获取、求解和校验流程。2026-08-29 用户授权的 Direct CLI 探针完成提交并在等待 5 秒后取消，订单列表最终为状态 2；详情请求曾出现 `upstream_unavailable`，成功空数据仍按旧版映射。`examples/buaa-api` 无对应实现，因此没有补充协议假设。

### Signin 时间戳解析校正

冻结 `LocalSigninApi.kt` 在 GET `app/common/get_timestamp.action` 响应 JSON 中读取字符串字段 `timestamp`；空字段或非 JSON 响应均映射为上游错误，随后将该值作为签到请求查询参数。Rust Core 已严格解析该字段，并以脱敏测试覆盖非 JSON 拒绝。`examples/buaa-api` 未实现 iClass 签到协议，因此未借用其响应结构。

Signin 提交请求的表单构造已单独覆盖：冻结 `stu_scan_sign.action` 只发送 `id` 用户标识，`courseSchedId` 与 `timestamp` 位于查询参数，`sessionId` 位于请求头；测试断言表单不会增加其他字段。

### Evaluation 评教提交信封

冻结 `LocalEvaluationService.kt` 最终向 `evaluationMethodSix/submitSaveEvaluation` 发送 JSON 正文：`pjidlist` 固定为空数组、`pjjglist` 为逐课程结果列表、`pjzt` 固定为字符串 `"1"`，响应按业务 `code` 和消息字段判定成功。Rust Core 已迁移该 URL、JSON 编码、请求头和非空列表校验，并提供 `build_submit_body` 脱敏向量测试。自动提交链会按旧版顺序对每门待评课程执行 `reviseQuestionnairePattern`（失败按冻结实现继续）、读取问卷题目、展开 `wjzblist[].tklist[]`，按题型构造答案后提交最终信封；选择题的第二个选项只在随机选中的一题使用，随机源保留在 Core 内且不写入日志。CLI 提供 `evaluation submit-pending --confirm-write`，未确认时在读取课程前拒绝；实时验证永不调用写操作。`examples/buaa-api` 无等价评教提交协议。

空 `pjjglist` 现在在会话建立前返回 `invalid_input`；单元测试使用禁止网络的传输验证该边界，确保无效评教提交不会访问上游。

逐请求证据：`crates/ubaa-core/tests/evaluation.rs` 通过 `RouteClient::evaluation_submit` 使用合成会话调用冻结 `submitSaveEvaluation`，断言 JSON 信封中的空 `pjidlist`、`pjzt="1"` 和课程结果字段，以及固定请求头；不记录原始响应或个人数据。

自动链证据：同一测试文件以单门脱敏课程调用 `evaluation_submit_courses`，严格断言 CAS 激活、revise（`rwid/wjid/msid`）、题目 GET 和最终提交四步顺序，并校验最终结果保留 `pjdf=93`。Mock 响应不包含真实课程或人员数据。

LibBook 座位排序补充：冻结 `LocalLibBookApi.getSeats` 在 DTO 映射后执行 `sortedBy { it.no }`；Core `parse_seats` 同样按座位号字符串升序输出，并由逆序脱敏测试固定该行为。

LibBook 预约分页补充：冻结 `getBookings` 在 `total` 缺失时以当前映射后的预约条数作为回退；Core `parse_bookings` 保留该回退，不把缺失总数误报为零。

LibBook 分区详情补充：冻结 `mapAreaDetail(areaId, raw)` 在响应区域对象缺少 `id` 时回退传入的 `areaId`；Core 的 `parse_area_detail_for` 与 `Space/map` 查询入口保留该语义。

Bykc 签到配置补充：冻结 `LocalBykcApi.parseSignConfig` 使用严格序列化，`signPointList` 中任一点缺少 `lat/lng` 或类型错误都会使整个配置解析失败并返回空；Core `parse_sign_config` 现对列表、点对象及坐标执行同等严格校验，`radius` 仅在字段缺失时回退零值。

Ygdk 记录时间补充：冻结 `LocalYgdkRecordRaw` 将 `startTime/endTime` 读取为 Unix 秒，并由 `timestampToDateTimeText` 按 `Asia/Shanghai` 格式化为 `yyyy-MM-dd HH:mm`；Core `parse_records` 现兼容数值秒时间戳并使用固定东八区格式化，同时保留已存在的字符串兼容路径。

Ygdk 记录图片补充：冻结 `extractRecordImages` 对 `images_fmt` 支持数组和非空单字符串；当字符串不是 JSON 数组时按单个地址保留，空字符串回退为空列表。Core `parse_records` 现保持该优先级和回退语义。

Ygdk 时间字符串补充：冻结 `JsonObject.long` 先读取 primitive 文本再执行 `toLongOrNull`，因此数字字符串时间戳与数值时间戳相同，均按东八区格式化；Core `datetime_text` 现保留该兼容性，非数字文本仍原样保留。

LibBook 原语字段补充：冻结 `JsonPrimitive.contentOrNull` 将数字和布尔原语按文本映射到馆区、楼层、座位、状态及预约字段；Core `text` 现兼容字符串、整数、浮点和布尔原语，保留字段别名与空值回退。

Cgyy 原语字段补充：冻结 `LocalCgyyApi.string` 使用 `jsonPrimitive.contentOrNull`，场馆、订单和说明类文本字段可由数字或布尔原语转为文本；Core `string` 现保持同等原语文本化，整数 ID 仍由独立 `int` 解析。

Signin 写响应补充：冻结 `LocalSigninApi` 的 `jsonStringValue`/`int` 对 `STATUS` 与 `stuSignStatus` 同时接受数字和数字字符串；Core `perform_signin` 现通过 `integer_value` 保持该状态解析兼容。

Evaluation 任务身份参数补充：冻结 `LocalEvaluationService.fetchTasks` 将已登录资料的 `schoolid`（为空时回退 `username`）作为 `yhdm`，并固定 `pageNum=1&pageSize=10`。Core 运行时现仅在内存保留登录成功资料中的 `school_id`/`username`，任务请求按同一优先级发送 `yhdm`；既有会话若无资料则保持空值，不从未证实的 Cookie 或响应字段推导身份。

Ygdk 原语文本补充：冻结 `LocalYgdkApi.kt` 的 `JsonObject.string` 使用 `jsonPrimitive.contentOrNull`，记录的 `item_name`、`place`、`create_time_fmt` 等文本字段可由数字或布尔原语映射为文本。Core `string` 现统一支持字符串、数字和布尔原语，空文本仍按旧版回退为空。

Evaluation 原语文本补充：冻结评教本地实现同样通过 `JsonPrimitive.contentOrNull` 读取文本字段；Core `string` 现支持字符串、整数、浮点和布尔原语，避免合法的非字符串课程/问卷字段被误判为缺失。
