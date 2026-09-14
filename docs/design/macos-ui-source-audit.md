# 当前 App 与旧版逐按钮源码对照

2026-09-15。冻结旧版6e75e120a26b0eefb3ab4a6f8251d1230db4a62e，示例efb7976bf513f38364b88aeb83d704586cff9b2a。两个引用已现场校验。本文记录首轮源码对照，后续实测发现继续补记；不能替代computer use结果，真实测试见[实测记录](macos-ui-button-results.md)。

旧页面路径统一位于 `ubaa_old/composeApp/src/commonMain/kotlin/cn/edu/ubaa/ui/screens/`；当前UI路径统一位于 `packages/ubaa_ui/lib/src/`。下列每组控制仍需展开执行成功、取消、返回及错误恢复；已有测试路径只提供定位，不自动记作本轮通过。

## 已被失败测试证实的问题

| 问题 | 按钮/触发条件 | 修复前行为 | 旧版/预期与证据 |
|---|---|---|---|
| MAC-01 | 记住密码、自动登录 | macOS原先未实现credentials.*，整组永久禁用 | Keychain接线708a6250及修复3966001e已通过native RED/GREEN和限定复审；真实账号重启选项仍待验 |
| LOG-01 | 开启自动登录，再取消记住密码 | autoLogin仍为true | 旧AuthViewModel.updateRememberPassword会同时关闭；App RED |
| LOG-02 | 已保存密码、auto=false、重新初始化 | 只填账号，密码为空，仍不能手动提交 | 旧loadSavedCredentials同次恢复二者；App RED |
| LOG-03 | 勾选记住并登录，Keychain保存失败 | 已认证成功却回登录页 | 应保留认证并说明保存失败；App RED |
| LOG-04 | 退出并清除，Keychain删除失败 | backend已注销，UI仍停在带用户的主页 | 内存/页面必须清理且不能虚报持久化删除；App RED |
| LOG-05 | 认证错误后Keychain删除也失败 | 异常漏出，未完成错误/阶段恢复 | 必须退出忙碌并保留invalidCredentials；App RED |
| LOG-06 | 点击登录页蓝色项目文字 | 无回调 | 旧LoginScreen:227–236有clickable/openUri；Host文字点击RED |
| LOG-07 | 点击记住密码/自动登录文字 | 不触发选项 | 旧LoginScreen两个Row可点；Host文字点击RED |
| LOG-08 | 退出并清除成功 | 登录页仍保留账号和选项 | 旧logout使用LoginFormState清空；本次明确清除应无残留，App第六项RED |
| LOG-09 | 退出并清除在途时后台恢复 | 新backend重建使旧清除代次失效，未删密码仍正常返回且可显示Home | 独立App与真实Host组件的合成RED；P1，修复轮1已通过限定复审 |
| LOG-10 | 用户改填新账号后后台重建 | 重新恢复旧账号及旧密码 | 独立App RED；P2，修复轮1已通过限定复审 |
| LOG-11 | auto无效凭据且本地删除失败，再后台恢复 | 没有新点击也再次提交同一失败凭据 | App与Host合成RED；P2，修复轮1已通过限定复审 |
| NAV-01 | 普通/高级页卡片的原生语义激活 | 外层带完整标签的button节点没有tap动作，物理点击正常 | 共享组件SemanticsAction.tap行为RED；[来源与最小修复](../migration/source-parity-ui-navigation-actions.md) |

LOG-01至LOG-11的实现和独立复审已在41ece772完成，最终774项Flutter通过；表内RED描述保留为原缺陷证据，真实按钮复验尚未完成。MAC-01原生接线已通过限定复审；NAV-01在02806bf1完成两行修复，24项新动作、81项导航与UI275项通过，规范/质量审查通过，真实窗口仍待复测。

## 按钮映射与后续实操清单

| 领域/稳定编号 | 逐个需操作的控件 | 旧版依据 | 当前接线与边界 |
|---|---|---|---|
| 登录 AUTH-01–07 | 学号、密码、眼睛、记住框/文字、自动框/文字、连接菜单各模式、登录、键盘完成、错误复制、诊断、项目链接、验证码刷新 | auth/LoginScreen.kt、AuthViewModel.kt | app/login.dart→ubaa_host callbacks→AppController；LOG/MAC问题已列。验证码图/刷新没有当前公开能力，不能把输入占位当功能 |
| 首页/主导航 | 菜单、主页、普通、高级、实际路线、关闭说明、刷新、每种待办、成绩变化查看/忽略 | menu/HomeScreen.kt、RegularFeaturesScreen.kt、AdvancedFeaturesScreen.kt、navigation/MainAppScreen.kt | app/home.dart、shell.dart；普通8项/高级4项完整。今日课程旧卡本来只读；待办才有动作。真实首页已有课程及SPOC待办，其他来源按真实数据和合成分支分别验证 |
| 用户/设置 USR/SET | 我的、资料展开/关闭、联系方式显示/遮罩、设置、三主题、三默认路线、统计开关、诊断打开/复制/关闭、退出、清除确认/取消 | auth/UserInfoScreen.kt、menu/SettingsScreen.kt、Sidebar.kt | app/profile*.dart、shell.dart；联系人默认遮罩。本次主题仅运行期生效是现行明确规则。退出失败的内存和持久化边界需LOG-04/08修复 |
| 关于 | 进入、版本读取失败重试、项目、反馈、外链失败复制/关闭、返回 | 旧OtherScreens/About与Sidebar | app/about.dart→PlatformAppInformation；typed AppLink白名单，不发送消息。不能把打开反馈网址当已发送反馈 |
| 课表 SCH-01–04 | 根入口、顶栏周次、上一周、下一周、周列表、学期列表、今日/周/按输入查询、课程格、重叠课程组、详情关闭、查询应用/关闭、刷新 | schedule/ScheduleScreen.kt:157–209/345起、CourseDetailScreen.kt | features/academic/schedule_flow.dart、week_picker.dart、schedule_content.dart。自动链只采唯一当前学期/周；顶栏步进沿原周顺序；详情本地展示不额外读取。真实逐按钮待验 |
| 考试 EX-01–03 | 全部/已安排/未安排、学期选择、已结束展开/收起、单场详情/关闭、搜索/应用、刷新 | exam/ExamScreen.kt | academic.dart、academic/exam_timeline.dart。未知时间仍留未安排/其他；不能因为真实列表为空就算详情通过 |
| 成绩 GR-01–03 | 学期选择、全部/已出/待出、成绩卡详情/关闭、统计重试、刷新、搜索、成绩变化查看/忽略 | grade/GradeScreen.kt、HomeScreen.kt | academic/grades_flow.dart/grade_cards.dart/grade_notice.dart。全部统计独立缓存，搜索不重算统计集合；真实行和统计/返回需CUA |
| 空教室 CLS-01 | 日期日历确认/取消、三个校区、楼层/节次选择/清空、应用、搜索清空、教室详情/关闭、横纵滚动、刷新 | classroom/ClassroomQueryScreen.kt、ClassroomViewModel.kt | classroom_queries.dart、classroom_content.dart。保留原14节与父楼名分组；floor/section是既有本地筛选。空结果被detail_list拦截，不进入details.first；不能仅凭局部实现推断崩溃 |
| SPOC SPC-01–02 | 搜索/清除、每张作业卡、详情刷新/返回、查询模式、已加载作业选择/取消、错误重试 | spoc/SpocAssignmentsScreen.kt、SpocAssignmentDetailScreen.kt | assignments.dart、coursework/assignment_content.dart、assignment_picker.dart→typed assignmentId；旧详情也只显示plainText，不擅自增加附件上传 |
| 希冀 JDG-01–04 | 搜索/清除、包含过期、单项详情、加入批量、查看所选、清空选择、批量结果、返回、刷新、输入键选择 | judge/JudgeAssignmentsScreen.kt、JudgeAssignmentDetailScreen.kt | coursework/assignment_selection.dart与typed有序(courseId,assignmentId)；WebVPN真实父列表无ID，详情/批量不能记真读PASS |
| 博雅 BY-01–05 | 三子菜单、个人资料查询、六状态筛选、状态不限/恢复默认、类别/校区筛选、页码/数量/翻页、课程详情、已选详情、选/退/签到/签退准备及确认取消、统计 | bykc/BykcHomeScreen.kt、BykcCoursesScreen.kt:368–457、BykcCourseDetailScreen.kt、ChosenCourses/Statistics | features/bykc/*→bridge/read/bykc.dart。状态、基本详情、已选权威动作存在；类别/适用校区和完整详情字段缺失，见下方。当前只过滤已加载服务器页，有范围提示 |
| 图书馆 LIB-01–06 | 两子菜单、楼馆/楼层/分区、时段、日期、地图打开/缩放/拖动/重置/关闭、查询座位、选/取消选座、准备预约、确认/取消、预约记录翻页及取消准备 | libbook/LibBookReserveScreen.kt、LibBookViewModel.kt、LibBookBookingsScreen.kt | features/libbook/*；一页父子选择、地图和typed动作已接。时间chips只带id/start/end，日期被主动清空；必须手输日期，是已知关联缺口，需逐项核对正常任务是否可用 |
| 研讨室 CG-01–07 | 三子菜单、校区/日期/站点、房间时段切换、1–2相邻选择、下一步、用途选择、各表单字段、返回/准备/确认/取消、订单详情、翻页/取消、门锁刷新 | cgyy/CgyyReservePickerScreen.kt、FormScreen/OrdersScreen/LockCodeScreen、CgyyViewModel | features/cgyy/*、write/cgyy_form.dart。展示只消费Core资格，用途fallback注明来源。当前门锁只有available；旧密码与预约信息不是已保留能力 |
| 阳光 YG-01–02/W-YG | 提醒开关、记录详情/关闭、加载更多、搜索、概览/记录查询、添加、运动项目、开始/结束选择和取消、地点、系统选图/取消/重选/清除、分享开关、准备/确认/取消 | ygdk/YgdkHomeScreen.kt、YgdkClockinFormScreen.kt | features/ygdk/*、write/ygdk_form.dart、PhotoHandler。macOS照片已接但仍需当前候选CUA；不宣称原生探测等于选图。旧自动选项目/随机时间/透明图默认值与现typed写入合同不同，见下 |
| 课堂签到 SIG/W-SIG | 全部/可签到/已签到、课程详情/关闭、签到、统一确认/取消/返回、刷新 | signin/SigninScreen.kt、HomeScreen.kt | assignments.dart、coursework/course_participation.dart；仅allowed且scheduleId完整可准备；状态与资格不一致明确提示，不凭文案伪造已签到 |
| 评教 EV/W-EV | 全部/待评、课程详情/关闭、单选/取消、多选、全选/取消全选、准备单门/批量、确认/取消、逐项结果、刷新 | evaluation/EvaluationScreen.kt | features/evaluation.dart、coursework/evaluation_row.dart；hasCanonicalTarget同时要求allowed与完整目标；未选时没有空批量栏，不能用0待评真实列表证明提交按钮 |
| 共享 W-COM/导航 | 每个领域的返回/刷新/查询关闭、确认取消、提交忙碌、意图过期、未知结果、回读失败 | 各旧ViewModel/Screen及本次统一安全合同 | common/read_navigator.dart/feature_detail.dart、WriteCoordinator、write/confirmation.dart。每领域需要单独数据/流程证据；不以一次统一确认演示覆盖全部写入 |

## 必须显式保留的旧版能力差异

1. **博雅类别/校区筛选和完整详情**：旧BykcCourseDto已含category/subCategory/audienceCampuses/hasSignPoints；旧LocalBykcApi.kt:524–541明确映射。旧详情另含联系人、适用范围、description和signConfig（:554–580）。当前Core BykcCourse与BridgeBykcCourse均未承载这些字段，UI不存在相应选择/内容；不能从地点或课程名猜类别和校区。此前视觉批次不改Bridge v9的范围已留下该缺口；本次完整功能专项已裁决允许有来源的非敏感typed只读补齐及候选Bridge10，仍未实施或标完成。
2. **图书馆日期与时段关联**：旧mapAreaDetail取原date.list第一项times，同时可用日期先过滤空日；当前公开读法同样展开，UI无法可靠配对。当前Core已经有parse_area_detail_for_day，仅用于预约fresh authority，按目标日唯一匹配且有测试。恢复自然选择应以有证据的typed日期关联为依据，不把所有日期套同一时段，也不让“请明确选择日期”成为没有选择控件的文案。实施前九列和兼容方案已写入[日期来源](../migration/source-parity-ui-libbook-dates.md)。
3. **门锁密码**：旧CgyyLockCodeScreen从qrCode/dueDate/orderView派生，30秒刷新；当前Core CgyyLockCode/Bridge只公开available，旧普通合同只含available。当前菜单“门锁状态”只能准确描述现能力，不能冒充旧“查看密码”已恢复；本专项已裁决新增专用短期视图，保留旧普通接口不变，待实现。
4. **登录验证码**：旧LoginScreen有图片、刷新及输入，当前旧非交互接口遇captcha仍拒绝，生产UI缺完整链。本专项已裁决新增独立交互入口，只传受限像素帧并用opaque句柄绑定答案；此次真实登录未要求captcha，因此登录成功不证明该旧能力存在。
5. **阳光自动默认值**：旧表单允许自动选项目、随机时间及无图时透明图；现Bridge v9要求canonical target/时间和必需照片。这些差异必须单列，不能复刻任意随机字段绕过当前typed确认权威，也不能称所有旧按钮已保留。
6. **原生定位**：当前macOS尚无location.* handler，但冻结旧MainAppScreen:908–915向博雅signCourse同样传null/null，通常由Core沿冻结范围逻辑处理；不能仅凭缺少系统GPS宣称所有旧签到都不可用。需要调用者坐标的条件路径仍明确不可用，真实与合成资格分别验证。
7. **博雅详情补查、动作入口及筛选偏好**：旧已选详情会额外getAllConfig→queryChosenCourse，配置/考勤补查失败整次详情失败；普通课程详情也有签到/签退入口。旧BykcCourseFilterStore按账号跨重启保存筛选，当前只有帧内状态。以上均纳入[博雅实施来源](../migration/source-parity-ui-bykc-details.md)及Task3D/3D2，不能只加字段或局部chips就标全部恢复；新增展示考勤不产生写权限。

## 后续闭环

- Keychain及登录缺口已完成阶段修复/独立审查，继续语义入口、日期时段、博雅完整字段和专用敏感视图。
- 敏感能力的已证字段、短期显示与未知协议边界见[实施前裁决](../migration/source-parity-ui-sensitive-displays.md)；不擅自扩散原始响应或凭据，不把待实现方案标为可用。
- 解锁后逐个操作本表全部当前控件；真实记录/资格不存在时，在显式合成backend的真实macOS生产组件中补按钮流程，不记作真实学校写入。
- 最后按最终源码运行门禁并核对每条证据。当前仍不满足全功能正常使用的完成判定。
