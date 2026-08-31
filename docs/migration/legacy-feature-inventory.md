# 旧版功能盘点与迁移缺口

本文基于冻结提交 `ubaa_old/`（`6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`）进行盘点。旧版目录只读；本文不包含账号、密码、Cookie、验证码图片或真实响应。路径、方法名和字段名保留代码原文，说明文字使用中文。

实时验收以 `core-live` 的 Direct/WebVPN 只读逐操作结果为准；历史写探针仅作背景记录，不构成本周期验收，写操作不得在真实账号上执行。

## 结论摘要

当前 UBAA2 CLI 的合同范围是用户信息、课表、考试、成绩、空闲教室、SPOC 作业、希冀作业、签到查询，以及 Signin、Ygdk、LibBook、Cgyy、Bykc 和 Evaluation 的扩展能力。写操作已在 Core/CLI 中实现协议、确认门禁和确定性 Mock/向量测试；真实验收与真实账号写请求仍永久禁止。

这五组功能均不是简单的中转接口：本地实现会在主认证会话之上建立业务登录、独立 Cookie/令牌或会话缓存，处理重定向、过期重试、分页、字段兼容和错误映射。迁移时应先在 Core 中定义稳定 DTO 与 facade，再由 CLI 消费，不能把旧版 `Local*Client` 或上游 JSON 暴露给宿主。

## Signin（课堂签到）

### Signin：API 与操作

`SigninApiBackend` 定义：

- 查询：`getTodayClasses(): Result<SigninStatusResponse>`。
- 写操作：`performSignin(courseId: String): Result<SigninActionResponse>`。

公共中转 API 路径为 `api/v1/signin/today`（GET）和 `api/v1/signin/do`（POST，参数 `courseId`）。CLI 后续若只做查询，应只暴露“今日签到课堂列表”。

### Signin：本地实现与上游证据

证据文件：

- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalSigninApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/SigninApi.kt`

本地查询先从 `LocalAuthSessionStore` 获取主认证，再按学生标识缓存 `LocalSigninSession`。业务请求使用 `https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action`，请求头为 `sessionId`，查询参数为 `id` 与当前日期 `dateStr`。业务登录使用 `.../app/user/login.action`，登录名由 User Center/重定向结果解析；签到动作另外读取 `app/common/get_timestamp.action`，再提交 `eschool/app/course/stu_scan_sign.action`。Direct 与 WebVPN 通过 `localUpstreamUrl`/`localSigninCheckinUrl` 选择，失败时有会话失效和一次重试逻辑。

### Signin：DTO 与测试

`Signin.kt` 定义 `SigninClassDto`、`SigninStatusResponse`、`SigninActionResponse`；课堂 DTO 由上游 `result` 数组映射，响应包含 `code`、`message`、可选 `data`。

测试证据：

- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalSigninApiBackendTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/SigninLoginNameSupportTest.kt`
- `ubaa_old/shared/src/jvmTest/kotlin/cn/edu/ubaa/api/LocalSigninRealIntegrationTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/signin/SigninClientTest.kt`

### Signin：UBAA2 缺口与优先级

UBAA2 已提供 `signin` domain、iClass 独立业务会话、Core facade 和 `signin today` CLI 查询命令，并纳入 Direct/WebVPN 路线隔离状态。脱敏解析、请求接线和双路线只读实时证据已记录；签到提交协议仅允许 Mock/向量验证，并由 CLI 确认门禁保护。

## Ygdk（阳光打卡）

### Ygdk：API 与操作

`YgdkApiBackend` 定义：

- 查询：`getOverview()`、`getRecords(page: Int, size: Int)`。
- 写操作：`submitClockin(request: YgdkClockinSubmitRequest)`。

中转路径为 `api/v1/ygdk/overview`（GET）、`api/v1/ygdk/records`（GET，`page`/`size`）和同路径 POST（多部分表单，包含项目、时间、地点、是否广场及照片）。

### Ygdk：本地实现与上游证据

证据文件：

- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalYgdkApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/feature/YgdkApi.kt`

本地实现先通过 OAuth 重定向获取授权码，再调用 `https://ygdk.buaa.edu.cn/api/Front/Clockin/User/campusAppLogin`（参数 `code`）建立业务会话。查询链路调用：`Classify/getList`、`Item/getList`、`Clockin/getCount`、`Term/get`、`Clockin/getList`；记录查询带分页参数。提交链路还调用 `Upload/File/post` 上传照片，再调用 `Clockin/clockin`。会话按学生标识缓存并有统一过期重试/错误映射。

### Ygdk：DTO 与测试

`Ygdk.kt` 定义 `YgdkTermSummaryDto`、`YgdkItemDto`、`YgdkOverviewResponse`、`YgdkRecordDto`、`YgdkRecordsPageResponse`、`YgdkPhotoUpload`、`YgdkClockinSubmitRequest` 和 `YgdkClockinSubmitResponse`。查询 DTO 覆盖学期汇总、运动项目、记录分页及 `hasMore`。

测试证据：

- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalYgdkApiBackendTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/YgdkApiTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/ygdk/YgdkRoutesTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/ygdk/YgdkServiceTest.kt`

### Ygdk：UBAA2 缺口与优先级

UBAA2 已提供 OAuth 业务会话、概览和记录分页的 Core/CLI 能力，并覆盖照片上传与打卡提交的 multipart/表单协议测试。写操作仅允许 Mock/向量验证；提醒存储属于本地定时任务边界，本轮不迁移。

## LibBook（图书馆座位）

### LibBook：API 与操作

`LibBookApiBackend` 定义：

- 查询：`getLibraries(day)`、`getAreas(premisesId, storeyId?, day)`、`getAreaDetail(areaId)`、`getSeats(areaId, day, startTime, endTime)`、`getBookings(page, limit)`。
- 写操作：`reserve(request)`、`cancelBooking(bookingId)`。

中转路径分别为 `api/v1/libbook/libraries`、`areas`、`areas/{areaId}`、`areas/{areaId}/seats`、`reservations`（查询分页）以及 `bookings` POST、`bookings/{id}/cancel` POST。

### LibBook：本地实现与上游证据

证据文件：

- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalLibBookApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalLibBookCrypto.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalLibBookHttpClient.kt`

本地业务基址为 `https://booking.lib.buaa.edu.cn`，请求统一走 `/v4/`：`space/pick`（图书馆）、`Space/seat`（区域/座位）、`space/confirm`（确认）、`member/seat`（我的预约）等。登录先访问 `https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbooking.lib.buaa.edu.cn%2Fv4%2Flogin%2Fcas`，从最终 URL 解析 `cas` 票据，再调用 `login/user`。实现包含独立客户端缓存、Referer/Origin 头、CAS 重定向和加密预约负载映射。

### LibBook：DTO 与测试

`LibBook.kt` 定义 `LibBookLibraryDto`、`LibBookStoreyDto`、`LibBookAreaDto`、`LibBookTimeSlotDto`、`LibBookAreaDetailDto`、`LibBookSeatDto`、`LibBookReserveRequest`、`LibBookReserveResponse`、`LibBookCancelResponse`、`LibBookBookingsResponse`、`LibBookBookingDto` 及加密请求体。查询 DTO 需保留楼栋/楼层/区域、时段、座位状态和预约分页字段。

测试证据：

- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalLibBookApiBackendTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/model/dto/LibBookBookingStatusTest.kt`
- `ubaa_old/shared/src/jvmTest/kotlin/cn/edu/ubaa/api/LocalLibBookRealIntegrationTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/libbook/LibBookRoutesTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/libbook/LibBookServiceTest.kt`

### LibBook：UBAA2 缺口与优先级

UBAA2 已提供五类图书馆只读查询及独立路线业务会话，并将预约/取消写入口置于显式确认门禁后；真实路线证据仍需逐项复测，写操作绝不由只读 CLI 或实时验证器调用。

## Cgyy（场馆预约）

### Cgyy：API 与操作

`CgyyApiBackend` 定义：

- 查询：`getVenueSites()`、`getPurposeTypes()`、`getDayInfo(venueSiteId, date)`、`getMyOrders(page, size)`、`getOrderDetail(orderId)`、`getLockCode()`。
- 写操作：`submitReservation(request)`、`cancelOrder(orderId)`。

中转路径为 `api/v1/cgyy/sites`、`purpose-types`、`day-info`（参数 `venueSiteId`/`date`）、`orders`（`page`/`size`）、`orders/{id}`、`orders/lock-code`，提交和取消分别为 `reservations` POST、`orders/{id}/cancel` POST。

### Cgyy：本地实现与上游证据

证据文件：

- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalCgyyApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalCgyySigner.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalCgyyCaptchaSupport.kt`

本地基址为 `https://cgyy.buaa.edu.cn/venue-zhjs-server/`，纯查询上游路径为 `/api/front/website/venues`、`/api/codes`、`/api/reservation/day/info`、`/api/orders/mine`、`/api/orders/{id}`、`/api/orders/lock/code`。业务登录先经过 `sso/manageLogin`/前端站点，再调用 `/api/login` 取得 token 或 `access_token`。实现有按用户的客户端缓存、签名、状态映射和统一错误转换。预约提交流程额外包含 `/api/reservation/order/info`、验证码 `/api/captcha/get` 与 `/api/captcha/check`、`/api/reservation/order/submit`，因此不可视为查询。

### Cgyy：DTO 与测试

`Cgyy.kt` 定义场地、用途、时段、时段状态、空间可用性、日期信息、预约选择、预约请求、订单、分页响应、提交响应和锁码响应等 DTO，并提供订单状态/可取消时间的显示计算。

测试证据：

- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalCgyyApiBackendTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalCgyyCaptchaSolverTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalCgyySignerTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/model/dto/CgyyOrderStatusTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/model/dto/CgyyOrderCancellationTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/cgyy/CgyyRoutesTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/cgyy/CgyyServiceTest.kt`

### Cgyy：UBAA2 缺口与优先级

UBAA2 已提供场地、用途、日期、订单、详情和锁码的 Core/CLI 只读入口，并实现独立 token、签名和验证码协议；每项 Cgyy 公共操作均绑定 facade 解析出的路线 runtime，WebVPN 不回退 Direct。真实日期/订单/锁码失败仍按新 Core-live 逐操作摘要记录，写操作仅允许确定性 Mock/向量验证。

## Bykc（博雅课程）

### Bykc：API 与操作

`BykcApiBackend` 定义：

- 查询：`getProfile()`、`getCourses(page, size, all)`、`getCourseDetail(courseId)`、`getChosenCourses()`、`getStatistics()`。
- 写操作：`selectCourse(courseId)`、`deselectCourse(courseId)`、`signCourse(courseId, lat?, lng?, signType)`。

### Bykc：本地实现与上游证据

证据文件：

- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalBykcApi.kt`
- `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalBykcCrypto.kt`

本地客户端先访问 `https://bykc.buaa.edu.cn/sscv/cas/login`，再处理 `cas-login?token=` 重定向。查询调用加密的 `/sscv/{apiName}` 请求，课程选择等动作调用 `/system/course-select`。实现有按用户客户端缓存、AES/请求签名、登录重定向、分页筛选及签到配置解析。由于 `apiName` 在加密请求体中动态传递，冻结实现是确定具体方法和参数的唯一依据，后续不得凭经验拼接。

### Bykc：DTO 与测试

`Bykc.kt` 定义课程分类/子分类/状态枚举，以及 `BykcCourseDto`、`BykcCourseDetailDto`、`BykcChosenCourseDto`、`BykcSignConfigDto`、`BykcSignPointDto`、`BykcUserProfileDto`、`BykcStatisticsDto`、`BykcCategoryStatisticsDto`、分页和成功响应 DTO。详情包含受众、签到配置、当前签到/考核状态和可执行性；列表有 `all` 过滤和分页总数。

测试证据：

- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalBykcApiBackendTest.kt`
- `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/LocalBykcCryptoTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/bykc/BykcClientTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/bykc/BykcCryptoTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/bykc/BykcModelsTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/bykc/BykcRoutesTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/bykc/BykcServiceCacheTest.kt`
- `ubaa_old/server/src/test/kotlin/cn/edu/ubaa/bykc/BykcServiceDetailTest.kt`

### Bykc：UBAA2 缺口与优先级

UBAA2 已提供课程列表、详情、已选课程、统计和资料的 Core/CLI facade，并实现冻结 AES/RSA/SHA-1 请求封装及写链 Mock；已选课程实时上游返回 `upstream_changed`，真实写操作永久禁止。

## 统一后续迁移建议

1. 先把每个查询 operation 的 DTO、URL/参数、认证前置条件和错误分类写入 `docs/migration/source-parity.md` 或独立决策记录；本报告只做库存，不替代逐接口 parity 表。
2. 为每个功能增加脱敏 fixture 和 Mock transport 的失败测试，再实现 `ubaa-core::facade` 方法；CLI 只接受结构化筛选参数并支持 JSON 输出。
3. 业务会话、Cookie、令牌和缓存必须挂在 `UbaaClient` 的路线隔离状态中，不能使用旧版隐式全局客户端。
4. 在真实验收矩阵中单独记录 Direct/WebVPN 是否可用；Mock 通过不能证明上游协议成功。
5. 写操作虽然已完成协议和安全门禁实现，仍保持真实执行禁止；只有另立合同并完成风险评估和独立验收后才能讨论启用。

## 当前 UBAA2 对照表

| 功能 | 旧版查询能力 | 旧版写能力 | 当前 Core/CLI | 建议优先级 |
|---|---|---|---|---|
| Signin | 今日课堂/签到状态 | 执行签到 | 已接入 `signin today`（Core facade + CLI）；真实上游待验证 | 中 |
| Ygdk | 概览、记录分页 | 运动打卡、照片上传 | 已接入 `ygdk overview`/`ygdk records`（Core facade + CLI）；真实上游待验证 | 中低 |
| LibBook | 图书馆、区域、座位、我的预约 | 预约、取消 | 已接入五类只读 CLI；真实路线待验证 | 低 |
| Cgyy | 场地、用途、日期可用性、订单、详情、锁码 | 预约、取消、验证码 | 已接入完整只读及锁码 Core/CLI；预约验证码求解、预约、取消具备确定性协议证据；真实写请求默认禁止。2026-08-29 的一次 Direct 预约并取消仅为周期外历史探针，不属于本周期验收，当前仍禁止真实写；Direct 与 WebVPN 均由 facade 绑定各自路线 runtime，日期/订单/详情/锁码实时可用性由 Core-live 逐操作记录 | 低 |
| Bykc | 资料、课程、详情、已选、统计 | 选课、退选、签到/签退 | 五项只读及三项写请求均已接入 Core/CLI，具备加密向量和 Mock；真实写请求禁止，WebVPN 业务路线仍待上游确认 | 中低 |
