# 测试策略与日常入口

当前合同：CLI JSON schema v11；Flutter bridge contract v40。CLI 验证 human/JSON schema v11，版本常量、JSON Schema、Dart 接受版本与现行文档由 `just contract-version-check` 同步检查。旧升级流水见[历史指南](../migration/history/testing-before-2026-10-07.md)。

## 按修改范围运行

```bash
just refs
just flutter-test ubaa_app test/features/grades
just flutter-test ubaa_ui test/features/grades
just flutter-test ubaa_host test/recovery
just module-check
just integration-check
```

`flutter-test` 使用固定官方 SDK，仅运行指定包的普通 test 路径，不解析依赖、不选择设备或真实账号。首次准备依赖或完整分析时用 `just flutter-check`。Rust 聚焦回归使用 `cargo test --locked -p <crate> <过滤名>`；Core facade 注入需 `--features test-contract`，完整开启/关闭态由 `just core-test-contract` 验证。

## 各层的独立责任

| 层级 | 入口 | 保护 |
|---|---|---|
| Core/Fixture/Mock | Core src、tests、ubaa-test-support | 精确请求、解析、加密、认证、路线、缓存与并发 |
| CLI 及二进制 E2E | apps/ubaa-cli/tests | 参数、真实进程输出、schema、退出码与脱敏 |
| FRB/Bindings | Rust Bridge、ubaa_bindings/test、codegen checker | typed DTO、错误、版本、句柄与生成零漂移 |
| App/Domain/Platform | 各包 test 下的领域、session、recovery、write | 边界、账号代次、恢复和单次写入 |
| UI | features、query、navigation、visual | 可点击入口、状态、草稿、响应式与 golden |
| Host | ubaa_host/test | 生命周期、平台注入、能力和 callback 接线 |
| 门禁自身 | scripts/tests、离线统计合同 | 入口完整性、账号隔离、依赖环、规模与失败退出 |

不同层的同名业务测试不能据此认定重复。合并限于同一边界、输入和故障保护；删除时记录替代用例。保留 unknown 禁止重发、最多一次写入、账号/路线隔离、迟到结果、安全材料和错误传播等独有分支。

公共 API 使用真实 import 与静态签名编译，不检查手写名字清单长度。旧 WriteFlowController 是同一协调器的兼容入口，独有错误/返回值合同归 `ubaa_app/test/write/compatibility_test.dart`。行为文件独立注册，共享夹具放 test/support；UI 点击前滚动并确认可命中，不能调用内部 State 跳过入口，也不能依赖前一用例留下的大窗口。golden 字节保持原基线。

## 原生、真实与人工入口

```bash
just integration-list
just integration-test
just integration-test synthetic/cache/bridge_test.dart macos macos
```

默认集合只包含已登记的应用流程、合成 FFI 缓存与本地网络恢复；macOS CI 使用同一集合。其余原生用例按清单路径显式运行。platforms 表示入口适用条件，不表示本轮已验证全部平台。

人工巡检在 apps/ubaa_flutter 下单独启动，例如：

```bash
flutter run -d macos -t integration_test/manual/app/flow_driver.dart
```

manual/live 永不进入默认 CI。真实只读的 environment 与 defines 见清单；启动测量 driver 还需独立材料空间和 `scripts/live/offline-startup/run.py` 的显式参数。不要对整个 integration_test 目录执行通配测试。截图和录屏进入仓库外私有目录。

## 完整确定性门禁

```bash
just refs
just check-sensitive
just check-strict
just flutter-check
CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check
just integration-test
git diff --check
```

check-strict 要求 ShellCheck 0.11.0；普通 check 缺少它时明确 SKIP。两者均包含 Rust/CLI、Shell/Python、结构、模块与入口清单检查。普通 Flutter 七包测试不能替代原生测试；golden 固定官方 SDK 与 macOS 渲染环境。构建、设备、Core-live、真实 App 和发布分别记账。

真实只读遵循 goal.md 路线边界，本轮校外仅 WebVPN，Direct 不执行。Fixture、Mock、空数据和 unavailable 不等于当前候选真实成功。实际结果见[当前状态](../migration/status.md)。
