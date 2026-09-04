# 决策记录

## 2026-09-04：Phase 11H 场馆取消双 fresh authority 与最终单次发送边界（当前有效）

本条只固定 Phase 11H 的来源与实施合同，不宣称当前生产实现已经满足。重新核对冻结
`ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 的 `CgyyApi.kt`、`LocalCgyyApi.kt`、
`LocalCgyySigner.kt`、`Cgyy.kt`、Cgyy 订单取消状态/时间测试以及旧 server 实现。固定
`examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a` 的模块清单没有 Cgyy、
`venue-zhjs`、`cgAuthorization` 或场馆订单协议，九列均为“不适用且不等价”；不得从 Boya 课程取消、
通用 SSO/VPN、credential、Cookie 或错误类型类比补字段。

冻结引导为无显式 `service` 参数的 GET
`https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin`，再以 `Sso-Token` 空表单 POST
`/api/login`；`data.token.access_token` 只作为当前路线业务请求的 `cgAuthorization`。订单详情唯一有
证据的端点为 GET `/api/orders/{id}`，最终取消为 URL 编码空表单 POST
`/api/orders/new/cancel/{id}`；旧 relay `/api/v1/cgyy/orders/{id}/cancel` 不是上游。请求保持冻结
`Accept`、mobileReservation Referer、`app-key/timestamp/sign/cgAuthorization` 与小写 MD5 签名，GET
`nocache` 参与签名；取消没有 captcha/challenge、AES 或其它加密。Cookie/token 只在当前用户和路线内存使用，
不落盘、不跨路线，也不与预约 token 混用。

冻结客户端自动跳转、固定 Direct 且没有 hop/host/terminal 白名单，与当前路线隔离及 WebVPN Cookie 同步
决策冲突，明确不倒退复制。prepare 与 commit 必须分别在解析出的同一路线上 fresh GET
`/api/orders/{id}`；请求 ID 网络前必须为正，响应只接受唯一 JSON object 中 canonical 正整数 `id` 严格等于
请求 ID。`data=null`、数组、缺失、畸形、非正或不匹配 ID 一律 unknown 并在发送前拒绝；不得信任 UI
label/value、缓存列表或调用方提交的状态，也不得发明冻结来源中不存在的分页扫描消歧协议。

资格矩阵固定为：canonical `orderStatus in {1,3}` 且 `checkStatus in {1,2,3,4,5,6}` 才能
allowed；`orderStatus=2` 或任一负 `checkStatus` 为 denied；状态缺失、畸形、0 或其它值均为 unknown。
冻结 `displayStatus` 会放行部分缺失、0 或未知正审核状态，本阶段为遵守 typed unknown 失败关闭而有意收紧，
不得把旧 UI 宽松行为伪称为当前允许。取消时限固定按 `Asia/Shanghai`：start 有效时只允许严格
`now < start - 4h`，恰好 deadline 即拒绝；start 缺失或无效才回退有效 end 并要求 `now < end`；start/end
都缺失或无效时不增加时间限制，但严格 ID 与状态门禁仍照常执行。Core 必须使用可注入时钟，不依赖设备时区。

冻结 client 会在认证失效后重放业务请求，旧 server 对认证错误或泛 Cgyy 错误还可能重建 client 后再次取消；
冻结 UI 则从缓存订单直接写且没有 fresh authority。上述行为违反当前一次性 intent 与结果未知不自动重试合同，
明确不复制：认证准备和两次详情复核都在发送边界前完成，final POST 只经 `request_non_idempotent` 恰好调用
一次，401、认证/业务跳转或任何其它结果都不得刷新认证后重放。只有冻结支持的 `code=200` 产生固定安全成功
结果；一旦 POST 已发送，非 200、final URL 异常、transport/timeout、Cookie、非 JSON、非 object、code
缺失或畸形统一返回不可重试 `outcome_unknown`。raw message/body、Cookie、token、签名和订单敏感字段均不得
进入公共 DTO、CLI、Bridge、日志或文件。

确定成功或 `outcome_unknown` 后都只在原路线读取订单列表与同 ID 详情，绝不再次提交。仅 fresh canonical
同 ID `orderStatus=2` 是取消证据；空详情、读取失败、ID 不匹配或列表/详情冲突保持未核对。历史独立授权探针
曾出现取消信封成功后列表仍为状态 1、稍后列表才变为状态 2，详情则先失败再返回空 data，因此取消响应不能
自行升级为最终业务状态，读回失败也不能触发自动重发。本条没有授权或执行真实取消；实施必须先以脱敏
fixture/Mock 完成严格 ID、状态、上海时间边界、双 fresh、单 POST、`outcome_unknown`、安全结果与列表/详情
回读 RED 门禁。

## 2026-09-04：Phase 11G 场馆预约 typed 资格与最终单次发送边界（当前有效）

本阶段重新核对冻结 `ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 的
`LocalCgyyApi.kt`、`LocalCgyySigner.kt`、`LocalCgyyCaptchaSupport.kt`、`Cgyy.kt`、
`CgyyViewModel.kt` 及其测试。固定
`examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a` 的 `src/api.rs` 与 `src/lib.rs`
没有 Cgyy、`venue-zhjs`、`cgAuthorization` 或场馆验证码协议；其通用 SSO/VPN、可落盘 credential 与 raw
response 错误只属于其它 API，九列均为“不适用且不等价”，不得类比补 service、Cookie、字段、加密或错误。

冻结引导为无显式 `service` 参数的 GET
`https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin`，再以 `Sso-Token` 空表单 POST `/api/login`；
`data.token.access_token` 只作为后续 `cgAuthorization`，day-info 返回的预约 `token` 只进入上下文与最终表单。
冻结客户端会自动跟随跳转、固定走 Direct 且没有 hop、host 或 terminal URL 白名单；这与当前路线隔离和已记录的
WebVPN 网关 Cookie 同步证据冲突。本阶段不倒退复制该行为：继续使用当前有界 SSO/WebVPN 路线适配，不跨路线
复用 Cookie/token，也不从固定示例借用 VPN service。该既有路线决策不等同于两份冻结来源一致。

预约写链固定为 fresh GET `/api/reservation/day/info`，URL 编码表单 POST `/api/reservation/order/info`，
GET `/api/captcha/get`、表单 POST `/api/captcha/check`，最后表单 POST `/api/reservation/order/submit`。
上下文严格携带五字段 `venueSiteId/reservationDate/weekStartDate/reservationOrderJson/token`；最终提交严格携带
十四字段：前四项加 `phone/theme/purposeType/joinerNum/activityContent/joiners`、两个映射为 `0/1` 的布尔项、
`captchaVerification` 与预约 `token`。请求继续使用冻结 Accept、Referer、`app-key/timestamp/sign` 及
`cgAuthorization`；MD5 签名、GET `nocache`、captcha AES-ECB/PKCS5Padding、标准 Base64、固定
`{"x":offset,"y":5}` 与 `challenge-token---point-json` 明文形状均不改变。

typed 资格只在请求日期键精确存在、站点/空间/时段身份完整且唯一时产生；冻结 parser 在请求日期缺失时回退
`reservationDateSpaceInfo` 首键的兼容行为只供只读展示，绝不授权写。槽位只有
`reservationStatus=1`、`tradeNo=null`、`orderId=null` 且 `takeUp!=true` 时为 `allowed`；状态或占用字段
缺失/畸形造成无法判定时为 `unknown`，明确其它状态为 `denied`。稳定 action 携带 typed 站点、日期、空间、
空间组及时段目标，不从中文 label/value 反向解析。prepare 与 commit 都 fresh 复核同一路线目标；选择必须无
重复、同一空间、数量为一至两个，两个时段按 fresh `timeSlots` 列表索引相邻而不是按 `timeId` 数值相邻，
`venueSpaceGroupId` 必须与 fresh 空间值一致。

冻结提交合同只证明 `phone/theme/activityContent/joiners` trim 后非空、`joinerNum>0`；当前产品继续要求
`purposeType>0`，不臆造手机号格式、文本长度、参与人数量相等或 `reservationTotalNum` 容量规则。冻结 UI 会
持久化电话、主题、活动正文和参与人等表单明文，本阶段明确不复制；Bridge pending intent 只在内存保存一次，
opaque 摘要不得包含这些值，取消、过期、提交或 dispose 后立即删除。

冻结 `repeat(3)` 实际把 captcha 获取、求解、校验和最终 submit 全部包在同一个宽泛 `catch` 中；底层
`requestJson` 还会在认证失效时重放包括最终 POST 在内的业务请求。该行为与一次性 intent 和结果未知不自动
重试的当前安全合同冲突，明确不复制：最多三轮只覆盖最终发送前的 captcha 挑战/校验；最终 submit 只通过
`request_non_idempotent` 发送一次，绝不认证重放或再次进入 captcha 循环。发送后 transport、Cookie、
认证/业务跳转、非 JSON 或结构不足造成的歧义返回不可重试 `outcome_unknown`；明确 `code=200` 按冻结产品
语义确认提交，订单可选并只以正订单编号形成安全收据，后续列表核对不重放写请求。非成功信封和公开结果使用
固定安全文案，不透传可能包含 token、个人数据、控制字符或上游原始正文的 message。本阶段只使用脱敏
fixture/Mock，不执行真实场馆预约，也不授权其它真实写操作。

## 2026-09-04：Phase 11F 图书馆取消 typed 资格与单次发送边界（当前有效）

本阶段重新核对冻结 `ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 的
`shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalLibBookApi.kt`、
`shared/src/commonMain/kotlin/cn/edu/ubaa/model/dto/LibBook.kt`、
`shared/src/commonTest/kotlin/cn/edu/ubaa/model/dto/LibBookBookingStatusTest.kt` 和
`shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalLibBookApiBackendTest.kt`。固定
`examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a` 的
`src/api.rs` 模块清单没有 LibBook、图书馆座位或 `booking.lib.buaa.edu.cn` 协议，因此 URL、重定向、
Cookie/会话、方法/参数、Header/编码、加密、DTO、并发/重试和错误语义九列均为“不适用且不等价”，不得从
其通用 SSO 或其它模块类比补值。

冻结本地产品的取消请求为 JSON POST `/v4/space/cancel`，wire 正文只有 `{id}`；它没有按 ID 查询详情、全量
扫描或 arbitrary ID 校验端点。Phase 11F 因此把产生 action 时的正数 `page/limit` 保存在本地 authority
上下文中，prepare 与 commit 都只能 POST `/v4/member/seat` 的同一页，并要求目标 booking ID 在 fresh 页中
唯一匹配；取消 authority 还要求响应显式携带 canonical 正数分页元数据，别名同时存在时必须一致，不能把
缺失、畸形、非正或冲突值回退成 action 的页。`page/limit` 绝不进入最终取消正文。只有非空 ID 且 canonical
整数状态 `1` 为 `allowed`，状态
`6/8` 为 `denied`；状态缺失、null、畸形、非 canonical 整数或其它值均为 `unknown` 并安全拒绝。
`statusName` 仅供展示，不能产生或改变 typed 资格。该 fail-closed 规则是当前安全合同的明确收紧：冻结产品
会让中文 `statusName` 参与判断，并默认允许部分缺失或未知状态，本阶段不复制这一行为，也不虚构详情协议。

冻结 `LocalLibBookApi.kt` 会让共享业务客户端自动跟随跳转，并在识别认证失效后刷新 bearer、重放原请求；
旧 server relay 还可能在重建 client 后再次调用。Phase 11F 不复制业务跳转和认证失效重放：CAS 登录及只读
fresh 复核必须在越过发送边界前完成，最终 cancel 只调用一次 `request_non_idempotent`，不接受认证跳转且
绝不自动重放。请求一旦已经发送，timeout、transport、HTTP/认证跳转、非 JSON 或结构不足而无法判定时返回
不可重试的 `outcome_unknown`，随后只允许刷新预约列表供用户核对。冻结 JVM/Android LibBook engine 的
trust-all certificate/hostname verifier 违反当前 TLS 安全边界，明确不采用。

冻结成功 fixture 只证明上游 raw `code=1` 与精确 `message=取消成功`；冻结本地实现允许 canonical
`code=0/1`，本阶段只在二者与精确成功文案组合时确认成功。确定的已取消、已结束、不存在或失效消息
只用于映射固定安全业务错误，已知负面文案可映射固定 `success=false`；其它新成功文案一律为
`outcome_unknown`。最终取消与 authority `/v4/member/seat` 的非成功 envelope 都不得把 raw message 带入
公开结果或错误；Core 在取消专用解析边界固定归约 `upstream_changed` 文案，CLI 与 Bridge 再按操作做同样的
防御性投影，避免夹带预约标识、个人数据、控制字符或 token。
这些证据不证明 raw `success` 或 `status` 字段参与上游成败。产品
`LibBookCancelResponse { success, message }` 是冻结 backend 映射后的 DTO，Core、CLI 与 Bridge 不得据此
猜测不存在的 raw 字段，也不得在无法判定时默认成功。本阶段只使用脱敏 fixture/Mock，不执行真实取消，且不
授权其它真实写操作。

## 2026-09-04：Phase 11E 图书馆预约 typed 资格与发送边界（当前有效）

固定 `examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a` 没有 LibBook、座位或预约
协议，九列均为“不适用且不等价”；不得类比其 URL、字段、会话、加密或错误。Phase 11E 只采用冻结
`ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 的适用本地产品实现：先以
`Space/map` 当前详情核对日期、唯一时段 ID 与起止时间，再以 `Space/seat` 当前结果核对唯一座位。座位
`status=1` 为 `allowed`，`2/3` 为 `denied`；状态缺失、null、畸形、其它值、空目标、目标缺失或重复均为
`unknown` 并安全拒绝。prepare 与最终提交都必须 fresh 复核，不信任宿主回传的展示字段或旧布尔值。

稳定产品目标为 `(area_id, seat_id, day, segment)`；`start_time/end_time` 必须与 fresh 时段严格一致并只作
确认、座位查询和读后核对元数据。冻结预约密文明文严格为
`{seat_id,segment,day,start_time:"",end_time:""}`：`area_id` 不进入密文，调用方提供的起止时间也不得
进入密文。AES-128-CBC、PKCS#7、日期八位数字加逆序组成的 key、固定 IV
`ZZWBKJ_ZHIHUAWEI` 和标准 Base64 均保持现有 golden，不因 typed 化改变。

冻结本地 `LocalLibBookApiBackend.reserve` 对 `code=0/1` 下的明确业务拒绝返回正常
`LibBookReserveResponse(success=false)`，而冻结 server relay 会把同类结果抛错；本阶段采用适用的本地产品
语义，Core、CLI 与 Bridge 均不得把确定的 `success=false` 覆盖为成功。冻结低层客户端还会在认证失效文本后
重放包括预约在内的请求；该行为与当前一次性 intent 合同冲突，明确不复制。登录和只读复核可在发送前刷新
业务 bearer，最终 `/v4/space/confirm` 必须通过 non-idempotent 边界只发送一次；发送后的 transport、timeout、
HTTP/认证歧义、非 JSON 或无法确定业务结果的响应统一为不可重试的 `outcome_unknown`。

`LibBookSeat.status` 从任意字符串改为可空整数，并以 `reserveEligibility/reserveTarget` 取代
`isAvailable`，会破坏严格的 FFI 与 CLI JSON 消费者。因此 Flutter bridge contract 从 v3 显式升为 v4，CLI
envelope/schema 从 v4 显式升为 v5；磁盘 `session.json` 继续使用 schema v2。Flutter 的完整
`LibbookReserveAction` 只由 typed 座位目标、typed 资格和 typed 查询上下文组成，中文 label/value 仅用于展示。
这一确定性阶段不执行真实预约，也不授权其它写操作。

## 2026-09-04：Phase 11D 课堂签到 typed 资格与发送边界（当前有效）

课堂签到的生产修复只采用两份冻结来源一致的事实和适用冻结本地实现：今日课程使用 `signStatus`，值 `0`
表示可签到、`1` 表示已签到，缺失、畸形或其它值为 `unknown` 并安全拒绝；写目标是今日列表中唯一匹配的
课程安排 ID。prepare 与最终提交均须重新读取今日课程，不能信任宿主回传的展示字段或旧状态。

最终请求按冻结本地实现使用 `courseSchedId=<课程安排 ID>`、form `id=<业务登录返回的用户 ID>` 和
`sessionId` 请求头；三个值使用不同脱敏向量测试，防止再次混淆。响应同时解析顶层 `STATUS/ERRMSG` 与嵌套
`result.stuSignStatus`；明确的业务 false 保持 `SigninActionResult.success=false`，Bridge 不得无条件改成成功。
最终 POST 通过 `request_non_idempotent` 且只发送一次，发送后的 transport、Cookie、认证跳转、非 JSON 或
结构不完整响应归为 `outcome_unknown`、禁止自动重放；发送前读取失败保持原错误分类。

`signStatus` 从必填整数改为可空并新增 eligibility/target，会破坏严格的 FFI 与 CLI JSON 消费者；本阶段
因此显式把 Flutter bridge contract 从 v2 升为 v3、CLI envelope/schema 从 v3 升为 v4，并让 CLI schema
新增 `SigninActionResult` 成功数据分支。不得在旧版本号下静默改变字段。明确的业务拒绝仍是成功解码出的
`SigninActionResult { success: false }`：CLI 外层 `ok=true`、退出码 0 表示调用完成且结果确定，脚本必须读取
内层 `success` 判断签到是否完成；Bridge 同样保留 `success=false`，UI 不显示成功、不触发成功后的刷新。
这一选择复刻冻结 API 的 `Result.success(SigninActionResponse(... success=false))`，不发明新的错误码。

冻结本地与固定示例在登录 URL、端口、时间戳方法、参数载体及会话头身份上仍有冲突。本阶段保持当前已有、
由 Direct/WebVPN 只读证据支持的登录/读取路径，不借结构治理改写这些未决项；也不执行真实签到。UI 只消费
Core→Bridge→Domain 的 typed action，中文状态文案只用于展示。

## 2026-09-04：CLI JSON envelope 显式升级为 schema v3（Phase 11C 历史决策；已由 v4 取代）

Phase 11C 将 Bykc 已选课程的 `checkin` 从必填整数改为可空，把 `canSign`/`canSignOut` 两个布尔字段替换为
含 `unknown` 的 `signEligibility`/`signOutEligibility`，并把写请求越过发送边界后的不确定结果公开为
`outcome_unknown`。字段删除、类型放宽、三态资格和封闭错误集合扩展都会破坏严格的 schema v2 消费者，
因此不得继续标记为 v2：CLI 的全部成功、失败、参数错误、聚合认证/注销和隐藏诊断 envelope 统一显式升级
为 schema v3，JSON Schema 与真实序列化合同只接受版本 3，并明确拒绝旧 v2 envelope。

这个版本只属于 CLI stdout 公开合同。`session.json` 继续使用 schema v2 双路线快照，`config.toml` 继续使用
版本 1；本决策不迁移、不重写会话存储，也不改变 revision CAS。Phase 11C 之前绑定 schema v2 的历史提交、
测试结果与验证记录保持原样，不回写为 v3；Phase 11C 的实现证据仍按 v3 解释。Phase 11D 起当前
CLI/Core-live/实时验证器一律按上方已登记的 v4 合同校验。

## 2026-09-03：Phase 11 typed 写资格的来源边界（当前有效）

本轮在把 Flutter 写入口从中文展示字段迁移到 typed action eligibility 前，重新逐操作核对了
`ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 与
`examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a`。审查发现既有
`source-parity.md` 把固定示例中的 Bykc、Class/Signin 和 Evaluation 等价实现误记为不适用，并有若干
合成测试固定了错误字段。处理原则如下：

- 对两份冻结来源一致的事实先补脱敏 RED，再修正生产实现：Signin 今日课程字段为 `signStatus`、签到结果为
  `result.stuSignStatus`；Bykc 签到正文坐标键为 `signLat/signLng`；Ygdk 提交时间为上海时区 Unix 秒；
  LibBook AES 明文不包含 `areaId`，且 `start_time/end_time` 固定为空字符串。
- Signin 的业务登录端点、业务会话头身份、时间戳请求方法、`id` 参数位置以及 Direct/WebVPN 端口在两份
  冻结来源之间冲突。当前周期没有逐目标真实签到授权，既有只读成功也不能证明写协议。因此该冲突边界保持
  未决，不以结构整理改动登录、会话头、方法或端口；只修复两份来源一致的 DTO/结果层级，并以适用的冻结
  本地实现修正当前明确错误的用户 ID 值。任何进一步改动必须先取得脱敏实时写链证据或新的逐操作授权。
- Bykc 签到位置算法采用被迁移产品的冻结本地实现：每次提交前重读已选课程和签到配置；从完整签到点列表随机
  取点，仅在被选中点半径为正数时在圆内生成坐标，否则要求调用方提供完整坐标。固定示例的 `±1e-5` 偏移只
  记录为冲突证据，不混入实现。
- Bykc 签到与签退时间边界采用冻结本地产品实现的闭区间；固定示例只有被忽略的真实账号样例使用严格开区间，
  且没有已选、考勤、考核或负例证明，不能覆盖产品规则。旧实现将缺失的 `checkin/pass` 当作未签到/未通过，
  typed 资格层为避免把不完整上游状态推成可写，改为 `unknown` 并安全拒绝。`courseSignType` 仅在冻结 DTO 中
  透传且 UI 未消费，实际 action 封闭映射 `signType=1/2`。
- 冻结旧版会对任意 Bykc 请求异常强制登录并重放一次，其中包含非幂等签到；该行为与一次性 intent、结果未知
  不自动重试的当前安全合同冲突，故不复制。请求头差异采用被迁移产品的 Origin/Referer 与双 token 形状；
  固定示例的单 `Authtoken` 只作端点和加密交叉证据。
- Cgyy 一次预约采用冻结 ViewModel 的产品限制：只能选择同一空间、最多两个且相邻的可预约时段；
  `joiners` 与冻结提交合同一致，作为必填输入。固定示例没有等价 Cgyy 协议，不能覆盖该规则。
- Cgyy 取消资格由 Core 使用 `Asia/Shanghai` 解释上游无时区时间，并在 prepare 与 commit 前复核；开始时间
  存在时严格要求当前时刻早于“开始前四小时”，否则回退结束时间。状态未知时拒绝；仅在冻结规则允许且
  两个时间都不可解析时不额外增加时间限制。
- Evaluation 的答案选择和请求顺序采用适用的冻结本地实现；固定示例的首题策略及提交后的额外探测请求仅作
  冲突记录，不拼接为新协议。读取结果必须保留提交所需的完整课程 DTO，逐课程失败不得被 bridge 投影成整体成功。
- UI action 缺失或 eligibility 未知时一律拒绝。中文 label/value 只用于展示；Core prepare/commit 的重新读取
  与资格复核仍是最终权威。以上确定性开发不授权真实选课、退选、签到、预约、取消、上传或评教提交。

## 2026-09-02：MethodChannel 平台能力合同（当前有效）

- 生产宿主统一使用 `cn.edu.buaa.ubaa/platform` 的 typed MethodChannel：权限通过
  `permission.request` 返回固定状态，安全凭据通过 `credentials.capability/read/write/clear`
  使用版本化 namespace，照片通过 `photo.capability/pick` 传递有界字节、文件名和 MIME。
- Dart 适配器在能力探测失败、原生异常或返回值不符合合同（无效凭据、非图片、文件名越界、照片
  超过 10 MiB）时安全拒绝；不把原始路径、URL、Cookie、令牌或平台异常正文带入 UI、日志或 Core。
- `createDefaultPlatformCapabilities()` 已接入官方 Flutter 与 OHOS 薄宿主；无原生 handler 时保持
  `isAvailable=false`，不能把内存/Noop 实现描述为系统安全存储。Android/iOS/macOS/Linux/Windows
  的原生安全存储和 HarmonyOS HUKS handler、设备权限/生命周期 smoke 仍是后置 `BLOCKED`。
- 该决策只确定 Dart/原生边界，不引入任何上游协议字段或真实账号副作用；行为由
  `packages/ubaa_platform/test/method_channel_adapters_test.dart` 的 Mock 合同测试覆盖。

## 2026-09-02：无签名平台能力边界与宿主全功能 smoke（当前有效）

- 采用 `PlatformPermissionGateway` 和 `PlatformPhotoPicker` 作为相机、相册、文件、前台位置及照片输入的唯一宿主边界；不可用实现安全拒绝，内存实现仅用于脱敏测试。照片不以路径或原始文件元数据跨入业务层。
- 官方 Flutter/OHOS 宿主只接收可选 picker 注入；无设备、证书或原生插件时不伪造照片上传成功。设备权限、硬件安全存储和真实照片上传继续记录为后置 `BLOCKED`。
- 宿主集成测试扩展为普通 8 项和高级 4 项详情入口逐项打开/返回，证明共享导航和 typed 状态链路；该 fake 证据不替代 FRB/Core-live 或实体设备证据。
- 无签名 `release-preflight` 增加 Cargo SBOM、Dart/Flutter 锁文件版本和许可证审计，并在合同 CI 上传短期 artifact；报告不含账号、令牌、原始响应或签名材料。
- `a7d4ac0` 将该报告的锁文件枚举固定为 Git 跟踪路径，避免把构建目录临时锁文件带入可复核结果；复跑确认 8 个锁文件且工作树保持干净。
- `9dfe078` 将 `just release-preflight` 的 CI/Runbook 调用统一为绝对报告目录的位置参数；合同 CI
  `33573554458` 已验证 `just check`、无签名报告生成和 artifact 上传成功。后续只有该位置参数形式
  作为发布前置报告的合同调用，错误的 `report_dir=...` 形式不再接受。
- 当前提交 `2ceda40` 复核确认宿主 picker 必须经 `PlatformPermissionGateway` 包装：未注入权限实现时
  默认安全拒绝，只有明确注入并获得 `granted` 才能调用 picker。该提交的干净工作树
  `release-preflight` 与 OHOS API26 无签名 HAP/arm64 包检查均通过；构建输出不进入版本库。

## 2026-09-02：无签名执行目标取代正式发布门禁（当前有效）

用户明确要求在没有签名证书、签名账号和实体设备的条件下继续完成代码、确定性测试、无签名构建、静态检查、来源对照和发布文档。`goal.md` 因此新增“无签名执行合同”：P1–P4 的功能与安全闭环、P5 的平台代码/权限/生命周期/安全存储边界、P6 的无签名 RC/产物审计/SBOM/runbook 仍是本轮必需门禁。

正式签名 HAP/Release、公证、商店上传、实体设备安装/hello、HUKS/硬件安全存储和设备权限验证不再阻塞本轮目标，统一记录为后置 `BLOCKED`。无签名产物只能标记为开发或 RC 证据，不能宣告正式发布；真实写入依旧要求每次具体操作、目标、路线和时间的独立授权，本次范围变更不授权任何真实副作用。

## 当前有效性说明（2026-08-31）

本文件按日期保留协议证据和历史冲突。2026-08-29 的真实写探针属于周期外、一次性授权的
历史记录，不是当前验收例外；本周期仍禁止真实签到、选课、预约、取消、上传和评教提交。
旧版聚合验证、`route=auto` 真实示例、jq/摘要盐及曾经的 Cgyy Direct 兼容分支均已被后续
决策取代，当前入口只有 Core-live 的显式 Direct/WebVPN 逐操作只读矩阵。

本周期新增的 `auth/prepare` 证据映射到登录内部保存的准备状态，Core-live 不再重复发起
准备请求；SPOC/ Judge 诊断逐项输出 `global_page_count`、`course_count`、`raw_anchor_count`
和 `filtered_unique_count` 等安全计数。认证准备或登录失败会为所选矩阵补齐所有后续
`BLOCKED` 项，依赖 ID 缺失才使用带原因的 `NOT_APPLICABLE`。Cgyy 用途若采用冻结静态
回退，会显式输出 `source=static_fallback`，不伪装为上游成功。所有 facade 写入口在请求
前重新校验外部会话 CAS 修订；stale writer 的 Mock 证明不会发出写请求。`core-live.sh`
已取消 `exec`，并用统一 EXIT/信号陷阱清理自动临时目录，显式目录仍由调用方管理。

本次复核补充四项边界：Core-live 的 SPOC/Judge 诊断行与普通结果共享同一次响应并明确
`reuse_from`；课表没有正数周序号时输出 `NOT_APPLICABLE`，禁止猜测周次；Cgyy 业务 3xx
跳转到 SSO 时分类为认证失效，其它 3xx 分类为上游变化；Cgyy 日期上下文令牌和验证码
材料均留在 Core 内部，Cookie 单值读取也必须按请求 URL 过滤域名、路径、Secure 和过期时间。
聚合 facade 的普通读操作同样在发起请求前校验外部会话 revision，防止过期读客户端产生网络
副作用。

## 2026-08-31：Cgyy WebVPN 网关 Cookie 同步证据

用户提供的 `examples/BUAA-CGYY/d.buaa.edu.cn.cgyy.har`（仅读）记录了完整的 WebVPN 浏览器流程。脱敏审阅确认：Cgyy `manageLogin` 在 WebVPN 包装地址上经两次 302 到 `/venue-zhjs`，没有 HTTP `Set-Cookie`；浏览器随后调用 `d.buaa.edu.cn/wengine-vpn/cookie` 的 `method=get` 接口，按 `host=cgyy.buaa.edu.cn`、`scheme=https`、`path=/venue-zhjs` 和当前时间戳读取纯文本 Cookie 快照，其中包含 `sso_buaa_zhjs_token` 名称。前端把该值作为 `Sso-Token` 头发送到包装后的 `POST /venue-zhjs-server/api/login`，成功信封仍为 `code/data/message`，再以 `cgAuthorization` 继续业务读取。

此前 Core 只等待 Cgyy 响应的 `Set-Cookie`，因此 WebVPN 实时矩阵安全返回 `authentication_required`。先添加 `webvpn_从网关_cookie接口取得_cgyy_sso令牌` 脱敏 Mock 并观察到预期失败，再实现网关 Cookie 同步；同步响应只在当前请求内存中解析，令牌不进入 Session、日志或文件。该证据不改变冻结 `ubaa_old` 的 Direct Cgyy URL、参数、签名、DTO 或错误语义，`examples/buaa-api` 仍无等价 Cgyy 模块；本地 Core WebVPN-only 回归和敏感扫描需在真实重跑前通过。

## 2026-08-31：HAR 修复后的 Cgyy 双路线重跑（历史快照）

重新执行 `just verify-live mode=direct` 与 `just verify-live mode=webvpn`，两条路线均退出码 0。两条路线的 Cgyy 站点、用途、日期、订单、订单详情和锁码逐项均为 `PASS`（站点 7、用途 10、订单 15、锁码摘要数量 0），Evaluation 的全部与待评教读取也逐项 `PASS`；其他已接入只读领域同样通过。WebVPN Judge 本次瞬时数量为 `include_expired/current/details_batch=49/17/17`，此前同日快照曾有 `80/48/48` 或更早的 `40/0/0`，但列表、详情和批量详情均按当前依赖 ID 语义门禁记录。SPOC/Bykc 详情因无上游标识按 `NOT_APPLICABLE`，auto 仍只做确定性路由测试。真实账号未执行任何写操作。

## 2026-08-31：最新 Core-live 实时复核处于图书馆非营业时间

随后再次串行执行 `just verify-live mode=direct` 和 `just verify-live mode=webvpn`。两条路线的
认证、用户、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、Bykc、Cgyy 和 Evaluation
逐项结果与前述快照一致，Cgyy 六项均通过且 WebVPN 没有回退 Direct。唯一异常是
`libbook/area_detail`：HTTP 状态为 200，但业务信封为 `code=500` 且缺少 `data`，Core 按冻结
合同返回 `upstream_changed`，两条路线均以退出码 5 结束。该轮运行时间处于图书馆开放时间之外；
已知开放时间为每日 08:30–23:00（`Asia/Shanghai`），因此该样本不能作为协议不兼容或实现错误
的结论。安全调试摘要只记录操作、路线、状态、脱敏路径、正文长度和 JSON 结构，不记录响应正文
或消息值；必须在开放窗口内重新运行后再判定。

## 2026-08-31：Cgyy 路线与 Core-live 真实验证边界校正

本周期先对照冻结 `ubaa_old`、固定版本 `examples/buaa-api` 和现有脱敏 Mock。原有 WebVPN Cgyy 测试复现了业务请求误走 Direct 的失败：WebVPN-only 会话无法完成站点读取，且写入口也固定访问 Direct。新增失败测试后，Core facade 将每个 Cgyy 公共操作分别绑定到解析出的路线 runtime；WebVPN 现在只使用 WebVPN URL，Direct 会话缺失不会触发偷偷回退。相同批次内业务令牌仍只在当前客户端内存复用，认证失效最多清理、重登并重放一次。

冻结旧版 `LocalWebVpnSupport.localCgyyUpstreamUrl` 曾返回直连地址，`examples/buaa-api` 没有等价实现；该冻结行为与本周期明确的 WebVPN-only 路线合同冲突。冲突边界以脱敏 WebVPN-only 失败/修复测试和当前路线安全要求为依据，未从示例协议借用任何 URL、字段或令牌；后续真实 WebVPN 结果必须逐操作记录，若上游不支持该路线则记录失败而不回退 Direct。

锁码解析另以脱敏失败测试复现了 CLI 序列化原始 `data` 的泄漏，现已收敛为 Core/CLI 公共结果 `{available: boolean}`；锁码正文不会进入 Session、日志或文件。以上修复均通过 focused Cgyy 测试、敏感扫描和确定性检查；协议 URL、参数、签名常量仍只取冻结实现，`examples/buaa-api` 无对应 Cgyy 实现，未作类比推断。

真实验证入口已拆为单批次 `core-live` 与薄 `verify-live`：Core-live 一次创建固定路线 `RouteClient`，从 stdin 读取凭据并串行执行只读 facade 操作，逐项输出路线、操作、`PASS/FAIL/BLOCKED/NOT_APPLICABLE` 和稳定错误码；不调用任何写方法。`verify-live` 仅校验参数、临时读取 `.env.local`、锁定构建并转发，拒绝 `auto`；`auto` 只保留 Mock/确定性路由证据。Direct/WebVPN 的真实结果必须在本周期重新逐项记录，不能沿用旧脚本聚合摘要。

新入口真实结果：Direct 全量逐项退出码 0，仅 SPOC 详情与 Bykc 课程详情因空列表为 `NOT_APPLICABLE`；课表、考试、成绩、教室、SPOC、Judge（含批量详情）、Signin、Ygdk、LibBook、Bykc、Cgyy、Evaluation 均有安全 `PASS`。WebVPN 的认证、用户、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc 逐项通过，SPOC/Bykc 详情因无标识为 `NOT_APPLICABLE`；Cgyy 站点/用途/订单/锁码和 Evaluation 全部得到 `authentication_required`，依赖日期/订单详情为 `NOT_APPLICABLE`，Evaluation pending 为 `BLOCKED`，退出码 5。该失败保持 WebVPN 路线，不以 Direct 结果替代。

## 2026-08-29：用户授权 Cgyy Rust CLI 读写探针及提交落库时序

用户明确授权使用 `.env.local` 中的真实测试账号执行一次 Cgyy Rust CLI 预约并立即清理订单；该授权仅覆盖本次单笔 Direct 探针，不改变 `verify-live` 永远只读的全局规则。实时读操作中，Direct 登录、站点、用途、日期和订单读取均成功；日期返回 84 个时段，其中存在可预约时段。请求 JSON 省略验证码材料，由 Core 自动获取挑战、求解图片、校验并提交。

首次提交返回成功后立即调用取消，取消接口和 CLI 均返回成功，但订单列表仍暂时为 `orderStatus=1`。对照冻结 Python 脚本的 `sleep(5)`，等待 5 秒后对同一订单再次取消，订单列表最终变为 `orderStatus=2`；因此记录“提交完成到取消之间需要等待旧版落库窗口”，不能仅以取消接口的成功信封作为最终状态证据。没有保留或记录订单号、手机号、令牌、Cookie、验证码或原始响应。

取消后的详情请求第一次返回 `upstream_unavailable`，随后成功信封的 `data` 为空，Rust 按冻结旧版映射为空详情；订单列表状态 2 是本次取消的最终实时证据。另发现日期 DTO 曾将预约上下文 `reservationToken` 序列化到 CLI，导致安全合同拒绝成功响应；已通过脱敏失败测试先复现，再对 `CgyyDayInfo.reservation_token` 增加仅 Core 内部可用的序列化屏蔽。

## 2026-08-29：继续对齐 Cgyy 业务会话、信封和 Direct 路由

冻结 `ubaa_old` 的 `requestJson` 对场馆 GET/POST 请求都使用同一业务访问令牌，并在业务认证失效时清理业务令牌、强制登录后只重放一次；预约上下文返回的 `token` 只作为后续预约表单的业务字段，不能替代 `access_token` 放入 `cgAuthorization`。Rust 原实现在上下文、验证码校验和最终提交中误用了该预约 `token`，且业务认证失败没有按旧版重试；`WebVPN` facade 的 Cgyy 写操作也错误地使用了主路线 transport。

历史记录：本轮先以脱敏 Mock 固定上述失败行为，再完成最小修复：所有 Cgyy 业务 GET/POST 统一经过一次认证重试，写请求头恢复使用业务 `access_token`。当时的 WebVPN Direct 兼容分支已被本周期路线校正 supersede；当前 facade 读写均使用解析出的路线 runtime。日期接口严格要求 `code=200` 且 `data` 存在并为 JSON 对象（允许空对象）；锁码接口严格要求成功代码，缺失 `data` 映射为空值，保持旧版可空语义。

确定性证据为 Core Cgyy 集成测试 12/12、CLI 合同测试 23/23，以及 Cgyy facade 路由回归测试通过。实时只读证据仅确认两条路线的站点列表各返回 7 个；日期、订单和锁码在不同日期/路线出现 `upstream_unavailable` 或 `invalid_semantics`，部分日期结构探针曾返回正常对象，因此需把上游窗口/限流不稳定与本地协议错误分开处理。本轮没有调用预约、验证码校验、提交或取消写接口。`examples/buaa-api` 在冻结提交中没有等价 Cgyy 协议，未借用其 URL、字段或错误语义。

## 2026-08-17 至 2026-08-29：已归档历史决策摘要

以下条目是已被当前中文合同、来源对照和后续决策吸收的历史摘要；完整旧正文仍可从 Git
历史追溯，不再在当前文档重复维护。

- 认证与连接只接受主机白名单内的 HTTP/HTTPS 跳转，TLS 校验保持开启；非 HTTP 协议即使主机匹配也拒绝。公共宿主只使用具体的 facade，运行时、上游解析和存储实现保持私有。
- 响应正文、会话文件和内存缓冲均有上限；Session 文件使用防符号链接、仅所有者权限、侧车锁、唯一临时文件和单调 CAS 修订，防止陈旧进程覆盖、重建或删除新会话。
- 交互式验证码分支已被 2026-08-25 的非交互决策取代。遇到未支持的验证控件时，Core 在请求验证码图片或提交凭据前返回 `upstream_changed`；CLI、JSON 合同和真实验证器不暴露挑战、答案或图片。
- 课表周视图的响应 `code` 只按冻结 DTO 作为非空展示字段解析，不能强行要求它等于请求学期；课表和成绩表单保持 `application/x-www-form-urlencoded`。AAS 读取前执行有证据支持的服务激活并校验最终 URL。
- 注销保持“远端尽力请求后清理本地”的冻结顺序；持久化清理由 CAS 修订保护。确定性 Cargo 门禁统一锁定依赖解析；格式检查工具不解析依赖，因此不需要锁定参数。
- Judge 的历史 `auto -> WebVPN` 覆盖已在校园网 Direct 复核后撤销；现在所有功能使用统一路线表。网关探测固定为 `gw.buaa.edu.cn:80` 的一次 500 毫秒总预算 TCP 探测，并在进程内缓存 60 秒。
- 普通路线选择已从宿主迁入聚合 `UbaaClient`。双路线协调器拥有完整快照和修订；外部 CAS 冲突是当前实例的终止状态，清理双路线内存并停止后续网络 I/O，恢复必须重新打开 facade。
- 仅接收 SSO 准备页 Cookie 不代表已认证；只有持久化的认证时间或用户中心状态成功后才允许业务读取。CLI 对所有命令只输出 schema v2；路线解析前的错误只包含功能名，不虚构路线元数据。
- SPOC 以冻结本地实现为准：课程元数据可选，作业列表必须调用加密的全局分页请求；加密正文恰好按 16 字节对齐时不额外补零块。详情公共 DTO 只保留规范化纯文本，不暴露原始 HTML。
- SPOC 令牌必须绑定 HTTPS `spoc.buaa.edu.cn/spocnew/cas` 和当前路线；业务认证重试只重放失败的单项请求，解析错误和权限错误不伪装成认证失效。业务认证耗尽后仅在用户中心明确失效时清主会话。
- Judge 与 SPOC 的隐藏诊断仅输出安全计数并复用普通 facade 响应；它们不增加 URL、参数、Header 或重试。历史摘要盐、jq 聚合与真实 `auto` 验证器已停用，当前 Core-live 直接输出逐操作安全证据。
- Cgyy、Signin、Ygdk、LibBook、Evaluation 的历史单项修复均已纳入 `source-parity.md`：Signin 使用冻结 GET/`sessionId` 形状；Ygdk 和 Evaluation 保留有证据的可选读取回退；LibBook 双路线读取已验证；Cgyy 签名、业务令牌与每项真实结果独立判定。
- 2026-08-29 的 Direct/WebVPN/auto 聚合结果和瞬时 Judge 数量只保留为上游波动背景，不再作为当前验收。当前门禁只接受 Core-live 的显式 Direct/WebVPN 只读矩阵，且绝不调用真实写操作。

## 2026-08-28：场馆预约的 WebVPN 策略必须保留直连业务域（已被 2026-08-31 决策取代）

本轮真实验证中，WebVPN 主认证成功，但场馆预约返回
`authentication_required`；同一账号的 Direct 场馆查询成功并返回 4 个站点。
冻结 `LocalWebVpnSupport.localCgyyUpstreamUrl` 明确规定
`cgyy.buaa.edu.cn` 公网可达，任何连接模式下都使用直连 URL；冻结
`LocalCgyyApi.ensureBusinessLogin` 进一步固定使用 Direct Cookie 存储和直连客户端
完成 SSO 跳转，再从场馆域 Cookie 取得 `sso_buaa_zhjs_token`。
`examples/buaa-api` 没有等价协议，不能提供替代路线。

当前 Rust 实现将场馆登录、业务登录和查询统一交给所选路线的
`ClientRuntime`。当路线为 WebVPN 时，`runtime.url` 会包装场馆 URL，且 Cookie
仍属于 WebVPN 路线；这与冻结实现的“主认证路线可为 WebVPN，但场馆业务交换固定
直连”并不等价。禁止通过放宽认证错误、跨域复制 Cookie 或把缺少令牌解释为空结果
来规避该差异。后续修复必须先用脱敏 Mock 固定以下合同：WebVPN 主会话保持隔离；
场馆入口和业务请求使用直连 URL；Direct SSO/场馆 Cookie 仅在场馆业务交换范围内
使用；最终业务令牌仍按调用客户端隔离且不持久化。该调整需要明确的双运行时 facade
接口，不能仅在 `features/cgyy.rs` 中替换 URL。
# 2026-08-28 Cgyy 门锁码实时证据

- 命令：`UBAA_VERIFY_DIGEST_SALT=<临时值> just verify-live mode=direct feature=all`。
- 结果：schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc、evaluation 均通过；`cgyy` 站点查询通过。
- 失败：`cgyy_lock_code` 返回稳定错误 `upstream_unavailable`（退出码 5），因此 `feature=all` 聚合失败。
- 处理：不把上游失败改写为空数据，不调用任何写操作；继续执行 WebVPN 同项验证，并核对门锁码冻结接口/错误语义。

# 2026-08-28 WebVPN 全量只读证据

- 命令：`UBAA_VERIFY_DIGEST_SALT=<临时值> just verify-live mode=webvpn feature=all`。
- 结果：schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc 均通过；Judge 仅记录脱敏计数和盐化摘要。
- 失败：Cgyy 与 Evaluation 在业务阶段均返回 `authentication_required`（退出码 3），聚合以 `one_or_more_features_failed` 结束。
- 处理：保留逐项失败，不用 all 聚合结果掩盖；不调用写操作。下一步核对 WebVPN 下 Cgyy 登录跳转与 Evaluation CAS 激活的路线 Cookie/最终 URL 证据。

# 2026-08-29 全量只读复测

- Direct 全量：Judge 为 `upstream_unavailable`、Cgyy 为 `timeout`，其余已执行只读功能通过；聚合以 `one_or_more_features_failed` 结束。
- WebVPN 全量：Cgyy 与 Evaluation 为 `authentication_required`，其余已执行只读功能通过；聚合以 `one_or_more_features_failed` 结束。
- 以上仅记录脱敏错误类别和功能结果；未记录摘要盐、Cookie、令牌、原始响应，也未调用任何写接口。

# 2026-08-29 Cgyy 单项复测

- Direct：站点查询成功，门锁码返回 `upstream_unavailable`（退出码 5）。
- WebVPN：Cgyy 业务入口返回 `authentication_required`（退出码 3）。
- 结论：失败可复现；不放宽错误分类，不跨路线复制 Cookie/令牌，不执行任何写操作。

# 2026-08-28 Cgyy WebVPN 路线冲突

- 冻结依据：`ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalWebVpnSupport.kt` 的 `localCgyyUpstreamUrl` 明确返回原始直连 URL；注释说明 Cgyy 在校外公开可访问，不通过 WebVPN 包装。
- 当前 Rust：`features/cgyy.rs` 通过所选 `ClientRuntime::url` 包装全部场馆地址；显式 WebVPN 验收的 Cgyy 业务阶段返回 `authentication_required`。
- 决策：不能复制 Direct Cookie/令牌到 WebVPN，也不能只改 URL 而让 WebVPN 传输承载直连 Cookie。需要后续设计“主路线诊断与 Cgyy 直连业务 runtime”边界，并补充隔离 Mock；在此边界明确前不猜测修复。

## 2026-08-28 Cgyy 直连 URL 复测

- Rust 已按冻结 `localCgyyUpstreamUrl` 将 Cgyy 地址改为原始直连 URL，同时保留当前路线的 Cookie 容器和传输对象。
- WebVPN 单项复测仍为 `authentication_required`；因此问题不只是 URL 包装，不能据此宣称 WebVPN 通过。
- Direct 单项站点查询继续通过，门锁码仍返回 `upstream_unavailable`。后续必须设计独立直连业务 runtime，并用 Mock 证明 Cookie 不跨主认证路线复制。

# 2026-08-28 只读矩阵复测

- Direct：schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc、cgyy 站点及 evaluation 均通过；`cgyy_lock_code` 仍为 `upstream_unavailable`（退出码 5）。
- WebVPN：schedule、exam、classroom、spoc、signin、ygdk、libbook、bykc 通过；grades 返回 `upstream_changed`（退出码 6），judge 返回 `invalid_semantics`（截止阶段退出码 1），cgyy 与 evaluation 返回 `authentication_required`（退出码 3）。
- 处理：保留逐操作失败证据，聚合命令以 `one_or_more_features_failed` 结束；本轮只读验证未调用任何写操作，以上摘要不含原始响应或个人数据。

## 2026-08-28 WebVPN 逐项复测

- `feature=grades`、`feature=judge`、`feature=evaluation` 单项重跑均成功；Judge 脱敏计数为课程 5、原始锚点 49、过滤后 49、当前 17、截止跳过 32，并取得语义详情。
- `feature=cgyy` 单项重跑仍为 `authentication_required`（退出码 3）。该失败与此前结果一致，不能由其他场馆或主认证成功替代。
- 本次复测全部为只读操作，未调用任何提交、取消、预约、签到、上传或选课接口。

## 2026-08-29 逐操作验证器扩展与三路线复测

- 提交 `c35c9ca` 将 `verify-live` 的扩展领域从代表性查询扩展为逐操作链：Ygdk
  概览/记录，LibBook 楼馆/区域/详情/座位/预约记录，Bykc 资料/课程/详情/已选/统计，
  Cgyy 站点/用途/日期/订单/详情/锁码，以及 Evaluation 全部/待评教。详情请求只有在
  上游返回脱敏标识时才继续，空集合不会伪造详情成功；脚本 stub 覆盖调用顺序且不输出
  原始响应。
- 提交 `406177b` 将 User 的 `user show` 纳入独立验证和 `all` 聚合，并校验完整脱敏
  profile 字段集合、类型与掩码规则。
- Direct 三路线复测命令为
  `UBAA_VERIFY_DIGEST_SALT=<临时值> just verify-live mode=direct feature=all`：课表、
  考试、成绩、教室、SPOC、User、Signin、Ygdk、LibBook、Cgyy 站点/用途/日期/订单、
  Evaluation 成功；Judge 返回 `upstream_unavailable`，Bykc 已选返回 `upstream_changed`，
  Cgyy 锁码响应未通过当前安全结构校验，聚合退出 5。
- WebVPN 同命令：课表、考试、成绩、教室、SPOC、Judge、User、Signin、Ygdk、LibBook
  成功；Bykc 已选返回 `upstream_changed`，Cgyy 与 Evaluation 返回
  `authentication_required`，聚合退出 6。
- auto 同命令解析到 Direct：课表、考试、成绩、教室、SPOC、User、Signin、Ygdk、
  LibBook、Evaluation 成功；Judge 返回 `upstream_unavailable`，Bykc 已选返回
  `upstream_changed`，Cgyy 在用途查询阶段返回 `upstream_unavailable`，聚合退出 5。
- 以上运行只执行读操作；未记录凭据、Cookie、令牌、摘要盐、原始响应或个人数据，
  未调用任何选课、退选、签到、预约、取消、提交或上传接口。整体迁移继续保持未完成。

## 2026-08-29 用户独立只读验收

- `feature=user route=direct`、`feature=user route=webvpn` 和
  `feature=user route=auto` 均退出 0；auto 实际解析到 Direct。
- 三次运行均通过完整脱敏 profile 结构校验；没有记录姓名、联系方式、身份信息、Cookie、
  令牌或原始响应，也没有调用任何写操作。

## 2026-08-29 Bykc 已选课程包装修复

- 冻结 `ubaa_old/shared/.../LocalBykcApi.kt` 的 `queryChosenCourse` DTO 是
  `data.courseList`，Rust 原实现把解密后的业务数据直接当数组解析，导致 Direct、WebVPN
  和 auto 均在 `bykc_chosen` 返回 `upstream_changed`。
- 按 TDD 先加入 `courseList` 对象包装 fixture，旧实现失败；随后让解析器从对象读取
  `courseList`，并保留已有数组兼容路径。聚焦测试通过后，三路线单项命令均退出 0，
  返回脱敏课程计数摘要；未记录课程标识、令牌、密文或原始响应。

## 2026-08-29 Bykc 修复后全量实时矩阵

- Direct 全量：User、课表、考试、成绩、教室、SPOC、Signin、Ygdk、LibBook、Bykc、Cgyy 站点和 Evaluation 通过；Judge 在 `judge_all` 返回 `upstream_unavailable`，Cgyy 在 `cgyy_day` 返回 `upstream_unavailable`，聚合退出 5。
- WebVPN 全量：User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc 通过；Cgyy 与 Evaluation 在业务阶段返回 `authentication_required`，聚合退出 3。
- auto 全量解析到 Direct：User、课表、考试、成绩、教室、SPOC、Signin、Ygdk、LibBook、Bykc、Cgyy 站点和 Evaluation 通过；Judge 在 `judge_all`、Cgyy 在 `cgyy_purposes` 返回 `upstream_unavailable`，聚合退出 5。
- 本轮使用临时摘要盐，仅保留退出码、阶段和脱敏计数；没有输出或持久化凭据、Cookie、令牌、原始响应、课程/个人标识，也没有调用真实写操作。失败项继续作为硬门禁，不以 `all` 聚合掩盖。

## 2026-08-29 Direct Judge/Cgyy 单项复测

- `feature=cgyy` 站点查询成功（4 个站点），日期阶段仍为 `upstream_unavailable`，退出 5。
- `feature=judge` 在列表阶段仍为 `upstream_unavailable`，退出 5。
- 两次复测均未改变请求、解析或错误策略；没有跨路线复制 Cookie/令牌，也没有调用真实写操作。该结果确认失败位于实时上游可用性边界，不能由其他功能成功替代。

## 2026-08-29 WebVPN Cgyy 直连业务 transport 复测

- 按冻结 `LocalCgyyApi.ensureBusinessLogin` 的 Direct 客户端语义，聚合 facade 在 WebVPN
  路线解析和会话预检后改用 Direct 业务 transport；Cookie 仍由 Direct 路线槽位独立提供，
  未从 WebVPN 槽位复制材料。
- `feature=cgyy route=webvpn` 的站点查询通过（4 个站点），用途查询阶段返回
  `upstream_unavailable`（退出 5），不再返回此前的 `authentication_required`。
- 该结果证明 transport 分派方向正确，但尚不足以宣告 WebVPN Cgyy 全部读操作通过；
  日期、订单、锁码等后续操作仍需逐项实时证据。

## 2026-08-29 Judge 路线复测更新

- auto（实际解析到 Direct）的 Judge 单项复测通过，返回课程 5、当前任务 65，并完成
  详情语义校验；摘要仅保留脱敏计数和临时盐摘要。
- Direct Judge 同轮仍在 `judge_all` 返回 `upstream_unavailable`。这与历史列表快照
  波动一致，不能用 auto 成功替代 Direct 路线证据；继续保留逐路线硬门禁。
- WebVPN 全量同轮除 Cgyy 用途查询 `upstream_unavailable` 外，其余已执行只读操作通过，
  包括 Judge 和 Evaluation。所有运行均未调用真实写接口。

## 2026-08-29 Direct Judge/Cgyy 复测收敛

- Direct Judge 随后单项复测通过：课程 5、当前任务 65，详情语义校验通过；结合本轮
  WebVPN 与 auto 成功结果，Judge 三路线证据已齐备。
- Direct Cgyy 站点查询通过（4 个站点），日期阶段仍返回 `upstream_unavailable`，退出 5。
  该失败不被站点成功掩盖，也未改变冻结请求和错误分类。

## 2026-08-29 Cgyy 验证器逐操作不中断

- 旧验证器在 Cgyy 用途或日期失败时提前返回，无法证明订单、详情和锁码是否被独立
  尝试。现按操作分别记录脱敏失败，继续执行不依赖失败响应的后续查询；订单详情仅在
  订单列表提供标识时调用，日期详情仅在站点列表提供标识时调用。
- `scripts/test-verify-live.sh` 已补齐站点、日期、订单、订单详情和锁码的合成响应与调用
  顺序断言；真实验证仍不执行写操作，聚合返回首个失败退出码。

## 2026-08-29 Cgyy 三路线逐操作复测

- WebVPN：站点与用途通过，日期和锁码为 `upstream_unavailable`；订单查询通过但没有
  可用详情标识，因此未伪造详情请求。
- auto（解析到 Direct）：站点通过；用途、日期、订单和锁码均为
  `upstream_unavailable`。
- Direct：站点请求本轮为 `upstream_unavailable`，用途和锁码同样失败；验证器不再从
  失败信封提取站点标识或打印成功摘要。上述运行均未执行真实写操作。

## 2026-08-29 Cgyy 日期窗口排除复测

- Direct Cgyy 使用验证器允许的只读日期覆盖 `2026-09-01` 重跑：站点仍通过（4 个），
  用途、日期、订单返回 `upstream_unavailable`，锁码为 `invalid_semantics`。
- 改变日期未改变失败类别，因此当前证据不足以把问题归因于当天没有可预约数据；不据此
  修改日期格式、响应字段或错误映射，也未执行任何真实写操作。

## 2026-08-29 锁码 CLI 脱敏边界

- 冻结旧版允许 `getLockCode()` 返回可空不透明 `data`，但 CLI 安全合同禁止输出原始
  锁码或 `rawData` 字段。提交 `8ef875a` 保留 Core facade 的原始 `Value`，将单路线与
  聚合 CLI 投影为仅含 `{available: boolean}`，并同步 schema、验证器与脱敏单测。
- Direct Cgyy 随后复测中锁码阶段返回 `upstream_unavailable`；验证器不再因旧的
  `rawData` 结构要求产生误报。真实写操作仍未调用。

## 2026-08-29 Cgyy 最新三路线波动

- Direct 单项：站点、用途、订单、锁码均为 `upstream_unavailable`。
- WebVPN 单项：站点查询通过，随后用途、日期、订单、锁码均为
  `upstream_unavailable`。
- auto 单项：站点、用途、订单均为 `upstream_unavailable`，在没有订单标识时按规则
  跳过详情。
- 本轮没有出现新的可验证 URL/字段冲突；不据此增加网络重试、改写参数或放宽错误分类，
  继续保留失败证据并禁止真实写操作。

## 2026-08-29 锁码投影后三路线复测

- WebVPN：站点成功，用途、日期、订单、锁码均为 `upstream_unavailable`。
- auto：站点、用途、订单、锁码均为 `upstream_unavailable`；站点失败后未构造依赖详情。
- 两路线均未出现旧 `rawData` 结构误报，说明 CLI 安全投影与验证器合同已生效；Cgyy
  实时硬门禁仍未满足，未执行任何写操作。

## 2026-08-29 三路线全量复测更新

- Direct 全量：除 Cgyy 外所有 User、课表、考试、成绩、教室、SPOC、Judge、Signin、
  Ygdk、LibBook、Bykc、Evaluation 通过；Cgyy 用途/订单为 `upstream_unavailable`、
  日期为 `upstream_changed`、锁码为 `invalid_semantics`。
- WebVPN 全量：除 Cgyy 日期和锁码 `upstream_unavailable` 外，其余只读操作通过，Cgyy
  站点、用途、订单已通过。
- auto 全量（解析到 Direct）：除 Cgyy 日期和锁码 `upstream_unavailable` 外，其余只读
  操作通过。Judge 三路线均完成课程/任务/详情语义校验；所有命令仍未调用真实写接口。

## 2026-08-29 当前轮三路线全量验收

- Direct 全量逐操作运行成功完成 User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation；Judge 课程/任务/详情语义校验通过。Cgyy 站点查询通过（4 个站点），用途和订单返回 `upstream_unavailable`，日期返回 `upstream_changed`，聚合退出码 5。
- WebVPN 全量逐操作运行成功完成除 Cgyy 外的全部只读操作，Judge 详情语义校验通过。Cgyy 站点查询通过（4 个站点），用途和订单返回 `upstream_unavailable`，日期返回 `upstream_changed`，聚合退出码 5。
- auto 全量解析为 Direct，除 Cgyy 外的全部只读操作通过；Cgyy 站点通过，用途和订单为 `upstream_unavailable`，日期为 `upstream_changed`，锁码为 `upstream_unavailable`，聚合退出码 5。
- 三次运行均使用未持久化的进程内摘要盐，仅记录路由、阶段、计数和错误类别；没有输出凭据、Cookie、令牌、原始响应或个人标识，也没有调用真实写接口。Cgyy 仍未满足实时硬门禁，不修改协议实现或错误策略。

## 2026-08-29 Cgyy 用途类型回退修复

- 冻结 `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalCgyyApi.kt` 的 `getPurposeTypes` 在已有主会话后对动态请求和解析使用 `runCatching`，失败即采用静态十项列表。Rust 原实现传播 `/api/codes` 的上游错误，与冻结行为不符。
- 新增 `crates/ubaa-core/tests/cgyy.rs` Mock：`/api/codes` 返回合成 502 时，单路线 facade 仍返回十项静态用途；测试先观察到 `UpstreamUnavailable` 失败，再实现回退并通过。`RouteClient` 同步补齐用途类型入口。
- Direct、WebVPN、auto 复测中用途阶段均成功，失败边界后移到日期/订单（及依赖详情）的实时上游错误；未改变 URL、签名、重试或错误映射，也未调用真实写接口。

## 2026-08-29 Cgyy 回退后 Direct 全量复测

- Direct `feature=all` 在用途回退修复后继续完成所有独立操作：非 Cgyy 功能及 Judge 详情语义通过，Cgyy 站点成功（4 个），日期返回 `upstream_changed`，锁码返回 `upstream_unavailable`，聚合退出 6。
- 该结果确认用途回退减少了一个实时失败点，但日期和锁码仍缺乏新的协议证据；不猜测参数或增加重试，未执行真实写操作。

## 2026-08-29 Cgyy 回退后 WebVPN/auto 全量复测

- WebVPN 全量中用途阶段通过静态回退，站点成功（4 个），非 Cgyy 操作与 Judge 详情语义通过；日期和依赖详情返回 `upstream_unavailable`，聚合退出 5。
- auto 全量解析到 Direct，用途阶段通过静态回退，站点成功（4 个），非 Cgyy 操作与 Judge 详情语义通过；日期和订单返回 `upstream_unavailable`，聚合退出 5。
- 两次运行只进行了只读请求，未改变日期/订单协议、未增加重试或放宽错误分类，也未执行真实写操作。

## 2026-08-29 用途回退后 WebVPN/auto 全量复测

- WebVPN 全量中用途静态回退成功，站点成功（4 个），非 Cgyy 操作与 Judge 详情语义通过；日期和依赖详情返回 `upstream_unavailable`，聚合退出 5。
- auto 全量解析到 Direct，用途静态回退成功，站点成功（4 个），非 Cgyy 操作与 Judge 详情语义通过；日期和订单返回 `upstream_unavailable`，聚合退出 5。
- 本轮无新的 URL、字段或重定向证据；不猜测协议、不增加重试，未执行真实写操作。

## 2026-08-29 Cgyy 成功信封代码严格校验

- 冻结 `LocalCgyyApi.requestJson` 在 JSON 解析后明确要求 `code == 200`；缺失代码或其他数值均抛出业务错误。
- Rust `features/cgyy.rs::data` 原先允许缺失代码及 `code=0`，新增脱敏解析测试先复现错误再收紧为仅接受 `Some(200)`；非 JSON、数组或标量结构仍按原错误分类处理。
- 未改变 URL、请求、重定向、签名、缓存或实时错误边界；未执行真实写操作。

## 2026-08-29 Cgyy 日期槽位排序

- 冻结 `LocalCgyyApi.mapDayInfo` 会过滤无效槽位并按 `timeId` 升序整理每个空间的槽位；Rust 原实现保留上游顺序。
- 新增逆序 `spaceTimeInfo` 脱敏测试先失败后通过，当前输出与冻结排序一致；未改变请求协议或实时错误策略。

## 2026-08-29 Cgyy 三路线逐操作复测（二）

- 使用未持久化进程内摘要盐执行 `feature=cgyy` 的 Direct、WebVPN、auto 只读验证；三次站点查询均成功并返回 4 个站点。
- Direct 日期和锁码为 `upstream_unavailable`；WebVPN 日期为 `upstream_changed`、订单和锁码为 `upstream_unavailable`；auto 解析为 Direct，日期为 `upstream_changed`、订单为 `upstream_unavailable`。
- 脚本逐项继续执行并返回首个失败码；本轮未改变 URL、参数、解析或错误策略，未执行任何真实写操作。Cgyy 实时硬门禁仍未满足。

## 2026-08-29 三路线全量只读复测

- Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge（课程/任务/详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 均成功；Cgyy 站点成功（4 个），日期和订单为 `upstream_unavailable`，聚合退出 5。
- WebVPN：上述非 Cgyy 能力均成功，Judge 详情语义通过；Cgyy 站点成功（4 个），日期和订单为 `upstream_unavailable`，聚合退出 5。
- auto：解析为 Direct，上述非 Cgyy 能力均成功；Cgyy 站点成功（4 个），日期为 `upstream_changed`、订单为 `upstream_unavailable`，聚合退出 6。
- 结果与冻结实现的请求和解析行为一致但实时上游不可用的项仅作记录，不修改协议或错误策略；仅执行读操作，未执行真实写接口。

## 2026-08-29 Cgyy 场馆包装展开

- 冻结 `LocalCgyyClient.getVenueSites` 调用 `asVenueSiteArray`，将场馆对象的 `siteList` 展开并继承场馆名称与校区；当前解析器原先把场馆对象误当作站点。
- 新增旧版包装的脱敏测试，先复现站点 ID 被误读为场馆 ID，再实现展开并通过；同时保留扁平数组和 `content` 包装。
- 未改变请求、签名、路由、会话或实时错误策略，未执行真实写操作。

## 2026-08-29 LibBook 座位排序

- 冻结 `LocalLibBookApi.getSeats` 在 DTO 映射后执行 `sortedBy { it.no }`；Rust `parse_seats` 原先保留响应顺序。
- 新增逆序座位号脱敏测试先失败后通过，并在 Core 中按字符串座位号升序排序；未改变请求协议或实时路由行为。

## 2026-08-29 LibBook 预约总数回退

- 冻结 `LocalLibBookApi.getBookings` 在响应缺少 `total` 时使用当前预约列表条数；Rust 原解析固定回退为 0。
- 新增缺少 `total` 的脱敏分页测试先失败后通过，Core 现按冻结语义回退；未改变请求协议或实时路由行为。

## 2026-08-29 LibBook 分区编号回退

- 冻结 `LocalLibBookApi.mapAreaDetail(areaId, raw)` 在上游区域对象缺少 ID 时回退请求参数 `areaId`；原 Core 解析器没有请求上下文并返回空 ID。
- 新增缺少区域 ID 的脱敏测试先失败后通过，增加带请求 ID 的解析入口并由查询调用；未改变请求协议或实时路由行为。

## 2026-08-29 Bykc 签到配置严格解析

- 冻结证据：`ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalBykcApi.kt` 的 `parseSignConfig` 通过序列化器解析 `LocalBykcSignConfig`；签到点 `lat/lng` 为必填，单点解码异常会使 `runCatching` 返回空配置。
- 原 Core 使用 `filter_map` 丢弃坏点并保留配置，与冻结错误语义不一致。新增无效坐标脱敏测试先失败，再改为列表与点字段整体严格校验。
- `examples/buaa-api` 无等价 Bykc 签到配置协议，不参与字段或错误推断；未执行真实写操作。

## 2026-08-29 Ygdk 记录时间戳

- 冻结证据：`ubaa_old/.../LocalYgdkApi.kt` 的记录字段 `startTime/endTime` 为 `Long?`，映射时调用 `timestampToDateTimeText`，使用固定 `LOCAL_YGDK_TIME_ZONE`（东八区）输出分钟精度文本。
- 原 Core 仅读取字符串，数值时间会变为空。新增数值时间脱敏测试先失败，再增加固定东八区转换；未从 `examples/buaa-api` 借用协议。

## 2026-08-29 Ygdk 记录图片字段

- 冻结证据：`LocalYgdkApi.kt` 的 `extractRecordImages` 对 `images_fmt` 的 `JsonPrimitive` 非空内容直接返回单元素列表；只有数组字符串才尝试 JSON 数组解析。
- 原 Core 将所有字符串当作数组 JSON，合法单地址会变为空列表。新增单字符串脱敏测试先失败，再保留非空字符串作为单地址；未执行真实写操作。

## 2026-08-29 Ygdk 数字字符串时间戳

- 冻结证据：`LocalYgdkApi.kt` 的 `JsonObject.long` 对 JSON primitive 的文本执行 `toLongOrNull`，数字字符串会进入时间戳格式化。
- 原 Core 遇到任意字符串即原样返回。新增数字字符串时间戳测试先失败，再仅对可解析整数执行东八区转换；未改变非数字文本路径。

## 2026-08-29 LibBook 原语字段兼容

- 冻结证据：`LocalLibBookApi.kt` 的 `JsonObject.string` 读取 `jsonPrimitive.contentOrNull`，其语义覆盖字符串、数字和布尔原语。
- 原 Core `text` 仅接受 JSON 字符串，数字座位标识/状态会清空。新增数字字段脱敏测试先失败，再扩展原语文本化；未执行真实写操作。

## 2026-08-29 三路线全量只读复测（二）

- Direct 全量首个失败为 Cgyy 业务阶段 `upstream_unavailable`（退出 5）；其余功能及 Judge 详情语义通过。
- WebVPN 记录 Grades `parse_error`、Judge `invalid_semantics`，以及 Cgyy 日期/订单/锁码 `upstream_unavailable`（退出 6）；站点和其他可用功能仍按逐操作结果记录。
- auto 解析为 Direct，Grades 为 `upstream_changed`，Cgyy 后续业务阶段为 `upstream_unavailable`（退出 6）；Judge 详情通过。
- 本轮没有新的 URL、参数、重定向或字段证据；按用户约定，对与冻结旧版一致但实时上游不可用的项只记录并继续推进，未执行真实写操作。

## 2026-08-29 Cgyy 原语字段兼容

- 冻结证据：`LocalCgyyApi.kt` 的 `JsonObject.string` 返回 `jsonPrimitive.contentOrNull`，不限定 JSON 字符串类型。
- 原 Core `string` 仅接受 `as_str`，数字场馆名称等合法原语会清空。新增脱敏站点测试先失败，再统一支持字符串、数字和布尔原语；未执行真实写操作。

## 2026-08-29 Signin 写响应状态兼容

- 冻结证据：`LocalSigninApi.kt` 的 `jsonStringValue` 读取 primitive 文本，`int` 随后执行 `toIntOrNull`；签到写响应的 `STATUS`/`stuSignStatus` 因此接受数字或数字字符串。
- 原 Core 写响应仅使用 `Value::as_i64`，数字字符串会回退为零/未完成。新增脱敏状态测试先失败，再增加整数兼容辅助；未执行真实写操作。

## 2026-08-29 Evaluation 任务 `yhdm` 身份来源

- 证据：冻结 `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalEvaluationService.kt` 的 `fetchTasks` 明确发送 `authSession.user.schoolid.ifBlank { authSession.username }`。
- 原差异：Rust `features/evaluation.rs::get_all` 曾固定发送空 `yhdm`，无法保持同一请求构造。
- 决策：登录成功后仅在运行时内存记录 `UserProfile.school_id`，缺失时记录 `username`；评教任务请求使用该值，既有无资料会话保持空值。未从 Cookie、实时响应或示例项目猜测身份字段，也未执行真实写操作。

## 2026-08-29 Ygdk 文本原语

- 证据：冻结 `LocalYgdkApi.kt` 的 `JsonObject.string` 读取 `jsonPrimitive.contentOrNull`，因此数字和布尔原语也会得到文本内容。
- 原差异：Rust Ygdk `string` 只调用 `Value::as_str`，合法原语字段会被当作缺失。
- 决策：统一将字符串、数字、布尔映射为文本并保留空文本过滤；未借用非等价示例协议，未执行真实写操作。

## 2026-08-29 Evaluation 文本原语

- 证据：冻结评教 DTO 映射使用 `JsonPrimitive.contentOrNull`，其文本读取不限定 JSON 字符串类型。
- 原差异：Rust Evaluation `string` 只接受字符串和整数，布尔/浮点字段会被当作缺失；新增布尔字段测试先失败。
- 决策：扩展为字符串、整数、浮点、布尔的文本化并保留空值语义；未从示例项目类比协议，未执行真实写操作。

## 2026-08-29 三路线逐操作实时证据

- Direct 全量：非 Cgyy 功能全部通过；Cgyy 站点通过，日期 `upstream_unavailable`。
- WebVPN 全量：非 Cgyy 功能全部通过；Cgyy 日期 `invalid_semantics`、锁码 `upstream_unavailable`。
- auto 全量：解析到 Direct；非 Cgyy 功能全部通过；Cgyy 日期/详情 `upstream_unavailable`。
- 这些实时失败没有提供足以证明新 URL、参数或字段的证据；与冻结实现一致的项不改协议，仅保留稳定错误分类并继续其它迁移。所有命令均未调用真实业务写操作，输出未包含凭据、Cookie、令牌、原始响应或完整个人数据。

## 2026-08-29 认证资料持久化冲突

- 冻结证据：`ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt` 的 `LocalAuthSession` 包含 `username` 和 `user.schoolid`，并由 `LocalAuthSessionStore` 持久化。
- 当前约束：`docs/contracts/connection-and-session.md` 与合同安全边界要求 `session.json` 不保存 username、密码或用户资料。
- 决策：不为追求表面 parity 写入个人身份资料；登录成功后仅在 Core 运行时内存使用 `school_id/username`，跨进程加载会话时身份参数缺失按安全契约处理。该边界可能使部分旧版依赖身份查询的上游在重启后不可用，若未来要改变必须另立安全与存储决策，不能从实时失败猜测协议。
## 2026-08-29 三路线逐操作实时复测（认证领域拆分后）

- Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge（课程/任务/详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 均成功；Cgyy 站点成功（7 个），日期与锁码均返回 `upstream_unavailable`，聚合退出码 5。
- WebVPN：上述非 Cgyy 功能均成功；Cgyy 站点成功（7 个），日期返回 `invalid_semantics`、锁码返回 `upstream_unavailable`，聚合退出码 1。
- auto：解析为 Direct；上述非 Cgyy 功能均成功；Cgyy 站点成功（7 个），日期返回 `invalid_semantics`、订单返回 `upstream_unavailable`，聚合退出码 1。
- 本轮只执行认证和读操作，未调用任何选课、退选、签到、预约、取消、提交或上传接口。失败项没有提供新的 URL、参数、重定向、字段或加密证据；其本地逻辑与冻结实现一致但实时上游不可用/返回不满足语义，按约定只记录并继续，不猜测修改协议。
## 2026-08-29 认证领域拆分后实时只读矩阵

- Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 逐项成功；Cgyy 站点返回 7 个站点，日期和锁码均为 `upstream_unavailable`，聚合退出 5。
- WebVPN：非 Cgyy 功能逐项成功；Cgyy 站点返回 7 个站点，日期为 `invalid_semantics`、锁码为 `upstream_unavailable`，聚合退出 1。
- auto：路由解析为 Direct；非 Cgyy 功能逐项成功；Cgyy 站点返回 7 个站点，日期为 `invalid_semantics`、订单为 `upstream_unavailable`，聚合退出 1。
- 本轮只读验证未调用任何选课、退选、签到、预约、取消、提交或上传接口。失败项未提供新协议证据，按冻结逻辑与实时上游状态分别记录，不猜测修改 URL、参数、字段或错误语义。

## 2026-08-29 Direct 全量验证的聚合登录边界

- `feature=auth route=direct` 单独验证成功，输出为 `auth_status` 成功。
- `feature=all route=direct` 在业务操作前的聚合登录语义校验失败，返回 `login`/`invalid_semantics`；未执行任何业务读请求。
- 该差异来自 `all` 验证路径要求双路线聚合登录，不足以证明 Direct 单路线认证或任一业务协议缺失；保持冻结认证逻辑和验证器边界，不猜测修改实现。所有真实业务写操作仍未调用。

## 2026-08-29 WebVPN/auto 全量实时复测

- WebVPN 全量逐操作：User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin、Ygdk、LibBook、Bykc 与 Cgyy 站点成功；Cgyy 日期阶段返回 `invalid_semantics`，依赖订单/锁码未调用。
- auto 全量解析到 Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin 成功；Ygdk 阶段返回 `timeout`，后续功能未调用。
- 失败项没有提供新的 URL、参数、字段或加密证据；按冻结实现保留现状并记录实时上游不稳定性。全程未调用真实业务写接口。

## 2026-09-03 Ygdk 路线状态失效代数

- 冻结证据：`ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalYgdkApi.kt` 以独立 `sessionCache` 保存业务会话，并用同一个 `sessionMutex` 保护缓存读取、认证失效删除和 `currentSession` 的最终 `getOrPut`；但会话创建发生在最终锁外，`clearCache` 也没有加锁，因此冻结实现本身不能证明失效代数语义。
- 固定提交的 `examples/buaa-api` 没有 Ygdk 等价实现，不能据此类比 URL、字段、令牌流程或错误语义。
- 当前 `source-parity.md` 已明确决定使用路线内单飞登录与失效代数，使清理前启动的旧登录不能在清理后重新填充凭据；这是 Core 进程内缓存的本地并发合同，不是从冻结实现补出的上游协议字段，也不改变请求 URL、参数、请求头、正文编码、DTO 或错误分类。
- 当前 Rust 状态的无条件 `set` 可与 `clear` 交错，使清理前启动的旧登录在清理后回写凭据。本轮先增加确定性竞态测试与仅测试暂停点，要求失效后旧结果不得重新填充；生产修复必须沿用既有路线隔离与脱敏边界。

## 2026-09-03 Ygdk OAuth 跳转主机约束冲突

- 冻结 `LocalYgdkApi.kt` 的 `fetchOauthCode` 最多跟随十次 `Location`，会从 query 或 fragment query 提取 code，但没有逐跳 host 校验；固定 `examples/buaa-api` 没有 Ygdk 等价实现。
- 当前 Core `features/ygdk.rs::oauth_code` 与 `code_from_url` 同样接受任意 host 的绝对/相对跳转。原 `source-parity.md` 曾写“仅允许已记录的 BUAA 主机”，但没有给出完整允许集合对应的冻结实现、测试或安全实时观察，因此该表述不能作为已实现事实。
- 决策：把主机限制明确标为既有未决 parity gap。2026-09-03 的目录整理只原样移动当前跳转逻辑，不借结构提交增加猜测白名单；后续必须先取得适用冻结实现或脱敏实时跳转链证据，记录具体 host 集合并增加未知 host 的 RED 测试，才能单独收紧生产行为。

## 2026-09-03 Bykc 认证失效重试差异

- 冻结 `LocalBykcApi.kt` 的 `doCallApiRaw` 会识别登录重定向，以及解密正文中的“会话已失效”或“未登录”；后者先清空业务令牌，再由 `callApiRaw` 强制刷新登录并最多重试一次。固定 `examples/buaa-api/src/api/boya` 只能作为同一业务端点的交叉证据，不能替代该冻结错误与重试语义。
- 当前 Core `features/bykc.rs::request_api` 只处理非 200 状态与响应 envelope，没有识别上述确定性认证失效，也不会清理路线凭据并重试，与主来源矩阵中“CAS/令牌失效清理业务状态并最多刷新一次”的既有要求不一致。
- 决策：2026-09-03 的目录化提交仍只移动现有行为；该差异另立脱敏 Mock RED 测试与行为提交。修复只允许对有冻结证据的认证失效信号清理并重试一次，不得把网络异常、任意非 200 或不明确业务失败纳入重试，尤其不得冒险重复真实写操作。
