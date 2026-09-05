# Flutter Bridge 合同

状态：合同 v9 的 Phase 11J typed 实现已进入当前工作树，完整本地确定性门禁与阶段提交待完成；此前 P1 证据只作历史基线，实体设备上的
原生 isolate/内存观测仍是后置发布证据

本合同固定 Flutter/FRB 与 Rust Core facade 之间的唯一生产边界。上游 URL、Cookie、
Session 内容、业务 token、签名、验证码材料、原始 HTML/JSON 和诊断方法均不得穿过此边界。
协议事实仍以 `docs/migration/source-parity.md` 为准；本文件只定义已有稳定 facade 的产品投影，
不新增或反推上游协议。

## 1. 版本与命名

- 合同版本为 `9`；FRB、runtime、codegen 和 Cargokit 固定为 `2.13.0`。历史版本 3 将课堂签到
  `signStatus` 改为可空并新增 typed eligibility/target；版本 4 又将 LibBook 座位 `status` 改为
  可空整数，以 typed `reserveEligibility/reserveTarget` 取代 `isAvailable`。版本 5 将 LibBook booking
  `status` 改为可空整数并新增 typed `cancelEligibility/cancelTarget`，同时让取消请求携带本地
  `id/page/limit` authority 上下文。版本 6 将 Cgyy 时段 `reservationStatus` 改为可空整数，以 typed
  `reservationEligibility/reservationTarget` 取代 `isReservable`，并将预约成功结果收窄为安全收据。
  版本 7 再为 Cgyy 订单增加 typed `cancelEligibility/cancelTarget/cancelledTarget`，并新增
  caller-pinned 的取消列表/详情回读。版本 8 为 Ygdk 项目增加 typed
  `submitEligibility/submitTarget`，将提交请求收紧为完整 typed target、canonical 时间和必需照片，并新增
  caller-pinned 的概览/记录回读与安全提交收据。版本 9 为 Evaluation 增加 typed
  `submitEligibility/submitTarget`、只含 targets 的批量请求、四态逐项结果与 caller-pinned 原路线回读。
  版本 9 不与版本 8 或更早的生成绑定混用。
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
| `contractVersion` | 无 | `u32=9` | sync、无 I/O；宿主必须与同一次 codegen 产物配套 |

同一 client 的 Core 调用串行持有一个异步互斥锁；读操作可以在 Dart 侧取消等待，但已经进入
Core 的调用不会被透明重放。dispose 后所有方法返回 `client_disposed`。isolate 重建必须重新
`open`，不得复用旧 handle 或 intent。应用仍处于认证/路线初始化读取阶段时，宿主重建请求
必须安全拒绝，避免旧初始化结果写入新 handle；初始化结束后的下一次生命周期恢复再重建。
panic 由 FRB 捕获为 `internal_error`，不得把 panic 正文、backtrace 或参数回传 UI。

`AppController.initialize` 在每个异步路线、认证、用户资料和凭据读取边界检查 controller
生命周期；若宿主已销毁，后续读取和首页刷新立即停止。宿主销毁会尽力释放当前 backend，不能
让已完成的旧初始化结果重新写入 UI 状态。

`refreshHome` 与 `refreshFeatureQuery` 在 controller 销毁后立即成为 no-op；已在途的读取只在
controller 仍存活且代次未变化时写入快照，成功或失败结果都不能回写已销毁状态。

登录提交同样受 controller 生命周期约束：`login`、路线状态和用户资料的在途结果在销毁后
不再继续读取或写入用户/凭据/UI 状态；安全凭据清理仍可在已开始的失败处理内完成。

路线策略切换在 controller 销毁后也立即停止；延迟的 `prepareLogin` 或路线状态读取不得
回写默认策略、活动路线或错误状态。

注销调用在 controller 销毁后为 no-op；已在途的注销完成后不得回写用户、活动路线、登录表单
或阶段状态。若调用方已明确要求清理已保存凭据，清理动作仍按安全边界执行。

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
`upstream_unavailable`、`outcome_unknown`、`upstream_changed`、`parse_error`、`internal_error`。
博雅签到、课堂签到、LibBook 预约/取消、Cgyy 预约/取消、Ygdk 与 Evaluation 提交合同都只允许在非幂等写请求越过
发送边界后产生 `outcome_unknown`；其余写操作暂时保留既有的 commit 阶段保守映射，可能把业务登录或
预检中的网络类失败也归入结果未知，必须在后续来源对照阶段逐项收窄。LibBook 的 `outcome_unknown`
保留 Core 提供的稳定 code、kind 与安全 message，同时强制 `retryable=false`；Cgyy 预约遵守相同的安全
message、不可重试和先读后判定约束。Ygdk upload 与 final 都不得自动重试；upload 失败时不得发送 final，
final 发送后无法确定结果才进入不可重试的 `outcome_unknown`。无论来源如何，宿主都必须禁止自动重试并先执行只读核对。bridge 新增且
只用于本地状态的错误码为 `client_disposed`、`confirmation_required`、`intent_expired`、
`operation_conflict`。未知 Core 码必须失败关闭为 `internal_error`。

## 4. 认证、会话与路线

| 方法 | 输入 | 成功结果 | 约束 |
|---|---|---|---|
| `prepareLogin` | 无 | `LoginPreparation` | 固定 Direct、WebVPN 两项；不返回 execution 或挑战材料 |
| `login` | `username: String, password: String` | `LoginOutcome` | 密码立即包装为 `SecretValue`；不进入 Debug、日志或持久化；成功后使旧 intent 失效 |
| `authStatus` | 无 | `LoginOutcome` | 复用聚合 facade；部分路线成功必须保留；调用完成后使全部旧 intent 失效 |
| `userInfo` | 无 | `Routed<UserProfile>` | 只返回白名单字段 |
| `logout` | 无 | `void` | 远端尽力、Core Session 清理并使旧 intent 失效；不删除平台 CredentialVault |
| `routeSettings` | 无 | `RouteSettings` | 返回配置策略与当前有效路线槽位，不读取 Session 内容 |
| `setDefaultRoutePolicy` | `RoutePolicy` | `RouteSettings` | 有进行中的 Core 请求时拒绝；原子保存、清空 feature override、重开 client、保留路线 Session，并使旧 intent 失效 |

认证 DTO：

- `RouteLoginResult {route, state, error?}`，`state` 仅为 `ready|failed`；错误使用
  `SafeError {code, kind, retryable, message}`。
- `LoginPreparation {routes: List<RouteLoginResult>}`，顺序固定 Direct、WebVPN。
- `LoginOutcome {readiness, routes, profile?}`，`readiness` 为
  `allReady|partial|noneReady`。
- `UserProfile` 白名单为 `username`、`name`、`schoolId`、`email`、`phone`、
  `idCardTypeName`；不向 Flutter 返回证件号码、上游包装或 Cookie。
- `RouteSettings {defaultPolicy, activeRoutes}`；`activeRoutes` 只含 Direct/WebVPN 枚举。

切换策略时若有进行中的 Core 调用则拒绝；待确认 intent 不阻止切换，但保存和重开成功后必须全部失效。
保存失败保持旧 client 与旧策略。成功时从同一目录重新 open，再返回新设置。Flutter
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
| `ygdkOverviewOnRoute` | `route: ConnectionMode` | `CallerPinnedYgdkOverview` |
| `ygdkRecordsOnRoute` | `route: ConnectionMode, page: i32, size: i32` | `CallerPinnedYgdkRecords` |
| `cgyySites` | 无 | `List<CgyyVenueSite>` |
| `cgyyPurposeTypes` | 无 | `CgyyPurposeTypes` |
| `cgyyDayInfo` | `siteId: i32, date: String` | `CgyyDayInfo` |
| `cgyyOrders` | `page: i32, size: i32` | `CgyyOrdersPage` |
| `cgyyOrderDetail` | `id: i32` | `CgyyOrder` |
| `cgyyLockCode` | 无 | `CgyyLockCode` |
| `evaluationAll` | 无 | `EvaluationCoursesResponse` |
| `evaluationAllOnRoute` | `route: ConnectionMode` | `CallerPinnedEvaluation` |

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
- `SigninClass {courseId,courseName,classBeginTime,classEndTime,signStatus?,signinEligibility,signinTarget?}`；
  `signStatus=0/1` 分别映射 `allowed/denied`，缺失、畸形或其它值映射 `unknown`。宿主只消费
  typed eligibility/target 决定操作，action 缺失、`unknown`、`denied` 或空目标都必须拒绝。
- `BykcUserProfile {id,employeeId?,realName?,studentNo?,collegeName?}`；
  `BykcCourse {id,courseName,coursePosition?,courseTeacher?,courseStartDate?,courseEndDate?,courseSelectStartDate?,courseSelectEndDate?,courseCancelEndDate?,courseMaxCount?,courseCurrentCount?,status,selected?,selectEligibility,deselectEligibility}`；
  两项 eligibility 都是 `allowed/denied/unknown` 的封闭枚举，缺失 action 或 `unknown` 均必须按拒绝处理；
  `BykcCoursePage {content,totalElements,totalPages,size,number}`。
- `BykcChosenCourse` 仅保留课程/签到所需的公开字段
  `{id,courseId,courseName,coursePosition?,courseTeacher?,courseStartDate?,courseEndDate?,selectDate?,courseCancelEndDate?,category?,subCategory?,checkin?,score?,pass?,signEligibility,signOutEligibility,deselectEligibility,signConfig?,courseSignType?}`；
  三项 eligibility 均为 `allowed/denied/unknown` 的封闭枚举，`checkin` 缺失时保持 `null`；`signConfig` 仅含四个时间字段与
  `signPoints {lat,lng,radius}`。作业正文、附件名称/路径和签到附注属于内部材料，均不得跨 FFI。
  `BykcStatistics {totalValidCount?,categories}`，分类项为
  `{categoryName?,subCategoryName?,requiredCount?,passedCount?,qualified?}`。
- `LibBookLibrary {id,name,freeNum,totalNum,storeys}`；`LibBookStorey` 同名计数字段；
  `LibBookArea {id,name,areaName,premisesId,storeyId,freeNum,totalNum}`；
  `LibBookAreaDetail {id,name,availableDates,timeSlots}`；时段 `{id,start,end,label}`；
  座位 `{id,name,no,status?,statusName,reserveEligibility,reserveTarget?}`；`status` 只允许可空整数，
  eligibility 为 `allowed|denied|unknown`，仅明确状态与非空稳定目标产生 target；预约
  `{id,nameMerge,areaName,seatNo,day,beginTime,endTime,status?,statusName,cancelEligibility,cancelTarget?}`；
  `status` 只允许可空整数，canonical `1` 为 `allowed`、`6/8` 为 `denied`，缺失、畸形或其它值为
  `unknown`；非空 ID 的 `1/6/8` 保留 target，只有 `unknown` 不签发 target。`statusName` 仅供展示；分页
  `{bookings,page,limit,total}`。
- `YgdkOverview {summary,classifyId,classifyName,defaultItemId,defaultItemName,items}`；统计
  `{termId?,termName?,termCount,termTarget?,weekCount?,weekTarget?,monthCount?,monthTarget?,dayCount?,goodCount?}`；
  项目 `{itemId,name,kind?,sort?,submitEligibility,submitTarget?}`，其中 `submitTarget` 仅为
  `{classifyId,itemId}`；记录分页 `{content,total,page,size,hasMore}`；记录
  `{recordId,itemId?,itemName?,startTime?,endTime?,place?,imageCount,isOpen,state?,createdAt?,createdAtLabel?}`。
  只有 Core 从同一 fresh overview 中证明 canonical 正数 classify/item 身份各自唯一、名称非空且
  target 与父项严格一致时，`submitEligibility` 才能为 `allowed` 并携带 target；其余情况均为
  `unknown` 且无 target。`imageCount` 只表示图片数量；图片地址列表和其中可能包含的业务令牌不得跨 FFI。
  `CallerPinnedYgdkOverview` 与 `CallerPinnedYgdkRecords` 只含 `{data,pinnedRoute}`，表示 Core 实际使用
  调用方指定的已认证路线，不伪造 `RouteDecision`，也不执行 Auto 探测或跨路线回退。
- `CgyyVenueSite`、`CgyyTimeSlot`、`CgyySpaceAvailability`、`CgyyDayInfo` 保持 facade 公共字段；
  `CgyySlotStatus` 仅允许
  `{timeId,reservationStatus?,reservationEligibility,reservationTarget?,startDate?,endDate?}`。
  `reservationStatus` 只允许可空整数；eligibility 为 `allowed|denied|unknown`，仅明确 `allowed` 且站点、
  日期、空间、空间组及时段身份完整唯一时提供 target。`CgyyReservationTarget` 固定为
  `{venueSiteId,reservationDate,spaceId,timeId,venueSpaceGroupId?,timeOrdinal}`：站点、空间和时段 ID 必须为
  正数，日期非空，空间组为 `null` 或正数，raw `timeOrdinal` 为非负整数。交易号、
  订单号、占用数量/标记和内部说明不得跨 FFI。`CgyyOrder` 的 Dart 投影仅允许
  `{id,venueSiteId?,reservationDate?,reservationDateDetail?,venueSpaceName?,campusName?,venueName?,siteName?,reservationStartDate?,reservationEndDate?,orderStatus?,checkStatus?,theme?,purposeTypeName?,joinerNum?,cancelEligibility,cancelTarget?,cancelledTarget?}`。
  `cancelTarget` 只在 Core 确认订单可取消且 canonical 正数 ID 与订单一致时存在；
  `cancelledTarget` 只在 Core 严格解析同 ID `orderStatus=2`、资格为 `denied` 且无待取消目标时存在。
  交易号、手机号、支付状态、用途原始编号、活动正文、参与人、审核内容、处理原因和备注
  不得进入 `BridgeCgyyOrder`；写入结果另只从该投影提取非敏感收据。`CgyyOrdersPage`
  保持分页字段；用途结果必须为 `{items,source}`，`source` 为
  `upstream|staticFallback`；锁码只含 `{available}`。
- `EvaluationCoursesResponse {courses,progress}`；课程只允许
  `{id,kcmc,bpmc,isEvaluated,submitEligibility,submitTarget?}`，target 固定为
  `{rwid,wjid,kcdm,bpdm?}`。只有 Core 给出未评、非空课程/教师名、`allowed`、完整严格 target，且
  `id == "rwid_wjid_kcdm_bpdm"`、规范化 target 在同批课程中唯一时，Bridge 才保留 action；`bpdm=null`
  与空串属于同一 identity。其余矛盾、空白别名或重复均降级为 `unknown` 且无 target。进度为
  `{totalCourses,evaluatedCourses,pendingCourses}`。Dart 的待评列表必须由
  `courses.where((course) => !course.isEvaluated)` 派生，不存在 `evaluationPending` 方法。
  `CallerPinnedEvaluation` 只含 `{data,pinnedRoute}`，不执行 Auto 探测或跨路线 fallback。

枚举 wire 值固定为 Core serde 值；Dart 不以展示文案替代 wire 值。所有 ID 保持原 Core
类型，不把字符串 ID 自动转数字，不把可选字段默认成空字符串或零。

共享应用层的 `FeatureQuery` 只携带已证明的 typed 查询参数。除学期、日期、校区、周次和分页
外，Bykc、图书馆、阳光打卡、场馆预约、SPOC 和 Judge 详情使用封闭的 `FeatureQueryView` 与公开
ID/分页字段：

支持分页的查询结果在应用层以封闭 `FeaturePagination` 投影 Core 返回的 `page`、`size`、`total`、
可选 `totalPages`/`hasMore`；展示页码统一采用 1-based 语义。该元数据不改变 bridge 请求参数，
也不向 UI 暴露原始上游响应。

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
| `libbookSeats` | `areaId`、`segment`、`startTime`、`endTime`、`date?` | `libbookSeats(areaId, day, startTime, endTime)`；`segment` 只进入 typed 预约 action，不改变只读请求 |
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
| `signinPending` | 无 | `signinToday` 后按 `signinEligibility == allowed` 本地派生 |
| `signinCompleted` | 无 | `signinToday` 后按 `signinEligibility == denied` 本地派生 |

缺少必填 ID、时段或批量键时由 bridge 返回 `invalid_input`；Dart 不拼接 URL、JSON 或 Cookie。Judge
批量键在 UI 中使用每行 `课程编号/作业编号` 的公开编号格式解析为 typed 列表，不把该文本作为 raw
payload 传递。查询结果
仍只映射到白名单 `FeatureDetail`，预约 ID、座位 ID、区域 ID、场馆站点 ID 和订单 ID 仅作为
用户选择后再次查询的公开标识，不进入日志或遥测。Cgyy 用途结果始终携带 `source`，UI 必须
明示 `staticFallback`，不得将冻结回退伪称为上游成功；门锁结果只允许展示 `available`。
图书馆预约详情将 nullable `status`、`cancelEligibility/cancelTarget` 一并投影；UI 只消费 typed action
决定取消入口，`statusName` 和“状态码”只供展示，不参与资格推断。场馆订单列表/详情可投影冻结
`checkStatus` 为“审核状态”，仅供展示；这些字段均不是令牌、交易号或内部正文，不改变 Core 的最终取消资格校验。
场馆订单同时提供由冻结状态码派生的“订单状态说明/审核状态说明”，仅作为稳定中文展示文本；Dart 不据此拼接
请求或改变 Core 的取消资格。`BridgeCallerPinnedCgyyOrders` 与
`BridgeCallerPinnedCgyyOrder` 只包含 `{data,pinnedRoute}`；它们表示 Core 实际使用了调用方指定的
已认证路线，不伪造 `RouteDecision`，不执行 Auto 探测或跨路线回退。

## 6. 写 intent

Flutter 不直接调用 facade 写方法。每项写入先调用 typed prepare，再由同一 client 调用
`commitWrite(intentId)`；用户取消确认时调用 `discardWriteIntent(intentId)`，在 Bridge 内显式释放
待确认意图：

| prepare 方法 | typed 请求 | commit 结果 variant |
|---|---|---|
| `prepareBykcSelectCourse` | `{courseId}` | `bykcAction` |
| `prepareBykcDeselectCourse` | `{courseId}` | `bykcAction` |
| `prepareBykcSignCourse` | `{courseId,lat?,lng?,signType}` | `bykcAction` |
| `prepareSigninPerform` | `{courseId}` | `signinAction` |
| `prepareLibbookReserve` | `{areaId,seatId,day,segment,startTime,endTime}` | `libbookReserve` |
| `prepareLibbookCancelBooking` | `{id,page,limit}` | `libbookCancel` |
| `prepareYgdkSubmit` | `{target:{classifyId,itemId},startTime,endTime,place?,shareToSquare,photo:{bytes,fileName,mimeType}}` | `ygdkSubmit` |
| `prepareCgyySubmitReservation` | 由 1–2 个 `CgyyReserveAction` 唯一派生的目标与表单字段；不含 challenge 内部材料 | `cgyyReservation` |
| `prepareCgyyCancelOrder` | `{orderId}` | `cgyyCancelOrder` |
| `prepareEvaluationSubmitCourses` | `{targets: List<EvaluationSubmitTarget>}` | `evaluationBatch` |

`cgyyReservation` 成功结果可附带 `CgyyReservationReceipt`，只投影
`orderId`、可选 `venueSiteId`、可选 `reservationDate` 和可选 `orderStatus`；交易号、电话、主题、
参与人及活动正文不会进入 Dart。App 在成功回调后优先刷新 `cgyyOrders`，页面必须以订单列表/详情
作为最终核对来源，并且只在刷新成功且订单列表出现同一公开 `orderId` 时标记为已核对；UI 可以显示
订单编号并提示核对，但收据缺失、刷新失败或编号不匹配不得宣称已完成核对。

`ygdkSubmit` 的确定成功结果固定为 `success=true`、安全文案“阳光打卡已提交”和可选
`YgdkSubmitReceipt {recordId}`；`recordId` 只有在 Core 返回 canonical 正整数时存在。收据不得携带
`classifyId`、`itemId`、summary、raw message/body、时间、地点、照片信息、uid 或 token。

`WriteIntent` 固定字段：

| 字段 | 类型 | 语义 |
|---|---|---|
| `intentId` | `String` | 当前 client 内随机 128-bit 标识，不持久化 |
| `operation` | `WriteOperation` | 封闭枚举，与 prepare 方法一一对应 |
| `targetSummary` | `String` | 不含手机号、位置、照片名、token 或个人标识的中文摘要 |
| `resolvedRoute` | `ConnectionMode` | prepare 时 Core 解析的实际路线 |
| `warnings` | `List<String>` | 固定产品提示，不拼上游正文 |
| `expiresAt` | `i64` | Unix 秒，默认 prepare 后 120 秒 |
| `requestDigest` | `String` | 规范化非秘密请求的 SHA-256 十六进制指纹；只随 intent 返回，不是 commit 入参或写入授权依据 |

opaque `intentId` 只在当前 client 内绑定内存中的 typed 请求、过期时间、prepare 路线和冲突键；不得保存
密码、Cookie、challenge 图片或外部验证码三元组。`commitWrite` 只接收该 ID，原子取出 typed 请求后再执行，
因此重复点击最多一次进入 Core。过期、已消费、路线变化或同目标冲突均不得执行网络写入；`requestDigest`
不会由调用方回传，也不存在 bridge 侧摘要比对。外部进程改变 Session 修订时，由 Core 的 Session/CAS 边界
在最终发送前拒绝，bridge 将其映射为 `operation_conflict`。login 成功、logout、`authStatus`、策略保存后
重开 client 以及 dispose 都会清空旧 intent。写请求可能到达上游后出现 timeout/连接中断时返回
`outcome_unknown`，intent 仍视为已消费，Flutter 必须调用合同指定的读取方法核对，禁止自动重试。

`discardWriteIntent` 只接受当前 client 的 opaque intent ID，删除操作幂等且不执行网络请求。正式
确认页只有在 discard 成功后才能清除本地待确认状态；若 commit 已先开始，discard 不负责中断已进入
Core 的操作。

博雅签到 prepare 必须先由 Core 重读当前学期、目标课程、三态资格、时间窗和位置配置；确认摘要
必须包含脱敏课程名称、课程标识、签到或签退类型、有效时间窗以及位置来源。若已有同一课程和
签到类型的未过期 intent，第二次 prepare 返回 `operation_conflict`。commit 消费 intent 后再次
执行相同预检，并由 Core 在最终 POST 前复核当前 Session/CAS 状态；预检失败不得误报为结果不确定，只有最终写请求
可能已到达上游后仍无法得到确定结果时才返回 `outcome_unknown`。

课堂签到 prepare 必须调用 Core 只读 preflight，确认摘要逐项清理课程名、安排 ID、起止时间并显示
当前可签到状态；UI 将完整 `SigninPerformAction` 传给共享 Host/AppController，只有最末 Bridge request
构造才提取 `scheduleId`。commit 消费 intent 后由 Core 再 fresh 查询今日课程，要求唯一精确目标且
eligibility 为 `allowed` 后才可发送。确定业务拒绝保持 commit `success=false`，不显示成功且不触发
成功刷新；确定成功刷新今日签到一次，`outcome_unknown` 也只刷新一次并禁止自动重放。

图书馆预约 prepare 必须把完整 `LibbookReserveAction` 交给 bridge，并由 Core 依次 fresh 读取目标日期的
`Space/map` 时段与 `Space/seat` 座位，要求 `(areaId,seatId,day,segment,startTime,endTime)` 唯一精确匹配且
typed 资格为 `allowed`。commit 消费 intent 后执行同一 fresh 预检，最终 confirm 只发送一次。明确业务拒绝
保持 `success=false`；发送后 `outcome_unknown` 保留 Core 的稳定 code/kind/安全 message、不可重试且不得
重放。应用对确定成功和未知结果都刷新 `libbookBookings` 一次，刷新只用于核对，不能反向宣称写入成功。

图书馆取消 prepare 必须把完整 `LibbookCancelAction` 交给 bridge。action 的 `id/page/limit` 绑定预约记录
产生时的页；Bridge 规范化并校验三者后，由 Core fresh 读取同一页，要求 booking ID 唯一匹配且
`cancelEligibility=allowed` 才保存 intent。commit 消费 intent 后由 Core 再读取同一页复核，最终
`/v4/space/cancel` wire 正文严格只有 `{id}`，`page/limit` 不进入写请求；响应分页元数据缺失、畸形、非正
或别名冲突均安全拒绝。Core 仅对白名单 code/message 组合确认成功，并将成功、确定 false 与已知终态映射为
固定安全文案，raw message 不跨 facade/CLI/Bridge。只有最终请求已发送后仍无法判定才返回不可重试
`outcome_unknown`。成功或 unknown 后均只刷新同一
`libbookBookings(page,limit)` 页用于核对，禁止自动重放取消。
同页 authority 查询自身的失败也属于该边界：`/v4/member/seat` 非成功 envelope 的原始 message 不得进入
BridgeError，统一投影为 `upstreamChanged` 与固定安全文案。

阳光打卡 prepare 只接受当前 `YgdkOverview.items` 中 eligibility 为 `allowed` 的完整
`YgdkSubmitTarget {classifyId,itemId}`，不得把 primitive `itemId`、默认项目或展示名称兑换为写权限。
请求的 `startTime/endTime` 都是必填的精确 `yyyy-MM-dd HH:mm` 上海本地时间，必须同日且结束严格晚于开始；
`photo` 必填并在网络前执行 1..10 MiB、basename filename 与 `image/*` MIME 防注入校验。prepare 只执行
本地校验和 fresh classify/item authority，不上传照片，也不发送最终写请求。

commit 原子消费 intent，并只调用 Core expected-route 入口：本地校验、一次路线解析、intent 路线比较、
活跃 owner/session/credential generation、fresh classify/item、upload 与 final 都在同一 runtime 和代次内完成。
fresh target 不一致、路线或 generation 变化、上传失败均不得发送 final。upload 最多调用一次且不认证刷新、
不切换路线、不自动重试；final 同样只越过一次 non-idempotent 发送边界。final 已开始发送后出现 HTTP、认证、
跳转、transport、timeout、Cookie、JSON 或 envelope 歧义时只返回不可重试 `outcome_unknown`，不得依据 raw
message 推断成功或再次提交。

确定成功和 `outcome_unknown` 后，App 都只使用 commit 返回的原路线，各 best-effort 调用一次
`ygdkOverviewOnRoute(route)` 与 `ygdkRecordsOnRoute(route,page=1,size=20)`；两次读取彼此独立，不 Auto、
不 fallback，任一失败都不能触发写重放。冻结来源没有足以把某条记录与本次照片、时间和 target 唯一关联的
规则，因此 count、首条、近似时间、展示文案或旧 snapshot 都不能把 unknown 升级为 success，也不能标记
严格“已核对”。

教学评教 prepare 只接受读取结果中 `allowed` action 携带的完整 `EvaluationSubmitTarget`；Dart 与 Bridge
都要求 targets 在规范化后非空、有序、无重复，必填字符串非空，`bpdm=null` 与空串按同一 identity 处理。
完整课程 DTO、问卷、题目、答案策略和 authority 不进入请求或 intent 公开字段。Bridge prepare 调用 Core
fresh preflight，commit 消费 intent 后调用 expected-route 原子入口再次 fresh 读取；路线或 authority 漂移
均在最终请求前失败关闭。

Evaluation commit 的 `evaluationResult` 固定为
`{items:[{target,courseName,outcome,message}],success,outcomeUnknown}`，outcome 只允许
`success/failure/outcomeUnknown/unattempted`。逐课程保持输入顺序；确定 failure 可继续，首个 unknown 停止，
其后项目必须为 unattempted；只有全部 success 时批次 success。App 不信任 raw message，只显示固定安全文案。
确定结果、unknown 或 commit 抛错都至多沿 intent 原路线调用一次 `evaluationAllOnRoute`；回读只更新页面，
不得改变任何提交 outcome、自动重发或重新 Auto/fallback。

照片通过 `BridgePhoto {bytes,fileName,mimeType}` 一次传入；Debug 只记录字节数与 MIME 类型。
场馆 challenge 由 Core typed 流程内部完成，bridge 不公开图片、secret key、point JSON、token
或 verification。`evaluationSubmit` 的原始字符串 payload 不生成到 Dart。

Flutter domain/app 的场馆预约提交只接受读取结果产生的 `CgyyReserveAction` 与表单字段，不再开放站点、
日期、空间或时段的 primitive 覆盖入口。一至两个 action 必须全部为 `allowed`，具有正站点/空间/时段、
非空日期、`null` 或正空间组以及非负 raw ordinal，并且同站点、日期、空间和空间组，时段 ID 与 ordinal
各自唯一；两个 action 的 raw ordinal 必须相邻。AppController 和生产 BridgeBackend 共用该 fail-closed
校验；Bridge 只在最末 adapter 将已验证 action 投影为 FRB primitive 请求，Core 仍是最终权威。

场馆预约的 Bridge prepare 调用 Core fresh preflight，要求日期响应精确一致且目标唯一，随后只保存 Core
规范化的目标。commit 原子消费 intent 后，Core 再执行同一 fresh authority 复核；资格为 `denied`、
`unknown`、target 缺失或身份不一致时均在最终写请求前拒绝。验证码获取/校验最多重试三次且只发生在最终
提交之前；最终 reservation submit 使用单次 non-idempotent 发送边界，越过边界后无法确定结果时只返回
不可重试的 `outcome_unknown`，不得自动重放。确定成功只可附带
`{orderId,venueSiteId?,reservationDate?,orderStatus?}` 安全收据；验证码、完整订单、电话、主题、参与人、
活动正文、上游 raw message 和其它个人信息不得进入写结果或错误。

场馆取消 prepare 只接受读取结果产生的 `CgyyCancelAction`；App 要求 eligibility 为
`allowed`、canonical 正数 `orderId` 与 `cancelTarget.orderId` 严格一致，并只在最末 adapter 构造
`{orderId}`。Bridge prepare 与 commit 均由 Core fresh GET `/api/orders/{id}` 复核同 ID 资格与
上海时区的开始前四小时截止点。commit 在 Core 内只解析一次路线，仅当结果与 intent
的 `resolvedRoute` 一致时，才使用该同一 runtime 读详情并越过一次最终 POST 发送边界；路线变化在
网络写入前映射为 `operationConflict`。成功结果固定为 `success=true/场馆订单已取消`；
Core 若返回矛盾的 `success=false`，Bridge 失败关闭为 `upstreamChanged`，不得当作普通成功。

场馆取消确定成功或 `outcomeUnknown` 后，App 依次调用
`cgyyOrdersOnRoute(route,page=0,size=20)` 与 `cgyyOrderDetailOnRoute(route,id)`；两次回读都必须
使用 intent 原路线，不重新执行路线策略。证明只消费本次两个局部结果，两者各自必须唯一
匹配同 ID 且 `cancelledTarget.orderId` 一致；旧 snapshot、展示字段、单一列表或单一详情都不能标记
已核对。列表结果可在 generation 未变且路线一致时最佳努力刷新 UI，但 snapshot 绝不参与证明；
任一回读失败均只保持“未核对”，不重发取消。

场馆预约的本地表单门禁还要求联系电话、主题、活动内容和参与人文本非空，用途编号与参与人数为正；
这只约束产品 typed 请求，不改变 Core 上游协议。阳光打卡和场馆预约的 `request_digest` 只对非敏感形状做
规范化（结构 ID、文本存在/长度、照片字节数/MIME、布尔值），不写入或哈希返回电话、主题、参与人、
活动正文、地点、照片文件名和照片字节，避免敏感材料穿过 intent 投影；对应回归记录在
`docs/migration/source-parity.md`。

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

- Rust：每个映射的字段快照、错误映射、dispose、串行锁、panic 归约、intent 过期/重复、登录/注销/
  `authStatus`/重开失效、Core Session 冲突、路线失效、outcome unknown 和 typed 请求测试。
- Dart：生成 API schema 快照（包括场馆订单、场馆时段和博雅已选课程内部字段禁曝断言）、`evaluationAll` 待评派生、ID/可选字段、错误映射和
  `BridgeClient` isolate 重建测试；宿主通过 `BackendFactory` 创建新的 opaque
  backend 后，应用重新读取持久化路线与认证状态，不复用已 dispose 的 handle。
- FRB：`just flutter-codegen-check` 二次生成零漂移；生成目录禁止手改。
- 安全：Debug/Display、错误、intent 摘要和测试 fixture 均不得出现密码、Cookie、token、
  完整证件号、完整手机号、照片内容、challenge 或真实响应。
- 平台：五平台 native library 构建和 OHOS arm64 HAP 最终均调用同一合同版本。

P1 只有全部方法、DTO、写 intent、测试与生成绑定同时完成后才能勾选；只有合同文件或部分方法
不能标记 P1 完成。

## 9. 历史 P1 与当前实现证据（截至 2026-09-05）

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
  回归；Dart schema 快照覆盖全部公开读取 DTO 和十项写入口，应用层已有 dispose、后台恢复和
  代次丢弃的确定性测试，`just flutter-codegen-check` 报告零漂移。上述代码/合同门禁满足当时的
  无签名 P1；原生设备上的 isolate 重建、内存泄漏观测和真实跨平台生命周期仍留待后置设备验证。
- Phase 11I 提交已经闭合 Ygdk typed authority/request、Core expected-route 原子提交入口、
  owner/session/credential generation guard、caller-pinned overview/records 方法，以及 CLI JSON schema v9、
  Flutter Bridge contract v8 和相应生成类型。安全收据已严格收窄为 `{recordId}`，公开字段禁曝；完整
  Rust/CLI/Bridge/Dart/Flutter 门禁、FRB 零漂移、macOS 脱敏宿主 integration 与独立终审均已通过并提交为
  `d8484ad`。该阶段没有联网、上传照片或执行真实写入，也不构成签名、实体设备或正式发布证据。
- Phase 11J 当前工作树已升级到 CLI JSON schema v10、Flutter Bridge contract v9，并实现 Evaluation typed
  target、批量四态结果和 caller-pinned 回读；完整跨层门禁、FRB 二次零漂移、独立终审与阶段提交仍待完成，
  因此不能把当前工作树称为最终候选。本阶段不执行任何真实评教写入。
