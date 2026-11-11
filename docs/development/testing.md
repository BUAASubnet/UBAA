# 测试策略与日常入口

当前合同：CLI JSON schema v16；Flutter bridge contract v61。CLI 验证 human/JSON schema v16，版本常量、JSON Schema、Dart 接受版本与现行文档由 `just contract-version-check` 同步检查。旧升级流水见[历史指南](../archive/history/testing-before-2026-10-07.md)。

## 检查入口

日常聚焦回归、完整确定性清单、原生专项、真实验证及 CI 的实际范围只在[开发命令](commands.md)维护。本页说明测试设计与证据边界。Dart/Flutter 调用遵守 [AGENTS 工具链规则](../../AGENTS.md#项目工具链入口)。

## 各层的独立责任

| 层级 | 入口 | 保护 |
|---|---|---|
| Core/Fixture/Mock | Core src、tests、ubaa-test-support | 精确请求、解析、加密、认证、路线、缓存与并发 |
| 公共命令 | crates/ubaa_command/tests、src/agenda | 参数、schema、退出码、协议 Mock 与共享日程 |
| App 命令调度 | packages/ubaa_app/test/command | 输入边界、恢复预算、一次完整重跑、账号变化、断管和关闭 |
| Core-live | tools/core_live/tests | 独立开发工具的子进程与只读边界 |
| FRB/Bindings | Rust Bridge、ubaa_bindings/test、codegen checker | typed DTO、错误、版本、句柄与生成零漂移 |
| App/Domain/Platform | 各包 test 下的领域、session、recovery、write | 边界、账号代次、恢复和单次写入 |
| UI | features、query、navigation、visual | 可点击入口、状态、草稿、响应式与 golden |
| Host | ubaa_host/test | 生命周期、平台注入、能力和 callback 接线 |
| 门禁自身 | scripts/tests、离线统计合同 | 入口完整性、账号隔离、依赖环、规模与失败退出 |

不同层的同名业务测试不能据此认定重复。合并限于同一边界、输入和故障保护；删除时记录替代用例。保留 unknown 禁止重发、最多一次写入、账号/路线隔离、迟到结果、安全材料和错误传播等独有分支。

公共 API 使用真实 import 与静态签名编译，不检查手写名字清单长度。`WriteOperation` 原有固定数量与首尾断言由 Domain 动作映射、App 写入核对矩阵及云盘 typed 准备/提交回归覆盖替代，写协调器继续检查单次提交和未知结果不重发。写入流程合同由 `WriteCoordinator` 的测试覆盖。行为文件独立注册，共享夹具放 test/support；UI 点击前滚动并确认可命中，不能调用内部 State 跳过入口，也不能依赖前一用例留下的大窗口。golden 字节保持原基线。

云盘 Bridge 回归使用显式持锁和逐次轮询 Future 固定排队顺序，分别核对释放后的文件与分享提交零发送，以及已经发送请求的确定或未知结果。单文件分享 Widget 回归通过实际点击核对刷新、选择个人目的目录、另存回读、明确切库和授权失败的请求序列。

业务时钟测试必须让 Timer 保持在 FakeAsync 中。App 的启动预算和恢复退避用例使用专用合成账号接口，真实账号文件锁继续由其他 App、Host 与 Platform 集成覆盖。真实文件 I/O 应从 `tester.runAsync` 内发起并等待，不能在 FakeAsync 中创建 Future 后只靠 `pumpAndSettle` 等待。独立执行的缓存恢复使用明确的完成事件同步，不能假设会话恢复返回时磁盘任务已经完成。 Host 与 Flutter 宿主需要同时覆盖真实账号集成和虚拟业务时钟时，复用 `widgetAccounts`：在 `runAsync` 中创建真实账号，顶层账号操作在捕获的真实 Zone 内执行，按已发起的 Future 排空 I/O 后用零时长 pump 衔接界面。直接读取账号结果仍在 `runAsync` 中等待。材料事务内部保留原协调器 Zone，避免丢失借锁上下文。私有合成材料在卸载宿主或使控制器失效后等待全部在途事务结束，再删除独占目录。

## SSO、域名回退与共享缓存覆盖

主认证的 UC 必经链用例调整为 SSO 取票验票、无 UC 请求、票据拒绝和 WebVPN 网关独立认证。UC 的 HTTP SSO 升级、嵌套 service 编码、Cookie 路径和重定向预算仍由按需资料读取用例覆盖。未知验票正文保留会话，明确 SSO 失效清理会话；UC 资料失败不能单独注销主会话。

原校外一律 WebVPN 的断言改为 Direct 优先、按域名网络失败回退、24 小时期限、显式路线及写入不重放。原跨路线缓存缺失断言改为共用记录、跨路线替代旧读取和共同失效；账号、日期、分页和查询隔离继续保留。日程投影共用业务内容并保留真实来源，缺失范围仍带当前请求路线。普通所需路线的验证码等待用例明确指定所需路线，另测 Auto 部分成功直接进入并释放多余图片。旧 Auto 校外云盘拒绝用例改为 Direct 可用和显式 WebVPN 未验证能力，写入确认过期、路线变化与零发送保护保留。

## 原生能力与覆盖边界

原生测试保留 `integration_test/platform/`、`synthetic/cache/` 、`synthetic/command/` 的真实 FRB 输入边界和一个 `synthetic/app/` 宿主 smoke：真实安全存储、私有目录、网络、照片、包信息、系统方向、真实 Rust FFI 的离线启动与缺会话处理和缓存。替身后端驱动的登录到首页流程由 `apps/ubaa_flutter/test/app/smoke_test.dart` 覆盖：原生集成绑定不注册测试输入法，应用未取得前台时文本输入不可靠。原生材料测试同时隔离数据域和锁域：Windows 使用私有文件与真实 DPAPI/替换函数，Apple 使用独立 Keychain service，Android 使用独立 Debug 应用 `cn.edu.ubaa.synthetic.materials`，在访问安全存储前核对设备报告的实际包名。Android 专用入口 `scripts/tests/platform/android_materials.py` 先核对 APK 实际包名和 debuggable 属性，再启动真实插件用例，普通构建的生产 ID 和 Release 签名逻辑保持原实现。Linux 通用材料入口仅保留目录验证，整 map 的真实写读保留在 `scripts/tests/linux-secure-storage.sh` 创建的独立 D-Bus、Secret Service 和 XDG 目录中。缺少专用入口标记或目录前提时先拒绝，不探测默认会话。原生适配的合成保护回归覆盖默认域 B、原目标和备份不变，真实原生写读仍由对应平台入口承担。入口、平台、前提和 CI 归属集中在 `scripts/integration-tests.json`，用 `just integration-list` 查看，用 `just integration-test` 执行默认集合：运行时按清单生成被忽略的聚合入口，各入口在同一应用进程中依次运行，合并 Dart define 与持锁夹具，冲突时拒绝；`suite=ci-isolated` 逐文件构建运行，用于排查入口间的状态影响。其他能力选择清单中的精确路径，不对整个目录通配执行。

宿主 smoke 分别验证真实 Bridge/Core 的本地错误传播和替身的正向登录，不包含真实登录、查询及写入的完整链路。原生缓存入口还核对云盘能力 DTO、同步进度与取消句柄，以及固定 Direct 缺会话时在网络前返回认证错误，不请求学校。合成全流程、软键盘专项、真实账号 UI 和常驻预览已按用户决定删除。被普通测试引用的合成数据位于 `apps/ubaa_flutter/test/support/`，不再由单元测试导入原生入口。删除项、保留覆盖与自动化缺口见[范围决定](../archive/history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)。Fixture、Widget 和构建成功不能代替真实原生能力或学校协议证据。

日程 Widget 用例覆盖创建、编辑和删除、三种重复处理范围、完成与重新挂起、学校本地备注/隐藏、导出取消/失败，以及账号或路线变化后的迟到结果。原首页原位展开用例改为四项预览和进入日程待办，末尾事项及原详情单层返回由日程导航回归保留。课程与学业合并后的十二领域继续覆盖状态矩阵、物理点击和无障碍语义。原生缓存 probe 通过真实 FRB、SQLite 和文件写出验证重复编辑、关闭重开及范围快照，不请求学校。系统保存面板和各平台设备结果单独记录。 官方宿主原首页六来源的全量展示断言改为四项预览，签到、提醒设置和作业详情仍从首页实际点击；完整来源投影由原生 home_todo_probe 保留，预览外的事项与返回路径由日程导航回归覆盖。

日程视图回归覆盖选日与视图切换保留筛选、跨午夜与全天日期边界、重叠时段可分别打开、顶部截止条带、默认跨周范围、宽屏备注及刷新选择、360 像素大字体和键盘布局，以及路线变化同时撤销冲突弹窗与编辑器。共享网格的课表行为继续由原有节次、时间轴、重叠课程、滚动和 golden 覆盖。冲突保存回归检查确认前没有写入、返回修改保留输入、继续保存不改变课程，隐藏课程仍保留冲突提示，未知课程或预约的日期占位不被误判为全天冲突。手机回归检查初始焦点日期可见、等待查询返回的刷新保留横纵滚动位置，列表翻周保留全范围或单日筛选；键盘回归检查搜索框保留词语导航，按钮聚焦后可以切换周或月。

桌面宿主只允许单实例：macOS 在 AppDelegate 初始化时发现同 Bundle ID 的其他进程即唤起它并退出，Windows 使用会话级命名互斥量并唤起已有窗口，Linux 由 GApplication 在会话总线上把重复启动转交主实例。该行为没有自动化测试，需在各平台手动重复启动验证。Core 会话文件锁与 resourceBusy 提示继续作为兜底，由 Rust 合同测试覆盖；跨进程启动锁原生集成测试已删除。

关于、照片和 iPad 方向测试保留截图元数据。需要保存 iOS 截图时，显式使用 `test_driver/ui_render.dart`，将 UBAA_UI_EVIDENCE_DIR 设为 `.ubaa_local/` 中本次运行的空子目录；安全校验由共享 evidence_directory 和单元测试保护。软键盘专用驱动已删除。方向用例需要唯一 UBAA_ROTATION_RUN_ID 和外部系统方向握手，不能用修改 Widget 尺寸替代。

Golden 保留既有 macOS 基准，变更基准必须审阅实际差异。`ubaa_ui` 的 `flutter_test_config.dart` 允许不超过 0.2% 的像素差异，吸收 CI 与本机的字体抗锯齿差别，可见的颜色、间距和布局变化仍会失败；测试里的固定时钟使用带 `+08:00` 的校园时刻，不随运行机器时区变化。运行媒体遵守 [AGENTS 安全边界](../../AGENTS.md#安全边界)。offline_startup/analyze.py 只保留历史测量材料分析，不再提供已删除 driver 的测量启动器。

## 首页投影覆盖的归属

首页编排由 App 的 `test/home/` 覆盖缓存首屏、教学周日期选择、投影合并、账号切换与首批完成。UI 的 `home_harness.dart`、`home_shell_harness.dart` 复用生产 `HomeCoordinator`，保留既有日课表、待办、签到、错误重试与导航交互测试。原 UI“先忙后闲即完成刷新”的断言改为等待应用层明确完成信号，首批可展示后后台继续读取的覆盖迁入 `refresh_completion_test.dart`。学期与教学周旧代测试改用整页刷新建立新代，局部重试不影响其他缓存由 `home_parallel_test.dart` 保留。

单项目标恢复测试核对共享账号代次和后端绑定次数不变，主会话重绑仍重新准备旧计划。批次关闭回归覆盖客户端已关闭时的异步收尾。原生本机生命周期替身允许读取本地路线配置，仍拒绝网络入口。课表入口和选择面板、研讨室分段导航、阳光记录翻页与日程重复范围测试使用当前控件，原行为断言保留；课表窄屏大字表头基准图随单行修复更新。

身份复用测试分别验证 Direct/WebVPN 的请求计数、批次结束、旧批次收尾、强制失效、重新登录、路线变化与派生读取撤销。测试计数只证明请求合并，不作为真实网络耗时。

1c-b 移除 Domain 中按来源筛选、排序和判断紧迫的实现。原 `home_todo_test.dart` 的九组学校来源预期迁到原生 `synthetic/cache/home_todo_probe.dart`，通过生产 App 字段适配与真实 FFI 调用 Core。原 `home_calendar_test.dart` 的格式化和 48 小时判断中，业务边界由 Core `agenda::school_tests` 保留，格式化在原生预期中核对。Domain 继续保留课程日历测试。

Core 新增无缓存七来源等价、输入逐组到达顺序、本地完成/隐藏/清除/重新挂起及已退出库失败用例。App 验证日程打开不阻塞学校投影、覆盖失败与缓存保存失败分列、迟到结果与错误撤销、实际考试学期保留及无缓存签到跨校园午夜拒绝。Widget 测试只接收合成的已投影结果，继续验证首页预览、展开、时间刷新触发、签到流程和原功能导航，不维护学校筛选算法。

## 命令宿主替换后的覆盖

`cli_contract`、`command_boundary` 和 `identity_lifecycle` 迁到公共命令 crate，保留全部协议 Mock、JSON/退出码、输入顺序、照片文件变化和身份能力回归。Core-live 的参数、子进程与源码分层检查迁到 `tools/core_live`。无效 Cgyy 内部验证码输入改在公共准备阶段验证，并继续检查安全 JSON 和敏感字段拒绝。

| 删除的旧入口或测试 | 保留覆盖 |
|---|---|
| Rust 二进制宿主的 help、参数、stdin 和进程输出用例 | 公共 parser/prepare 和输出队列测试，Dart 命令调度，以及 macOS Engine/Linux AOT 的真实进程验收 |
| 旧 CLI 独立索引、Keychain worker、路径锁与登记测试 | Platform 共享账号/材料事务的进程测试，Core 身份能力测试，Bridge 固定共享代次和生命周期测试 |
| 旧本机取消适配 | `agenda::tests::本机取消与期限均保留_v13_storage退出码` |
| 旧原生 Keychain 索引加本机日程读取 | 独立合成材料的 GUI/命令进程互通，实际平台安全材料测试分别报告 |
| 旧宿主自行拥有路线和 Session 的结构断言 | 公共命令使用 facade 的分层检查、固定路线协议 Mock 和受限注销能力测试 |

原生进程验收覆盖普通关闭、外部撤销、两个进程修改同库、重复范围和 ICS 文件交付。Linux 专用隔离 Secret Service 另验证原插件和新传输双向兼容、无显示运行、无服务及锁定失败。Windows 原生运行和真实已有材料连续性单独登记，合成进程通过不填补这些缺口。

隔离命令 target 位于 `apps/ubaa_flutter/integration_test/synthetic/command/entry.dart`。构建必须提供私有 `UBAA_COMMAND_EVIDENCE_DIR`，材料、协调锁和业务数据库都位于该目录。普通 `--config-dir` 只覆盖业务目录，不能代替材料隔离。运行日志与媒体继续放 `.ubaa_local/`。

命令输入边界通过真实 parser/prepare 和生产 Runtime 核对空密码、错误阳光时间及缺失照片，材料工厂和学校客户端调用均为零。阳光照片准备后删除原文件的回归继续使用已准备的字节。恢复调度覆盖同账号外部继任后的新客户端单次执行，以及 cancelled、deadline、superseded 的独立结果。

日程独立快照的协调器覆盖保留账号关闭、路线变化、取消、同秒编辑、持久化失败、本机清除和删除防复活。旧共享文件的基版竞争覆盖改由双设备独立发布与逐记录合并覆盖，未知结果只读冻结。新增最高发布序号选择、坏快照整轮失败、跨进程唯一发布、持久成功回执和清除后的无正文在途覆盖。

应用服务的启动配置限流测试使用可控配额验证 IP 分桶、超额返回 429 和其他 IP 的独立额度。运行时测试另外调用原生 BOOTSTRAP_LIMIT 绑定，上报与删除测试保留原生限流耗尽覆盖。测试不通过连续发送 600 次请求来依赖真实分钟窗口。

## CI 执行分组

合并验收将 Flutter 格式与分析和测试分开，测试按包和 UI 文件组分配到独立托管运行器。所有 test 目录中的 *_test.dart 均进入一组，visual/golden 组保持 macOS 渲染。完整 Rust 测试继续在 Linux、macOS 和 Windows 执行，涵盖全部工作区目标。两个生产宿主用明确包列表在独立作业构建，共用生产依赖编译结果，不包含测试辅助 crate；默认 feature 与测试注入负向编译检查继续分别执行。Android 的 arm64-v8a、armeabi-v7a、x86_64 分配到三个托管作业，每个 APK 检查对应 Flutter/Rust 动态库，并拒绝混入其他 ABI。默认本地构建入口仍保留全部架构。

缓存续租测试保留 4,100 轮事务、回收边界与过期请求断言，仅在本测试连接使用内存回滚日志并关闭同步刷盘；磁盘持久化、重开和并发测试继续使用正常连接。详情核验期限继续覆盖正常期限、临近截止、最近截止、未知及无效截止和临近窗口内外等九种场景，使用原参数、期望请求数与独立数据库。
