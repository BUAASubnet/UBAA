# 研讨室预约

本文件收录研讨室（场馆）预约查询、订单详情、收据与写入边界的来源对照；提交与取消九列见[直接写操作](write-actions.md)。

## 逐操作基线矩阵

以下矩阵沿用[逐操作历史矩阵](general.md#逐操作历史矩阵)的取证说明：原始取证版本、换钉后的适用方式和重新核对要求以该节为准。

### 场馆预约只读查询

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

`examples/buaa-api` 在锁定提交中未实现 `venue-zhjs-server` 场馆预约协议，因此没有提供 URL、字段、令牌或错误语义；以上所有协议值均来自冻结 `examples/ubaa_old/shared/.../CgyyApi.kt`、`LocalCgyyApi.kt`、`LocalCgyySigner.kt` 及对应服务测试。取消、锁码和预约提交已分别接入 Core/CLI 或 Core；预约提交现在还会按冻结协议 POST `/api/captcha/check`，发送 `pointJson` 与验证码挑战 `token`，并要求响应 `data.success=true` 后才提交最终表单。验证码挑战 GET 的 `captchaType=blockPuzzle`、`clientUid=slider-<毫秒时间>`、`ts=<毫秒时间>` 参数及 `secretKey/token/originalImageBase64/jigsawImageBase64` 解析已固化测试；受控图像求解器已迁移到 Core，实时验证永不调用写操作。锁码原始 `data` 只在 Core 请求解析的短生命周期内使用，facade 与 CLI 均仅返回 `{available: boolean}`，避免打印或持久化锁码内容。

验证码位移凭据的加密已由 Core 提供：输入冻结挑战 `secretKey`、`token` 和外部图像求解器得到的横向位移，输出 AES-ECB/PKCS#7 的 `pointJson` 与 `captchaVerification`；确定性 golden 向量已覆盖 16 字节密钥。Rust 现已使用受控 PNG/JPEG 解码复刻旧版灰度、边缘、掩码和滑动匹配算法，挑战缺失或图片解析失败会失败关闭。Phase 11G 将“最多三轮”严格限定为最终发送前的挑战获取、求解与校验；最终 submit 不属于该循环。此前段落中的“求解端口尚未迁移”仅为历史记录，当前实现已完成该 Core 算法；WebVPN 场馆业务现在和其它公共操作一样使用 facade 解析出的 WebVPN runtime，日期/订单/锁码的实时失败仍单独保留，不能由会话路由问题替代解释。

2026-08-29 Cgyy 写链历史对照证据：上下文、验证码校验和最终提交三次 POST 的 `cgAuthorization` 均来自缓存的业务 `access_token`，而上下文返回的预约 `token` 仅进入冻结表单字段；当时的通用业务层会在认证失效时最多重建一次会话并重放所有请求。Phase 11G 仅保留发送前上下文/验证码阶段有证据的认证恢复，最终 submit 改用不可重放边界，取代上述历史行为。WebVPN facade 的 Cgyy 操作均固定使用解析出的 WebVPN runtime；实时验证永不调用写操作。CLI 请求省略验证码字段时，Core 复刻旧版自动获取、求解和校验流程。该次独立用户授权的 Direct CLI 探针完成提交并在等待 5 秒后取消，订单列表最终为状态 2；它不构成当前提交的写授权。`examples/buaa-api` 无对应实现，因此没有补充协议假设。

## 专项记录

### 2026-10-03 研讨室详情身份

真实 macOS/WebVPN 暴露的编号0详情、双来源九列和读取出口裁决见[订单详情身份校验](#研讨室订单详情身份校验)。请求协议和低层旧版空值兼容不变；只拒绝将缺失或不同身份视作所请求详情。

### 研讨室订单详情身份校验

日期：2026-10-03。生产 macOS App 使用 WebVPN，从实际订单列表进入详情后显示编号0、状态未知；私有桌面证据 `desktop-165`、`desktop-166`。这只能证明当前返回投影缺少目标身份，不能据此推断新的上游字段或接口。

#### 双来源对照

冻结版本沿用 `references.md`：旧版 `1f4b8f84`，示例 `a63712fa`。旧版接口 `shared/.../api/feature/CgyyApi.kt`、实现 `api/local/LocalCgyyApi.kt:194,359,620`、DTO `model/dto/Cgyy.kt`、测试 `LocalCgyyApiBackendTest.kt:464` 已核对。示例 `src/api.rs` 及各 API 模块没有同协议研讨室实现；其 CAS、加密和错误不能借用。

| 操作 | CAS/bootstrap/service | 重定向/final URL | Cookie/会话 | 方法/精确参数 | headers/body | 加密/签名 | DTO/解析 | 缓存/并发 | 错误/退出 |
|---|---|---|---|---|---|---|---|---|---|
| 订单详情 | 沿用现有 Cgyy `sso/manageLogin`、业务 `/api/login`；不改 service | 沿用已记录 Cgyy 认证跳转与 WebVPN 转换；不新增 URL | 当前账号、固定 WebVPN、业务令牌作用域不改 | GET `/api/orders/{id}`，原 `nocache`；不改请求 | 原 Accept/Referer/app-key/timestamp/sign/cgAuthorization；无 body | 原签名常量及字段排序不改 | 旧版从 `data` 映射 `CgyyOrderDto`，缺失/null 转空对象、缺 id 默认0；当前低层 parser 相同 | 不用列表资料拼装缺失详情，不扩缓存、不重试提交 | 旧版可产生编号0的伪详情；当前读取出口应拒绝缺失/非正/不同的返回 id，报 `upstream_changed`，CLI 沿用对应退出码 |

#### 决策与验证

保留冻结旧版请求、DTO和低层空值兼容规则；在只读详情操作的出口要求响应身份等于所请求订单。依据是本次真实页面缺失身份以及既有 facade 正数输入/唯一目标合同，不猜测字段，也不把列表摘要冒充成功详情。响应缺失时显示现有可恢复错误，返回仍保留父列表。只校验详情，不把合法空订单列表当错误。

新增 Mock 覆盖 `data:null`、缺 `data`、空对象、零/负/错目标 id 和正确身份，断言没有取消请求。先运行RED，修复后GREEN；日志保存在仓库外私有目录。当前实际账号的上游完整详情是否可恢复仍需 WebVPN 重验，不能用该修复宣称上游恢复。

#### 实时结构裁决（同日补充）

仓库外只读结构探针通过 facade 注入传输，保留 TLS 验证、Core 重定向/Cookie/签名，只接受 GET 和业务认证 POST；输出字段名、类型及相等性，不输出原始值。两笔列表记录独立得到 HTTP200/code200，`data` 包含 `orderInfo`、`venueInfoBean`、`orderDetailList`、`orderBuddyList`、`checkLogList`。`orderInfo` 无 `id`，也没有任何值等于请求数字编号；其 tradeNo/venueSiteId/reservationDate/theme/orderStatus 分别与对应列表记录相等。证据 `cgyy-shape4.log`。

这份实时证据取代旧版对详情平铺结构的假设：只读详情接受已观察的 `orderInfo` 包装，读取既有同名字段；场馆名称、校区和站点从 `venueInfoBean` 同名字段补足。无回传编号时，结果身份绑定本次请求的正数编号（不是把其他字段猜作编号），交易号、站点和状态必须实际存在；空包装仍报错。若响应明确带有不同 id 则拒绝。此包装不授予任何取消资格，`cancel_target`/`cancelled_target` 均为空，取消动作仍走原始 fresh authority 校验。原平铺结构继续要求 id 匹配。真实上游返回内容不能落入 fixture，新增测试全部使用合成值。

修复完成：身份缺失RED为1失败/1通过；包装支持RED为1失败/3通过；研讨室聚焦39项通过。`just check-sensitive`、`just check`（含CLI端到端）退出0；WebVPN研讨室专项9个步骤全部通过，包含实际订单详情；用途仍为static_fallback、锁码仍为空。生产macOS重建后 `desktop-274` 实际显示所选历史订单的场馆、时段、主题及状态，编号0问题已消除；学校业务写入0。日志前缀 `order-wrapper-*` 均在仓库外私有证据目录。图书馆Space/map阻塞与本修复无关，继续保留。

### 2026-09-01 场馆写入边界与收据复核

2026-09-01 bridge 写入边界复核（Cgyy/Ygdk）：本轮只修改 Flutter bridge 的本地输入校验和
intent 摘要规范化，没有改变 Core facade、上游 URL、HTTP 方法、验证码挑战、正文或错误协议。
Cgyy 的站点/日期/时段/同房间/必填文本/正数约束与 `crates/ubaa_core/src/features/cgyy.rs`
既有 `validate_submit_request` 及共享 UI typed 表单一致；验证码仍由 Core 内部获取、求解和校验。
`cgyy_canonical`/`ygdk_canonical` 仅保留公开结构和文本形状，不保留或哈希电话、主题、参与人、
活动正文、地点、照片文件名和照片字节。脱敏测试
`api::write::tests::write_digest_shapes_do_not_include_sensitive_text_or_photo_bytes` 与
`api::write::tests::cgyy_prepare_rejects_incomplete_request_before_route_resolution` 证明该边界；
本轮没有真实账号写入、验证码材料或照片上传。

2026-09-01 Cgyy 提交收据边界复核：冻结 `LocalCgyyApi.submitReservation` 的成功结果可带订单对象，
Core 已按冻结 DTO 映射；`examples/buaa-api` 仍无同一研讨室预约协议，因此未借用其字段。Flutter bridge
只把订单编号、站点编号、预约日期和订单状态投影为 `CgyyReservationReceipt`，明确排除交易号、电话、
主题、参与人和活动正文；成功后 App 优先按同一路线刷新 `cgyyOrders`，收据或刷新缺失不被视为最终核对。
`BridgeBackend 保留场馆提交的非敏感订单收据用于结果核对` 与 `场馆写入成功优先刷新订单列表用于核对`
回归固定了该边界；未改变 URL、方法、挑战或真实写入授权。

2026-09-01 Cgyy 收据 UI 呈现复核：Flutter 统一确认状态只显示收据中的公开订单编号并提示进入订单
列表核对，不把交易号、电话、主题、参与人或活动正文放入 SnackBar/日志。widget 回归
`场馆可预约时段先填写 typed 信息再进入确认页` 先复现旧泛化文案，再验证带收据文案；这只是安全呈现，
不构成真实订单成功或最终核对证据。
