# 迁移状态

更新日期：2026-09-01

## 2026-09-01 当前 HEAD 双路线只读复核

- `just verify-live mode=direct` 在当前 HEAD 串行执行：认证、用户资料、课表、考试、成绩、空教室、SPOC、Judge、阳光打卡、图书馆、博雅、场馆和评教读取均按既有矩阵返回；`libbook/area_detail` 为 `PASS(count=1)`，SPOC/博雅详情因父列表为空为 `NOT_APPLICABLE`，Cgyy 用途明确为 `PASS source=static_fallback`。
- 同批次 Direct 的 `signin/today` 返回 `FAIL error=network_error`，命令以 exit code 5 结束；因此 Direct 本批次不能记为全通过，失败事实保留，不以历史成功替代。
- 随后串行执行 `just verify-live mode=webvpn`，所有必需只读操作通过（`signin/today`、`libbook/area_detail` 均 PASS），未调用任何真实写接口。该结果仍只证明 Core-live 协议矩阵，不替代六平台 Flutter→FRB→Core 实体设备 E2E。

## 2026-09-01 三类复杂写入 typed 准备边界

- AppController 现对阳光打卡、场馆预约和教学评教提供 typed prepare 入口：照片只复制到本次内存请求，场馆空间/时段只接受公开 ID，评教只接受读取结果中的待评课程稳定字段；均不接受 raw JSON，也不会在准备阶段提交网络写请求。
- BridgeBackend 将三类领域输入逐字段映射到既有 FRB 请求 DTO，新增 app/bridge 回归覆盖参数清理、非法输入拒绝和确认前零提交；教学评教详情补齐课程/任务/问卷/课程代码/模型公开标识，并提供单课程“准备提交评教”确认入口。
- 本轮没有真实账号写入、照片上传或验证码挑战；场馆预约的挑战交互、阳光打卡照片选择/权限、评教答题策略与批量核对仍待完成，P4/P5/P6 不能勾选。

## 2026-09-01 核对刷新映射回归

- AppController 的写入成功核对映射已通过回归：取消图书馆预约只刷新图书馆读取领域，不触发其它领域或任何额外写请求。
- 该测试与 UI 成功回调共同证明核对路径按操作隔离；未知结果仍不刷新、不重试，场馆预约、阳光打卡、教学评教提交仍未实现。

## 2026-09-01 最新本地/远端门禁复核

- 提交 `3e16d6f` 的远端合同 CI `33496873082` 已成功；Flutter native `33496873088` 的 Windows、macOS、Linux、Android APK
  和 iOS simulator 五个 job 也全部成功，Android job 最后完成。
- 该组仍只提供 debug 原生构建与上传产物，不包含 OHOS 签名 HAP、正式签名/公证、实体设备或真实 Flutter→FRB→Core E2E；
  本地 `just refs`、`just check-sensitive`、`just check`、`just flutter-codegen-check`、`just flutter-check` 通过，OHOS 双布局
  前置通过但签名处阻断。

## 2026-09-01 写入成功后只读核对钩子

- 统一确认页在 Core 返回确定成功后调用 `AppController.refreshAfterWrite`，按写操作映射到关联读取领域；刷新失败仅保留
  已提交提示，不会重试写请求。
- UI/app 回归覆盖成功回调一次调用；`outcome_unknown` 与 commit 异常仍立即消费 intent 并引导用户先刷新核对，其他真实
  写入授权规则不变。

## 2026-09-01 图书馆座位预约确认入口

- 图书馆座位 typed 读取详情现在保留公开分区/座位 ID、日期、时段、起止时间和可预约状态；查询控件新增可选公开时段编号，
  供预约摘要复用。
- 可预约座位显示“准备预约此座位”，AppController 仅接受上述完整参数并调用既有 typed `prepareLibbookReserve`；确认页二次
  确认后才单次提交，准备阶段不提交。bridge/app/widget 回归覆盖字段投影、参数清理和确认流程，本轮无真实账号写入。
- 图书馆取消、预约均已具备确定性确认 UI；场馆预约、阳光打卡、教学评教三项提交仍待完成，P4/P5/P6 仍未完成。

## 2026-09-01 博雅签到/签退确认入口

- 博雅课程详情在存在公开正整数课程 ID 时提供“准备博雅签到/准备博雅签退”；AppController 只接受冻结合同的
  `signType` 1/2，通过既有 typed `prepareBykcSignCourse` 传入课程编号，位置不在 UI 伪造。
- 确认页在二次确认后才单次提交 intent；位置/时间窗等业务条件由 Core prepare 判定，失败不会发出提交请求；widget/app
  回归覆盖 signType 校验、取消确认和准备阶段零提交。本轮无真实账号写入，其他四项写操作仍待完成。

## 2026-09-01 可逆取消确认 UI

- 图书馆预约记录与场馆订单详情的公开 `预约 ID`/`订单编号` 现在提供“准备取消预约/准备取消订单”按钮；AppController
  通过 `CancellationWriteBackend` 做领域和编号校验，再调用既有 typed prepare。
- 确认页仍只在二次确认后单次提交 `intentId`，取消准备阶段不发写请求，结果不确定时提示刷新核对且不自动重试；app/widget
  回归覆盖目标编号清理、非法场馆编号拒绝和确认后提交。本轮无真实账号写入，预约/提交类其它写操作仍待完成。

## 2026-09-01 课堂签到确认 UI

- 签到只读详情现在投影冻结 DTO 已证明的公开 `课程 ID`；共享详情页在该字段非空时提供“准备签到”按钮。
- AppController 通过 `SigninWriteBackend` 调用既有 typed `signin_perform` prepare，确认页仍只在用户二次确认后
  单次提交 `intentId`，提交前不发写请求，结果不确定时提示刷新核对且不自动重试。
- app/widget/bridge 回归已覆盖课程编号清理、准备不提交和确认后提交；本轮无真实账号写入，位置/挑战条件仍由 Core
  合同判定，其他七项写操作及 P4/P5/P6 仍未完成。

## 2026-09-01 博雅选课/退选确认 UI

- 共享详情页在存在白名单 `课程 ID` 时提供“准备选课/准备退选”按钮；AppController 通过封闭
  `BykcWriteBackend` 只接受正整数课程 ID，调用既有 typed prepare 并展示 `WriteIntent` 确认页。
- 确认页只在用户再次确认后调用一次性 `commitWrite(intentId)`；提交期间锁定操作，结果不确定时提示先刷新核对，
  不自动重试。widget/app 回归覆盖准备不提交、确认后提交和非法操作拒绝。
- 本轮没有执行真实账号写入；博雅签到及其它八项写操作仍只有 bridge/状态机确定性门禁，P4/P5/P6 仍未完成。

## 2026-09-01 读取详情公开标识选择器

- 共享查询控件现在从当前只读详情白名单提供公开 ID 选择器，覆盖博雅课程、图书馆馆区/分区、场馆站点/订单、
  SPOC 作业和 Judge 课程/作业；仍保留手动输入并只生成已有 typed `FeatureQuery`。
- SPOC 列表补齐课程编号后，作业详情可直接从当前列表选择作业编号；widget 回归覆盖选择器到查询参数的传递。
- 选择器只读取当前页面数据，不新增上游请求、URL 或写操作；P3 的服务端分页核对、完整状态、golden/integration
  和真实 Flutter App E2E 仍缺证据。

## 2026-09-01 SPOC 课程标识投影补齐

- SPOC 作业列表的共享详情白名单补充 `课程编号` 字段，与既有 typed `spocAssignment(assignmentId)`
  详情查询所需的公开标识保持一致；未暴露 Cookie、令牌或原始载荷。
- BridgeBackend 脱敏回归测试验证课程编号投影；Flutter 全量检查通过，未新增请求或写操作。
- P3 仍未完成：列表选择器、完整状态、服务端分页核对、golden/integration 和真实 Flutter App E2E
  仍缺证据。

## 2026-09-01 查询失败重试状态保持

- 共享详情页现在按功能保存最近一次 `FeatureQuery`；查询后的失败/过期数据点击“重试”会再次调用同一
  typed 查询，保留学期、日期、筛选、分页和公开 ID，不会静默退回首页摘要查询。
- 新增 widget 回归覆盖楼层筛选在失败后重试仍被复用；该修正只影响本地 UI 状态，不新增上游参数，也不触发写操作。
- P3 仍未完成：逐领域完整状态、服务端分页核对、golden/integration 和真实 Flutter App E2E 仍缺证据。

## 2026-09-01 五平台 native/合同 CI 复核

- 提交 `e2fdd5a` 的合同 CI run `33490877831` 已成功：`contract-gates`、macOS Rust 和 Windows Rust
  三个 job 全部通过。
- 同提交触发的 Flutter native run `33490877817` 已成功：Windows、macOS、Linux、Android APK 与
  iOS simulator 五个 job 全部构建并上传 debug 产物。该证据仍不包含 OHOS HAP、正式签名、公证、实体机
  或真实 Flutter→FRB→Core 读取/写入 E2E。

## 2026-09-01 Android Release AAB 终检复核

- `just flutter-build platform=android-appbundle mode=release` 的 Gradle `bundleRelease` 成功，生成本地
  未签名 AAB；Flutter 随后的 `apkanalyzer files list` 因 SDK `cmdline-tools/latest` 指向 Homebrew
  symlink，无法定位 `build-tools`，按门禁返回失败。
- 使用临时只读 SDK overlay（build-tools 指向现有 SDK）复核 AAB，确认 `arm64-v8a`、`armeabi-v7a`
  和 `x86_64` 均包含 `libflutter.so.sym` 与 `libubaa_flutter_bridge.so.sym`；这只证明产物内容，不能
  将 Flutter release gate、签名、安装、实体机或商店发布标记为通过。未改 SDK、未签名、未上传。

## 2026-09-01 课堂签到状态本地派生视图

- `FeatureQueryView` 新增 `signinPending`/`signinCompleted`；BridgeBackend 两者均只调用已有
  `signinToday`，按冻结 `SigninClass.signStatus` 的 0/1 语义在本地筛选并保留 Core 实际路线。
- 高级功能查询控件提供“全部课程/未签到/已签到”下拉视图，app/widget 回归覆盖筛选结果和参数传递，
  未触发课堂签到写请求。
- P3/P4 仍未完成：签到课程选择、写入确认/核对、完整页面状态、golden/integration 和真实 Flutter
  App E2E 仍缺证据。

## 2026-09-01 Judge 批量详情读取增量

- `FeatureQueryView.judgeBatchDetails` 与 `JudgeAssignmentQueryKey` 接入共享查询模型；UI 使用每行
  `课程编号/作业编号` 的公开编号格式，解析后调用已有 `judgeAssignmentDetails(keys)` typed facade。
- BridgeBackend 拒绝空键列表，按 Core 返回顺序映射作业头、题目状态/分数和纯文本白名单；不新增上游
  请求或协议字段。app 回归覆盖批量键、路线和题目字段，widget 回归覆盖多行键解析。
- P3 仍未完成：列表选择器与服务端分页、全部页面状态、golden/integration、真实 Flutter App E2E
  以及 P4 写入表单和结果核对仍缺证据。

## 2026-09-01 OHOS API26/Command Line Tools 构建复核

- 用户更新后的 Command Line Tools 与 DevEco Studio 均报告 `26.0.0.821`、Hvigor `6.26.4`、
  ohpm `26.0.0.630`、Node `24.14.1` 和 OpenHarmony SDK API `26`；锁定 fork、native
  SDK/clang/sysroot、Rust `aarch64-unknown-linux-ohos`、hdc、OHOS `analyze` 与 widget
  测试均通过。
- 工程级 `compatibleSdkVersion`/`targetSdkVersion` 已使用 API26 的 `"26.0.0"` 形式，
  hvigor 与工程 `modelVersion` 已升至 `6.0.0`。门禁脚本支持 DevEco Studio 的
  `tools/...` 和 Command Line Tools 的 `tool/...` 两种布局，并将匹配的 hvigor、ohpm、Node
  固定到构建 `PATH`。
- 默认 Studio 路径和 `UBAA_DEVECO_HOME=/Users/moorefoss/Code/bin/command-line-tools`
  路径分别执行 `just ohos-check mode=debug`，均通过工具链、Dart、native 前置并进入 HAP
  assemble，随后在调试签名配置处停止：未打开 DevEco Signing Configs、未自动签名、未连接
  设备，也没有验收 HAP 或 FRB hello 证据。
- 这不是工具链缺失；签名材料或自动签名仍需项目所有者单独授权。P0/P6 继续未完成，旧版
  DevEco/API21 的失败记录仅作为历史证据，不再代表当前机器状态。

## 2026-09-01 希冀过期作业筛选

- 希冀作业列表控件现提供“包含已过期作业”本地开关，按冻结 `judgeAssignments(includeExpired)`
  的既有参数传递，不新增上游字段或请求；详情视图不显示该开关。
- widget 回归覆盖开关到 typed `FeatureQuery.includeExpired` 的传递，未触发任何写操作。
- P3 仍未完成：完整作业状态/分页、golden/integration、真实 Flutter App E2E 及写入表单仍缺证据。

## 2026-09-01 成绩状态本地派生视图

- 普通功能页新增“全部成绩/已出成绩/待出成绩”封闭视图；BridgeBackend 三种视图均调用同一
  `grades(term)`，仅依据冻结 DTO 的 `score` 非空与否在本地投影，不引入成绩状态接口或
  分数阈值猜测。
- 学期参数和白名单字段保持既有 typed 映射，widget 回归覆盖已出成绩视图的参数传递，未触发
  任何写操作。
- P3 仍未完成：成绩更细的服务端筛选/分页、完整状态核对、golden/integration、真实 Flutter
  App E2E 和其他领域细粒度筛选仍缺证据。

## 2026-09-01 空教室楼层与节次本地筛选

- `FeatureQuery` 新增非敏感 `floorId`/`section` 字段；页面同时提交日期、校区和这两个本地
  筛选值。`BridgeBackend` 仍只调用冻结的 `classroomSearch(campus,date)`，不会把新字段拼入
  URL 或改变上游请求。
- 楼层按白名单 `floorId` 或分组楼层名精确匹配；节次按冻结 `kxsds`/`availableSections`
  的逗号分隔令牌精确匹配，避免第 3 节误命中第 13 节。widget 回归覆盖控件参数传递，并保留
  首次缺字段的编译失败证据后通过。
- P3 仍未完成：服务端筛选/分页、所有领域完整状态、golden/integration、真实 Flutter App
  E2E 及写入页面仍缺证据。

## 2026-09-01 考试安排本地派生视图

- 普通功能页新增“全部考试/已安排/未安排”封闭视图；BridgeBackend 三种视图均调用同一
  `examArrangement(term)`，仅在本地从 `arranged`/`notArranged` 投影白名单详情，不猜测新接口。
- 学期参数仍可选并沿用 Core 当前学期选择；widget 回归覆盖已安排视图的 typed 传递，未触发
  任何写操作。
- P3 仍未完成：成绩/空教室/签到等领域的细粒度筛选、完整状态、golden/integration、真实
  Flutter App E2E 和服务端核对尚缺证据。

## 2026-09-01 评教待评本地派生视图

- 高级功能页新增“全部课程/待评课程”封闭视图；`BridgeBackend` 两种视图都只调用一次
  `evaluationAll`，待评列表在本地按 `isEvaluated=false` 派生，未新增或伪造
  `evaluation_pending` facade 方法。
- 查询控件和 widget 测试覆盖待评视图 typed 传递；课程状态和进度继续来自同一份 Core 结果，
  不触发评教提交写操作。
- P3/P4 仍未完成：评教题目选择/批量提交确认、结果核对、完整页面状态、golden/integration
  和六平台真实 App E2E 尚缺证据。

## 2026-09-01 课表学期与周次读取增量

- `FeatureQueryView` 增加 `scheduleToday`、`scheduleTerms`、`scheduleWeeks` 和 `scheduleWeek`；
  BridgeBackend 直接调用对应 typed facade，映射学期选择状态、周次日期和周课表课程，不构造
  上游参数或会话材料。原有 `summary` 查询兼容今日/指定周行为。
- 课表控件新增今日/学期列表/周次列表/周课表下拉视图；周次与周课表要求学期编码，周课表还
  要求正周次，widget 测试覆盖学期列表 typed 传递。
- 本轮只读，不触发任何写操作；P3 仍缺全页面状态、golden/integration、真实 App E2E 和
  其他领域的逐项服务端核对。

## 2026-09-01 博雅课程详情读取增量

- `FeatureQueryView` 增加 `bykcDetail`；列表现在展示可再次查询的课程 ID，详情视图将用户选择的
  正整数 ID 传给已有 `bykcCourseDetail` typed facade，并映射课程、教师、地点、时间、容量、
  状态与已选标记，不接触加密正文或业务令牌。
- 普通功能页新增“课程列表/课程详情”控件；列表继续使用 Core 的 1-based 服务端分页，详情输入
  在 UI 与 bridge 两层拒绝非正整数。新增 widget 测试先观察缺失 enum 的编译失败，再验证课程 ID
  的 typed 传递通过。
- 本轮只读，不触发选课、退选或签到；P3/P4 仍未完成，已选课程/统计详情、写入表单、结果核对、
  golden/integration 和六平台真实 App E2E 仍缺证据。

## 2026-09-01 博雅已选课程与修读统计读取增量

- `FeatureQueryView` 继续增加 `bykcProfile`、`bykcChosenCourses` 和 `bykcStatistics`；
  `BridgeBackend` 直接调用对应 typed facade，展示个人资料、已选课程考勤/成绩状态及分类达标
  统计，课程附件路径等潜在 URL 不进入 `FeatureDetail`。
- 博雅控件将课程列表、详情、已选课程、修读统计和个人资料统一置于封闭下拉视图；本轮没有新增
  未经 Core 证明的参数或接口，也不触发选课、退选、签到。
- 该增量仍仅覆盖只读映射；P3 的全页面 loading/empty/stale、golden/integration、服务端分页
  核对和六平台真实 App E2E 尚未闭合。

## 2026-09-01 SPOC/Judge 作业详情读取增量

- `FeatureQueryView` 增加 `spocDetail` 与 `judgeDetail`；`BridgeBackend` 分别以
  `assignmentId`、`courseId + assignmentId` 调用已有 typed facade 详情方法，并在缺少标识时
  返回稳定的 `invalid_input`，不在 Dart 拼接 URL、JSON 或会话材料。
- 高级功能页新增“作业列表/作业详情”控件；Judge 详情展示作业头与题目状态/分数，SPOC/Judge
  内容仅映射白名单纯文本字段，不暴露原始 HTML、链接、Cookie 或业务令牌；新增 widget 测试
  覆盖 SPOC 作业编号的 typed 传递。
- 本轮只读，不触发提交或其他写操作；P3 仍未完成，服务端分页/详情逐项核对、golden/
  integration、完整页面状态和六平台真实 App E2E 仍缺证据。

## 2026-09-01 场馆预约只读详情增量

- `FeatureQueryView` 现支持 Cgyy 用途类型、日期空间、订单列表、订单详情和门锁状态；
  `BridgeBackend` 通过已有 typed facade 方法完成映射，订单展示主动省略手机号、参与人和交易号，
  门锁只展示 `available`。
- 高级功能页新增站点/用途/日期空间/订单/门锁视图控件；用途结果明确显示“上游”或“本地冻结回退”，
  不把静态回退伪称上游成功；widget 测试覆盖站点 ID 与日期的 typed 传递。
- 该增量不触发预约、取消或锁码写操作；P3/P4 仍未完成，真实双路线 App E2E、权限/挑战、
  结果核对和完整页面状态尚缺证据。

## 2026-09-01 阳光打卡记录读取增量

- `FeatureQueryView` 增加 `ygdkRecords`，`BridgeBackend` 以 typed 页码/数量调用已有
  `ygdkRecords` facade，并仅把记录编号、时间、地点、公开状态和图片数量映射为白名单详情；
  不把图片地址或业务令牌交给 UI。
- 高级功能页新增“概览/记录列表”分页控件及 widget 回归测试；该增量只读，不触发阳光打卡提交。
- P3 仍未完成：其余领域详情、全部页面状态、golden/integration、服务端分页核对和六平台真实
  App E2E 仍缺少证据。

## 2026-09-01 图书馆读取详情闭环增量

- 共享 `FeatureQuery` 新增封闭的 `FeatureQueryView` 及图书馆公开 ID/时段字段；BridgeBackend
  现在按 typed 视图调用 `libbookLibraries`、`libbookAreas`、`libbookAreaDetail`、
  `libbookSeats` 和 `libbookBookings`，不在 Dart 拼接 URL、JSON 或会话材料。
- 图书馆详情控件已支持馆区、分区详情、座位和预约记录读取；结果继续映射为脱敏
  `FeatureDetail`，新增 widget 测试覆盖馆区 ID 与楼层 ID 的提交。该增量只读，不执行预约或取消。
- 本轮仍不能将 P3 标记完成：领域下拉选择、服务端分页、逐项详情/写入核对、golden/integration
  与六平台真实 App E2E 尚未闭合；`libbook_area_detail` 的真实双路线证据仍按营业窗口门禁执行。

## 2026-09-01 读取实际路线投影

- `FeatureResult`、`FeatureSnapshot` 和 `BridgeBackend` 现在保留 Core 返回的
  `resolved_route`；共享卡片与详情页显示“实际路线”，不会把配置策略当作请求结果。
- 新增 app/widget 回归测试，并通过固定 Flutter SDK 的聚焦测试；刷新失败进入 `stale` 时继续
  保留上次成功路线。该增量不发起网络写入，也不改变 Core 协议。
- 应用层新增受限 `RouteSettingsBackend` 投影；固定路线切换后若目标路线没有认证槽位，立即
  清除用户和功能快照并回到登录页，生产 bridge 仍由 Core 负责原子保存、重开和 intent 失效。
- 启动时会先恢复 Core 持久化的 `defaultPolicy` 再检查认证状态，避免设置页显示错误的默认路线。
- AppController 现在同步暴露不含 Session 内容的 `activeRoutes`，共享“我的”页展示已认证路线，
  与各功能结果的“实际路线”字段分开。
- `AppController.rebuildBackend()` 已增加显式 isolate/宿主生命周期重建路径：通过注入的
  `BackendFactory` 只创建全新 backend，成功后释放旧实例、清空旧投影并重新读取路线/认证状态；
  无工厂、并发重建和登录中均安全拒绝，新增 app 回归测试覆盖旧实例释放与 WebVPN 槽位恢复。
- 官方 Flutter 与 OHOS 宿主已监听后台→前台恢复，在恢复时调用该入口；测试注入的 fake backend
  不提供工厂，因此不会被生命周期回调替换。
- 修正只读合同中遗留的 `evaluation_pending` 名称：CLI 的 `pending` 继续由同一次
  `evaluation_all` 结果按 `is_evaluated=false` 本地派生，facade/bridge 只保留 `evaluation_all`。
- 共享“我的”页面现区分“退出登录”和经二次确认的“退出并清除本机账号”；app/widget 测试
  覆盖取消确认与确认回调，后者调用 `logout(clearSavedCredential: true)`。

## 2026-09-01 最新 CI 终态

- 远端 CI run `33468279841`（提交 `530a38e`）已完成且结论为 success；`contract-gates`、
  macOS Rust、Windows Rust 三个 job 的 refs、敏感扫描、全 Rust 测试/构建/文档和严格 lint
  均通过。
- 该 run 不包含 OHOS API26/DevEco、正式签名、实体设备或 Flutter Release；这些门禁仍按
  `goal.md` 保持未完成。

## 2026-09-01 空结果刷新状态修复

- 提交 `a17d398` 为 `FeatureSnapshot` 增加显式摘要/详情清理语义；Core 明确返回空结果时，
  app 现在会清除上次成功内容并进入 `empty`，刷新失败仍保留内容并进入 `stale`。
- 新增 app 回归测试覆盖该边界；`flutter-check`、`check-sensitive` 和完整 `just check` 均通过。

## 2026-09-01 a17d398 远端构建终态

- CI run `33469682792` 已成功，contract-gates、macOS Rust 和 Windows Rust 全部通过。
- Flutter 原生 debug run `33469682830` 已成功，Linux、Windows、macOS、iOS simulator 和
  Android APK 五个 job 均构建并上传 debug 产物；不包含 OHOS API26/HAP、正式签名或实体设备。

## 2026-09-01 Flutter 六平台 P0 基线

已按新的 `goal.md` 开始 P0。开始时工作树包含用户已有的 Flutter/OHOS 探索骨架、
共享 Dart package、版本矩阵与 ADR，均先按未验收输入保留。冻结引用验证通过：
`ubaa_old @ 6e75e120a26b0eefb3ab4a6f8251d1230db4a62e`、
`examples/buaa-api @ efb7976bf513f38364b88aeb83d704586cff9b2a`。

本轮基线事实：

- `just check` 完整通过；首次 `just check-sensitive` 被共享 package 的可再生 Dart
  二进制测试缓存误报阻断，未发现源码秘密。缓存移到系统临时目录并增加 package 级
  `.dart_tool`/`build`/`coverage` 忽略规则后，敏感扫描通过（327 个仓库文件）。
- 官方 Flutter `3.41.9` 固定在提交
  `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`，OHOS fork
  `3.41.10-ohos-1.0.1` 固定在提交
  `adaf911c35c9136a7d18fc424d714c9ec7724e60`；两者均为 Dart `3.11.5`。
- 官方 SDK 下 `ubaa_domain`、`ubaa_platform`、`ubaa_app` 与官方宿主的 analyze/test
  通过；`ubaa_ui` analyze 通过但初始没有测试，已作为 P0 缺口补最小 widget 测试后复验。
- 本机 DevEco Command Line Tools 为 `6.0.1.251`、OpenHarmony API 21，不能满足
  合同锁定的 CLI/API 26；当前只作为失败边界证据，未将 API 18/21 冒充发布基线。
- 当前探索 UI 仍含 Demo backend、摘要卡片和占位详情，不是产品验收结果；P1 至 P4
  必须由 FRB production backend、完整 DTO/页面和一次性写确认流程替换。
- FRB Dart/Rust/runtime/codegen 已精确锁定 `2.13.0`。新增
  `ubaa-flutter-bridge` 的 `cdylib`/`staticlib` 与 Cargokit binding package；生成 API
  目前只有固定非敏感 `bridge_hello`，不会发起业务网络请求。
  `cargo test --locked -p ubaa-flutter-bridge`、严格 Clippy、
  `just flutter-codegen-check` 的二次生成零漂移，以及全部共享 package/官方宿主的
  `just flutter-check` 均通过。
- 官方五平台宿主已完成本机可验证的三类实际链接：macOS arm64 App 启动并越过
  `RustLib.init`/hello 断言；iOS simulator 产出 x86_64+arm64 framework；Android
  debug APK 同时包含 armeabi-v7a、arm64-v8a、x86_64 的
  `libubaa_flutter_bridge.so`。这些只证明 P0 FFI 链路，不证明登录或任何业务功能。
- Android 首次构建被本机 JDK `25.0.3` 与 Gradle 组合阻断；切换到固定用户级
  OpenJDK `17.0.19` 后 APK 构建通过。Android SDK 已补齐 API29/API35/API36、
  NDK、CMake、Ninja 与已接受许可；官方 `flutter doctor` 的 Android/Xcode/
  CocoaPods 必需项通过。
- OHOS Rust target `aarch64-unknown-linux-ohos` 已安装。`just ohos-check mode=debug`
  仍按预期只在 DevEco `6.0.1.251` 与 API21 两个硬门槛失败。锁定 fork 已生成
  OHOS runner，OHOS app 的 pub get/analyze/widget test 通过，并接入同一 FRB Dart API
  与 arm64 Cargokit HAR；但因工具链预检失败，尚无 HAP/FRB 设备 hello 证据，P0
  不得标记完成。华为当前 API26/DevEco 26 下载入口要求账号登录，本轮未提交账号信息
  或下载受限工具包。
- 由 FRB 生成的 FFI 编解码模块包含必要 `unsafe` 与机械转换；bridge crate 仍默认
  `unsafe_code=deny`，仅对私有生成模块使用局部 allow。生成文件不手改，业务 API
  继续受严格 Clippy 与零漂移门禁约束。
- GitHub Actions 原生 debug 矩阵已在提交 `c94dbcd` 的 run `33450597586` 完整通过：
  Windows、Linux、macOS、iOS simulator、Android APK 五个 job 均在对应原生 runner
  构建并上传 `ubaa-<platform>-debug-33450597586` 产物。对应 CI run `33450597476` 的
  `contract-gates`、macOS Rust、Windows Rust 三个 job 同样全部通过。
- 首轮远端证据依次暴露并关闭了真实跨平台缺口：浅克隆缺少 Flutter tag、Windows 路径
  形式、CRLF 导致的 rustfmt 差异、Windows 本地状态门禁和 plugin junction 下 Cargokit
  父目录解析。最终 Windows CMake 从 app `CMAKE_SOURCE_DIR` 生成绝对 Rust manifest
  目录，未修改协议、FFI schema、冻结目录或任何真实账号数据。
- run `33450597586` 的五份未过期产物大小分别为 Android APK 69,375,026 字节、iOS
  simulator 50,530,714 字节、Windows 33,378,901 字节、macOS 108,101,612 字节、Linux
  54,378,146 字节。它们是无签名 debug 构建证据，不是 P6 正式发布产物。

本节仅记录确定性和工具链事实；未执行任何真实账号写操作，也未读取、输出或暂存
`.env.local`、会话、Cookie、token、验证码图片或真实响应。

## 2026-09-01 Flutter P1 bridge 合同

- 新增 `docs/contracts/flutter-bridge.md`，固定合同版本、opaque client 生命周期、typed
  `BridgeError`、路线决策、认证资料白名单、全部读取方法/DTO 和十类 typed 写 intent。
- `evaluationPending` 明确不作为 bridge 方法；待评课程只由 `evaluationAll` 中
  `isEvaluated=false` 派生。Cgyy 用途通过安全来源 DTO 区分 upstream 与 static fallback。
- bridge 不生成诊断方法、原始 Evaluation payload、Cookie/token、场馆 challenge 材料或
  任意 JSON 写入口。协议九列继续引用本文件已有逐领域 parity，本次合同没有修改生产代码或
  访问真实账号。

## 2026-09-01 Flutter P3 查询入口与页面状态推进

- `FeatureQuery` 固定 term/date/campus/floorId/section/week/page/size 八类非敏感查询参数；`FeatureQueryBackend` 作为
  可选能力保持旧 fake backend 兼容，`AppController.refreshFeatureQuery` 不支持时返回稳定
  `unsupported`，不会在 Dart 端拼接 URL 或伪造查询成功。
- `BridgeBackend` 的课表学期/周次、考试/成绩学期和空教室日期/校区参数已 typed 传递到 Core；空教室楼层/节次仅在白名单结果上本地过滤；
  博雅列表的 1-based page/size 也经过 bridge 边界收敛。官方 Flutter 与 OHOS 宿主均把详情页查询回调接到同一
  协调器。
- 详情页新增课表/考试/成绩学期编码（课表可选周次）、空教室日期/校区及博雅 1-based 页码/每页数量控件，非法日期、周次或分页显示
  可行动中文提示；widget 与 app 测试分别证明控件提交和协调器参数不变形。其余领域筛选、
  真正服务端分页、golden/
  integration 以及写入页面仍未完成，P3/P4 不能勾选。

## 2026-09-01 Flutter P1 panic 归约补强

- bridge 对 `BridgeClient` 的 open、生命周期、认证、路线设置、读取执行和全部 typed 写意图
  入口统一包裹 panic 捕获；panic 只映射为固定 `internal_error`/`bridge operation failed
  internally`，不把 panic payload 或上游正文返回给 Dart。
- 新增 panic payload 不泄露测试，并复跑 `cargo test --locked -p ubaa_flutter_bridge --lib`、
  `just check-sensitive`、`just check` 和 `just flutter-codegen-check`；生成 Dart API 仍零漂移。
- 该证据覆盖 Rust unwind 边界与 generated API 映射；真实 Dart isolate 重建、内存泄漏和六平台
  生命周期/设备测试仍需 P1/P5/P6 环境，不能据此勾选阶段。

## 2026-09-01 Flutter P4 写入协调入口推进

- `WriteFlowController.prepare` 现在接收一次 typed prepare 回调，在确认前台意图建立期间只更新
  状态，不触发 commit；已有意图、提交中或已销毁状态均安全拒绝。prepare 失败统一归约为
  `UiError`，未知异常不向 UI 泄露原文。
- `BridgeBackend` 的十项 typed prepare 均通过统一错误映射进入 `BackendException`，照片仍只以
  内存字节传递；现有 `WriteConfirmationView` 可直接消费这些意图。确定性测试覆盖 prepare
  不提交网络、失败映射和一次性 commit。
- 各领域选择器、权限/挑战交互、读后核对、六平台 integration 与真实写入仍未完成；本轮没有
  触发任何真实账号写操作，P4 不能勾选。

## 2026-09-01 Flutter P6 发布 Runbook

- 新增 `docs/runbooks/flutter-release.md` 并在 `docs/index.md` 建立入口，固定发布前门禁、六平台
  产物/签名隔离、设备与 Direct/WebVPN smoke、写入授权和回滚留档顺序。
- Runbook 明确签名私钥、商店账号和真实写入必须逐项授权；当前仅允许无签名开发构建与确定性
  测试。OHOS DevEco/API26、正式签名、实体设备、安全存储插件和真实写入矩阵未闭合，不能宣告
  P6 或执行发布。

## 2026-09-01 Flutter 五平台 CI 与 Release 探索

- 提交 `79e8391` 的 CI run `33466562627` 和 Flutter 原生 run `33466562620` 均已成功；
  原生矩阵的 Windows、Linux、macOS、Android APK、iOS simulator job 均完成并上传 debug
  产物。这些是五平台 debug/确定性证据，不包含 OHOS、正式签名或真实设备。
- 本机 macOS Release 因缺少 `x86_64-apple-darwin` Rust target 且下载无输出而中断；Android
  AAB 的 Gradle/native strip 阶段完成并写出本地 AAB，但 Flutter 最终使用 `apkanalyzer`
  检查 debug symbols 时因 Homebrew command-line tools 的 SDK 目录布局无法定位 latest build
  tools，命令失败。该 AAB 未签名、未上传，不计 Release PASS；应在修复工具链目录布局的受控
  runner 重新执行。

## 2026-09-01 11:58 Core-live 营业窗口复核

在 `Asia/Shanghai` 图书馆营业窗口内，按顺序执行 `just verify-live mode=direct` 与
`just verify-live mode=webvpn`；凭据仍只经现有安全 stdin 路径传入，没有调用任何写方法。

- Direct：认证准备/登录/状态、用户、全部读取领域均通过；此前营业时间外失败的
  `libbook/area_detail` 本次为 `PASS(count=1)`。SPOC/Bykc 父列表为 0，因此详情为同批次
  `NOT_APPLICABLE`；Cgyy 用途为 `PASS(count=10, source=static_fallback)`。
- WebVPN：同一必需矩阵全部通过，`libbook/area_detail` 为 `PASS(count=1)`；SPOC/Bykc 详情
  同样因父列表为空为 `NOT_APPLICABLE`，Cgyy 用途同样明确为 `static_fallback`。本次 Judge
  瞬时计数为 `include_expired=57`、`current=17`，只作为当前安全快照。

该结果闭合 Core-live 的营业窗口协议缺口，但不证明六平台 Flutter App E2E、实体设备、安全
存储、写入 UI、正式签名或 Release 产物；这些 P3–P6 门禁保持未完成。

## 2026-08-31 本周期复核结果（最近一次，15:05）

基线命令 `git status --short --branch`、`just refs`、`just check-sensitive`、`just check`
均已重新执行并通过。当前实现新增了 `core-live` 的显式 `auth/prepare` 证据（映射到登录
内部已保存的准备状态，不重复发起请求）、完整的 SPOC/Judge 诊断矩阵行、认证失败后的完整
依赖阻断矩阵，以及禁止猜测周次的依赖处理。Cgyy 现在按 facade 解析出的 Direct/WebVPN/auto
路线执行，业务令牌在同一客户端内单飞复用，3xx 统一认证跳转会触发一次安全重登，Cookie
读取遵守域名、路径、Secure 和过期规则；预约上下文令牌和验证码字段不再是宿主可读的公共
字段，日志只保留操作名与长度摘要。聚合 facade 的读写入口均在网络副作用前校验外部会话
CAS 修订；stale reader/writer 的 Mock 测试均确认请求数为 0。

图书馆分区详情的最近一次 Direct/WebVPN 运行发生在开放时间之外（每日 08:30–23:00，
`Asia/Shanghai`）。两条路线都收到 HTTP 200、业务 `code=500` 且没有 `data`；二进制按
冻结合同输出 `upstream_changed`，但该非营业时间样本不能作为协议不兼容结论，必须在开放
窗口内重跑后再决定是否存在实现问题。

本次新入口真实只读结果如下（每条路线一个 `RouteClient`，未执行真实写操作）：

- Direct：除 `libbook/area_detail` 外，`auth/prepare`、登录、状态、用户、课表四项、考试、成绩、教室、SPOC 列表与
  `global_page_count=1`、Judge 列表/当前/详情/批量及 `course_count=5`、`raw_anchor_count=88`、
  `filtered_unique_count=83`、签到、阳光打卡、图书馆其余四项、博雅五项、Cgyy 六项、评教两项均
  为 `PASS`；`libbook/area_detail` 为 `FAIL(upstream_changed)`（业务 `code=500`、无 `data`）。
  SPOC 详情和博雅课程详情因无 ID 为 `NOT_APPLICABLE`。Cgyy 用途为
  `PASS source=static_fallback`，表示本地冻结回退，不代表上游用途接口成功。
- WebVPN：除 `libbook/area_detail` 外，上述所有必需操作均为 `PASS`；本次瞬时 Judge 计数为 `course_count=5`、`raw_anchor_count=17`、
  `filtered_unique_count=17`，当前列表为 17 项，详情和批量均为 `PASS`；SPOC/博雅详情因无 ID
  为 `NOT_APPLICABLE`。`libbook/area_detail` 同样为 `FAIL(upstream_changed)`（业务 `code=500`、无 `data`）。
  Cgyy 同样为 `source=static_fallback`，没有切换到 Direct。

逐操作安全摘要（本次运行）如下，计数为瞬时上游快照，不作为跨日期稳定断言：

```text
Direct:
auth/prepare PASS(mapping=embedded_login_state); auth/login PASS; auth/status PASS; user/info PASS
schedule/terms PASS(9); schedule/weeks PASS(19); schedule/current PASS; schedule/today PASS(0)
exam/arrangement PASS; grades/query PASS; classroom/search PASS(158)
spoc/assignments PASS(0,global_page_count=1); spoc/diagnostics PASS(1,reuse_from=assignments); spoc/detail NOT_APPLICABLE(no_assignment_id)
judge/include_expired PASS(83,course_count=5,raw_anchor_count=88,filtered_unique_count=83); judge/diagnostics PASS(83,reuse_from=include_expired); judge/current PASS(65); judge/detail PASS; judge/details_batch PASS(65)
signin/today PASS(0); ygdk/overview PASS(11); ygdk/records PASS(20)
libbook/libraries PASS(3); libbook/areas PASS(2); libbook/area_detail FAIL(upstream_changed); libbook/seats PASS(175); libbook/bookings PASS(2)
bykc/profile PASS; bykc/courses PASS(0); bykc/course_detail NOT_APPLICABLE(no_course_id); bykc/chosen PASS(0); bykc/statistics PASS
cgyy/sites PASS(7); cgyy/purposes PASS(10,source=static_fallback); cgyy/day PASS; cgyy/orders PASS(15); cgyy/order_detail PASS; cgyy/lock_code PASS(0)
evaluation/all PASS(0); evaluation/pending PASS(0)

WebVPN:
auth/prepare PASS(mapping=embedded_login_state); auth/login PASS; auth/status PASS; user/info PASS
schedule/terms PASS(9); schedule/weeks PASS(19); schedule/current PASS; schedule/today PASS(0)
exam/arrangement PASS; grades/query PASS; classroom/search PASS(158)
spoc/assignments PASS(0,global_page_count=1); spoc/diagnostics PASS(1,reuse_from=assignments); spoc/detail NOT_APPLICABLE(no_assignment_id)
judge/include_expired PASS(49,course_count=5,raw_anchor_count=49,filtered_unique_count=49); judge/diagnostics PASS(49,reuse_from=include_expired); judge/current PASS(17); judge/detail PASS; judge/details_batch PASS(17)
signin/today PASS(0); ygdk/overview PASS(11); ygdk/records PASS(20)
libbook/libraries PASS(3); libbook/areas PASS(2); libbook/area_detail FAIL(upstream_changed); libbook/seats PASS(175); libbook/bookings PASS(2)
bykc/profile PASS; bykc/courses PASS(0); bykc/course_detail NOT_APPLICABLE(no_course_id); bykc/chosen PASS(0); bykc/statistics PASS
cgyy/sites PASS(7); cgyy/purposes PASS(10,source=static_fallback); cgyy/day PASS; cgyy/orders PASS(15); cgyy/order_detail PASS; cgyy/lock_code PASS(0)
evaluation/all PASS(0); evaluation/pending PASS(0)
```

认证准备失败或登录失败时，Core-live 会继续输出所选功能的每一个认证、用户和业务操作，
并按依赖标记 `BLOCKED reason=authentication_failed`；依赖 ID 缺失只标记带原因的
`NOT_APPLICABLE`。真实矩阵的逐行安全摘要以本节为当前依据，下面较早日期的失败和上游
波动记录仅作历史证据，不得覆盖当前结果。

## 2026-08-31 独立代码审查复核

| 严重度 | 位置 | 发现 | 修复与验证 | 残留风险 |
|---|---|---|---|---|
| 高 | `scripts/core-live.sh` | `exec` 绕过 `EXIT` 陷阱导致自动会话目录泄漏，构建失败和信号路径也没有合同测试。 | 移除 `exec`，保留子进程退出码，增加 EXIT 与信号陷阱；`scripts/test-verify-live.sh` 运行时覆盖成功、失败、构建失败、SIGTERM、参数转发和显式目录保留。 | 无；显式目录仍由调用方负责清理。 |
| 高 | `crates/ubaa-core/src/facade/mod.rs`、`runtime.rs`、`session/mod.rs` | 读写请求前只检查进程内状态，外部会话修订变化可能在网络副作用后才被发现。 | 新增 `SessionStore::is_revision_current` 和协调器外部修订检查；聚合 facade 所有操作入口统一预检；stale reader/writer Mock 均断言请求计数为 0。 | Windows 权限策略仍依赖平台 ACL，按既有会话审计记录。 |
| 中 | `apps/ubaa-cli/src/lib.rs`、`routing.rs` | CLI 生产代码直接导入 `connection` 路由诊断，宿主边界不完整。 | 将安全诊断类型经 `facade` 重导出，新增递归源码依赖扫描覆盖全部 CLI `src/`；CLI 全量测试通过。 | Core 内部模块仍为测试兼容保持公开，后续可在测试支持库迁移后进一步收紧。 |
| 中 | `apps/ubaa-cli/src/bin/core-live.rs` | 认证准备、诊断字段和认证失败后的矩阵项不完整，Cgyy 静态回退来源不可区分。 | 显式调用一次 `prepare_login` 并映射到登录状态，补齐阻断矩阵和 SPOC/Judge 计数，新增 Cgyy 来源 DTO；两条真实路线逐项通过。 | 真实上游列表数量会波动，只记录安全计数并保持逐项语义门禁。 |

## 当前大文件拆分例外

本周期先保留以下仍超过 800 行的文件，以避免在协议收口阶段引入行为变化；每个文件的
职责和测试边界已由现有模块/测试固定，后续触碰时按目标树渐进拆分，不创建空转发模块：

| 文件 | 行数（2026-08-31） | 暂缓原因与后续安排 |
|---|---:|---|
| `apps/ubaa-cli/src/lib.rs` | 2598 | 仍是 CLI backend 合同和命令委托的唯一组合入口；先保持公共 trait/退出语义稳定，后续按 `args/backend/execution/input/render` 迁移并逐组验证。 |
| `crates/ubaa-core/src/facade/mod.rs` | 2000 | facade 委托方法共享路线生命周期和收尾逻辑；本周期新增读写 stale revision 预检，继续拆分前先冻结 facade 快照并为每个业务建立单独合同测试。 |
| `crates/ubaa-core/src/features/cgyy.rs` | 1603 | Cgyy 协议、解析、重定向和写保护刚完成路线统一；加密/签名已独立文件，下一次协议变更前拆读/写/解析。 |
| `crates/ubaa-core/src/features/judge.rs` | 1423 | Judge 列表、详情、缓存和并发边界需共享同一生命周期；保持四 worker/缓存测试完整，后续拆为读、解析、诊断。 |
| `crates/ubaa-core/src/features/spoc.rs` | 1417 | SPOC 登录、分页、解析和诊断共享业务令牌状态；保持一次登录和全局页计数，后续按认证/读/解析拆分。 |
| `crates/ubaa-core/src/session/mod.rs` | 1050 | 会话 CAS、锁、迁移和权限代码共同维护原子不变量；存储、Cookie、端口已先行拆出，后续继续按 coordinator/validation 拆分。 |
| `crates/ubaa-core/src/features/bykc.rs` | 964 | 博雅读写协议和加密调用共享认证上下文；下一次写协议变更前按读/写/解析拆分。 |
| `crates/ubaa-core/src/features/state.rs` | 843 | 路线状态缓存的生成号和失效逻辑需要集中维护；已有 `state_cache.rs`，后续按业务状态拆分并保留并发测试。 |

## 2026-08-31 本周期基线检查

本周期开始时工作树包含既有未提交改动，按合同作为基线保留。`just refs` 和
`just check-sensitive` 已通过；`just check` 在 Clippy 阶段失败，具体为
`crates/ubaa-core/src/facade/mod.rs:592` 的 `RouteResolution`（可复制小类型）
仍按引用传递，触发 `clippy::trivially-copy-pass-by-ref`。该失败是基线事实，
不是验收通过；后续先做最小修复并重新运行完整门槛。

## 2026-08-31 Cgyy WebVPN 路由失败优先证据

按 Cgyy 合同先将 facade 回归断言改为 WebVPN runtime，并运行
`cargo test --locked -p ubaa-core --test facade cgyy_webvpn_uses_`。测试按预期失败：
`cgyy_webvpn_uses_webvpn_business_transport_after_route_resolution` 实际调用
Direct 传输 1 次、WebVPN 传输 0 次。该失败证明现有实现仍存在固定 Direct 路由，随后只做
runtime/URL 选择的最小修复。

Core 安全失败优先证据：新增 `锁码公共序列化不暴露上游原始数据` 后，
`cargo test --locked -p ubaa-core --test cgyy 锁码公共序列化不暴露上游原始数据`
按预期失败，序列化结果包含 fixture 锁码。该失败确认不能只在 CLI 做投影，Core
公共 DTO 本身也必须阻断原始 `data` 外泄。

修复路由后首次 `just check` 仍在 Core 单元测试发现一条旧断言
`web_vpn模式下场馆签名请求保持直连地址`，其期望为 `cgyy.buaa.edu.cn`，
与当前 WebVPN 合同冲突；该测试已改为验证 `d.buaa.edu.cn` 及编码后的 Cgyy 目标。

## 2026-08-31 Core-live 验证入口改造

已新增 `core-live` 二进制和 `scripts/core-live.sh` 启动器。Core-live 在单个固定路线
`RouteClient` 内完成一次登录，然后串行调用只读 facade，并按操作输出路线、状态和稳定错误码；
详情 ID 只在进程内存中传递，写方法不在入口白名单内。`verify-live` 已收敛为参数白名单、
`.env.local` 安全读取、锁定构建和一次 stdin 转发，拒绝 `auto` 真实登录；对应 Shell 合同测试
已改用假 Core-live 验证凭据不进入参数或 xtrace。Direct/WebVPN 真实矩阵尚待本周期新入口
分别执行，旧脚本的聚合摘要不作为当前证据。

## 2026-08-31 Core-live Direct/WebVPN 真实逐操作结果（网关 Cookie 修复前）

使用 `just verify-live mode=direct` 和 `just verify-live mode=webvpn`，凭据只经
stdin 注入，未保存 stdout 以外的内容，两个运行均未调用写方法。Direct 退出码 0：

```text
auth/login PASS; auth/status PASS; user/info PASS
schedule/terms PASS(9); schedule/weeks PASS(19); schedule/current PASS; schedule/today PASS(0)
exam/arrangement PASS; grades/query PASS; classroom/search PASS(158)
spoc/assignments PASS(0); spoc/detail NOT_APPLICABLE(no_assignment_id)
judge/include_expired PASS(83); judge/current PASS(65); judge/detail PASS; judge/details_batch PASS(65)
signin/today PASS(0); ygdk/overview PASS(11); ygdk/records PASS(20)
libbook/libraries PASS(3); libbook/areas PASS(2); libbook/area_detail PASS(1); libbook/seats PASS(175); libbook/bookings PASS(2)
bykc/profile PASS; bykc/courses PASS(0); bykc/course_detail NOT_APPLICABLE(no_course_id); bykc/chosen PASS(0); bykc/statistics PASS
cgyy/sites PASS(7); cgyy/purposes PASS(10); cgyy/day PASS; cgyy/orders PASS(15); cgyy/order_detail PASS; cgyy/lock_code PASS(0)
evaluation/all PASS(0); evaluation/pending PASS(0)
```

WebVPN 的认证、用户、课表/考试/成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook 和
Bykc 均通过；本次 Judge `include_expired/current/details_batch` 分别为 49/17/17（同日早先重跑为 209/209/209，保留为上游列表波动观察）；SPOC 详情与 Bykc 课程详情因上游列表为空分别为
`NOT_APPLICABLE(no_assignment_id)`、`NOT_APPLICABLE(no_course_id)`。WebVPN 退出码 5，
失败项逐项为：

```text
cgyy/sites FAIL(authentication_required); cgyy/purposes FAIL(authentication_required)
cgyy/day NOT_APPLICABLE(no_site_id); cgyy/orders FAIL(authentication_required)
cgyy/order_detail NOT_APPLICABLE(no_order_id); cgyy/lock_code FAIL(authentication_required)
evaluation/all FAIL(authentication_required); evaluation/pending BLOCKED(all_failed)
```

WebVPN Cgyy 没有回退到 Direct；上述 `authentication_required` 是当前上游路线结果，
不是本地改写为成功。窄范围日志显示 Cgyy SSO 在 `d.buaa.edu.cn` 路线完成 4 次重定向后
以 200 返回，但未写入冻结要求的 SSO Cookie，Core 因此安全失败。`auto` 未执行真实登录，
只由 facade 的确定性 WebVPN-only、Direct/WebVPN 探测和路由策略测试覆盖。

## 2026-08-31 Core-live Direct/WebVPN 真实逐操作结果（HAR 网关 Cookie 修复后的历史快照）

依据 `examples/BUAA-CGYY/d.buaa.edu.cn.cgyy.har` 的脱敏证据，Core 在 WebVPN Cgyy SSO
重定向后读取网关 Cookie 快照；令牌只在内存中作为 `Sso-Token` 使用。以下为重新执行的
单路线、串行、只读结果，凭据仅经 stdin 注入，未调用任何真实写方法。

Direct 退出码 0：

```text
auth/login PASS; auth/status PASS; user/info PASS
schedule/terms PASS(9); schedule/weeks PASS(19); schedule/current PASS; schedule/today PASS(0)
exam/arrangement PASS; grades/query PASS; classroom/search PASS(158)
spoc/assignments PASS(0); spoc/detail NOT_APPLICABLE(no_assignment_id)
judge/include_expired PASS(83); judge/current PASS(65); judge/detail PASS; judge/details_batch PASS(65)
signin/today PASS(0); ygdk/overview PASS(11); ygdk/records PASS(20)
libbook/libraries PASS(3); libbook/areas PASS(2); libbook/area_detail PASS(1); libbook/seats PASS(175); libbook/bookings PASS(2)
bykc/profile PASS; bykc/courses PASS(0); bykc/course_detail NOT_APPLICABLE(no_course_id); bykc/chosen PASS(0); bykc/statistics PASS
cgyy/sites PASS(7); cgyy/purposes PASS(10); cgyy/day PASS; cgyy/orders PASS(15); cgyy/order_detail PASS; cgyy/lock_code PASS(0)
evaluation/all PASS(0); evaluation/pending PASS(0)
```

WebVPN 退出码 0：

```text
auth/login PASS; auth/status PASS; user/info PASS
schedule/terms PASS(9); schedule/weeks PASS(19); schedule/current PASS; schedule/today PASS(0)
exam/arrangement PASS; grades/query PASS; classroom/search PASS(158)
spoc/assignments PASS(0); spoc/detail NOT_APPLICABLE(no_assignment_id)
judge/include_expired PASS(80); judge/current PASS(48); judge/detail PASS; judge/details_batch PASS(48)
signin/today PASS(0); ygdk/overview PASS(11); ygdk/records PASS(20)
libbook/libraries PASS(3); libbook/areas PASS(2); libbook/area_detail PASS(1); libbook/seats PASS(175); libbook/bookings PASS(2)
bykc/profile PASS; bykc/courses PASS(0); bykc/course_detail NOT_APPLICABLE(no_course_id); bykc/chosen PASS(0); bykc/statistics PASS
cgyy/sites PASS(7); cgyy/purposes PASS(10); cgyy/day PASS; cgyy/orders PASS(15); cgyy/order_detail PASS; cgyy/lock_code PASS(0)
evaluation/all PASS(0); evaluation/pending PASS(0)
```

Judge 数量随上游快照变化（本次 WebVPN 为 `80/48/48`，早先同日运行也出现过
`49/17/17` 与 `209/209/209`），但每次均逐项完成列表、详情和批量详情语义校验；
数量波动不改变路线成功结论。SPOC 与 Bykc 详情因对应列表为空按合同标记
`NOT_APPLICABLE`。auto 没有真实登录矩阵，只保留确定性路线解析与 WebVPN-only Mock 证据。

## 2026-08-31 确定性门禁与交接复核（历史快照）

以下命令在 HAR 修复、测试和文档更新后再次执行并通过：

```text
just refs                         PASS（冻结引用版本匹配）
just check-sensitive              PASS（168 个仓库文件）
just check                        PASS（fmt、Clippy、全工作区测试、构建、文档、Shell、diff）
cargo test --locked -p ubaa-cli --all-targets       PASS（13 个二进制 E2E、23 个 CLI 合同、2 个 Core-live 运行时）
cargo test --locked -p ubaa-cli --test cli_contract PASS（23）
bash ./scripts/test-verify-live.sh                  PASS
```

各主题提交前均通过 `git diff --check`；Cgyy 协议提交只暂存 Core 实现、脱敏 Mock 和
迁移记录，文档收口提交只涉及合同与历史矩阵。HAR、`ubaa_old`、`examples/buaa-api`、
`.env.local` 及任何运行时会话材料均未暂存。真实 Direct/WebVPN 只读矩阵曾在同一批次
单路线客户端内串行完成；顶部最近一次运行发现图书馆分区详情业务 `code=500`，不被本节
历史快照覆盖。所有写操作仍仅有 Mock、向量和 CLI 阻止证据。

独立代码审查覆盖本周期完整差异，重点检查 facade 唯一宿主边界、Cgyy Direct/WebVPN/auto
路线绑定、业务令牌生命周期、Core-live/verify-live 分工、写操作入口和敏感输出。未发现
可复现的高严重度问题；相关 Cgyy 与 facade 回归测试在最终门禁后再次通过。

## 2026-08-29 阶段提交

- Cgyy Rust CLI 已完成一次用户明确授权的 Direct 读写探针：登录、站点、用途、日期、订单读取成功；提交时省略验证码字段，由 Core 自动获取、求解和校验；提交后按冻结 Python 脚本等待 5 秒再取消，取消命令成功，订单列表最终确认 `orderStatus=2`。本次未输出或持久化订单号、手机号、令牌、Cookie、验证码和原始响应；`verify-live` 仍不执行写操作。
- 修复 Cgyy 日期 DTO 的敏感边界：预约上下文 `reservationToken` 继续留在 Core 提交链，但不再序列化到 facade/CLI 输出；新增失败优先的序列化回归测试。修复后 Direct/WebVPN Cgyy 站点与日期实时门禁均通过；订单详情/锁码仍可能受上游 `upstream_unavailable` 影响。
- 本轮继续对照冻结 `ubaa_old` 修复 Cgyy 业务请求：GET/POST 共用业务令牌失效后的单次重登重放；预约上下文、验证码校验和最终提交的 `cgAuthorization` 均使用 `access_token`，预约表单中的业务 `token` 仍按旧版保留；未执行真实写请求。
- Cgyy 日期接口现在要求成功信封中的 `data` 存在且为 JSON 对象（允许空对象）；锁码接口要求 `code=200`，缺失 `data` 按旧版映射为空值；新增业务认证重试、信封和路由回归测试，Core Cgyy 集成测试通过 12/12，CLI 合同测试通过 23/23。
- 历史记录：Cgyy 在 `WebVPN` facade 中的写操作曾固定使用 Direct 业务地址；本周期已由路线失败测试和最小修复 supersede，当前公共读写入口均绑定解析出的路线 runtime，真实验证仍禁止写操作。
- `verify-live` 在未设置 `UBAA_VERIFY_DATE` 且日期接口明确返回 `upstream_unavailable` 时，最多尝试当前日期及未来 7 天；显式日期不回退，`invalid_semantics` 仍立即失败，避免用日期轮询掩盖协议变化。
- 本轮只读实时证据：Direct 与 WebVPN 站点均返回 7 个；结构探针在部分未来日期获得正常的日期对象、时段数组和空间数组，但正式复验中的日期/订单/锁码仍出现 `upstream_unavailable` 或 `invalid_semantics`。实时上游不稳定，不能据此宣称 Cgyy 全链路验收完成；未执行预约、提交或取消。
- Direct Cgyy 只读复验（`feature=cgyy route=direct`）成功，站点摘要为 7 个；验证器未执行任何预约或取消写操作，后续日期/订单等依赖操作仍按逐项结果记录。
- auto Cgyy 只读复验解析到 Direct：站点摘要为 7 个；日期返回 `invalid_semantics`，锁码返回 `upstream_unavailable`。验证器按依赖关系继续逐项输出，未执行任何预约或取消写操作。
- 对照冻结 `LocalSigninApi.getTodayClasses` 修正签到今日查询：使用 GET 与 `sessionId` 请求头；新增请求构造测试先失败后通过，并校正 source parity 中与示例协议混淆的旧描述。
- Direct Signin 只读复验（`feature=signin route=direct`）成功，返回 0 条课程；验证器只执行今日查询，未调用签到提交写操作。
- WebVPN Signin 只读复验（`feature=signin route=webvpn`）成功，返回 0 条课程；验证器只执行今日查询，未调用签到提交写操作。
- Direct 与 WebVPN LibBook 只读复验均成功（`feature=libbook`），各返回 2 个馆区；验证器仅执行馆区及后续只读查询，未调用预约或取消写操作。
- 对照冻结 `LocalYgdkApi.getOverview` 补齐统计与学期请求的可选失败回退；新增 Mock 先失败后通过，保留分类/项目概览并将缺失统计回退为零值，未改变记录或写链协议。
- Direct Ygdk 概览只读复验（`feature=ygdk route=direct`）成功，返回 11 个项目；验证器未执行打卡提交或照片上传。
- WebVPN Ygdk 概览只读复验（`feature=ygdk route=webvpn`）成功，返回 11 个项目；验证器未执行打卡提交或照片上传。
- 对照冻结 `LocalEvaluationService` 补齐评教激活、任务、问卷及课程读取的非认证异常回退；新增激活临时失败 Mock 先失败后通过，认证失效仍保持错误传播，未改变评教写链或 CLI 确认保护。
- Direct 与 WebVPN Evaluation 只读复验均成功（`feature=evaluation`），各返回 0 门课程；验证器仅读取评教任务，未执行评教提交。
- auto Signin 只读复验解析到 Direct 成功，返回 0 条课程；仅执行今日查询，未调用签到提交写操作。
- auto LibBook 只读复验解析到 Direct 成功，返回 2 个馆区；仅执行馆区及后续只读查询，未调用预约或取消写操作。
- auto Evaluation 只读复验解析到 Direct 成功，返回 0 门课程；仅读取评教任务，未执行评教提交。
- auto Ygdk 只读复验解析到 Direct 成功，返回 11 个项目；仅执行概览与记录读取，未执行打卡提交或照片上传。
- 本轮 Direct/WebVPN/auto `feature=all` 聚合验收均在 Judge 路线比较前因缺少 `UBAA_VERIFY_DIGEST_SALT` 退出码 2；`.env.local` 仅提供测试账号字段，未提供该非凭据配置。该缺口已记录，不能以聚合结果替代逐功能证据。
- 最新 Cgyy 三路线逐项复验：Direct、WebVPN、auto 的站点读取均成功并返回 7 个站点；三路线日期与订单阶段均返回 `upstream_unavailable`，WebVPN 锁码同样返回 `upstream_unavailable`。未获得新的协议证据，保持冻结请求与失败关闭语义，未执行真实写操作。
- 使用仅存在于当前 shell 的临时 `UBAA_VERIFY_DIGEST_SALT` 完成三路线 `feature=all` 复验：Direct 与 WebVPN 的 User、Schedule、Exam、Grades、Classroom、SPOC、Judge（含详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 均成功；auto 解析到 Direct 且上述功能均成功。Direct Cgyy 日期/锁码为 `upstream_unavailable`；WebVPN Cgyy 日期为 `invalid_semantics`、订单/锁码为 `upstream_unavailable`；auto 在 Cgyy 日期阶段为 `upstream_unavailable`。盐值未写入、未输出，未执行真实写操作。
- CLI 合同端到端测试 `cargo test --locked -p ubaa-cli --test cli_contract` 通过 23/23；覆盖所有功能入口、JSON schema、human/JSON 脱敏、路线诊断及全部写操作默认拒绝与显式确认行为。
- Core 集成测试 `cargo test --locked -p ubaa-core --tests` 通过（各功能、连接、会话、解析及写链 Mock 测试均通过，退出码 0）；未执行真实写请求。
- Direct、WebVPN、auto 认证状态复验均成功（`feature=auth`，三条路线均 `parsed_user=yes`）；认证仅用于建立/检查只读会话，未执行业务写操作。
- 方法级对照复核冻结 `ubaa_old/shared/api/feature` 的 13 个领域：当前 Core facade、RouteClient 与 CLI 均覆盖对应读写方法；未发现遗漏的直接上游操作。该复核未将 Server 或非等价 examples 接口纳入范围。
- 对照冻结 `LocalClassroomApi` 移除教室响应 `e` 的额外非零门控；新增脱敏测试先失败后通过，保留完整信封/字段类型校验并原样映射 `ClassroomQuery.code`。
- 将 Cgyy MD5 签名规范化与摘要构造移入 `crates/ubaa-core/src/features/cgyy_sign.rs`；保持前缀、路径、非空参数排序、时间戳、空格和摘要输出不变；Cgyy 请求向量、敏感扫描与全量门禁通过。
- 将 Cgyy 签名模块中的毫秒时间戳读取与签名摘要保持同一职责边界；维持 Unix epoch、溢出处理及 `UpstreamChanged` 错误语义不变；Cgyy 定向测试与敏感扫描通过。
- 对照冻结 `LocalCgyySigner.cleanParams` 补齐签名前审计键过滤，排除 `gmtCreate`、`gmtModified`、`creator`、`modifier`、`id`、`_index`、`_rowKey`；新增脱敏向量先失败后通过，保持其余签名排序、空值和摘要语义不变。
- 校正 `legacy-feature-inventory.md` 与 `source-parity.md` 的 Cgyy WebVPN 现状：当前业务 runtime 与 facade 解析路线一致，并有 WebVPN-only 回归测试；剩余日期/订单/锁码仅按逐操作实时结果记录，避免历史失败表述与当前代码不一致。
- 将 Cgyy 验证码点位与校验凭据的 AES-ECB/PKCS#7/Base64 加密辅助移入 `crates/ubaa-core/src/features/cgyy_crypto.rs`；保持三种密钥长度、字段拼接、错误文本和冻结向量不变；Core、敏感扫描与全量门禁通过。
- 将 Ygdk 照片 multipart 正文构造移入 `crates/ubaa-core/src/features/ygdk_upload.rs`；保持 `uid`、`token`、文件元数据、CRLF 和 boundary 终止顺序不变；上传字段测试、敏感扫描与全量门禁通过。
- 将 LibBook 预约请求 DTO 与日期派生 AES-128-CBC/PKCS#7 加密辅助移入 `crates/ubaa-core/src/features/libbook_crypto.rs`；保持固定 IV、字段顺序、错误文本和 Base64 输出不变；LibBook golden 向量、敏感扫描与全量门禁通过。
- 将 SPOC 参数 AES-CFB/Base64 加密辅助移入 `crates/ubaa-core/src/features/spoc_crypto.rs`；保持冻结密钥、链式初始向量、零填充、块加密和 Base64 输出不变；golden 向量、敏感扫描与全量门禁通过。
- 将 Judge 路线缓存共用的定时条目、TTL 判断和有界插入辅助移入 `crates/ubaa-core/src/features/state_cache.rs`；保持缓存容量、过期淘汰、空结果处理和并发语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 最新实时复测：WebVPN 全量在 Cgyy 日期阶段返回 `invalid_semantics`（此前非 Cgyy 及 Cgyy 站点均成功）；auto 解析到 Direct 并在 Ygdk 阶段返回 `timeout`，此前 User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin 成功。失败项按冻结逻辑与实时证据保留，未执行真实写操作。
- 将 `RouteClient` 会话冲突保护、认证失效清理和操作收尾逻辑移入 `crates/ubaa-core/src/facade/session_lifecycle.rs`；保持会话所有权、错误码、清理时机及重试语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 实时复核记录：`feature=auth route=direct` 单项认证成功；`feature=all route=direct` 在聚合登录语义校验阶段返回 `invalid_semantics`，未进入业务读操作。该结果按验证器双路线聚合边界记录，未据此修改冻结认证协议。
- 将 WebVPN 主机段 AES-CFB 编解码与十六进制辅助逻辑移入 `crates/ubaa-core/src/connection_codec.rs`；保持冻结密钥、填充、重定向主机还原及错误码不变；Core、敏感扫描与全量门禁通过。
- 将 CLI 的 `command_output_value` 与 human 输出渲染分别移入 `apps/ubaa-cli/src/command_output.rs`、`apps/ubaa-cli/src/render.rs`；保持 JSON/human 内容、错误文本和退出码不变；CLI、敏感扫描与全量门禁通过。
- 新增 `crates/ubaa-core/src/facade/aggregate_helpers.rs`，收拢聚合登录准备、路由结果、安全错误和备用路线辅助函数；保持 `UbaaClient` 的路由顺序、错误码和 JSON 安全投影不变；Core、CLI、敏感扫描与全量门禁通过。
- 将 `Cli` 的登录、会话预检、登出、认证状态和功能映射方法移入 `apps/ubaa-cli/src/commands.rs`；保持命令匹配、路由模式和稳定功能标识不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/judge_args.rs`，收拢 Judge 列表、隐藏诊断和详情/批量 key 参数定义；保持历史作业开关、参数名称及输出语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/spoc_args.rs`，收拢 SPOC 列表、隐藏诊断与详情命令定义；保持作业 ID 参数、诊断隐藏属性和输出语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/classroom_args.rs`，收拢空闲教室命令参数与子命令定义；保持校区、日期参数及查询输出语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/grades_args.rs`，收拢成绩命令参数与子命令定义；保持 `grades list --term` 入口及参数语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/exam_args.rs`，收拢考试命令参数与子命令定义；保持 `exam list --term` 入口及参数语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/user_args.rs`，收拢用户中心命令参数与子命令定义；保持 `user show` 入口、会话要求和输出语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/schedule_args.rs`，收拢课表命令参数与子命令定义；保持学期、教学周、指定周次和今日课表入口及参数语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/auth_args.rs`，收拢认证命令参数与子命令定义；保持登录、状态、登出命令、敏感输入边界及输出语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/signin_args.rs`，收拢课堂签到命令参数与子命令定义；保持今日查询、课程编号校验及 `--confirm-write` 写操作保护不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/ygdk_args.rs`，收拢阳光打卡命令参数与子命令定义；保持概览/记录分页默认值、照片输入参数及 `--confirm-write` 写操作保护不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/libbook_args.rs`，收拢图书馆命令参数与子命令定义；保持库馆/分区/座位/预约查询参数、默认分页值及预约/取消的显式写保护不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/evaluation_args.rs`，收拢评教命令参数与子命令定义；保持全部/待评教查询、payload 路径校验及 `--confirm-write` 写操作保护不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/bykc_args.rs`，收拢博雅课程命令参数与子命令定义；保持课程分页默认值、详情/已选/统计查询以及选课、退选、签到的显式写保护不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/cgyy_args.rs`，收拢场馆命令参数与子命令定义；保持查询参数、写操作 `--confirm-write`/`--request-stdin` 保护和 CLI 命令语义不变；CLI、敏感扫描与全量门禁通过。
- 最新 `auto` 全量只读复测解析到 Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 成功；Cgyy 站点成功而日期、订单详情、锁码为 `upstream_unavailable`。未执行真实写操作；自动路由结果与 Direct 实时证据一致。
- 最新 Direct/WebVPN 全量只读复测：Direct 的 User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 成功，Cgyy 站点成功而日期/订单/锁码为 `upstream_unavailable`；WebVPN 的 User、Schedule、Exam、Grades、Classroom、SPOC、Signin、Ygdk、LibBook、Bykc、Evaluation 成功，Judge 因冻结语义校验为 `judge_cutoff`/`invalid_semantics`，Cgyy 日期/锁码为 `upstream_unavailable`。未执行真实写操作；失败项按旧版逻辑与实时上游证据保留。
- 将 CLI 的评教 payload 与场馆预约标准输入读取移入 `apps/ubaa-cli/src/input.rs`；保持 JSON 校验、空 payload 拒绝、敏感输入边界和错误语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/command_output.rs`，收拢 `CommandOutput` 与 `readonly` Core 结果投影；保持 human/JSON 输出、路线元数据和序列化语义不变；CLI、敏感扫描与全量门禁通过。
- 扩展 `docs/development/engineering-standards.md`，新增跨宿主交接规范矩阵，明确 Core/CLI 与 Flutter、OpenHarmony、Node、Swift、Kotlin、ArkTS、MCP、Server 的依赖方向、敏感边界、稳定输出和写操作默认关闭规则；文档、敏感扫描与全量门禁通过。
- 新增 `crates/ubaa-core/src/session/storage.rs`，收拢会话文件锁与临时文件生命周期；保持原子写入、失败清理、跨平台锁释放和权限边界不变；Session、CLI、敏感扫描与全量门禁通过。
- 新增 `crates/ubaa-core/src/session/ports.rs`，收拢 `SessionStore` 持久化端口；保持版本化加载、比较交换、保存/清理循环和错误语义不变；Session、CLI、敏感扫描与全量门禁通过。
- 新增 `apps/ubaa-cli/src/login_args.rs`，收拢登录参数及敏感 Debug 脱敏实现；保持参数名称、隐藏属性、标准输入校验和 JSON/交互登录语义不变；CLI、敏感扫描与全量门禁通过。
- 新增 `crates/ubaa-core/src/session/types.rs`，收拢单路线/双路线会话快照、版本包装、校验与比较交换结果类型；保持 schema-v2 字段、旧版迁移、Deref 和序列化语义不变；Session、CLI、敏感扫描与全量门禁通过。
- 新增 `crates/ubaa-core/src/session/cookies.rs`，收拢 `StoredCookie`、`CookieJar` 及其容器逻辑；保持 Cookie 的 Domain/Path/Secure/Max-Age/Expires 过滤、替换、持久化和敏感 Debug 脱敏语义不变；Cookie、Session、支持库测试及全量门禁通过。
- 新增 `apps/ubaa-cli/src/routing.rs`，收拢 `ReadonlyRouteContext` 及路由决策转换；保持 CLI 公共导出、路由元数据和 JSON 输出语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 三路线逐操作只读复核（本轮）：Direct 的 User、Schedule、Exam、Grades、Classroom、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 通过，Cgyy 站点通过而日期为 `invalid_semantics`、锁码为 `upstream_unavailable`；WebVPN 的 User、Schedule、Exam、Grades、Classroom、SPOC、Signin、Ygdk、LibBook、Bykc、Evaluation 通过，Judge 为 `timeout`，Cgyy 日期/订单/锁码为 `upstream_unavailable`；auto 解析到 Direct，除 Schedule 当前周 `timeout` 外非 Cgyy 操作通过，Cgyy 日期/详情/锁码为 `upstream_unavailable`。未执行真实写操作；失败项与冻结请求逻辑一致，按上游实时证据保留。
- 新增 `facade/types.rs`，收拢 `Routed`、`RoutedError` 与内部 `Operation` 类型；通过 facade 重新导出稳定结果包装器，保持 CLI/API 可见性、路由元数据和错误语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/judge.rs`，收拢希冀状态、作业摘要、诊断、详情键、题目和详情 DTO；保持字段、公开导出与序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/spoc.rs`，收拢 SPOC 作业状态、列表、诊断和详情 DTO；保持字段、公开导出与 camelCase/SCREAMING_SNAKE_CASE 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/cgyy.rs` 进一步收拢 `CgyyReservationSelection`、`CgyyReservationSubmitRequest` 及其 Debug 脱敏实现；保持验证码字段 `skip_serializing`、CLI 写操作保护和序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/bykc.rs` 继续收拢 `BykcCourse` 与 `BykcCourseStatus`，保持 camelCase/snake_case 序列化、默认状态和公开导出不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/bykc.rs` 已收拢课程分页、已选课程、分类、签到配置和统计 DTO，保持字段、默认值与 serde 语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/bykc.rs` 继续收拢 `BykcActionResult` 与 `BykcSignRequest` 写操作 DTO；仅调整模块归属，保持字段、camelCase 序列化和 CLI 默认阻止语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/libbook.rs`，收拢图书馆库房、区域、座位、预约请求及结果 DTO；保持公开导出、字段和 camelCase 序列化不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/ygdk.rs`，收拢阳光打卡概览、记录、图片上传和提交 DTO；保持字段、序列化与图片 Debug 脱敏语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/evaluation.rs`，收拢评教任务、课程、进度及结果 DTO；保持字段、进度计算和 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/signin.rs`，收拢 iClass 课堂签到状态与签到结果 DTO；保持字段、状态值和 camelCase 序列化不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/schedule.rs`，收拢学期、教学周、课表、今日课程和考试 DTO；保持字段、默认值与 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/grades.rs`，收拢成绩课程与学期结果 DTO；保持字段、可空性和 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/classroom.rs`，收拢空闲教室查询及教室信息 DTO；保持严格字段类型、公开导出和 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- 新增 `domain/cgyy.rs`，收拢场馆站点、用途、时段、空间、日期和订单等只读 DTO；验证码敏感写请求仍保留原边界，公开导出与 camelCase 序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/cgyy.rs` 进一步收拢场馆写操作结果与安全锁码载荷；预约请求及验证码敏感字段保持原位和 Debug 脱敏，公开导出、字段与序列化语义不变；Core、CLI、敏感扫描与全量门禁通过。
- `domain/bykc.rs` 先拆出 `BykcUserProfile` DTO，保持 camelCase 序列化和公开导出不变；Core、CLI、敏感扫描与全量门禁通过，后续继续在同一模块收拢 Bykc 类型。
- `domain/route.rs` 拆出 `ConnectionMode`、`RoutePolicy` 与 `ReadonlyFeature`，保持序列化名称、配置键和路由语义不变；Core 全部测试与全量门禁通过。
- 最新三路线只读复测：Direct 仅 Cgyy 日期/锁码为 `upstream_unavailable`；WebVPN 的 Cgyy 日期为 `invalid_semantics`、锁码为 `upstream_unavailable`；auto 解析为 Direct，Cgyy 日期为 `invalid_semantics`、订单为 `upstream_unavailable`。其余功能逐项通过，未执行真实写操作。
- 认证领域拆分后重新执行三路线逐操作只读矩阵：Direct 仅 Cgyy 日期/锁码为 `upstream_unavailable`；WebVPN 的 Cgyy 日期为 `invalid_semantics`、锁码为 `upstream_unavailable`；auto 解析为 Direct，Cgyy 日期为 `invalid_semantics`、订单为 `upstream_unavailable`。其余功能逐项通过；未执行真实写操作。
- `domain/auth.rs` 拆出认证输入、聚合登录结果、用户资料与认证状态 DTO；字段、serde 别名、脱敏 Debug/Display/Serialize 语义保持冻结实现一致。认证、契约、只读集成测试与全量门禁通过。
- `execution.rs` 拆出 CLI 的公共后端执行入口与命令到功能映射；具体 feature 分支和渲染逻辑保持原边界，CLI、Core、敏感扫描和文档门禁全部通过。
- 后续结构提交将 CLI 顶层解析器与命令分派移入 `apps/ubaa-cli/src/commands.rs`，保持现有命令、参数、输出和退出语义；本阶段全量确定性门禁通过。
- `0d6284b` 将 CLI 连接模式解析及 `ConnectionMode` 转换拆分到独立模块；命令名、参数、退出码、路由和协议行为保持不变，`just check-sensitive` 与 `just check` 均通过。
- `a70ea60` 固化 Cgyy 签名请求的 WebVPN 路线合同：场馆业务签名请求保持
  `cgyy.buaa.edu.cn` 直连主机，不被错误包装为 WebVPN 地址；测试使用无网络传输，
  不读取或写入真实会话。
- `baf295f` 校正扩展功能库存，使 Signin、Ygdk、LibBook、Cgyy、Bykc 和 Evaluation
  的 Core/CLI 实现状态与当前代码一致，并明确真实写操作永久禁止。
- Bykc 已选课程曾因 Rust 仅接受数组而在三条路线返回 `upstream_changed`；提交 `29a83b2`
  已按冻结 `data.courseList` 包装修复并通过完整门禁。2026-08-29 Direct、WebVPN、auto
  单项复测均通过。
- 当前阶段扩展 `verify-live` 的逐操作只读矩阵：Ygdk 记录、LibBook 区域/详情/座位/预约、
  Bykc 资料/课程详情/已选/统计、Cgyy 用途/日期/订单详情和 Evaluation 待评教均会独立
  执行；详情请求仅在上游返回脱敏标识时继续，空集合不会伪造详情成功。
- User `user show` 已纳入验证器的独立操作和 `all` 聚合，并以完整脱敏 profile 校验
  字段集合、类型和掩码规则；验证器脚本 stub 已覆盖该调用路径。
- 早期三路线复测中的 Judge/Bykc/Cgyy 失败已分别通过后续修复或重跑收敛；当前保留的实时失败集中在 Cgyy 日期、订单、锁码等上游阶段，按最新逐操作证据记录，不能由其他读操作成功替代。
- 本阶段 `just check-sensitive && just check` 全部通过。整体迁移仍未完成：Cgyy
  WebVPN 业务会话返回 `authentication_required`，Direct 门锁码返回
  `upstream_unavailable`，Signin/Ygdk/Evaluation 等逐操作实时矩阵仍有失败项。

## 当前结论与历史阶段摘要

冻结来源逐操作复核、Core/CLI 确定性门禁和当前只读能力已经完成；写操作均有协议实现、
Mock/向量和 CLI 确认保护，但真实账号永不执行写操作。当前验收以本文件顶部的
2026-08-31 Core-live Direct/WebVPN 逐操作记录为准，历史失败和上游波动不覆盖当前结论。

- 基线分支为 `ubaa2`；冻结 `ubaa_old/` 与 `examples/buaa-api/` 的提交分别为
  `6e75e120a26b0eefb3ab4a6f8251d1230db4a62e` 和
  `efb7976bf513f38364b88aeb83d704586cff9b2a`。参考目录只读，`.env.local` 不进入输出、
  日志、暂存或持久化。
- Core 的路由、双路线会话、认证、标准业务和扩展业务已按目标树整理；Cgyy 统一使用
  facade 解析出的 Direct/WebVPN/auto runtime，业务令牌在单一客户端内复用，WebVPN 不隐藏回退
  Direct。SPOC/Judge 诊断复用普通请求并只输出安全计数。
- CLI 只调用 facade，所有普通、诊断、参数和错误输出均使用 schema v2；写命令需要显式
  `--confirm-write`，Core-live 与 `verify-live` 永远不调用写接口。
- 历史阶段曾完成 Cgyy、Bykc、Signin、Ygdk、LibBook 和 Evaluation 的 DTO、解析、协议向量、
  Mock 链与默认拒绝；逐项实时失败只按日期、路线和稳定错误记录，不从失败响应猜测协议。
- 大文件和同名模块迁移遵循书面例外：`session.rs` 已迁移为唯一的 `session/mod.rs`；
  facade、CLI 和大型业务文件暂不强行拆分，下一次触碰时按目标树渐进拆分。
- 2026-08-28 以前的三路线聚合、旧验证器摘要和 Cgyy 直连兼容分支均已被当前决策取代；
  完整细节保留在 Git 历史，当前文档只维护中文结论和仍有证据价值的冲突。

## 历史阶段门槛

历史运行曾通过格式、Clippy、工作区测试、构建、文档、差异检查、CLI E2E、Shell 合同、
`just refs` 和敏感扫描。它们只能说明对应提交的确定性状态；最终结果必须以本周期最后一次
串行 `just check`、CLI 测试、Shell 测试、敏感扫描和 Core-live 实时运行重新确认。
## 2026-08-26：修正后的实时矩阵历史摘要

以下内容只保留历史命令的安全计数、路线元数据和稳定结果，不保存作业 ID、标题、正文、
Cookie、令牌或摘要盐。它们用于解释上游快照波动，不替代 2026-08-31 的当前 Core-live
逐操作证据。

- 认证历史：2026-08-23 的 Direct、WebVPN `auth_status` 均退出 0，只能证明当时认证路线可用，不能证明注销原子性、交互验证边界或任何业务端点。
- 旧版只读聚合：课表、考试、成绩、空教室、SPOC、Judge 曾在三路线命令中退出 0，但当时的 SPOC 可能未真正发送全局空 `kcid` 请求，Judge 详情未覆盖完整题目/分数/状态语义，自动路由还由宿主实现，因此这些结果不再作为当前门槛。
- 路线波动：历史 Judge 曾出现 Direct 65、WebVPN 17 等不同数量，也曾返回 `timeout`、`upstream_changed` 或找不到过期 ID。这些是上游快照变化，不用于固定路线或放宽解析器。
- 旧版确定性门禁：历史 `cargo test --locked --workspace`、Clippy、CLI 二进制测试、测试辅助库测试、Shell 合同、`just refs`、`just check-sensitive` 和 `just check` 均曾通过；它们只描述修复前实现，当前结果以本文件顶部和最终命令为准。
- 2026-08-28 至 2026-08-29 的扩展读取记录了 Signin、Ygdk、Bykc、Cgyy 和 Evaluation 的多次业务认证、上游不可用或语义不符；没有从失败响应猜测新 URL、参数或字段，也没有调用真实写接口。
- 当前验收边界：所有历史聚合摘要均不覆盖逐操作失败；Core-live 只接受显式 Direct/WebVPN，`auto` 只做确定性路由测试，真实写操作永久排除。

## 2026-08-26：历史确定性门槛摘要

- `just refs`：冻结参考提交匹配。
- `just check-sensitive`：未发现凭据、Cookie、令牌、验证码或原始实时材料。
- `just check`：历史运行包含格式、Clippy（`-D warnings`）、工作区测试、Shell 合同、构建、文档和差异检查。
- CLI 二进制和验证器测试均有历史通过记录；这些记录不替代本周期最终串行门禁。
- 确定性门禁与实时矩阵是两类独立证据，Fixture/Mock 通过不能替代真实上游结果。

## 历史认证和只读命令说明

历史命令的功能名、路线和退出码仍保留在 Git 记录中；当前文档只保留上面的中文结论，避免重复维护同一批摘要。
## 当前缺陷与证据缺口

- 生产自动选择已使用经过验收的 TCP 可达性探测和 Core facade 所有权；修正后的 Direct/auto 与最新 WebVPN 聚合证据已接受。若再次出现瞬时 WebVPN Judge 快照失败，仍须严格重跑。
- 交互式验证按设计不支持：Core 回归证明 `config.captcha` 在登录页 GET 后、图片请求和凭据 POST 前返回 `upstream_changed`。实时遇到该页面时应记录为硬门槛上游变化，不得增加提示或绕过。
- 配置持久化已有符号链接、普通文件、唯一临时文件、权限和并发写入的确定性覆盖；真实路由配置行为仍属于后续实时矩阵。
- Classroom 已在确定性测试中匹配冻结的 UA、跳转、DTO 和状态合同，并通过修正后的 Direct/auto 聚合及 WebVPN 显式运行。
- SPOC 传输测试会捕获并解密包含 `kcid=""` 的全局分页请求；修正后的实时诊断在 Direct、WebVPN 和 auto 均观察到一个权威全局页。非空详情/提交语义仍取决于上游是否返回数据。
- Judge 解析、详情、截止时间、分组批量和缓存生命周期均有确定性覆盖；路线本地数量差异只作观察，不得归一化。WebVPN 快照漂移导致的 `judge_cutoff` 失败必须保留并立即重跑。
- Judge 业务认证耗尽已有来源支持的 UC 仲裁：只有 UC 明确 Invalid 才清理所选路线；Valid 或不可用结果保留主会话并返回可重试的 `upstream_unavailable`。
- CLI schema v2 及实时验证器的路线、未解析、聚合、SPOC 身份和 Judge 语义拒绝均有确定性覆盖；Judge 跨请求比较经 stdin 传递，schema 不含交互验证字段或错误码。这些只证明验证器行为，不等同于实时路线成功。
- 范围内所有写操作均有 Core/CLI 协议实现、Mock、向量、解析和确认保护证据；真实提交、上传、答题、预约、签到、成绩变更等副作用请求在本合同中永久禁用。
- Windows 仅所有者目录 ACL 强制仍是基线遗留的发布审计项。

## 后续重跑交接

1. 上游变化后，从整合工作树重新运行 `just refs`、`just check-sensitive`、`just check`、CLI 二进制 E2E 和验证器回归。
2. 如需比较 Judge 摘要，只在当前 Shell 生成一次临时 `UBAA_VERIFY_DIGEST_SALT`，绝不记录其值。
3. 在 Direct 和 WebVPN 重跑 `feature=auth`、`feature=all route=auto`、两条显式路线的每项功能以及两个完整聚合；每个多请求功能必须保持同一解析路线。
4. SPOC 要求 `global_page_count >= 1`，非空时再要求一个详情；Judge 要求课程、原始锚点、过滤后、当前和截止数量，并在有数据时验证一个语义详情。
5. 只记录安全路线、耗时、数量、存在性、稳定错误和盐化摘要。列表快照漂移时保留严格失败并重跑，不得归一化路线差异或放宽子集检查。
随后依据固定 Class 模块证据修正签到业务登录入口、会话头和查询方法，并将
`STATUS=2` 识别为合法空课程结果。修正后 `feature=signin route=direct` 与
`feature=signin route=webvpn` 均通过，返回 0 条课程；签到只读功能的两条真实路线
验收完成，签到提交仍不在范围内。
阳光打卡随后按冻结实现补齐 fragment OAuth code、项目/记录 query 与表单双传、
精确表单编码和业务会话失效重登。最终根因是 token 解码把不含等号的值误解析为空；
改为按独立 URL 值解码后，`feature=ygdk route=direct` 与
`feature=ygdk route=webvpn` 均通过并解析到 11 个项目。阳光打卡只读双路线验收完成。
博雅 WebVPN 登录失败的根因是网关绝对 `Location` 未先还原为业务直连语义，
因此被未知主机检查拒绝。修正为先反解最终地址和跳转目标、校验 `sso/bykc`
主机、再按当前路线包装后，`feature=auth route=webvpn` 与
`feature=bykc route=webvpn` 均通过并解析到 1 条课程；结合此前 Direct 成功结果，
博雅五项只读功能的双路线入口已验证。
# 2026-08-28 执行更新（历史）

- 新增评教 Core 只读链路（CAS 激活、任务/问卷/课程请求、稳定课程 DTO 和进度）以及 CLI `evaluation all|pending` 命令。
- 新增 Bykc Core 选课、退选、签到请求构造和 CLI 命令。所有 Bykc、Cgyy 写命令都要求显式 `--confirm-write`，实时验证绝不执行写操作。
- `just check-sensitive`、`just check`、`cargo test --locked -p ubaa-core --tests` 和 `cargo test --locked -p ubaa-cli --tests` 均通过。
- `just verify-live mode=direct feature=evaluation` 与 `just verify-live mode=webvpn feature=evaluation` 均通过，仅记录脱敏的 `course_count=0` 摘要。
- 剩余验收缺口：写操作的 Core 协议、向量、Mock 和 CLI 默认阻止均已具备，真实写操作永久禁止。当前缺口集中在 Judge 与 Cgyy 的三路线只读实时稳定性，迁移尚未完成。
- 本阶段补齐 LibBook 预约/取消 Core 与 CLI 写入口，并以冻结 golden 向量验证字段顺序、日期派生 AES-128-CBC、PKCS#7 和固定 IV；本阶段提交为后续审查起点。
- LibBook 写链阶段进一步增加了确定性 Mock 端到端测试，覆盖预约 `/v4/space/confirm` 与取消 `/v4/space/cancel` 的顺序、请求体和路线内会话；提交为 `24acd8b`。该证据不等同于真实写操作验收，verify-live 仍永久跳过写入口。
- 新增 Ygdk `submit` Core/CLI 写入口，按冻结实现上传照片后提交打卡表单；默认拒绝，必须显式 `--confirm-write`，未执行真实写操作。
- Ygdk 写入阶段完成了 multipart 上传边界、固定表单字段、CLI 文件输入校验及脱敏请求向量；真实写操作仍永久禁止，最终验收仍受全局实时矩阵门禁约束。
- Cgyy 阶段已提交 `1d25ef2`：完成日期上下文、空间/时段校验、预约上下文创建和最终预约表单的冻结字段实现；验证码挑战、受控图像求解和重试已迁移，CLI 提交入口和真实写验收继续禁止调用。
- Signin 阶段已提交 `0824947`：按冻结协议严格读取 `get_timestamp.action` JSON 的 `timestamp` 字段，并拒绝非 JSON 或空值响应；Signin 写操作仍需补充 CLI 专用安全测试和 Mock 请求断言。
- Signin 写链阶段新增 `crates/ubaa-core/tests/signin.rs` 端到端 Mock 断言，覆盖业务会话跳转、时间戳 GET、签到 URL 查询参数、`sessionId` 请求头和仅含 `id` 的表单；真实签到仍永久禁止。
- Evaluation 阶段已完成最终提交 JSON 信封、问卷题目读取/答案构造和逐课程自动提交链；CLI 提供 `evaluation submit-pending --confirm-write`，并以未确认不访问后端的测试覆盖安全门禁。仍需补充逐请求 Mock/错误向量以及真实只读矩阵收敛，评教写操作永不进入 live 验收。
- 2026-08-28 只读实时矩阵：Direct 全量除 `cgyy_lock_code`（`upstream_unavailable`）外通过；WebVPN 全量的 Cgyy 与 Evaluation 返回 `authentication_required`，其余功能通过。Cgyy WebVPN 与冻结 `localCgyyUpstreamUrl` 的直连语义存在已记录路线冲突，尚未修复。
- Cgyy 验证码阶段已补齐 Core `/api/captcha/check` 的 `pointJson`、挑战 token 和成功判定；敏感验证码字段仅存在当前请求内，CLI 暂不通过 argv 暴露，验证码获取/求解和 WebVPN 直连 runtime 仍未完成。
- Cgyy 验证码挑战阶段已固化 `/api/captcha/get` 的冻结参数及四个响应字段解析测试；图像求解已接入 Core，未将任何默认位移或验证码写入真实请求。
- Cgyy 图像验证码阶段现已接入受控 PNG/JPEG 解码、冻结滑块匹配算法和三次获取/校验重试；挑战图片、密钥和生成凭据仅在当前请求内存中流转，真实写操作仍禁止。
- 2026-08-28 复跑只读矩阵：Direct 除 `cgyy_lock_code=upstream_unavailable` 外通过；WebVPN 的 Grades 为 `upstream_changed`、Judge 为 `invalid_semantics`，Cgyy/Evaluation 为 `authentication_required`，其余已执行项通过。该结果不满足最终实时验收门禁。
- Ygdk 写请求阶段已补充 multipart 上传正文确定性测试，覆盖冻结的 `uid`、`token`、`file` 字段及边界/文件元数据；仍不执行真实打卡写操作。
- Ygdk 写入口现将照片非空、开始/结束时间成对校验前置到业务登录之前；新增无网络回归测试，确保无效写请求不会建立业务会话。
- Ygdk 写链阶段新增完整 Mock 端到端测试，覆盖 OAuth 回调、业务登录、概览四请求、照片 multipart 上传和最终打卡表单；仅使用合成会话与响应，真实打卡仍禁止。
- Evaluation 提交请求已补充固定地址、`Content-Type`、`X-Requested-With` 和 JSON 信封的确定性测试。
- Evaluation `submit_payload` 现将空结果列表校验前置到会话和网络请求之前，新增禁止网络回归测试，避免无效评教写请求触发业务登录。
- Evaluation 写链新增 `crates/ubaa-core/tests/evaluation.rs` Facade 到 HTTP 的 Mock，断言最终提交 URL、JSON 信封、`Content-Type` 与 `X-Requested-With`；真实评教提交仍永久禁止。
- Evaluation 自动逐课程写链新增 Mock，覆盖 CAS 激活、`reviseQuestionnairePattern`、题目读取和 `submitSaveEvaluation` 的冻结顺序，并断言课程标识与 `pjdf=93`；真实评教仍永久禁止。
- Cgyy CLI 已新增 `cgyy submit --request-stdin --confirm-write`，从标准输入读取包含敏感字段的 JSON 请求并在确认前拒绝读取；未执行真实预约。
- Cgyy RouteClient 现补齐 `cgyy_cancel_order` 直接 Facade 入口，并以签名路径/订单标识 Mock 覆盖；聚合与直接宿主均要求显式确认，真实取消仍禁止。

## 2026-08-29 全量只读复测

- Direct：schedule、exam、grades、classroom、spoc、signin、ygdk、libbook、bykc、evaluation 均通过；Judge 返回 `upstream_unavailable`，Cgyy 返回 `timeout`，聚合退出码为 5。
- WebVPN：schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc 均通过；Cgyy 与 Evaluation 返回 `authentication_required`，聚合退出码为 3。
- 两次运行均只调用读接口，未执行任何真实写操作；失败项保留，不以聚合成功掩盖。
- Cgyy 单项复测（2026-08-29）：Direct 站点查询通过（4 个站点），门锁码仍为 `upstream_unavailable`；WebVPN 业务入口稳定返回 `authentication_required`。未跨路线复制 Cookie 或令牌。
- Cgyy RouteClient 现补齐 `cgyy_cancel_order` 直接 Facade 入口，并以签名路径/订单标识 Mock 覆盖；聚合与直接宿主均要求显式确认，真实取消仍禁止。
- Signin 写请求已提取冻结表单构造器并增加只含 `id` 字段的确定性断言；真实签到和写请求 live 验收仍永久禁止。

## 2026-08-29 Bykc 修复后全量只读复测

- Direct：User、schedule、exam、grades、classroom、spoc、signin、ygdk、libbook、bykc、Cgyy 站点查询和 evaluation 成功；Judge 为 `upstream_unavailable`，Cgyy 日期查询为 `upstream_unavailable`，聚合退出码 5。
- WebVPN：User、schedule、exam、grades、classroom、spoc、judge、signin、ygdk、libbook、bykc 成功；Cgyy 与 evaluation 为 `authentication_required`，聚合退出码 3。
- auto：实际解析到 Direct；User、schedule、exam、grades、classroom、spoc、signin、ygdk、libbook、bykc、Cgyy 站点查询和 evaluation 成功；Judge 为 `upstream_unavailable`，Cgyy 用途查询为 `upstream_unavailable`，聚合退出码 5。
- 本轮确认 Bykc 已选课程对象包装修复在三路线聚合中生效；所有命令仅执行读操作，未调用任何真实写接口。上述 Judge/Cgyy 失败仍是最终实时验收未满足项。
- 随后 Direct 单项复测仍在 `cgyy_day` 返回 `upstream_unavailable`、在 `judge_all` 返回 `upstream_unavailable`；站点查询和请求前置均正常，未放宽解析或错误语义。
- WebVPN Cgyy 在切换 Direct 业务 transport 后，站点查询已通过（4 个站点）；用途查询进入业务请求阶段但返回 `upstream_unavailable`，原先的 `authentication_required` 已消除，后续继续复核上游可用性。
- 后续 WebVPN 全量复测：User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 均通过；Cgyy 站点通过（4 个站点），用途查询为 `upstream_unavailable`，聚合退出 5。
- auto Judge 单项复测已通过（课程 5、当前任务 65，详情语义通过）；Direct Judge 同轮仍为 `upstream_unavailable`。Judge 列表存在实时快照波动，继续保留逐路线结果。
- Direct Judge 随后单项复测通过（课程 5、当前任务 65，详情语义通过）；Judge 的 Direct/WebVPN/auto 成功证据现已齐备。
- Direct Cgyy 同轮站点查询通过（4 个站点），日期查询仍为 `upstream_unavailable`；Cgyy 是当前唯一未收敛的只读实时领域。
- `verify-live` 的 Cgyy 分支已改为逐操作继续执行：用途、日期、订单、条件详情和锁码失败会逐项输出脱敏错误，只有依赖标识缺失时才跳过对应详情；末尾返回首个失败码。shell 回归测试已覆盖完整调用顺序。
- 验证器进一步修正站点失败语义：站点响应未通过时不再输出成功摘要，也不从错误信封提取站点标识。三路线 Cgyy 复测显示 WebVPN 站点/用途/订单通过、日期和锁码失败；auto 站点通过、用途/日期/订单/锁码失败；Direct 站点、用途和锁码均受上游失败影响。详情仅在真实订单标识存在时尝试。
- 更新后的三路线全量复测：Direct 的 User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 均通过，Cgyy 用途/订单为 `upstream_unavailable`、日期为 `upstream_changed`、锁码为 `invalid_semantics`；auto 除 Cgyy 日期/锁码 `upstream_unavailable` 外其余通过；WebVPN 除 Cgyy 日期/锁码 `upstream_unavailable` 外其余通过。Judge 三路线均完成完整详情语义校验。
- Direct Cgyy 使用只读日期覆盖 `2026-09-01` 复测后，站点仍通过（4 个），用途/日期/订单仍为 `upstream_unavailable`，锁码为 `invalid_semantics`；失败不随日期窗口改变，暂不能归因于当天无数据。
- CLI 锁码输出已改为仅返回 `{available: boolean}`，Core facade 仍保留旧版不透明 `data`；CLI schema、验证器和脱敏单测均已同步。Direct 复测中锁码现按上游 `upstream_unavailable` 记录，不再误报 `rawData` 结构错误。
- 锁码投影后的 WebVPN/auto 单项复测均未再出现 `rawData` 结构误报：WebVPN 站点成功但用途、日期、订单、锁码均为 `upstream_unavailable`；auto 在站点、用途、订单阶段失败并按依赖规则跳过详情，锁码同样为 `upstream_unavailable`。
- 最新三路线 Cgyy 单项复测：Direct 在站点、用途、订单、锁码均为 `upstream_unavailable`；WebVPN 站点通过后用途、日期、订单、锁码均为 `upstream_unavailable`；auto 在站点、用途、订单失败后结束，均为 `upstream_unavailable`。该波动未提供足够证据修改请求或重试策略。

## 2026-08-29 当前轮三路线全量复测

- Direct 全量使用进程内临时摘要盐执行：User、课表、考试、成绩、教室、SPOC、Judge、Signin、Ygdk、LibBook、Bykc、Evaluation 均通过；Judge 详情语义通过。Cgyy 站点通过（4 个），用途与订单为 `upstream_unavailable`，日期为 `upstream_changed`，聚合退出码 5。
- WebVPN 全量使用进程内临时摘要盐执行：除 Cgyy 外全部只读操作通过，Judge 详情语义通过；Cgyy 站点通过（4 个），用途与订单为 `upstream_unavailable`，日期为 `upstream_changed`，聚合退出码 5。
- auto 全量解析到 Direct：除 Cgyy 外全部只读操作通过，Judge 详情语义通过；Cgyy 站点通过（4 个），用途与订单为 `upstream_unavailable`，日期为 `upstream_changed`，锁码为 `upstream_unavailable`，聚合退出码 5。
- 本轮未调用任何真实写操作。摘要盐仅存在当前 shell，未输出、保存或提交；Cgyy 失败仍是未解决的实时硬门禁，不能宣告迁移完成。

## 2026-08-29 Cgyy 用途类型冻结回退修复

- 根据冻结 `LocalCgyyApiBackend.getPurposeTypes` 的 `runCatching` 语义，动态 `/api/codes` 请求或解析失败时回退十项静态用途类型；无主会话仍返回认证错误。新增单路线 Mock 测试先失败后通过，并补齐 `RouteClient::cgyy_purpose_types` 入口。
- 修复后 Direct、WebVPN、auto 的 Cgyy 用途阶段均不再失败；三路线继续执行到日期/订单阶段。Direct 日期/订单为 `upstream_unavailable`；WebVPN 与 auto 日期及依赖详情为 `upstream_unavailable`。未执行真实写操作。

## 2026-08-29 Cgyy 回退后 Direct 全量复测

- Direct 全量：用途阶段通过静态回退，站点查询成功（4 个）；其余非 Cgyy 只读操作及 Judge 详情语义均通过。Cgyy 日期为 `upstream_changed`、锁码为 `upstream_unavailable`，聚合退出码 6。
- 本轮仍只执行读操作；未改变日期/锁码请求或错误分类，也未执行任何真实写接口。

## 2026-08-29 Cgyy 回退后三路线复测更新

- WebVPN 全量：用途静态回退成功，站点成功（4 个）；其余只读操作及 Judge 详情语义通过，Cgyy 日期和依赖详情为 `upstream_unavailable`，聚合退出码 5。
- auto 全量解析到 Direct：用途静态回退成功，站点成功（4 个）；其余只读操作及 Judge 详情语义通过，Cgyy 日期和订单为 `upstream_unavailable`，聚合退出码 5。
- 两次运行均未调用真实写接口；失败集中在日期/订单实时上游，暂无新协议证据支持修改请求或错误策略。

## 2026-08-29 用途回退后 WebVPN/auto 全量复测

- WebVPN 全量：用途回退成功，站点查询成功（4 个）；其余只读操作及 Judge 详情语义通过。Cgyy 日期和依赖详情为 `upstream_unavailable`，聚合退出码 5。
- auto 全量解析到 Direct：用途回退成功，站点查询成功（4 个）；其余只读操作及 Judge 详情语义通过。Cgyy 日期和订单为 `upstream_unavailable`，聚合退出码 5。
- 本轮仅执行只读请求，未改变协议策略或执行任何真实写操作。

## 2026-08-29 Cgyy 成功信封严格校验

- 对照冻结 `LocalCgyyApi.requestJson`，将 Core Cgyy 信封校验收紧为必须存在且等于 `code=200`；新增缺失码和 `code=0` 的脱敏测试，先失败后通过。
- 该修复仅影响异常响应的解析语义，不改变实时 URL、重定向、签名或缓存；实时日期/订单硬门禁仍未通过，未执行真实写操作。

## 2026-08-29 Cgyy 日期槽位排序

- 对照冻结日期映射补齐每个空间槽位按 `timeId` 升序输出，逆序脱敏响应测试已通过。
- 本轮未改变上游协议或执行真实写操作；Cgyy 日期/订单实时硬门禁仍待上游可用证据。

## 2026-08-29 Cgyy 三路线逐操作复测

- Direct：站点成功（4 个），日期和锁码 `upstream_unavailable`，退出码 5。
- WebVPN：站点成功（4 个），日期 `upstream_changed`，订单和锁码 `upstream_unavailable`，退出码 6。
- auto：解析到 Direct；站点成功（4 个），日期 `upstream_changed`、订单 `upstream_unavailable`，退出码 6。
- 仅记录路由、阶段、计数和稳定错误类别；没有输出凭据、Cookie、令牌、原始响应或个人数据，也没有调用真实写接口。Cgyy 仍是未通过的实时硬门禁。

## 2026-08-29 三路线全量只读复测

- Direct：全部非 Cgyy 功能及 Judge 详情通过；Cgyy 站点 4 个通过，日期/订单 `upstream_unavailable`，退出码 5。
- WebVPN：全部非 Cgyy 功能及 Judge 详情通过；Cgyy 站点 4 个通过，日期/订单 `upstream_unavailable`，退出码 5。
- auto：解析到 Direct，全部非 Cgyy 功能及 Judge 详情通过；Cgyy 站点 4 个通过，日期 `upstream_changed`、订单 `upstream_unavailable`，退出码 6。
- 这些失败项已确认不是本地缺失功能；按冻结实现保持现状并记录，未执行真实写操作。整体迁移仍未完成，待 Cgyy 实时上游恢复或取得新证据。

## 2026-08-29 Cgyy 场馆包装展开

- 对照冻结 `asVenueSiteArray`，Core 现将 `data` 中场馆对象的 `siteList` 展开为扁平站点并继承 `venueName/campusName`；新增脱敏回归测试已通过。
- 扁平响应仍兼容；本轮未改变实时协议或执行真实写操作。Cgyy 日期/订单实时硬门禁仍按上游不可用记录。

## 2026-08-29 LibBook 座位排序

- 对照冻结实现补齐座位 DTO 按 `no` 字符串升序输出；新增脱敏回归测试已通过，LibBook focused suite 6/6 通过。
- 本轮未改变上游请求或执行真实写操作。

## 2026-08-29 LibBook 预约总数回退

- 对照冻结实现补齐预约分页缺少 `total` 时回退为当前条数；新增脱敏回归测试已通过，LibBook focused suite 7/7 通过。
- 本轮未改变上游请求或执行真实写操作。

## 2026-08-29 LibBook 分区编号回退

- 对照冻结实现补齐分区详情缺少区域 ID 时回退请求 ID；新增脱敏回归测试已通过，LibBook focused suite 8/8 通过。
- 本轮未改变上游请求或执行真实写操作。

## 2026-08-29 Bykc 签到配置严格解析

- 对照冻结 `LocalBykcApi.parseSignConfig`，补齐签到点列表的整体失败语义：任一点坐标缺失或类型错误时返回空配置，而不是静默丢弃坏点。
- 新增脱敏测试先失败后通过，Bykc focused suite 9/9 通过；未改变请求协议、加密或实时验收策略。

## 2026-08-29 Ygdk 记录时间戳

- 对照冻结 `LocalYgdkRecordRaw` 与 `timestampToDateTimeText`，补齐记录 Unix 秒时间戳到东八区文本的转换；新增脱敏测试先失败后通过。
- 未改变请求参数、会话、上传或真实写操作策略。

## 2026-08-29 Ygdk 记录图片字段

- 对照冻结 `extractRecordImages`，补齐 `images_fmt` 非空字符串作为单个地址的兼容解析；新增脱敏测试先失败后通过。
- 未改变请求参数、会话、上传或真实写操作策略。

## 2026-08-29 Ygdk 数字字符串时间戳

- 对照冻结 `JsonObject.long`，补齐数字字符串时间戳的东八区格式化；新增脱敏测试先失败后通过。
- 未改变请求参数、会话、上传或真实写操作策略。

## 2026-08-29 三路线全量只读复测（二）

- Direct：User、Schedule、Exam、Classroom、SPOC、Judge（含详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 通过；Grades 本轮未出现失败；Cgyy 在用途/站点后业务阶段返回 `upstream_unavailable`，聚合退出码 5。
- WebVPN：User、Schedule、Classroom、SPOC、Signin、Ygdk、LibBook、Bykc、Cgyy 站点和 Evaluation 通过；Grades 返回 `parse_error`，Judge 严格快照校验返回 `invalid_semantics`；Cgyy 日期、订单、锁码均 `upstream_unavailable`，聚合退出码 6。
- auto：解析到 Direct；User、Schedule、Exam、Classroom、SPOC、Judge（含详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 通过；Grades 返回 `upstream_changed`；Cgyy 用途/站点后订单、锁码等阶段 `upstream_unavailable`，聚合退出码 6。
- 三次运行均只执行认证和读操作，未调用任何真实业务写接口；失败项均保留冻结实现语义，未根据单次实时错误猜测新协议。

## 2026-08-29 LibBook 原语字段兼容

- 对照冻结 `JsonPrimitive.contentOrNull`，补齐图书馆字段由数字/布尔原语转文本的行为；新增数字座位字段脱敏测试先失败后通过。
- 未改变请求、加密、会话或真实写操作策略。

## 2026-08-29 Cgyy 原语字段兼容

- 对照冻结 `LocalCgyyApi.string`，补齐场馆文本字段从数字/布尔原语转为字符串的行为；新增数字站点字段脱敏测试先失败后通过。
- 未改变签名、请求、路线、会话或真实写操作策略。

## 2026-08-29 Signin 写响应状态兼容

- 对照冻结 `jsonStringValue`/`int`，补齐签到写响应中数字字符串 `STATUS` 与 `stuSignStatus` 的解析；新增脱敏单元测试通过。
- 未改变签到登录入口、请求参数或真实写操作禁止策略。

## 2026-08-29 Evaluation 任务身份参数

- 对照冻结 `LocalEvaluationService.fetchTasks`，补齐任务列表 `yhdm` 使用登录资料 `schoolid`、空值回退 `username` 的语义；新增脱敏单元测试并通过。
- 账号标识仅保存在 Core 运行时内存，不写入会话文件、日志或实时证据；未改变评教写操作禁止策略。

## 2026-08-29 Ygdk 原语文本兼容

- 对照冻结 `JsonPrimitive.contentOrNull`，补齐记录文本字段对数字/布尔原语的文本化；新增脱敏测试覆盖 `item_name` 与 `place` 并通过。
- 未改变阳光打卡请求、令牌、上传或真实写操作禁止策略。

## 2026-08-29 Evaluation 原语文本兼容

- 新增布尔原语脱敏测试，先确认旧实现失败，再补齐评教文本字段对数字/浮点/布尔原语的文本化；focused 测试通过。
- 未改变评教请求顺序、提交信封或真实写操作禁止策略。

## 2026-08-29 三路线全量只读复测（原语兼容后）

- Direct：User、Schedule、Exam、Grades、Classroom、SPOC、Judge（含详情）、Signin、Ygdk、LibBook、Bykc、Evaluation 逐项通过；Cgyy 站点通过，日期返回 `upstream_unavailable`，聚合退出码 5。
- WebVPN：上述非 Cgyy 功能逐项通过；Cgyy 站点通过，日期为 `invalid_semantics`、锁码为 `upstream_unavailable`，聚合退出码 1。
- auto：路由解析为 Direct；上述非 Cgyy 功能逐项通过；Cgyy 站点通过，日期与详情为 `upstream_unavailable`，聚合退出码 5。
- 本轮只执行认证和读操作，未调用选课、签到、预约、取消、提交或上传；失败项按用户约定保留冻结实现并记录，未依据单次实时响应猜测新协议。

## 2026-08-29 认证资料持久化边界

- 冻结旧版会在 `LocalAuthSession` 中保存 `schoolid/username`，评教任务等请求可在进程重启后继续发送身份参数。
- UBAA2 当前合同与公开会话契约明确禁止在 `session.json` 持久化用户名或个人资料；Core 因此只在本次进程登录成功后以内存状态提供身份参数，加载旧会话时缺失身份会保持空值并返回上游实际结果。
- 该项是安全契约与旧版持久化语义的已记录边界，不从 Cookie 或未证实响应字段推导身份，也不因此修改上游协议。

## 2026-09-01 Flutter bridge 与生产入口

- `2faa753` 完成 FRB 2.13.0 的 opaque `BridgeClient`、认证/路线 typed DTO、全部 facade 读取
  投影和十项 typed 写入意图；Core 仅新增 `resolve_route_for_feature` 供准备阶段解析实际路线。
- bridge 严格 Clippy、单元测试、全工作区 `just check` 通过；FRB 重新生成零漂移，敏感扫描通过。
- `7bd8fd2` 接入共享 `BridgeBackend`、应用私有配置目录解析和生命周期销毁。官方 Flutter/OHOS
  生产入口改为创建 FRB backend；初始化失败进入安全 `unsupported`，不再以 Demo 数据伪造成功。
- `just flutter-check` 覆盖六个 package/宿主的 analyze 与测试并通过。P1 尚不勾选：完整
  schema 快照、isolate 重建、跨进程会话锁、intent 路线/会话失效测试及逐领域页面仍待实现。
- 本轮没有读取或写入真实账号，也没有传入签名凭据；OHOS API26/DevEco、正式签名和实体设备门禁
  仍按下方历史记录保持阻断。

## 2026-09-01 共享功能详情基础页

- `65b7b48` 将 `FeatureId` 扩展为 8 个普通功能和 4 个高级只读功能，生产 bridge 的 12 个读取
  分支均投影为白名单 `FeatureDetail`；普通/高级导航保持固定顺序。
- 详情页已替换占位卡，覆盖可滚动列表、字段标签/值、本地筛选、loading/empty/failure/retry
  状态和键盘/语义提示；widget 测试验证真实字段渲染。
- 这只是 P3 的共享壳基础，不宣称领域完成：学期/日期/校区筛选、分页/详情层级、缓存 stale
  状态、逐领域 golden/integration 及所有写入确认页仍未完成。

## 2026-09-01 平台安全凭据适配边界

- `5ffc9f6` 增加 `PlatformSecureCredentialStore` 与版本化 `PlatformCredentialVault`，统一校验
  最小凭据、能力探测和稳定错误归约；测试覆盖命名空间、不可用存储和异常隐藏。
- 该提交不伪造平台安全能力：Keychain、Keystore、Credential Manager、Secret Service 和
  HUKS 的原生插件实现及六平台实体设备证据仍未提供，生产宿主默认继续使用安全的 Noop
  （本次会话不持久化），P5/P6 不能勾选。

## 2026-09-01 写入确认状态机

- `1b0d24e` 将 bridge 的十项 typed 写意图投影为共享 `WriteIntent`，并由
  `WriteFlowController`/`WriteConfirmationView` 统一处理摘要、实际路线、警告、过期、单次
  提交和 `outcome_unknown`；提交异常不会自动重试，测试覆盖重复确认、过期和未知结果。
- 该轮只增加确定性状态机和 UI 组件，没有调用真实写接口；各领域的目标选择器、权限窗口、
  照片/位置输入、读取核对和六平台集成仍属于 P4 未完成项。

## 2026-09-01 P1 生命周期、schema 与 stale 证据

- `061c8c2` 修正 `outcome_unknown` 后 app 不再保留旧 intent，并为已成功加载数据的刷新失败
  增加 `stale` 状态、旧详情保留和可重试提示；Flutter 全量分析/测试通过。
- `60686a9` 增加生成 Dart API 的方法/DTO/十项写 operation schema 快照测试、dispose 后重建
  client 测试、过期 intent 消费测试，以及独立 `FileSessionStore` 实例的 OS 文件锁串行测试。
- 这些证据闭合了部分 P1 测试缺口，但 FRB panic 归约、跨 isolate 的真实 native 重建、六平台
  原生安全存储和领域级读取/写入页面仍未闭合。

## 2026-09-01 详情分页与高级写入 typed 入口

- `891f6e4` 为阳光打卡、场馆预约/取消和教学评教补齐 app 层 typed prepare 映射；照片只以内存
  字节进入 bridge DTO，场馆 selection 为封闭 ID 记录，均不接受 raw JSON。
- 共享详情列表新增每页 20 项的本地分页、上一页/下一页语义和筛选后回到第一页的 widget 测试。
  领域学期/日期/校区查询、服务端分页、真实写入 UI 与读取核对仍未完成。

## 2026-09-01 native 链接修复与会话冲突映射

- `60ebb6c` 在 macOS binding podspec 中显式链接 `SystemConfiguration` 并传递到最终 Runner，
  修复 arm64 Rust archive 缺少 `SCDynamicStore`/`SCNetworkReachability` 符号导致的本机失败；
  `just flutter-build` 的 macOS debug 已重新通过，Podfile.lock 校验同步更新。
- 写 intent 路线复核将 Core 已冻结的跨进程会话修订冲突安全投影为 `operation_conflict`，并有
  bridge 单元测试；不会继续提交旧请求。

## 2026-09-01 自动登录与敏感输入生命周期

- `AppController.initialize` 现在仅在安全 `CredentialVault` 返回且用户此前明确开启
  `autoLogin` 时自动提交一次登录；成功或失败都会清空 controller 中的密码，错误凭据会清理
  保险箱。自动登录偏好随最小凭据对象保存，安全存储不可用时复用本次会话但不宣称持久化。
- 登录 UI 在安全存储不可用时同时禁用“记住密码”和“自动登录”选项；没有改变 Core 协议或
  真实写入范围，平台原生插件仍待 P5。
