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
| Windows | Windows 10/11 | x64；arm64 后续 | `windows-2025` 原生 debug runner 构建与产物上传通过 |
| macOS | macOS 12+ | arm64；x64 兼容构建 | arm64 debug App 已构建、启动并完成 FRB hello |
| Linux | Ubuntu 22.04/24.04、Debian 12 | x64 | Ubuntu 24.04 原生 debug runner 构建与产物上传通过 |
| Android | API 24+，重点 API29/API35 | arm64-v8a；模拟器 x64 | debug APK 已含三种 ABI 的 FRB 动态库；实体机/签名待验证 |
| iOS | iOS 15+ | arm64；模拟器 arm64 | simulator debug 已链接 FRB universal framework；签名/真机待验证 |
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
cd /Users/moorefoss/Code/UBAA
just flutter-codegen-check
just flutter-check
just flutter-build platform=macos mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug
cargo test --locked -p ubaa-flutter-bridge
cargo clippy --locked -p ubaa-flutter-bridge --all-targets --all-features -- -D warnings
```

OHOS 的完整门禁命令为 `just ohos-check mode=release`；当前仅将其预检失败记录为
工具链阻断，匹配 API26 安装并实际生成 HAP 前不得记录为构建通过。

## 5. 验收记录模板

| 日期 | 平台/设备 | SDK/架构 | 命令/产物 | 启动 | FRB | 登录模拟 | 安全存储 | 只读 smoke | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-01 | macOS 本机 | 3.41.9/arm64 | debug App | 通过 | hello 通过 | 未验证 | 未验证 | 未验证 | 仅 P0 FFI 链路 |
| 2026-09-01 | iOS simulator | 3.41.9/x86_64+arm64 | debug framework | 不适用 | 链接通过 | 未验证 | 未验证 | 未验证 | 无签名/真机证据 |
| 2026-09-01 | Android APK | 3.41.9/三 ABI | debug APK | 未运行 | 三 ABI 打包通过 | 未验证 | 未验证 | 未验证 | 无签名/实体机证据 |
| 2026-09-01 | Windows GitHub runner | 3.41.9/x64 | `ubaa-windows-debug-33450597586` | 不适用 | 链接/打包通过 | 未验证 | 未验证 | 未验证 | `windows-2025` 原生构建 |
| 2026-09-01 | Linux GitHub runner | 3.41.9/x64 | `ubaa-linux-debug-33450597586` | 不适用 | 链接/打包通过 | 未验证 | 未验证 | 未验证 | Ubuntu 24.04 原生构建 |
| 2026-09-01 | HarmonyOS | 3.41.10-ohos-1.0.1/arm64 | `just ohos-check mode=debug` | 阻断 | 阻断 | 阻断 | 阻断 | 阻断 | runner 已生成；DevEco 26/API26 缺失 |

任何失败要保留安全的错误类别、工具版本和阶段，不保留凭据、个人数据或原始上游响应。

## 6. P0 探索产物审查

| 产物 | 采用结论 | P0 证据 | 后续约束 |
|---|---|---|---|
| `apps/ubaa_flutter` 五平台官方宿主 | 保留生成宿主与薄入口作为构建起点 | 官方 `3.41.9` analyze/test 通过，五个平台目录齐全 | 默认 Demo backend 仅限测试/预览，Release 前必须由 FRB production backend 替换 |
| `apps/ubaa_ohos` | 保留共享入口并用锁定 fork 生成官方 runner | fork 提交/Dart 匹配，pub get、analyze、widget test 通过 | arm64 Cargokit/FRB 已接线；尚无 API26 HAP、签名或设备证据 |
| `ubaa_domain`、`ubaa_app`、`ubaa_platform` | 保留为分层骨架 | 官方 SDK analyze/test 通过 | 当前仅有摘要模型与内存/回调适配，不能作为完整功能或安全存储实现 |
| `ubaa_ui` | 保留主题、响应式导航和基础状态组件 | analyze 通过；P0 补充 widget 基线测试 | 摘要卡片、占位详情和“即将接入”均明确未验收，P3/P4 必须逐领域替换 |
| Demo backend、交互验证码字段 | 不作为生产合同采用 | Core 当前未证明通用交互验证码；Demo 不访问 Core | P1/P2 移除生产默认 Demo，并按稳定 bridge 合同收敛登录状态 |

P0 的“保留”只表示允许作为后续实现起点，不表示满足 `goal.md` 的功能、平台或发布完成条件。

## 7. FRB 生成边界

`packages/ubaa_bindings/lib/src/rust/` 与
`crates/ubaa-flutter-bridge/src/frb_generated.rs` 是 FRB `2.13.0` 的机械生成输出，
禁止手改。生成的 FFI 编解码需要 `unsafe`；仓库仅在私有 `frb_generated` 模块上局部
允许 `unsafe_code` 与生成噪声，bridge crate 的手写模块仍保持 `unsafe_code=deny` 和
严格 Clippy。`just flutter-codegen-check` 重新生成、以锁定 Rust toolchain 机械执行
`cargo fmt --all` 并要求零漂移，防止例外扩散到业务代码。

## 8. 新依赖审计

| 依赖 | 固定版本 | 用途 | 许可证 | 五平台状态 | OHOS 状态 |
|---|---|---|---|---|---|
| `flutter_rust_bridge` | `2.13.0` | 生成 Dart/Rust FFI codec 与 runtime | MIT | Windows、Linux、macOS、iOS simulator、Android 原生 runner 均已实际链接 | Dart API/HAR 已接线，HAP 受 API26 阻断 |
| Cargokit | FRB `2.13.0` 随附快照 | 从 Flutter native build 驱动固定 Rust crate | MIT/Apache-2.0 | 五平台均通过；Windows 使用 app `CMAKE_SOURCE_DIR` 计算绝对 manifest，避免 plugin junction 的父目录语义差异 | arm64 HAR/CMake 已接线，HAP 受 API26 阻断 |

两项依赖都不拥有协议、Cookie、路线或业务 DTO；它们只负责 FFI 生成与 native library
构建。版本升级必须同时更新 Rust crate、Dart package、codegen、Cargokit 快照和六平台
构建证据，禁止只升级其中一处。

## 9. P0 风险与 go/no-go

| 风险 | 当前证据 | 影响 | 处置与门禁 |
|---|---|---|---|
| GitHub Actions Node.js 20 运行时进入弃用迁移 | 成功 run `33450597586` 对 `checkout@v4`、`upload-artifact@v4` 给出强制 Node.js 24 警告 | 当前不影响产物，但后续 runner 可能停止兼容旧 action runtime | P1 前期按官方 action 版本说明升级并以完整 CI/native run 复验 |
| OHOS 工具链版本不满足合同 | DevEco `6.0.1.251`、API21；预检明确失败 | 无法生成可验收 HAP 或设备 FRB hello | 仅安装 DevEco/CLI26 与完整 API26 后重跑；不得用 API18/21 降级 |
| OHOS 下载入口需要华为账号 | 未登录、未传输账号信息 | 工具链取得受外部账号与授权约束 | 取得项目所有者明确授权后才登录或使用受限下载 |
| 正式签名材料未提供 | 仅有无签名 debug/simulator 产物 | P0 空 HAP 与 P6 正式发布均不能完成 | Apple、Google、Microsoft、HarmonyOS 账号/证书单独授权并安全注入 |
| 当前 Flutter UI 仍含探索 Demo/占位 | P0 仅验证宿主与 hello | 不能作为 P1 至 P6 功能完成证据 | P1 固定 bridge 合同，P2/P3/P4 逐项移除并以测试闭环 |

当前结论为 **NO-GO（正式发布）/ GO（继续五平台 P1 开发）**。官方 Flutter 五平台
native debug 矩阵已在 run `33450597586` 全部通过并上传独立产物，合同与 macOS/Windows
Rust job 也在 run `33450597476` 全部通过；OHOS API26、签名 HAP 与实体机 hello 仍为
硬阻断。该结论只允许继续不依赖签名和真实写入的实现、确定性测试及只读验证，不允许将
任何 debug 产物称为正式版。
