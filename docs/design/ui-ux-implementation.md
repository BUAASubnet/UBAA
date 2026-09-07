# UI/UX 分批实施清单

日期：2026-09-08。设计：`docs/design/ui-ux-redesign.md`；功能编号：`ui-ux-inventory.md`；来源边界：`ui-ux-parity-review.md`。执行者使用 `superpowers:executing-plans`；用户已授权连续推进，本清单不新增审批。此文档只描述待执行工作，不声称 RED/GREEN、原型或运行完成。

目标：保留十二领域和全部 typed 写入语义，完成今日/学习/校园/我的导航、600/1000 响应式布局、最大内容宽度 1200、领域结构展示、状态保留和本次运行主题选择。技术栈沿锁定 Rust/Flutter/Dart/FRB，不升级依赖；Bridge v9、Core 配置 v1、CLI v10、Session v2 保持。纯视觉按现有来源 C1–C9 保持；参数/展示模型接线先写有意义失败测试；不触发真实业务写入。

## 实际接口基线

以下签名已从当前源码核实；后文新增接口均明确为计划，不冒充既存 API。

| 文件 | 当前真实接口/状态 | 使用决定 |
|---|---|---|
| `packages/ubaa_ui/lib/src/app/shell.dart` | `UbaaMainShell` 接收 `Map<FeatureId, FeatureSnapshot> snapshots`、`Future<void> Function(FeatureId, FeatureQuery)? onFeatureQuery`、`initialTab`、各 typed 写回调；State 已有 `_featureQueries` | 保留公开回调；导航名称/分组改变不改 FeatureId 或 wireName |
| `packages/ubaa_ui/lib/src/common/feature_detail.dart` | `_FeatureDetailView` 已接收 `FeatureQuery? query`，但创建 `_FeatureQueryControls` 时未传 query | P3 修复重入时控件恢复；不能仅保存 shell map 却重建空输入 |
| `packages/ubaa_ui/lib/src/common/query_controls.dart` | `_FeatureQueryControls({required feature,required details,required onApply})`；State.initState 将控制器置默认值 | 计划增加受控草稿输入/回调，并用 FeatureQuery 初始值；保留尚未应用字段 |
| `packages/ubaa_ui/lib/src/common/detail_list.dart` | `_FeatureDetailList` 已有 query/pagination/onQuery；State 私有 `_queryController`、`_query`、`_page`、`_selectedEvaluationKeys` | 本地筛选/页码/滚动需提升到稳定页面状态；服务端分页不转成本地页 |
| `packages/ubaa_domain/lib/src/feature/query.dart` | `FeatureQuery` 的日期字段是 `DateTime? date`；含 term/week/page/size/view/premisesId/storeyId/areaId/startTime/endTime/segment/siteId/orderId/assignmentId/courseId/judgeKeys/includeExpired | 不使用审查文本笔误 day；Bridge 的 day 由既有格式化路径提供 |
| `packages/ubaa_domain/lib/src/feature/result.dart` | `FeatureResult`、`FeatureSnapshot` 均含 details/pagination/resolvedRoute；`FeatureDetail` 含 title/subtitle/fields/actions 与 `action<T>()` | 展示结构可新增可空 typed 字段，所有旧构造保持兼容；资格仍 actions |
| `packages/ubaa_domain/lib/src/common/auth.dart` | `UserSummary({required username,displayName,department})` | 计划新增可空 `schoolId/email/phone/idCardTypeName`；department 不填入猜测来源 |
| `packages/ubaa_host/lib/src/callbacks.dart` | `_buildApplication()` 的 MaterialApp 固定 `themeMode: ThemeMode.system` | 改为宿主 State 的内存主题值；onThemeModeChanged 驱动 setState，不写磁盘 |
| `packages/ubaa_app/lib/src/bridge/common.dart` | `_userInfo` 已调用 userInfo，仅映射 username/name，username 空时返回 null | 四项资料来自同次公开结果；不额外请求；局部资料回退若调整须独立 RED |
| `packages/ubaa_app/lib/src/bridge/read/libbook.dart` | `_loadLibbookFeature(BridgeBackend,FeatureId,FeatureQuery,String today)`；楼层和时段被降为计数/文本 | 映射时保留现有公开 DTO，不从 UI 字段反解析 |
| `packages/ubaa_app/lib/src/write/coordinator.dart` | 现有唯一 WriteCoordinator | 保留全部 prepare/cancel/confirm 入口；不在 UI 再造写入状态机 |

## 批次 0：原型与设计闭合（P2）

- [ ] 阅读设计和 84 项映射；将现状截图与问题对应到 `ui-ux-audit.md`，不把通用控件存在当作各领域可用。
- [ ] 以合成数据制作并实际渲染登录/今日、成绩密集列表、作业详情、图书馆首日选择、场馆表单、确认/未知结果、我的代表性原型。每种至少窄/中/宽、明/暗，按合同另补边界与字体 1.3。
- [ ] 观察主次层级、操作可达与软键盘；发现不合理布局先修设计再渲染。不更新旧 golden 来冒充原型。
- [ ] 在 `docs/migration/evidence/2026-09-08-ui-ux.md` 记录原型类别、尺寸、截图、问题与复验。原型工具或文件由执行代理选择；截图放 `docs/design/evidence/ui-ux/` 并标明 prototype。
- [ ] 原型自评闭合后执行后续批次；不等待逐页用户审批，不跳过原型实际渲染。

## 批次 1：状态连续性先 RED，再公共布局（P3）

修改文件：`packages/ubaa_ui/lib/src/app/shell.dart`、`common/feature_detail.dart`、`common/query_controls.dart`、`common/detail_list.dart`、`common/pagination.dart`。按责任可新增 `packages/ubaa_ui/lib/src/common/page_state.dart`，由 `widgets.dart` 显式 part 接入。

消费：现有 `FeatureQuery`、`FeatureSnapshot`、onFeatureQuery。计划产出：UI 私有 `_FeaturePageState`，每 FeatureId 一份，拥有 `FeatureQuery appliedQuery`、`FeatureQuery draftQuery`、`String localSearch`、`int localPage`、`double scrollOffset`、`String? selectedDetailKey`。必要的未解析文本草稿另用该对象私有字段保存，不能把非法输入强转为合法 FeatureQuery。该类型是计划新增，只归 UI，不向 Core/Bridge 输出。

- [ ] 在 `packages/ubaa_ui/test/widgets/shell.dart` 新增“同一已挂载页面跨 599→600→1000→599 后仍保留成绩筛选/当前领域，且查询调用数不变”。不能每个宽度重新 pump 一个全新 Shell 来规避状态问题。
- [ ] 在 `packages/ubaa_ui/test/widgets/queries.dart` 新增“输入学期/周次但未应用→返回分组→重入仍有草稿”；再加“已应用筛选重入恢复视图和输入，刷新提交已应用 query 而非新默认值”。测试用原 harness 记录 query 参数，不仅断言文本存在。
- [ ] 在 `packages/ubaa_ui/test/widgets/feature_details.dart` 新增“列表本地搜索和滚动→进入详情→返回保留；切另一领域不能继承上一领域输入”。服务端分页测试另断言 page/size 原样回调。
- [ ] 先运行以下入口并保存预期 RED：

```sh
# packages/ubaa_ui
"${UBAA_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-3.41.9}/bin/flutter" test test/widgets_test.dart
```

失败应是输入/选中页丢失或新断点导航断言不符；若测试意外通过，检查场景是否真正重建了断点容器/返回重入，不编造失败。

- [ ] 最小修复控件恢复与稳定页面身份；`didUpdateWidget` 仅在领域/受控草稿变化时同步，避免每次加载通知覆盖用户正在输入的文本。
- [ ] 布局切到 600/1000，内容最大 1200；同一 `_FeaturePageState` 跨导航形态使用，不因宽度或主题重新调用 onFeatureQuery。
- [ ] 聚焦 GREEN 后运行完整 widgets；实际 macOS 缩放复验上述场景。清空账户数据的断言与状态保留并存，不把隐私清理当作回归修掉。

## 批次 2：设计系统、任务导航与主题（P3/P4-A）

修改：`packages/ubaa_ui/lib/src/theme.dart`、`app/{shell,home,profile,login,splash}.dart`、`packages/ubaa_domain/lib/src/feature/catalog.dart`、`packages/ubaa_host/lib/src/{ubaa_app_host,callbacks}.dart`。公共布局变量可新增 `packages/ubaa_ui/lib/src/layout.dart`，由 `lib/ubaa_ui.dart` 稳定导出需要的公开内容。

消费：`UbaaTheme.light()/dark()`、现有 FeatureId 目录和宿主 State。计划产出：Shell 新增可选 `ThemeMode themeMode = ThemeMode.system`、`ValueChanged<ThemeMode>? onThemeModeChanged`；Profile 同样接收。宿主 `_themeMode` 默认为 system，设置回调 setState；不放入 AppController、Core 配置或平台持久存储。

- [ ] 先增导航完整性 RED：学习恰有 7 项，校园恰有 5 项，今日十二项均能打开相同 FeatureId。保留现有用例，把“普通功能/高级功能”名称断言迁移为学习/校园，不删除回归场景。
- [ ] 增主题行为 RED：手动浅/深色切换可观察 MaterialApp.themeMode，页面与草稿不丢；重建全新宿主恢复 system。查询/写入计数不变。
- [ ] 实现设计变量和紧凑导航入口；首页摘要只用 snapshots，不新增预取。主操作禁用时使用可读色，不仅降低透明度。
- [ ] 登录窄屏及复杂错误支持滚动；保留真实 backend 失败，禁止自动 Demo 回退。captcha 占位不接伪挑战。
- [ ] 测试 `UT/widgets/{shell,states,accessibility,goldens}.dart`（通过 `widgets_test.dart` 入口）、`packages/ubaa_host/test/ubaa_app_host_test.dart`、`lifecycle_test.dart`。看过新实际渲染后才逐个批准更新确有变化的 golden；保留语义和字体测试。

## 批次 3：领域展示模型与学习领域（P4-B/C）

修改：`packages/ubaa_domain/lib/src/feature/result.dart`、`packages/ubaa_domain/lib/ubaa_domain.dart`、`packages/ubaa_app/lib/src/bridge/read/{academic,assignments,evaluation}.dart`、`packages/ubaa_ui/lib/src/features/{academic,assignments,evaluation}.dart`、`common/detail_list.dart`。按领域新增展示文件 `packages/ubaa_domain/lib/src/feature/presentation.dart`、`packages/ubaa_ui/lib/src/features/academic_content.dart`、`assignment_content.dart`，避免领域渲染堆入入口。

消费：Bridge 已公开课程时间/节次/周几、考试安排、成绩、作业和题目 DTO。计划产出：在 `FeatureDetail` 增加 `FeaturePresentation? presentation`（封闭领域展示基类，具体类型置 presentation.dart），在 app 映射点构造；保留 title/subtitle/fields 供兼容搜索/次要信息，主要渲染通过类型分派。新类型只能包含已公开的字段，不含 raw JSON、URL、FRB 对象或资格推断结果。

- [ ] 学期/周次保留真实 typed 选项；选择器不得为了填默认值重复请求。现有查询列表可作为明确取值步骤，用户选择后带参前进。
- [ ] 先写 App 映射 RED：周几/起止节次/缺值在展示结构中保真，null 不变 0；作业 stable ID 与正文/题目层级分开，批量顺序不变；评教 target 仍沿原一致性检查。
- [ ] UI RED：有合成课程时间地点的课表不是通用“字段：值”列表；成绩宽表/窄卡具有成绩与学分层级；作业点击带正确 typed ID，批量选择不手拼文本键；空教室第 3 节不能命中第 13 节。
- [ ] 实现 SCH/EXM/GRD/ROOM/SPOC/JDG/SIG/EV 全部子视图；保留查询、已安排/未安排、已出/待出、含过期和批量入口。课堂签到虽导航在校园，仍由 assignments 接线。
- [ ] 测试：`packages/ubaa_app/test/bridge_backend_characterization_test.dart`、`bridge_backend_test.dart`、`app_controller_test.dart`；UI `widgets_test.dart` 中 queries/feature_details/signin_writes/evaluation_writes。每领域合成数据实际渲染手机/平板/macOS；长正文和大量题目不只换标题截图。

### 批次 3 实施前 typed 字段与导航补充（2026-09-08 静态核实）

依据实际生成 `packages/ubaa_bindings/lib/src/rust/api/read.dart` 和 App `bridge/read/{academic,assignments,evaluation}.dart`，不改变 Bridge v9。以下都是新增展示模型计划，不是已存在接口。

| 操作 | 当前被压缩或遗漏的真实字段 | 最小投影/导航决定 |
|---|---|---|
| 今日课表 | bizName String；shortName/place/time String? | 独立今日时间地点展示；没有 typed 周几/节次，不从 time 猜周网格。 |
| 学期/周次 | Term itemCode/itemName String、selected bool、itemIndex int；Week term/startDate/endDate/name String、serialNumber int、curWeek bool | 学期点击生成 `FeatureQuery(view:scheduleWeeks,term:itemCode)`；周次点击用已确认父请求 term 与正 serialNumber 生成 scheduleWeek。响应 term 与请求 term 分开保留。 |
| 周课表两分支 | courseCode/courseName String；courseSerialNo/credit/beginTime/endTime/placeName/weeksAndTeachers/teachingTarget/color String?；beginSection/endSection/dayOfWeek int? | 显式 scheduleWeek 与 summary(term,week) 共用投影；1–7 周几有冻结 Schedule.kt 证据，完整合法节次定位网格，缺失/异常保留待确认列表；不解析周次教师混合文本。 |
| 考试 | courseName String；courseNo/examTimeDescription/examDate/startTime/endTime/examPlace/examSeatNo/examType/taskId String?；week/examStatus int? | 独立日期、座位、起止时间，保留单侧时间；arranged 标记来自所属列表，summary 保持两列表原拼接顺序。 |
| 成绩 | courseName/courseCode/score/gradePoint/courseType/scoreType/termCode String?；credit double? | 保留字符串成绩/绩点与 null，不转成 0；已出/待出沿 score 非空规则，不自造排名或平均 GPA。 |
| 空教室 | room id/floorId/name/availableSections String；父 floor.name String | 保留房间、父楼层、原节次字符串和完整逗号令牌；3 不匹配 13；网络仍 campus/date，floor/section 仅本地。 |
| SPOC 列表/详情 | assignmentId/courseId/courseName/title/submissionStatusText String；teacherName/startTime/dueTime/score String?；typed submitted/unsubmitted/unknown；详情再含 contentPlainText/submittedAt String? | 列表点击只向 spocDetail 发送 assignmentId；courseId 保留父归属但不发不存在的 Bridge 参数。正文独立长段落，不能新增附件/提交入口。 |
| Judge 列表/单详情/批量 | 双 ID/标题/课程名/状态文本 String；startTime/dueTime/maxScore/myScore String?；totalProblems/submittedCount int；typed submitted/partial/unsubmitted/unknown；详情 problems 与 contentPlainText String? | 保留双 ID 构造 judgeDetail；批量 JudgeAssignmentQueryKey 按选择/结果顺序，不能按标题排序。每份作业内嵌问题，problem 仅 name/statusText、score/maxScore String?、typed status，没有 problemId。 |
| 评教 | id/kcmc/bpmc String、isEvaluated bool；原 typed target/eligibility；progress 三个 int | 增集合级 typed 进度和课程展示，不复制一套资格；target 继续来自现有已校验 EvaluationSubmitAction，不 split id 或按 isEvaluated 授权。 |

具体接口草案：在新 `domain/src/feature/presentation.dart` 定义 `sealed class FeaturePresentation { const FeaturePresentation(); }`；各类型同文件继承，避免 FRB import。FeatureDetail 计划追加默认 null 的 `FeaturePresentation? presentation`、`FeatureReadNavigation? readNavigation`；现 actions 原样保留。集合级进度可追加 `FeaturePresentation? overview` 到 FeatureResult/FeatureSnapshot，并同步构造、copyWith 和 AppController result→snapshot；未接入时明确延后，不从摘要反解数字。

```dart
// 以下为新类型签名草案，正式实现时显式导出。
final class FeatureReadNavigation {
  const FeatureReadNavigation({required this.feature, required this.query});
  final FeatureId feature;
  final FeatureQuery query;
}
final class ScheduleCoursePresentation extends FeaturePresentation {
  const ScheduleCoursePresentation(this.data);
  final ({String courseCode, String? beginTime, String? endTime,
    int? beginSection, int? endSection, int? dayOfWeek,
    String? place, String? weeksAndTeachers}) data;
}
final class GradePresentation extends FeaturePresentation {
  const GradePresentation(this.data);
  final ({String? courseCode, String? score, String? gradePoint,
    double? credit, String? courseType, String? scoreType, String? termCode}) data;
}
enum AssignmentSubmission { submitted, partial, unsubmitted, unknown }
final class AssignmentProblemPresentation {
  const AssignmentProblemPresentation(this.data);
  final ({String name, String? score, String? maxScore,
    AssignmentSubmission status, String statusText}) data;
}
final class AssignmentPresentation extends FeaturePresentation {
  const AssignmentPresentation(this.data);
  final ({FeatureId feature, String courseId, String assignmentId,
    String courseName, String? teacher, String? startTime, String? dueTime,
    String? score, String? maxScore, int? totalProblems, int? submittedCount,
    AssignmentSubmission status, String statusText, String? contentPlainText,
    String? submittedAt, List<AssignmentProblemPresentation> problems}) data;
}
```

其余 Today/Term/Week/Exam/Classroom/EvaluationCourse/EvaluationProgress 类型按表逐字段定义；列表投影复制为不可变 List。SPOC 没有题目数量/maxScore 时用 null，不填 0。FeatureQuery.copyWith 以 `new ?? old` 保留值，不能传 null 假装清除字段；切子视图构造精确新 query。读导航只来自 DTO，不能沿旧 `_detailFieldValues('作业编号')` 反解；本地考试/成绩/课程展开没有新 Bridge 方法，应零请求。进入作业子详情前保存父 query/结果/滚动，返回不直接抛弃父筛选。

排序边界：time/date/start/due 为展示 String，不承诺时区或可解析格式。初版保持 Core 顺序与 includeExpired 语义；不把 tryParse 失败回退当前时间，不把 score/gradePoint 转为数字排序。周网格只使用范围验证后的 typed 周几/节次。

追加最小 RED：App 在 `bridge_backend_characterization/{read,fakes}.dart` 体系覆盖周二 3–4 节和结束时间两个周表分支、单侧考试时间/座位、非数字绩点/null、3/13 节次精确匹配；SPOC 导航仅 assignmentId，Judge 同标题不同双 ID 的批量 B→A 顺序和问题归属。UI 可新增 academic_presentation_test.dart/assignment_presentation_test.dart：真实点学期→周次一次 query、缺时间课程仍可见、同名作业精确选中父 ID、长正文和嵌套问题可滚动。Evaluation 复用 bridge_backend/evaluation.dart 与 widgets/evaluation_writes.dart，重复 target 仍 unknown；fields 故意含误导 ID 时新 readNavigation 仍只用 typed 来源。上述测试尚未编写或运行。

### 批次 3 的页面上下文约束补充

当前 `common/feature_detail.dart` 在 loading/empty/failure/success/stale 分支间更换内容子树，`_FeatureDetailList` 的搜索与滚动状态会随子树销毁；P3已验证的跨功能返回与断点保留不等于刷新期间也保留。typed 父子导航实施前需单独 RED：搜索/滚动后的父列表→子详情→返回，保留父筛选与位置；同一查询 success→loading→success/stale 不丢本地搜索；空结果不显示旧业务条目。

现 `FeatureSnapshot` 不携带成功结果对应的 query；`AppController._loadFeature` 抛错时沿同一 feature 保留 previous 数据。切换子视图时，不能仅以“同一feature”认定旧数据属于新查询。后续实现必须为父子展示保存明确上下文，或为结果记录来源查询，确保失败后不会把前一子视图冒充当前父列表。新的显示上下文不拥有写资格；迟到响应仍以AppController的generation/lifecycleEpoch为准，账户变化销毁所有个人上下文。不得缓存Widget或绕开既有typed请求，不能因新增本地展示历史改变网络重试/缓存/路由协议。

`UbaaMainShell._buildFeaturePage` 已在详情重试时复用 `_featureQueries[feature]`，这项是现有已修行为，应保留而非误报“所有重试都回到默认”。首页显式全量刷新和失败卡的重试行为另按实际任务测试，不把新typed点选的参数拼回展示字符串。

## 批次 4：校园父子查询与资料（P4-D/A）

修改：`packages/ubaa_domain/lib/src/feature/{result,presentation}.dart`、`common/auth.dart`、`packages/ubaa_app/lib/src/bridge/common.dart`、`bridge/read/{bykc,libbook,cgyy,ygdk}.dart`、`packages/ubaa_ui/lib/src/features/{bykc,libbook,cgyy,ygdk}.dart`、`app/profile.dart`。必要时新增 `packages/ubaa_ui/lib/src/features/library_content.dart`、`reservation_content.dart`、`campus_content.dart`，各自负责领域布局。

消费：真实 `BridgeLibBookLibrary.storeys`、`BridgeLibBookAreaDetail.availableDates/timeSlots`、`BridgeLibBookTimeSlot{id,start,end,label}`；`BridgeUserProfile.schoolId`；现有 typed actions。计划产出：展示层 `LibrarySelectionContext`（明确计划新类型），保存父馆/楼层/分区、可确认日期与时段选项；此结构仅从 DTO 映射生成。所有选中 ID 从结构取得，不能读回“馆 ID”标签值。

- [ ] Library RED：选首日 slot 后 onFeatureQuery 收到 segment=id/startTime=start/endTime=end；变日期/楼层清除旧时段/座位；迟到旧分区响应不能恢复旧 action；非首日不自动复用首日 slot，缺关联阻塞有提示。Core/Bridge 均不改。
- [ ] Cgyy RED：占用与未知时段可展示但无写入口；allowed+合法 target 才有按钮；用途来源 static_fallback 仍明示，门锁仅 available。订单列表/详情保留分页及 typed 取消资格。
- [ ] 资料 RED：schoolId 可空保留，username/name 原映射不退化；department 不凭 schoolId 填院系；同次白名单email/phone默认遮罩、明确查看后仅本地展开，idCardTypeName只显示类型，不新增证件号码。关闭详情/换账号/退出清旧展开状态与资料。
- [ ] 实现楼馆/楼层/首日时段联动与领域卡；保留跨日期显式输入原能力但不声称自动时段联动，完整跨日期能力列阻塞。不扩 Bridge v9、不从 Core 内部类型取数据。
- [ ] 实现博雅统计/已选/资料、场馆站点/用途/日期/订单/门锁、阳光概览/记录全部子视图；数字有来源，目标为空不显示虚构进度比例。
- [ ] 测试：`packages/ubaa_app/test/bridge_backend/{libbook,cgyy,ygdk}.dart` 经 `bridge_backend_test.dart`；`bridge_backend_characterization_test.dart`；UI `widgets/libbook_queries.dart`、`feature_details.dart`、各领域 writes（经 widgets_test.dart）。在三端实际走父子选择及返回。

## 批次 5：全部写入可用性与结果（P5）

修改：`packages/ubaa_ui/lib/src/write/{cgyy_form,ygdk_form,confirmation}.dart`、`write_callbacks.dart`、各 `features/*.dart`、`app/shell.dart`。只在必要展示接线时改 app；`A/write/coordinator.dart` 语义保持，任何行为修复先 RED。

消费：既有 typed starter/preparer、WriteState、WriteIntent、WriteCommitResult。产出：滚动安全表单、明确资格原因、统一确认与可持续查看的逐项结果；不得额外创建 commit 接口或自行保存意图。

- [ ] 每种 W-BY、W-SIG、W-LIB、W-CG、W-YG、W-EV 操作分别验证 allowed/denied/unknown/目标缺失、取消/过期、提交一次、核对失败。复用现有 write_harness 的 typed fake，不接真实业务写。
- [ ] 先 RED：360×800/844×390+键盘下表单继续按钮可滚动到达；准备后改变断点/主题 commit 次数仍为 0；提交双击次数 1；取消失败仍留确认态。
- [ ] RED：批量成功/失败/unknown/unattempted 四态同屏可扫读，不把 unknown 画绿勾；未知后续项不自动再次发送。Ygdk 无照片选择能力显示原因；Bykc 拒定位不发业务写。
- [ ] 实现表单布局与结果展示，保留新账号/路线失效和迟到回调保护；结果页返回不丢父查询但不能恢复旧意图。
- [ ] 聚焦测试入口：

```sh
# packages/ubaa_ui
"${UBAA_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-3.41.9}/bin/flutter" test test/widgets_test.dart test/write_coordination_test.dart
# packages/ubaa_app
"${UBAA_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-3.41.9}/bin/flutter" test test/write_coordinator_test.dart test/app_write_lifecycle_test.dart test/write_readback_reentry_test.dart
```

- [ ] 三端实际操作全部脱敏写入流程，合成照片不含个人数据；integration 通过不能替代截图和操作观察。

## 每批提交与最终门禁（P3–P7）

每批完成聚焦 GREEN、适用实际渲染及修复后，从根执行 `just check-sensitive`、`just check`；检查暂存清单不含敏感/冻结/临时文件，只提交本批文件和证据。本计划不指定未经核实的提交 SHA，不使用 blanket git add。UI 不变的 Rust 检查可按合同覆盖关系记录，不能删现有测试缩减要求。

最终按 `goal.md` 第六节运行 refs/layout/contract/check-strict/CLI E2E/flutter-check/codegen 与 macOS/Android/iOS-simulator/OHOS 无签名门禁；构建后用实际产物路径做 artifact-check。串行 Direct/WebVPN Core-live，生产 App 只读单独记录。真实账号受阻时保留精确 blocker，继续 fake 三端验收，不将假数据渲染写成真实上游成功。

84 项追踪：批次 1 覆盖 NAV-01 与所有查询连续性；批次 2 覆盖 AUTH/SET 与导航；批次 3 覆盖 SCH/EXM/GRD/ROOM/SPOC/JDG/SIG/EV；批次 4 覆盖 USR/BY/LIB/CG/YG；批次 5 覆盖全部 W/CAP；INT-01–08 保持不公开并由边界测试回归。图书馆跨日期关联与其他明确协议缺证据项保留阻塞；不能从清单删除以获得完整。

最终更新清单五列状态、设计实际落点、现行 UI 规格、状态与证据。原型、widget、实际 App fake、Core-live、生产 App 只读分别给结论。手机/平板/macOS 全部必需运行证据未齐时，不标 Goal 全部完成。

## 静态计划自评

接口核对已发现并处理：query 控件缺少传入恢复值；日期实为 date；主题当前固定 system；UserSummary.department 无生产资料来源；Library DTO 无跨日期关联。新增类型明确列为计划，由对应批次产出后才能消费；未要求修改 Core/Bridge 合同。所有功能编号已分配批次，实际运行、原型复验及阶段提交仍待执行。

## P4-B 实际接口与实现回写

已产出 `FeaturePresentation` 及按schedule/exam/grade/classroom拆分的7种模型、`FeatureReadNavigation(feature,query)`、`FeatureReadContext(query?,requestRevision)`。`FeatureDetail.presentation/readNavigation` 可空；`FeatureSnapshot.readContext` 可空兼容旧fake，生产读取明确归属。`FeatureQuery.hasSameParameters`比较全部字段及有序keys；context冻结keys。AppController新增只读 `readCacheEpoch`，Host转发到Shell，不改Bridge9。

UI新增 `academic_content.dart` 与 `schedule_content.dart`，并由 `common/read_navigator.dart` 管理同领域稳定父页帧。查询控件仅按新帧初始query恢复，避免加载通知覆盖未应用草稿。新增实际“刷新当前查询”按钮，默认load与显式summary读取有别；分页仍按原默认query构造下一页，不因内部null语义隐藏服务端分页。

独立review暴露epoch两种时序：无关领域失效带着已退出子页旧快照、写后权威回读先失效后返回不同query；已分别RED后用requestRevision边界修复。写后proof仍从App局部typed回读判断，UI缓存从不回写或作为receipt证据。后续P4-C/D复用本接口时仍需原生逐流程检查，不能把本批学期链路当作所有父子查询已通过。

B1留项（B2已按下文实现，尚待原生验收）：App仍支持同时传term/week时读取周表，而查询下拉当前summary文案为“今日课程”。若在最终设计中收敛该入口，优先让UI显式scheduleToday或给出真实条件提示；保持backend summary兼容和公开参数合同，先补行为用例，不能在不记录语义的情况下删掉旧能力。

## B2 连续实施清单

B1已提交 `83ee9e89`。B2现已实现独立学期选项读取接口： `AppController.loadAcademicTerms({bool forceRefresh=false}) -> Future<FeatureResult>`，复用原scheduleTerms查询但不改全局课表快照，App负责并发合并、错误重试与读取生命周期失效；Host可空 `onLoadAcademicTerms(bool)` 传到共享选择器，用户明确打开才读取。App已完成RED/GREEN和生命周期并发测试；原生选择器验收仍待执行。

- 三学业页选项直接消费TermPresentation.code/selected，选定仅回填学期草稿，由原应用查询提交；保留手填兼容入口，失败/空选项不阻止手填。
- 独立“今日课程”使用已有scheduleToday；summary兼容term+week保留为中性“按输入查询”，不再把周表结果称今日。
- 教室日期选择回填现有严格日期字段；typed楼层/节次选项来自同日期/校区未过滤结果，过滤后仍可切其他楼层，切日期/校区失效。不从展示文本反推ID。ClassroomPresentation已追加同次实际参数queryDate/campus便于识别归属。日期框宽度应包含1.3字体和日期选择按钮。
- 考试按arranged、成绩按既有非空score分组，组内不解析时间/成绩排序；宽考试与教室利用多列/楼层导航。宽成绩优先让主要列与课程标识同时可见，其余信息本地展开，避免横滚失去关键上下文；周表课程需在滚动时保留周几信息。
- 每段仍执行行为RED/GREEN、实际手机/平板运行并复核；macOS人工窗口待解锁后补。B2之前的B1截图只证明B1，不借用为最终设计已完成。


### B2 当前实施与反馈

学期缓存以backend身份、生命周期、readCacheEpoch隔离，同代在途合并；错误不缓存，force只绕过已完成缓存，选择不会修改课表快照。教室选项按typed日期校区累积，切换日期/校区/epoch立即失效；独立审查发现epoch伴新loading被提前标为消费，已RED后仅屏蔽旧snapshot，success可补回新选项。

`academic_tables.dart`将考试/成绩按原有资格字段分组（计数明确为本页），组内维持Core输入顺序；实际内容宽度740起显示4主要列，完整字段本地详情，行高随1.3长文本伸展。`classroom_content.dart`宽布局提供当前页楼层导航，窄布局分楼层卡片；这是本地当前页筛选，原服务查询仍需应用控件。课程卡独立重复星期信息，以免长周列滚动离开列头后失去日期上下文。typed模型不匹配时整页退回通用详情，保留原字段。

日期选择使用锁定Flutter自带的flutter_localizations中文委托，传递增加SDK锁定intl0.20.2；没有升级SDK或既有依赖。8张旧golden仅更新已查看的今日控件收敛/教室日期与选择按钮差异；测试字体方框仅用于结构回归，中文可读性以本批原生图片为准。完整原生验收和本批阶段提交尚未完成。


## P4-C 接续计划（B2原生与阶段提交、P4-A剩余实现后实施）

本段尚未实现。SPOC/希冀、课堂签到、评教遵循既有Bridge白名单，不加后台请求或学校写入。待来源增补复核后，先Domain/App投影RED，再共享UI和Inspection，最后手机/平板实际点击与脱敏写入路径。每阶段只保留一个实施子代理，root独立文件同步工作；不在B2原生候选构建时更改生产源码。

1. `presentation/assignment.dart`分别承载SPOC/希冀列表和详情所需typed ID、时间/状态/分数/正文及题目集合；不要把无ID的题目造为可请求目标。SPOC详情导航只带assignmentId，希冀带courseId+assignmentId；FeatureReadNavigation复用当前返回帧。单份作业一个父模型，题目在父模型内，批量保持Core返回顺序及输入有序键，不按标题去重。
2. `presentation/signin.dart`保留原课程与时间及signStatus；按钮继续只读SigninPerformAction的target/eligibility。是否需要调整状态文案须由冻结来源和Core映射核对后决定，不能从denied泛化业务成功或更改既有过滤语义。
3. `presentation/evaluation.dart`仅表示课程和isEvaluated；EvaluationSubmitTarget仍只在现有action内，不在展示模型复制资格。新增集合overview应独立于details：拟`FeatureOverview`与`EvaluationProgressOverview(total,evaluated,pending)`，SPOC学期上下文也仅用当前响应envelope。经FeatureResult/FeatureSnapshot/copyWith、App正常结果/空结果/失败/写后回读、UI父帧全链传递；新query清旧、同query stale保留、返回父页恢复，明确空结果用当前overview或空，不能沿用上次统计。
4. UI新增`assignment_content.dart`呈现按课程分组的列表与长正文/题目详情；summary列表typed点击或有序多选直接进入查询，现手输编号保留为高级兼容但不再独立拼配课程与作业ID选择。教务任务的列表搜索和批量本地选择应在返回时保持；宽题目表保留题目名、状态、得分、满分，窄卡展示全部字段。课程分组只用已有courseId/name，不额外查询。
5. `FeatureDetailList`新增领域展示分派须保留现action消费者；签到/评教定制头部和课程行应复用唯一WriteCoordinator回调，不能用纯内容组件替掉确认入口、资格提示或逐项结果。集合进度依据typed总数，局部搜索/分页不重算总进度。
6. 关键回归包括同名异ID单项/批量、字段文本被干扰时typed导航仍正确、非标准时间与可空得分/正文、父子返回、过期includeExpired、签到unknown/target缺失、评教重复target/无教师维持拒绝、四态批量结果与只回读不重试。生产App只读及三端完整验收依旧单独计账。


P4-C独立审查补充：overview置于详情列表外，空待评结果仍显示Core总进度；copyWith显式clearOverview，普通映射缺值清除，hadPreviousData纳入有效overview，同query异常保持stale，专用评教回读失败仍按原失败规则。Judge有序多选放父列表State，按双ID保存用户选择顺序，搜索/分页/子页返回保留；响应更新删已不存在键，epoch清空。搜索需覆盖嵌套题目文本，分页单位明确为父作业，保留旧所有可搜索信息。评教固定路线和普通读取共用现有_mapEvaluationResult投影，不改Ygdk/Cgyy回读证明。

签到来源已核对：当前Core仅非空target+status1产生denied，但status1+空target为unknown；记录事实与资格分开展示，状态0/1/其他分别未签/已签/未知，异常组合提示不一致。pending=allowed、completed=denied过滤保持；typed action与fresh预检仍是写权威，不在展示层重算资格。具体冻结证据见source-parity-ui-coursework.md。


P4-A资料一致性裁决已更新设计：新增4个可空字段而非仅schoolId，保留现username为空返回null及preferredName规则。UI账号资料详情不新增网络读取；先RED验证可空白名单投影、默认遮罩/主动展开/关闭恢复、相同账号资料更新与账号切换不会残留旧展开内容。所有原生资料证据使用synthetic，真实只读不保存原始个人页面截图。学校标识标签不推断为院系或学校名称。


P4-A共享补项：B2手机实屏复核确认现查询头虽可滚动，却未提供设计要求的折叠。小于600时加入“查询条件”收起/展开，初始保持展开以保留当前参数发现性，宽屏继续直接显示；不自动应用或修改草稿。面板隐藏期间仍保留State，恢复宽度、收起再展开与父返回不触发query、不改变结果。先RED验证草稿/搜索/已应用参数连续性与零请求，再在手机原生实际操作。此项追踪UX-13，P3补充验收重新保持待办，B2领域展示的已通过证据仍有效。
