# 全功能 UI/UX 操作清单

审计日期：2026-09-08。静态源码基点：`e6e0e3c5f9c52f9c302742a780da3e67a8251a65`。本文件是 P1 静态盘点，不是 P1 实际操作验收；本代理未运行测试、Flutter、构建或真实请求。运行代理应按末尾证据字段补充本轮结果，不能继承历史 PASS。

依据为 `goal.md`、`AGENTS.md`、`UBAA2.md`、`full-feature-matrix.md`、`readonly-feature-matrix.md`、`source-parity.md`、`flutter-bridge.md` 与下列实际源码。前两份功能矩阵包含历史证据，本文只用来检查遗漏。`UBAA2.md` 的 MCP/公告是路线图示例，当前十二领域目录与 Bridge 没有对应产品操作，不作为已实现功能。

## 读法与定位

每行编号固定，设计和运行证据引用编号，不随导航改名。实现列指代码存在程度，UI 可达列只指静态接线；每行后三项分别为确定性验证、实际渲染、真实只读，本次均未执行。写入真实只读列标“不适用（写入）”，其准备和结果回读也尚未做本轮真实验证。

以下路径前缀仅为排版缩写，拼接后均为仓库相对准确位置：

- `F` = `crates/ubaa-core/src/facade/`；`B` = `crates/ubaa-flutter-bridge/src/api/`；`A` = `packages/ubaa_app/lib/src/`；`U` = `packages/ubaa_ui/lib/src/`。
- `UT` = `packages/ubaa_ui/test/`；`AT` = `packages/ubaa_app/test/`；`CT` = `crates/ubaa-core/tests/`。
- 所有读取链：`F/read/{academic,assignments,services,evaluation}.rs` → `B/read/methods.rs`（评教另有 `B/read/evaluation.rs`）→ 表中 `A/bridge/read/*.dart` → `A/controller/app_controller/refresh.dart` → `U/common/feature_detail.dart`、`detail_list.dart`、`detail_fields.dart` → 表中领域控件。表中“链”明确 facade 方法和 app/UI 文件；Bridge 同名 snake_case 方法生成 Dart camelCase 方法。
- 所有写入链：表中 `F/write/*.rs` → `B/write/prepare.rs` 对应 `prepare_*` → `B/write/commit.rs` 的统一提交 → `A/bridge/write/{prepare,commit,lifecycle}.dart` → 唯一 `A/write/coordinator.dart` → `U/write_callbacks.dart`、`U/write/confirmation.dart` 和领域按钮。共同测试：`UT/write_coordination_test.dart`、`AT/write_coordinator_test.dart`、`AT/app_write_lifecycle_test.dart`、`AT/write_readback_reentry_test.dart`；领域测试列为额外定位，文件存在不表示每行已有充分断言。
- 页面地图：`U/app/shell.dart` 的主页、普通功能、高级功能、我的；普通功能包含课表/考试/成绩/博雅/空教室/SPOC/希冀/图书馆，高级功能包含课堂签到/研讨室预约/阳光/评教。来源 `packages/ubaa_domain/lib/src/feature/catalog.dart`。领域根页后通过查询下拉、参数和“应用筛选”进入子视图，当前不是独立路由；多数详情仍以通用字段列表呈现。
- 从主页默认进入功能卡片为 1 次点击；切换功能分组再进入为 2 次；切换查询视图、选参数、应用筛选需要额外操作。这是静态导航下界，实际任务点击数/重复输入次数待运行记录。

## 认证、个人与全局

| 编号 | 用户任务与当前入口 | 实现位置与约束 | 实现 | UI 可达 | 新设计位置/接入结论 | 对应测试 | 确定性验证 | 实际渲染 | 真实只读 |
|---|---|---|---|---|---|---|---|---|---|
| AUTH-01 | 启动与会话恢复：启动页 | F/auth.rs auth_status；B/client.rs auth_status；A/controller/app_controller.dart；U/app/splash.dart；保留部分路线就绪 | 有 | 自动 | 启动页保留恢复/失败分支 | AT/app_controller/auth.dart；AT/app_controller/lifecycle.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 未执行 |
| AUTH-02 | 双路线准备与账号密码登录：登录页 | F/auth.rs prepare_login/login；B/client.rs；A/bridge/common.dart；U/app/login.dart；密码不入日志，成功清除旧意图 | 有 | 有 | 登录页保留错误与部分成功信息 | AT/bridge_backend_characterization/auth.dart；UT/widgets/shell.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 未执行 |
| AUTH-03 | 交互验证码 | U/app/login.dart 仅 captcha 非空时渲染输入；B/client.rs login 只接受用户名密码，生产无挑战材料 | 占位 | 生产无完整链 | 不新增伪验证码流程；明确 Core 不支持交互挑战，失败保持失败 | Host callbacks验证码参数兼容；Bridge login签名静态核对，无挑战材料不伪造链路 | 静态边界：Bridge仅用户名/密码，无公开挑战材料；保留旧fake输入兼容，不新增假流程 | 生产交互挑战无完整公开链，不能用合成输入冒充可用；明确不接 | 未执行 |
| AUTH-04 | 记住密码：登录选项 | U/app/login.dart；packages/ubaa_host/lib/src/；CredentialVault 能力约束 | 有 | 条件可达 | 登录选项解释本机保存及能力不可用 | packages/ubaa_platform/test/credentials_test.dart；packages/ubaa_host/test/ubaa_app_host/capability_gates.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地） |
| AUTH-05 | 自动登录：登录选项 | A/controller/app_controller.dart；U/app/login.dart；受保存凭据和平台能力约束 | 有 | 条件可达 | 随记住密码控制，不绕过恢复失败 | AT/app_controller/auth.dart；packages/ubaa_host/test/lifecycle_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 未执行 |
| USR-01 | 查看姓名账号：我的 | F/read/services.rs get_user_info；B/client.rs user_info；A/bridge/common.dart _userInfo 只投影 username/name；U/app/profile.dart | 有 | 有 | 个人页摘要 | AT/bridge_backend_characterization/auth.dart；UT/widgets/shell.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 未执行 |
| USR-02 | 查看其余公开资料 | B/client.rs user_info 白名单含 schoolId/email/phone/idCardTypeName；A 的 UserSummary 已同次投影四字段 | 有（A新实现） | 我的→查看账号资料 | 本地展开，联系人默认遮罩；主动显示，不接证件号码 | AT/profile_projection_test.dart；Domain/user_summary_test.dart；UT/profile_details_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 未执行 |
| SET-01 | 默认路线设置：我的→连接模式 | F/routing.rs；B/client.rs set_default_route_policy；A/bridge/common.dart；U/app/profile.dart；请求中拒绝、保存失败保留旧策略、重开后旧 intent 失效 | 有 | 有 | 我的→连接设置 | AT/app_controller/lifecycle.dart；CT/route_policy.rs | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地设置） |
| SET-02 | 查看已认证路线：我的 | B/client.rs route_settings；U/app/profile.dart activeRoutes；不等于本次请求路线 | 有 | 有 | 连接设置与状态摘要 | UT/widgets/shell.dart；AT/app_controller/auth.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 未执行 |
| SET-03 | 查看实际查询路线：功能详情 | A/bridge/read/*.dart resolvedRoute；U/common/feature_detail.dart；每次结果独立 | 有 | 有 | 顶栏唯一实际路线图标；首页按已显示来源聚合，混合路线说明按需查看 | AT/bridge_backend_characterization/read.dart；UT/widgets/feature_details.dart | D5混合路线与短窗口RED后通过，保留原领域actualroute测试 | D5两端各54图及macOS独立实窗，混合路线合成通过 | D5生产首页Direct/WebVPN均逐来源匹配 |
| SET-04 | 明暗主题与选择 | Host lifecycle.dart内存_themeMode；callbacks.dart传值；U/app/profile.dart选择 | 有 | 我的→外观主题 | 系统/浅色/深色，本次运行生效，重启跟随系统 | Host theme_preference_test.dart；UT/widgets/goldens.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地） |
| SET-05 | 匿名统计开关：我的 | U/app/profile.dart；packages/ubaa_platform/lib/；只计功能使用，不包含内容 | 有 | 有 | 我的→隐私；保持默认和声明一致 | packages/ubaa_platform/test/telemetry_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地） |
| SET-06 | 查看/复制本次诊断：登录或我的 | U/app/profile.dart；U/common/error_card.dart；A/controller/app_controller/diagnostics.dart；不自动上传 | 有 | 有 | 错误页与我的→诊断；仅脱敏元信息 | UT/diagnostics_test.dart；AT/diagnostics_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地） |
| AUTH-06 | 退出：我的 | F/auth.rs logout；B/client.rs logout；U/app/profile.dart；保留主动保存凭据，清理会话/意图 | 有 | 有 | 我的底部退出 | AT/app_controller/lifecycle.dart；packages/ubaa_host/test/lifecycle_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 未执行 |
| AUTH-07 | 退出并清除本机账号：我的→确认 | U/app/profile.dart _confirmClearAccount；宿主 CredentialVault 清理；不删除学校数据 | 有 | 有 | 独立破坏性本机确认 | packages/ubaa_host/test/ubaa_app_host/callbacks.dart；packages/ubaa_platform/test/credentials_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地） |
| NAV-01 | 导航、返回与刷新 | U/app/{shell,home}.dart；A/controller/app_controller/refresh.dart；generation/迟到响应保护 | 有 | 有 | 旧三导航与单顶栏；首页今日课表→六来源待办，点击直达原详情，返回保留滚动 | D5 Domain/home_todo、controller/home_sources、reminders、宿主home_navigation | D5 617项Flutter门禁；时间边界/缓存并发/提醒隔离/短路线面板通过 | D5手机平板各54图全复核，macOS16原生及6独立实窗；最终P6仍待验 | D5生产App两路线8来源均通过，已选0条；真实写入0 |

## 十二领域查询与子视图

表中同一领域继承其“链”定位；分组列出到具体 facade 方法，UI 文件均位于 `U/features/`，app 文件均位于 `A/bridge/read/`。列表字段展开也计入对应条目，避免把通用详情卡误当作另一次上游请求。

| 编号 | 用户任务 / 当前查询入口 | 链：facade 方法；app / UI 文件 | 参数与资格约束 | 实现 | UI 可达 | 新设计位置与具体接入建议 | 对应测试 | 确定性验证 | 实际渲染 | 真实只读 |
|---|---|---|---|---|---|---|---|---|---|---|
| SCH-01 | 查看今日课表 / 今日课程 | `F/read/academic.rs schedule_today`；`academic.dart` | 无参数；课程时间地点可空 | 有 | 有 | 课表默认今日，保留空课提示；E3b保留，E3c将收敛自然选择 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | E3b Core与生产App双路线今日1条，只读；首页today未改变 |
| SCH-02 | 选择学期 / 学期列表 | `F/read/academic.rs schedule_terms`；`academic.dart` | 真实 itemCode 与 selected；不猜学期 | 有 | 有 | B2三领域共享typed学期选择；课表学期→周次返回链；E3b保留，E3c将收敛自然选择 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | E3b生产App双路线9学期，选择唯一selected后进入周次；真实写入0 |
| SCH-03 | 选择教学周 / 周次列表 | `F/read/academic.rs schedule_weeks`；`academic.dart` | 必填 term，日期/当前周来自返回 | 有 | 有 | 从选定学期自动提供周次，替代手输；E3b保留，E3c将收敛自然选择 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | E3b生产App双路线19周，选择唯一current进入周表；真实写入0 |
| SCH-04 | 查看周课表 / 周课表 | `F/read/academic.rs schedule_week`；`academic.dart` | term、正整数week；B1已保留起止时间/节次/周几typed字段，未知值不丢弃 | 有 | 有 | E3b旧七日节次网格/原色/完整集合与本地详情；自然学期周选择和真实日期待E3c | UT/academic/schedule_old_test；AT/bridge_backend_characterization/academic_presentation；原生ui_schedule_old | E3b最终667项Flutter、16学业聚焦；color原值/重叠22门/未知时间/大字固定轴/空周位置RED→GREEN | E3b三端r4各14及r5空周各2通过；两端各38图、Mac4操作图已核对，另1Key A限制图非PASS；自然周选择及完整键盘待验 | E3b生产App双路线当周10课程；本地详情额外读取0、草稿/actualroute保留，真实写入0 |
| EXM-01 | 全部考试 / 全部考试 | `F/read/academic.rs exam_arrangement`；`academic.dart` | term；缺省选真实当前学期；无学期为空 | 有 | 有 | 旧日期时间线：已结束默认收起，待考升序/待定随后/未安排最后；座位右侧、低频本地详情；查询仅右上面板 | Domain/exam_timeline_test；UI/academic/old_layout_test与原typed写测试；原生ui_academic_old | E1最终624项Flutter门禁；日期边界、完整结果分组、低频检索及中文委托通过 | E1三端r4全26；最后考试位置r5各14复验；两端各60图及Mac8实窗已复核，完整P6仍待验 | E1生产Direct/WebVPN三视图均empty0；Core-live两路线考试通过，真实考试详情因无记录未执行 |
| EXM-02 | 已安排考试 / 已安排 | `F/read/academic.rs exam_arrangement`；`academic.dart` | 同一信封 arranged，本地视图 | 有 | 有 | 旧日期时间线：已结束默认收起，待考升序/待定随后/未安排最后；座位右侧、低频本地详情；查询仅右上面板 | Domain/exam_timeline_test；UI/academic/old_layout_test与原typed写测试；原生ui_academic_old | E1最终624项Flutter门禁；日期边界、完整结果分组、低频检索及中文委托通过 | E1三端r4全26；最后考试位置r5各14复验；两端各60图及Mac8实窗已复核，完整P6仍待验 | E1生产Direct/WebVPN三视图均empty0；Core-live两路线考试通过，真实考试详情因无记录未执行 |
| EXM-03 | 未安排考试 / 未安排 | `F/read/academic.rs exam_arrangement`；`academic.dart` | 同一信封 notArranged，不伪造考试日期 | 有 | 有 | 旧日期时间线：已结束默认收起，待考升序/待定随后/未安排最后；座位右侧、低频本地详情；查询仅右上面板 | Domain/exam_timeline_test；UI/academic/old_layout_test与原typed写测试；原生ui_academic_old | E1最终624项Flutter门禁；日期边界、完整结果分组、低频检索及中文委托通过 | E1三端r4全26；最后考试位置r5各14复验；两端各60图及Mac8实窗已复核，完整P6仍待验 | E1生产Direct/WebVPN三视图均empty0；Core-live两路线考试通过，真实考试详情因无记录未执行 |
| GRD-01 | 全部成绩 / 全部成绩 | `F/read/academic.rs grades`；`academic.dart` | 真实 term；成绩/绩点可空 | 有 | 有 | 完整学期旧统计→描边课程卡，右上按需查询；低频字段本地详情 ；首页变化提醒沿旧横幅查看/忽略 | Domain grade_statistics；App app_controller/grades；UI academic/grades_old；integration_test/ui_grades_old ；GradeScoreWatch/GradeScoreStore/grade_notice | E2a 641项门禁；完整集合、旧公式、缓存切换/失效和按需面板通过 ；E2b655项通过 | E2a三端r2各18，r3查询各2；两端各50原图/macOS独立8图全复核；完整键盘与全产品P6待验 ；E2b三端各12及66合成原图 | E2a Direct/WebVPN Core-live及生产App：9/9学期82条、三视图和本地详情PASS；真实写入0 ；E2b双路线当前14条基线/重建恢复、变化0 |
| GRD-02 | 已出成绩 / 已出成绩 | `F/read/academic.rs grades`；`academic.dart` | score 非空本地筛选；不按文案猜通过 | 有 | 有 | 完整学期旧统计→描边课程卡，右上按需查询；低频字段本地详情 | Domain grade_statistics；App app_controller/grades；UI academic/grades_old；integration_test/ui_grades_old | E2a 641项门禁；完整集合、旧公式、缓存切换/失效和按需面板通过 | E2a三端r2各18，r3查询各2；两端各50原图/macOS独立8图全复核；完整键盘与全产品P6待验 | E2a Direct/WebVPN Core-live及生产App：9/9学期82条、三视图和本地详情PASS；真实写入0 |
| GRD-03 | 待出成绩 / 待出成绩 | `F/read/academic.rs grades`；`academic.dart` | score 空本地筛选 | 有 | 有 | 完整学期旧统计→描边课程卡，右上按需查询；低频字段本地详情 | Domain grade_statistics；App app_controller/grades；UI academic/grades_old；integration_test/ui_grades_old | E2a 641项门禁；完整集合、旧公式、缓存切换/失效和按需面板通过 | E2a三端r2各18，r3查询各2；两端各50原图/macOS独立8图全复核；完整键盘与全产品P6待验 | E2a Direct/WebVPN Core-live及生产App：9/9学期82条、三视图和本地详情PASS；真实写入0 |
| ROOM-01 | 按日期校区查空教室 | `F/read/academic.rs classroom_search`；`academic.dart` | 严格日期；campus 1/2/3，现显示校区数字 | 有 | 有 | 旧楼栋分组与1–14节表格；固定表头/必要横滚固定教室列；右上按需日期校区楼栋节次，原字段本地详情 | UI academic/classroom_old_test、academic_presentation、classroom_selectors；原生ui_classroom_old/native_test与live_readonly_test | E3a661项；完整列表/分组、ID检索、字段保留、查询归属、草稿及横滚固定列通过 | E3a三端最终r3各14；两端各30及macOS独立4图已检查；CUA面板之后AXError限制另记P6 | E3a Core-live与生产Direct/WebVPN PASS：158→144→27条，实际route一致、详情无额外读取、草稿恢复、业务写入0 |
| ROOM-02 | 楼层筛选 | `F/read/academic.rs classroom_search`；`academic.dart` | floorId/楼层名精确本地匹配 | 有 | 有 | 旧楼栋分组与1–14节表格；固定表头/必要横滚固定教室列；右上按需日期校区楼栋节次，原字段本地详情 | UI academic/classroom_old_test、academic_presentation、classroom_selectors；原生ui_classroom_old/native_test与live_readonly_test | E3a661项；完整列表/分组、ID检索、字段保留、查询归属、草稿及横滚固定列通过 | E3a三端最终r3各14；两端各30及macOS独立4图已检查；CUA面板之后AXError限制另记P6 | E3a Core-live与生产Direct/WebVPN PASS：158→144→27条，实际route一致、详情无额外读取、草稿恢复、业务写入0 |
| ROOM-03 | 节次筛选 | `F/read/academic.rs classroom_search`；`academic.dart` | availableSections 逗号完整令牌匹配，3 不匹配 13 | 有 | 有 | 旧楼栋分组与1–14节表格；固定表头/必要横滚固定教室列；右上按需日期校区楼栋节次，原字段本地详情 | UI academic/classroom_old_test、academic_presentation、classroom_selectors；原生ui_classroom_old/native_test与live_readonly_test | E3a661项；完整列表/分组、ID检索、字段保留、查询归属、草稿及横滚固定列通过 | E3a三端最终r3各14；两端各30及macOS独立4图已检查；CUA面板之后AXError限制另记P6 | E3a Core-live与生产Direct/WebVPN PASS：158→144→27条，实际route一致、详情无额外读取、草稿恢复、业务写入0 |
| SPOC-01 | 作业列表 / 作业列表 | `F/read/assignments.rs spoc_assignments`；`assignments.dart` | 全局权威分页由 Core 聚合；不另造本地分页语义 | 有 | 有 | 按课程分组，突出截止/状态 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| SPOC-02 | 单项内容 / 作业详情 | `F/read/assignments.rs spoc_assignment`；`assignments.dart` | assignmentId；现可手输或从当前结果选编号 | 有 | 有 | 点击父作业直接带 typed ID 入详情 | `UT/widgets/feature_details.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| JDG-01 | 当前作业 / 作业列表 | `F/read/assignments.rs judge_assignments`；`assignments.dart` | includeExpired=false；课程来自作业摘要，无独立课程查询 facade | 有 | 有 | 课程分组/筛选由已有摘要派生，不新增接口 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| JDG-02 | 包含过期作业 / 包含已过期作业 | `F/read/assignments.rs judge_assignments`；`assignments.dart` | includeExpired=true；Core 截止语义不变 | 有 | 有 | 保留当前/含过期筛选，分清截止状态 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| JDG-03 | 单项详情与题目 | `F/read/assignments.rs judge_assignment`；`assignments.dart` | courseId+assignmentId；内容、题目状态、得分/满分 | 有 | 有 | 父列表直达题目详情，编号降为辅助 | `UT/widgets/feature_details.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| JDG-04 | 批量详情 | `F/read/assignments.rs judge_assignment_details`；`assignments.dart` | 非空键列表；现文本输入；Core 去重顺序/缓存负责 | 有 | 有 | 列表多选代替手输键串，保留批量读取 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| SIG-01 | 今日课堂列表 / 全部课程 | `F/read/assignments.rs signin_today`；`assignments.dart` | 当天安排、状态可空；独立 iClass 会话在 Core | 有 | 有 | 旧20内边距横卡：课程时间在左、typed操作或已签图标在右；未知和缺目标说明保留 | Domain/exam_timeline_test；UI/academic/old_layout_test与原typed写测试；原生ui_academic_old | E1最终624项Flutter门禁；日期边界、完整结果分组、低频检索及中文委托通过 | E1三端r4全26；最后考试位置r5各14复验；两端各60图及Mac8实窗已复核，完整P6仍待验 | E1生产Direct/WebVPN各1条；本地详情无额外请求，业务写入0 |
| SIG-02 | 可签到课堂 / 可签到 | `F/read/assignments.rs signin_today`；`assignments.dart` | 本地仅 allowed 资格筛选；未知不等于未签到 | 有 | 有 | 文案改为可签到，保留未知说明 | `UT/widgets/signin_writes.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| SIG-03 | 已签到课堂 / 已签到 | `F/read/assignments.rs signin_today`；`assignments.dart` | 本地 signinEligibility==denied 筛选；须与 Core 派生依据核对，不新请求协议 | 有 | 有 | 已完成分组，状态缺失单独呈现 | `UT/widgets/signin_writes.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| BY-01 | 课程列表 / 课程列表 | `F/read/services.rs bykc_courses`；`bykc.dart` | page/size；app 固定 all=true，Core all 参数未开放选择 | 有 | 有 | 选择课程→整卡详情；顶栏当前页六状态与分页，all=true不改 | D3 App投影 / UI navigation/bykc_content / 宿主boya_navigation | 旧卡片/typed投影/默认状态草稿通过；类别校区缺公开字段 | D3两端各96图、macOS38原生与7独立实窗；见old-d3-native | D3 Core-live及生产App两路线通过；已选0条，真实已选详情未执行 |
| BY-02 | 课程详情 / 课程详情 | `F/read/services.rs bykc_course_detail`；`bykc.dart` | 正整数 id；typed eligibility/actions | 有 | 有 | 课程详情→基本信息/时间→原资格操作 | D3 App投影 / UI navigation/bykc_content / 宿主boya_navigation | typed详情与课程ID对应通过；完整简介等缺公开字段 | D3两端各96图、macOS38原生与7独立实窗；见old-d3-native | D3 Core-live及生产App两路线通过；已选0条，真实已选详情未执行 |
| BY-03 | 已选课程 / 已选课程 | `F/read/services.rs bykc_chosen_courses`；`bykc.dart` | 保留 courseInfo 与目标归属，不由展示字段决定写入 | 有 | 有 | 我的课程→紧凑卡片→私有已选详情 | D3 App投影 / UI navigation/bykc_content / 宿主boya_navigation | recordId/courseId唯一匹配；刷新清旧动作、返回不复活；连续42条通过 | D3两端各96图、macOS38原生与7独立实窗；见old-d3-native | D3 Core-live及生产App两路线通过；已选0条，真实已选详情未执行 |
| BY-04 | 修读统计 / 修读统计 | `F/read/services.rs bykc_statistics`；`bykc.dart` | Core 统计字段；不自行补学分规则 | 有 | 有 | 课程统计→总体净有效次数→分类三列 | D3 App投影 / UI navigation/bykc_content / 宿主boya_navigation | total零/null与独立qualified、空分类保留总值通过 | D3两端各96图、macOS38原生与7独立实窗；见old-d3-native | D3 Core-live及生产App两路线通过；已选0条，真实已选详情未执行 |
| BY-05 | 博雅资料 / 个人资料 | `F/read/services.rs bykc_profile`；`bykc.dart` | 博雅专属资料白名单 | 有 | 有 | 顶栏查询→个人资料 | D3 App投影 / UI navigation/bykc_content / 宿主boya_navigation | 仅原白名单typed资料卡通过 | D3两端各96图、macOS38原生与7独立实窗；见old-d3-native | D3 Core-live及生产App两路线通过；已选0条，真实已选详情未执行 |
| LIB-01 | 楼馆列表 / 馆列表 | `F/read/services.rs libbook_libraries`；`libbook.dart` | day与typed嵌套storeys，保留同名楼层的独立ID | 有 | 有 | 旧版同页楼馆/楼层联动，隐藏页不自动请求 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 561门禁通过；D1c657项/缺省与冲突父标识回归 | D1b手机/平板各58图、macOS18项原生断言及7图独立实窗补验；D1c三端各6/31原图已复核 | D1c Core-live及生产App两路线只读PASS：3馆/首馆2区/1详情含1时段1日期/175座位/2预约；只明确查询，不代表可约；业务写入0 |
| LIB-02 | 馆区和楼层 / 馆区列表 | `F/read/services.rs libbook_areas`；`libbook.dart` | typed父馆/楼层/day；完整手填仍在顶栏面板 | 有 | 有 | 同页换馆/层清除旧分区时段座位，保持实际读取日期 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 561门禁通过；D1c657项/缺省与冲突父标识回归 | D1b手机/平板各58图、macOS18项原生断言及7图独立实窗补验；D1c三端各6/31原图已复核 | D1c Core-live及生产App两路线只读PASS：3馆/首馆2区/1详情含1时段1日期/175座位/2预约；只明确查询，不代表可约；业务写入0 |
| LIB-03 | 分区详情 / 分区详情 | `F/read/services.rs libbook_area_detail`；`libbook.dart` | areaId；营业窗口由 upstream 条件决定 | 有 | 有 | 结构化日期/时段与旧版29分区静态地图；可缩放拖动，未知分区不借图 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 561门禁通过；D1c657项/缺省与冲突父标识回归 | D1b手机/平板各58图、macOS18项原生断言及7图独立实窗补验；D1c三端各6/31原图已复核 | D1c Core-live及生产App两路线只读PASS：3馆/首馆2区/1详情含1时段1日期/175座位/2预约；只明确查询，不代表可约；业务写入0 |
| LIB-04 | 可用日期/时段选择 | `F/read/services.rs libbook_area_detail`；`libbook.dart` | 保留availableDates与时段id/start/end/label；没有日期关联 | 有，受日期关联上限限制 | 时段三字段回填，明确日期后完整查询可达 | 明确日期后查询；不自动复制时段给所有日期 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 561门禁通过；D1c657项/缺省与冲突父标识回归 | D1b手机/平板各58图、macOS18项原生断言及7图独立实窗补验；D1c三端各6/31原图已复核 | D1c Core-live及生产App两路线只读PASS：3馆/首馆2区/1详情含1时段1日期/175座位/2预约；只明确查询，不代表可约；业务写入0 |
| LIB-05 | 座位查询 / 座位查询 | `F/read/services.rs libbook_seats`；`libbook.dart` | areaId/day/start/end；app 另必填 segment 供预约，不能猜编号 | 有 | 有 | 四列座位，选中后才显示摘要；仅独立allowed完整action可准备 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 561门禁通过；D1c657项/缺省与冲突父标识回归 | D1b手机/平板各58图、macOS18项原生断言及7图独立实窗补验；D1c三端各6/31原图已复核 | D1c Core-live及生产App两路线只读PASS：3馆/首馆2区/1详情含1时段1日期/175座位/2预约；只明确查询，不代表可约；业务写入0 |
| LIB-06 | 我的预约 / 预约记录 | `F/read/services.rs libbook_bookings`；`libbook.dart` | page>=1、limit 1–100；保留服务端分页 | 有 | 有 | 旧版紧凑记录；编号进只读详情，canonical取消保留原页 | `UT/widgets/libbook_writes.dart`；`AT/bridge_backend_characterization/read.dart` | 561门禁通过；D1c657项/缺省与冲突父标识回归 | D1b手机/平板各58图、macOS18项原生断言及7图独立实窗补验；D1c三端各6/31原图已复核 | D1c Core-live及生产App两路线只读PASS：3馆/首馆2区/1详情含1时段1日期/175座位/2预约；只明确查询，不代表可约；业务写入0 |
| CG-01 | 研讨室站点 / 站点列表 | `F/read/services.rs cgyy_sites`；`cgyy.dart` | 站点 ID 来自返回 | 有 | 有 | 点站点进入可预约日期与场地 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | 572项Flutter门禁通过；typed投影/自然选择/草稿回归 | D2手机/平板各44图与macOS14项原生及6图实窗；最终P6待验 | Core-live双路线六读PASS；生产App新UI待验 |
| CG-02 | 用途 / 用途类型 | `F/read/services.rs cgyy_purpose_types`；`cgyy.dart` | 来源 upstream/static_fallback 必须明示 | 有 | 有 | 独立用途查询与来源已保留；表单typed用途选择随P5补齐 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | 572项Flutter门禁通过；typed投影/自然选择/草稿回归 | D2手机/平板各44图与macOS14项原生及6图实窗；最终P6待验 | Core-live双路线六读PASS；生产App新UI待验 |
| CG-03 | 日期空间 / 日期空间 | `F/read/services.rs cgyy_day_info`；`cgyy.dart` | 正 siteId、严格日期 | 有 | 有 | 站点带入日期选择，保留返回空间层级 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | 572项Flutter门禁通过；typed投影/自然选择/草稿回归 | D2手机/平板各44图与macOS14项原生及6图实窗；最终P6待验 | Core-live双路线六读PASS；生产App新UI待验 |
| CG-04 | 可预约场地与时段 / 日期空间结果 | `F/read/services.rs cgyy_day_info`；`cgyy.dart` | 全部slot只读保留，独立allowed完整target及唯一归属才可选 | 有 | 有，含不可约/未知/无时段房间 | 旧版房间时段表，固定房间列；不把denied一律称为占用 | `UT/widgets/cgyy_writes.dart`；`AT/bridge_backend_characterization/read.dart` | 572项Flutter门禁通过；typed投影/自然选择/草稿回归 | D2手机/平板各44图与macOS14项原生及6图实窗；最终P6待验 | Core-live双路线六读PASS；生产App新UI待验 |
| CG-05 | 我的订单 / 订单列表 | `F/read/services.rs cgyy_orders`；`cgyy.dart` | 原始page>=0/size；UI一基显示，Core number原样保留后在投影+1 | 有 | 有 | 订单状态与审批状态分层，保持服务端分页 | `UT/widgets/cgyy_cancel_writes.dart`；`AT/bridge_backend_characterization/read.dart` | D2b 574项门禁；零基分页/typed投影回归 | D2b两端各44图与macOS14项原生；保留D2实窗，最终P6待验 | Core-live双路线六读PASS；D2b生产原生双路线首页/分页/详情通过 |
| CG-06 | 订单详情 / 订单详情 | `F/read/services.rs cgyy_order_detail`；`cgyy.dart` | 正订单 ID；现父结果选 ID 或手输 | 有 | 有 | 列表点击直达详情，不重输编号 | `UT/widgets/cgyy_cancel_writes.dart`；`AT/bridge_backend_characterization/read.dart` | D2b 574项门禁；零基分页/typed投影回归 | D2b两端各44图与macOS14项原生；保留D2实窗，最终P6待验 | Core-live双路线六读PASS；D2b生产原生双路线首页/分页/详情通过 |
| CG-07 | 门锁状态 / 门锁状态 | `F/read/services.rs cgyy_lock_code`；`cgyy.dart` | Bridge 只返回 available，不返回秘密锁码 | 有 | 有 | 保留门锁可用性；不能扩为明文锁码展示 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | 572项Flutter门禁通过；typed投影/自然选择/草稿回归 | D2手机/平板各44图与macOS14项原生及6图实窗；最终P6待验 | Core-live双路线六读PASS；生产App新UI待验 |
| YG-01 | 学期概览 / 概览 | `F/read/services.rs ygdk_overview`；`ygdk.dart` | 分类/项目/学期次数与可空目标；重复 target 不允许写入 | 有 | 有 | 学期/本周概要→账号隔离首页提醒开关→记录；右下新增才选择项目 | D4 App投影 / UI ygdk_content / 宿主sports_navigation | D4概要与回读通过；D5提醒4/16旧规则、账号周学期存储和开关往返通过 | D4原生旧首页；D5三端提醒开关与首页同步复验，见old-d5-native | D4 Core-live及生产App Direct/WebVPN均通过；真实写入0 |
| YG-02 | 记录与分页 / 记录列表 | `F/read/services.rs ygdk_records`；`ygdk.dart` | page/size；公开状态/地点/图片数量，不返回图片 URL | 有 | 有 | 旧记录卡→本地低频详情；首页加载更多，独立记录一基分页 | D4 App投影 / UI ygdk_content / 宿主sports_navigation | 同路线追加与局部失败、低频搜索、分页草稿保留通过 | D4手机平板各r1全28场景/r2正常两主题；macOS28原生+4独立实窗，old-d4-native | D4 Core-live及生产App Direct/WebVPN均通过；真实写入0 |
| EV-01 | 全部课程与进度 / 全部课程 | `F/read/evaluation.rs evaluation_all`；`evaluation.dart` | 课程教师、isEvaluated、typed target；重复或不一致 target 降 unknown | 有 | 有 | 评教总览与进度 | `UT/widgets/evaluation_writes.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| EV-02 | 待评课程 / 待评课程 | `F/read/evaluation.rs evaluation_all`；`evaluation.dart` | 同一结果 isEvaluated=false 本地视图 | 有 | 有 | 待评清单，资格原因与状态独立 | `UT/widgets/evaluation_writes.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |

## 全部写入与平台输入

所有写入口要求明确 typed target 与 `allowed`，Core 在 prepare/commit 重新取得最终权威。未知资格不得从中文状态推断为可写。真实业务写入本轮禁止，后续只使用显式脱敏 backend 验证。表中方法均在 `F/write/`；对应 Bridge prepare 名称见 `docs/contracts/flutter-bridge.md` 第 6 节，不把 commit 当作可重复调用的普通按钮。

| 编号 | 操作 / 当前入口 | facade / UI 定位 | 输入与资格约束 | 实现 | UI 可达 | 新设计位置与接入建议 | 对应测试 | 确定性验证 | 实际渲染 | 真实只读 |
|---|---|---|---|---|---|---|---|---|---|---|
| W-BY-01 | 博雅选课 / 准备选课 | `F/write/campus.rs bykc_select_course`；`U/features/bykc.dart` | courseId、选择资格与 fresh authority | 有 | 条件可达 | 课程详情固定操作区 | `UT/widgets/writes.dart`；`B/write/tests/bykc.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-BY-02 | 博雅退选 / 准备退选 | `F/write/campus.rs bykc_deselect_course`；`U/features/bykc.dart` | courseId、退选资格；不复用选课资格 | 有 | 条件可达 | 已选详情独立退选确认 | `UT/widgets/writes.dart`；`B/write/tests/bykc.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-BY-03 | 博雅签到 / 准备博雅签到 | `F/write/campus.rs preflight_bykc_sign_course/bykc_sign_course`；`U/features/bykc.dart` | courseId、lat/lng、signType；平台定位能力与 typed 目标 | 有 | 条件可达 | 签到页解释定位不可用，禁止伪造位置 | `UT/widgets/writes.dart`；`B/write/tests/bykc.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-BY-04 | 博雅签退 / 准备博雅签退 | `F/write/campus.rs preflight_bykc_sign_course/bykc_sign_course`；`U/features/bykc.dart` | 同方法独立 signType/资格，不能把签到当作签退 | 有 | 条件可达 | 同课程签退操作独立显示条件 | `UT/widgets/writes.dart`；`B/write/tests/bykc.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-SIG-01 | 课堂签到 / 准备签到 | `F/write/campus.rs preflight_signin_perform/signin_perform`；`U/features/assignments.dart` | 当天唯一安排、courseId、allowed；单次发送 | 有 | 条件可达 | 旧列表右侧签到→唯一协调器确认；原typed目标不从展示编号重建 | Domain/exam_timeline_test；UI/academic/old_layout_test与原typed写测试；原生ui_academic_old | E1最终624项Flutter门禁；日期边界、完整结果分组、低频检索及中文委托通过 | E1三端显式合成prepare/cancel；完整提交/核对及状态矩阵仍属P5 | 不适用（写入） |
| W-LIB-01 | 图书馆预约 / 准备预约此座位 | `F/write/reservations.rs preflight_libbook_reserve/libbook_reserve`；`U/features/libbook.dart` | areaId/seatId/day/segment/start/end；完整父查询上下文 | 有 | 条件可达 | 座位→确认显示馆区时段，不让用户拼 ID | `UT/widgets/libbook_writes.dart`；`B/write/tests/libbook.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-LIB-02 | 图书馆取消 / 准备取消预约 | `F/write/reservations.rs preflight_libbook_cancel/libbook_cancel_booking`；`U/features/libbook.dart` | typed 记录 target、page/limit；原页刷新 | 有 | 条件可达 | 预约卡片取消，结果留在原分页 | `UT/widgets/libbook_writes.dart`；`B/write/tests/libbook.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-CG-01 | 研讨室预约 / 准备研讨室预约→表单 | `F/write/reservations.rs preflight_cgyy_reservation/cgyy_submit_reservation`；`U/features/cgyy.dart` | 1–2 同空间目标，站点日期时间顺序；电话/主题/用途/人数/正文/参与人及标志 | 有 | 条件可达 | U/write/cgyy_form.dart；用途列表联动，展示完整预约时间 | `UT/widgets/cgyy_writes.dart`；`B/write/tests/cgyy_reservation.rs`（预约）或 `B/write/tests/cgyy_cancel.rs`（取消） | 未执行 | 未执行 | 不适用（写入） |
| W-CG-02 | 研讨室取消 / 准备取消订单 | `F/write/reservations.rs preflight_cgyy_cancel/cgyy_cancel_order_if_route_matches`；`U/features/cgyy.dart` | 正订单 ID、typed 取消资格、原路线核对 | 有 | 条件可达 | 订单详情和订单卡一致动作，核对取消状态 | `UT/widgets/cgyy_cancel_writes.dart`；`B/write/tests/cgyy_reservation.rs`（预约）或 `B/write/tests/cgyy_cancel.rs`（取消） | 未执行 | 未执行 | 不适用（写入） |
| W-YG-01 | 阳光照片打卡 / 准备阳光打卡→表单 | `F/write/campus.rs preflight_ygdk_submit/ygdk_submit_if_route_matches`；`U/features/ygdk.dart` | 分类项目 target、开始结束、地点可选、公开开关、照片 bytes/name/MIME；一次 upload/final | 有 | 条件可达 | U/write/ygdk_form.dart；照片能力缺失说明，未知结果先核对 | `UT/widgets/ygdk_writes.dart`；`B/write/tests/ygdk.rs` | D4新增项目合法性与缺项校验、prepare/cancel通过；P5完整提交未执行 | D4三端合成准备取消；旧独立表单与完整写流程待P5 | 不适用（写入） |
| W-EV-01 | 单门评教 / 勾选一门→准备评教 | `F/write/evaluation.rs preflight_evaluation_submit_courses/evaluation_submit_courses_if_route_matches`；`U/features/evaluation.dart` | 一个完整 typed target；问卷 payload 留 Core | 有 | 条件可达 | 课程确认，说明既定提交语义，不伪装可编辑问卷 | `UT/widgets/evaluation_writes.dart`；`B/write/tests/evaluation.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-EV-02 | 批量评教 / 勾选课程→准备批量评教 | `F/write/evaluation.rs preflight_evaluation_submit_courses/evaluation_submit_courses_if_route_matches`；`U/features/evaluation.dart` | 非空唯一 targets；仅合法待评项；unknown 后停止后续 | 有 | 条件可达 | 多选工具栏及逐项结果：成功/失败/未知/未尝试 | `UT/widgets/evaluation_writes.dart`；`B/write/tests/evaluation.rs` | 未执行 | 未执行 | 不适用（写入） |
| CAP-01 | 照片选择/预览/重新选择 | `U/write/ygdk_form.dart`；`packages/ubaa_host/lib/src/`；`packages/ubaa_platform/lib/` | 平台照片能力，合成图片用于测试；照片不入诊断/证据 | 有 | 条件可达 | 打卡表单原位反馈，权限不可用说明 | `UT/widgets/ygdk_writes.dart`；`packages/ubaa_host/test/ubaa_app_host/capability_gates.dart` | 未执行 | 未执行 | 不适用（本地） |
| CAP-02 | 博雅定位与权限 | `U/app/shell.dart`；`U/write_callbacks.dart`；宿主平台定位适配 | 由平台回调获取，用户拒绝/能力缺失不得提交 | 有 | 条件可达 | 签到/签退前解释位置用途；不新增阳光自动位置能力假象 | `packages/ubaa_host/test/ubaa_app_host/capability_gates.dart`；`UT/widgets/writes.dart` | 未执行 | 未执行 | 不适用（本地） |
| W-COM-01 | 准备→确认→取消/提交 | `A/write/coordinator.dart`；`B/write/lifecycle.rs`；`U/write/confirmation.dart` | 120 秒 intent；取消失败保留阻塞；只用 opaque ID commit；账户/路线切换失效 | 有 | 全写入共用 | 确认页保留目标/实际路线/警示/期限，不能双击发送 | `UT/write_coordination_test.dart`；`AT/write_coordinator/flow.dart`；`AT/write_coordinator/invalidation.dart` | 未执行 | 未执行 | 不适用（写入） |
| W-COM-02 | 提交结果与读取核对 | `A/write/receipt_verifier.dart`；`A/controller/app_controller/{cgyy_readback,ygdk_readback,evaluation_readback}.dart`；`U/write/confirmation.dart` | 成功收据不等于核对；unknown/异常仅一次 caller-pinned 核对，不重发；逐项保留未尝试 | 有 | 写入完成反馈 | 持续可查看结果；回读失败提示人工核对，严禁成功色误导 | `AT/write_readback_reentry_test.dart`；`AT/write_coordinator/readback.dart`；`UT/widgets/evaluation_writes.dart` | 未执行 | 未执行 | 未执行（仅后续回读） |

## 内部能力与不直接暴露的理由

| 编号 | 能力与位置 | 当前投影 / 决定 | 验证边界 |
|---|---|---|---|
| INT-01 | `F/read/assignments.rs spoc_assignments_diagnostics/judge_assignments_diagnostics` | Core/CLI 安全诊断保留；Bridge 不生成诊断方法；普通页面显示业务数据，不能把内部计数当业务成功 | 本轮未执行；`CT/facade.rs` 与 Bridge 边界测试待运行 |
| INT-02 | `F/read/services.rs cgyy_purpose_types_diagnostics` | 普通用途 DTO 只显示来源；诊断详情不直接暴露，static_fallback 不声称实时成功 | 本轮未执行；`AT/bridge_backend/cgyy.dart` |
| INT-03 | `F/read/services.rs cgyy_lock_code`、`B/read/mappers.rs` | 只开放 CG-07 可用状态；秘密锁码不跨 Bridge，不能为“全功能”破坏白名单 | 本轮未执行；`B/read/tests.rs` |
| INT-04 | caller-pinned Cgyy/Ygdk/Evaluation 读取方法 | 供写入后原路线核对；不开放用户任选路线绕过 coordinator 的独立页面 | 本轮未执行；`AT/write_readback_reentry_test.dart` |
| INT-05 | CAS bootstrap/重定向/Cookie/业务登录/验证码自动求解 | 全部留 Core；没有合法用户任务要求显示 Cookie、token、挑战和原始 URL | 本轮未执行；来源记录见 `source-parity.md` |
| INT-06 | Evaluation 问卷获取/答案组装/逐项提交 | 只开放单门/批量 typed target；不添加任意 payload 编辑器，不把未知答案字段带到宿主 | 本轮未执行；`CT/evaluation/authority.rs`、`protocol.rs`、`batch.rs` |
| INT-07 | per-feature override、client open/dispose、会话文件 | 默认策略足够产品设置；opaque client 生命周期由宿主管理，不暴露会话内容与内部覆盖能力 | 本轮未执行；`CT/facade_boundary_architecture.rs`、`AT/public_api_contract_test.dart` |
| INT-08 | 阳光图片 URL、用户完整证件信息、场馆交易号 | Bridge 白名单刻意排除，照片记录只显示图片数量；不新增原图浏览或敏感字段来补表面覆盖率 | 本轮未执行；`B/read/tests.rs` 与 `AT/bridge_backend/ygdk.dart` |

## 文档与源码差异、接入优先级

1. `full-feature-matrix.md` 的“学期/周次 typed 页面”不代表用户已有联动选择器。SCH-02/03/04 目前仍是查询模式+文本参数；P2 应补联动，不改上游请求。
2. 图书馆“时段 typed 查询”在 Bridge 存在，而 LIB-04 app 将日期/时段 join 为文本，座位表单要求手输 segment。属于主任务受阻风险，P1 实际复现后给审查问题定级；P2 先保留完整 typed 时段，再串接楼馆→分区→时段→座位。
3. 十二领域全部有根入口，不等于每个能力已被保真呈现。CG-04 仅剩可约项，LIB-01 丢失楼层结构，SCH-04 丢失周表结构，USR-02 缺少公开资料子页。合理产品能力要在展示层补齐。
4. SET-04 只有跟随系统，无手动主题设置。新增系统/浅色/深色选择属于本地产品能力，不需上游协议修改；默认与持久化需独立设计及测试。
5. `source-parity.md` 已明确交互验证码不支持；登录控件的 captcha 占位不代表生产可用。AUTH-03 保留明确能力边界，不用 fake 登录成功冒充生产验证。
6. 希冀“课程”目前是作业摘要所属课程，没有独立公开课程查询操作。JDG-01 可以按已有课程键分组；不能凭路线图杜撰课程 API。
7. BY-01 的 `all` 固定为 true。若新设计加入“全部/可选”切换，必须先核实冻结语义并扩展 typed query；当前清单不声称已有这个筛选入口。
8. 所有写入按钮已有接线；首要是提升上下文与可用条件解释，保留资格/原路线/未知结果保护。每种写入均需脱敏实际操作，不得用 W-COM-01 一次确认演示覆盖全部领域。

本清单共 84 个稳定编号：76 个用户/平台/共享流程条目，8 个内部能力条目。内部能力的实现均存在；UI 按上述理由不开放（INT-03 仅公开可用状态），确定性验证、实际渲染、真实只读均未执行，后续不应将内部不公开计为入口缺陷。

## 本轮运行证据填写区

下表由执行实际测试/渲染的代理补写。每个编号应至少链接一条适用证据；没有适用证据保持未执行。测试文件是定位，不是执行结果。新设计列当前为接入建议，P2 定稿后补具体规格锚点。

| 证据编号 | 功能编号 | 源码 SHA | 命令/退出码或操作步骤 | 平台/设备 | 逻辑尺寸/DPR/主题 | backend 类型 | 预期/实际结果 | 截图相对路径（脱敏） | 日期 | 结论 |
|---|---|---|---|---|---|---|---|---|---|---|
| 待补 | 待补 | 待补 | 未执行 | 待补 | 待补 | 待补 | 未执行 | 无 | 待补 | 未执行 |

实际任务测量另记：首页起点、到达功能编号、点击数、重复输入字段、返回后参数/滚动保留、三端差异。业务只读证据分别列 Direct 与 WebVPN；fake 实际 App 渲染只证明 UI。真实写入不进入执行计划。

P3A运行索引：`evidence/ui-ux/p3a-native/{iphone,ipad}/manifest.json`，每端38张合成原生截图。对应默认页面观察不包含该领域全部子视图或真实上游；表中真实只读仍未执行。


P4-C实现定位补充：Domain `feature/presentation/{assignment,signin,evaluation}.dart` 与 `feature/overview.dart`；App `bridge/read/{assignments,evaluation}.dart`；UI `features/coursework/`。新增 typed 父子导航、配对选择、勾选顺序、独立全局进度和签到/评教领域布局；原手填、过滤、分页、资格、准备确认路径保留。UI173全量通过，实际运行列尚不升级为C通过，生产App真实只读也未执行。


## O1/O2旧版基准补记

84个稳定编号保留。NAV入口调整为主页／普通功能／高级功能；资料和设置从侧栏进入，手机领域页只保留顶部返回。所有查询和本地搜索由顶栏打开按内容收缩的面板，保存各帧草稿和搜索；实际路线来自当前可见读取帧。未选中时不显示批量栏，确认页去掉重复标题。O1/O2原生第一轮十二领域默认页面与面板已观察，第二轮正在复验；它们不覆盖全部业务子视图，也不替代P4-C/D/P5/P6最终验收。

用户09:10提供旧版原生App进一步确认课程分组、紧凑卡片和研讨室子菜单；O3需恢复对应层级。既有A/B/C数据投影和业务保护保留，旧原生图只对应旧候选。真实账号只读现已明确再次授权；Core本轮Direct40PASS、WebVPN38PASS+2NOT_APPLICABLE，生产App隔离恢复与真实页面核验进行中。

### O3-A课程卡片续验

保持原84项编号。SPOC/希冀列表课程分组只显示一次，整张作业卡进入typed详情；SPOC的score在列表、详情和更多信息均标为“分值”，不当作已得成绩。手机36张明暗原生子视图图已实际观察，精确父查询/二元键顺序/草稿/选择/取消断言通过；完整状态矩阵与平板、macOS仍在执行，不能据此关闭最终验收列。CG-07继续受现有公开available字段约束，旧版“查看密码”子菜单恢复时说明其当前只返回门锁状态。

O3-B更新（本批三端复验已完成，见证据）：EV-01/EV-02在各端均为旧版紧凑课程行；W-EV-01沿“勾选一门→准备评教→确认”进入原单target流程，W-EV-02沿“勾选多门→准备批量评教→确认”进入原有序targets流程。课程详情图标只显示公开字段，单门/批量业务方法与资格不变；不在每张卡重复常驻按钮。原84编号保留。


O3-C恢复博雅3项、图书馆2项、研讨室3项根子菜单；列表/详情顶栏使用当前子视图标题。原84编号及全部查询参数保留，根菜单不显示无结果的本地搜索；结果页搜索/草稿仍保留。CG-07显示门锁available状态，菜单叫“门锁状态”，公开字段限制不变。菜单路径原生复验进行中，LB/CG/BY各明细内容与自然选择仍属P4-D待完成。


O3-D1图书馆实施中（84编号不增减）：LB五视图现保留公开楼馆/楼层/分区/时段/座位/预约结构，原生预约页沿旧版单页选项与四列座位，选择后才出现摘要/准备按钮。记录低频编号放只读详情，取消仍用canonical目标和服务器分页。日期时段关联上限未变；从分区进入查询必须明确日期，完整手填始终保留。手机原生r1/r2存在辅助fixture和滚动定位失败，r3复验中；平板和macOS本批尚未取得终态证据，不填最终完成列。


D1本批复验更新：LIB-01–LIB-06既有五读视图及楼层结构、W-LIB-01/W-LIB-02准备/取消路径在本批手机和平板各46图与macOS15项原生断言通过，558项Flutter门禁通过；Core-live图书馆五读Direct/WebVPN均PASS。旧版静态分区地图归入LIB-03子能力继续补，不新造第85编号；日期关联限制和macOS独立实窗未完成保持显式记录。当前表格历史列未被整体改写成最终通过，最终验收按P6另行核对。

D1b更新：LIB-03静态地图与LIB-04时段原始三字段回填已通过561项门禁、两端各58图与macOS18项原生断言。证据见本轮O3-D1b；日期关联和独立macOS实窗限制不变。

D2本批：CG-01–CG-07读取投影、自然选择和订单详情/分页/取消准备已三端局部复验。保留84编号；表单用途选择和完整写入状态继续P5，最终生产App与全产品P6未完成。

O3-C/D1 macOS补验：锁屏解除后，376d941a生产源码下以显式合成入口完成三根菜单及图书馆地图缩放/拖动/重置、时段草稿、明确日期座位查询、合法选择与准备取消、预约详情与取消准备。分别新增3图与7图原始窗口证据；不替代生产真实只读，也未关闭P5完整提交闭环或UX-O8。84项编号不变。

D2b进行中：CG-05在生产直连发现首页零基偏差，已RED后修App/显示双向转换，574项Flutter门禁与手机平板原生全场景通过，每端44图；本批首页/第二页明暗4图每端复核。真实直连修复后首页15条、详情路线直连；WebVPN及macOS原生复验继续。历史D2合成backend的一基缺陷已纠正，不回填成此前已验证。

D2b生产终态：Direct r1/WebVPN r2正常bootstrap的真实原生分页/详情场景均退出0，真实写入0。旧WebVPN会话启动r1失败保留；CUA输入路径不算通过，P6物理键盘与图书馆WebVPN后续读取仍待补。

D5补充：保持84编号。NAV-01覆盖旧Home六来源，SCH-01补课程顺序和简称，BY-03/CG-05补独立首页读缓存及待办跳转，YG-01恢复本地提醒；W-SIGNIN-01新增首页原typed目标准备取消，完整提交仍在P5。课程成绩变化提醒随学业旧细节继续核对，不把本批六来源等同全部旧首页细节完成。

E1补充：84编号不变。EXM-01–03、SIG-01、W-SIG-01更新到旧布局与本批证据；SIG-02/03共享横卡已继承，但三个显式签到查询的最终原生与生产覆盖仍留P6，不用文本搜索替代。

E2b子能力归GRD-01与既有首页入口，84个稳定编号不增删。E2b首页成绩变化提醒已沿旧横幅实现：首次仅建立独立基线，查看/忽略消费，空集合和失败不覆盖，账号与实际路线隔离，唯一当前学期读取；无通知时实际成绩检查路线也进入唯一顶栏。最终655项Flutter门禁通过，三端各12业务场景通过，手机/平板各30及macOS独立6张合成原图共66张已逐图复核。生产Direct/WebVPN各完成14条首次基线、重读和宿主/存储实例重建恢复；文件600，实测变化0，真实业务写入0。仅证明宿主重建，不冒称完整进程重启或观察到真实学校分数更新。P4其余旧布局及P5–P7继续，完整键盘限制保留。

清单列归位（2026-09-09）：修正E1考试三项、SIG-01及W-SIG-01更新时缺少UI可达单元格造成的证据错列；仅将已记录的E1事实归回对应列，移除被其替代的旧“未验”单元格，未新增任何验收结论。84编号不变。

D1c修复缺省父标识使图书馆分区详情不自动读取的问题：仅使用当前查询返回的原唯一area.id，不回填DTO父字段；非空父标识冲突仍阻止自动进入。10项聚焦、657项Flutter门禁、三端各6场景通过，28张两端原图和macOS独立3图共31张已复核。生产Direct/WebVPN均自动完成楼馆/分区/详情、明确查询175座位和2条预约记录，真实业务写入0；先前超时不标通过。协议与资格不变，跨日期时段关联仍不猜。84编号不变。

E3a空教室已恢复旧楼栋分组与1–14节紧凑表格，绿色只表示原空闲令牌；无服务端分页时完整连续滚动，真实分页保留。日期/校区/楼栋/节次和搜索仅右上按需面板，学院路/沙河/杭州沿旧源码命名；原字段本地详情及检索保留。1.3倍文字必要横滚时固定教室列和楼栋标题，纵滚保持表头。661项Flutter门禁、三端最终r3各14场景通过；两端各30及macOS独立4图，共64合成原图已检查。生产两路线均158条学院路、144条沙河、楼栋节次过滤27条，详情无额外读取、草稿保留、业务写入0。macOS独立CUA操作到查询面板后持续AXError.failure，未完成该独立鼠标路径的楼栋选择，不以原生测试代称；整体P6工具输入复验继续。84编号不变。
