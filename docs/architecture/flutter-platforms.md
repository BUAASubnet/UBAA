# Flutter 六平台版本与验收矩阵

本页供处理平台构建、平台能力和工具链升级的贡献者使用，列出锁定的工具链、各平台目标、平台能力的边界和 FRB 生成规则。各平台的实际验证结果见[状态页](../project/status.md)；P0–P6 阶段的构建与验收记录见[归档快照](../archive/history/flutter-platforms-2026-11-11.md)。

“理论支持”不等于 UBAA 已验证。平台只有在具备日期、命令以及产物或设备证据时才算通过，这些结果记录在状态页。

## 1. 锁定工具链

| 组件 | 版本/提交 | 配置入口 | 核对方式 |
|---|---|---|---|
| 官方 Flutter | 3.41.9 / `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694` | `$UBAA_FLUTTER_HOME` | `flutter --version` |
| Dart | 3.11.5 | 随上述两个 SDK | 两个 SDK 的 `flutter --version` |
| OHOS Flutter fork | tag `3.41.10-ohos-1.0.1` / `adaf911c35c9136a7d18fc424d714c9ec7724e60` | `$UBAA_OHOS_FLUTTER_HOME` | fork release note 与 Git 提交 |
| FRB | 2.13.0 | Cargo/pub 锁文件 | Dart/Rust/codegen/macros 必须完全一致 |
| Rust | 1.95.0 | `rust-toolchain.toml` | `rustc --version` |
| DevEco/CLI | 26.0.0.821 / Hvigor 6.26.4 / ohpm 26.0.0.630 | `$UBAA_DEVECO_HOME` | `check-toolchain.sh` 双布局预检 |
| OpenHarmony SDK | API 26 / platform 26.0.0 | 上述 DevEco/CLI 的 `sdk` | `check-toolchain.sh` 与 `sdk-pkg.json` |

精确版本以 [`scripts/tools/versions.env`](../../scripts/tools/versions.env) 和锁文件为准，安装步骤见[开发环境](../development/setup.md)。

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

| 平台 | 目标系统 | 架构 |
|---|---|---|
| Windows | Windows 10/11 | x64；arm64 后续 |
| macOS | macOS 12+ | arm64；x64 兼容构建 |
| Linux | Ubuntu 22.04/24.04、Debian 12 | x64 |
| Android | API 24+，重点 API29/API35 | arm64-v8a；模拟器 x64 |
| iOS | iOS 15+ | arm64；模拟器 arm64 |
| HarmonyOS | build/target API26，理论 runtime API17+ | arm64-v8a |

版本页面展示的区间只用于选择工具链；UBAA 的承诺以状态页记录的实际通过范围为准。正式分发的产物与渠道见[发布流程](../runbooks/flutter-release.md)。

## 3. OHOS 边界

- 工程 `build-profile.json5` 使用 `compatibleSdkVersion`/`targetSdkVersion` `"26.0.0"`，Hvigor 与工程 `modelVersion` 为 `6.0.0`。
- 根级门禁固定匹配安装中的 hvigor、ohpm、Node 和 SDK，兼容 DevEco Studio 的 `tools/...` 与 Command Line Tools 的 `tool/...` 两种布局。
- 正式构建需要签名配置。没有签名材料或实体设备时，`UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug` 生成并检查 `entry-default-unsigned.hap`，包内 Rust bridge 为 `libs/arm64-v8a/libubaa_bindings.so`。
- 无签名构建只用于包内容与动态库检查，不能作为平台完成、发布或实体设备证据。
- 签名 HAP，以及实体 HarmonyOS 设备上的启动、FRB 调用、私有目录、网络、权限和 HUKS smoke，是发布前的独立条件。缺少证书或设备时记录为 `BLOCKED`，不把无签名包标为平台完成。

无签名检查覆盖：

1. 在不读取或写入签名凭据的前提下，预检匹配的 DevEco/CLI、API26 SDK 和工程配置。
2. 生成 FRB/Cargokit arm64 产物，确认无签名 HAP 包含 `libs/arm64-v8a/libubaa_bindings.so`（或同一 bridge 的兼容命名）且架构为 arm64。
3. 对无签名 HAP 执行包结构、动态库和加载前置的静态检查，保留可复核的命令输出。
4. 记录 `runtimeOS`、`compatibleSdkVersion`、build/target API 和 SDK 组件版本，防止“SDK component missing”类混配。

宿主细节见 [OHOS 宿主说明](../../apps/ubaa_ohos/README.md)。

## 4. 平台能力

### 4.1 共享平台通道

`ubaa_platform` 通过 `cn.edu.buaa.ubaa/platform` MethodChannel 暴露稳定边界：

| 方法 | 边界 |
|---|---|
| `permission.request` | 返回固定的权限状态 |
| `photo.capability/pick` | 只传递受限的图片字节、展示名和 MIME |
| `location.capability/current` | 提供受类型与范围约束的位置坐标 |

`createDefaultPlatformCapabilities()` 在宿主启动时探测照片和位置等能力。缺少原生 handler 或返回值不符合合同时安全归约为不可用，不回退到明文文件、内存凭据或原始路径。能力的具体实现见 [ubaa_platform 说明](../../packages/ubaa_platform/README.md)。

### 4.2 安全材料

- 官方五平台使用固定的 `flutter_secure_storage 10.0.0`；OHOS 通过本仓库的 HUKS 插件适配走相同的插件接口。
- 凭据、账号索引和随机业务缓存密钥使用独立命名空间，不枚举或导出已有密钥。
- macOS 使用系统登录钥匙串；固定 darwin 0.2.0 的参数拼写差异在适配层显式兼容，避免误启用需要开发证书的数据保护钥匙串。
- Android 禁止自动备份，iOS 配置 Keychain 权限。

Linux 安全存储的依赖：

- 构建需要 `libsecret-1-dev`（插件要求 libsecret-1 >= 0.18.4）。
- 运行需要 `libsecret-1-0`、可用的 D-Bus 会话和 Secret Service 提供者（例如已解锁的 GNOME Keyring）。
- CI 额外安装 gnome-keyring、dbus-x11、xvfb，只在独立临时 XDG 目录中验证合成材料的写入、重开读回和删除，以及无会话服务时安全失败。构建依赖齐全不代表用户桌面会话已解锁。

### 4.3 照片

照片能力由 [media.dart](../../packages/ubaa_platform/lib/src/media.dart) 定义边界：

- [PluginPhotoPicker](../../packages/ubaa_platform/lib/src/media/plugin_photo.dart) 使用 image_picker 选择或拍摄照片；[DesktopFilePhotoPicker](../../packages/ubaa_platform/lib/src/media/desktop_photo.dart) 使用 file_selector。
- 共享读取校验把图片限制为 10 MiB 内的可解码内容，只把受限的内存字节、展示名与 MIME 交给 Host，不暴露插件路径。
- macOS 只启用用户所选文件的只读访问。
- photos 权限状态表示可以请求系统选择器；所选图片的访问由系统选择结果授予，不代表全量相册授权。原生失败不伪装成取消。
- Android 相机请求沿用插件限制预览尺寸与质量；跨进程遗失的结果只清理，不附回新账号。
- 平台默认能力的选择以 [defaults.dart](../../packages/ubaa_platform/lib/src/defaults.dart) 为准；插件注册成功仍需对应平台验收。

### 4.4 宿主入口与写入

- 两个平台的 `main.dart` 只保留锁定 SDK/FRB 初始化、平台能力工厂和 `runApp` 注入；共享 `ubaa_host` 负责 AppController 生命周期与回调接线。
- 生产默认通过 `createProductionBackend()` 打开 `BridgeBackend`，打开失败才使用 `UnavailableBackend`。Demo 只用于显式注入的测试或预览。
- 写入状态由应用层 `WriteCoordinator` 唯一持有。平台位置获取期间发生会话失效时，不继续准备旧操作。
- 取消类写入口：`BridgeBackend` 可以把图书馆状态名和研讨室订单/审核状态投影为展示字段，但共享 UI 只依据 Core 派生的 typed `cancelEligibility/cancelTarget` 开放入口，不按展示状态、中文文案或时间截止规则自行判断。缺失、格式未知或目标不一致时入口默认关闭；Core prepare/commit 负责最终的资格、时区、会话和上游错误判定。取消沿用一次性写意图，不增加后台重试或跨路线切换。

## 5. 常用构建命令

```sh
# 在仓库根目录执行
just flutter-codegen-check
just flutter-check
just flutter-build platform=macos mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug
cargo test --locked -p ubaa-flutter-bridge
cargo clippy --locked -p ubaa-flutter-bridge --all-targets --all-features -- -D warnings
UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
```

全部命令与检查范围见[开发命令](../development/commands.md)。失败记录只保留安全的错误类别、工具版本和阶段，不保留凭据、个人数据或原始上游响应。

## 6. FRB 生成边界

- `packages/ubaa_bindings/lib/src/rust/` 与 `crates/ubaa_flutter_bridge/src/frb_generated.rs` 是 FRB 2.13.0 的机械生成输出，禁止手改。
- 生成的 FFI 编解码需要 `unsafe`。仓库只在私有 `frb_generated` 模块上局部允许 `unsafe_code` 与生成噪声，bridge crate 的手写模块保持 `unsafe_code=deny` 和严格 Clippy。
- `just flutter-codegen-check` 重新生成，以锁定 Rust toolchain 机械执行 `cargo fmt --all`，并要求零漂移，防止例外扩散到业务代码。

## 7. FFI 依赖

| 依赖 | 固定版本 | 用途 | 许可证 | 平台说明 |
|---|---|---|---|---|
| `flutter_rust_bridge` | `2.13.0` | 生成 Dart/Rust FFI codec 与 runtime | MIT | 六个平台使用同一份生成 Dart API |
| Cargokit | FRB `2.13.0` 随附快照 | 从 Flutter native build 驱动固定的 Rust crate | MIT/Apache-2.0 | Windows 使用 app `CMAKE_SOURCE_DIR` 计算绝对 manifest，避免 plugin junction 的父目录语义差异；OHOS 通过 arm64 HAR/CMake 接线 |

两项依赖都不拥有协议、Cookie、路线或业务 DTO，只负责 FFI 生成与 native library 构建。升级时必须同时更新 Rust crate、Dart package、codegen、Cargokit 快照，并重新取得六平台构建证据，不能只升级其中一处。
