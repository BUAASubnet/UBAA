# 认证、会话与连接方式

本文件收录 SSO 登录、UC 激活、WebVPN 与校园网探测、验证码、退出及路线切换的来源对照。

## 当前规则

### WebVPN 普通登录失败重试

2026-11-09 核对冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LocalConnectionAuth.kt`、`LocalWebVpnSupport.kt`、`AuthApi.kt`、`model/dto/Auth.kt` 和 `LocalAuthServiceBackendTest.kt`，以及固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `api/sso/auth.rs`、`request.rs`、`store/{cookies,cred}.rs` 和 `error.rs`。两份来源均没有普通登录失败后自动重试的外层流程。当前产品要求 WebVPN 首次失败后再尝试一次，明确的账号密码错误也纳入重试。

| 操作 | CAS/引导与 service | 跳转与最终地址 | Cookie/会话作用域 | 方法与参数 | 请求头与编码 | 加密/签名 | DTO/解析 | 缓存/并发/重试 | 错误与产品语义 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WebVPN 普通登录 | 两源均从 SSO `/login` 获取 execution；网关 service 沿本页 SSO 身份核验对照 | 保留既有网关激活、SSO 验票与跳转限制 | 复用原 WebVPN 运行时和 Cookie，Direct 槽独立 | 重新 GET 登录页，使用新 execution 和同一组账号密码提交原六字段 POST | 原 `application/x-www-form-urlencoded` 与请求头 | 原 WebVPN AES-CFB 编码，无新增签名或密码加密 | 原 UserProfile、登录错误和验票解析 | 网络错误、超时、上游暂时不可用或明确凭据拒绝后，完整普通登录最多追加一次；重试前清除旧准备页并复核当前登录仍有效 | 首次成功立即返回；再次失败返回最后一次错误。取消、会话冲突、无效输入和交互验证要求仍按原流程处理；Direct 不追加重试 |

### SSO 身份核验与 UC 解耦

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LocalConnectionAuth.kt`、`AuthApi.kt`、`UserInfo.kt` 和认证/Cookie 测试以 UC 激活及 status 作为主会话依据。固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `api/sso/auth.rs`、`api/user/{auth,opt}.rs`、`api/aas/core.rs`、`request.rs`、`store/{cookies,cred}.rs` 将 SSO 与 UC 分成两项操作，但 SSO 登录依赖默认落地页的 HTTP 成功。两份来源均没有直接验票操作，其验票 URL、参数和 DTO 列不适用。新行为依据本会话真实 SSO 响应及 [CAS 协议](https://apereo.github.io/cas/development/protocol/CAS-Protocol-Specification.html)，冲突取舍见[决策记录](../decision-log.md#2026-11-06sso-直接验票与域名路线缓存)。

| 操作 | CAS/service 与重定向 | 方法、参数、请求头与编码 | Cookie、加密、DTO、缓存与错误 |
| --- | --- | --- | --- |
| 准备及提交登录 | 保留 SSO `/login`；默认 UC 落地跳转停止在请求 UC 之前，随后独立取票验票。 | GET 准备，POST 保留已证六字段或验证码八字段及 URL 表单编码。 | 仍使用当前路线 Cookie，密码不持久化；保持密码风险继续和三次验证码预算。302 和 Cookie 存在不授予本地身份。 |
| 取票与会话检查 | SSO `/login` 使用既有教务 service `https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp`。只读取精确 service 回调 Location 中一次性 ticket，不请求教务服务器。 | GET，service 与冻结 `api/aas/core.rs` 的生产地址一致。 | 已有会话和刚提交凭据使用相同流程。登录页表示会话失效；未知响应按协议变化处理。 |
| 验票 | SSO `/serviceValidate`，service 必须与取票请求完全一致。 | GET 参数 `service`、`ticket`、`format=JSON`；TLS 校验开启，验票响应不跟随重定向。 | 2026-11-06 校外 Direct 和 WebVPN 实测返回 HTTP 200、顶层 `user` 字符串及 `attributes.name/type/employeeNumber` 字符串数组。`user` 和唯一 `employeeNumber` 与登录账号一致。仅成功解析后保存路线会话；失败响应不能授予身份。票据只使用一次，网络错误不重放。原始材料只保留在私有目录。 |
| UC 资料读取 | 原 UC 激活链及 userinfo 地址不变，按需激活 UC。 | 保留原 GET、service、重定向和参数。 | UC 不可达只影响资料读取。UC 自身失效不直接注销 SSO；SSO 状态通过独立验票确认。 |
| WebVPN 网关认证 | 固定 buaa-api `api/sso/auth.rs::login_vpn` 的 service 为 `https://d.buaa.edu.cn/login?cas_login=true`，验证落地为网关根地址。旧版通过 UC 链间接完成网关激活，没有独立等价入口。 | 在已有 WebVPN 路线 SSO Cookie 下 GET 同一 service，不重新提交密码。2026-11-06 真实链依次返回包装后的网关 `/login`、`/wengine-vpn-token-login`、网关 `/token-login`。 | 网关自指回调保留真实 Location 的 WebVPN 包装路径。网关 token 回调写入 Cookie 后可能跳回此前业务地址。主登录改为读取网关根地址确认，不依赖该业务站点；随后 SSO 验票确认账号并保存该路线会话。网关 Cookie 与 SSO Cookie 仍保留各自路径，不复制到 Direct。 |

域名路线记录、24 小时期限及业务缓存去除路线分区是本机编排规则，两份冻结参考没有相同操作，CAS、方法、请求参数、加密和 DTO 列不适用。业务请求继续使用本索引各功能已有的逐操作协议；回退只重放读取及其必要业务认证，不改变参数、日期和分页，不重放业务写入。旧版 `LocalWebVpnSupport.kt`、`LocalConnectionAuth.kt` 与固定 buaa-api `api/sso/auth.rs`、`utils/net.rs`、`store/cookies.rs` 分别提供 URL 包装、独立 SSO 和校园网探测依据。路线记录按实际失败的上游域名保存，仅在同域名 WebVPN 读取成功后生效；同域名功能共用记录。

### 校园网变化后的会话准备

2026-11-10 对照冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LocalConnectionAuth.kt`、`LocalWebVpnSupport.kt`、认证 DTO 与测试，以及固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `utils/net.rs`、`api/sso/auth.rs`、`store/cookies.rs` 和 `store/cred.rs`。

| 操作 | 两份来源与当前行为 |
| --- | --- |
| 网络重新检测 | buaa-api 使用 `gw.buaa.edu.cn:80` 与 500 ms TCP 探测；旧版本地按选择路线认证，没有同等双槽位网络恢复。Core 沿现有探测目标、私网地址过滤与总预算，前台连接恢复撤销旧探测缓存。此操作不提交凭据，没有 CAS、正文编码、加密或业务 DTO。 |
| 校外会话准备 | 两源的普通 SSO、WebVPN 网关 service、重定向、方法、表单字段、Cookie、验证码和错误来源沿本页前两节。只改变本机调用时机：Auto 校外准备 WebVPN，校内准备 Direct，显式路线保持原选择。凭据仍由共同恢复服务按已有自动登录许可取得，账号、取消、写意图、验证码预算及退出规则不变。 |
| 读取失败后的恢复 | 两源没有同等的双运行时按域名回退恢复，新增协议列不适用。Core 只在内存共享已发生网络回退的域名，按该域名恢复 WebVPN；成功读取后才保存原有 24 小时偏好。临时恢复需求不写入持久配置，业务请求、参数、响应解析、身份核验和一次只读重试保持原合同。 |

### SSO 图像验证码静默处理

2026-11-06 实现前核对冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `LocalConnectionAuth.kt`、`AuthApi.kt`、`model/dto/Auth.kt` 及 `LocalAuthServiceBackendTest.kt`，固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `api/sso/auth.rs`、`request.rs`、`store/{cookies,cred}.rs` 与 `error.rs`。基础协议九列沿用[交互验证码来源对照](#验证码与门锁信息逐操作来源与专用显示边界)和[SSO 传输对照](#sso-传输协议与-uc-激活链对照)。buaa-api 无同协议图像验证码操作，该分支不适用，不能从普通 SSO 推断验证码字段或错误分类。

| 操作 | 引导、路线、跳转与会话 | 方法、精确参数、编码与加密 | 解析、缓存、重试及错误 |
|---|---|---|---|
| 准备图像验证码 | 沿用 HTTPS SSO `/login`，Direct 和 WebVPN 各自使用原路线 Cookie；不复制会话或修改 service | GET，无凭据正文，无新增签名或加密；保留既有 TLS 与重定向规则 | 旧版解析 `config.captcha {type,id}` 和 execution。真实页面定义配置后使用 `config.captcha.id` 生成图片地址，配置引用不构成第二个挑战。实际表单的 `execution/type/_eventId` 未写 input type，按已知协议字段处理；未知额外验证仍拒绝 |
| 获取或刷新图片 | 同路线 `/captcha`，挑战标识只留 Core | GET，业务参数 `captchaId`；浏览器另附随机 `r/t`，不据此引入新的业务字段 | HAR 中相同 captchaId 的重复 GET 返回不同图片。图片和答案只保留当前内存引用，不按 captchaId 缓存或复用；刷新后旧答案失效 |
| 提交验证码 | 同一路线 SSO `/login`，成功后执行本页的网关激活与 SSO 身份校验 | POST，沿冻结旧版八字段 `username/password/captcha/captchaResponse/execution/_eventId/submit/type`，`application/x-www-form-urlencoded`，不增加密码加密 | 真实 WebVPN 每次 GET 都轮换 captchaId 和 execution，浏览器直接提交取图时的 execution。按[来源裁决](../decision-log.md#2026-11-06sso-图像验证码按当前准备状态直接提交)取消提交前 GET，保留本地代次、账号、取消和有效期检查。自动识别使用本地模型，不上传验证码图片 |
| 拒绝与下一次尝试 | 用户提供的 WebVPN HAR 第 39 项登录 POST 返回 401，仍为原 SSO 登录页，并带新的 captchaId 和 execution | 拒绝后重新取得该路线的当前挑战，不复用原 POST；网络异常或未知响应不按验证码拒绝自动重放 | `#errorDiv p` 为“用户名或密码错误。”，验证码失败也使用此文案，无法据此判定密码无效。用户明确允许带图像验证码的已证统一拒绝最多自动提交三次，包含首次；保留保存的凭据，耗尽后转人工输入 |

用户确定的界面行为是：手动登录、已开启的自动登录和会话恢复均可静默处理验证码，期间只显示普通登录或恢复状态，失败后才显示人工输入窗口。两路线独立计数、独立挑战；当前所需路线就绪后不因另一条路线的验证码阻塞使用。Auto 在校园网内只准备和认证 Direct；校外允许保留 Direct 与 WebVPN 两套会话，已配置的校外域名直接选择 WebVPN，其余业务默认 Direct，并按域名回退规则记录当前网络可达性。

HAR 只包含 WebVPN，Direct 使用同一 SSO 解析与提交实现，真实双路线验收分别记录。原 HAR、验证码、Cookie、凭据与原始响应不进入仓库；只保存脱敏协议事实和合成回归用例。

## 逐操作基线矩阵

以下矩阵沿用[逐操作历史矩阵](general.md#逐操作历史矩阵)的取证说明：原始取证版本、换钉后的适用方式和重新核对要求以该节为准。

### 网关探测

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**不适用，没有校园探测。**示例：**`utils/net.rs` 目标为 `gw.buaa.edu.cn:80`。**决策：**严格使用该主机和端口；2026-10-28 起只尝试解析到 `10.0.0.0/8` 的 IPv4 地址（产品约束，两份参考均无地址过滤）。 | **旧版/示例：**不适用，此操作不是 HTTP。**决策：**不处理重定向或最终 URL。 | **旧版/示例：**不使用 Cookie 或凭据。**决策：**仅保留进程内探测状态。 | **示例：**先执行 `ToSocketAddrs`，再循环 `TcpStream::connect_timeout` 直到成功。**决策：**解析和全部地址尝试共用 500 毫秒总期限。 | **旧版/示例：**无请求头或正文。**决策：**只建立 TCP 连接，不发送 HTTP/TLS 数据。 | **旧版/示例：**不适用。**决策：**不使用加密或签名。 | **示例：**返回校园布尔结果。**决策：**任一 `10.0.0.0/8` 地址连接成功为 `Campus`，其他地址不尝试；普通解析、无地址、连接失败或超时为 `OffCampus`；仅内部/注入探测失败为 `Unknown`。 | **示例：**无缓存且每地址 500 毫秒。**决策：**产品合同收窄为一次总预算，并增加可注入时钟/探测器和进程内 3 秒缓存。 | **示例：**普通失败均返回 false。**决策：**`OffCampus` 按校外域名名单与运行时偏好选择，`Unknown` 使用功能的 `unknown_default`；探测本身不产生 CLI 失败。

2026-08-24 的确定性实现证据：`route_policy` 覆盖固定 500ms 预算、三种网络状态、显式策略不探测、
缓存过期和并发缺失时的单飞行为；`facade` 覆盖 facade 所有缓存、默认与功能策略、成功诊断及
缺少会话时零请求。CLI 二进制边界测试禁止 `main.rs` 持有配置、探测或解析器。这些测试不证明
实时校园网络可达性或任何业务端点结果。

### 双路线加载/保存/退出

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**远端注销为 `https://sso.buaa.edu.cn/logout`，持久化无 URL。**示例：**没有等价的双路线注销。**决策：**各路线使用转换后的 SSO 注销地址，存储操作仅在本地执行。 | **旧版：**先远端注销再清本地，不校验最终 URL。**示例：**不适用。**决策：**远端请求只做尽力尝试，不能单独授权删除持久化数据。 | **旧版：**`ModeScopedSessionStore` 按模式隔离认证/Cookie，但切换或重置会清理全部范围。**示例：**共享 `cookies.json` 与 `cred.json`，不是双槽位。**决策：**一个双路线快照，包含独立路线槽位和路线业务状态。 | **旧版：**settings get/put/remove，无 CAS。**示例：**分别截断写文件。**决策：**在同一锁内加载快照和修订；路线保存、聚合清理各执行一次完整快照 CAS。 | **旧版/示例：**JSON 持久化，本地操作无 HTTP 正文。**决策：**schema-v2 `session.json`，仅支持旧单路线读取；使用唯一原子临时文件和仅所有者权限。 | **旧版/示例：**不适用。**决策：**不为本地持久化臆造加密。 | **旧版：**用户名、用户资料、时间戳和 Cookie 记录。**示例：**Cookie 及凭据/令牌过期时间。**决策：**只持久化路线、过滤后的 Cookie 和时间戳，绝不保存用户名、密码、execution、challenge 或业务令牌。 | **旧版：**各存储有互斥锁但没有跨文件事务，重置会清缓存。**示例：**进程内原子单元，没有文件锁/CAS。**决策：**一个协调器拥有双路线快照和修订；冲突后不重新加载或采用外部修订；本地失效/注销时清理全部路线业务状态。 | **旧版：**远端错误仍清本地状态。**示例：**普通 I/O/解析错误。**决策：**陈旧 CAS 返回可重试的 `internal_error`，只清当前进程并保留更新后的两个槽位；聚合注销成功时只推进一次修订。

### 准备/登录（UBAA2 不支持交互验证码）

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**GET/POST `https://sso.buaa.edu.cn/login`，随后访问 `https://uc.buaa.edu.cn/api/login?target=...` 激活用户中心；冻结流程还可能出现 `config.captcha` 并读取 `/captcha?captchaId=...`。**示例：**只有 SSO `/login`，无等价验证码协议。**决策：**Direct 与 WebVPN 各自保留普通登录和激活顺序，明确不实现可选交互验证分支。 | **旧版：**手动解析绝对、协议相对、根相对和路径相对跳转，密码风险页最多继续一次；用户中心状态证明激活完成。**示例：**reqwest 自动跟随跳转，`verify_url` 为用户中心或网关根。**决策：**所有跳转锁定路线，并要求主机和最终用户中心地址通过白名单校验。 | **旧版：**按模式保存 Cookie，execution 仅是内存请求状态。**示例：**共享上下文 Cookie/凭据存储。**决策：**路线 Cookie jar 和临时 execution 独立保存，绝不持久化 execution 或交互验证材料。 | **旧版：**表单复制隐藏字段并增加 `username`、`password`、`execution`、`_eventId=submit`、`submit=登录`、`type=username_password`；旧验证码分支还会发送 `captcha`/`captchaResponse`。**示例：**同样的普通基础字段和风险表单。**决策：**只发送有证据支持的普通表单；含 `config.captcha` 的页面在取图或提交凭据前返回 `upstream_changed`。 | **旧版/示例：**表单 URL 编码。**决策：**保留隐藏字段语义和编码，不把表单值写入日志或错误。 | **旧版/示例：**无额外登录加密。**决策：**不增加；WebVPN 主机编解码属于独立连接证据。 | **旧版：**execution、`config.captcha {type,id}`、提示/错误文本和 `UserInfoResponse code/data`。**示例：**只说明 execution 和风险页标记，不支持验证码。**决策：**只公开稳定资料/错误 DTO，不公开挑战 ID、图片状态或验证字节。 | **旧版：**各路线后端通过自己的 Cookie 存储保留准备状态。**示例：**无验证码生成。**决策：**各路线只保留自己的 execution，不存在跨路线或跨进程验证状态。 | **旧版：**缺少验证码可能返回 captcha-required，错误凭据、风险页或激活失败有用户错误。**示例：**缺少 execution/服务器和登录失败错误。**决策：**任何交互验证标记都返回 `upstream_changed`，不重试或提示；普通认证、网络和解析错误保留稳定分类。

当前分类器还会拒绝额外的可见输入、`textarea`/`select`、冻结验证码字段名
`captcha`/`captchaResponse`，以及仅拒绝型 `config.*` 标记（`captcha`、`mfa`、`otp`、
`verification`、`verify` 或 `challenge`）。这是从冻结普通输入解析器导出的封闭世界安全边界，
可防止凭据被提交到未知验证界面，同时不声称这些新字段或标记属于协议。

### 用户资料

| 启动/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|
| **旧版：**用户中心激活属于登录流程，查询地址为 `https://uc.buaa.edu.cn/api/uc/userinfo`。**示例：**`api/user` 只激活用户中心并返回状态，不是同一资料查询。**决策：**在 facade 解析的路线使用旧版资料地址。 | **旧版：**SSO/最终 HTML 表示会话过期。**示例：**用户中心激活会跟随跳转。**决策：**WebVPN 转换和跳转始终锁定路线，不跨路线重试。 | **旧版：**当前模式的 Cookie/认证会话；`getUserInfo` 本身缺少所需本地预检。**示例：**共享上下文。**决策：**只使用所选路线槽位；通过校验/持久化登录得到的 `authenticated_at` 才是本地凭据，准备页 Cookie 不能授权业务请求。 | **旧版：**GET `/api/uc/userinfo`，无参数。**示例：**不等价的 GET `/api/uc/status?selfTimestamp=...`。**决策：**不能用状态接口替代资料接口。 | **旧版：**默认 GET。**示例：**默认 GET。**决策：**不臆造正文或请求头。 | **旧版/示例：**不适用。 | **旧版：**`code` 和可选 `data`；资料字段为 `idCardType`、`idCardTypeName`、`phone`、`schoolid`、`name`、`idCardNumber`、`email`、`username`。**示例：**返回原始状态文本，不等价。**决策：**稳定的可选资料 DTO，展示时遮罩敏感字段。 | **旧版/示例：**无资料缓存。**决策：**聚合 facade 负责路线解析和预检；没有有效路线槽位（包括准备后、登录前）时零 HTTP 请求。 | **旧版：**401/SSO HTML 清理当前本地会话；非零/缺少 data 为 `user_info_failed`。**决策：**缺少槽位返回 `authentication_required`；明确失效只清所选路线；瞬时 5xx/超时保留两条路线。

## 专项记录

### 认证安全修复复核

基线 `1e1729a1`，复核 `19c97520` 与未提交修改。冻结引用已通过 `just refs`：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`、buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。本轮没有学校请求。

旧版已读 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalWebVpnSupport.kt`、`LocalConnectionAuth.kt`、`LocalBykcApi.kt`、`LocalSigninApi.kt`、`LocalLibBookApi.kt`、`LocalYgdkApi.kt`、对应 feature 接口、DTO 及 commonTest BackendTest；签到另读 `SigninLoginNameSupport.kt` 和测试。另一来源已读 `src/api/{sso/auth,boya/core,class/core,class/data,user/auth}.rs`、`request.rs`、`store/cookies.rs` 和 API 模块清单。buaa-api 没有图书馆或阳光打卡等价协议，相关列不适用。

#### 实施前逐操作比较与决定

| 操作 | 引导 URL/service | 重定向与最终地址 | Cookie/Token 作用域 | 方法与参数 | 请求头/编码 | 加密 | DTO/解析 | 缓存/重试 | 错误与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| WebVPN 编解码与认证跳转 | 旧版网关为 HTTPS d.buaa.edu.cn；buaa-api SSO 使用同网关 | 旧 codec 原样保留不能解码的网关原生路径；支持 HTTP(S) 与业务自定义端口。仅在第二段确为加密主机后严格解析端口，禁止畸形端口降为默认端口。保留合法包装 SSO 解包后按 Direct 访问上游 | 旧版按路线；独立参考共享；保留 Core 路线隔离 | 不新增请求 | 保留原 path/query/fragment 编码及嵌套 service | AES-CFB key/IV 与 host 算法不变 | 不新增 DTO；网关原生路径不能误认成包装 | 原跳数和运行时不变 | 非法 wrapper/authority 在请求前拒绝；不把 codec 对自定义端口的支持等同认证端口许可 |
| BYKC CAS/token | 旧版 `/sscv/cas/login`；参考 SSO service 指向同址 | 两源 token 回调 `/cas-login`。先解析包括根相对/协议相对网关包装的实际目标，再检查 sso/bykc authority，最后提 token；普通业务相对路径沿解包后基址 | 原主 Cookie、路线内 token | 原 GET；业务 POST 参数不变 | 原 token 双头和正文编码不变 | 原 AES/RSA/SHA-1 不变 | token 非空、仅安全 bykc 主机；不从恶意包装路径猜来源 | 原登录锁/8 跳不变 | 非法目标零业务请求；回调 token 直接提取，不请求无必要的回调页面 |
| Signin loginName | 旧版 8346 `?type=jumpMyCenter`、8347 `app/user/login.action`；参考业务登录路径不同，沿既有真实证据裁决，登录端点不改 | 旧测试支持绝对、根相对、路径相对；旧 helper 明确支持网关根相对包装。先还原真实目标，iClass 自定义端口只允许 8346/8347，SSO 仅默认端口 | 原路线 Cookie、内存 id/sessionId | 原五个 login query，签到 POST 原值 | 原 sessionId/form 不变 | 无 | 原 loginName 与 DTO；不把 iClass 端口放行到 SSO | 原单飞、读取重试不变 | 写后 SSO 落点仍保守归 OutcomeUnknown；不复用发送前安全 authority 判定缩小未知结果范围 |
| LibBook CAS | 旧版 SSO service 为 `/v4/login/cas`；另一来源不适用 | 旧测试 query cas 与 `/h5/index.html#/cas/?cas=` 均支持。根相对包装先解包再验证 sso/booking 主机；保留 fragment CAS | 原路线内 bearer、Cookie | GET CAS，POST `/v4/login/user` 的 cas；其它参数不变 | 原固定 Header 与 JSON 不变 | 原预约 AES 不变 | cas query/fragment 解析不变 | 原登录锁/8 跳；写不重试 | 写后认证路径与 SSO 保持 OutcomeUnknown；严格 final 检查不能把异常落点变成功 |
| Ygdk OAuth/code | 旧版固定 app `/uc/api/oauth/index`，redirect 为 `https://ygdk.buaa.edu.cn/#/home`；另一来源不适用 | 冻结 BackendTest 证明 app→ygdk 回调，未证明其它中间主机。改为只允许 HTTPS app/ygdk 默认端口；d 只能是 WebVPN 外壳，内层同样验证；未知主机拒绝。code 只从 ygdk 根路径的 query 或 `/home` fragment query 提取 | 当前路线 Cookie；code 仅本轮内存，uid/token 仍受 generation 守卫 | 原 GET campusAppLogin，code 单次 URL 编码 | 不新增 Header 或正文 | 无 | 不增加 DTO；代码中的 app?code Mock 迁为冻结 ygdk 回调；保留 query/fragment 与百分号编码 | 原 10 跳和登录锁；禁止因未知目标改路线 | 这是安全收紧，不声称已证明真实完整链；未知中间学校主机会明确失败，需脱敏证据后才扩充 |

#### 审查更正与验证边界

Direct 收到合法 WebVPN 包装后解包并请求上游，不等于向网关发请求，不能据此判为路线越界。Signin/LibBook 非法 final URL 加成功 JSON 的反例证明 Core 分类回归，但生产 Reqwest 禁止自动重定向，普通 Location 无法直接伪造该 final；不将该反例夸大为已证明的远程利用。

Ygdk 旧实现无逐跳白名单不构成继续放行任意主机的理由。本轮只采用已经有证据的 app/ygdk 集合，未知目标失败关闭。真实双路线兼容性尚未验证。

Ygdk `extractOauthCode` 与业务 token 调用 Ktor `decodeURLQueryComponent()`，其 [官方 API](https://api.ktor.io/ktor-http/io.ktor.http/decode-u-r-l-query-component.html) 默认 `plusIsSpace=false`。Core 原来把单个 token 拼成表单查询，导致字面 `+` 变空格、`&` 截断。按冻结语义仅执行一次百分号解码，保留字面 `+` 和 `&`；交换 code 时由 URL serializer 重新编码一次，不进行二次解码。

复核还发现旧的 Core codec 在网关协议/密文前缀含重复斜杠时，过滤空段后仍用规范前缀 `strip_prefix`，失败便把业务 path 丢成空串。`/other?code=...` 因此可能被误识别为 ygdk 根回调。冻结 `LocalWebVpnSupport.kt` 过滤空前缀段但保留后续业务段；本轮沿用该可识别前缀语义，并准确保留主机段之后的原始业务 path。负例先复现 `Some(code)`，修复后必须为 None。网关原生路径继续原样保留。

Ygdk 的冻结 `resolveRedirectUrl` 明确按当前请求（包括 d 网关）解析根相对与路径相对 Location；因此保留当前 `base.join(location)`，不套用 Signin/LibBook 的“先解包业务基址”规则。Direct 拒绝未解包的网关 Location 是本轮显式安全收紧，旧 Ygdk 没有证明该混合路线正常行为；保留拒绝，真实兼容性待验证。该点与共享认证中已有证据的 Direct 解包 SSO 不同。

Ygdk 回调的根路径 query 与 fragment query 分别处理：存在根路径 `?code=` 时，无关 fragment 不改变 code；只有从 fragment 内取 code 才要求片段路由为 `/home`。先将 `/?code=...#section` 写为失败正例，再修正本轮把 fragment 条件施加到所有 code 的过度限制。

此前“主机大小写可绕过”的表述不准确：Rust `url` 会将 HTTP(S) 域名规范化为小写，增加大小写不敏感比较本身不能证明修复了一条可利用路径。保留对应边界用例，但实际缺陷依据是 userinfo、未声明端口、错误解包与提取顺序，不把大小写变体单列为已证安全漏洞。

写后判定还须覆盖 codec 拒绝异常网关的情况：Signin/LibBook 原先 `from_webvpn_url` 失败便回退原始 d URL，再配合成功 JSON 会误报成功。两个完整写链反例使用非法 HTTP 网关 final，证实最终写已发送一次却返回 success；改为解包失败、无法解析 URL 或解包后仍是网关时均返回 OutcomeUnknown。有效业务 false 与成功仍按原响应解析，未知结果不自动重放。该反例也只证明 Core/custom transport 分类边界，未证明生产 Reqwest 可收到攻击者任意 final URL。


#### 失败反例与确定性结果

以下反例均在相应生产修复前实际失败，随后复跑通过：

- 网关 `/wengine-vpn/cookie` 与 `/por/login_psw.csp` 被错误按包装协议解析。
- BYKC 根相对恶意 wrapper 被借用当前 bykc 主机；同主机非 `/cas-login` 页面 token 被接受。
- 普通 `../../../cas-login` 在首次 wrapper 修复后被误拒绝；恢复按解包后的业务目录解析。
- SSO 错误借用 iClass 的 8346/8347 端口许可。
- Ygdk 未知主机、未证回调路径和 wrapper 内层非法端口被放行；token 字面 `+` 被转为空格、`&` 截断。
- wrapper 前缀重复斜杠丢弃业务路径；根路径 query code 被无关 fragment 误拒绝。
- Signin/LibBook 写后非法网关 final 加成功 JSON 返回 success；修复后 OutcomeUnknown，写只发送一次。

最终聚焦命令 `cargo test --locked --offline -p ubaa-core --features test-contract --lib --test connection --test bykc --test signin --test libbook --test ygdk`：Core lib 394 通过、1 项按已有标记忽略；connection 9、BYKC 21、Signin 10、LibBook 26、Ygdk 5 全通过。BYKC 双路线测试检查实际请求 host、final/Location token 提取及不额外请求 callback。Ygdk 双路线测试检查未知主机请求前拒绝、WebVPN root-relative wrapper、code 单次解码后重新编码与路线固定。BYKC full_detail 夹具原先人为在 `/sscv/cas/login` 拼 token，已改成冻结证实的 `/cas-login`，未放宽生产回调规则。

最终 `cargo clippy --locked --offline -p ubaa-core --all-targets --features test-contract -- -D warnings` 与 `git diff --check` 通过。补充的写后无法解析/原生网关分支测试已聚焦复跑通过。

本轮只运行本地确定性协议测试。真实账号、学校网络与 Direct/WebVPN 完整实时链均未运行。仓库完整门禁由主任务统一执行，其结果独立记录。

Bridge 的两个共享 BYKC 夹具也曾在 `/sscv/cas/login` 拼接 token，导致严格回调校验后 29 项测试无法进入业务步骤。夹具改为同路线的 `/cas-login` 后，Bridge 157 项通过、2 项按已有标记忽略；业务资格、缓存失效与只发送一次的原断言全部保留。

### SSO 传输协议与 UC 激活链对照

日期：2026-10-21。实现前记录。基线 `01fd09b4`。

#### 来源与冲突决策

- 冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`：`shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt`（表单、跳转、Cookie/会话、UC 状态）、`LocalWebVpnSupport.kt`（网关编解码）、`api/auth/AuthApi.kt`（接口）、`model/dto/UserInfo.kt`（DTO）及 `commonTest/.../api/LocalAuthServiceBackendTest.kt`、`LocalCookieStoreTest.kt`、`LocalWebVpnSupportTest.kt`。
- 冻结 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`：`src/api/sso/auth.rs`、`api/user/{auth,opt}.rs`、`api/aas/core.rs`、`request.rs`、`store/{cookies,cred}.rs`、`error.rs`。其 WebVPN 主要服务 ClassAPI，不是 UBAA 的全请求路线，不能照搬该 service。
- 用户 UC HAR 共 131 请求：#24 密码 POST 返回302；#71 status仍为10600；#72 UC激活跳到 HTTP SSO，#74 HTTPS SSO 返回UC ticket回调，#75去ticket，#76落地；#125/#129 status为0。BYXT HAR共90请求：#0根入口指向HTTP；#1浏览器307升级HTTPS；#26 SSO返回带ticket教务回调；#38/#49 currentUser的code为字符串0，数据在datas。独立解析只输出地址主机/路径、参数名和业务code，不读取到日志的实际凭据或资料。
- 冻结旧版 UC 激活依赖 Ktor 自动跳转，独立 Rust 参考依赖 Reqwest 自动跳转；两者没有覆盖本次 HTTP SSO Location 的显式升级。UBAA2 已手动跳转、禁用 Reqwest 自动跳转、最终核对 UC status，不能直接套用 Kotlin 缺陷结论。UBAA2 当前会原样请求 HTTP SSO，Secure Cookie 因协议不匹配而不发送；WebVPN 包装也会保留 HTTP 上游段。
- 决策：仅对跳转目标中默认 HTTP 端口的精确 `sso.buaa.edu.cn` 主机升级 HTTPS，网关包装先还原、核对目标后按固定路线重包；保留原始查询编码，不改 service 值和其他主机协议。主登录与业务门户既有白名单、跳转上限分别保留。依据是实际浏览器成功链，优先于冻结源未覆盖的旧行为。2026-10-30 起，认证重定向同时拒绝用户信息和未声明端口；SSO 只接受默认端口，iClass 仅在自身主机允许来源已声明的 8346/8347，通用 WebVPN codec 继续支持业务自定义端口；这是针对 Location 注入与网关绕过的安全收紧，若与未覆盖的旧端点行为冲突，必须先补充来源证据再放宽。

#### 逐操作对照

| 操作 | bootstrap/service 与最终 URL | 方法/参数/头/body | Cookie、凭据与加密 | DTO/解析、缓存/并发与错误 |
| --- | --- | --- | --- | --- |
| 准备普通/交互式登录 | 两份源都从 HTTPS SSO `/login` 开始；旧版在已有SSO状态时激活UC。UBAA2保留该行为，不能把302本身判为已完成登录。 | GET；无凭据body；UA沿现有传输，不增加fingerprint请求。 | 旧版Cookie按模式隔离并检查Secure/domain/path；buaa-api共享上下文Cookie；UBAA2保持独立RouteClient与session修订检查，不复制另一槽。 | 旧版解析execution和验证码；独立参考不支持等价交互式流程。保留现有Plain/Image/Ready分类，验证码仍按原挑战处理。 |
| 密码提交及后续SSO跳转 | SSO `/login`；六字段与HAR及两源相同。只升级跳转目标的SSO传输，不修改嵌套service。 | POST表单URL编码：username、password、submit、type=username_password、execution、_eventId=submit；旧版允许既有表单附加字段，UBAA2继续保留；Content-Type为application/x-www-form-urlencoded。 | 密码沿TLS原表单提交，不新增密码加密或指纹。WebVPN主机编码沿冻结AES-CFB、key/IV `wrdvpnisthebest!`，不改算法或常量。 | 旧版识别登录错误和密码风险继续；独立参考宽松判HTTP成功。UBAA2保留原错误分类、一次风险继续与10跳上限，最终仍需UC校验。 |
| UC票据交换 | 旧版/UBAA2为 `https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin`；独立参考使用未编码target字符串。HAR证实须再经过SSO(service=UC回调)、ticket回调、去ticket跳转。UBAA2保留既有编码与起点。 | 每跳GET、保存响应Cookie后再发下一跳；不重复密码POST。Location使用URL解析，相对地址按当前响应解析，不对query重新解码/编码。 | Secure Cookie只在HTTPS发送；网关路由下Cookie属于网关并按路径匹配，不外泄到直连；固定路线不随UI策略切换。 | 旧版自动链无显式预算，UBAA2已有10跳预算及缺失Location/服务端错误处理；保留。落地HTML200不能替代最终status。 |
| UC状态与资料 | `/api/uc/status`、`/api/uc/userinfo`沿旧版；独立参考status带selfTimestamp并返回原文，不直接采用其弱校验。 | GET；旧版status有Accept及X-Requested-With，UBAA2当前请求头保持，本次不引入未经反例证明的头变更。 | 以当前路线会话发请求；只有验证成功后保存认证时间与Cookie，失效清理和CAS修订语义不改。 | 旧版code=0且data有身份信息；HAR10600表示尚未激活。UBAA2继续使用白名单UserProfile和稳定错误码，不导出完整个人资料。 |
| 教务及共享业务CAS跳转 | BYXT `/jwapp/sys/homeapp/api/home/currentUser.do` 与现有CAS入口保持；独立参考`api/aas/core.rs`使用homeapp service。HAR中的byrhmhsy是浏览器门户入口，不替换已有homeapp service。其他业务沿现有逐操作来源记录。 | 共享GET跳转只在精确SSO目标上升级；已有业务headers/body/请求参数保持。 | 同一运行时Cookie和固定模式不变；仍由相应业务入口验证业务会话，不把UC成功等同所有业务成功。 | 当前UBAA2仅校验HTTP200，冻结旧版只校验JSON形状，独立参考只校验落地URL；三者均未充分验证currentUser业务状态。HAR #49已核实code为字符串0、datas为非空对象且userId为字符串。新增精确homeapp currentUser最终地址、code=0及非空userId校验，异常响应归为UpstreamChanged，不伪造成功、不推断未知业务码含义；现有本科失败后GSMIS探测保持。共享业务跳转8跳上限、主机白名单与缓存不变。 |

其他业务的请求/DTO/签名常量详见既有 [source-parity.md](../README.md) 对应操作，本次不改业务服务参数、数据解析或缓存策略。用户更新指令明确排除中转；不修改旧配置或凭据。

补充边界：发现网关包装目标可以绕过原白名单，先用合成包装未登记主机/非HTTP协议证明失败，再将既有白名单应用于解包后的目标。范围仍是已有白名单，不新增上游主机。

### 交互验证码整合前来源与生命周期约束

日期：2026-10-02，起点`4fda272c`。当前冻结旧版`1f4b8f84`的LocalConnectionAuth/AuthApi、验证码DTO与后端测试，相较旧专项`6e75e120`内容未变化；旧AuthViewModel只增加课表账号关联，LoginScreen增加离线课表入口。当前示例`a63712fa`的SSO、request和store相较`efb7976`未变化，仍无同协议图像验证码实现。逐操作URL/service、跳转、Cookie、方法/八字段/编码、crypto、解析、生命周期及错误对照完整沿[敏感显示专项](#验证码与门锁信息逐操作来源与专用显示边界)。不能从示例普通SSO推断验证码字段。

旧macOS worktree未提交Core候选已单独运行19项交互认证测试通过（`<private-evidence>/legacy-tmp/ubaa-existing-interactive-core-20261002.log`），这是移植前专项证据，不是本候选已可用。原目录和未提交内容保持原样。接续采用受限PNG/JPEG解码后的RGBA、opaque挑战和单调时限；提交前按旧版GET复核execution/id，轮换时返回新挑战且零POST，未经真实来源裁决不得跳过此GET。

本轮额外整合约束：本地首页仍可显示缓存，验证码不能授予写资格或触发后台自动提交；已有会话恢复保持非交互；仅用户手动登录进入交互链。原位登录须保留页面与查询，网络/校验期间阻止旧读取和写流程，关闭弹窗/退出/账号变化/失效/后台须撤销当前挑战并释放帧。最终身份核对、安全保存、本机账号绑定及恢复状态复用当前登录收尾，不能回退到旧分支缺少缓存接线的实现。

CLI普通登录、默认路线解析和其他业务合同保持；只有用户明确选择才改变实际默认策略以使用已就绪路线。当前不在校园网，真实验收使用WebVPN，不运行Direct矩阵；真实验证码出现时不自动解答或提交未经确认的答案。旧方案的新手动上下文只清当前实例所属的旧本地会话槽，不远端注销、不修改其他配置目录。


明确选择Direct/WebVPN并点击登录已表达该路线的使用意图。旧LocalConnectionAuth按所选模式登录，另一模式失败不应阻断已选模式；当前新交互若只有另一条路线需验证码，原实现仍停留登录页，新行为回归已RED。裁决：已选固定路线就绪后通过同一个continue接口进入首页，不改策略、不重发认证；Auto保留原解析与明确选择规则。此项只改变已验证结果的宿主接续，不改九列中的学校请求或挑战消费。

### 验证码与门锁信息：逐操作来源与专用显示边界

日期：2026-09-15。旧版固定 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，示例固定 `efb7976bf513f38364b88aeb83d704586cff9b2a`。当前生产源码索引以 `3966001e02db960cacf3b09945c503c73232d07a` 为基线；实施前继续运行纯校验 `just refs`。

状态：Task3E 已接入验证码专用 Core/Bridge/App/Host/UI 候选，正在执行本地合成验证；门锁显示仍待独立批次。未取得真实验证码或门锁显示验收。用户要求完整恢复旧版按钮功能，专用的短期显示能力属于本专项所需修复；不因此开放通用原始响应、上游鉴权材料或真实学校写入。

#### 已作出的实施裁决

1. 允许通过独立 `facade`/typed Bridge 能力显示旧版已证的验证码图像，以及登录会话返回的门锁密码/预约摘要。只在用户打开的当前页面保留；不得放进普通FeatureField、FeatureResult、AppSnapshot、配置、Session、诊断、JSON或日志。服务器challenge id/execution、URL、Cookie/token/sign/密钥继续完全留在Core。
2. 旧非交互prepare/login和CLI仍在验证码前拒绝，不取图、不接受答案。新增交互入口使用Core持有的路线内不透明句柄；图像只输出已解码的受限像素帧，答案只用于本次精确表单。两路线独立，一路成功时保留就绪槽位和资料；可继续完成另一路，也可明确使用已就绪连接，不能重发已完成路线或偷偷复用密码。
3. 验证码初版保留旧提交前 GET。2026-11-06 的真实观察已证实 GET 会轮换挑战，当前按[来源裁决](../decision-log.md#2026-11-06sso-图像验证码按当前准备状态直接提交)直接提交当前准备页；本文下方保留初版对照与测试登记，现行行为见[静默处理](#sso-图像验证码静默处理)。
4. 验证码本地最长显示/回答时间120秒；编码图片最大512KiB，只解码现有锁定image依赖支持的JPEG/PNG，宽高各不超过1024、总像素不超过1048576、RGBA不超过4MiB。先检查资源边界再解码，不从JPEG前缀推断真实图片格式。这些是本地资源/显示约束，不是上游协议、TTL或学校规定。
5. 门锁从已证的qrCode字符串取值，保留前导零；dueDate原文字段及旧页九个预约字段均允许仅在专用视图显示，其中tradeNo映射为reservationReference、orderName仍标“预约人”，不假称当前本人。七个场所/日期字段见下表。普通订单DTO、CLI和通用JSON仍不得包含交易号或这些敏感显示字段；不得把password猜作qrCode别名。
6. 门锁第一次打开fresh读取，手动与30秒刷新共用单次在途请求。成功显示最多30秒，到期先移除旧码再刷新，失败不保留旧码。dueDate只显示上游原文，不从设备时区推断绝对失效时间，不声称30秒是学校密码更新周期。
7. 两类敏感页面返回、销毁、账号/会话/路线变更及hidden/paused/detached时立即清显示和答案、撤销句柄，迟到结果不能重新出现；inactive本身不等于窗口不可见。取消标记不得排队等待Bridge网络大锁。恢复可见后重新准备/打开，不恢复旧帧或旧码；不用剪贴板、分享、磁盘或网络图像缓存。
8. 类型不实现serde/toJson，Debug/Display/toString只输出安全状态；内存清理只承诺释放引用和缓存，不声称已物理擦除Dart/FFI/图形系统所有拷贝。门锁响应不记录整包body_sha1，也不记录低熵码、图像或答案的摘要。
9. 所有新增接口仍属于未发布候选Bridge10，合同另设敏感显示专节，与图书馆/博雅非敏感扩展分别说明。CLI schema10、Session2、配置1、现有available摘要和WriteCoordinator权威不变。若候选先行发布，后续新增合同再独立升版；当前没有发布行为。

部分就绪的本地交互补充：若当前固定策略指向尚未完成的路线，“使用已就绪连接”必须明确显示将使用哪条就绪路线，并在进入主页前让后续读取实际采用该路线；原本匹配就绪路线的策略保持。Auto继续必须先沿现有解析规则确认其选中的路线已就绪，成功时保持Auto。若Auto选中未就绪路线，保持原策略、就绪槽位和交互上下文，返回可恢复提示；UI另提供明确“改用直连/WebVPN并继续”的操作，只有用户点击该操作才保存相应固定策略并继续。用户也可补全另一条路线后继续保持Auto。不得打开全局ready-route fallback、引入隐藏路线覆盖，或在不可读取时仍显示进入成功。

固定策略的改变来自这次明确继续操作，不调用旧prepareLogin重新准备两路或重发已完成认证；策略保存失败留在登录交互并如实反馈，不伪造ready或资料。须用两个方向的固定策略不匹配、Auto解析选中就绪路线、Auto解析选中未就绪路线后显式切换、零就绪及保存失败的合成行为测试验证，并保留进入后实际facade读取成功、认证POST计数不增加的断言。该Auto限定来自本批扩展用例的真实失败及现有SAFE_DEFAULT，详见[决策记录](../decision-log.md)中“Auto部分就绪继续的可用性”条目。

协议证据不足只限制相应分支，不阻止已有冻结实现支持的图像刷新、精确提交、门锁文本和短期生命周期实现。必须先观察合成行为RED，再实现与独立审查；真实无挑战、无有效预约或锁屏都不能记作功能通过。

#### 可核查的源码索引


路径均相对本工作区；行号属于上述冻结提交或当前基线。

| 代号 | 文件与行号 | 本次用途 |
|---|---|---|
| A1 | `examples/ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/auth/AuthApi.kt:41-55,98-117` | 本地认证接口明确有 `captcha` 与 `execution` 入参 |
| A2 | `examples/ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Auth.kt:15-20,58-76,103-112` | 请求、验证码与预加载 DTO；relay 的 `clientId` 不能类比成上游参数 |
| A3 | `examples/ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt:402-448` | GET 登录页、预加载检测、取图与结果 |
| A4 | 同文件 `451-550` | 提交前 GET、外部 execution 优先、验证码分支、激活与状态验证 |
| A5 | 同文件 `624-746` | 图片 GET、JPEG 前缀、跳转、错误、旧版 WebVPN 后额外 Direct 登录 |
| A6 | 同文件 `831-974` | `config.captcha`、execution、普通/验证码表单、错误与风险页解析 |
| A7 | 同文件 `98-116,150-196,232-240,297-316` | 路线 Cookie 存储、匹配、客户端重定向与超时 |
| A8 | `examples/ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/LoginScreen.kt:133-157,191-197,297-331` | 图片/答案/点击刷新/提交使能 |
| A9 | `examples/ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/AuthViewModel.kt:87-190` | preload、刷新、提交及错误恢复的实际实现 |
| A10 | `examples/ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalAuthServiceBackendTest.kt:361-402` | Direct 要求验证码的 Mock；图片内容是四个伪字节，不是有效 JPEG |
| W1 | `examples/ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalWebVpnSupport.kt:8-27,68-83,98-105` | WebVPN 包装及 Cgyy 固定 Direct 特例 |
| E1 | `examples/buaa-api/src/api/sso/auth.rs:9-92` | 普通 SSO/VPN URL、固定表单、风险继续与成功判据；没有验证码分支 |
| E2 | `examples/buaa-api/src/api/sso/mod.rs:20-24`；`src/context.rs:11-14,61-66,185-188,231-235,267-283` | 所有分组共享 Context、Cookie 与凭据；不等价于两条隔离 runtime |
| E3 | `examples/buaa-api/src/request.rs:7-22` | UA、reqwest 默认跳转、Cookie provider；不可复制关闭证书校验的配置 |
| E4 | `examples/buaa-api/src/store/cookies.rs:130-176,215-269,297-321`；`src/store/cred.rs:13-39,91-157` | Cookie/凭据可序列化存盘、原子更新与过期标记；没有挑战存储协议 |
| E5 | `examples/buaa-api/src/error.rs:13-19,57-98,136-149,185-193` | Auth/Network/Parse/Server 分类及可能记录 raw 的路径；无等价 CLI exit 合同 |
| L1 | `examples/ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/CgyyApi.kt:33-39,81-83,133-135` | 无参数 `getLockCode`；relay 路径不是学校上游 URL |
| L2 | `examples/ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/Cgyy.kt:93-118,136` | 原始订单 DTO 与不透明 `CgyyLockCodeResponse.rawData` |
| L3 | `examples/ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalCgyyApi.kt:207-243,448-455,636-805` | 主会话预检、用户级 client、GET 锁码、业务认证/请求/错误与一次重试 |
| L4 | `examples/ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalCgyySigner.kt:9-53` | 固定 app-key、MD5 常量、字段过滤和 GET nocache |
| L5 | `examples/ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/cgyy/CgyyLockCodeScreen.kt:38-53,62-146,177-244` | 门锁显示、30 秒刷新及实际字段解析 |
| L6 | `examples/ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/cgyy/CgyyViewModel.kt:140-151,398-420`；`composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/CgyyViewModelTest.kt:164-203,404-407` | 加载标记、重复请求防护、缓存及失败保留旧值 |
| L7 | `examples/ubaa_old/composeApp/src/commonTest/kotlin/cn/edu/ubaa/ui/CgyyScreenLogicTest.kt:44-92` | `qrCode/dueDate/orderView` 与仅未来预约摘要两个正例 |
| L8 | `examples/ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalCgyyApiBackendTest.kt:442-443,466-480`；`shared/src/commonTest/kotlin/cn/edu/ubaa/api/CgyyApiTest.kt:133-156` | `password` 字段仅验证原样透传，与 UI 所读字段不同 |
| C1 | `crates/ubaa_core/src/upstream/mod.rs:27-89`；`src/auth/mod.rs:19-95,98-170,186-266` | 当前封闭交互拒绝、临时登录状态与普通认证链 |
| C2 | `crates/ubaa_core/src/facade/auth.rs:15-80,88-102,153-181`；`src/domain/auth.rs:88-160` | 双路线固定顺序与旧序列化 envelope |
| C3 | `crates/ubaa_flutter_bridge/src/api/client.rs:17,178-224,297-339,430-455` | 当前 Bridge v9、认证类型、整次异步锁与重开 |
| C4 | `crates/ubaa_core/src/features/cgyy/read.rs:92-95`；`parser.rs:701-713`；`crates/ubaa_flutter_bridge/src/api/read/mod.rs:600-603` | 门锁只返回 data 非空布尔；当前时区转换仅服务其它 Cgyy 日期逻辑 |
| C5 | `crates/ubaa_core/src/features/cgyy/auth.rs:20-74,77-143,150-191`；`http.rs:14-80,83-119,170-183` | 当前路线认证、WebVPN Cookie 同步、请求与响应摘要日志 |
| C6 | `packages/ubaa_app/lib/src/bridge/read/cgyy.dart:159-177` | `available` 被投影为“门锁可用”和普通 `FeatureField` |
| P1 | `docs/protocol/source-parity.md:72-76,95-104`，读取基线版本 | 现有 WebVPN/准备登录九列矩阵 |
| P2 | 同文件 `594-609`，读取基线版本 | 现有 Cgyy 只读九列、3xx 规则及脱敏 WebVPN 观察记录 |
| P3 | `docs/contracts/auth-and-user.md:8-24,32-45`；`connection-and-session.md:26-34`，读取基线版本 | CLI v10、Session v2、交互拒绝及退出分类 |
| P4 | `docs/contracts/flutter-bridge.md:8,228-234,282-297`，读取基线版本 | 验证码材料禁曝、交易号禁曝、门锁仅 available |

对固定 `examples/buaa-api/src` 搜索 `captcha|venue-zhjs|cgyy|orders/lock/code` 无匹配；SSO 模块只声明 `mod auth`。下文“例无”均表示该操作在固定示例中没有同协议实现，九列都不能借用其它模块的 URL、DTO、加密、缓存或错误。示例普通 SSO 的有限等价性只在明确标出的单元格中使用。

#### 登录验证码：逐操作九列


以下每行分别说明与 P1 已有九列的继承和新增。旧非交互合同继续保留；本页裁决只为独立交互入口新增专用边界。

| 操作 | CAS/bootstrap 与 service | redirect/finalURL | Cookie/session | HTTP 与精确参数 | Header/body | crypto 常量 | DTO/parser 类型 | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| A：准备与检测 | 旧 A3/A5：GET `https://sso.buaa.edu.cn/login`，无 service；WebVPN 经 W1 包装。例 E1 普通 Direct 相同，但 VPN 明加网关登录 service，不是旧版同一选择。继承 P1 的旧版 URL/路线，不借示例 service。 | 旧 preload 遇 3xx 转用户中心激活/校验；普通登录页要求 200，旧流程无逐跳 host 白名单。例 reqwest 跟随跳转并用 uc 或网关根作已登录判断。继承当前有界、路线内解析与既有允许主机；不扩大白名单。 | 旧 A7 当前 mode 的 jar；execution 在返回 DTO 中。例 E2/E4 共享 Context，非路线隔离。继承当前两 jar、准备页 Cookie 不等于已认证槽位。新增挑战只在当前 Core 实例/路线/准备代次内存。 | 旧空正文 GET，无 username/captcha/body；响应提取 execution 和 `config.captcha`。例只取 execution。新增仅增加页面分类，不增加探测 URL 或 GET 参数。 | 旧无 CAPTCHA 专用 Header；例自带 E3 UA。继承现有请求默认值，不借示例 UA，不新增 Origin/XHR。 | 两源普通 SSO 不加密账号密码；WebVPN 仅 W1 路线包装。继承 P1：`wrdvpnisthebest!`、AES-128-CFB 与既有 URL 编解码；不借 Cgyy AES/滑块算法。 | 旧 A6 正则只识别 `config.captcha = { type: '<值>', id: '<值>' }` 的顺序形状；A2 有 string id/type/imageUrl/base64Image。例无验证码 DTO。新增只接受来源支持的 `type=image` 与唯一非空 id/execution；其它交互仍拒绝。对外不传原始 id/execution/HTML/URL。 | 旧 UI 可并发 launch，无代次校验。例无挑战状态。继承当前每路线 AuthWorkflow；新增每路线单个准备代次，替换前作废旧 handle，禁止跨路线借用。 | 旧非 200 preload 甚至可返回“不需要验证码”；缺图可保留要求状态。例只给缺 execution/Server 错误。新交互入口返回明确 required 或安全失败；旧 API/CLI 保持 `upstream_changed`、exit 6，且仍零取图。 |
| B：图片加载 | 旧 A5：路线转换后的 `https://sso.buaa.edu.cn/captcha`，无 CAS/service。例无。新增沿用该固定地址，宿主不提供 URL。 | 旧 shared client 可自动跳转，没有 CAPTCHA 终点白名单。例无。新增本操作只接受同路线还原后 SSO `/captcha` 的有效图片终点；未知跳转失败关闭；现有 SSO 跳转规则可复用，不由图片失败扩充主机。这是较旧版更窄的产品边界，未声称已证明真实图片重定向链。 | 旧与准备请求共用当前 mode Cookie。例无。继承当前 runtime jar；新增 handle 校验在请求前进行，图片回复后再核对代次。 | 旧精确 GET `/captcha?captchaId=<从页面提取的id>`；不带答案、execution、clientId、nonce 或刷新 timestamp。例无。新增仍只有 captchaId 一个 query 值，使用有界 URL 构造；不生成上游挑战 ID。 | 旧空正文，无专用 Accept；只要求 HTTP 200 就读 ByteArray，再硬编码 `data:image/jpeg;base64,`。例无。新增不照抄伪 MIME，不将 HTML 或畸形字节交给界面。 | 旧仅 Base64 展示编码，不是验证码加密。例无。新增无签名/解密，不复用研讨室预约滑块求解器。 | A10 的响应 Content-Type 标 JPEG，但四个伪字节只测试前缀。新增依据实际字节受控解码，返回 RGBA 帧或确认格式的内存图片；格式白名单是本地解码支持范围，不是上游必定 JPEG/PNG 的事实。未知格式返回安全失败。 | 旧无 TTL 或图片结果单飞证明。例无。新增一 challenge 一次取图、可取消的显示生命周期、编码长度与解码尺寸上限；不使用 URL/file/image 全局缓存。 | 旧非 200 返回 null，异常转用户错误；没有正确图像解码的测试。例无。新增保留“需要验证但图片加载失败”的状态，允许用户刷新，禁止因此提交空答案或自动改为普通登录；旧 CLI 不走此操作。 |
| C：点击刷新 | 旧 A9 `refreshCaptcha()` 实际重跑 `preloadLoginState()`，即 A→B；没有独立 refresh 上游端点。例无。新增仍使用同一组已证 URL/service。 | 继承 A/B 对各自终点的规则；旧没有刷新特例，例无；新增不因刷新重选路线。 | 旧同 mode jar。例无。继承同一路线 jar；新增先作废旧 handle/答案，再取得新 execution/id，禁止拿新图配旧 execution。 | 旧 GET `/login` 后按新 id GET `/captcha`；不是对原图 URL添加时间参数。例无。新增不带 username/password/答案，不发送登录 POST。 | 继承 A/B 的空正文及默认 Header，例无；新增不假定 Cache-Control/Referer 参数。 | 继承 A/B；无额外 crypto，例无。 | 旧返回可选 captcha/execution，刷新回调没有清空已有答案，且无类型/代次验证。例无。新增刷新成功替换整个 typed challenge；答案清空；用户名、密码和记住密码选项保留。 | 旧 isRefreshing 只影响按钮，后端无完整防重/迟到响应守卫。例无。新增每路线 single-flight，第二次刷新可替换或拒绝；较旧回复永不覆写新挑战。 | 旧刷新失败保留旧 challenge 及答案并显示错误。例无。新增显示安全错误并保持旧挑战作废，显式可重试；不恢复旧答案、不自动 POST。旧 CLI 无此操作。 |
| D：提交答案与恢复 | 旧 A4 每次 login 先 GET `/login`，再 POST 同地址；成功后 UC_ACTIVATE_URL 与状态/资料查询。无新 service。例 E1 只有无验证码普通表单。继承已证登录/激活地址。 | 旧 A5 手动跟随任意 3xx，风险继续最多一次；最终 URL 的 exception.message/错误 HTML 会失败。例以 HTTP success 为主要成功判据。继承当前有界路线跳转、一次风险继续及用户中心校验，不采用“200 就登录成功”。 | 旧优先使用调用者 execution，获取新页面后未验证 id/execution 与答案一致。例无对应关联。新增 opaque handle 绑定同实例、同路线、同准备代次及 jar；另一条已登录路线保持有效，禁止复制 Cookie 或答案。 | 旧验证码 POST 精确八字段：`username,password,captcha,captchaResponse,execution,_eventId=submit,submit=登录,type=username_password`；两答案值相同，无 captchaId/clientId。例只有六个普通字段。新增仅发上述字段，不把普通隐藏字段无差别并入验证码表单。提交前 GET 的轮换问题见下文，不能忽略。 | 旧 `FormDataContent`，当前与例皆 `application/x-www-form-urlencoded`；无 JSON。新增答案仅出现在本次请求表单，不进 URL/Header。 | 两源普通 SSO 均无额外密码/答案加密；新增无 AES/RSA/signature；继续既有 WebVPN 编码。 | 旧未输入答案返回 `CaptchaRequiredClientException(captcha,execution)`；POST 后主要按通用错误/剩余 execution 判断失败。例无 CAPTCHA 结果类型。新增结果区分等待输入、需重新准备、已认证和安全失败；没有证据时不宣称“验证码错误”与“账号错误”可准确区分。 | 旧 WebVPN 成功后另试 Direct SSO，失败吞掉。例无对应双路线挑战。继承当前 Direct→WebVPN 独立编排，绝不复制旧额外 Direct 副作用。handle 一次性消费；提交/刷新互斥；不保留密码供后台自动重放。 | 旧缺答案是 CAPTCHA required，其它原文错误经包装；例 Server/Network/Parse 且无 CLI exit。新交互结果可以要求重新输入，但未知交互仍 upstream_changed；认证/网络/解析使用现有稳定码。旧序列化 DTO 与 CLI exit 0/2/3/5/6/7不变。 |

##### 不能略过的冲突

1. **提交前 GET 与旧 challenge 关联**：A4:459 再次 GET `/login`，A4:475-489 却优先用调用者旧 execution；该次新 GET 的 captcha id 是否相同、旧答案是否有效，没有成功提交/刷新轮换测试。最保守方案保留 GET；若其 execution/id 与 handle 绑定值不同，就返回新挑战并且零 POST。若 GET 每次都轮换，这个保守方案会一直要求新图，必须拿适用上游证据裁决是否允许直接消费 prepared challenge。不能凭普通 Core 已缓存表单就声称 CAPTCHA 可省略这一步。
2. **JPEG 不是已证实际格式**：A5:629-635 无 Content-Type 或 magic 校验；A10:384-402 是假字节测试。可做受控字节解码和未知格式拒绝，不能把旧硬编码当真实 JPEG 证据，也不能自动支持任意 SVG、脚本或未知验证码 type。
3. **图片跳转白名单**：旧 A5 使用 followRedirects 的 shared client，没有图片专用终点约束；当前认证白名单不自动证明任何新图片主机。先只允许来源中的 SSO `/captcha`，实际跳到新主机时应留 gap，不能加猜测的 CDN。
4. **例的 VPN service/共享存储与旧版不等价**：E1:24 的 `service=https://d.buaa.edu.cn/login?cas_login=true`、E2/E4 共享 Context 不用于挑战路由。E3:18 与 Context 默认值存在关闭证书检查的组合，绝不复制。
5. **旧刷新恢复并不安全完整**：A9:124-141 不清答案，异步回复没有代次守卫；这证明旧体验有刷新入口，不证明可继续复用旧答案或旧挑战。新方案必须显式收窄。

#### 研讨室门锁：逐操作九列


P2 中“站点”和“锁码”的九列可以复用既有请求链；本专项新增的是最后一层敏感显示投影与生命周期。为避免“认证成功”掩盖过程，以下将 bootstrap、WebVPN Cookie 同步、业务登录、锁码读取和界面刷新分别列出。

| 操作 | CAS/bootstrap 与 service | redirect/finalURL | Cookie/session | HTTP 与精确参数 | Header/body | crypto 常量 | DTO/parser 类型 | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| L-A：业务 SSO 引导 | 旧 L3:754 GET `https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin`，无显式 service。例无。继承 P2 同地址，不使用 relay `/api/v1/cgyy/*`。 | 旧 followRedirects=true 且固定 Direct，W1:105 原样 URL。例无。继承已有 Core 当前路线的有界跳转及 SSO/Cgyy 主机规则，保留 P2 已记录的旧版路线冲突；不恢复 WebVPN 偷走 Direct。 | 旧 L3:747-764 用 Direct jar 取得 `sso_buaa_zhjs_token`。例无。继承当前路线 jar 与已证 WebVPN 适配；不得复制另一路线 Cookie。 | 旧仅 GET，无业务参数/正文；例无；继承。 | 旧仅客户端默认 Header；这里不是 `/api/login` 的签名请求。例无。继承已有 bootstrap 请求，不把 business 头一概加给 SSO。 | 无 Cgyy 业务签名；WebVPN 包装继承 P1/W1。例无。 | 旧读 Cookie，不产出用户锁码 DTO。例无。继承：SSO Cookie 内存进入下一步，宿主不可见。 | 旧 client 按用户名缓存、业务登录 Mutex。例无。继承当前路线 token 单飞；不为显示页另建认证客户端。 | 缺主会话零业务请求；无 SSO Cookie 为认证失败。例无。继承现有用户中心失效仲裁和稳定错误；不记 raw URL/Cookie。 |
| L-B：WebVPN Cookie 同步 | 旧/例均无该同协议步骤；来自 P2:607 已提交脱敏观察，当前 C5 实现 `https://d.buaa.edu.cn/wengine-vpn/cookie`。仅 WebVPN 且当前 jar 未取得所需 Cookie 时调用，无 service。 | P2 没有授权新重定向主机；当前要求 HTTP 200。新增显示完全继承，不自行试别的网关或 Direct。 | 当前 WebVPN 网关 Cookie 参与请求；响应纯文本只在请求内提取 `sso_buaa_zhjs_token`。旧/例无。继承：不保存完整快照、不传宿主。 | GET 精确 `method=get,host=cgyy.buaa.edu.cn,scheme=https,path=/venue-zhjs,vpn_timestamp=<毫秒>`。旧/例无。全部继承 C5:164-172。 | Referer 为当前路线包装的 `https://cgyy.buaa.edu.cn/venue-zhjs`；空正文。旧/例无。继承 C5:173-177，不增加猜测 Header。 | 无新签名/加密，网关 URL 已明确。旧/例无。 | 分号分隔 name=value，精确匹配 Cookie 名并取非空值；不是 JSON。旧/例无；本专项不新增解析字段。 | 本轮业务认证内存，不建立全局 Cookie 镜像。旧/例无；继承现有 token 单飞。 | 非 200/缺 token 安全认证错误；不调用门锁接口伪造“无预约”。旧/例无；CLI 错误分类不改。 |
| L-C：取得业务 access token | 旧 L3:772-793 POST 同基址 `/api/login`；bootstrap 为 L-A，无 service。例无。继承 P2，新增显示不调用 roleLogin/website/init。 | 旧 shared client自动跟随，SSO final URL/401/登录 HTML 视为失效。例无。继承现有业务 3xx 拒绝与认证分类，不让 token 来自其它主机。 | `Sso-Token` 只取上一步 Cookie；响应 `data.token.access_token` 才进入 `cgAuthorization`。例无。继承路线内存；不是预约表单 reservationToken，不落 Session。 | POST 空表单、无 query 业务参数；`includeAuthorization=false`、`allowRetry=false`。例无。继承，不添加上游未证 role/身份字段。 | `Accept: application/json, text/plain, */*`、路线转换 mobileReservation Referer、app-key/timestamp/sign/Sso-Token；`application/x-www-form-urlencoded` 空正文。例无。继承 L3:665-692。 | 继承 L4：`app-key=8fceb735082b5a529312040b58ea780b`，prefix=`c640ca392cd45fb3a55b00a63a86c618`，规范路径+排序过滤标量+timestamp+空格+prefix 后小写 MD5；POST 无 GET nocache。例无。 | 要求成功信封、object data.token、非空 access_token。例无。继承；token、raw/message 不进入显示类型。 | 按当前路线业务状态缓存 token、login_guard 单飞；旧按用户名缓存。例无。继承当前路线/用户隔离，不因 30 秒刷新反复登录。 | 缺字段/业务失败保持已有稳定认证/解析/上游错误；失败不能显示上一次密码。例无。不改普通 CLI exit。 |
| L-D：读取锁码 | 旧 L3:636-642 GET `/api/orders/lock/code`，前置 L-A/L-C；无 service。例无。继承 P2 精确 URL。 | 旧业务 client 自动跳转。例无。继承当前不自动跟随业务 3xx：SSO 目标认证失效，其它目标 upstream_changed；读取仍在第一次解析的路线。 | 复用该用户/路线 access token 和 Cookie；例无。继承认证仲裁、一次 token 刷新；不因显示需要传 token/完整订单。 | GET 无业务参数、无订单 ID，自动且仅加入 `nocache=<毫秒>`。例无。继承，禁止发明按订单查密码的 URL 或参数。 | L-C 的 Accept/Referer/app-key/timestamp/sign，改带 cgAuthorization、不带 Sso-Token；空正文。例无。继承。 | 同 L4 的 MD5；nocache 参与签名。没有锁码解密、AES 或 CAPTCHA。例无。继承。 | 旧 DTO 为 JsonElement?；旧 UI L5 只读取 string-like qrCode/dueDate 及指定 orderView 字段。L8 的 password 只证明 raw 透传。例无。新增严格白名单 typed 显示；原 `available = data非空` API 完全保留，不把它解释为密码存在。 | 旧业务不缓存锁码结果，UI 会留 raw 值；例无。继承路线 token 单飞，新增短期显示 lease、每页一次在途刷新与代次校验，不缓存锁码到 FeatureResult。 | 旧仅业务 code=200解包；网络/认证/解析不是空成功。例无。继承现有 HTTP/业务信封顺序及最多一次认证恢复；新显示失败立即撤下旧密码，稳定 CLI available/exit 不变。 |
| L-E：显示、30 秒/手动刷新、隐藏 | 没有独立上游 URL/service；刷新复用 L-D，例无。不可把屏幕预约单号作为新查询 target。 | 每次刷新仍使用 lease 的已解析路线；旧无显示特例，例无。新进入页面可重新让 facade 解析，已有页面不因 Auto 变化静默换路线。 | 旧 ViewModel 保存 rawData，resetLoadedState 才整体清空；例无。新增屏幕存活期引用，账户/路线/会话 generation 变化立即撤销。 | L5:48-51 每 30 秒调用 getLockCode，手动下拉同样调用；无写入。例无。继承周期和只读性质；同时保留一次请求防重。 | 继承 L-D；本地显示无 HTTP Header/body，例无。不为前台轮询新增缓存绕过参数。 | 本地显示无 crypto，例无。不开二维码编码器：旧 qrCode 直接作为等宽文本显示，并未证明它是二维码图像内容。 | L5:213-223 精确读取 qrCode/dueDate/orderView；trim、空串/字面 null→空。例无。新增分开“密码可显示/仅有预约摘要/无预约/响应未知”，不以 available 代替；dueDate 原文字段不是已证时间戳。 | 旧 isLockCodeLoading 防重复；失败保留旧 raw 值，离开屏幕可留在 ViewModel。例无。新增30秒本地显示期限、隐藏/销毁同步撤销、到期即移除、迟到回复丢弃；手动与定时 single-flight。 | 旧 UI 看见 qrCode 就写“当前时段可开门”，没有验证 dueDate；例无。新不以本地 lease 冒充学校有效期，解析/刷新失败清除密码，只显示安全错误及可重试操作；旧 CLI 无显示 lease。 |

##### 字段来源与实施边界

| 字段 | 旧产品证据 | 建议边界 |
|---|---|---|
| `data.qrCode` | L5:81-85直接等宽显示；L7有string正例。L5:227的stringValue实际对JsonPrimitive取contentOrNull，因而旧实现也会把数值/布尔变成文字；这不是仅字符串的实现 | 本批明确收窄为已证字符串形态的开门凭据；其他primitive返回未知结构，不假称旧实现从未接受它们。允许经专用敏感视图短期显示，不进入普通字段/日志/持久化；保留前导零，不猜六位数规则 |
| `data.dueDate` | L5:87-91显示“有效期至”；L7只有无时区字符串样例 | 用户需要看到的上游有效期文字。可以原文白名单显示；时区、精度、服务端过期判据尚未证明，不直接映射为 epoch/业务授权 |
| `orderView.venueName/siteName/venueSpaceName/reservationDate/reservationDateDetail/reservationStartDate/reservationEndDate` | L5:133-141,216-223；L7验证教室前缀剥离及仅预约摘要 | 预约场所、日期和时段摘要，只取这些字段。全部仍留在同一短期视图，禁止把整个 orderView 交给 Dart。时段展示规则可照 L5:239-244，不新增日期推断 |
| `orderView.tradeNo` | L5:134确实展示为“预约单号”，L7也用于 hasUpcomingReservation | 有用户展示来源，但 P4 明确禁止交易号进入当前 BridgeCgyyOrder。它不能被假称为普通公开 orderId。本页裁决允许仅在专用短期视图作为 `reservationReference` 显示，禁止回流普通订单 DTO、CLI 或 JSON |
| `orderView.orderName` | L5:137,219显示预约人；L7没有该字段的值/格式正例 | 属于个人展示信息，不是开门鉴权材料。本页裁决允许仅在专用短期视图标为“预约人”显示，不推断本人、不透传完整对象 |
| `data.password` | 只有 L8 后端/relay 原样传递测试，UI 不读 | 不能宣称是 qrCode 别名，不增加 password→qrCode 回退。仅有此字段时归为未支持形状，直到适用来源/脱敏观察裁决 |
| `Sso-Token/cgAuthorization/access_token/sso_buaa_zhjs_token/sign/reservationToken` | L3/L4 的内部鉴权与请求材料 | 继续完全留在 Core，不进入任何显示类型；预约表单 token 与门锁阅读无关 |
| 其它 orderView/订单原始字段、phone/theme/joiners/activityContent、支付/审核正文 | 旧门锁页没有使用这些材料的证据；部分存在于 L2 的其它订单 DTO | 无本任务的显示理由，维持排除。未知字段只忽略或导致安全结构错误，不串成通用字段列表 |

`tradeNo` 和 `orderName` 已按本页专用视图裁决保留；它们不成为通用公开字段或任何写入目标。

#### 有意义的 RED 清单


先保留所有旧 API“遇验证码拒绝、零图片/零答案”断言。新增交互 API 的正向用例必须先失败；不能删除旧合同测试来制造 GREEN。合成图片使用测试内生成的有效像素图，不复制真实 CAPTCHA；所有账号、图片、答案、锁码和交易参考使用明确哨兵值。

| 编号 | 初始测试位置 | 行为与应观察的 RED |
|---|---|---|
| A-RED-01 | 新 `crates/ubaa_core/tests/interactive_auth.rs` | 同一合成 image 页：旧 prepare仍 upstream_changed且仅一次登录页 GET；新入口应返回当前路线 challenge+帧。当前没有新能力或只返回旧错误，正向失败 |
| A-RED-02 | 新 auth parser 单元测试 | 精确支持旧 config 形状；空 id/execution、未知 type、额外 MFA/OTP/select、混合未知交互一律拒绝且零取图/POST。防止把“支持 CAPTCHA”改成允许全部交互 |
| A-RED-03 | Core Mock | Direct/WebVPN 分别验证精确 `/captcha?captchaId=...`、当前 jar、实际路线与最终端点；同一图像 handle 不能在另一 runtime使用。200 HTML、假 JPEG与超限字节均安全失败 |
| A-RED-04 | Core Mock | 在 GET `/login` 后提交精确八字段，captcha/captchaResponse相等；不带 captchaId/clientId/旧隐藏额外字段。计数证明每个答案最多一个 POST，非验证码路线不收到答案 |
| A-RED-05 | Core Mock | prepare得 E1/C1，提交前GET得 E2/C2：必须零POST、旧handle失效并返回新挑战。E1/C1稳定时可继续；两种合成情形分别验，不把任一种说成真实上游事实 |
| A-RED-06 | Core/Bridge 可控时钟与延迟传输 | 过期、refresh替换、异实例、账号变化、Session冲突、logout/dispose后提交均网络前拒绝；返回晚于取消的图片/错误均不能发布 |
| A-RED-07 | Bridge/Dart认证控制器 | 一路Ready+一路CaptchaRequired保留partial/profile；完成第二路不再POST第一路；两路独立答案/刷新；无密码缓存供后台重放 |
| A-RED-08 | UI widget | 点击图片只刷新当前challenge并清答案，保留用户字段；图片失败仍要求验证码；过期/隐藏/销毁即清帧与答案，迟到回复不复活控件 |
| A-RED-09 | 序列化/诊断合同 | 哨兵 id、execution、图片字节、答案不在 Debug/Display/Error/LocalDiagnostics/Session/配置/CLI 输出；材料 DTO 不实现serde，旧CLI schema仍验证通过 |
| L-RED-01 | 新 `crates/ubaa_core/tests/cgyy/sensitive_display.rs` 或现有 parser测试模块 | 使用 L7 结构合成 qrCode/dueDate/orderView，断言取得真正文本与摘要。当前只有available，正向必失败；密码前导零不得丢失 |
| L-RED-02 | 同上 | qrCode空串/空白/字面null/缺失+有效orderView为ReservationOnly；data null为NoReservation；password-only、bool、array不冒充code，不报“当前可开门” |
| L-RED-03 | facade Mock | 首次解析路线、后续同lease固定路线，实际URL/Cookie/token一致；无主会话零HTTP；业务认证只刷新一次；绝不调用预约/取消/验证码写链 |
| L-RED-04 | Bridge/Dart可控计时 | 29,999ms不刷新，30,000ms清旧码并触发一次fresh读取；定时与手动重叠只有一个请求；失败时旧码不会继续展示 |
| L-RED-05 | Bridge延迟响应 | 读途中隐藏、返回、换账号、改路线、dispose：取消标记先于大锁生效，迟到成功与错误不进入新屏幕或普通AppSnapshot |
| L-RED-06 | parser/时钟 | dueDate未知格式只作为原文，不擅自取设备时区；本地显示期限可靠到期。上游时区裁决后再增加真正到期/边界秒测试，不能先写猜测期望值当证据 |
| L-RED-07 | Bridge/Dart边界快照 | 普通schema无rawData/orderView/token/sign/图片/交易号；新敏感数据不转FeatureField、不复制到snapshot或toJson。tradeNo/orderName只在本页裁决的专用视图内显示，普通DTO保持禁曝 |
| L-RED-08 | tracing捕获与格式化测试 | 哨兵锁码及其整包SHA-1均不出现在任何级别日志、Debug、错误或LocalDiagnostics。当前通用log_response仍有body_sha1，应先观察这个确定失败再收窄 |
| L-RED-09 | CLI/旧Bridge兼容测试 | 原cgyy_lock_code仍只输出available，schema v10/Session v2/配置v1不变；新 UI 凭据不能从旧命令获得；图像/答案不会新增CLI选项或文件路径 |

两个阶段分别观察合成 RED 后做最小实现，运行对应 Core/Bridge/Dart focused tests、生成绑定一致性、`just check-sensitive` 与 `just check`，阶段提交前只检查/暂存本阶段文件。准备最终验收时再按主线授权执行完整门禁和独立的真实测试；本报告不运行这些检查，不借其它阶段的认证成功或门锁 available=true 作为本专项真实功能证据。


#### 实施与真实验收边界

##### Task3E 验证码候选实现

生产所有者为 `crates/ubaa_core/src/facade/interactive_auth.rs` 与 `auth/interactive.rs`；页面分类在
`upstream/interactive_auth.rs`，资源解码在 `facade/interactive_auth/image.rs`。服务器 id/execution 只存 Core
当前路线状态，已返回像素不进入 Core 会话或流程缓存。新手动上下文按[决策记录](../decision-log.md)中
“新手动交互登录与旧账号会话隔离”执行现有所有权/CAS 清理；普通启动恢复仍走旧非交互链。

Bridge 的 `api/interactive_auth.rs` 用同步登记和撤销处理排队期间取消，异步流程继续检查 Core
句柄。App 的独立 `LoginVerificationState` 不回流普通快照或诊断；等待中选项变化以最终表单为准。
Host/UI 接入路线图片、输入、点击刷新、单路线继续以及显式改用固定就绪路线。普通设置切换也按
backend/认证/凭据/请求代次丢弃迟到成功和失败，见[连接生命周期对照](#连接策略切换与后台重建的迟到结果)。

本轮合成 RED 覆盖新 image 正向、App 等待选项、真实 LoginView 可达性及普通路线迟到回写。
扩展用例进一步真实暴露 Auto 部分就绪时仍进入不可读主页的假设，故增加上文普通 Auto 校验与显式固定
继续裁决；原失败日志和后续实际 facade 读取/零新增认证 POST 断言继续保留。精确命令、退出码、
日志与最终候选映射记录在本批实施报告；这些证据仅属确定性行为，不是上游 live 或 native App 验收。

按验证码、门锁显示两个独立批次实施，每批提供专用facade/Bridge、App状态、生产UI与生命周期测试。opaque句柄绑定客户端、路线、会话/账户代次和本地期限；上游返回值只能经已证白名单解析，不允许Host拼接请求。

当前没有真实挑战图片、成功答案提交、WebVPN验证码链或有效门锁码的本轮证据。真实格式/新重定向主机、提交前GET轮换行为、上游错误分类、password别名与dueDate时区仍需适用证据。已有普通登录、锁码available、Mock解码或合成刷新成功均不代替这些真实结果。

#### 2026-10-02门锁实现前复核

当前旧版`1f4b8f84`与示例`a63712fa`为实际冻结引用。以上L1–L8的接口、DTO、本地请求/签名、UI和测试相较原专项旧版提交均未变化；示例仍无同协议模块。沿用L-A至L-E逐操作九列，不引入password别名、时区解析、订单参数或新主机。新增专用显示绑定客户端、固定路线、会话生命周期与路线代次；同步取消标记阻止在途结果展示。普通available/CLI输出保持。原专项Bridge10仅为旧分支历史版本，本阶段以当前v38为起点升至v39。

### 登录选项与凭据失败恢复的双来源核对

日期：2026-09-15；生产修改前记录。旧版固定 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，示例固定 `efb7976bf513f38364b88aeb83d704586cff9b2a`，本次均经 `just refs` 核验。

#### 已确认的行为差异

| 操作 | 冻结旧版 | 冻结示例 | 当前差异与修复要求 |
|---|---|---|---|
| 取消记住密码 | `composeApp/.../auth/AuthViewModel.kt:76–84` 同时关闭自动登录；`shared/.../api/storage/CredentialStore.kt:30–38` 清除保存值并关闭自动登录 | `src/store/cred.rs` 和 `context.rs` 没有两个UI选项联动 | 当前 `AppController.setRememberPassword(false)` 只改一项，可能形成不记密码却勾选自动登录的矛盾表单；恢复旧联动。是否清除已保存值仍按当前显式提交/清除契约，不额外产生即时磁盘副作用。 |
| 记住密码但不自动登录时恢复 | `AuthViewModel.kt:41–58` 同次恢复用户名与密码，只在auto时自动提交 | 示例凭据容器支持读取用户名和密码，没有手动登录页面 | 当前initialize只恢复用户名，密码仅在auto分支读取，因此“记住密码”不能用于下次手动提交。安全保险箱可用且确有保存值时，在登录表单恢复遮罩密码；auto=false不能隐式登录。认证成功或离开账号上下文释放密码。 |
| 成功登录后的本地保存失败 | 旧版先将isLoggedIn设为true，再保存选项/密码；本地Settings失败没有稳定领域错误 | 示例普通文件I/O返回错误，无UI行为 | 当前保存异常被统一catch成登录失败，即使上游已经认证。应保持已经确认的认证状态，明确提示未能保存，不自动再次登录或夸大“已记住”。需先写行为测试验证最终产品反馈。 |
| 退出并清除的本地删除失败 | 旧版CredentialStore.clear只删除自身四键，没有统一失败恢复测试 | 示例没有当前的用户退出/清除双操作 | 当前logout在清保险箱后才清用户/页面，删除异常可让已注销界面保留用户和业务数据。应在本地删除失败时仍完成会话及内存展示清理，并向调用者报告本机保存内容未清除；不能宣称删除成功。 |
| 无效凭据后的清除失败 | 旧版没有当前稳定保险箱错误接口 | 无对应UI恢复契约 | 当前invalidCredentials处理先await保险箱clear；若再抛错，可能跳过登录错误与阶段恢复。应始终回到可重试登录页并保留原认证失败类别；本地删除错误单独以脱敏诊断记录，不能导致转圈卡住或自动重试。 |

#### 逐操作协议边界

以上五项都是本地表单/状态/系统存储操作，每项的业务 CAS/bootstrap URL、service 参数、重定向/最终URL、Cookie/session范围、HTTP方法/参数、请求头/编码及加密/签名常量均不增加、不替换。实际认证仍严格沿 [准备登录/登录九列](../README.md) 和 [登录/资料旧布局补充](../../archive/protocol/source-parity-ui-profile.md) 的既有协议；不能把示例的普通凭据文件当成安全保险箱。

本地数据仅采用现有 `Credential(username: String,password: String,autoLogin: bool)`；不增加上游DTO、会话文件字段、公开Bridge schema或日志字段。联动不发请求；非自动恢复不发登录请求；失败不重发认证。异步恢复/保存/清除仍受controller销毁及账号生命周期保护，不能把迟到凭据回填到新账号。

旧版接口为AuthApi/LocalConnectionAuth，DTO为LoginPreloadResponse/LoginResponse及CredentialStore中的两个字符串/两个开关；旧测试定位AuthViewModelTest.kt、AuthViewModelInitializeAppTest.kt。示例最近模块为src/api/sso/auth.rs、src/api/user/auth.rs、src/store/cred.rs、src/context.rs：SSO请求/跳转/错误沿已有比较，不具有本地UI选项、Keychain或当前注销状态机，不按类比引入其文件存储。

缓存与并发变更只允许恢复已授权保存的同一账号凭据；未选记住密码、不可用保险箱、清除本机账号或账号切换后不能恢复旧密码。新增测试必须使用合成值，并先观察上述差异的行为失败。当前本页仅记录来源与待修要求，不是修复或验收通过证明。

#### 登录页项目入口与选项点击范围

冻结 `examples/ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/auth/LoginScreen.kt:227–236` 的项目文本具有clickable，并将固定公开项目地址交给LocalUriHandler；当前 `packages/ubaa_ui/lib/src/app/login.dart` 对应位置只有Text，无点击回调。当前About页已有typed `AppLink.project`、宿主 `PlatformAppInformation.open` 与系统浏览器能力；恢复登录入口复用该白名单和已有失败反馈，不由UI拼学校URL、不携带账号或会话、不触发登录。

同一冻结LoginScreen的两个选项Row可点击，Checkbox另有回调；当前_LoginOptions的文字没有动作。应使文字与复选框等价、一次点击只触发一次更改，busy/能力不可用时整行保持禁用。示例项目是API库，没有项目链接或复选框交互；两项均无学校HTTP、重定向、Cookie、加密或DTO变更，也不新增网络读取缓存。外链目标沿现有AppLink公开常量，失败不能静默无效。

已新增两个宿主层行为回归（只用合成backend和注入的AppInformation），从实际可见文字点击，而非直接调用UI回调；RED/GREEN结果另记。


追加清除边界：冻结AuthViewModel.logout成功时以LoginFormState()清空表单；当前明确“退出并清除本机账号”成功后仅清密码，仍残留用户名/记住/自动选项。这也是本地状态缺口；应清空明确要求删除的表单信息，同时普通退出继续保留已授权的系统保存值，不混淆两种操作。对应新增第六项App回归，协议九列不变。

### 连接策略切换与后台重建的迟到结果

2026-09-15，保留实施前 RED，并补 Task3E 修复事实。RED 时涉及的 `AppController.setRoutePolicy`、`rebuildBackend` 和认证辅助文件与 `a85d111cf5552ae4a1580e677caa1b32f20d6ae4` 一致；没有将博雅修改当成此缺陷来源。

#### 已复现问题

当前设置回调先等待旧backend的 `prepareLogin`。其间后台可以重建backend，并从新实例恢复已保存的WebVPN策略和就绪会话。旧实例随后失败时，`setRoutePolicy` 只检查controller是否销毁，没有核对backend/认证代次，因而把表单策略改回旧直连值并带入过期错误。实际已保存策略仍是WebVPN，界面却显示直连。

独立合成探针调用真实AppController公开方法：初始直连就绪→延迟切换WebVPN→成功后台重建并确认新策略WebVPN→释放旧调用的失败。最后预期WebVPN，实际直连，成功编译后的断言失败，退出1。未调用真实学校接口或读取账号。

精确命令如下，运行目录为专项工作区 `packages/ubaa_app`：

```sh
just flutter test '<private-evidence>/macos-ui-20260915/route-lifecycle/late_policy_probe_test.dart' --no-pub --reporter expanded
```

日志为同私有目录的 `late-policy-probe-red.log`。探针及日志不进入Git。Task3E 已补正式
`packages/ubaa_app/test/auth/route_lifecycle_regression_test.dart`：旧成功/失败分别覆盖重建、新选择和退出。
首次修复后六项正式用例及原外部探针共七项退出 0，日志为同一专项私有目录下
`interactive-auth/route-lifecycle-initial-green.log`。设置回调只向捕获的 backend 读取，并在每次
await 后匹配 backend、认证代次、凭据修订和最新请求；原准备调用、默认解析与认证次数保持。

随后补充“旧切换在途时再次选择原策略”的两项行为回归：旧实现把该选择当作无变化而忽略，
成功编译后两项均失败（`interactive-auth/route-original-choice-red.log`，退出 1）。修复保留
`_routePolicyInFlight`，让用户的这次选择也成为新请求；八项正式回归加未修改的外部探针共九项通过
（`interactive-auth/route-lifecycle-final-green.log`，退出 0）。本批三个新增 App 测试最终统一归入
`test/auth/`；移动前后内容哈希一致，旧日志中的直属路径保留原始命令事实。

#### 双来源与操作边界

旧版固定SHA为 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`。`composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/menu/SettingsScreen.kt` 的当前模式由调用者传入，确认后通过 `onModeSelected` 回调；`ui/navigation/MainAppScreen.kt:557–571` 按模式变化重置领域状态，`:831–833` 将当前模式和切换回调传给设置页。旧版没有当前Flutter后台backend重建接口，不能照搬旧ViewModel的异步行为作为新实例的写入授权。

示例固定SHA为 `efb7976bf513f38364b88aeb83d704586cff9b2a`，没有Flutter设置页、AppController或宿主后台重建的对应操作。示例认证/URL包装不构成本次迟到UI回写的依据。

| 操作/来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧设置模式选择 | 沿既有认证合同，不新增请求值 | 不增加规则 | 旧模式变化重置对应领域状态 | 仅调用已存在模式切换回调 | 不适用新增编码 | 不变 | 当前模式由上层状态传入 | 未实现Flutter后台backend重建 | 不提供本项目CLI退出语义 |
| 示例 | 无对应UI/重建操作 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 |
| 本次修复 | 保留原准备和策略保存调用，不新增上游地址/service | 不变 | 不复制会话、不授权旧backend影响新实例 | 原参数/次数不因迟到结果而重发 | 不变 | 不变 | 保持BackendRouteSettings和既有公开版本 | 回写须属于当前backend、账号/认证代次及当前切换；旧成功/失败都不能覆盖新的状态 | 丢弃失效结果，当前失败仍如实反馈；不把旧错误写入新页面 |

本项纳入Task3E的认证/路线生命周期接线，需保留普通无验证码的行为回归，并覆盖旧失败、旧成功、后续新选择、退出及重建。不能只保护新验证码图片而继续让普通路线回调覆盖新会话。没有要求改变旧学校协议、默认路线选择规则或公开配置格式。


#### 2026-10-02整合后的接续

当前冻结来源中设置页未变化，MainAppScreen只额外加入账号变化时重置；以上无新增学校请求的对照保持适用。新离线合同禁止路线变更在途时重建backend，因此正式测试对该分支验证“在途拒绝、收尾后重建重新核对”；同一backend的先后选择、再次原值选择、退出后的迟到成功/失败仍必须丢弃。只增加请求修订及当前账号/实例边界，不改变路线优先级、缓存来源或学校字段。

#### 2026-11-01 首页待办投影的路线切换窗口

本次按当前冻结参考重新核对：旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `MainAppScreen.kt` 在 `LaunchedEffect(connectionMode, userData.schoolid)` 中重置签到等领域状态，并刷新当前页面。`SettingsScreen.kt` 仍通过上层模式回调切换。旧版没有当前 App 的异步纯投影接口。`buaa-api` 固定提交 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/context.rs` 管理客户端、Cookie 和凭据，没有 Flutter 首页、路线设置回调或投影生命周期，对本操作不适用。

本操作只处理已取得的 typed 首页快照。CAS/service、重定向与最终 URL、Cookie/Session/Token 作用域、HTTP 方法与参数、请求头与编码、加密常量和学校 DTO 均沿原操作，不新增学校请求或重试。并发边界使用既有路线在途标志、读取 transition、实际 policy、账号和读取代次。切换开始后拒绝新投影并撤销旧动作，成功或回滚后重新投影。切换前读取的签到内容可以继续只读展示，只有切换后新读取才能恢复动作。路线保存错误沿原逻辑回滚和报告，旧投影统一拒绝。日程与缓存存储、Bridge v45 和 CLI v12 保持原合同。

#### 2026-11-12 手动路线切换与后台读取互斥

旧版固定提交 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `SettingsScreen.kt:97–106` 在确认后调用 `onModeSelected`，`MainAppScreen.kt:562–580` 按模式与账号重置页面数据。`buaa-api` 固定提交 `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/context.rs` 管理客户端、Cookie 和凭据，没有设置页或全局路线切换操作。

| 操作/来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧版设置切换 | 本地回调，无新增地址 | 不适用 | 提示退出当前模式并重新登录 | 本地模式参数 | 不适用 | 不适用 | `ConnectionMode` | 切换后重置页面数据，没有当前 Bridge 读写锁 | 无锁忙错误定义 |
| buaa-api | 无对应操作 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 | 不适用 |
| 当前 Bridge 策略保存与重开 | 本地配置操作，无学校请求 | 不适用 | 保留独立路线槽位、共享账号归属与关闭标记 | 原 `BridgeRoutePolicy` 参数 | 不适用 | 不适用 | 保持 `BridgeRouteSettings` | 取消普通读取后等待既有读写锁，独占保存与重开，后续读取不能插队 | 等待期间关闭则返回 `client_disposed`，不保存策略；其他原错误继续反馈 |

回归覆盖直连与 WebVPN 在后台读取期间排队、后续读取采用新策略、保存后重开保持策略，以及等待期间关闭客户端。验证使用本地合成会话，不涉及学校协议、登录请求或业务写入。

#### 2026-11-13 校外域名名单

用户授权在本机非校园网环境检测业务域名，并明确财务必须通过 WebVPN。名单采用本次公开入口观察与用户确认，详见[校外域名配置](../../contracts/route-policy.md#校外域名配置)。本次不读取账号凭据，不执行登录或业务写入。HTTPS 保留证书验证，使用公共 DNS 的真实地址和实际联网网卡，避免本机代理 fake-IP 影响公网可达性结论。原始响应、DNS 和计时保存在忽略目录 `.ubaa_local/off_campus_domains/`。

冻结旧版 `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 的 `shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalWebVpnSupport.kt` 按当前模式包装业务 URL，场馆保留直连；`LocalConnectionAuth.kt` 的 Cookie 按模式隔离。固定 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81` 的 `src/utils/net.rs` 探测校园网关。两份来源均没有当前按域名配置的校外名单，不据此推断其他域名可达性。

| 操作/来源 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 旧版模式包装 | 继承各业务原地址 | 按模式包装 WebVPN URL | 路线隔离 | 原业务操作 | 原业务编码 | 既有 WebVPN 编解码 | 无校外名单 DTO | 无当前名单 | 无当前名单规则 |
| buaa-api 网关探测 | 不适用 | 不适用 | 无会话 | DNS 与 TCP，无 HTTP | 不适用 | 不适用 | 布尔可达性 | 无当前名单 | 探测失败表示不可达 |
| 当前名单选择 | 继承各业务原地址 | 不改变跳转校验 | 保持 Direct/WebVPN 独立会话 | 不新增请求，只提前选路线 | 不变 | 不变 | 不变 | Auto 且 OffCampus 时先按名单选择 WebVPN，再检查目标会话；无会话不尝试已知不可达的 Direct | 缺少目标认证按 WebVPN 返回 authentication_required；显式策略、校内选择及写入不重放保持原规则 |

名单外信息门户的合成测试覆盖网络错误回退、非网络错误不回退、24 小时记录、重开与过期。希冀分段回退在网络未知时覆盖独立路线重建选课上下文，课表覆盖普通 Auto 恢复的直连优先。名单域名分别覆盖首次选择、缺少 WebVPN 会话、校园网、未知网络和显式路线。

#### 换网期间的读取取消与恢复

用户明确要求网络变化立即失效旧观察、取消旧只读请求并保留原查询，准备目标路线后继续读取。两份冻结来源沿上述固定版本，旧版 `LocalConnectionAuth.kt` 设置连接 10 秒、请求 30 秒，`LocalWebVpnSupport.kt` 按模式包装 URL；buaa-api 的对应网关探测仍为 `src/utils/net.rs`。两者没有当前并行读取取消和统一恢复期限，新增调度行为采用本项目产品要求。

| 操作 | CAS/bootstrap/service | redirect/finalURL | Cookie/session | HTTP/精确参数 | headers/body | crypto | DTO/parser | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| 换网检测 | 既有网关目标，无新增学校地址 | 不适用 | 不使用会话 | 既有 DNS/TCP 探测 | 不适用 | 不适用 | 保留网络三态，宿主另传是否联网 | 探测独立于业务锁，缓存缩短至 3 秒；换网立即失效，并发合并 | 断网保留页面，最新事件不丢弃 |
| 只读请求取消和继续 | 原业务认证入口 | 原重定向校验 | 保持路线、账号和凭据许可隔离 | 原查询参数，网络恢复后重建同查询；已发送写入不重放 | 不变 | 不变 | 不变 | 取消传到 Rust Future 并释放读取占用；校外初始 Direct 连接预算 2 秒，正常响应预算保留；一次读取最多跨路线回退一次 | 旧网络结果不交付；恢复总期限覆盖排队、认证及重读，网络失败不退出账号 |

网络错误后重新探测可以推翻旧的校内判断。返回校园网的新请求优先 Direct，正常在途 WebVPN 读取可完成。每次换网按共同恢复服务合并目标路线登录；验证码、凭据拒绝与缺少许可继续交给现有人工入口。


### Live 验证与客户端认证入口统一（2026-11-13）

冻结来源为 ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3` 和 buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。旧版核对 `LocalConnectionAuth.kt` 的预加载、验证码图片、表单和用户中心校验，以及 `AuthApi.kt`、`Auth.kt`、`LocalAuthServiceBackendTest.kt`；另一来源核对 `api/sso/auth.rs`、`request.rs`、`store/cred.rs`、`store/cookies.rs`、`error.rs`。沿用本页验证码逐操作依据，不修改学校协议。

| 操作 | CAS/bootstrap 与 service | 重定向与最终 URL | Cookie、Session、Token | 方法与参数 | 请求头和编码 | 加密与签名 | DTO 与解析 | 缓存、并发、重试 | 错误与产品语义 |
|---|---|---|---|---|---|---|---|---|---|
| Live 登录准备 | 旧版 SSO login；示例 Direct 相同、VPN service 不等价；采用客户端 Core 既有入口 | 旧版跳转后激活 UC；示例按最终地址判断；沿用 Core 校验 | 旧版按路线 jar；示例共享 Context；沿用 Core 双槽隔离，验证固定单路线 | 原 GET 登录页，提取 execution 和验证码配置 | 原请求头、无正文 | 无新增 | 旧版 LoginPreloadResponse；示例仅 execution；采用现有交互状态 | 使用 prepare_quiet_login_for，仅准备指定路线 | 现有普通诊断 API 保留原合同，live 使用客户端交互流程 |
| 自动图片验证码登录 | 旧版同 SSO login/captcha；示例无验证码流程，不适用 | 沿用 Core 的路线内跳转、UC 身份验证 | 挑战和答案只留内存，绑定当前账号与路线 | 旧版 captchaId 取图，POST username/password/captcha/captchaResponse/execution/_eventId/submit/type；全部由现有 Core 构造 | 原表单编码，图片沿既有解码 | 旧版无自动识别；使用客户端已有本地模型，无新协议常量 | 原图像挑战及用户资料，不输出个人数据或验证码 | 复用 submit_quiet_login 的最多三轮自动处理；不在工具额外重试 | 自动耗尽输出 captcha_required，依赖读取 BLOCKED；批处理工具不等待人工输入 |
| 认证后只读调用 | 两源按各功能既有协议；沿用对应协议页 | 采用 UbaaClient 的固定 Direct/WebVPN 路线，禁止 Auto 或跨路线回退 | 同一客户端、同一登录会话 | 原只读方法与参数不变 | 原业务头和正文不变 | 原业务规则不变 | 原 typed 数据只投影安全计数 | 各功能串行执行，内部缓存与并发由现有 facade 决定 | 财务与其余功能使用统一认证；失败保留稳定分类、非零退出和逐项阻塞 |

公共 CLI 的显式单路线登录已调用 login_required_route，支持自动验证码。旧聚合 UbaaClient.login、RouteClient.login 及 prepare_login 的普通登录合同有独立覆盖，本次保持。客户端的渐进作业读取与 live 聚合协议验证仍有调度差异，应用性能需要通过实际渐进入口单独测量。

验证入口的请求级测试覆盖 Direct/WebVPN 普通登录、图片验证码成功、第三次成功、三次耗尽、服务异常、未知挑战和账号不匹配，以及登录后的同路线用户读取。认证失败的依赖矩阵覆盖全部受支持功能，包括 iHome 的列表、详情、配置和公告。原源码门禁的 RouteClient 构造及普通准备顺序断言更新为 UbaaClient 和独立认证模块；只读禁写、facade 分层、stdin 脱敏与二进制退出码覆盖保留。
