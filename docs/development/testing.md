# 测试策略与日常入口

当前合同：CLI JSON schema v12；Flutter bridge contract v42。CLI 验证 human/JSON schema v12，版本常量、JSON Schema、Dart 接受版本与现行文档由 `just contract-version-check` 同步检查。旧升级流水见[历史指南](../migration/history/testing-before-2026-10-07.md)。

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

原生测试保留 `integration_test/platform/`、`synthetic/cache/` 和一个 `synthetic/app/` 宿主 smoke：真实安全存储、私有目录、网络、照片、包信息、系统方向、使用替身的登录到首页接线、真实 Rust FFI 的离线启动与缺会话处理、缓存和跨进程启动锁。入口、平台、前提和 CI 归属集中在 `scripts/integration-tests.json`，用 `just integration-list` 查看，用 `just integration-test` 执行默认集合。其他能力选择清单中的精确路径，不对整个目录通配执行。

宿主 smoke 分别验证真实 Bridge/Core 的本地错误传播和替身的正向登录，不包含真实登录、查询及写入的完整链路。合成全流程、软键盘专项、真实账号 UI 和常驻预览已按用户决定删除。被普通测试引用的合成数据位于 `apps/ubaa_flutter/test/support/`，不再由单元测试导入原生入口。删除项、保留覆盖与自动化缺口见[范围决定](../migration/history/2026-10-30-decisions-through-quality-phase3.md#2026-10-29原生集成只保留真实原生能力)。Fixture、Widget 和构建成功不能代替真实原生能力或学校协议证据。

启动锁通过已登记夹具执行：应用在自身沙箱创建临时目录并派生系统 Perl 子进程持有真实 OS 锁，验证不同 PID、等待画面、resourceBusy 与释放后的 FFI 重试。宿主终端不访问应用容器，也不修改系统权限。Perl 从应用继承的 PATH 查找，以兼容 Linux 的安装位置；不依赖终端访问其他 App 数据的权限。Perl 缺失或不能启动时该项应失败，不能改用同进程锁。

关于、照片和 iPad 方向测试保留截图元数据。需要保存 iOS 截图时，显式使用 `test_driver/ui_render.dart`，将 UBAA_UI_EVIDENCE_DIR 设为 `.ubaa_local/` 中本次运行的空子目录；安全校验由共享 evidence_directory 和单元测试保护。软键盘专用驱动已删除。方向用例需要唯一 UBAA_ROTATION_RUN_ID 和外部系统方向握手，不能用修改 Widget 尺寸替代。

Golden 保留既有 macOS 基准，变更基准必须审阅实际差异。运行媒体遵守 [AGENTS 安全边界](../../AGENTS.md#安全边界)。offline_startup/analyze.py 只保留历史测量材料分析，不再提供已删除 driver 的测量启动器。
