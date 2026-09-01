# Flutter Bridge 合同

状态：P1 合同与生产绑定已提交；P1 验收仍待补齐平台/并发证据

本合同固定 Flutter/FRB 与 Rust Core facade 之间的唯一生产边界。上游 URL、Cookie、
Session 内容、业务 token、签名、验证码材料、原始 HTML/JSON 和诊断方法均不得穿过此边界。
协议事实仍以 `docs/migration/source-parity.md` 为准；本文件只定义已有稳定 facade 的产品投影，
不新增或反推上游协议。

## 1. 版本与命名

- 合同版本为 `1`；FRB、runtime、codegen 和 Cargokit 固定为 `2.13.0`。
- Rust 类型使用 `Bridge` 前缀，Dart 生成类型去除 Rust module 路径并使用 `camelCase` 字段。
- `BridgeClient` 是 opaque handle。Dart 不能读取其内部 Core client、配置目录、Session、
  请求、路线 runtime 或待提交请求。
- 下表中的 `Routed<T>` 表示 `{data: T, route: RouteDecision}`。实际生成代码可以为每个
  `T` 生成具体结果类型，但字段和语义必须完全相同，不得用 `dynamic`、任意 JSON 或字符串
  envelope 代替。
- `RouteDecision` 固定字段为 `policy: RoutePolicy`、`resolvedRoute: ConnectionMode`、
  `network: NetworkState`、`initialRoute: ConnectionMode`、`usedFallback: bool`。

## 2. 生命周期与并发

| 方法 | 输入 | 成功结果 | 稳定语义 |
|---|---|---|---|
| `BridgeClient.open` | `configDir: String` | opaque `BridgeClient` | 只接受绝对应用私有目录；调用 `UbaaClient::open`；不返回或扫描目录内容 |
| `dispose` | 无 | `void` | 幂等；使全部 intent 失效；等待当前持锁操作结束后销毁 Core client |
| `contractVersion` | 无 | `u32=1` | sync、无 I/O |

同一 client 的 Core 调用串行持有一个异步互斥锁；读操作可以在 Dart 侧取消等待，但已经进入
Core 的调用不会被透明重放。dispose 后所有方法返回 `client_disposed`。isolate 重建必须重新
`open`，不得复用旧 handle 或 intent。应用仍处于认证/路线初始化读取阶段时，宿主重建请求
必须安全拒绝，避免旧初始化结果写入新 handle；初始化结束后的下一次生命周期恢复再重建。
panic 由 FRB 捕获为 `internal_error`，不得把 panic 正文、backtrace 或参数回传 UI。

## 3. 错误合同

`Result<T, BridgeError>` 在 Dart 中抛出 typed `BridgeError implements Exception`。字段固定为：

| 字段 | 类型 | 约束 |
|---|---|---|
| `code` | `BridgeErrorCode` | 机器稳定枚举 |
| `kind` | `BridgeErrorKind` | 宽泛分类，不含上游细节 |
| `retryable` | `bool` | 只说明重新发起非写操作是否可能成功 |
| `message` | `String` | Core 已确认安全的消息；UI 默认按 code 映射中文，不直接展示技术正文 |
| `resolvedRoute` | `ConnectionMode?` | 仅在 Core 已完成路线解析时存在 |

Core 错误码逐一映射：`invalid_input`、`authentication_required`、`invalid_credentials`、
`password_risk_confirmation_failed`、`permission_denied`、`network_error`、`timeout`、
`upstream_unavailable`、`upstream_changed`、`parse_error`、`internal_error`。bridge 新增且只用于
本地状态的错误码为 `client_disposed`、`confirmation_required`、`intent_expired`、
`operation_conflict`、`outcome_unknown`。未知 Core 码必须失败关闭为 `internal_error`。

## 4. 认证、会话与路线

| 方法 | 输入 | 成功结果 | 约束 |
|---|---|---|---|
| `prepareLogin` | 无 | `LoginPreparation` | 固定 Direct、WebVPN 两项；不返回 execution 或挑战材料 |
| `login` | `username: String, password: String` | `LoginOutcome` | 密码立即包装为 `SecretValue`；不进入 Debug、日志或持久化 |
| `authStatus` | 无 | `LoginOutcome` | 复用聚合 facade；部分路线成功必须保留 |
| `userInfo` | 无 | `Routed<UserProfile>` | 只返回白名单字段 |
| `logout` | 无 | `void` | 远端尽力、Core Session 清理；不删除平台 CredentialVault |
| `routeSettings` | 无 | `RouteSettings` | 返回配置策略与当前有效路线槽位，不读取 Session 内容 |
| `setDefaultRoutePolicy` | `RoutePolicy` | `RouteSettings` | 有请求或 intent 时拒绝；原子保存、清空 feature override、重开 client、保留路线 Session |

认证 DTO：

- `RouteLoginResult {route, state, error?}`，`state` 仅为 `ready|failed`；错误使用
  `SafeError {code, kind, retryable, message}`。
- `LoginPreparation {routes: List<RouteLoginResult>}`，顺序固定 Direct、WebVPN。
- `LoginOutcome {readiness, routes, profile?}`，`readiness` 为
  `allReady|partial|noneReady`。
- `UserProfile` 白名单为 `username`、`name`、`schoolId`、`email`、`phone`、
  `idCardTypeName`；不向 Flutter 返回证件号码、上游包装或 Cookie。
- `RouteSettings {defaultPolicy, activeRoutes}`；`activeRoutes` 只含 Direct/WebVPN 枚举。

切换策略时必须先确认没有进行中的 bridge 调用和未消费 intent；保存失败保持旧 client 与旧策略。
保存成功后使 intent 全失效，dispose 旧 client，从同一目录重新 open，再返回新设置。Flutter
不得开放 per-feature override，也不得把 `defaultPolicy` 当成某次调用的 `resolvedRoute`。

## 5. 读取方法与 schema

普通页面只能调用下列方法；`*_diagnostics` 不生成到生产 Dart API。

| 方法 | 输入 | `Routed<T>` 中的 `T` |
|---|---|---|
| `scheduleTerms` | 无 | `List<Term>` |
| `scheduleWeeks` | `term: String` | `List<Week>` |
| `scheduleWeek` | `term: String, week: i32` | `WeeklySchedule` |
| `scheduleToday` | 无 | `List<TodayClass>` |
| `examArrangement` | `term: String` | `ExamArrangement` |
| `grades` | `term: String` | `GradeData` |
| `classroomSearch` | `campus: i32, date: String` | `ClassroomQuery` |
| `spocAssignments` | 无 | `SpocAssignments` |
| `spocAssignment` | `assignmentId: String` | `SpocAssignmentDetail` |
| `judgeAssignments` | `includeExpired: bool` | `List<JudgeAssignmentSummary>` |
| `judgeAssignment` | `courseId: String, assignmentId: String` | `JudgeAssignmentDetail` |
| `judgeAssignmentDetails` | `keys: List<JudgeAssignmentKey>` | `List<JudgeAssignmentDetail>` |
| `signinToday` | 无 | `List<SigninClass>` |
| `bykcProfile` | 无 | `BykcUserProfile` |
| `bykcCourses` | `page: i32, size: i32, all: bool` | `BykcCoursePage` |
| `bykcCourseDetail` | `id: i64` | `BykcCourse` |
| `bykcChosenCourses` | 无 | `List<BykcChosenCourse>` |
| `bykcStatistics` | 无 | `BykcStatistics` |
| `libbookLibraries` | `day: String` | `List<LibBookLibrary>` |
| `libbookAreas` | `premisesId: String, storeyId: String?, day: String` | `List<LibBookArea>` |
| `libbookAreaDetail` | `areaId: String` | `LibBookAreaDetail` |
| `libbookSeats` | `areaId: String, day: String, startTime: String, endTime: String` | `List<LibBookSeat>` |
| `libbookBookings` | `page: i32, limit: i32` | `LibBookBookingsPage` |
| `ygdkOverview` | 无 | `YgdkOverview` |
| `ygdkRecords` | `page: i32, size: i32` | `YgdkRecordsPage` |
| `cgyySites` | 无 | `List<CgyyVenueSite>` |
| `cgyyPurposeTypes` | 无 | `CgyyPurposeTypes` |
| `cgyyDayInfo` | `siteId: i32, date: String` | `CgyyDayInfo` |
| `cgyyOrders` | `page: i32, size: i32` | `CgyyOrdersPage` |
| `cgyyOrderDetail` | `id: i32` | `CgyyOrder` |
| `cgyyLockCode` | 无 | `CgyyLockCode` |
| `evaluationAll` | 无 | `EvaluationCoursesResponse` |

DTO 字段保持与 facade 稳定类型一一对应，但只允许以下字段：

- `Term {itemCode,itemName,selected,itemIndex}`；`Week {startDate,endDate,term,curWeek,serialNumber,name}`。
- `CourseClass {courseCode,courseName,courseSerialNo?,credit?,beginTime?,endTime?,beginSection?,endSection?,placeName?,weeksAndTeachers?,teachingTarget?,color?,dayOfWeek?}`；
  `WeeklySchedule {arrangedList,code,name}`；`TodayClass {bizName,place?,time?,shortName?}`。
- `ExamArrangement {arranged,notArranged}`；`Exam {courseName,courseNo?,examTimeDescription?,examDate?,startTime?,endTime?,examPlace?,examSeatNo?,week?,examStatus?,examType?,taskId?}`。
- `GradeData {termCode,grades}`；`Grade {courseName?,courseCode?,credit?,score?,gradePoint?,courseType?,scoreType?,termCode?}`。
- `ClassroomQuery {code,message,floors}`；`floors` 在 bridge 中编码为
  `List<ClassroomFloor {name,rooms}>`，避免跨语言 map 顺序差异；
  `ClassroomInfo {id,floorId,name,availableSections}`。

空教室页面的 `floorId` 和 `section` 仅是 Dart 对上述白名单 DTO 的本地筛选参数：前者按
`ClassroomInfo.floorId` 或分组楼层名精确匹配，后者按冻结 `availableSections` 的逗号分隔
节次令牌精确匹配；它们不会改变 `classroomSearch(campus,date)` 的请求、会话或上游协议。
- `SpocAssignments {termCode,termName?,assignments}`；摘要字段为
  `{assignmentId,courseId,courseName,teacherName?,title,startTime?,dueTime?,score?,submissionStatus,submissionStatusText}`；
  详情在摘要字段后增加 `{contentPlainText?,submittedAt?}`。
- `JudgeAssignmentSummary {courseId,courseName,assignmentId,title,startTime?,dueTime?,maxScore?,myScore?,totalProblems,submittedCount,submissionStatus,submissionStatusText}`；
  `JudgeAssignmentKey {courseId,assignmentId}`；详情增加 `problems` 与 `contentPlainText?`；批量详情保持
  去重后的输入顺序，逐项使用同一白名单详情结构。
  `JudgeProblem {name,score?,maxScore?,status,statusText}`。
- `SigninClass {courseId,courseName,classBeginTime,classEndTime,signStatus}`。
- `BykcUserProfile {id,employeeId?,realName?,studentNo?,collegeName?}`；
  `BykcCourse {id,courseName,coursePosition?,courseTeacher?,courseStartDate?,courseEndDate?,courseSelectStartDate?,courseSelectEndDate?,courseCancelEndDate?,courseMaxCount?,courseCurrentCount?,status,selected?}`；
  `BykcCoursePage {content,totalElements,totalPages,size,number}`。
- `BykcChosenCourse` 仅保留课程/签到所需的公开字段
  `{id,courseId,courseName,coursePosition?,courseTeacher?,courseStartDate?,courseEndDate?,selectDate?,courseCancelEndDate?,category?,subCategory?,checkin,score?,pass?,canSign,canSignOut,signConfig?,courseSignType?}`；`signConfig` 仅含四个时间字段与
  `signPoints {lat,lng,radius}`。作业正文、附件名称/路径和签到附注属于内部材料，均不得跨 FFI。
  `BykcStatistics {totalValidCount?,categories}`，分类项为
  `{categoryName?,subCategoryName?,requiredCount?,passedCount?,qualified?}`。
- `LibBookLibrary {id,name,freeNum,totalNum,storeys}`；`LibBookStorey` 同名计数字段；
  `LibBookArea {id,name,areaName,premisesId,storeyId,freeNum,totalNum}`；
  `LibBookAreaDetail {id,name,availableDates,timeSlots}`；时段 `{id,start,end,label}`；
  座位 `{id,name,no,status,statusName,isAvailable}`；预约
  `{id,nameMerge,areaName,seatNo,day,beginTime,endTime,status,statusName}`；分页
  `{bookings,page,limit,total}`。
- `YgdkOverview {summary,classifyId,classifyName,defaultItemId,defaultItemName,items}`；统计
  `{termId?,termName?,termCount,termTarget?,weekCount?,weekTarget?,monthCount?,monthTarget?,dayCount?,goodCount?}`；
  项目 `{itemId,name,kind?,sort?}`；记录分页 `{content,total,page,size,hasMore}`；记录
  `{recordId,itemId?,itemName?,startTime?,endTime?,place?,images,isOpen,state?,createdAt?,createdAtLabel?}`。
- `CgyyVenueSite`、`CgyyTimeSlot`、`CgyySpaceAvailability`、`CgyyDayInfo` 保持 facade 公共字段；
  `CgyySlotStatus` 仅允许 `{timeId,reservationStatus,isReservable,startDate?,endDate?}`；交易号、
  订单号、占用数量/标记和内部说明不得跨 FFI。`CgyyOrder` 的 Dart 投影仅允许
  `{id,venueSiteId?,reservationDate?,reservationDateDetail?,venueSpaceName?,campusName?,venueName?,siteName?,reservationStartDate?,reservationEndDate?,orderStatus?,checkStatus?,theme?,purposeTypeName?,joinerNum?}`。
  交易号、手机号、支付状态、用途原始编号、活动正文、参与人、审核内容、处理原因和备注
  不得进入 `BridgeCgyyOrder`；写入结果另只从该投影提取非敏感收据。`CgyyOrdersPage`
  保持分页字段；用途结果必须为 `{items,source}`，`source` 为
  `upstream|staticFallback`；锁码只含 `{available}`。
- `EvaluationCoursesResponse {courses,progress}`；课程保持 facade 公开字段；进度为
  `{totalCourses,evaluatedCourses,pendingCourses}`。Dart 的待评列表必须由
  `courses.where((course) => !course.isEvaluated)` 派生，不存在 `evaluationPending` 方法。

枚举 wire 值固定为 Core serde 值；Dart 不以展示文案替代 wire 值。所有 ID 保持原 Core
类型，不把字符串 ID 自动转数字，不把可选字段默认成空字符串或零。

共享应用层的 `FeatureQuery` 只携带已证明的 typed 查询参数。除学期、日期、校区、周次和分页
外，Bykc、图书馆、阳光打卡、场馆预约、SPOC 和 Judge 详情使用封闭的 `FeatureQueryView` 与公开
ID/分页字段：

| `view` | 必填字段 | bridge 调用 |
|---|---|---|
| `summary` | `date?` | `libbookLibraries(day)` |
| `scheduleToday` | 无 | `scheduleToday` |
| `scheduleTerms` | 无 | `scheduleTerms` |
| `scheduleWeeks` | `term` | `scheduleWeeks(term)` |
| `scheduleWeek` | `term`、`week` | `scheduleWeek(term, week)` |
| `evaluationPending` | 无 | `evaluationAll` 后按 `isEvaluated=false` 本地派生 |
| `examArranged` | `term?` | `examArrangement(term)` 后取 `arranged` |
| `examNotArranged` | `term?` | `examArrangement(term)` 后取 `notArranged` |
| `gradesScored` | `term?` | `grades(term)` 后按 `score` 非空本地派生 |
| `gradesMissing` | `term?` | `grades(term)` 后按 `score` 空值本地派生 |
| `bykcDetail` | `courseId`（正整数） | `bykcCourseDetail(courseId)` |
| `bykcProfile` | 无 | `bykcProfile` |
| `bykcChosenCourses` | 无 | `bykcChosenCourses` |
| `bykcStatistics` | 无 | `bykcStatistics` |
| `libbookAreas` | `premisesId`，`storeyId?`，`date?` | `libbookAreas(premisesId, storeyId?, day)` |
| `libbookAreaDetail` | `areaId` | `libbookAreaDetail(areaId)` |
| `libbookSeats` | `areaId`、`startTime`、`endTime`、`date?` | `libbookSeats(areaId, day, startTime, endTime)` |
| `libbookBookings` | `page`、`size` | `libbookBookings(page, limit)` |
| `ygdkRecords` | `page`、`size` | `ygdkRecords(page, size)` |
| `cgyyPurposeTypes` | 无 | `cgyyPurposeTypes`（含 `source`） |
| `cgyyDayInfo` | `siteId`、`date?` | `cgyyDayInfo(siteId, date)` |
| `cgyyOrders` | `page`、`size` | `cgyyOrders(page, size)` |
| `cgyyOrderDetail` | `orderId` | `cgyyOrderDetail(orderId)` |
| `cgyyLockCode` | 无 | `cgyyLockCode`（只含 `available`） |
| `spocDetail` | `assignmentId` | `spocAssignment(assignmentId)` |
| `judgeDetail` | `courseId`、`assignmentId` | `judgeAssignment(courseId, assignmentId)` |
| `judgeBatchDetails` | `judgeKeys: List<{courseId,assignmentId}>`，至少一项 | `judgeAssignmentDetails(keys)` |
| `signinPending` | 无 | `signinToday` 后按 `signStatus == 0` 本地派生 |
| `signinCompleted` | 无 | `signinToday` 后按 `signStatus == 1` 本地派生 |

缺少必填 ID、时段或批量键时由 bridge 返回 `invalid_input`；Dart 不拼接 URL、JSON 或 Cookie。Judge
批量键在 UI 中使用每行 `课程编号/作业编号` 的公开编号格式解析为 typed 列表，不把该文本作为 raw
payload 传递。查询结果
仍只映射到白名单 `FeatureDetail`，预约 ID、座位 ID、区域 ID、场馆站点 ID 和订单 ID 仅作为
用户选择后再次查询的公开标识，不进入日志或遥测。Cgyy 用途结果始终携带 `source`，UI 必须
明示 `staticFallback`，不得将冻结回退伪称为上游成功；门锁结果只允许展示 `available`。

## 6. 写 intent

Flutter 不直接调用 facade 写方法。每项写入先调用 typed prepare，再由同一 client 调用
`commitWrite(intentId)`：

| prepare 方法 | typed 请求 | commit 结果 variant |
|---|---|---|
| `prepareBykcSelectCourse` | `{courseId}` | `bykcAction` |
| `prepareBykcDeselectCourse` | `{courseId}` | `bykcAction` |
| `prepareBykcSignCourse` | `{courseId,lat?,lng?,signType}` | `bykcAction` |
| `prepareSigninPerform` | `{courseId}` | `signinAction` |
| `prepareLibbookReserve` | `{areaId,seatId,day,segment,startTime,endTime}` | `libbookReserve` |
| `prepareLibbookCancelBooking` | `{id}` | `libbookCancel` |
| `prepareYgdkSubmit` | `{itemId?,startTime?,endTime?,place?,shareToSquare?,photo?}` | `ygdkSubmit` |
| `prepareCgyySubmitReservation` | facade 公开请求字段，不含 challenge 内部材料 | `cgyyReservation` |
| `prepareCgyyCancelOrder` | `{id}` | `cgyyAction` |
| `prepareEvaluationSubmitCourses` | `{courses: List<EvaluationCourse>}` | `evaluationBatch` |

`cgyyReservation` 成功结果可附带 `CgyyReservationReceipt`，只投影
`orderId`、可选 `venueSiteId`、可选 `reservationDate` 和可选 `orderStatus`；交易号、电话、主题、
参与人及活动正文不会进入 Dart。App 在成功回调后优先刷新 `cgyyOrders`，页面必须以订单列表/详情
作为最终核对来源，并且只在刷新成功且订单列表出现同一公开 `orderId` 时标记为已核对；UI 可以显示
订单编号并提示核对，但收据缺失、刷新失败或编号不匹配不得宣称已完成核对。

`WriteIntent` 固定字段：

| 字段 | 类型 | 语义 |
|---|---|---|
| `intentId` | `String` | 当前 client 内随机 128-bit 标识，不持久化 |
| `operation` | `WriteOperation` | 封闭枚举，与 prepare 方法一一对应 |
| `targetSummary` | `String` | 不含手机号、位置、照片名、token 或个人标识的中文摘要 |
| `resolvedRoute` | `ConnectionMode` | prepare 时 Core 解析的实际路线 |
| `warnings` | `List<String>` | 固定产品提示，不拼上游正文 |
| `expiresAt` | `i64` | Unix 秒，默认 prepare 后 120 秒 |
| `requestDigest` | `String` | 规范化非秘密请求的 SHA-256 十六进制摘要 |

intent 只在内存中保存 typed 请求和 prepare 时的 Session 修订/路线；不得保存密码、Cookie、
challenge 图片或外部验证码三元组。commit 原子取出 intent 后再执行，因此重复点击最多一次进入
Core。过期、已消费、client 重开、策略改变、Session 改变、同目标冲突或摘要不一致均不得执行
网络写入。写请求可能到达上游后出现 timeout/连接中断时返回 `outcome_unknown`，intent 仍视为已
消费，Flutter 必须调用合同指定的读取方法核对，禁止自动重试。

照片通过 `BridgePhoto {bytes,fileName,mimeType}` 一次传入；Debug 只记录字节数与 MIME 类型。
场馆 challenge 由 Core typed 流程内部完成，bridge 不公开图片、secret key、point JSON、token
或 verification。`evaluationSubmit` 的原始字符串 payload 不生成到 Dart。

场馆预约的 bridge prepare 在路线解析前执行本地输入门禁：站点/日期、至少一个有效时段、同一房间、联系电话/主题/活动内容、正用途编号和正参与人数必须满足；这只约束产品 typed 请求，不改变 Core 上游协议。阳光打卡和场馆预约的 `request_digest` 只对非敏感形状做规范化（结构 ID、文本存在/长度、照片字节数/MIME、布尔值），不写入或哈希返回电话、主题、参与人、活动正文、地点、照片文件名和照片字节，避免敏感材料穿过 intent 投影；对应回归记录在 `docs/migration/source-parity.md`。

## 7. 来源对照与安全边界

| bridge 领域 | 协议对照权威 |
|---|---|
| 认证、用户资料、Session、路线 | `source-parity.md` 的“网关探测”“双路线加载/保存/退出”“准备/登录”“用户资料”“CLI 与配置” |
| 课表、考试、成绩、空教室 | “未改变的课表/考试证据”“未改变的成绩证据”“空教室会话同步/查询” |
| SPOC、Judge | “SPOC 认证/列表/详情”“Judge 列表/详情/批量与缓存” |
| Signin、Ygdk、LibBook | “课堂签到今日查询”“阳光打卡只读查询”“图书馆座位只读查询”及直接写操作表 |
| Bykc、Cgyy、Evaluation | “博雅课程只读查询”“场馆预约只读查询”及直接写操作表 |

bridge 只调用这些已对照 facade 方法，不拥有重定向、Cookie、Header、加密、缓存或重试逻辑。
新增 bridge DTO 不授权改变 Core 协议；若 facade 字段发生变化，必须先按 `AGENTS.md` 更新来源
对照、失败测试和 Core 合同，再更新本文件与生成绑定。

## 8. 验收门禁

- Rust：每个映射的字段快照、错误映射、dispose、串行锁、panic 归约、intent 过期/重复/
  Session 或路线失效、outcome unknown 和 typed 请求测试。
- Dart：生成 API schema 快照（包括场馆订单、场馆时段和博雅已选课程内部字段禁曝断言）、`evaluationAll` 待评派生、ID/可选字段、错误映射和
  `BridgeClient` isolate 重建测试；宿主通过 `BackendFactory` 创建新的 opaque
  backend 后，应用重新读取持久化路线与认证状态，不复用已 dispose 的 handle。
- FRB：`just flutter-codegen-check` 二次生成零漂移；生成目录禁止手改。
- 安全：Debug/Display、错误、intent 摘要和测试 fixture 均不得出现密码、Cookie、token、
  完整证件号、完整手机号、照片内容、challenge 或真实响应。
- 平台：五平台 native library 构建和 OHOS arm64 HAP 最终均调用同一合同版本。

P1 只有全部方法、DTO、写 intent、测试与生成绑定同时完成后才能勾选；只有合同文件或部分方法
不能标记 P1 完成。

## 9. 当前实现证据（2026-09-01）

- 提交 `2faa753` 实现 `BridgeClient` opaque 生命周期、认证、路线设置、全部表中读取方法、
  typed 写入准备/一次性提交和安全错误投影；Core 新增仅用于准备阶段的路线解析入口。
- `just flutter-codegen-check` 在该提交后再次生成并报告“FRB 生成零漂移”；生成的 Rust/Dart
  文件由 FRB 机械产出，未手工改写生成内容。
- `cargo fmt --all`、bridge 严格 Clippy、bridge 测试（4 项）和 `just check` 均通过；测试覆盖
  相对路径拒绝、幂等 dispose、use-after-dispose、随机 intent/digest 形状以及未知/重复 intent
  在网络前拒绝。
- 生产 Flutter 适配提交 `7bd8fd2` 通过 `BridgeBackend` 连接上述 API，并保留显式
  `UnavailableBackend` 安全失败；生产入口不再默认构造 `DemoBackend`。
- 读取结果中的 `RouteDecision.resolvedRoute` 现在沿 `FeatureResult`、`FeatureSnapshot` 和
  `BridgeBackend` 传到卡片与详情页；页面显示“实际路线”，不会把 `defaultPolicy` 冒充为本次
  请求路线。app/widget 回归测试固定该投影，刷新失败的 `stale` 数据继续保留上次实际路线。
- 应用层现在通过受限的 `RouteSettingsBackend` 读取 `defaultPolicy` 与 `activeRoutes`；切换
  固定路线后若目标槽位未认证，会清除用户与功能快照并回到登录页，避免继续展示旧路线数据。
  生产 bridge 仍由 Core 完成原子保存、重开和 intent 失效，Dart 不读取 Session 内容。
- 应用启动时先读取同一投影恢复 Core 已保存的 `defaultPolicy`，再检查认证状态；因此设置页不会
  把 `auto` 默认值误显示为持久化的固定路线。
- `AppController.rebuildBackend()` 为 isolate/宿主生命周期重建提供显式安全入口：只有新
  backend 创建成功后才释放旧实例，清空旧用户、路线投影和功能快照，再重新执行初始化；没有
  `BackendFactory` 或正在登录/重建时返回失败，不伪造恢复成功。
- panic 归约、跨进程 Session 锁、路线/会话失效 intent 和场馆订单敏感字段禁曝快照已有实现与
  回归；尚未把这些结果标记为 P1 完成。Dart isolate 的真实重建/内存泄漏证据、完整逐 DTO
  domain/UI 消费测试和跨平台生命周期证据仍需逐项补齐。
