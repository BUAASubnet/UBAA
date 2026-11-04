# 测试策略与日常入口

当前合同：CLI JSON schema v13；Flutter bridge contract v46。CLI 验证 human/JSON schema v13，版本常量、JSON Schema、Dart 接受版本与现行文档由 `just contract-version-check` 同步检查。旧升级流水见[历史指南](../migration/history/testing-before-2026-10-07.md)。

## 检查入口

日常聚焦回归、完整确定性清单、原生专项、真实验证及 CI 的实际范围只在[开发命令](commands.md)维护。本页说明测试设计与证据边界。Dart/Flutter 调用遵守 [AGENTS 工具链规则](../../AGENTS.md#项目工具链入口)。

## 各层的独立责任

| 层级 | 入口 | 保护 |
|---|---|---|
| Core/Fixture/Mock | Core src、tests、ubaa-test-support | 精确请求、解析、加密、认证、路线、缓存与并发 |
| CLI 及二进制 E2E | apps/ubaa_cli/tests | 参数、真实进程输出、schema、退出码与脱敏 |
| FRB/Bindings | Rust Bridge、ubaa_bindings/test、codegen checker | typed DTO、错误、版本、句柄与生成零漂移 |
| App/Domain/Platform | 各包 test 下的领域、session、recovery、write | 边界、账号代次、恢复和单次写入 |
| UI | features、query、navigation、visual | 可点击入口、状态、草稿、响应式与 golden |
| Host | ubaa_host/test | 生命周期、平台注入、能力和 callback 接线 |
| 门禁自身 | scripts/tests、离线统计合同 | 入口完整性、账号隔离、依赖环、规模与失败退出 |

不同层的同名业务测试不能据此认定重复。合并限于同一边界、输入和故障保护；删除时记录替代用例。保留 unknown 禁止重发、最多一次写入、账号/路线隔离、迟到结果、安全材料和错误传播等独有分支。

公共 API 使用真实 import 与静态签名编译，不检查手写名字清单长度。写入流程合同由 `WriteCoordinator` 的测试覆盖。行为文件独立注册，共享夹具放 test/support；UI 点击前滚动并确认可命中，不能调用内部 State 跳过入口，也不能依赖前一用例留下的大窗口。golden 字节保持原基线。

## 原生能力与覆盖边界

原生测试保留 `integration_test/platform/`、`synthetic/cache/` 和一个 `synthetic/app/` 宿主 smoke：真实安全存储、私有目录、网络、照片、包信息、系统方向、真实 Rust FFI 的离线启动与缺会话处理和缓存。替身后端驱动的登录到首页流程由 `apps/ubaa_flutter/test/app/smoke_test.dart` 覆盖：原生集成绑定不注册测试输入法，应用未取得前台时文本输入不可靠。入口、平台、前提和 CI 归属集中在 `scripts/integration-tests.json`，用 `just integration-list` 查看，用 `just integration-test` 执行默认集合：运行时按清单生成被忽略的聚合入口，各入口在同一应用进程中依次运行，合并 Dart define 与持锁夹具，冲突时拒绝；`suite=ci-isolated` 逐文件构建运行，用于排查入口间的状态影响。其他能力选择清单中的精确路径，不对整个目录通配执行。

宿主 smoke 分别验证真实 Bridge/Core 的本地错误传播和替身的正向登录，不包含真实登录、查询及写入的完整链路。合成全流程、软键盘专项、真实账号 UI 和常驻预览已按用户决定删除。被普通测试引用的合成数据位于 `apps/ubaa_flutter/test/support/`，不再由单元测试导入原生入口。删除项、保留覆盖与自动化缺口见[范围决定](../migration/history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)。Fixture、Widget 和构建成功不能代替真实原生能力或学校协议证据。

日程 Widget 用例覆盖创建、编辑和删除、三种重复处理范围、完成与重新挂起、学校本地备注/隐藏、导出取消/失败，以及账号或路线变化后的迟到结果。原首页原位展开用例改为四项预览和进入日程待办，末尾事项及原详情单层返回由日程导航回归保留。课程与学业合并后的十二领域继续覆盖状态矩阵、物理点击和无障碍语义。原生缓存 probe 通过真实 FRB、SQLite 和文件写出验证重复编辑、关闭重开及范围快照，不请求学校。系统保存面板和各平台设备结果单独记录。 官方宿主原首页六来源的全量展示断言改为四项预览，签到、提醒设置和作业详情仍从首页实际点击；完整来源投影由原生 home_todo_probe 保留，预览外的事项与返回路径由日程导航回归覆盖。

桌面宿主只允许单实例：macOS 在 AppDelegate 初始化时发现同 Bundle ID 的其他进程即唤起它并退出，Windows 使用会话级命名互斥量并唤起已有窗口，Linux 由 GApplication 在会话总线上把重复启动转交主实例。该行为没有自动化测试，需在各平台手动重复启动验证。Core 会话文件锁与 resourceBusy 提示继续作为兜底，由 Rust 合同测试覆盖；跨进程启动锁原生集成测试已删除。

关于、照片和 iPad 方向测试保留截图元数据。需要保存 iOS 截图时，显式使用 `test_driver/ui_render.dart`，将 UBAA_UI_EVIDENCE_DIR 设为 `.ubaa_local/` 中本次运行的空子目录；安全校验由共享 evidence_directory 和单元测试保护。软键盘专用驱动已删除。方向用例需要唯一 UBAA_ROTATION_RUN_ID 和外部系统方向握手，不能用修改 Widget 尺寸替代。

Golden 保留既有 macOS 基准，变更基准必须审阅实际差异。`ubaa_ui` 的 `flutter_test_config.dart` 允许不超过 0.2% 的像素差异，吸收 CI 与本机的字体抗锯齿差别，可见的颜色、间距和布局变化仍会失败；测试里的固定时钟使用带 `+08:00` 的校园时刻，不随运行机器时区变化。运行媒体遵守 [AGENTS 安全边界](../../AGENTS.md#安全边界)。offline_startup/analyze.py 只保留历史测量材料分析，不再提供已删除 driver 的测量启动器。

## 首页投影覆盖的归属

1c-b 移除 Domain 中按来源筛选、排序和判断紧迫的实现。原 `home_todo_test.dart` 的九组学校来源预期迁到原生 `synthetic/cache/home_todo_probe.dart`，通过生产 App 字段适配与真实 FFI 调用 Core。原 `home_calendar_test.dart` 的格式化和 48 小时判断中，业务边界由 Core `agenda::school_tests` 保留，格式化在原生预期中核对。Domain 继续保留课程日历测试。

Core 新增无缓存七来源等价、输入逐组到达顺序、本地完成/隐藏/清除/重新挂起及已退出库失败用例。App 验证日程打开不阻塞学校投影、覆盖失败与缓存保存失败分列、迟到结果与错误撤销、实际考试学期保留及无缓存签到跨校园午夜拒绝。Widget 测试只接收合成的已投影结果，继续验证首页预览、展开、时间刷新触发、签到流程和原功能导航，不维护学校筛选算法。
