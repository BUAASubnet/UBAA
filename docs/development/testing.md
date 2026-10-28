# 测试策略与日常入口

当前合同：CLI JSON schema v12；Flutter bridge contract v42。CLI 验证 human/JSON schema v12，版本常量、JSON Schema、Dart 接受版本与现行文档由 `just contract-version-check` 同步检查。旧升级流水见[历史指南](../migration/history/testing-before-2026-10-07.md)。

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
| CLI 及二进制 E2E | apps/ubaa_cli/tests | 参数、真实进程输出、schema、退出码与脱敏 |
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

默认集合包含已登记的应用流程、合成 FFI 缓存、本地网络恢复与真实插件通道；macOS CI 使用同一集合。其余原生用例按清单路径显式运行。platforms 表示入口适用条件，不表示本轮已验证全部平台。

人工巡检在 apps/ubaa_flutter 下单独启动，例如：

```bash
flutter run -d macos -t integration_test/manual/app/flow_driver.dart
```

manual/live 永不进入默认 CI。真实只读的 environment 与 defines 见清单；启动测量 driver 还需独立材料空间和 `scripts/live/offline_startup/run.py` 的显式参数。不要对整个 integration_test 目录执行通配测试。截图和录屏进入仓库外私有目录。

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

真实只读遵循 goal.md 路线与授权边界；当前整改不主动发起真实账号验证。Fixture、Mock、空数据和 unavailable 不等于当前候选真实成功。实际结果见[当前状态](../migration/status.md)。

### 全平台合成数据预览

人工入口为 `apps/ubaa_flutter/integration_test/manual/preview/preview_driver.dart`。它直接注入 `PreviewBackend`、内存凭据库、权限和照片实现，不初始化 FRB，不读取本机账号，不请求学校服务。登录页填写任意非空账号和密码即可进入。全部业务数据为合成内容，写入只改变当前进程的内存状态，重启后恢复初始数据。不要在此入口填写真实账号或个人信息。

在 `apps/ubaa_flutter` 中运行：

```sh
flutter run -d <设备ID> -t integration_test/manual/preview/preview_driver.dart
flutter run -d macos -t integration_test/manual/preview/preview_driver.dart --dart-define=UBAA_UI_STATE=many
```

相同入口适用于工程支持的 iOS、Android、macOS、Windows、Linux。设备 ID 通过 `flutter devices` 查询；桌面端也可使用 `macos`、`windows`、`linux`。各平台需要各自的 Flutter 原生构建环境。本入口仅在集成目录清单登记为 `manual`、`runner: run`、`ci: false`，不属于自动回归套件。

`UBAA_UI_STATE` 支持以下值：

| 值 | 行为 |
| --- | --- |
| `normal` | 常规 typed 内容和本地写入 |
| `empty` | 空业务列表，保留课表学期、教学周选择 |
| `loading` | 业务读取延迟 8 秒后返回 |
| `first-error` | 同一查询范围第一次失败，重试恢复 |
| `stale` | 同一查询范围首次成功，后续读取失败，用于检查旧内容保留 |
| `long` | 长标题、长正文，增加时间待定课程 |
| `many` | 大量课程、作业、座位等条目，增加时间待定课程 |

学业数据包含三个学期、以运行当天为第 8 周的 18 周校历、14 节作息、已安排与未安排考试、百分制与等级制成绩，以及两校区各四栋楼、每栋八间空教室。首页单日课表使用 typed 投影。`long`、`many` 中的时间待定课程会触发现有首页的日期完整性保护。

图书馆与研讨室预约、取消、博雅选退、签到、评教和阳光打卡可在内存中提交并回读；iHome 支持列表、详情、公告及本地关注和支持。个人资料使用合成身份。课表同步模拟 18 周进度，不写入实际课表缓存。

当前边界：窄屏空教室页面没有校区、日期选择器，现有产品代码仅在宽屏展示这些控件。图书馆合成分区未关联平面图，因此显示“当前分区暂无平面图”。系统级通知、桌面组件、真实相册、定位、离线持久化及真实认证不属于该内存入口的模拟范围。iHome 列表提供分页、关键词和个人范围过滤，排序和分类选择不模拟服务端排序差异。状态模式用于主要业务读取，不覆盖系统设置和所有辅助元数据请求。页面截图与录屏只能保存在仓库外私有目录。
