# Flutter Bridge 合同

状态：P1 冻结中

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
`open`，不得复用旧 handle 或 intent。panic 由 FRB 捕获为 `internal_error`，不得把 panic
正文、backtrace 或参数回传 UI。

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
- `SpocAssignments {termCode,termName?,assignments}`；摘要字段为
  `{assignmentId,courseId,courseName,teacherName?,title,startTime?,dueTime?,score?,submissionStatus,submissionStatusText}`；
  详情在摘要字段后增加 `{contentPlainText?,submittedAt?}`。
- `JudgeAssignmentSummary {courseId,courseName,assignmentId,title,startTime?,dueTime?,maxScore?,myScore?,totalProblems,submittedCount,submissionStatus,submissionStatusText}`；
  `JudgeAssignmentKey {courseId,assignmentId}`；详情增加 `problems` 与 `contentPlainText?`；
  `JudgeProblem {name,score?,maxScore?,status,statusText}`。
- `SigninClass {courseId,courseName,classBeginTime,classEndTime,signStatus}`。
- `BykcUserProfile {id,employeeId?,realName?,studentNo?,collegeName?}`；
  `BykcCourse {id,courseName,coursePosition?,courseTeacher?,courseStartDate?,courseEndDate?,courseSelectStartDate?,courseSelectEndDate?,courseCancelEndDate?,courseMaxCount?,courseCurrentCount?,status,selected?}`；
  `BykcCoursePage {content,totalElements,totalPages,size,number}`。
- `BykcChosenCourse` 固定 facade 全部公开字段；`signConfig` 仅含四个时间字段与
  `signPoints {lat,lng,radius}`；附件只保留 facade 当前公开的名称/路径字段，不由 Dart
  解释为 URL。`BykcStatistics {totalValidCount?,categories}`，分类项为
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
- `CgyyVenueSite`、`CgyyTimeSlot`、`CgyySlotStatus`、`CgyySpaceAvailability`、
  `CgyyDayInfo`、`CgyyOrder`、`CgyyOrdersPage` 保持 facade 公共字段；用途结果必须为
  `{items,source}`，`source` 为 `upstream|staticFallback`；锁码只含 `{available}`。
- `EvaluationCoursesResponse {courses,progress}`；课程保持 facade 公开字段；进度为
  `{totalCourses,evaluatedCourses,pendingCourses}`。Dart 的待评列表必须由
  `courses.where((course) => !course.isEvaluated)` 派生，不存在 `evaluationPending` 方法。

枚举 wire 值固定为 Core serde 值；Dart 不以展示文案替代 wire 值。所有 ID 保持原 Core
类型，不把字符串 ID 自动转数字，不把可选字段默认成空字符串或零。

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
- Dart：生成 API schema 快照、`evaluationAll` 待评派生、ID/可选字段、错误映射和
  `BridgeClient` isolate 重建测试。
- FRB：`just flutter-codegen-check` 二次生成零漂移；生成目录禁止手改。
- 安全：Debug/Display、错误、intent 摘要和测试 fixture 均不得出现密码、Cookie、token、
  完整证件号、完整手机号、照片内容、challenge 或真实响应。
- 平台：五平台 native library 构建和 OHOS arm64 HAP 最终均调用同一合同版本。

P1 只有全部方法、DTO、写 intent、测试与生成绑定同时完成后才能勾选；只有合同文件或部分方法
不能标记 P1 完成。
