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

### 2026-11-25 杭州校区空间预约（hzsm）与杭州统一认证（hzsso）

日期：2026-11-25。来源 issue：杭州校区学生请求适配。本专项先新增**只读**的场馆站点与我的预约；预约与取消见下一节，锁码等其余能力不在范围内。

#### 证据来源

1. **公开前端代码**（无需登录即可获取，记录文件名以便复核；内容会随上游发布变化）：
   - hzsm：`https://hzsm.buaa.edu.cn/venue/js/chingo.c5fe1b5a.js`（站点配置模块 `serverUrl`、`ssoLoginUrl`、`schoolCode: BUAA_H3I`；请求封装 `app-key/timestamp/sign/cgAuthorization`；签名函数 `F`；`getToken` 读取 Cookie `"sso_" + schoolCode.toLowerCase() + "_token"`；`getVenueListFront` 默认参数 `{page:-1,size:-1}`）、登录页 `chunk-4b4ad94a.e8abf532.js`（`loginHandle` → `POST /api/login`，头 `sso-token`；`roles` 存在时 `POST /roleLogin`）、订单页 `chunk-1c9e1d72.177c6fa7.js` 等（`/api/orders/mine`，读取 `content/totalElements/totalPages`）。
   - hzsso：`/frontend/login/js/app.402876f8.js`（接口表与 `getAuthTraceId`、`verifyTraceId`、`saveSession` 调用，`window.client_id`）、`/public/api/authenticate/plugin_cas/static/index.html` 与 `callback.html`（CAS 插件请求体），公开接口 `GET /api/public/bff/v1.2/load_auths?enterpriseId=idaas`（`北航登录` = `idaasplugin_cas`/`plugin_cas`，`clientDevices` 仅 `PC_BROWSER`）。
2. **账号本人浏览器实录**（2026-11-25，账号本人操作；只保留请求方法、主机、路径和查询参数名，未保留响应体、Cookie、令牌）：hzsso 登出后点击「使用北航统一认证登录」，依次出现 `generate_trace_id` → `plugin_cas/static/index.html` → `plugin_cas/login` → `callback.html?ticket=` → `valid_ticket` → `validate_trace_id` → `user_setting_info` → `session/save`；hzsso 已登录时访问 `idaasplugin_jwt38` 入口，302 到 `https://hzsm.buaa.edu.cn/venue-server/loginto?id_token=<JWT>`，之后浏览器持有 Cookie `sso_buaa_h3i_token`，前端调用 `POST /venue-server/api/login`、`POST /venue-server/roleLogin`，再读取 `website/catalog_list`、`website/init`。
3. **北京冻结来源**：本表“与北京相同”的列沿用上方矩阵的冻结旧版依据。由 hzsm 前端配置解码得到的 `app-key`（`a` 数组反转后 Base64）与签名前缀（`s` 数组 Base64）**与北京常量逐字相同**，签名函数结构相同。
4. `examples/buaa-api` 没有杭州实现，不适用。

#### 逐操作对照

| 操作 | 引导/服务 URL | 重定向/最终 URL | Cookie/会话范围 | 方法与精确参数 | 请求头/正文编码 | 加密常量 | DTO/解析字段 | 缓存/并发 | 错误/退出语义 |
|---|---|---|---|---|---|---|---|---|---|
| hzsso 登录（北航 CAS 插件） | 入口 `http://hzsso.buaa.edu.cn`；CAS 由 `plugin_cas/login` 返回的 `loginUrl` 给出，必须是 `sso.buaa.edu.cn`/`uc.buaa.edu.cn`（`is_allowed_auth_host`），否则 `upstream_changed`。 | `loginUrl` 由主会话跟随重定向，必须落到 `hzsso.buaa.edu.cn/public/api/authenticate/plugin_cas/static/callback.html?ticket=`；落在其它地址（如北航登录页）即认证失败。 | hzsso 会话 Cookie 由 Core Cookie 罐保存在当前路线 runtime；IDaaS `accessToken` 只在本次调用内存中使用。 | 1 `GET /api/public/bff/v1.2/frontend/login_data` 取 `data.clientId`；2 `POST .../authenticate/plugin/generate_trace_id` `{enterpriseAuthId:"idaasplugin_cas", enterpriseId:"idaas", clientId}`；3 `POST /public/api/authenticate/plugin_cas/login` `{enterpriseAuthId, traceId}`；5 `POST .../plugin_cas/valid_ticket` `{enterpriseAuthId, traceId, ticket}`；6 `POST .../authenticate/plugin/validate_trace_id` `{traceId}`；7 `POST /api/bff/v1.2/commons/session/save` `{access_token}`。 | JSON 正文 `Content-Type: application/json;charset=UTF-8`；第 7 步按前端拦截器（非 `public` 路径）带 `Authorization: Bearer <accessToken>`。 | 无（IDaaS 的 SM2 只用于本地密码登录，本流程不涉及）。 | 2 `data.traceId`；3 顶层 `success`、`loginUrl`；5 顶层 `success`（另有 `frontendAdapterAddress`，未使用）；6 `data.accessToken`（前端另有 `portalBound/needBind/redirectUri` 分支，未使用）；7 `data.result=true`。 | 由业务登录单飞锁串行；只在应用入口落到 hzsso 登录页时执行一次，之后重进入口一次。 | 非直连路线 `unsupported`；缺字段/非 JSON `upstream_changed`；`success!=true`、无票据、`result!=true`、重进后仍在登录页均为 `authentication_required`；不清除北航主会话。 |
| 杭州业务登录 | `http://hzsso.buaa.edu.cn/enduser/sp/sso/idaasplugin_jwt38?enterpriseId=idaas`（hzsm 前端 `ssoLoginUrl`）。 | 302 → `https://hzsm.buaa.edu.cn/venue-server/loginto?id_token=<JWT>` → `/venue/login`；重定向只额外放行 `hzsso.buaa.edu.cn`、`hzsm.buaa.edu.cn`，且仅限本功能。hzsso 未登录时落到 `/frontend/login/`，先执行上一行。 | `sso_buaa_h3i_token`（hzsm 主机）；业务 `access_token` 存在当前路线 `hz_cgyy` 槽位，与北京 `cgyy` 分开，不写入 `session.json`。 | `POST /venue-server/api/login`，无表单字段。 | 与北京相同的 `Accept`、`app-key`、`timestamp`、`sign`，`Sso-Token` 携带 Cookie 值；`Referer` 为 `https://hzsm.buaa.edu.cn/venue/home`（实录中前端页面地址）。 | 与北京相同（见证据 3）。 | `data.token.access_token`（hzsm 前端 `t.token.access_token`）。前端在 `roles` 恰好一个时自动 `POST /roleLogin`（表单 `roleid=roles[0].id`，头 `cgAuthorization` 为登录令牌），之后改用其返回的 `data.token.access_token`；Core 照此实现（仅杭州，北京不变）。 | 单飞；令牌复用；业务认证失效清 `hz_cgyy` 并最多重登一次（同北京）。 | 落地页非 200 走 HTTP 状态错误；缺 Cookie/令牌为 `authentication_required`。 |
| 杭州场馆站点 | 同业务登录。 | 同北京业务请求：不跟随重定向，落到认证主机即认证失效。 | 复用 `hz_cgyy` 令牌。 | `GET /venue-server/api/front/website/venue_information?isNeedSearchVenue=0&resourceType=1`，自动加 `nocache`（hzsm「场地预约」页 `/venue-introduce`，`chunk-c2b6f4f4`，`RESOURCE_TYPE.SITE=1`）。真机诊断显示 `website/venues` 即使 `roleLogin` 后也返回 `data:null`，故不用。2026-11-25 第二次真机诊断：`siteList` 项的场地编号字段是 `siteId`（没有 `id`），日表 `venueSiteId` 用它。 | 同北京，带 `cgAuthorization`。 | 同北京。 | 场地平铺在 `data.siteList`，项字段 `id/siteName/venueName/campusName` 与北京一致；`parse_hangzhou_sites` 复用北京字段映射，缺 `siteList` 为 `upstream_changed`。 | 不缓存列表数据。hzsm 业务令牌进入只读 worker 共享的业务会话缓存（`BusinessScope::HzCgyy`，2 小时）：v6 真机诊断显示，读组 worker 重建后每次都重走 hzsso + CAS 登录链（约 2.5–3 秒，含两次约 1 秒的等待）。令牌失效时请求收到认证失效，会从缓存剔除并重新登录一次。北京研讨室不变。 | 同北京。 |
| 杭州我的预约 | 同上。 | 同上。 | 同上。 | `GET /venue-server/api/orders/mine?page=&size=`，自动加 `nocache`。 | 同北京。 | 同北京。 | `content/totalElements/totalPages`（hzsm 订单页读取这些字段）；订单字段沿用北京 `parse_orders_at`。 | 不缓存。 | 页码小于 0 或每页数量不为正数是 `invalid_input`；其余同北京。 |

#### 决策

- 杭州与北京共用签名、业务信封、解析器；差异集中在 `features/cgyy/site.rs`，北京请求、错误文案和行为保持不变。
- **只支持直连**：北航 WebVPN 能否访问 hzsso/hzsm 没有证据，按“缺少证据时不推断”的底线直接返回 `unsupported`（诊断 `hangzhou_webvpn_unverified`），不做猜测性转换。重跑条件：取得 WebVPN 访问杭州主机的实录后再补该路线。
- hzsso 全站为 `http`；这不涉及关闭 TLS 校验，hzsm 业务请求仍为 HTTPS。

#### 验证状态

- Mock：`crates/ubaa_core/tests/hangzhou_cgyy.rs` 5 项（完整登录链请求顺序与正文、已登录复用、我的预约、WebVPN 不支持且不发请求、CAS 未签发票据）先失败后通过；`features::hzsso` 单元测试 2 项。全部使用合成值。
- **2026-11-25 真机诊断（账号本人手机测试包，只看方法/主机/路径/参数名/状态/JSON 键结构，未记录值）**：hzsso 未登录时应用入口 302 到 `http://hzsso.buaa.edu.cn/login`（不是 `/frontend/login/`），Core 两者都视为登录页；北航 CAS 先回到 `plugin_cas/idaasplugin_cas/receive_ticket?ticket=` 再 302 到 `callback.html`；`/api/login` 返回 `roles`，`roleLogin` 必需；`website/venues` 返回 `data:null`，改用 `venue_information`。
- **2026-11-25 日表与官网对照（浏览器，仅键结构）**：
  - `day/info` 的 `reservationDateList` 只含所查日期。官网的“今天/明天/后天”三个日期按钮来自 `venue_info` 的 `advanceReservationDays`（实测为 3）。Core 用它按上海时区从今天起生成可选日期（只接受 1–14），并保留所查日期。
  - 时段键含 `reservationStatus/adminTake/adminRemark/alreadyNum/useNum/…`。官网“教学使用”格对应 `adminTake=true` 加 `adminRemark`，Core 只在 `adminTake` 为真时取 `adminRemark`（trim 后不超过 20 字、不含控制字符），用于展示。官网“已售”对应 `reservationStatus=4`，UI 只在杭州场馆显示这两类说明，北京研讨室不变。
  - 场地名“羽毛球馆（篮球场）”、场次“1号（篮球场）”是上游原名，不是合并。
  - 健康中心等场地的 `reservationTotalNum` 远大于 1，是按人数计的容量模式。按 hzsm 前端 `getReservationSpaceText`：管理员占用说明优先；`reservationTotalNum > 1` 时格子显示 `alreadyNum/reservationTotalNum`；只有 `alreadyNum < reservationTotalNum` 才可选。UBAA 照此显示“已约/总数”，约满的时段（杭州专用 `hangzhou_apply_capacity`）改为不可预约，提交前的复核同样适用。
  - 该模式下的预约请求没有实录。UBAA 沿用讨论室实录的提交形状，这一点未经验证，实测之前不应视为已支持。
- **真实验证未执行**：需要维护者按 AGENTS.md 授权功能与连接方式后，用杭州校区账号做 Direct 只读验证（站点、我的预约），并确认 `roleLogin` 是否必需、各响应真实结构。WebVPN 路线见上方决策。

### 2026-11-25 杭州空间预约提交与取消（写入）

日期：2026-11-25。在上一节只读能力之上补预约与取消。**只支持免费场地，UBAA 不做任何付款**；路线同上，只支持直连。

#### 证据来源

1. **账号本人浏览器实录**（2026-11-25，Claude 内置浏览器，账号本人亲手完成两次免费场地预约并各自取消；只记录方法、主机、路径、表单/查询参数名、JSON 键结构与状态，未记录值、令牌、Cookie、手机号与验证码图片）。场地为一处免费讨论室；实录中误点产生的请求已剔除。取消一次在“我的预约”、一次在“个人中心 → 场馆预约 → 校园场馆预约记录”，两处调用同一取消接口。
2. **hzsm 前端**：滑块验证码为 AJ-Captcha `blockPuzzle`；`orderPin` 由站点配置中的公开前端常量（`k`/`v` 数组）组成 AES-128-CBC 密钥与 IV，对 `"clientX,clientY"`（用户点击“提交”的屏幕坐标）加密后输出小写十六进制。
3. 北京冻结来源：`pointJson`/`captchaVerification` 的 AES-ECB 构造与北京 `crypto.rs` 相同。

#### 逐操作对照

| 操作 | 请求 | 关键字段 | 响应 | 失败与重试 |
|---|---|---|---|---|
| 日表 | `GET /venue-server/api/reservation/day/info?venueSiteId&searchDate`（实录另带 `hasReserveInfo=1`） | — | 键与北京相同：`reservationDateList`、`spaceTimeInfo[{id,beginTime,endTime}]`、`reservationDateSpaceInfo`、`reservationTotalNum`、`isFee` 等；状态码 1=空闲、2=不可用、3=待支付、4=已预约，复用北京 `parse_day_context`。 | 只读，同北京。 |
| 取验证码 | `GET /venue-server/api/captcha/get?captchaType=blockPuzzle&clientUid&ts` | — | `repData{secretKey,token,originalImageBase64,jigsawImageBase64}` | 只读。图片只交给用户拖动，不落盘、不入库。 |
| 校验滑块 | `POST /venue-server/api/captcha/check`，表单 `pointJson`、`token` | `pointJson` = AES-ECB(secretKey) 加密的 `{"x":X,"y":5}`；X 为用户拖动距离按 310 像素宽原图换算 | 失败 → `invalid_input`，**不提交预约** | 不重试，用户换一张后重新提交。 |
| 提交预约 | `POST /venue-server/api/reservation/order/submit`，表单 `captchaVerification`、`captchaToken`、`reservationOrderJson`、`reservationDate`、`weekStartDate`、`reservationType`、`orderPrice`、`orderPin`、`venueSiteId`、`phone` | `reservationOrderJson` = `[{"spaceId":"…","timeId":"…"}]`（字符串 id）；`weekStartDate` = 日表 `reservationDateList[0]`；`reservationType` = `-1`；`captchaVerification` = AES(token + `---` + pointJson) | `data{id,tradeNo,reservationStartDate,reservationEndDate}`。**没有北京的 `order/info` 步骤。** | 业务码非 200 → `business_rejected`；已发出但结果不明 → `outcome_unknown`，不自动重试。 |
| 0 元确认 | `GET /venue-server/api/venue/finances/order/detail?venueTradeNo` → `POST /venue-server/api/venue/finances/order/pay`，表单 `venueTradeNo`、`isApp=0` | 提交后订单处于待支付（10 分钟超时）；前端随即确认 | detail 含 `payFee`；pay 返回 `{payFee:0.0}` | `payFee > 0` 时**不调用 pay**，返回 `business_rejected` 并带订单号让用户自行处理。 |
| 取消提醒 | `GET /venue-server/api/orders/cancel_tip` | — | `data.tip` | 只读，作为确认提示。 |
| 取消 | `POST /venue-server/api/venue/finances/order/cancel`，表单 `venueTradeNo`、`handleReason` | 订单号来自“我的预约”的 `tradeNo`；原因由用户填写，1–200 字 | `data:null` 视为成功 | 同提交，不重试。 |

#### 决策

- **验证码由用户亲手完成**：北京研讨室会自动识别拼图；杭州不复用，界面显示原图与拼图块，由用户拖动，应用只做坐标换算。`orderPin` 只加密用户真实点击“提交预约”时的坐标，不构造坐标。
- **收费场地在任何写请求前拒绝**：提交前用 fresh 日表复核，`isFee != 0`、时段资格非 Allowed 都返回 `invalid_input`，不发校验/提交请求。
- `orderPrice` 实录中非空，免费场地按 `"0"` 提交——这是本节唯一的推断，依据是 `isFee=0` 与 pay 返回 `payFee:0.0`；若维护者实测发现不符，以实测为准。
- “我的预约”列表的取消入口只排除明确已取消（`orderStatus=2` 或审核状态为负）与已结束的订单；杭州的取消时限没有证据，不沿用北京“开始前 4 小时”规则，交给 `cancel_tip` 与取消接口判断。
- 写入后以“我的预约”列表为唯一回读入口。
- **时段选择规则（2026-11-26 按 hzsm 前端 `reserveHandler`/`pushSelected` 修正）**：
  - 杭州站点的学校代码是 `BUAA_H3I`，`isBUAA()` 为假，因此官网只要求同一房间（同 `dataId`），**不要求相邻**（除非站点配置 `spaceContinue`），也不是北京的“最多两段”。
  - 单次上限 `maxCount` 取自 `/api/reservation/campus/venue/info` 的 `reservationNumMax`，或站点的 `reservationSpaceCount`；`isTimePay` 时为 1。UBAA 目前不请求该接口，所以不在本地限制数量，上限交给服务端判断，只挡住空选择和超过 48 段的异常输入。
  - `reservationTotalNum` 是单个时段可容纳的人数（官网 `alreadyNum < reservationTotalNum` 才可选），不是单次可选的时段数。此前把它当成数量上限是误用，已删除。
  - 实测（账号本人 v8）：UBAA 只能选两个，官网可以选更多，与上述代码一致。

#### 验证状态

- Mock：`crates/ubaa_core/tests/hangzhou_cgyy.rs` 新增 6 项（按实录字段提交并完成 0 元确认、收费场地写前拒绝、滑块失败不提交、发现需付费不代付、路线变化不发请求、取消先读提醒再只发一次）；`hangzhou_write` 单元测试覆盖 `orderPin` 往返与表单 JSON。Dart 侧覆盖写准备参数映射与写后回读入口。全部使用合成值。
- **真实写入验证未执行**：按 AGENTS.md 第 7 条，需要维护者对具体操作、场地、路线与时间逐次授权后，再用杭州校区账号在 Direct 路线验证一次预约与取消。WebVPN 见上一节决策。

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

### 场馆信封错误分类

重新核对冻结 `CgyyApi.kt`、`LocalCgyyApi.kt::requestJson`、`Cgyy.kt`、`LocalCgyyApiBackendTest.kt`。固定示例的 `src/api.rs` 与各业务模块无同协议，下列操作的九列均不适用。旧版逐操作的 CAS/引导、终点、令牌、参数、头/编码、签名、DTO 与重试保持[只读矩阵](#场馆预约只读查询)及[写入矩阵](write-actions.md#ubaa2-直接写操作与评教2026-08-28)的取舍。

| 操作 | CAS / service | 重定向与最终地址 | Cookie / 凭据 | 方法与参数 | 头与编码 | 加密签名 | DTO / 解析 | 缓存、并发与重试 | 错误语义 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 业务引导和登录 | `sso/manageLogin`、`api/login` | 原允许跳转与 SSO 识别 | 从路线内 Cookie 换取业务令牌 | GET 引导，POST 空表单 | Sso-Token 及原签名头 | 原 MD5 | `code/data.token.access_token` 不变 | 业务会话单飞 | 有效业务拒绝、HTTP 异常、语法和结构区分 |
| 站点、用途、日期、订单列表及详情、锁码 | 同引导 | 原业务请求不跟随跳转，SSO Location 单独识别 | 同一路线业务令牌 | 逐项沿原只读矩阵的 GET、日期/分页/站点参数及 `nocache` | 原 Accept、Referer 与签名头，无正文 | 原 MD5 | 各操作只按成功信封读取原 DTO，保留安全码与字段类型 | 保留认证一次恢复和用途静态回退 | 有效业务信封沿用旧版优先；HTTP 429 且业务未成功时，以限流解释该失败，保留可验证的业务码 |
| 预约、取消及其写前资格 | 同引导 | 原固定路线和终点 | 同一令牌代次 | 沿原订单、预约上下文、验证码挑战、校验及最终提交的 GET/POST | 原签名头、表单及验证码编码 | 原 MD5 和挑战 AES | 原严格资格、收据与最终响应，不暴露锁码和凭据 | 只恢复可重放的前置请求，最终请求单次发送 | 前置共用信封分类；已发送后的未知结果保留该语义，不把推测当作确定拒绝 |
