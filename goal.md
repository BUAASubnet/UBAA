# UBAA Flutter 六平台全功能正式版执行计划

状态：P0 受阻；P1 bridge 已实现但验收未闭合；继续 P2/P3（官方五平台 native CI 通过；DevEco/API26 已就绪；签名 HAP/设备待闭合）
计划确认日期：2026-09-01
项目根目录：/Users/moorefoss/Code/UBAA

本文件是当前阶段唯一的活动执行计划。目标是以现有 Rust Core/facade 为唯一业务核心，交付共享 Dart/UI 的 Flutter 正式版，覆盖 Windows、macOS、Linux、Android、iOS 和 HarmonyOS，并让当前迁移矩阵中的全部用户可见读取与写入能力在六个平台可用。

“完成”必须同时意味着：功能完整、六平台可复现构建、正式签名产物、真实设备验证、写操作安全闭环、隐私和凭据安全、Direct/WebVPN 路线证据以及发布文档齐备。空壳页面、Demo backend、Mock 成功、单个平台编译通过或仅实现读取能力都不能宣告完成。

## 1. 已确认的产品决策

- 技术路线：Flutter + flutter_rust_bridge（FRB），Rust Core 继续负责全部协议、认证、路由、Cookie、Session、加密、解析和业务规则。
- 平台路线：Windows、macOS、Linux、Android、iOS 使用官方 Flutter；HarmonyOS 使用锁定的 CPF-Flutter/OpenHarmony fork。
- 共享方式：六个平台共享 domain、app、UI 和 FRB Dart API，只保留宿主、签名、权限和平台安全存储差异。
- UI：保留旧版 UBAA 的品牌、中文标签、导航层级、菜单顺序、Material 3 风格和主要交互体验，不要求像素级复制。
- 网络路线：Auto 为默认；设置中提供 Direct 和 WebVPN；不提供 Server Relay。Dart 不拼 URL、不处理 Cookie、不自行探测或切换路线。
- 正式版范围：覆盖 docs/migration/full-feature-matrix.md 与当前 facade 中所有面向用户的读取和写入能力。
- 账号：单账号；支持安全持久化密码和自动登录。登录流程不猜测或预留尚未由 Core 证明的交互验证码；只有已有协议证据和 typed facade 合同的业务挑战才进入 UI，材料不持久化。
- 系统：只承诺仍受上游框架或厂商支持的主流系统版本，具体范围由第 8 节的实际构建和设备证据定稿。
- 冻结参考：ubaa_old/、examples/、.env.local、运行时会话和真实响应始终只读。

## 2. 范围权威与变更规则

功能范围按以下顺序确定：

1. docs/migration/full-feature-matrix.md 中记录的旧版用户能力；
2. crates/ubaa-core/src/facade 当前公开的稳定业务方法；
3. docs/contracts 下的认证、路线、会话、读取功能和 CLI JSON 合同；
4. 冻结旧版 UI、接口、DTO、实现和测试；
5. 必要时由安全实时观察补充当前上游事实。

隐藏诊断入口、原始上游 payload、Cookie/token、验证码内部材料和仅供测试的 RouteClient 不属于用户功能。若执行中发现矩阵与 facade 冲突，先记录差异、确定产品语义、更新本计划或链接的合同，再修改生产代码。

已有未提交 Flutter/OHOS 骨架只是此前探索产物，不因存在于工作树就自动成为验收基线。P0 必须逐文件审查、保留有证据的部分、重写不符合计划的部分，并记录最终采用结果。

### 2.1 强制来源对照门禁

每个认证、读取和写入操作在修改生产代码前，都必须分别对照 docs/migration/references.md 固定提交中的 ubaa_old 和 examples/buaa-api，并在 docs/migration/source-parity.md 或链接的决策记录中逐项固定：

1. 业务 CAS/Bootstrap URL 与 service 参数；
2. 重定向与最终 URL 规则；
3. Cookie、Session 与业务 token 作用域；
4. HTTP 方法、精确参数、Header 与 Body 编码；
5. 加密、签名和挑战常量；
6. DTO、解析字段、类型与缺失值规则；
7. 缓存、并发、去重与重试行为；
8. 错误、退出和结果不确定语义；
9. Flutter 展示或写确认所需但不能反推上游协议的产品语义。

某个参考没有等价协议时记录“不适用”，不得类比借用。两个参考冲突时停止该协议边界的实现，在 docs/migration/decision-log.md 记录文件、提交和安全实时观察，只采用实时证据或适用冻结本地实现支持的行为。

每个 parity 缺口遵循同一 TDD 闭环：先增加脱敏 fixture、Mock 请求或解析失败测试并保留预期失败证据，再做最小实现，随后运行聚焦测试、just check-sensitive 和 just check。冻结目录、真实响应、Cookie、token、验证码和个人数据不得进入补丁或测试材料。

## 3. 当前基线

恢复任何执行阶段时先运行：

    git status --short --branch
    just refs
    just check-sensitive
    just check

已知事实：

1. 当前分支为 ubaa2 并跟踪 `origin/ubaa2`；合同、探索骨架、FRB 绑定、OHOS runner、
   六平台门禁、bridge 实现、共享读取状态、macOS 链接修复和查询入口均已形成阶段提交；
   最新提交及远端基线以 `git log` 和 CI 终态为准。
2. 冻结引用由 docs/migration/references.md 固定；不得修改或暂存冻结仓库。
3. Rust Core/CLI 的确定性门禁已通过；图书馆分区详情已在 2026-09-01 11:58（Asia/Shanghai）
   营业窗口内复跑，Direct 与 WebVPN 均为 `PASS(count=1)`。
4. 官方 Flutter 已锁定为 3.41.9，commit 00b0c91f06209d9e4a41f71b7a512d6eb3b9c694，Dart 3.11.5。
5. HarmonyOS fork 已锁定为 tag 3.41.10-ohos-1.0.1，commit adaf911c35c9136a7d18fc424d714c9ec7724e60。
6. 当前 OHOS fork 的发布说明要求 DevEco/Command Line Tools 26.0.0 Beta2 与 OpenHarmony API 26 构建；用户已更新 Command Line Tools，本机 Studio/CLI 均报告 26.0.0.821、Hvigor 6.26.4、ohpm 26.0.0.630 与 SDK API26。旧 API21 仅是历史失败证据，不再代表当前工具链。
7. 取得匹配 API 26 工具链、构建签名 HAP、打包 FRB arm64 动态库并完成实体机验证，是 HarmonyOS 正式版硬门槛。
8. 当前 Core-live 真实读取证据中 Direct/WebVPN 必需操作均通过；同批次 SPOC/Bykc 父列表为空，
   对应详情为 `NOT_APPLICABLE`，Cgyy 用途为 `PASS source=static_fallback`，不冒充上游接口成功。
   第 10.3 节的 Flutter App 六平台 E2E 与 RC 审查仍未闭合。
9. FRB Dart/Rust/runtime/codegen 与 Cargokit 已锁定 2.13.0；生成后由锁定 Rust
   toolchain 机械格式化并通过零漂移门禁。macOS App 已实际启动越过 hello 断言，
   iOS simulator 已链接 x86_64+arm64 framework，Android APK 已包含三种 ABI 的
   Rust 动态库；这些证据只覆盖 P0 FFI 链路，不代表业务功能完成。
10. OHOS runner 与 arm64 Cargokit HAR 已生成，OHOS app 的 pub get、analyze 和
    widget test 通过；当前 `just ohos-check mode=debug` 已通过工具链与 HAP 前置并进入
    assemble，但在调试签名配置处停止，仍不存在签名 HAP 或设备 hello 证据。
11. `just refs`、`just check-sensitive`、`just check`、`just flutter-codegen-check`、
    `just flutter-check` 和本机 macOS/Android/iOS debug 构建已通过。远端 CI
    `33466562627` 与原生构建 `33466562620` 均在提交 `79e8391` 通过；原生构建的
    Windows、Linux、macOS、iOS simulator、Android APK job 全部通过并各自产生产物。
    P0 仅因 DevEco/API26、签名空 HAP 与 OHOS 设备 hello 未完成而保持未勾选；按 P0
    合同继续不依赖该阻断的五平台 P1 工作。
12. `docs/contracts/flutter-bridge.md` 已冻结 P1 的 opaque client、typed error、认证/路线、
    全部读取 DTO 和一次性写 intent 目标合同；`2faa753` 已实现生产 Rust binding 与生成 Dart
    API，`7bd8fd2` 已接入应用 backend，但 panic/isolate/跨进程锁、完整 schema 快照和逐领域
    页面消费仍未闭合，不得勾选 P1。
13. `just flutter-codegen-check` 在 `2faa753` 后二次生成报告零漂移；`just flutter-check`、
    `just check-sensitive` 与 `just check` 均通过。官方入口当前创建 `BridgeBackend`，初始化
    失败只进入安全 `unsupported`，测试仍显式注入 `DemoBackend`；没有真实账号写入或签名凭据。
14. `65b7b48` 已将普通 8 项与高级 4 项只读能力接入共享详情模型和导航，详情页不再是占位文案，
    并通过 widget/app 测试；P3 的领域筛选、分页、stale 缓存、golden/integration 和完整写入
    UI 尚未完成，不能勾选 P3。
15. `5ffc9f6` 增加了平台安全凭据存储的 typed 注入边界和测试，但没有把回调冒充为原生实现；
    六平台 Keychain/Keystore/Credential Manager/Secret Service/HUKS 插件与设备证据仍是 P5/P6
    阻断，生产默认安全地不持久化密码。
16. `1b0d24e` 已将十项 typed 写入意图接入共享 `WriteIntent`、确认页面和 app 状态机，覆盖
    过期、重复确认和 `outcome_unknown` 的禁止自动重试语义；真实写入、各领域选择器/权限/读取
    核对和六平台集成尚未完成，P4 不能勾选。
17. `061c8c2` 修正未知结果后的 intent 消费语义，并让已有成功数据在刷新失败时进入 `stale`；
    `60686a9` 增加生成 API schema 快照、dispose 后重建、过期 intent 消费和独立会话实例文件锁
    测试。P1 仍缺 FRB panic 归约、真实 isolate 重建和完整逐 DTO/Dart 消费证据。
18. `891f6e4` 已补齐高级写操作的 app typed prepare 映射；共享详情列表已有本地筛选、20 项分页和
    widget 测试，但这不替代领域 query、服务端分页、写入表单/读取核对或真实矩阵证据。
19. `60ebb6c` 修复 macOS arm64 native debug 缺失 `SystemConfiguration` 链接并在本机重建通过；
    写 intent 的跨进程会话修订冲突现已映射为 `operation_conflict`。远端五平台 native CI 仍以
    最新提交终态为准，OHOS/API26、签名和设备证据仍未闭合。
20. 当前 `AppController` 仅从可用安全保险箱恢复并执行用户已选择的自动登录，随后清空密码；
   不可用保险箱会禁用持久化选项。自动登录确定性测试已通过，但六平台原生安全存储插件和
   生命周期/设备证据仍属于 P5/P6。
21. `FeatureQuery` 已固定 term/date/campus/floorId/section/week/page/size/judgeKeys 非敏感参数；`FeatureQueryBackend` 将课表
   学期/周次、考试/成绩学期、空教室日期/校区和博雅分页以 typed 方式传入 Core，详情页查询控件
   与 app/widget 测试已接线（博雅页码控件遵循 1-based）；bridge 将博雅页码明确收敛为 Core 要求的 1-based。其余领域筛选、
    服务端分页、逐领域详情闭环、golden/integration 和写入页面仍未完成。
22. bridge 现对 open、认证、路线、读取执行和 typed 写意图统一捕获 Rust panic，并归约为固定
   `internal_error`；panic payload 不进入 Dart。对应单元测试、全 Rust 门禁和 FRB 生成零漂移已
   通过，但 Dart isolate 重建、内存泄漏及六平台生命周期证据仍未完成。
23. `WriteFlowController.prepare` 与 `BridgeBackend` 十项 typed prepare 已统一接入安全错误映射；
   prepare 阶段不提交网络，确认页仍只消费一次性 `WriteIntent`。各领域表单、权限/挑战、读后
   核对、integration 和真实写入授权仍缺失，本轮未产生真实副作用。
24. 已新增 `docs/runbooks/flutter-release.md`，固定六平台发布前门禁、未签名/正式产物隔离、设备
   smoke、两条路线证据、写入授权和回滚留档流程；签名账号/私钥和真实写入继续等待逐项明确授权。
   OHOS API26/DevEco、实体设备、原生安全存储和正式签名仍是 P5/P6 阻断。
25. 本机曾执行无签名 Release 探索：macOS 因 Cargokit 需要的 `x86_64-apple-darwin` Rust target
    下载长期无输出而中断；Android AAB 的 Gradle 任务及 native strip 均完成并生成了本地 AAB，
    但 Flutter 最终 `apkanalyzer` 因 Homebrew command-line tools 的 SDK 目录布局无法定位
    latest build tools，命令按合同失败，不能将该 AAB 记为 Release PASS。未修改 SDK、未签名、
    未上传任何产物；该环境问题与 OHOS/API26、正式签名和设备阻断一并保留。
26. 2026-09-01 11:58（Asia/Shanghai）以当前提交串行执行 `just verify-live mode=direct` 与
    `mode=webvpn`，两条路线全部必需只读操作通过，尤其 `libbook/area_detail` 均为
    `PASS(count=1)`；SPOC/Bykc 详情因同批次父列表为空记 `NOT_APPLICABLE`，Cgyy 用途均明确
    `source=static_fallback`。本次只证明 Core-live 协议矩阵，没有调用真实写接口，也不替代六平台
    Flutter→FRB→Core 的真实设备 E2E。
27. 远端 CI run `33468279841`（当前文档提交 `530a38e`）已终态成功：`contract-gates`、
    macOS Rust 和 Windows Rust 三个 job 全部通过；该 run 只覆盖 Rust/合同门禁，不新增
    OHOS API26、正式签名、实体设备或 Flutter Release 证据。
28. 提交 `a17d398` 修正共享刷新状态：Core 明确返回空结果时清除旧摘要和详情，避免空状态
    残留过期数据；新增 app 回归测试通过。本修复不改变 stale 失败保留上次成功数据的语义。
29. 提交 `a17d398` 的远端 CI run `33469682792` 与 Flutter 原生 debug run `33469682830`
    均已成功；后者在 Linux、Windows、macOS、iOS simulator、Android APK 五个原生 job
    构建并上传 debug 产物。两者仍不提供 OHOS API26/HAP、正式签名或实体设备证据。
30. 当前增量将 Core 返回的 `resolved_route` 从 `FeatureResult`/`BridgeBackend` 保留到
    `FeatureSnapshot`，并在共享卡片与详情页显示“实际路线”；app/widget 回归测试已通过。
    这修复了配置策略与实际路线可能混淆的展示缺口，但不替代六平台真实 App E2E。
31. 应用层已通过受限 `RouteSettingsBackend` 读取活动路线；切换到未认证的固定路线时清除
    用户和功能快照并回到登录页，避免旧路线数据残留。Bridge 仍由 Core 执行原子策略保存、
    重开 client 和 intent 失效；对应 app 回归测试已通过。
32. 共享“我的”页面已区分普通退出与二次确认的“退出并清除本机账号”；后者同时清理 Core
    Session 和用户主动保存的凭据，app/widget 测试已通过。该流程不触发任何学校数据写入。
33. 应用启动时已通过受限路线设置投影恢复 Core 持久化的 `defaultPolicy`，再检查认证状态；
    路线切换仍按活动槽位决定是否清理状态并要求重新登录，相关 app 测试已通过。
34. AppController 和共享“我的”页现展示不含 Session 内容的 `activeRoutes`，并与每项读取
    结果的 `resolved_route` 分开；登录成功、路线切换和注销都会更新该投影，确定性测试已通过。
35. 应用层已提供显式 `BackendFactory`/`rebuildBackend()` 生命周期入口：isolate 或宿主重建时
    先创建新 opaque backend，再释放旧实例、清空旧用户/路线/功能快照并重新执行持久化路线与认证
    恢复；无工厂、登录中和并发重建安全拒绝，app 回归测试已通过。官方 Flutter 与 OHOS 宿主
    已接入后台→前台恢复回调。该证据仍不替代六平台实体生命周期与内存泄漏测试。
36. 修正 `docs/contracts/readonly-features.md` 遗留的 `evaluation_pending` 表述：待评列表仅由
    `evaluation_all` 的 `is_evaluated=false` 字段在 CLI/UI 本地派生，未新增未经 Core 证明的接口。
37. 共享 `FeatureQuery` 已新增封闭的 `FeatureQueryView` 与图书馆公开 ID/时段参数；
    `BridgeBackend` 和详情控件现可 typed 调用馆区、分区详情、座位及预约记录读取，并以
    `FeatureDetail` 展示白名单字段。该增量只读且有 widget 回归测试，不替代 P3 的全部领域
    页面、服务端分页、golden/integration 和六平台真实 App E2E。
38. `FeatureQueryView` 现支持 `ygdkRecords`；BridgeBackend 和高级功能控件可 typed 调用
    阳光打卡记录分页，并只展示不含图片地址/业务令牌的白名单字段。新增 widget 回归测试，
    仍不代表阳光打卡提交或 P3 完成。
39. `FeatureQueryView` 现覆盖 Cgyy 用途类型、日期空间、订单列表/详情和门锁状态；
    BridgeBackend 与高级功能控件调用已有 typed facade，订单白名单省略手机号/参与人/交易号，
    用途明示 `upstream` 或 `staticFallback`，门锁只展示 `available`。新增日期空间 widget
    回归测试；该只读增量不代表预约写入、权限挑战或 P3 完成。
40. `FeatureQueryView` 现支持 SPOC/Judge 作业详情；BridgeBackend 以公开作业/课程编号调用
    typed 详情 facade，并仅映射作业头、题目状态/分数和纯文本内容；高级功能控件与 widget
    测试已接线，缺少必要编号时返回 `invalid_input`。本轮只读，不代表 P3 的完整详情核对、
    golden/integration、写入页面或六平台真实 App E2E 已完成。
41. `FeatureQueryView` 现支持 `bykcDetail`；博雅列表展示课程 ID，详情控件与 BridgeBackend
    仅接受正整数并调用已有 `bykcCourseDetail` typed facade，映射课程/教师/地点/时间/容量/状态
    白名单字段。widget 测试先观察缺失视图的预期失败再通过；本轮不触发选课、退选或签到，
    也不代表 P3/P4 的其余详情、表单、核对和六平台 App E2E 已完成。
42. Bykc 只读视图继续覆盖 `bykcProfile`、`bykcChosenCourses` 和 `bykcStatistics`；
    BridgeBackend 直接调用 typed facade 并映射个人资料、已选课程考勤/成绩状态及修读统计，
    不传递课程附件路径等潜在 URL。博雅控件提供封闭下拉选择；本轮无新接口、无真实写操作，
    P3 的完整状态、分页核对、golden/integration 和六平台 E2E 仍未完成。
43. `FeatureQueryView` 现覆盖课表 `scheduleToday`、`scheduleTerms`、`scheduleWeeks` 和
    `scheduleWeek`；BridgeBackend 以 typed facade 映射学期/周次/周课表，控件提供封闭下拉视图
    并对学期、周次做本地必填校验。`summary` 的既有今日/指定周兼容行为保留；本轮只读，P3
    其他领域状态、真实 App E2E 和完整服务端核对仍未闭合。
44. 评教高级页现提供“全部课程/待评课程”视图；BridgeBackend 两者均调用同一
    `evaluationAll`，仅按 `isEvaluated=false` 在本地派生待评列表，未新增未经证明的
    `evaluation_pending` facade。控件/widget 回归已接线且不触发提交；题目选择、批量写入、
    结果核对及 P3/P4/P5/P6 证据仍未完成。
45. 考试页现提供“全部考试/已安排/未安排”视图；BridgeBackend 三种视图均调用
    `examArrangement(term)`，只在本地从已安排/未安排集合派生，控件与 widget 回归已接线，
    未新增接口或写操作。成绩、空教室、签到细筛及完整 P3 状态、真实 Flutter E2E 仍未闭合。
46. 成绩页现提供“全部成绩/已出成绩/待出成绩”视图；BridgeBackend 三种视图均调用
    `grades(term)`，仅按冻结 DTO 的 `score` 是否为空在本地派生，控件与 widget 回归已接线，
    未新增接口或写操作。成绩服务端筛选/分页、空教室/签到细筛及完整 P3 状态、真实 Flutter
    E2E 仍未闭合。
47. 希冀作业列表控件现提供“包含已过期作业”本地开关，按冻结
    `judgeAssignments(includeExpired)` 的既有 typed 参数传递；详情视图不显示该开关，widget
    回归已覆盖，未新增接口或写操作。完整作业状态/分页、golden/integration、真实 Flutter
    E2E 与 P4 写入页面仍未闭合。
48. 2026-09-01 初次复核 `just ohos-check mode=debug` 时记录了旧 DevEco `6.0.1.251` 与
    OpenHarmony SDK API21 的失败；该记录保留为历史证据，随后已由用户更新 Command Line
    Tools 的当前事实替代。该次未下载受限工具链、未登录华为门户、未签名/构建 HAP、未连接设备。
49. 用户更新 Command Line Tools 后，`/Users/moorefoss/Code/bin/command-line-tools` 与
    DevEco Studio 均报告 `26.0.0.821`、Hvigor `6.26.4`、ohpm `26.0.0.630`、Node `24.14.1`
    和 SDK API26。工程 profile 使用 `compatibleSdkVersion`/`targetSdkVersion: "26.0.0"`，
    hvigor/project `modelVersion: "6.0.0"`；Studio 默认路径和 CLI 根路径执行
    `just ohos-check mode=debug` 均通过工具链、Dart、native 前置并进入 HAP assemble，随后
    在调试签名配置处停止。未配置自动签名、未签名/上传 HAP、未连接设备；P0/P6 仍未完成。
50. 空教室查询现支持 `floorId` 与 `section` 本地筛选：楼层按白名单 `floorId` 或分组名精确匹配，
    节次按冻结 `kxsds`/`availableSections` 的逗号分隔令牌精确匹配；`BridgeBackend` 仍只调用
    `classroomSearch(campus,date)`，未改变上游参数。widget 控件参数测试通过，P3 的服务端筛选/分页、
    完整领域状态、golden/integration 与真实 Flutter App E2E 仍未闭合。
51. Judge 批量详情现通过 `FeatureQueryView.judgeBatchDetails` 和公开键列表接入共享 UI/BridgeBackend；
    UI 每行解析 `课程编号/作业编号`，bridge 调用既有 `judgeAssignmentDetails(keys)` 并按白名单映射
    作业头与题目。空键在 bridge/UI 均拒绝；P3 的列表选择器、分页、完整状态、golden/integration 和
    真实 Flutter App E2E 仍未闭合。
52. 课堂签到现通过 `FeatureQueryView.signinPending`/`signinCompleted` 接入共享 UI/BridgeBackend；
    两种视图均只调用 `signinToday`，按冻结 `signStatus` 0/1 本地派生并保留实际路线。签到写入、
    完整页面状态、golden/integration 和真实 Flutter App E2E 仍未闭合。
53. 2026-09-01 在当前 SDK 上复核 `just flutter-build platform=android-appbundle mode=release`：Gradle
    `bundleRelease` 成功，但 Flutter `apkanalyzer` 因 `cmdline-tools/latest` Homebrew symlink 无法定位
    SDK `build-tools` 而按门禁失败；临时 overlay 仅证明三 ABI AAB 含 debug symbols。产物未签名、未上传，
    Android Release/安装/实体机证据仍未完成。
54. 提交 `e2fdd5a` 的合同 CI run `33490877831` 与 Flutter native run `33490877817` 均已终态成功；
    后者 Windows、macOS、Linux、Android APK、iOS simulator 五个 job 全部构建并上传 debug 产物。
    该证据不包含 OHOS HAP、正式签名、公证、实体设备或真实 Flutter→FRB→Core E2E，P0/P5/P6 仍未闭合。
55. 详情页现在按功能保存最近一次 typed `FeatureQuery`；查询后的失败/过期重试会复用相同筛选、分页和
    公开 ID，不退回摘要查询。新增 widget 回归通过，未新增上游协议或写操作；P3 的逐领域完整状态、服务端
    分页核对、golden/integration 和真实 Flutter App E2E 仍未闭合。
56. SPOC 作业列表的详情白名单补充冻结 DTO 已证明的 `courseId`（课程编号），与已有 typed 详情调用的公开
    标识一致；新增 BridgeBackend 脱敏回归通过，未新增上游请求或写操作。P3 的列表选择器、完整状态、服务端
    分页核对、golden/integration 和真实 Flutter App E2E 仍未闭合。
57. 共享查询控件现在从当前只读详情白名单提供公开 ID 选择器，覆盖博雅课程、图书馆馆区/分区、场馆站点/订单、
    SPOC 作业和 Judge 课程/作业，并保留手动输入；新增 widget 回归通过，仍只生成 typed `FeatureQuery`，未新增
    上游协议或写操作。P3 的服务端分页核对、完整状态、golden/integration 和真实 Flutter App E2E 仍未闭合。
58. 博雅课程详情现提供选课/退选 typed 操作入口：共享 UI 仅在白名单课程 ID 为正整数时显示准备按钮，
    AppController 通过封闭 `BykcWriteBackend` 调用既有 prepare，确认页再单次提交 `intentId`。widget/app 回归证明
    准备阶段不提交、确认后才提交并拒绝非法操作；本轮无真实账号写入，其他写操作和 P4/P5/P6 门禁仍未闭合。
59. 课堂签到只读详情现投影冻结 DTO 已证明的公开 `课程 ID`，共享 UI 以该编号触发 typed `signin_perform` prepare，
    确认页二次确认后才单次提交；app/widget/bridge 回归覆盖编号清理、准备不提交和确认后提交。本轮无真实账号写入，
    位置/挑战条件仍由 Core 合同判定，其他写操作及 P4/P5/P6 门禁仍未闭合。
60. 图书馆预约记录与场馆订单详情现以读取白名单中的 `预约 ID`/`订单编号`提供可逆取消入口，
    AppController 通过 `CancellationWriteBackend` 严格校验领域和编号后调用既有 typed prepare；确认页二次确认后才单次提交，
    结果不确定时先刷新核对。app/widget 回归覆盖准备不提交、非法编号拒绝和确认后提交，本轮无真实账号写入，其他写操作及
    P4/P5/P6 门禁仍未闭合。
61. 博雅课程详情现提供签到/签退 typed 入口：UI 仅传公开正整数课程 ID，AppController 严格接受冻结 `signType` 1/2，
    调用既有 `prepareBykcSignCourse`；位置不在 UI 猜测，Core 在 prepare 阶段判定业务条件。确认页二次确认后才单次提交，
    app/widget 回归覆盖 signType 校验、取消确认和准备阶段零提交。本轮无真实账号写入，其他五项写操作及 P4/P5/P6 门禁仍未闭合。
62. 图书馆座位读取详情现保留公开分区/座位 ID、日期、时段、起止时间和可预约状态；共享 UI 对可预约座位提供预约准备入口，
    AppController 通过 `LibbookWriteBackend` 严格校验完整参数并调用既有 typed `prepareLibbookReserve`，确认页二次确认后才单次提交。
    bridge/app/widget 回归覆盖字段投影、参数清理和准备阶段零提交，本轮无真实账号写入；场馆预约、阳光打卡、教学评教提交仍缺失，
    P4/P5/P6 门禁仍未闭合。
63. 统一确认页在写入返回确定成功后通过 `AppController.refreshAfterWrite` 只刷新关联读取领域，作为结果核对钩子；刷新失败不重试写请求，
    `outcome_unknown`/commit 异常仍消费 intent 并要求先读取核对。app/widget 回归覆盖成功回调一次调用，本轮无真实账号写入，
    场馆预约、阳光打卡、教学评教提交及 P4/P5/P6 门禁仍未闭合。
64. 提交 `3e16d6f` 的远端合同 CI `33496873082` 与 Flutter native `33496873088` 均已成功，后者 Windows、macOS、Linux、Android APK、
    iOS simulator 五个 job 全部通过；本地 refs、敏感扫描、Rust/Flutter 全量门禁也通过，OHOS 双布局仅在调试签名处阻断。
    该证据不包含 OHOS HAP、正式签名/公证、实体设备或真实 App E2E，场馆预约、阳光打卡、教学评教提交及 P4/P5/P6 仍未完成。
65. 写入成功核对映射已增加回归：取消图书馆预约只刷新图书馆读取领域，不触发其它领域或额外写请求；与 UI 成功回调共同证明
    按操作隔离刷新。未知结果继续不刷新、不重试，场馆预约、阳光打卡、教学评教提交及 P4/P5/P6 仍未闭合。
66. AppController/BridgeBackend 现补齐阳光打卡、场馆预约、教学评教三类复杂写入的 typed prepare 边界：照片仅内存复制，场馆
    selection 与评教课程字段逐项映射，非法输入在网络前拒绝；教学评教详情补齐公开课程/任务/问卷/课程代码/模型标识并提供
    单课程确认入口。app/bridge/widget 聚焦回归通过，本轮无真实账号写入、照片上传或验证码挑战；三类完整表单、权限/挑战、
    批量答题与读后核对仍缺失，P4/P5/P6 不能勾选。
67. 当前 HEAD 在 2026-09-01 18:56（Asia/Shanghai）串行复核真实只读路线：WebVPN 全部必需操作通过（`signin/today`、
    `libbook/area_detail` 均 `PASS`）；Direct 除同样既有通过项外，`signin/today` 本批次为 `FAIL error=network_error`（exit code 5），
    因此 Direct 本批次不能记为全通过。两条路线均未调用真实写接口；该失败阻止 RC，不能用历史成功或 Mock 替代。
68. 最新代码在 DevEco Studio 默认路径与 `/Users/moorefoss/Code/bin/command-line-tools` CLI 路径复跑 `just ohos-check mode=debug`：
    两次工具链/API26、Dart analyze/widget、native 前置均 0 失败/0 警告，并进入 HAP assemble；均在调试签名配置处按门禁停止。
    未配置签名、未生成可发布 HAP、未连接设备；临时生成输出已移出工作树，P0/P6 仍未完成。
69. 提交 `6e0ecf6` 的合同 CI `33499492838` 与 Flutter native `33499492820` 均已终态成功；后者 Windows、macOS、Linux、Android APK、
    iOS simulator 五个 job 全部完成并上传 debug 产物。该证据不包含 OHOS HAP/签名、公证、实体设备或真实 App E2E；最新文档提交的
    CI 仍在运行，P0/P5/P6 及 P4 完整表单仍未完成。
70. 场馆日期空间读取现在逐个投影可预约时段公开站点/日期/空间/时段 ID 与时间；共享 UI 增加联系电话、主题、用途、人数、内容和
    布尔选项填写表单，校验后才进入既有 typed `prepareCgyySubmitReservation` 与统一二次确认。widget/bridge 回归通过，验证码仍由
    Core 受控流程处理，未执行真实预约；挑战恢复、订单匹配核对、阳光打卡照片表单、评教答题与 P4/P5/P6 仍未闭合。

## 4. 安全与架构边界

- 宿主只能依赖 ubaa-core facade 和专用 bridge DTO，不能访问 upstream、runtime、原始 URL、Cookie、业务 token 或内部 DTO。
- 密码、Cookie、token、验证码、真实响应、个人资料和照片不得进入日志、错误详情、命令行、普通配置文件、fixture 或版本库。
- 不关闭 TLS 校验，不绕过 CAS/SSO，不猜测上游 URL、字段、Header、加密常量或错误语义。
- 显式 Direct 或 WebVPN 失败时不得静默切换路线；只有 Core 的 Auto 策略可以统一选择路线。
- 每个写操作都必须由用户在前台主动发起，显示不可含糊的目标与影响，并再次确认。禁止后台写入、定时写入、登录后自动写入和隐藏批量写入。
- 写请求一旦可能到达上游，不得自动重试。结果不确定时先通过对应读取接口核对状态，再决定是否允许用户重试。
- 真实写入验证不是本计划的默认授权。每次真实验证前仍需用户对具体账号、目标、操作、路线、时间和可见副作用作出明确授权。
- 安全存储不可用时只能使用本次进程内凭据，并明确提示；绝不以明文文件兜底。

## 5. 完整功能矩阵

### 5.1 认证、会话和设置

| 能力 | Core/facade 边界 | Flutter 交付 |
|---|---|---|
| 打开客户端 | open | 使用平台应用私有配置目录创建 opaque client |
| 登录准备 | prepare_login | 分路线准备状态和可行动错误；当前 Core 未证明交互验证码时只展示稳定错误，不由 Flutter 猜测挑战协议 |
| 登录 | login | 单账号登录、部分路线成功、自动登录、安全凭据写入 |
| 状态恢复 | auth_status | Splash 恢复、过期会话清理、重新登录 |
| 用户资料 | get_user_info | 我的页面，只展示必要字段 |
| 注销 | logout | 退出登录；另有退出并清除本机账号 |
| 路线策略 | default_route_policy、active_routes、新增 set_default_route_policy | Auto、Direct、WebVPN；展示配置策略与实际解析路线，按本节下方合同切换 |

Flutter 不开放 per-feature route override。set_default_route_policy 必须作为新的稳定 facade 能力实现：拒绝在写 intent 或请求进行中切换；原子保存新的全局策略并清除 App 私有配置中的 feature override；使全部 WriteIntent 失效；dispose 后从同一私有目录重新 open；保留彼此隔离的路线 Session，再以 auth_status 检查目标路线，缺少目标路线认证时提示重新登录。每个业务结果仍展示 Core 返回的 resolved_route，不能把配置策略冒充实际路线。

### 5.2 全部读取能力

| 领域 | facade 方法 | 必须完成的页面与状态 |
|---|---|---|
| 课表 | schedule_terms、schedule_weeks、schedule_week、schedule_today | 学期、周次、周课表、今日课程、刷新和空状态 |
| 考试 | exam_arrangement | 学期选择、已安排/未安排、时间地点和座位 |
| 成绩 | grades | 学期成绩、课程详情、学分/绩点字段和缺失字段状态 |
| 空教室 | classroom_search | 校区、日期、楼层、节次筛选和结果分组 |
| SPOC | spoc_assignments、spoc_assignment | 作业列表、筛选排序、详情和提交状态 |
| 希冀 | judge_assignments、judge_assignment、judge_assignment_details | 列表、批量详情、题目与提交进度 |
| 课堂签到 | signin_today | 今日课程、签到状态和可操作窗口 |
| 博雅课程 | bykc_profile、bykc_courses、bykc_course_detail、bykc_chosen_courses、bykc_statistics | 课程浏览、详情、已选课程和修读进度 |
| 图书馆 | libbook_libraries、libbook_areas、libbook_area_detail、libbook_seats、libbook_bookings | 馆/楼层/分区/时段/座位和预约记录 |
| 阳光打卡 | ygdk_overview、ygdk_records | 学期进度、项目列表、记录分页和图片状态 |
| 场馆预约 | cgyy_sites、cgyy_purpose_types、cgyy_day_info、cgyy_orders、cgyy_order_detail、cgyy_lock_code | 站点、用途、日期空间、订单详情和门锁可用状态 |
| 教学评教 | evaluation_all | 全部/待评课程、完成进度和选择状态 |

诊断型方法只用于测试和脱敏诊断，不作为普通页面展示，也不能暴露内部协议信息。

不存在独立的 evaluation_pending facade 方法。待评列表统一由 evaluation_all 返回的稳定 is_evaluated=false 字段派生；P1 必须修正与此冲突的只读合同，并为 Core DTO、Dart 派生和 CLI 一致性建立 schema 快照测试。

### 5.3 全部写入能力

| 领域 | facade 方法 | 正式 UI 流程 | 完成后的核对 |
|---|---|---|---|
| 博雅选课 | bykc_select_course | 课程详情、资格/时间/容量检查、确认选课 | 刷新课程详情和已选列表 |
| 博雅退选 | bykc_deselect_course | 显示课程与退选截止时间、二次确认 | 刷新详情、已选列表和修读进度 |
| 博雅签到/签退 | bykc_sign_course | 显示课程、签到类型、时间窗口和位置要求、确认 | 刷新考勤状态 |
| 课堂签到 | signin_perform | 显示课程名称、上课时间和当前状态、确认 | 刷新今日签到状态，防止重复 |
| 图书馆预约 | libbook_reserve | 馆/分区/日期/时段/座位逐步选择、最终摘要确认 | 查询预约记录并匹配结果 |
| 图书馆取消 | libbook_cancel_booking | 显示预约详情、取消条件和确认 | 刷新预约记录 |
| 阳光打卡 | ygdk_submit | 项目、起止时间、地点、照片、公开选项、预览确认 | 刷新记录与进度 |
| 场馆预约 | cgyy_submit_reservation | 站点/日期/空间/时段、主题、用途、参与信息、挑战处理、最终摘要 | 查询订单并匹配结果 |
| 场馆取消 | cgyy_cancel_order | 显示订单详情、状态和取消影响、确认 | 刷新订单列表与详情 |
| 教学评教 | evaluation_submit_courses | 选择未评课程、展示答题策略与不可撤销警告、批量确认、逐项进度 | 重新读取完成进度并展示逐项结果 |

evaluation_submit 的原始字符串 payload 是低层 CLI/兼容入口，不直接暴露给 Flutter。Flutter 只使用 typed course 提交流程。SPOC、希冀、课表、考试、成绩和空教室在当前 Core 没有写入能力，不凭旧页面文案推断或新增协议。

### 5.4 写操作统一确认模型

bridge 为每项写操作提供 typed prepare 方法，并返回 WriteIntent：

- intent_id：只在当前 opaque client 内有效的随机标识；
- operation：固定写操作枚举；
- target_summary：用户可读的目标与影响摘要；
- resolved_route：Core 已解析的实际路线；
- warnings：不可撤销、时间窗口、权限或资源状态提示；
- expires_at：短时有效期；
- request_digest：用于检测确认前请求内容是否变化，不含秘密。

UI 展示摘要后，用户明确确认，再调用 commit_write(intent_id)。intent 只能使用一次；超时、客户端重开、路线改变、会话改变或请求内容改变都必须重新准备。commit 只执行已存储的 typed 请求，禁止接收任意 JSON 或 raw payload。

新增稳定写错误至少覆盖 confirmation_required、intent_expired、operation_conflict 和 outcome_unknown，并映射为安全中文提示。若 Core 已有等价错误，复用 Core；否则作为 bridge 合同新增并测试。

## 6. Flutter/FRB 目标架构

    apps/ubaa_flutter/                 Android、iOS、Windows、macOS、Linux 官方宿主
    apps/ubaa_ohos/                    HarmonyOS fork 宿主
    packages/ubaa_domain/              DTO、枚举、UiError、WriteIntent 和页面模型
    packages/ubaa_app/                 状态机、用例、依赖注入、读取与写入协调
    packages/ubaa_ui/                  主题、导航、读取页面、写入流程和组件
    packages/ubaa_platform/            CredentialVault、路径、权限、照片和位置接口
    packages/ubaa_bindings/            FRB 生成 Dart API，禁止手改
    crates/ubaa-flutter-bridge/        facade 到 FRB 的唯一映射层
    crates/ubaa-core/                  协议、路线、会话和全部业务实现

bridge crate 使用 cdylib 和 staticlib，并通过 Cargokit/FRB 生成平台产物。FRB Dart package、Rust crate、codegen 和 macros 必须锁定完全相同版本。生成配置、命令和输出目录纳入版本控制；重复生成不得产生未预期 diff。

bridge 必须：

- 使用 opaque BridgeClient 管理 UbaaClient；
- 串行保护当前需要 &mut self 的 facade 调用；
- 只返回专用、可序列化、FRB 兼容的最小字段 DTO；每个 DTO 使用展示白名单，不得把 Core DTO 整体透传；
- 不直接导出 Routed<T>、RoutedError、Path 或内部类型；
- 捕获 Rust panic 并投影为稳定内部错误，禁止 panic 穿越 FFI；
- 支持幂等 dispose，并测试 double-dispose、use-after-dispose、取消中的会话一致性、Dart isolate 重建、内存泄漏和应用生命周期恢复；
- 默认单进程单 BridgeClient；多实例或桌面多进程必须通过 Session Store 锁定，不能并发写同一会话文件；
- 为所有读取与写入方法建立明确的 Dart API、参数边界和 schema 快照；
- 在 docs/contracts/flutter-bridge.md 固定完整方法表、DTO、错误、schema 版本和 semver 兼容规则。

flutter-bridge.md 必须逐 DTO 记录字段用途、是否含个人信息、遮盖规则、缓存期限和错误/崩溃快照策略。手机号、证件号、参与人、图片、交易号等字段只有页面确有用途时才可进入 Dart；Cgyy 锁码继续只返回 available；图片由受控字节或临时句柄传递，禁止把带 token 的原始 URL 交给 Dart。

若首页串行读取影响体验，先在 Core 增加返回逐项结果的 home_bootstrap 聚合方法；未经会话并发审计不得在 Dart 建立多个隐式客户端或复制路由逻辑。

## 7. UI、权限、凭据和本地数据

### 7.1 页面与导航

- Splash：品牌、版本检查、会话恢复；公告或更新检查失败不得阻塞使用。
- 登录：学号、密码、记住密码、自动登录和路线选择；当前 Core 不支持的交互验证码显示可行动错误，不伪造输入流程。
- 根导航：主页、普通功能、高级功能、我的；宽屏侧栏，窄屏底部导航或抽屉。
- 普通功能顺序：课表、考试、成绩、博雅、空教室、SPOC、希冀、图书馆。
- 高级功能：课堂签到、研讨室预约、阳光打卡、教学评教和其他已证明能力。
- 首页各卡片独立 loading、success、empty、failure、stale 和 retry；单项失败不能白屏。
- 写按钮必须根据当前状态、时间窗口和权限禁用，并说明原因。
- 写入进行时只锁定相关目标；防重复点击。成功后刷新关联读取状态，失败保留非敏感输入。
- Material 3 明暗主题、动态字体、键盘导航、屏幕阅读器语义、焦点顺序和颜色以外的状态标识全部覆盖。

每个页面在 docs/design/flutter-ui-spec.md 记录导航来源、旧版参考文件、响应式布局、所有状态、确认文案和 widget/golden 测试。

### 7.2 CredentialVault

CredentialVault 提供 read、write、delete、capability，只保存一个账号的最小凭据，使用版本化命名空间和原子更新：

- macOS/iOS：Keychain；
- Android：Keystore 保护的密钥与应用私有密文，关闭敏感备份；
- Windows：Credential Manager/Locker；
- Linux：Secret Service/libsecret；
- HarmonyOS：HUKS 非导出密钥保护应用私有密文。

登录成功后才保存密码；凭据错误时清理旧密码；退出登录与退出并清除本机账号分开。安全存储缺失、锁定或损坏时退回本次会话，不创建明文备份。密码和挑战材料在使用后立即从 UI controller 与 bridge 临时状态中清理。

### 7.3 Core Session 存储

UbaaClient::open 只能接收 PlatformPaths 解析出的 App 私有目录。Core 继续拥有 Session 内容，Dart 和平台宿主不得读取 Cookie。P1/P2 必须冻结 session schema、迁移和清理合同，并逐平台满足：

- Windows：当前用户专属目录、严格用户 ACL、原子替换，安装包和便携包都不得落到程序目录；
- macOS/iOS：App Container/Application Support、备份排除；iOS 使用可用的数据保护级别；
- Linux：XDG 私有数据目录、目录 0700、文件 0600、原子替换；权限无法保证时禁止持久化；
- Android：应用私有 noBackupFilesDir 或等价目录，禁止云备份和设备间迁移；
- HarmonyOS：应用沙箱私有目录、备份排除和厂商支持的文件保护。

启动时拒绝符号链接、宽权限、损坏或降级 schema；注销清除 Core Session 但默认保留用户主动保存的密码，退出并清除账号同时删除 Session、密码和非必要缓存。升级、崩溃中断、重装和卸载后的行为必须有平台测试。

### 7.4 平台权限与敏感输入

- 阳光打卡：移动端支持相机/相册，桌面支持文件选择；提交前显示照片预览。照片只在本次提交和必要的预览生命周期内存在。
- 博雅签到：仅在业务配置要求时请求前台位置；不申请后台位置。桌面没有位置能力时提供明确、可审查的手动输入或上游允许的无坐标路径，不能伪造位置。
- 场馆挑战：图像和解答只保留在当前操作内存中，超时立即清理。
- 权限拒绝必须给出可行动说明；拒绝权限不能导致应用崩溃或影响无关读取功能。
- 普通缓存不得保存密码、Cookie、token、证件号、完整手机号、挑战图片或提交照片。
- 诊断日志只记录稳定错误码、阶段、耗时桶和随机问题编号；用户手动导出前再次脱敏。

## 8. 六平台目标与正式产物

| 平台 | 目标系统 | 正式产物 | 发布硬门槛 |
|---|---|---|---|
| Windows | Windows 10/11 x64 | 签名 MSIX 或安装包，另提供便携包 | Windows 原生 runner 构建、安装/升级/卸载、Credential Manager |
| macOS | macOS 12+，arm64；评估 x64 | 签名并公证的 DMG/App | Apple Silicon 实机、Intel 构建证据、Keychain |
| Linux | Ubuntu 22.04/24.04、Debian 12 x64 | AppImage 与 deb | Linux runner、GTK、Secret Service 存在/缺失两种路径 |
| Android | API 24+，重点 API29/API35 | 签名 AAB 与测试 APK | 模拟器+实体机、Keystore、权限和备份检查 |
| iOS | iOS 15+ arm64 | 签名 Archive/IPA 或 TestFlight 构建 | 模拟器+实体机、Keychain、权限、后台/前台恢复 |
| HarmonyOS | build/target API26，实际最低运行版本由设备证据定稿 | 签名 HAP/应用市场包 | DevEco/CLI26、完整 API26、arm64 FRB、HUKS、实体机 |

Windows、Linux 必须在对应系统的原生 runner 构建，macOS 不能以交叉编译替代运行证据。每个平台至少一个受支持环境完成全流程 smoke；Android、iOS、HarmonyOS 至少各一台实体设备验证权限、安全存储和写操作 UI。

正式签名需要的 Apple、Google、Microsoft、Linux 发布、HarmonyOS 账号与证书由项目所有者安全提供。没有签名/公证证据的开发产物不能标记正式版完成。

## 9. 分阶段执行

工期是单人顺序执行的粗略范围，不是发布日期承诺；OHOS 工具链、签名账号和真实写入窗口会影响总历时。

### P0：冻结基线和兼容性闸门（3–5 个工作日）

- 审查当前未提交 Flutter/OHOS 探索文件，形成可审查基线提交。
- 固定 Flutter、OHOS fork、Dart、Rust、FRB、Cargokit、DevEco/CLI 和 SDK 精确版本。
- 官方五平台分别建立最小宿主构建；OHOS 获得匹配 API26 并构建签名空 HAP。
- 在 macOS 和 OHOS 完成 FRB hello，确认 HAP 包含正确 arm64 Rust 动态库。
- 建立根级 just flutter-codegen-check、just flutter-check、just flutter-build 和 just ohos-check 配方；配方显式进入每个 package/app，官方 Flutter 与 OHOS fork 使用独立绝对 SDK 路径，禁止依赖当前 shell 中碰巧命中的 flutter。
- 建立 docs/architecture/flutter-platforms.md、风险表和 go/no-go 结果。
- OHOS 失败不阻塞其他五平台继续开发，但最终发布状态保持未完成。

### P1：稳定 bridge 合同（1–2 周）

- 建立 docs/contracts/flutter-bridge.md 和逐方法 DTO/schema。
- 修正 evaluation pending 合同；实现 BridgeClient 生命周期、认证、路线读取/设置和全部读取方法。
- 实现全部 typed 写请求、WriteIntent、一次性 commit 和不确定结果处理。
- 增加 panic、dispose、isolate 重建、会话锁、错误映射、个人字段白名单、并发/取消/重复提交测试。
- 建立可重复 FRB 生成、Cargokit 和六平台 native library 构建任务。

### P2：共享应用壳与认证（1–2 周）

- 完成 domain/app/ui/platform package 依赖边界。
- 完成 Splash、登录、会话恢复、自动登录、注销、我的、设置和安全凭据。
- 完成 Core Session 私有路径、权限、备份排除、损坏恢复、迁移和清理策略。
- 确定状态管理与导航依赖；只有通过官方 Flutter 与 OHOS spike 的依赖才能进入锁文件。
- 完成明暗主题、响应式导航、错误组件、空状态和无障碍基础。
- 使用 fake backend、脱敏 fixture 和 FRB mock 完成 widget/integration 测试。

### P3：全部读取能力（2–4 周）

按第 5.2 节逐领域交付。每个领域必须同时完成：

1. bridge DTO 与 Dart mapping；
2. 列表/详情/筛选/分页页面；
3. loading、empty、failure、retry、stale；
4. widget/golden 测试；
5. Core fixture/Mock 与 Direct/WebVPN 回归；
6. 对应真实读取证据或明确 BLOCKED 原因。

不得先做八张摘要卡片后长期保留空详情页；一个领域只有详情与全部读取闭环完成才可勾选。

当前读取缺口按以下规则闭合：libbook_area_detail 必须在 Asia/Shanghai 08:30–23:00 对 Direct/WebVPN 复跑；Bykc/SPOC 等详情只有在同一路线、同一批次的父列表确实为空时才可记 N/A，并保留父列表证据与详情 fixture 测试；Cgyy static_fallback 必须在 UI 标明来源和可能过期，且只有现有冻结回退决策仍适用并经 RC 审查时才可接受。

### P4：全部写入能力（3–6 周）

按风险从可逆到不可逆推进：

1. 图书馆预约/取消；
2. 场馆预约/取消及挑战；
3. 博雅选课/退选；
4. 博雅签到/签退与课堂签到；
5. 阳光打卡照片提交；
6. 教学评教选择与批量提交。

每项依次完成：冻结来源 parity、失败测试、typed bridge 请求、WriteIntent、确认 UI、重复点击防护、结果核对、错误恢复、六平台 widget/integration 测试、两条路线确定性测试。完成全部确定性证据后，才申请具体真实写入授权。

不可撤销操作必须单独列出目标、影响、时间窗口和预期结果；没有安全样本或授权时标记 BLOCKED，不能以 Mock 替代真实成功声明。

### P5：平台能力与六平台体验（2–4 周）

- 完成六个平台安全凭据适配。
- 完成相机/相册/文件选择、前台位置、已有 typed 合同的 Cgyy 业务挑战交互和权限拒绝路径。
- 完成桌面窗口尺寸、键盘/鼠标、移动端生命周期和 OHOS 平台差异。
- 对每个平台执行安装、升级、卸载重装、断网、会话过期、路线切换和权限变化测试。
- 完成性能、内存、无障碍和长列表检查。

### P6：发布候选与正式发布（2–4 周）

- 在原生 CI/runner 构建六平台 Release 产物。
- 完成签名、公证、SBOM、第三方许可、依赖审计和敏感信息扫描。
- 完成 Direct/WebVPN 全读取矩阵和经授权的写入矩阵。
- 完成崩溃恢复、版本升级、配置迁移、回滚和发布 runbook。
- 冻结 RC，所有阻塞问题关闭后生成正式版本与校验摘要。

## 10. 测试、证据与 CI 门禁

### 10.1 每次合并门禁

    just refs
    just check-sensitive
    just check
    just flutter-codegen-check
    just flutter-check
    git diff --check

上述 Flutter 配方由 P0 创建后生效：flutter-codegen-check 使用锁定 FRB 版本重新生成并要求零漂移；flutter-check 用官方 SDK 在明确 cwd 遍历共享 package 和官方 App，执行 pub get、analyze、test；ohos-check 使用独立 OHOS fork SDK 执行对应 analyze、test、HAP/native 构建。平台 build 和 Release 阶段再运行 just flutter-build 与 just ohos-check。FRB 重新生成后工作树必须只有预期生成差异。不得通过放宽 lint、删除测试、忽略敏感扫描或手改生成文件获得通过。

### 10.2 分层测试

- Rust：领域、协议、路由、会话、读取、写入请求向量、默认拒绝、WriteIntent 和不确定结果。
- Dart domain/app：DTO mapping、状态机、分页、缓存失效、错误和写确认。
- Widget/golden：所有页面在手机、平板、桌面断点及明暗主题下的关键状态。
- Integration：登录、会话恢复、路线切换、每个读取流程、每个写入准备/取消/确认流程。
- 平台：安全存储、权限、文件/照片、应用私有目录、动态库加载和生命周期。
- Release：安装、升级、卸载、签名、公证、产物校验和依赖清单。

### 10.3 真实系统证据

读取能力：Direct 与 WebVPN 按操作逐项验证，记录路线、时间、HTTP/业务安全状态和最终结论；Auto 保留确定性选择证据。FAIL 和必需 BLOCKED 一律阻止 RC。N/A 只有在父集合为空、前置条件客观不存在且有同批次证据时可接受；static_fallback 不算上游 PASS，只有 Cgyy 用途的既有冻结回退决策经复核且 UI 明示来源时可例外接受。

Core-live 证明协议，不证明 App 链路。Windows、macOS、Linux、Android、iOS 和 HarmonyOS 必须分别在受支持的原生环境通过真实 Flutter→FRB→Core→upstream 只读 E2E：登录/恢复、用户资料、每个业务域至少一个代表读取，以及 Direct/WebVPN 两种固定路线；平台或网络客观不支持某路线时必须给出可复核 BLOCKED，不能用 Mock 或另一平台代替。全部读取方法的协议矩阵仍由 Core-live 覆盖，全部页面状态由 fixture/integration 覆盖。

写入能力：

1. 先通过两条路线的 fixture/Mock/向量和默认拒绝测试；
2. 提交一份不含秘密的真实验证清单；
3. 用户明确授权具体操作和目标；
4. 单操作串行执行，不并行、不批量、不自动重试；
5. 立即使用读取接口核对结果；
6. 可逆操作在授权包含清理时执行取消/退选并再次核对；
7. 不可逆操作保留最小安全结果摘要；
8. 任一结果不确定立即停止该领域后续写入。

每个操作的 PASS、FAIL、BLOCKED 分开记录。历史上某次写入成功不能自动证明当前版本、另一条路线或另一项操作可用。

真实写入协议逐操作在一台受控代表设备完成即可；六平台不重复制造相同副作用，但每个平台必须通过 Flutter→FRB→Core 的写入 prepare、取消、确认门禁、平台权限和 Mock 提交 E2E。任何真实写入仍受本节逐次授权规则约束。

### 10.4 CI 平台

- macOS runner：Rust、Dart、macOS、iOS simulator。
- Linux runner：Rust、Dart、Linux、Android 构建。
- Windows runner：Rust、Dart、Windows 安装包。
- 受控 OHOS runner：固定 DevEco/CLI26、API26、HAP 构建和设备 smoke。
- 实体设备测试与签名任务使用受保护凭据，不在普通 Pull Request 中运行。

## 11. 完成定义

只有以下条件全部满足，状态才能改为“完成”：

1. 第 5 节列出的全部读取与写入能力均有正式 Flutter 页面，不存在占位页、Demo backend 或只显示摘要的未完成流程。
2. 每项业务通过 Rust、Dart、widget/integration 和 bridge 合同测试；写入额外通过确认、重复提交和结果不确定测试。
3. Windows、macOS、Linux、Android、iOS、HarmonyOS 分别有可复现 Release 产物和原生环境运行证据。
4. 六个平台分别完成登录、会话恢复、路线设置、凭据能力、全部读取 smoke 和全部写入 UI 流程；涉及权限的平台完成实体机验证。
5. Direct/WebVPN 全读取矩阵和六平台真实 App 代表读取 E2E 通过；每个写入操作有符合第 10.3 节的当前版本证据或明确记录的 BLOCKED。存在必需 BLOCKED 时不能完成。
6. 密码只进入经审计的平台安全存储或当前会话；日志、诊断、fixture、生成产物和版本库无秘密或个人数据。
7. 所有写操作均使用一次性确认意图，无后台写入、无透明路线切换、无可能重复提交的自动重试。
8. 正式产物完成签名/公证、安装/升级/卸载、依赖许可、安全扫描和回滚验证。
9. 平台矩阵、bridge 合同、UI 规格、功能矩阵、测试证据、已知限制和发布 runbook 完整。
10. just refs、just check-sensitive、just check、Flutter/FRB/六平台 Release 门禁全部通过，工作树干净。

## 12. 提交与变更管理

- 每个阶段分成可审查提交；计划/合同、生成骨架、bridge、单一领域 UI、平台适配和发布配置不得混成一个提交。
- 每个业务操作先增加失败测试并保留预期失败证据，再做最小实现。
- 每次提交前检查 staged 文件和敏感扫描；禁止使用宽泛 git add . 把冻结目录或本地配置带入。
- 自动生成文件必须可重现，禁止直接手改。
- 新依赖必须记录用途、许可证、六平台支持和 OHOS 验证结果。
- 任何范围、协议、平台最低版本或写入语义变化都要更新本计划或链接合同后实施。

## 13. 执行队列

- [x] 明确技术路线为 Flutter + FRB + Rust Core。
- [x] 明确目标为六平台全部读取与写入能力正式版。
- [x] 完成旧版 UI、Core facade、FRB/OHOS 工具链初步勘察。
- [x] 将本文件重写为全功能正式版执行计划。
- [ ] P0：审查探索产物、冻结提交基线和六平台工具链。
- [ ] P1：冻结完整 Flutter bridge 合同并实现绑定（生产绑定已提交，剩余验收证据待补齐）。
- [ ] P2：完成共享应用壳、认证、设置和安全凭据。
- [ ] P3：完成全部读取页面与证据。
- [ ] P4：完成全部写入页面、安全确认和证据。
- [ ] P5：完成六平台适配与设备体验。
- [ ] P6：完成签名 Release、真实矩阵和正式发布。
- [ ] 所有完成定义满足后，将状态改为“完成”。

## 14. 默认决策与后续授权点

- “记住密码”默认关闭，用户主动开启；安全存储不可用不明文降级。
- 路线默认 Auto；App 不暴露 feature override；切换固定路线时清除 App 私有 override、使 intent 失效、重新打开 Core client，并在 auth_status 表明目标路线未认证时重新登录。
- 所有写操作采用准备、摘要、明确确认、一次提交、读取核对的统一模型。
- 批量评教默认不自动提交；用户选择课程、查看数量和不可撤销提示后确认。
- 位置权限仅前台按需申请；不生成虚假位置。
- OHOS 锁定 fork commit + DevEco/CLI26/API26；完成实体机证据前不能作为正式版发布。
- 平台签名账号、证书、应用标识和商店发布权限在 P0/P6 由项目所有者单独安全提供。
- 每次真实写入验证仍需单独授权；本计划本身只授权实现和确定性测试，不授权对真实账号产生副作用。
