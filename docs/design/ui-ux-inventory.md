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
- 页面地图：`U/app/shell.dart` 的主页、普通功能、高级功能、我的；普通功能包含课表/考试/成绩/博雅/空教室/SPOC/希冀/图书馆，高级功能包含课堂签到/场馆/阳光/评教。来源 `packages/ubaa_domain/lib/src/feature/catalog.dart`。领域根页后通过查询下拉、参数和“应用筛选”进入子视图，当前不是独立路由；多数详情仍以通用字段列表呈现。
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
| SET-03 | 查看实际查询路线：功能详情 | A/bridge/read/*.dart resolvedRoute；U/common/feature_detail.dart；每次结果独立 | 有 | 有 | 结果页弱化状态信息；保留 Direct/WebVPN 事实 | AT/bridge_backend_characterization/read.dart；UT/widgets/feature_details.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 未执行 |
| SET-04 | 明暗主题与选择 | Host lifecycle.dart内存_themeMode；callbacks.dart传值；U/app/profile.dart选择 | 有 | 我的→外观主题 | 系统/浅色/深色，本次运行生效，重启跟随系统 | Host theme_preference_test.dart；UT/widgets/goldens.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地） |
| SET-05 | 匿名统计开关：我的 | U/app/profile.dart；packages/ubaa_platform/lib/；只计功能使用，不包含内容 | 有 | 有 | 我的→隐私；保持默认和声明一致 | packages/ubaa_platform/test/telemetry_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地） |
| SET-06 | 查看/复制本次诊断：登录或我的 | U/app/profile.dart；U/common/error_card.dart；A/controller/app_controller/diagnostics.dart；不自动上传 | 有 | 有 | 错误页与我的→诊断；仅脱敏元信息 | UT/diagnostics_test.dart；AT/diagnostics_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地） |
| AUTH-06 | 退出：我的 | F/auth.rs logout；B/client.rs logout；U/app/profile.dart；保留主动保存凭据，清理会话/意图 | 有 | 有 | 我的底部退出 | AT/app_controller/lifecycle.dart；packages/ubaa_host/test/lifecycle_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 未执行 |
| AUTH-07 | 退出并清除本机账号：我的→确认 | U/app/profile.dart _confirmClearAccount；宿主 CredentialVault 清理；不删除学校数据 | 有 | 有 | 独立破坏性本机确认 | packages/ubaa_host/test/ubaa_app_host/callbacks.dart；packages/ubaa_platform/test/credentials_test.dart | A对应App/Domain/UI/Host门禁通过（总500）；资料profile_projection/user_summary/profile_details及既有auth/lifecycle/diagnostics用例 | A两设备各15业务+1合同通过；资料/成功恢复独立补充，总79原图复核；跨账号旧确认由widget单列，最终macOS待验 | 不适用（本地） |
| NAV-01 | 导航、返回与刷新 | U/app/{shell,home}.dart；A/controller/app_controller/refresh.dart；generation/迟到响应保护 | 有 | 有 | P2 按学习/校园任务分组；跨宽度保留页面及输入 | UT/widgets/shell.dart；UT/widgets/states.dart；AT/app_controller/race.dart | 导航3项+连续性5项+刷新/键盘/主题7项通过；UI122回归通过 | P3/P3A手机平板12入口与草稿返回通过；P3B平板真实旋转、手机键盘/stale通过；macOS缩放/平板分屏待验 | 未执行 |

## 十二领域查询与子视图

表中同一领域继承其“链”定位；分组列出到具体 facade 方法，UI 文件均位于 `U/features/`，app 文件均位于 `A/bridge/read/`。列表字段展开也计入对应条目，避免把通用详情卡误当作另一次上游请求。

| 编号 | 用户任务 / 当前查询入口 | 链：facade 方法；app / UI 文件 | 参数与资格约束 | 实现 | UI 可达 | 新设计位置与具体接入建议 | 对应测试 | 确定性验证 | 实际渲染 | 真实只读 |
|---|---|---|---|---|---|---|---|---|---|---|
| SCH-01 | 查看今日课表 / 今日课程 | `F/read/academic.rs schedule_today`；`academic.dart` | 无参数；课程时间地点可空 | 有 | 有 | 课表默认今日，保留空课提示 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| SCH-02 | 选择学期 / 学期列表 | `F/read/academic.rs schedule_terms`；`academic.dart` | 真实 itemCode 与 selected；不猜学期 | 有 | 有 | B2三领域共享typed学期选择；课表学期→周次返回链 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| SCH-03 | 选择教学周 / 周次列表 | `F/read/academic.rs schedule_weeks`；`academic.dart` | 必填 term，日期/当前周来自返回 | 有 | 有 | 从选定学期自动提供周次，替代手输 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| SCH-04 | 查看周课表 / 周课表 | `F/read/academic.rs schedule_week`；`academic.dart` | term、正整数week；B1已保留起止时间/节次/周几typed字段，未知值不丢弃 | 有 | 有 | 学期与周次联动；typed 保留时空字段形成周表 | `UT/widgets/feature_details.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| EXM-01 | 全部考试 / 全部考试 | `F/read/academic.rs exam_arrangement`；`academic.dart` | term；缺省选真实当前学期；无学期为空 | 有 | 有 | 保持Core组内顺序、突出时间；B2宽时间表与分组已实现 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| EXM-02 | 已安排考试 / 已安排 | `F/read/academic.rs exam_arrangement`；`academic.dart` | 同一信封 arranged，本地视图 | 有 | 有 | 明确日期地点座位 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| EXM-03 | 未安排考试 / 未安排 | `F/read/academic.rs exam_arrangement`；`academic.dart` | 同一信封 notArranged，不伪造考试日期 | 有 | 有 | 独立待安排分组 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| GRD-01 | 全部成绩 / 全部成绩 | `F/read/academic.rs grades`；`academic.dart` | 真实 term；成绩/绩点可空 | 有 | 有 | 课程/学分/成绩/绩点结构，宽屏表格 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| GRD-02 | 已出成绩 / 已出成绩 | `F/read/academic.rs grades`；`academic.dart` | score 非空本地筛选；不按文案猜通过 | 有 | 有 | 成绩页筛选 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| GRD-03 | 待出成绩 / 待出成绩 | `F/read/academic.rs grades`；`academic.dart` | score 空本地筛选 | 有 | 有 | 待出分组保留缺值 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| ROOM-01 | 按日期校区查空教室 | `F/read/academic.rs classroom_search`；`academic.dart` | 严格日期；campus 1/2/3，现显示校区数字 | 有 | 有 | 日期选择器；校区命名须有证据映射 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| ROOM-02 | 楼层筛选 | `F/read/academic.rs classroom_search`；`academic.dart` | floorId/楼层名精确本地匹配 | 有 | 有 | 从结果提取 typed 楼层选择，避免手输 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| ROOM-03 | 节次筛选 | `F/read/academic.rs classroom_search`；`academic.dart` | availableSections 逗号完整令牌匹配，3 不匹配 13 | 有 | 有 | 节次选择与空闲时间可扫读呈现 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | B2 App投影/选项隔离与UI回归通过；academic_selectors/classroom_selectors/academic_presentation等，492项门禁 | B2手机/平板各14业务场景，110/122原图全复核；日期1.3/主要宽列通过；最终三端待验 | Core-live两路线基础读取PASS；生产App及筛选实读未验 |
| SPOC-01 | 作业列表 / 作业列表 | `F/read/assignments.rs spoc_assignments`；`assignments.dart` | 全局权威分页由 Core 聚合；不另造本地分页语义 | 有 | 有 | 按课程分组，突出截止/状态 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| SPOC-02 | 单项内容 / 作业详情 | `F/read/assignments.rs spoc_assignment`；`assignments.dart` | assignmentId；现可手输或从当前结果选编号 | 有 | 有 | 点击父作业直接带 typed ID 入详情 | `UT/widgets/feature_details.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| JDG-01 | 当前作业 / 作业列表 | `F/read/assignments.rs judge_assignments`；`assignments.dart` | includeExpired=false；课程来自作业摘要，无独立课程查询 facade | 有 | 有 | 课程分组/筛选由已有摘要派生，不新增接口 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| JDG-02 | 包含过期作业 / 包含已过期作业 | `F/read/assignments.rs judge_assignments`；`assignments.dart` | includeExpired=true；Core 截止语义不变 | 有 | 有 | 保留当前/含过期筛选，分清截止状态 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| JDG-03 | 单项详情与题目 | `F/read/assignments.rs judge_assignment`；`assignments.dart` | courseId+assignmentId；内容、题目状态、得分/满分 | 有 | 有 | 父列表直达题目详情，编号降为辅助 | `UT/widgets/feature_details.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| JDG-04 | 批量详情 | `F/read/assignments.rs judge_assignment_details`；`assignments.dart` | 非空键列表；现文本输入；Core 去重顺序/缓存负责 | 有 | 有 | 列表多选代替手输键串，保留批量读取 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| SIG-01 | 今日课堂列表 / 全部课程 | `F/read/assignments.rs signin_today`；`assignments.dart` | 当天安排、状态可空；独立 iClass 会话在 Core | 有 | 有 | 今日课程卡片 | `UT/widgets/signin_writes.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| SIG-02 | 可签到课堂 / 可签到 | `F/read/assignments.rs signin_today`；`assignments.dart` | 本地仅 allowed 资格筛选；未知不等于未签到 | 有 | 有 | 文案改为可签到，保留未知说明 | `UT/widgets/signin_writes.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| SIG-03 | 已签到课堂 / 已签到 | `F/read/assignments.rs signin_today`；`assignments.dart` | 本地 signinEligibility==denied 筛选；须与 Core 派生依据核对，不新请求协议 | 有 | 有 | 已完成分组，状态缺失单独呈现 | `UT/widgets/signin_writes.dart`；`AT/bridge_backend_characterization/read.dart` | P4-C Domain33/App223及UI173确定性通过；coursework投影、导航与overview；原生复验待执行 | 未执行 | 未执行 |
| BY-01 | 课程列表 / 课程列表 | `F/read/services.rs bykc_courses`；`bykc.dart` | page/size；app 固定 all=true，Core all 参数未开放选择 | 有 | 有 | 课程卡片与服务端分页；核对 all 语义后设计筛选 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| BY-02 | 课程详情 / 课程详情 | `F/read/services.rs bykc_course_detail`；`bykc.dart` | 正整数 id；typed eligibility/actions | 有 | 有 | 点课程进入详情和操作区 | `UT/widgets/feature_details.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| BY-03 | 已选课程 / 已选课程 | `F/read/services.rs bykc_chosen_courses`；`bykc.dart` | 保留 courseInfo 与目标归属，不由展示字段决定写入 | 有 | 有 | 我的博雅课程，突出时间与资格 | `UT/widgets/writes.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| BY-04 | 修读统计 / 修读统计 | `F/read/services.rs bykc_statistics`；`bykc.dart` | Core 统计字段；不自行补学分规则 | 有 | 有 | 博雅概览与分类进度 | `UT/widgets/feature_details.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| BY-05 | 博雅资料 / 个人资料 | `F/read/services.rs bykc_profile`；`bykc.dart` | 博雅专属资料白名单 | 有 | 有 | 博雅概览身份摘要，与主账号资料区分 | `UT/widgets/feature_details.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| LIB-01 | 楼馆列表 / 馆列表 | `F/read/services.rs libbook_libraries`；`libbook.dart` | day；Bridge 有 storeys，app 仅投影楼层数 | 部分 | 有 | 楼馆→楼层联动；补 typed 楼层选项 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| LIB-02 | 馆区和楼层 / 馆区列表 | `F/read/services.rs libbook_areas`；`libbook.dart` | premisesId、可选 storeyId、day；现手输编号或父列表拾取 | 有 | 有 | 点楼馆进馆区，保留当天上下文 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| LIB-03 | 分区详情 / 分区详情 | `F/read/services.rs libbook_area_detail`；`libbook.dart` | areaId；营业窗口由 upstream 条件决定 | 有 | 有 | 分区说明、可用日期、时段形成结构化视图 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| LIB-04 | 可用日期/时段选择 | `F/read/services.rs libbook_area_detail`；`libbook.dart` | availableDates、timeSlots；app 把时段仅 join(label)，丢失供后续选择的结构 | 部分 | 仅文本 | 补 typed 可选日期/时段，将 segment/start/end 一次带入 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| LIB-05 | 座位查询 / 座位查询 | `F/read/services.rs libbook_seats`；`libbook.dart` | areaId/day/start/end；app 另必填 segment 供预约，不能猜编号 | 有 | 有 | 从分区时段到座位列表，保留资格/未知状态 | `UT/widgets/libbook_queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| LIB-06 | 我的预约 / 预约记录 | `F/read/services.rs libbook_bookings`；`libbook.dart` | page>=1、limit 1–100；保留服务端分页 | 有 | 有 | 预约记录入口与取消操作同页 | `UT/widgets/libbook_writes.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| CG-01 | 场馆站点 / 站点列表 | `F/read/services.rs cgyy_sites`；`cgyy.dart` | 站点 ID 来自返回 | 有 | 有 | 点站点进入可预约日期与场地 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| CG-02 | 用途 / 用途类型 | `F/read/services.rs cgyy_purpose_types`；`cgyy.dart` | 来源 upstream/static_fallback 必须明示 | 有 | 有 | 作为预约表单选择器；保留降级来源说明 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| CG-03 | 日期空间 / 日期空间 | `F/read/services.rs cgyy_day_info`；`cgyy.dart` | 正 siteId、严格日期 | 有 | 有 | 站点带入日期选择，保留返回空间层级 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| CG-04 | 可预约场地与时段 / 日期空间结果 | `F/read/services.rs cgyy_day_info`；`cgyy.dart` | app 只遍历 allowed 且 target 一致的时段构成结果 | 部分 | 有但不展示不可约时段 | 显示已占用/未知也有上下文；写按钮仍只 allowed | `UT/widgets/cgyy_writes.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| CG-05 | 我的订单 / 订单列表 | `F/read/services.rs cgyy_orders`；`cgyy.dart` | page/size；Core 返回 number/totalElements/totalPages | 有 | 有 | 订单状态与审批状态分层，保持服务端分页 | `UT/widgets/cgyy_cancel_writes.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| CG-06 | 订单详情 / 订单详情 | `F/read/services.rs cgyy_order_detail`；`cgyy.dart` | 正订单 ID；现父结果选 ID 或手输 | 有 | 有 | 列表点击直达详情，不重输编号 | `UT/widgets/cgyy_cancel_writes.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| CG-07 | 门锁状态 / 门锁状态 | `F/read/services.rs cgyy_lock_code`；`cgyy.dart` | Bridge 只返回 available，不返回秘密锁码 | 有 | 有 | 保留门锁可用性；不能扩为明文锁码展示 | `UT/widgets/queries.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
| YG-01 | 学期概览 / 概览 | `F/read/services.rs ygdk_overview`；`ygdk.dart` | 分类/项目/学期次数与可空目标；重复 target 不允许写入 | 有 | 有 | 项目进度与合法操作同卡 | `UT/widgets/ygdk_writes.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | P3A手机/平板原生明暗默认视图已观察；子操作待对应批次 | 未执行 |
| YG-02 | 记录与分页 / 记录列表 | `F/read/services.rs ygdk_records`；`ygdk.dart` | page/size；公开状态/地点/图片数量，不返回图片 URL | 有 | 有 | 时间线与图片数量，保留分页 | `UT/widgets/ygdk_writes.dart`；`AT/bridge_backend_characterization/read.dart` | 未执行 | 未执行 | 未执行 |
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
| W-SIG-01 | 课堂签到 / 准备签到 | `F/write/campus.rs preflight_signin_perform/signin_perform`；`U/features/assignments.dart` | 当天唯一安排、courseId、allowed；单次发送 | 有 | 条件可达 | 今日课程动作 | `UT/widgets/signin_writes.dart`；`B/write/tests/signin.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-LIB-01 | 图书馆预约 / 准备预约此座位 | `F/write/reservations.rs preflight_libbook_reserve/libbook_reserve`；`U/features/libbook.dart` | areaId/seatId/day/segment/start/end；完整父查询上下文 | 有 | 条件可达 | 座位→确认显示馆区时段，不让用户拼 ID | `UT/widgets/libbook_writes.dart`；`B/write/tests/libbook.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-LIB-02 | 图书馆取消 / 准备取消预约 | `F/write/reservations.rs preflight_libbook_cancel/libbook_cancel_booking`；`U/features/libbook.dart` | typed 记录 target、page/limit；原页刷新 | 有 | 条件可达 | 预约卡片取消，结果留在原分页 | `UT/widgets/libbook_writes.dart`；`B/write/tests/libbook.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-CG-01 | 研讨室预约 / 准备研讨室预约→表单 | `F/write/reservations.rs preflight_cgyy_reservation/cgyy_submit_reservation`；`U/features/cgyy.dart` | 1–2 同空间目标，站点日期时间顺序；电话/主题/用途/人数/正文/参与人及标志 | 有 | 条件可达 | U/write/cgyy_form.dart；用途列表联动，展示完整预约时间 | `UT/widgets/cgyy_writes.dart`；`B/write/tests/cgyy_reservation.rs`（预约）或 `B/write/tests/cgyy_cancel.rs`（取消） | 未执行 | 未执行 | 不适用（写入） |
| W-CG-02 | 场馆取消 / 准备取消订单 | `F/write/reservations.rs preflight_cgyy_cancel/cgyy_cancel_order_if_route_matches`；`U/features/cgyy.dart` | 正订单 ID、typed 取消资格、原路线核对 | 有 | 条件可达 | 订单详情和订单卡一致动作，核对取消状态 | `UT/widgets/cgyy_cancel_writes.dart`；`B/write/tests/cgyy_reservation.rs`（预约）或 `B/write/tests/cgyy_cancel.rs`（取消） | 未执行 | 未执行 | 不适用（写入） |
| W-YG-01 | 阳光照片打卡 / 准备阳光打卡→表单 | `F/write/campus.rs preflight_ygdk_submit/ygdk_submit_if_route_matches`；`U/features/ygdk.dart` | 分类项目 target、开始结束、地点可选、公开开关、照片 bytes/name/MIME；一次 upload/final | 有 | 条件可达 | U/write/ygdk_form.dart；照片能力缺失说明，未知结果先核对 | `UT/widgets/ygdk_writes.dart`；`B/write/tests/ygdk.rs` | 未执行 | 未执行 | 不适用（写入） |
| W-EV-01 | 单门评教 / 准备提交评教 | `F/write/evaluation.rs preflight_evaluation_submit_courses/evaluation_submit_courses_if_route_matches`；`U/features/evaluation.dart` | 一个完整 typed target；问卷 payload 留 Core | 有 | 条件可达 | 课程确认，说明既定提交语义，不伪装可编辑问卷 | `UT/widgets/evaluation_writes.dart`；`B/write/tests/evaluation.rs` | 未执行 | 未执行 | 不适用（写入） |
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
