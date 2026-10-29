# 验证码与门锁信息：逐操作来源与专用显示边界

日期：2026-09-15。旧版固定 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`，示例固定 `efb7976bf513f38364b88aeb83d704586cff9b2a`。当前生产源码索引以 `3966001e02db960cacf3b09945c503c73232d07a` 为基线；实施前继续运行纯校验 `just refs`。

状态：Task3E 已接入验证码专用 Core/Bridge/App/Host/UI 候选，正在执行本地合成验证；门锁显示仍待独立批次。未取得真实验证码或门锁显示验收。用户要求完整恢复旧版按钮功能，专用的短期显示能力属于本专项所需修复；不因此开放通用原始响应、上游鉴权材料或真实学校写入。

## 已作出的实施裁决

1. 允许通过独立 `facade`/typed Bridge 能力显示旧版已证的验证码图像，以及登录会话返回的门锁密码/预约摘要。只在用户打开的当前页面保留；不得放进普通FeatureField、FeatureResult、AppSnapshot、配置、Session、诊断、JSON或日志。服务器challenge id/execution、URL、Cookie/token/sign/密钥继续完全留在Core。
2. 旧非交互prepare/login和CLI仍在验证码前拒绝，不取图、不接受答案。新增交互入口使用Core持有的路线内不透明句柄；图像只输出已解码的受限像素帧，答案只用于本次精确表单。两路线独立，一路成功时保留就绪槽位和资料；可继续完成另一路，也可明确使用已就绪连接，不能重发已完成路线或偷偷复用密码。
3. 验证码初版保留旧提交前GET。GET后的id/execution变化就作废旧答案并重新准备，零POST；不猜错误答案/过期分类，不增加图片主机或其他挑战类型。实际挑战每次轮换时保留真实可用性缺口，取得适用证据后再调整该顺序。
4. 验证码本地最长显示/回答时间120秒；编码图片最大512KiB，只解码现有锁定image依赖支持的JPEG/PNG，宽高各不超过1024、总像素不超过1048576、RGBA不超过4MiB。先检查资源边界再解码，不从JPEG前缀推断真实图片格式。这些是本地资源/显示约束，不是上游协议、TTL或学校规定。
5. 门锁从已证的qrCode字符串取值，保留前导零；dueDate原文字段及旧页九个预约字段均允许仅在专用视图显示，其中tradeNo映射为reservationReference、orderName仍标“预约人”，不假称当前本人。七个场所/日期字段见下表。普通订单DTO、CLI和通用JSON仍不得包含交易号或这些敏感显示字段；不得把password猜作qrCode别名。
6. 门锁第一次打开fresh读取，手动与30秒刷新共用单次在途请求。成功显示最多30秒，到期先移除旧码再刷新，失败不保留旧码。dueDate只显示上游原文，不从设备时区推断绝对失效时间，不声称30秒是学校密码更新周期。
7. 两类敏感页面返回、销毁、账号/会话/路线变更及hidden/paused/detached时立即清显示和答案、撤销句柄，迟到结果不能重新出现；inactive本身不等于窗口不可见。取消标记不得排队等待Bridge网络大锁。恢复可见后重新准备/打开，不恢复旧帧或旧码；不用剪贴板、分享、磁盘或网络图像缓存。
8. 类型不实现serde/toJson，Debug/Display/toString只输出安全状态；内存清理只承诺释放引用和缓存，不声称已物理擦除Dart/FFI/图形系统所有拷贝。门锁响应不记录整包body_sha1，也不记录低熵码、图像或答案的摘要。
9. 所有新增接口仍属于未发布候选Bridge10，合同另设敏感显示专节，与图书馆/博雅非敏感扩展分别说明。CLI schema10、Session2、配置1、现有available摘要和WriteCoordinator权威不变。若候选先行发布，后续新增合同再独立升版；当前没有发布行为。

部分就绪的本地交互补充：若当前固定策略指向尚未完成的路线，“使用已就绪连接”必须明确显示将使用哪条就绪路线，并在进入主页前让后续读取实际采用该路线；原本匹配就绪路线的策略保持。Auto继续必须先沿现有解析规则确认其选中的路线已就绪，成功时保持Auto。若Auto选中未就绪路线，保持原策略、就绪槽位和交互上下文，返回可恢复提示；UI另提供明确“改用直连/WebVPN并继续”的操作，只有用户点击该操作才保存相应固定策略并继续。用户也可补全另一条路线后继续保持Auto。不得打开全局ready-route fallback、引入隐藏路线覆盖，或在不可读取时仍显示进入成功。

固定策略的改变来自这次明确继续操作，不调用旧prepareLogin重新准备两路或重发已完成认证；策略保存失败留在登录交互并如实反馈，不伪造ready或资料。须用两个方向的固定策略不匹配、Auto解析选中就绪路线、Auto解析选中未就绪路线后显式切换、零就绪及保存失败的合成行为测试验证，并保留进入后实际facade读取成功、认证POST计数不增加的断言。该Auto限定来自本批扩展用例的真实失败及现有SAFE_DEFAULT，详见[决策记录](decision-log.md)中“Auto部分就绪继续的可用性”条目。

协议证据不足只限制相应分支，不阻止已有冻结实现支持的图像刷新、精确提交、门锁文本和短期生命周期实现。必须先观察合成行为RED，再实现与独立审查；真实无挑战、无有效预约或锁屏都不能记作功能通过。

## 可核查的源码索引


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
| P1 | `docs/migration/source-parity.md:72-76,95-104`，读取基线版本 | 现有 WebVPN/准备登录九列矩阵 |
| P2 | 同文件 `594-609`，读取基线版本 | 现有 Cgyy 只读九列、3xx 规则及脱敏 WebVPN 观察记录 |
| P3 | `docs/contracts/auth-and-user.md:8-24,32-45`；`connection-and-session.md:26-34`，读取基线版本 | CLI v10、Session v2、交互拒绝及退出分类 |
| P4 | `docs/contracts/flutter-bridge.md:8,228-234,282-297`，读取基线版本 | 验证码材料禁曝、交易号禁曝、门锁仅 available |

对固定 `examples/buaa-api/src` 搜索 `captcha|venue-zhjs|cgyy|orders/lock/code` 无匹配；SSO 模块只声明 `mod auth`。下文“例无”均表示该操作在固定示例中没有同协议实现，九列都不能借用其它模块的 URL、DTO、加密、缓存或错误。示例普通 SSO 的有限等价性只在明确标出的单元格中使用。

## 登录验证码：逐操作九列


以下每行分别说明与 P1 已有九列的继承和新增。旧非交互合同继续保留；本页裁决只为独立交互入口新增专用边界。

| 操作 | CAS/bootstrap 与 service | redirect/finalURL | Cookie/session | HTTP 与精确参数 | Header/body | crypto 常量 | DTO/parser 类型 | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| A：准备与检测 | 旧 A3/A5：GET `https://sso.buaa.edu.cn/login`，无 service；WebVPN 经 W1 包装。例 E1 普通 Direct 相同，但 VPN 明加网关登录 service，不是旧版同一选择。继承 P1 的旧版 URL/路线，不借示例 service。 | 旧 preload 遇 3xx 转用户中心激活/校验；普通登录页要求 200，旧流程无逐跳 host 白名单。例 reqwest 跟随跳转并用 uc 或网关根作已登录判断。继承当前有界、路线内解析与既有允许主机；不扩大白名单。 | 旧 A7 当前 mode 的 jar；execution 在返回 DTO 中。例 E2/E4 共享 Context，非路线隔离。继承当前两 jar、准备页 Cookie 不等于已认证槽位。新增挑战只在当前 Core 实例/路线/准备代次内存。 | 旧空正文 GET，无 username/captcha/body；响应提取 execution 和 `config.captcha`。例只取 execution。新增仅增加页面分类，不增加探测 URL 或 GET 参数。 | 旧无 CAPTCHA 专用 Header；例自带 E3 UA。继承现有请求默认值，不借示例 UA，不新增 Origin/XHR。 | 两源普通 SSO 不加密账号密码；WebVPN 仅 W1 路线包装。继承 P1：`wrdvpnisthebest!`、AES-128-CFB 与既有 URL 编解码；不借 Cgyy AES/滑块算法。 | 旧 A6 正则只识别 `config.captcha = { type: '<值>', id: '<值>' }` 的顺序形状；A2 有 string id/type/imageUrl/base64Image。例无验证码 DTO。新增只接受来源支持的 `type=image` 与唯一非空 id/execution；其它交互仍拒绝。对外不传原始 id/execution/HTML/URL。 | 旧 UI 可并发 launch，无代次校验。例无挑战状态。继承当前每路线 AuthWorkflow；新增每路线单个准备代次，替换前作废旧 handle，禁止跨路线借用。 | 旧非 200 preload 甚至可返回“不需要验证码”；缺图可保留要求状态。例只给缺 execution/Server 错误。新交互入口返回明确 required 或安全失败；旧 API/CLI 保持 `upstream_changed`、exit 6，且仍零取图。 |
| B：图片加载 | 旧 A5：路线转换后的 `https://sso.buaa.edu.cn/captcha`，无 CAS/service。例无。新增沿用该固定地址，宿主不提供 URL。 | 旧 shared client 可自动跳转，没有 CAPTCHA 终点白名单。例无。新增本操作只接受同路线还原后 SSO `/captcha` 的有效图片终点；未知跳转失败关闭；现有 SSO 跳转规则可复用，不由图片失败扩充主机。这是较旧版更窄的产品边界，未声称已证明真实图片重定向链。 | 旧与准备请求共用当前 mode Cookie。例无。继承当前 runtime jar；新增 handle 校验在请求前进行，图片回复后再核对代次。 | 旧精确 GET `/captcha?captchaId=<从页面提取的id>`；不带答案、execution、clientId、nonce 或刷新 timestamp。例无。新增仍只有 captchaId 一个 query 值，使用有界 URL 构造；不生成上游挑战 ID。 | 旧空正文，无专用 Accept；只要求 HTTP 200 就读 ByteArray，再硬编码 `data:image/jpeg;base64,`。例无。新增不照抄伪 MIME，不将 HTML 或畸形字节交给界面。 | 旧仅 Base64 展示编码，不是验证码加密。例无。新增无签名/解密，不复用研讨室预约滑块求解器。 | A10 的响应 Content-Type 标 JPEG，但四个伪字节只测试前缀。新增依据实际字节受控解码，返回 RGBA 帧或确认格式的内存图片；格式白名单是本地解码支持范围，不是上游必定 JPEG/PNG 的事实。未知格式返回安全失败。 | 旧无 TTL 或图片结果单飞证明。例无。新增一 challenge 一次取图、可取消的显示生命周期、编码长度与解码尺寸上限；不使用 URL/file/image 全局缓存。 | 旧非 200 返回 null，异常转用户错误；没有正确图像解码的测试。例无。新增保留“需要验证但图片加载失败”的状态，允许用户刷新，禁止因此提交空答案或自动改为普通登录；旧 CLI 不走此操作。 |
| C：点击刷新 | 旧 A9 `refreshCaptcha()` 实际重跑 `preloadLoginState()`，即 A→B；没有独立 refresh 上游端点。例无。新增仍使用同一组已证 URL/service。 | 继承 A/B 对各自终点的规则；旧没有刷新特例，例无；新增不因刷新重选路线。 | 旧同 mode jar。例无。继承同一路线 jar；新增先作废旧 handle/答案，再取得新 execution/id，禁止拿新图配旧 execution。 | 旧 GET `/login` 后按新 id GET `/captcha`；不是对原图 URL添加时间参数。例无。新增不带 username/password/答案，不发送登录 POST。 | 继承 A/B 的空正文及默认 Header，例无；新增不假定 Cache-Control/Referer 参数。 | 继承 A/B；无额外 crypto，例无。 | 旧返回可选 captcha/execution，刷新回调没有清空已有答案，且无类型/代次验证。例无。新增刷新成功替换整个 typed challenge；答案清空；用户名、密码和记住密码选项保留。 | 旧 isRefreshing 只影响按钮，后端无完整防重/迟到响应守卫。例无。新增每路线 single-flight，第二次刷新可替换或拒绝；较旧回复永不覆写新挑战。 | 旧刷新失败保留旧 challenge 及答案并显示错误。例无。新增显示安全错误并保持旧挑战作废，显式可重试；不恢复旧答案、不自动 POST。旧 CLI 无此操作。 |
| D：提交答案与恢复 | 旧 A4 每次 login 先 GET `/login`，再 POST 同地址；成功后 UC_ACTIVATE_URL 与状态/资料查询。无新 service。例 E1 只有无验证码普通表单。继承已证登录/激活地址。 | 旧 A5 手动跟随任意 3xx，风险继续最多一次；最终 URL 的 exception.message/错误 HTML 会失败。例以 HTTP success 为主要成功判据。继承当前有界路线跳转、一次风险继续及用户中心校验，不采用“200 就登录成功”。 | 旧优先使用调用者 execution，获取新页面后未验证 id/execution 与答案一致。例无对应关联。新增 opaque handle 绑定同实例、同路线、同准备代次及 jar；另一条已登录路线保持有效，禁止复制 Cookie 或答案。 | 旧验证码 POST 精确八字段：`username,password,captcha,captchaResponse,execution,_eventId=submit,submit=登录,type=username_password`；两答案值相同，无 captchaId/clientId。例只有六个普通字段。新增仅发上述字段，不把普通隐藏字段无差别并入验证码表单。提交前 GET 的轮换问题见下文，不能忽略。 | 旧 `FormDataContent`，当前与例皆 `application/x-www-form-urlencoded`；无 JSON。新增答案仅出现在本次请求表单，不进 URL/Header。 | 两源普通 SSO 均无额外密码/答案加密；新增无 AES/RSA/signature；继续既有 WebVPN 编码。 | 旧未输入答案返回 `CaptchaRequiredClientException(captcha,execution)`；POST 后主要按通用错误/剩余 execution 判断失败。例无 CAPTCHA 结果类型。新增结果区分等待输入、需重新准备、已认证和安全失败；没有证据时不宣称“验证码错误”与“账号错误”可准确区分。 | 旧 WebVPN 成功后另试 Direct SSO，失败吞掉。例无对应双路线挑战。继承当前 Direct→WebVPN 独立编排，绝不复制旧额外 Direct 副作用。handle 一次性消费；提交/刷新互斥；不保留密码供后台自动重放。 | 旧缺答案是 CAPTCHA required，其它原文错误经包装；例 Server/Network/Parse 且无 CLI exit。新交互结果可以要求重新输入，但未知交互仍 upstream_changed；认证/网络/解析使用现有稳定码。旧序列化 DTO 与 CLI exit 0/2/3/5/6/7不变。 |

### 不能略过的冲突

1. **提交前 GET 与旧 challenge 关联**：A4:459 再次 GET `/login`，A4:475-489 却优先用调用者旧 execution；该次新 GET 的 captcha id 是否相同、旧答案是否有效，没有成功提交/刷新轮换测试。最保守方案保留 GET；若其 execution/id 与 handle 绑定值不同，就返回新挑战并且零 POST。若 GET 每次都轮换，这个保守方案会一直要求新图，必须拿适用上游证据裁决是否允许直接消费 prepared challenge。不能凭普通 Core 已缓存表单就声称 CAPTCHA 可省略这一步。
2. **JPEG 不是已证实际格式**：A5:629-635 无 Content-Type 或 magic 校验；A10:384-402 是假字节测试。可做受控字节解码和未知格式拒绝，不能把旧硬编码当真实 JPEG 证据，也不能自动支持任意 SVG、脚本或未知验证码 type。
3. **图片跳转白名单**：旧 A5 使用 followRedirects 的 shared client，没有图片专用终点约束；当前认证白名单不自动证明任何新图片主机。先只允许来源中的 SSO `/captcha`，实际跳到新主机时应留 gap，不能加猜测的 CDN。
4. **例的 VPN service/共享存储与旧版不等价**：E1:24 的 `service=https://d.buaa.edu.cn/login?cas_login=true`、E2/E4 共享 Context 不用于挑战路由。E3:18 与 Context 默认值存在关闭证书检查的组合，绝不复制。
5. **旧刷新恢复并不安全完整**：A9:124-141 不清答案，异步回复没有代次守卫；这证明旧体验有刷新入口，不证明可继续复用旧答案或旧挑战。新方案必须显式收窄。

## 研讨室门锁：逐操作九列


P2 中“站点”和“锁码”的九列可以复用既有请求链；本专项新增的是最后一层敏感显示投影与生命周期。为避免“认证成功”掩盖过程，以下将 bootstrap、WebVPN Cookie 同步、业务登录、锁码读取和界面刷新分别列出。

| 操作 | CAS/bootstrap 与 service | redirect/finalURL | Cookie/session | HTTP 与精确参数 | Header/body | crypto 常量 | DTO/parser 类型 | cache/concurrency | error/exit |
|---|---|---|---|---|---|---|---|---|---|
| L-A：业务 SSO 引导 | 旧 L3:754 GET `https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin`，无显式 service。例无。继承 P2 同地址，不使用 relay `/api/v1/cgyy/*`。 | 旧 followRedirects=true 且固定 Direct，W1:105 原样 URL。例无。继承已有 Core 当前路线的有界跳转及 SSO/Cgyy 主机规则，保留 P2 已记录的旧版路线冲突；不恢复 WebVPN 偷走 Direct。 | 旧 L3:747-764 用 Direct jar 取得 `sso_buaa_zhjs_token`。例无。继承当前路线 jar 与已证 WebVPN 适配；不得复制另一路线 Cookie。 | 旧仅 GET，无业务参数/正文；例无；继承。 | 旧仅客户端默认 Header；这里不是 `/api/login` 的签名请求。例无。继承已有 bootstrap 请求，不把 business 头一概加给 SSO。 | 无 Cgyy 业务签名；WebVPN 包装继承 P1/W1。例无。 | 旧读 Cookie，不产出用户锁码 DTO。例无。继承：SSO Cookie 内存进入下一步，宿主不可见。 | 旧 client 按用户名缓存、业务登录 Mutex。例无。继承当前路线 token 单飞；不为显示页另建认证客户端。 | 缺主会话零业务请求；无 SSO Cookie 为认证失败。例无。继承现有用户中心失效仲裁和稳定错误；不记 raw URL/Cookie。 |
| L-B：WebVPN Cookie 同步 | 旧/例均无该同协议步骤；来自 P2:607 已提交脱敏观察，当前 C5 实现 `https://d.buaa.edu.cn/wengine-vpn/cookie`。仅 WebVPN 且当前 jar 未取得所需 Cookie 时调用，无 service。 | P2 没有授权新重定向主机；当前要求 HTTP 200。新增显示完全继承，不自行试别的网关或 Direct。 | 当前 WebVPN 网关 Cookie 参与请求；响应纯文本只在请求内提取 `sso_buaa_zhjs_token`。旧/例无。继承：不保存完整快照、不传宿主。 | GET 精确 `method=get,host=cgyy.buaa.edu.cn,scheme=https,path=/venue-zhjs,vpn_timestamp=<毫秒>`。旧/例无。全部继承 C5:164-172。 | Referer 为当前路线包装的 `https://cgyy.buaa.edu.cn/venue-zhjs`；空正文。旧/例无。继承 C5:173-177，不增加猜测 Header。 | 无新签名/加密，网关 URL 已明确。旧/例无。 | 分号分隔 name=value，精确匹配 Cookie 名并取非空值；不是 JSON。旧/例无；本专项不新增解析字段。 | 本轮业务认证内存，不建立全局 Cookie 镜像。旧/例无；继承现有 token 单飞。 | 非 200/缺 token 安全认证错误；不调用门锁接口伪造“无预约”。旧/例无；CLI 错误分类不改。 |
| L-C：取得业务 access token | 旧 L3:772-793 POST 同基址 `/api/login`；bootstrap 为 L-A，无 service。例无。继承 P2，新增显示不调用 roleLogin/website/init。 | 旧 shared client自动跟随，SSO final URL/401/登录 HTML 视为失效。例无。继承现有业务 3xx 拒绝与认证分类，不让 token 来自其它主机。 | `Sso-Token` 只取上一步 Cookie；响应 `data.token.access_token` 才进入 `cgAuthorization`。例无。继承路线内存；不是预约表单 reservationToken，不落 Session。 | POST 空表单、无 query 业务参数；`includeAuthorization=false`、`allowRetry=false`。例无。继承，不添加上游未证 role/身份字段。 | `Accept: application/json, text/plain, */*`、路线转换 mobileReservation Referer、app-key/timestamp/sign/Sso-Token；`application/x-www-form-urlencoded` 空正文。例无。继承 L3:665-692。 | 继承 L4：`app-key=8fceb735082b5a529312040b58ea780b`，prefix=`c640ca392cd45fb3a55b00a63a86c618`，规范路径+排序过滤标量+timestamp+空格+prefix 后小写 MD5；POST 无 GET nocache。例无。 | 要求成功信封、object data.token、非空 access_token。例无。继承；token、raw/message 不进入显示类型。 | 按当前路线业务状态缓存 token、login_guard 单飞；旧按用户名缓存。例无。继承当前路线/用户隔离，不因 30 秒刷新反复登录。 | 缺字段/业务失败保持已有稳定认证/解析/上游错误；失败不能显示上一次密码。例无。不改普通 CLI exit。 |
| L-D：读取锁码 | 旧 L3:636-642 GET `/api/orders/lock/code`，前置 L-A/L-C；无 service。例无。继承 P2 精确 URL。 | 旧业务 client 自动跳转。例无。继承当前不自动跟随业务 3xx：SSO 目标认证失效，其它目标 upstream_changed；读取仍在第一次解析的路线。 | 复用该用户/路线 access token 和 Cookie；例无。继承认证仲裁、一次 token 刷新；不因显示需要传 token/完整订单。 | GET 无业务参数、无订单 ID，自动且仅加入 `nocache=<毫秒>`。例无。继承，禁止发明按订单查密码的 URL 或参数。 | L-C 的 Accept/Referer/app-key/timestamp/sign，改带 cgAuthorization、不带 Sso-Token；空正文。例无。继承。 | 同 L4 的 MD5；nocache 参与签名。没有锁码解密、AES 或 CAPTCHA。例无。继承。 | 旧 DTO 为 JsonElement?；旧 UI L5 只读取 string-like qrCode/dueDate 及指定 orderView 字段。L8 的 password 只证明 raw 透传。例无。新增严格白名单 typed 显示；原 `available = data非空` API 完全保留，不把它解释为密码存在。 | 旧业务不缓存锁码结果，UI 会留 raw 值；例无。继承路线 token 单飞，新增短期显示 lease、每页一次在途刷新与代次校验，不缓存锁码到 FeatureResult。 | 旧仅业务 code=200解包；网络/认证/解析不是空成功。例无。继承现有 HTTP/业务信封顺序及最多一次认证恢复；新显示失败立即撤下旧密码，稳定 CLI available/exit 不变。 |
| L-E：显示、30 秒/手动刷新、隐藏 | 没有独立上游 URL/service；刷新复用 L-D，例无。不可把屏幕预约单号作为新查询 target。 | 每次刷新仍使用 lease 的已解析路线；旧无显示特例，例无。新进入页面可重新让 facade 解析，已有页面不因 Auto 变化静默换路线。 | 旧 ViewModel 保存 rawData，resetLoadedState 才整体清空；例无。新增屏幕存活期引用，账户/路线/会话 generation 变化立即撤销。 | L5:48-51 每 30 秒调用 getLockCode，手动下拉同样调用；无写入。例无。继承周期和只读性质；同时保留一次请求防重。 | 继承 L-D；本地显示无 HTTP Header/body，例无。不为前台轮询新增缓存绕过参数。 | 本地显示无 crypto，例无。不开二维码编码器：旧 qrCode 直接作为等宽文本显示，并未证明它是二维码图像内容。 | L5:213-223 精确读取 qrCode/dueDate/orderView；trim、空串/字面 null→空。例无。新增分开“密码可显示/仅有预约摘要/无预约/响应未知”，不以 available 代替；dueDate 原文字段不是已证时间戳。 | 旧 isLockCodeLoading 防重复；失败保留旧 raw 值，离开屏幕可留在 ViewModel。例无。新增30秒本地显示期限、隐藏/销毁同步撤销、到期即移除、迟到回复丢弃；手动与定时 single-flight。 | 旧 UI 看见 qrCode 就写“当前时段可开门”，没有验证 dueDate；例无。新不以本地 lease 冒充学校有效期，解析/刷新失败清除密码，只显示安全错误及可重试操作；旧 CLI 无显示 lease。 |

### 字段来源与实施边界

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

## 有意义的 RED 清单


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


## 实施与真实验收边界

### Task3E 验证码候选实现

生产所有者为 `crates/ubaa_core/src/facade/interactive_auth.rs` 与 `auth/interactive.rs`；页面分类在
`upstream/interactive_auth.rs`，资源解码在 `facade/interactive_auth/image.rs`。服务器 id/execution 只存 Core
当前路线状态，已返回像素不进入 Core 会话或流程缓存。新手动上下文按[决策记录](decision-log.md)中
“新手动交互登录与旧账号会话隔离”执行现有所有权/CAS 清理；普通启动恢复仍走旧非交互链。

Bridge 的 `api/interactive_auth.rs` 用同步登记和撤销处理排队期间取消，异步流程继续检查 Core
句柄。App 的独立 `LoginVerificationState` 不回流普通快照或诊断；等待中选项变化以最终表单为准。
Host/UI 接入路线图片、输入、点击刷新、单路线继续以及显式改用固定就绪路线。普通设置切换也按
backend/认证/凭据/请求代次丢弃迟到成功和失败，见[连接生命周期对照](source-parity-ui-route-lifecycle.md)。

本轮合成 RED 覆盖新 image 正向、App 等待选项、真实 LoginView 可达性及普通路线迟到回写。
扩展用例进一步真实暴露 Auto 部分就绪时仍进入不可读主页的假设，故增加上文普通 Auto 校验与显式固定
继续裁决；原失败日志和后续实际 facade 读取/零新增认证 POST 断言继续保留。精确命令、退出码、
日志与最终候选映射记录在本批实施报告；这些证据仅属确定性行为，不是上游 live 或 native App 验收。

按验证码、门锁显示两个独立批次实施，每批提供专用facade/Bridge、App状态、生产UI与生命周期测试。opaque句柄绑定客户端、路线、会话/账户代次和本地期限；上游返回值只能经已证白名单解析，不允许Host拼接请求。

当前没有真实挑战图片、成功答案提交、WebVPN验证码链或有效门锁码的本轮证据。真实格式/新重定向主机、提交前GET轮换行为、上游错误分类、password别名与dueDate时区仍需适用证据。已有普通登录、锁码available、Mock解码或合成刷新成功均不代替这些真实结果。

## 2026-10-02门锁实现前复核

当前旧版`1f4b8f84`与示例`a63712fa`为实际冻结引用。以上L1–L8的接口、DTO、本地请求/签名、UI和测试相较原专项旧版提交均未变化；示例仍无同协议模块。沿用L-A至L-E逐操作九列，不引入password别名、时区解析、订单参数或新主机。新增专用显示绑定客户端、固定路线、会话生命周期与路线代次；同步取消标记阻止在途结果展示。普通available/CLI输出保持。原专项Bridge10仅为旧分支历史版本，本阶段以当前v38为起点升至v39。
