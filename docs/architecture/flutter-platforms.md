# Flutter 六平台版本与验收矩阵

状态：P0 进行中
更新：2026-09-01

本文件记录可复现工具链事实和实际验证结果。版本“理论支持”不等于 UBAA 已验证；只有带日期、命令和产物/设备证据的行才能标记通过。

## 1. 锁定候选

| 组件 | 候选版本/提交 | 本机位置 | 证据 |
|---|---|---|---|
| 官方 Flutter | 3.41.9 / `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694` | `/Users/moorefoss/Dev/flutter-3.41.9` | `flutter --version` |
| Dart | 3.11.5 | 随上述两个 SDK | 两个 SDK 的 `flutter --version` |
| OHOS Flutter fork | tag `3.41.10-ohos-1.0.1` / `adaf911c35c9136a7d18fc424d714c9ec7724e60` | `/Users/moorefoss/Dev/flutter-ohos-3.41.10` | fork release note 与 Git 提交 |
| FRB | 2.13.0 | Cargo/pub 锁文件 | Dart/Rust/codegen/macros 必须完全一致 |
| Rust | 1.95.0 | `rust-toolchain.toml` | `rustc --version` |
| DevEco/CLI | 26.0.0 Beta2（待安装） | 待定 | OHOS fork release note |
| OpenHarmony SDK | build/target API 26（待安装） | 待定 | OHOS fork release note |

官方资料：

- Flutter 支持矩阵：https://docs.flutter.dev/reference/supported-platforms
- Flutter 平台通道/插件：https://docs.flutter.dev/platform-integration/platform-channels
- Flutter native binding：https://docs.flutter.dev/platform-integration/bind-native-code
- FRB package：https://pub.dev/packages/flutter_rust_bridge
- FRB 版本一致性：https://cjycode.com/flutter_rust_bridge/guides/miscellaneous/compatibility
- FRB Cargokit：https://cjycode.com/flutter_rust_bridge/manual/integrate/builtin
- FRB HarmonyOS：https://cjycode.com/flutter_rust_bridge/guides/miscellaneous/harmony-os
- CPF-Flutter fork：https://gitcode.com/CPF-Flutter/flutter_flutter
- DevEco 历史版本：https://developer.huawei.com/consumer/cn/deveco-studio/archive/

## 2. 产品目标

| 平台 | 目标系统 | 架构 | 当前状态 |
|---|---|---|---|
| Windows | Windows 10/11 | x64；arm64 后续 | 宿主生成，尚未在 Windows 构建 |
| macOS | macOS 12+ | arm64；x64 兼容构建 | 本机可用于首个闭环 |
| Linux | Ubuntu 22.04/24.04、Debian 12 | x64 | 宿主生成，尚未在 Linux 构建 |
| Android | API 24+，重点 API29/API35 | arm64-v8a；模拟器 x64 | 宿主生成，Android SDK/NDK 待定稿 |
| iOS | iOS 15+ | arm64；模拟器 arm64 | 宿主生成，签名/真机待验证 |
| HarmonyOS | build/target API26，理论 runtime API17+ | arm64-v8a | fork 已安装；匹配 SDK/DevEco 与真机待完成 |

版本页面展示的区间只用于选择候选。UBAA 的承诺以本表实际通过范围为准。

## 3. OHOS 已知边界

本机现有 DevEco Studio 6.0.1/SDK API21 只能用于探索。使用当前 fork 构建空 HAP 时，ArkTS 因 `AutoFillType`、`ViewData`、`AutoFillTriggerType`、`CompetitionStrategy` 等 API26 符号缺失而失败。OpenHarmony 5.1 公共 API18 包还缺少 DevEco 所需组件，也低于当前 fork 的构建要求，因此不能用它宣称兼容。

P0 必须完成：

1. 安装与 fork release note 匹配的 DevEco/Command Line Tools 26.0.0 Beta2 和完整 API26 SDK。
2. 空应用构建签名 HAP。
3. 生成 FRB/Cargokit arm64 产物，确认 HAP 包含 `libs/arm64-v8a/librust_*.so`。
4. 在实体 HarmonyOS 设备上完成启动、FRB hello、应用私有目录、网络和 HUKS smoke。
5. 记录 `runtimeOS`、`compatibleSdkVersion`、build/target API 和 SDK 组件版本，防止“SDK component missing”类混配。

## 4. 可复现命令

```sh
export PATH=/Users/moorefoss/Dev/flutter-3.41.9/bin:$PATH
flutter --version
flutter doctor -v

cd /Users/moorefoss/Code/UBAA/apps/ubaa_flutter
flutter pub get
flutter analyze
flutter test
flutter build macos --debug

cd /Users/moorefoss/Code/UBAA
cargo test --locked -p ubaa-flutter-bridge
flutter_rust_bridge_codegen generate
```

OHOS 命令必须在匹配 API26 工具链安装后写入；当前不记录一个已知会失败的伪基线。

## 5. 验收记录模板

| 日期 | 平台/设备 | SDK/架构 | 命令/产物 | 启动 | FRB | 登录模拟 | 安全存储 | 只读 smoke | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| 待填 | macOS 本机 | 3.41.9/arm64 | 待填 | 待填 | 待填 | 待填 | 待填 | 待填 | 首个闭环 |

任何失败要保留安全的错误类别、工具版本和阶段，不保留凭据、个人数据或原始上游响应。

## 6. P0 探索产物审查

| 产物 | 采用结论 | P0 证据 | 后续约束 |
|---|---|---|---|
| `apps/ubaa_flutter` 五平台官方宿主 | 保留生成宿主与薄入口作为构建起点 | 官方 `3.41.9` analyze/test 通过，五个平台目录齐全 | 默认 Demo backend 仅限测试/预览，Release 前必须由 FRB production backend 替换 |
| `apps/ubaa_ohos` | 保留共享入口、版本说明与工具链预检 | fork 提交与 Dart 版本匹配 | 尚无可验收 API26 工程/HAP；完成匹配工具链后重新生成宿主，不手工伪造 |
| `ubaa_domain`、`ubaa_app`、`ubaa_platform` | 保留为分层骨架 | 官方 SDK analyze/test 通过 | 当前仅有摘要模型与内存/回调适配，不能作为完整功能或安全存储实现 |
| `ubaa_ui` | 保留主题、响应式导航和基础状态组件 | analyze 通过；P0 补充 widget 基线测试 | 摘要卡片、占位详情和“即将接入”均明确未验收，P3/P4 必须逐领域替换 |
| Demo backend、交互验证码字段 | 不作为生产合同采用 | Core 当前未证明通用交互验证码；Demo 不访问 Core | P1/P2 移除生产默认 Demo，并按稳定 bridge 合同收敛登录状态 |

P0 的“保留”只表示允许作为后续实现起点，不表示满足 `goal.md` 的功能、平台或发布完成条件。
