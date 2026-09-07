# UI/UX 重设计前来源与接线审查

日期：2026-09-08。范围：静态源码审查；不改生产代码、不读取凭据、不执行实时请求。本记录不是 Core-live、确定性测试或实际 UI 验收 PASS。

## 冻结来源与索引约定

本次 `git -C ubaa_old rev-parse HEAD` 与 `git -C examples/buaa-api rev-parse HEAD` 实际输出分别为 `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`、`efb7976bf513f38364b88aeb83d704586cff9b2a`，与 `references.md` 一致。冻结目录完整纯校验由主执行代理记录。

以下 `K` 指 `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/`，`T` 指 `ubaa_old/shared/src/commonTest/kotlin/cn/edu/ubaa/api/`，`R` 指 `examples/buaa-api/src/`。文件名是具体来源定位，不是新增协议。旧版每个领域同时查 `api/feature/<领域>Api.kt`、`api/local/Local<领域>Api.kt`、`model/dto/<领域>.kt`；Evaluation 对应 `api/feature/EvaluationService.kt`、`api/local/LocalEvaluationService.kt`、`model/evaluation/EvaluationModel.kt`。测试对应 `T/Local<领域>ApiBackendTest.kt`，Evaluation 对应 `LocalEvaluationServiceBackendTest.kt`；Grade 的缓存测试为 `GradeScoreCacheStoreTest.kt`，不能声称其提供 HTTP 协议测试。

公共认证/传输来源：`K/api/auth/AuthApi.kt`、`K/api/local/LocalConnectionAuth.kt`、`K/api/local/LocalWebVpnSupport.kt`、`T/LocalAuthServiceBackendTest.kt`、`T/LocalAuthSessionStoreTest.kt`、`T/LocalCookieStoreTest.kt`、`T/LocalWebVpnSupportTest.kt`；独立 Rust 来源 `R/api/sso/auth.rs`、`R/api/user/{auth,opt}.rs`、`R/request.rs`、`R/context.rs`、`R/store/{cookies,cred}.rs`、`R/crypto/{aes,rsa}.rs`、`R/error.rs`。领域不等价时，不得从这组公共文件推导业务 URL、参数或令牌。

## 每项操作的九列保持条件

以下每个操作均逐项应用 C1–C9，并与[现有来源对照](../migration/source-parity.md)中指定章节共同构成设计前约束；这只允许纯视觉、公开 DTO 的无损展示和已存在 typed 参数接线，不授权改协议。

| 条件 | 必须保持的事实 |
|---|---|
| C1 URL/service | 调用既有 facade/Bridge 方法；业务 CAS/bootstrap URL 与 service 采用引用章节，不在 Dart 拼 URL，不借用不等价来源。 |
| C2 重定向/最终地址 | 路线包装、跳数、最终地址与 SSO 识别留在 Core；页面跳转不是网络重定向，不能触发路线回退。 |
| C3 Cookie/Session | 保持路线与用户隔离、业务令牌仅内存、既有会话清理和 generation 失效；宿主不持有新增 Cookie/token。 |
| C4 方法/参数 | 仅传现有 typed 参数；值来自对应父列表或用户现有合法输入；分页基数、查询筛选与字段大小写不变，不增加预取或重复请求。 |
| C5 Header/编码 | 不改请求头、Origin/Referer 转换、表单/JSON/multipart 编码；UI 不构造上游正文。 |
| C6 加密 | 不修改或复制 AES/RSA/MD5/签名常量到 UI；无加密操作仍无加密。 |
| C7 DTO/解析 | 保留 null、空、未知状态与 typed eligibility；只用公开 DTO；不解析展示文本反推 ID/权限，不把默认 0 计数称作实时可用证明。 |
| C8 缓存/并发 | 保持 Core 缓存时效、单飞与顺序；UI 重排/旋转不新增请求，父选择变化清理子上下文，迟到结果不覆盖新查询。 |
| C9 错误/退出 | 空结果、认证失效、普通失败、stale 与未知结果分别展示；不改变错误 code 或 CLI 退出语义，不自动重发写入。 |

## 逐操作来源映射

当前 Bridge 操作依据 `crates/ubaa-flutter-bridge/src/api/read/methods.rs` 和 `api/client.rs`；公开 DTO 位于 `api/read/mod.rs`。下表每一行独立受 C1–C9 约束。

| 操作 | Kotlin 具体领域/函数来源 | Rust 示例来源与差异 | 既有对照章节 |
|---|---|---|---|
| 准备登录 | LocalConnectionAuth.kt；AuthApi.kt；model/dto/Auth.kt | api/sso/auth.rs、api/user/auth.rs；保留现有交互验证码不支持边界 | 准备/登录（UBAA2 不支持交互验证码） |
| 登录 | LocalConnectionAuth.kt；LocalAuthServiceBackendTest.kt | api/sso/auth.rs；两路线与加密差异沿既有决定 | 准备/登录（UBAA2 不支持交互验证码） |
| 认证状态/恢复 | LocalConnectionAuth.kt；LocalAuthSessionStoreTest.kt | store/cookies.rs、store/cred.rs；不是相同持久化格式 | 双路线加载/保存/退出 |
| 退出/清除本机账号 | LocalConnectionAuth.kt；AuthApi.kt | api/sso/auth.rs；不照搬示例存储格式 | 双路线加载/保存/退出 |
| 用户资料 | LocalConnectionAuth.kt::getUserInfo；model/dto/UserInfo.kt | api/user/opt.rs::get_state 只读 status，不是 userinfo | 用户资料 |
| 网关探测/路线设置 | LocalConnectionAuth.kt；LocalWebVpnSupport.kt | request.rs、context.rs；默认策略保存是本地能力 | 网关探测；CLI 与配置 |
| scheduleTerms | Schedule 三文件及 LocalScheduleApiBackendTest.kt | api/aas/{core,opt,data}.rs；示例 campusCode 正文不可借用 | 未改变的课表/考试证据 |
| scheduleWeeks | Schedule 三文件及 LocalScheduleApiBackendTest.kt | api/aas/{core,opt,data}.rs；示例 campusCode 正文不可借用 | 未改变的课表/考试证据 |
| scheduleWeek | Schedule 三文件及 LocalScheduleApiBackendTest.kt | api/aas/{core,opt,data}.rs；示例 campusCode 正文不可借用 | 未改变的课表/考试证据 |
| scheduleToday | Schedule 三文件及 LocalScheduleApiBackendTest.kt | api/aas/{core,opt,data}.rs；示例 campusCode 正文不可借用 | 未改变的课表/考试证据 |
| examArrangement（已安排/未安排） | Schedule 三文件及 LocalScheduleApiBackendTest.kt | api/aas/{core,opt,data}.rs；示例 campusCode 正文不可借用 | 未改变的课表/考试证据 |
| grades（已出/待出） | Grade 三文件；GradeScoreCacheStoreTest.kt | api/app/{core,opt,data}.rs 无等价成绩协议 | 未改变的成绩证据 |
| classroomSearch（校区/日期及本地楼层/节次筛选） | Classroom 三文件及 LocalClassroomApiBackendTest.kt | api/app、api/class 非此空教室协议 | 空教室会话同步；空教室查询 |
| signinToday（全部/待签/已签） | Signin 三文件及 LocalSigninApiBackendTest.kt | api/class/{core,opt,data}.rs；登录端点采用既有实时裁决，查询仍旧 GET | 课堂签到今日查询 |
| spocAssignments | Spoc 三文件；LocalSpocSupport.kt；LocalSpocApiBackendTest.kt | api/spoc/{core,opt,data}.rs；缺角色初始化且列表方式不同，不直接替换 | SPOC 认证；SPOC 列表；SPOC 详情 |
| spocAssignment | Spoc 三文件；LocalSpocSupport.kt；LocalSpocApiBackendTest.kt | api/spoc/{core,opt,data}.rs；缺角色初始化且列表方式不同，不直接替换 | SPOC 认证；SPOC 列表；SPOC 详情 |
| judgeAssignments | Judge 三文件及 LocalJudgeApiBackendTest.kt | api.rs 无 Judge 同一协议模块；九列无等价补充 | Judge 列表；Judge 详情；Judge 批量与缓存 |
| judgeAssignment | Judge 三文件及 LocalJudgeApiBackendTest.kt | api.rs 无 Judge 同一协议模块；九列无等价补充 | Judge 列表；Judge 详情；Judge 批量与缓存 |
| judgeAssignmentDetails | Judge 三文件及 LocalJudgeApiBackendTest.kt | api.rs 无 Judge 同一协议模块；九列无等价补充 | Judge 列表；Judge 详情；Judge 批量与缓存 |
| bykcProfile | Bykc 三文件；LocalBykcCrypto.kt；LocalBykcApiBackendTest.kt | api/boya/{core,opt,data}.rs 同业务交叉证据；不能替换旧本地加密 | 博雅课程只读查询 |
| bykcCourses | Bykc 三文件；LocalBykcCrypto.kt；LocalBykcApiBackendTest.kt | api/boya/{core,opt,data}.rs 同业务交叉证据；不能替换旧本地加密 | 博雅课程只读查询 |
| bykcCourseDetail | Bykc 三文件；LocalBykcCrypto.kt；LocalBykcApiBackendTest.kt | api/boya/{core,opt,data}.rs 同业务交叉证据；不能替换旧本地加密 | 博雅课程只读查询 |
| bykcChosenCourses | Bykc 三文件；LocalBykcCrypto.kt；LocalBykcApiBackendTest.kt | api/boya/{core,opt,data}.rs 同业务交叉证据；不能替换旧本地加密 | 博雅课程只读查询 |
| bykcStatistics | Bykc 三文件；LocalBykcCrypto.kt；LocalBykcApiBackendTest.kt | api/boya/{core,opt,data}.rs 同业务交叉证据；不能替换旧本地加密 | 博雅课程只读查询 |
| libbookLibraries | LibBook 三文件；LocalLibBookApiBackendTest.kt | api.rs 无 LibBook 同协议模块，九列 N/A | 图书馆座位只读查询；Phase 11 typed action eligibility 对照 |
| libbookAreas | LibBook 三文件；LocalLibBookApiBackendTest.kt | api.rs 无 LibBook 同协议模块，九列 N/A | 图书馆座位只读查询；Phase 11 typed action eligibility 对照 |
| libbookAreaDetail | LibBook 三文件；LocalLibBookApiBackendTest.kt | api.rs 无 LibBook 同协议模块，九列 N/A | 图书馆座位只读查询；Phase 11 typed action eligibility 对照 |
| libbookSeats | LibBook 三文件；LocalLibBookApiBackendTest.kt | api.rs 无 LibBook 同协议模块，九列 N/A | 图书馆座位只读查询；Phase 11 typed action eligibility 对照 |
| libbookBookings | LibBook 三文件；LocalLibBookApiBackendTest.kt | api.rs 无 LibBook 同协议模块，九列 N/A | 图书馆座位只读查询；Phase 11 typed action eligibility 对照 |
| ygdkOverview / ygdkOverviewOnRoute | Ygdk 三文件及 LocalYgdkApiBackendTest.kt | api.rs 无 Ygdk 同协议模块，九列 N/A | 阳光打卡只读查询；Phase 11I |
| ygdkRecords / ygdkRecordsOnRoute | Ygdk 三文件及 LocalYgdkApiBackendTest.kt | api.rs 无 Ygdk 同协议模块，九列 N/A | 阳光打卡只读查询；Phase 11I |
| cgyySites | Cgyy 三文件；LocalCgyySigner.kt；LocalCgyyApiBackendTest.kt | api.rs 无 venue-zhjs-server 同协议模块，九列 N/A | 场馆预约只读查询（同名逐操作行） |
| cgyyPurposeTypes | Cgyy 三文件；LocalCgyySigner.kt；LocalCgyyApiBackendTest.kt | api.rs 无 venue-zhjs-server 同协议模块，九列 N/A | 场馆预约只读查询（同名逐操作行） |
| cgyyDayInfo | Cgyy 三文件；LocalCgyySigner.kt；LocalCgyyApiBackendTest.kt | api.rs 无 venue-zhjs-server 同协议模块，九列 N/A | 场馆预约只读查询（同名逐操作行） |
| cgyyOrders / cgyyOrdersOnRoute | Cgyy 三文件；LocalCgyySigner.kt；LocalCgyyApiBackendTest.kt | api.rs 无 venue-zhjs-server 同协议模块，九列 N/A | 场馆预约只读查询（同名逐操作行） |
| cgyyOrderDetail / cgyyOrderDetailOnRoute | Cgyy 三文件；LocalCgyySigner.kt；LocalCgyyApiBackendTest.kt | api.rs 无 venue-zhjs-server 同协议模块，九列 N/A | 场馆预约只读查询（同名逐操作行） |
| cgyyLockCode | Cgyy 三文件；LocalCgyySigner.kt；LocalCgyyApiBackendTest.kt | api.rs 无 venue-zhjs-server 同协议模块，九列 N/A | 场馆预约只读查询（同名逐操作行） |
| evaluationAll / evaluationAllOnRoute（全部/待评） | Evaluation 三文件及 LocalEvaluationServiceBackendTest.kt | api/tes/{auth,opt,data}.rs；activation、并发和筛选以既有裁决为准 | Phase 11J Evaluation 提交逐操作九列：会话激活、tasks/questionnaires/courses authority |

独立 Rust 示例未提供某领域时，已以 `R/api.rs` 的导出目录和相关模块核对不存在同一协议；不把同名 App/Class 误认作空教室、成绩、图书馆或场馆协议。每个领域的局部查询参数、错误、字段、缓存详细值以引用的原九列为准，不能将本索引理解为已重新执行全部协议测试。

### 已有文档的精度问题

2026-09-08 已修正 `source-parity.md` 的“SPOC 详情”错置表：原 `assignment/index.jsp`、worker Cookie、两分钟缓存属于 Judge，仍由原“Judge 详情”记录。SPOC 节现按冻结 `LocalSpocApi.kt`、示例 `api/spoc/{opt,core,data}.rs` 和当前 Core `features/spoc/{detail,parser}.rs` 补齐必需详情 GET `queryKczyInfoByid?id` 与可选提交信息 GET `queryXsSubmitKczyInfo?kczyid` 两项九列。示例详情端点等价但 DTO/角色初始化不完整，不提供同一提交信息补充流程。历史误置说明保留，生产协议与代码未变；不得把文档修正称作实时验证通过。

## 图书馆父子选择器接线

| 步骤 | 已存在的 typed 来源 | 实施约束 |
|---|---|---|
| 日期与馆列表 | `libbookLibraries(day)` → `BridgeLibBookLibrary{id,name,freeNum,totalNum,storeys}` | 沿用 `FeatureQuery.day` 当前传递路径；显示馆名与计数，保存馆 ID，不能从“馆 ID”展示字段读回。 |
| 楼层 | `BridgeLibBookStorey{id,name,freeNum,totalNum}` | 直接保留父馆的 `storeys`；选择楼层不需新端点，可提供未选楼层的现有空筛选语义。 |
| 分区 | `libbookAreas(premisesId,storeyId,day)` → `BridgeLibBookArea{id,name,areaName,premisesId,storeyId,...}` | 值来自父选择；父馆/楼层/日期变化清空旧分区、时段、座位和 action，拒绝迟到结果跨父显示。 |
| 分区详情 | `libbookAreaDetail(areaId)` → `BridgeLibBookAreaDetail{id,name,availableDates,timeSlots}` | 显示可用日期；当前接口没有 day 参数，不能假装按日期查详情。 |
| 时段 | `BridgeLibBookTimeSlot{id,start,end,label}` | `segment=slot.id`，`startTime=slot.start`，`endTime=slot.end`；label 仅展示，不拼接/解析以生成 ID。 |
| 座位 | `libbookSeats(areaId,day,startTime,endTime)` → `BridgeLibBookSeat` | 该只读方法没有 segment 参数；App 为后续 typed action 保存 segment，但不新增到上游座位查询。只按 `reserveEligibility/reserveTarget` 开放预约。 |
| 我的预约 | `libbookBookings(page,limit)` → `BridgeLibBookBookingsPage` | 独立记录入口，保留 1 基页码、分页上下文与 `cancelEligibility/cancelTarget`；文字状态不作资格。 |

请求级复核：旧版 `LocalLibBookApi.kt:190` 起确认五项均 POST JSON。馆列表 `space/pcTopFor {day}`；分区 `space/pick {premisesIds,categoryIds:[],storeyIds:[],boutiqueIds:[],date}`，选定楼层才加入 `storeyIds`；详情 `Space/map {id}`；座位 `Space/seat {id,day,label_id:[],start_time,end_time,begdate:"",enddate:""}`；记录 `member/seat {type:"1",page,limit}`。其余八列严格沿用来源矩阵图书馆行；Rust 示例九列均无同协议补充。公开选择器不接触 Authorization、CAS 或 AES。

**必须阻塞的日期边界：**Core `features/libbook/parser.rs::parse_area_detail_for` 从 `date.list` 提取所有日期，但只从首项对象提取 `times/timeSlots`，否则使用顶层时段；公开 Bridge 没有日期→时段的关联。Core 写入预检内部 `parse_area_detail_for_day` 会对实际指定日期重新核对。因此可无协议变化接入现有明确时段，但不能把这组时段承诺为每一天的可预约时段，不能生成不存在的日期关联。若产品要支持完整跨日期时段选择，须单独补公开合同与来源失败测试，且当前合同要求 Bridge v9 保持不变，不能暗改 FRB DTO。可以先保留日期输入与明确的时段核对提示，不能以 Core 最终拒绝替代正确展示。

当前 App `packages/ubaa_app/lib/src/bridge/read/libbook.dart` 把馆楼层降为数量、详情时段降为字符串。建议在 `ubaa_domain` 增加展示层 typed 选择项/上下文，BridgeBackend 在映射当时保留现有公开 DTO 字段，UI 消费这些选择项；避免在共享 UI 引入 FRB 类型或从 `FeatureField` 反向解析。新增展示模型不改变 Bridge schema，但需要 App 映射、父子联动和迟到响应失败测试。

## 用户资料接线

`api/client.rs::BridgeUserProfile` 已白名单公开六个可空字段：`username`、`name`、`schoolId`、`email`、`phone`、`idCardTypeName`。`map_profile` 直接投影字段，不负责遮罩；“安全公开”不表示可写入日志或真实截图。禁止增加证件号码字段。来源为旧版 `LocalConnectionAuth.kt::getUserInfo` GET `/api/uc/userinfo` 与 `UserInfo.kt`；示例 `api/user/opt.rs::get_state` 访问 `/api/uc/status?selfTimestamp=...`，不等价，不能拿来补资料。

当前 `packages/ubaa_app/lib/src/bridge/common.dart::_userInfo` 已调用 `client.userInfo()`，但仅在 username 非空时返回 `UserSummary(username,displayName)`；`UserSummary.department` 没有此响应来源。可在个人页接入学号、邮箱、电话、证件类型名称的可空展示字段，敏感联系资料默认遮罩，空值显示“未提供”或隐藏；不得猜院系、专业、年级、头像、账号健康状态。不得把“没有 username”当作所有资料字段为空；若调整该回退，先为局部资料对象增加 App 测试，并保持认证状态由 authStatus 决定。

保持现有启动恢复/登录后的资料读取，打开个人页无需再增加一次请求；刷新若新增，须显式列为行为变更测试路线、错误、会话过期与迟到响应。资料状态需在退出、清除账号、账号切换时清除，不能以旧用户数据填充新用户。生产资料不能进入 golden、截图、调试日志；本轮运行展示只用合成资料。

## 其余明确边界

- Ygdk 完整重定向主机允许集合仍缺适用证据，只记录 gap，不猜白名单；不阻塞纯视觉设计。
- Cgyy 锁码只显示现有 `{available}`，无权把原始锁码接入 UI；用途固定回退需标明来源。
- Signin、LibBook、Bykc、Ygdk、Evaluation 的按钮继续消费 typed action/eligibility，不能照搬旧 Kotlin 的文案推断许可。
- 写入继续 prepare→确认→单次 commit→既定同路线只读核对；结果未知、逐项未执行不显示成功。此次未调用任何真实写入，也未新增其协议。
- 主题、导航、匿名统计与本地诊断没有新增上游业务来源，不以两份冻结来源虚构 HTTP 请求。诊断展示沿现有安全摘要，不开放 SPOC 内部诊断或原始数据。

以上接线建议是设计输入，待实现与验证；本轮不宣称功能接入完成。
