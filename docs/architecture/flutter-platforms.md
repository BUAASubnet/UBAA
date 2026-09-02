# Flutter 六平台版本与验收矩阵

状态：无签名执行目标 P0–P6 已完成；签名、设备和原生安全存储为后置发布条件
更新：2026-09-02

本文件记录可复现工具链事实和实际验证结果。版本“理论支持”不等于 UBAA 已验证；只有带日期、命令和产物/设备证据的行才能标记通过。

## 1. 锁定候选

| 组件 | 候选版本/提交 | 本机位置 | 证据 |
|---|---|---|---|
| 官方 Flutter | 3.41.9 / `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694` | `/Users/moorefoss/Dev/flutter-3.41.9` | `flutter --version` |
| Dart | 3.11.5 | 随上述两个 SDK | 两个 SDK 的 `flutter --version` |
| OHOS Flutter fork | tag `3.41.10-ohos-1.0.1` / `adaf911c35c9136a7d18fc424d714c9ec7724e60` | `/Users/moorefoss/Dev/flutter-ohos-3.41.10` | fork release note 与 Git 提交 |
| FRB | 2.13.0 | Cargo/pub 锁文件 | Dart/Rust/codegen/macros 必须完全一致 |
| Rust | 1.95.0 | `rust-toolchain.toml` | `rustc --version` |
| DevEco/CLI | 26.0.0.821 / Hvigor 6.26.4 / ohpm 26.0.0.630（已安装） | `/Applications/DevEco-Studio.app/Contents`；`/Users/moorefoss/Code/bin/command-line-tools` | `check-toolchain.sh` 双布局预检 |
| OpenHarmony SDK | API 26 / platform 26.0.0（已安装） | 上述 DevEco/CLI 的 `sdk` | `check-toolchain.sh` 与 `sdk-pkg.json` |

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
| HarmonyOS | build/target API26，理论 runtime API17+ | arm64-v8a | API26 工具链与无签名 debug HAP 包内容检查通过；签名/真机待完成 |

版本页面展示的区间只用于选择候选。UBAA 的承诺以本表实际通过范围为准。

## 3. OHOS 已知边界

当前 DevEco Studio 与 Command Line Tools 均为 `26.0.0.821`，Hvigor 为 `6.26.4`，ohpm 为
`26.0.0.630`，SDK 为 API26。工程 `build-profile.json5` 使用 `compatibleSdkVersion`/
`targetSdkVersion` `"26.0.0"`，Hvigor 与工程 `modelVersion` 为 `6.0.0`。根级门禁已固定
匹配安装中的 hvigor、ohpm、Node 和 SDK，兼容 Studio `tools/...` 与 CLI `tool/...` 两种布局。

两种安装路径执行 `just ohos-check mode=debug` 时，锁定 fork、native、Dart、工具链和 HAP
assemble 前置均通过；正式构建需要在 DevEco Signing Configs 配置调试签名。没有实体设备时，
可用 `UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug` 生成并检查
`entry-default-unsigned.hap`；当前包内实际的 Rust bridge 名称为
`libs/arm64-v8a/libubaa_bindings.so`。无签名构建不能作为平台完成、发布或实体设备证据。旧
DevEco/API21 的失败仅保留在迁移状态中作为历史记录。

本轮无签名目标必须完成：

1. 在不读取或写入签名凭据的前提下，完成匹配的 DevEco/CLI、API26 SDK 和工程配置预检。
2. 生成 FRB/Cargokit arm64 产物，确认无签名 HAP 包含
   `libs/arm64-v8a/libubaa_bindings.so`（或同一 bridge 的兼容命名）且架构为 arm64。
3. 对无签名 HAP 执行包结构、动态库和加载前置静态检查，并保留可复核命令输出。
4. 记录 `runtimeOS`、`compatibleSdkVersion`、build/target API 和 SDK 组件版本，防止“SDK component missing”类混配。

签名 HAP、实体 HarmonyOS 设备上的启动/FRB hello、应用私有目录、网络、权限和 HUKS smoke
均为后置发布条件；没有证书或设备时必须记录为 `BLOCKED`，不得把无签名包标为平台正式完成。

## 3.1 无签名平台能力适配

共享 `ubaa_platform` 通过 `cn.edu.buaa.ubaa/platform` MethodChannel 暴露三类稳定边界：
`permission.request` 返回固定权限状态，`credentials.capability/read/write/clear` 访问
版本化安全存储 namespace，`photo.capability/pick` 只传递受限的图片字节、展示名和 MIME。
`createDefaultPlatformCapabilities()` 在两个 Flutter 宿主启动时先探测凭据和照片能力；缺少
原生 handler 或返回值不符合合同会安全归约为不可用，不会回退到明文文件、内存凭据或原始路径。

当前已完成 Dart typed 适配器、输入校验和 MethodChannel Mock 合同测试；Android Keystore、
iOS/macOS Keychain、Linux Secret Service、Windows 安全存储和 HarmonyOS HUKS 的原生 handler
尚未接入，实体设备权限、生命周期和硬件安全存储验证继续记录为后置 `BLOCKED`。

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

本轮无签名 RC 的 OHOS 门禁命令为
`UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug`；该命令验证 API26 工具链、Dart/native
前置、arm64 动态库和无签名 HAP 包内容。它不能替代后置的签名 HAP、实体设备 FRB hello 或正式
发布构建，后置项必须单独记录为 `BLOCKED`。

## 5. 验收记录模板

| 日期 | 平台/设备 | SDK/架构 | 命令/产物 | 启动 | FRB | 登录模拟 | 安全存储 | 只读 smoke | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-01 | macOS 本机 | 3.41.9/arm64 | debug App | 通过 | hello 通过 | 未验证 | 未验证 | 未验证 | 仅 P0 FFI 链路 |
| 2026-09-01 | iOS simulator | 3.41.9/x86_64+arm64 | debug framework | 不适用 | 链接通过 | 未验证 | 未验证 | 未验证 | 无签名/真机证据 |
| 2026-09-01 | Android APK | 3.41.9/三 ABI | debug APK | 未运行 | 三 ABI 打包通过 | 未验证 | 未验证 | 未验证 | 无签名/实体机证据 |
| 2026-09-01 | Android AAB 本机 | 3.41.9/三 ABI | `flutter build appbundle --release` | 不适用 | Gradle bundle 成功；Flutter `apkanalyzer` 终检阻断 | 未验证 | 未验证 | 未验证 | SDK `cmdline-tools/latest` 为 Homebrew symlink，apkanalyzer 无法定位 `build-tools`；临时 SDK 复核含三 ABI debug symbols，但产物未签名/未上传 |
| 2026-09-01 | Windows GitHub runner | 3.41.9/x64 | `ubaa-windows-debug-33450597586` | 不适用 | 链接/打包通过 | 未验证 | 未验证 | 未验证 | `windows-2025` 原生构建 |
| 2026-09-01 | Linux GitHub runner | 3.41.9/x64 | `ubaa-linux-debug-33450597586` | 不适用 | 链接/打包通过 | 未验证 | 未验证 | 未验证 | Ubuntu 24.04 原生构建 |
| 2026-09-02 | HarmonyOS | 3.41.10-ohos-1.0.1/arm64 | `UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug` | 未运行 | 包内容通过 | 未验证 | 后置 BLOCKED | 未验证 | API26 工具链/Dart/native 前置通过；生成 `entry-default-unsigned.hap`，实体机/签名待完成 |

任何失败要保留安全的错误类别、工具版本和阶段，不保留凭据、个人数据或原始上游响应。

取消写入口的跨层边界：`BridgeBackend` 仅把图书馆状态码/状态名和场馆订单/审核状态作为公开详情字段投影；共享 UI
按冻结 DTO 的状态和时间截止规则隐藏明显不可取消的记录，Core 仍负责最终资格、会话和上游错误判定。状态缺失或格式未知
不由宿主猜测协议，场馆入口默认关闭；取消仍沿用一次性 `WriteIntent`，不增加后台重试或跨路线切换。

最新五平台复核：提交 `62ec048` 的 Flutter native run `33541980112` 已完成 Windows、macOS、Linux、
Android APK 与 iOS simulator debug 构建并上传产物；该 run 的 macOS、Windows、Linux、iOS simulator
和 Android APK job 均成功。这仍不是签名 Release 或实体设备证据。

提交 `0fa5ec0` 的本机无签名复核补充了平台回调边界：`CallbackPermissionGateway` 将原生权限 SDK
异常归约为稳定的 `unavailable`，`CallbackPhotoPicker` 将选择器异常归约为稳定能力错误，
`PermissionedPhotoPicker` 可显式使用相册或桌面文件权限。该适配器只负责 typed 边界，不伪造任何
Keychain/Keystore/Credential Manager/Secret Service/HUKS 能力；原生插件与实体设备验证继续保持后置
`BLOCKED`。当前提交 `b0c4a77` 的合同 CI `33583052957` 与五平台 native CI `33583052953` 均已终态成功；
五个平台 job（Windows、Linux、macOS、iOS simulator、Android APK）均通过并上传无签名 Debug 产物。
该证据不包含 OHOS 签名 HAP、实体设备或正式发布。

最终 HEAD `5bd9814` 重新运行 OHOS API26 无签名门禁，DevEco `26.0.0.821`、fork/API26 工具链与
`aarch64-unknown-linux-ohos` 前置均通过，HAP 内含 `libs/arm64-v8a/libubaa_bindings.so`。HAP 未签名、
未安装、未上传，生成输出已移出工作树；签名和设备验证仍为后置 `BLOCKED`。

## 5.1 无签名执行目标终态复核（2026-09-02）

- `81dd9d2` 的官方 macOS 宿主写入组合回归为十项写操作逐项断言提交后刷新关联只读领域；预期失败后
  聚焦场景 1/1 通过。十二项领域详情 golden、共享状态矩阵、typed 查询宿主 smoke 与未知结果/异常边界
  共同覆盖无签名 UI 流程。
- `0a0bb71` 进一步以手机/平板/桌面三种尺寸和明/暗主题建立主页与课表详情响应式 golden（12 个），并以动态字体、键盘焦点、十二项卡片语义和 1000 条详情分页回归覆盖
  无障碍与长列表边界；`ubaa_ui` 全量 49 项测试通过。
- Core-live 在当前营业窗口内 Direct/WebVPN 串行复跑均 exit code 0；提交 `4eaf1dd` 的五平台 Flutter native CI
  `33628444289` 与合同 CI `33628444204` 均终态成功。API26 无签名 OHOS HAP、arm64 bridge、敏感扫描、
  SBOM/依赖审计和回滚 runbook 均有本机或 CI 证据；FRB 零漂移沿用 `94133ae` 前同一生成输入的成功门禁，
  `81dd9d2` 仅改宿主测试且生成目录无差异；当前最终提交 `4eaf1dd` 再次运行 codegen 成功报告零漂移。
- 因此 P3（全部读取页面与双路线证据）、P4（十项写入确认/防重复/读后核对与 deterministic/Mock）、
  P5（平台能力抽象、权限/照片边界、生命周期/长列表/无障碍及无签名静态检查）和 P6（无签名 RC 发布准备）
  的无签名部分已完成。原生 Keychain/Keystore/Credential Manager/Secret Service/HUKS handler、实体设备
  安装/权限/生命周期、签名/公证/商店发布明确保持后置 `BLOCKED`。

## 6. P0 探索产物审查

| 产物 | 采用结论 | P0 证据 | 后续约束 |
|---|---|---|---|
| `apps/ubaa_flutter` 五平台官方宿主 | 保留生成宿主与薄入口作为构建起点 | 官方 `3.41.9` analyze/test 通过，五个平台目录齐全 | 默认 Demo backend 仅限测试/预览，Release 前必须由 FRB production backend 替换 |
| `apps/ubaa_ohos` | 保留共享入口并用锁定 fork 生成官方 runner | fork 提交/Dart 匹配，pub get、analyze、widget test 与 API26 工具链前置通过 | arm64 Cargokit/FRB 已接线；无签名 HAP 包内容检查通过，签名 HAP 与设备证据待完成 |
| `ubaa_domain`、`ubaa_app`、`ubaa_platform` | 保留为分层骨架 | 官方 SDK analyze/test 通过 | 无签名 RC 已具备完整状态/凭据安全边界与内存/回调适配；原生密钥链插件和设备验证列为 P5/P6 后置 |
| `ubaa_ui` | 保留主题、响应式导航、共享详情/查询/确认组件 | analyze、widget、十二项逐领域 golden 以及宿主全功能 smoke 通过 | 十二项功能已有 typed 详情入口和写入确认组件；真实设备链路与原生安全存储仍为后置条件 |
| Demo backend、交互验证码字段 | 不作为生产合同采用 | Core 当前未证明通用交互验证码；Demo 不访问 Core，生产入口默认 `UnavailableBackend` | Demo 仅限测试/预览；交互挑战继续由 Core 已证明的 typed 流程处理 |

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
| `flutter_rust_bridge` | `2.13.0` | 生成 Dart/Rust FFI codec 与 runtime | MIT | Windows、Linux、macOS、iOS simulator、Android 原生 runner 均已实际链接 | Dart API/HAR 已接线，无签名 HAP assemble 与 arm64 包内容检查通过 |
| Cargokit | FRB `2.13.0` 随附快照 | 从 Flutter native build 驱动固定 Rust crate | MIT/Apache-2.0 | 五平台均通过；Windows 使用 app `CMAKE_SOURCE_DIR` 计算绝对 manifest，避免 plugin junction 的父目录语义差异 | arm64 HAR/CMake 已接线，无签名 HAP assemble 已通过 |

两项依赖都不拥有协议、Cookie、路线或业务 DTO；它们只负责 FFI 生成与 native library
构建。版本升级必须同时更新 Rust crate、Dart package、codegen、Cargokit 快照和六平台
构建证据，禁止只升级其中一处。

## 9. P0 风险与 go/no-go

| 风险 | 当前证据 | 影响 | 处置与门禁 |
|---|---|---|---|
| GitHub Actions Node.js 20 运行时进入弃用迁移 | 成功 run `33450597586` 对 `checkout@v4`、`upload-artifact@v4` 给出强制 Node.js 24 警告 | 当前不影响产物，但后续 runner 可能停止兼容旧 action runtime | P1 前期按官方 action 版本说明升级并以完整 CI/native run 复验 |
| OHOS 调试签名尚未配置 | DevEco/CLI `26.0.0.821`、Hvigor `6.26.4`、ohpm `26.0.0.630`、SDK API26 前置通过；无签名 HAP assemble 与包内容检查通过 | 无法生成签名 HAP 或设备 FRB hello，但不阻断本轮无签名 RC | 取得项目所有者逐项授权后配置受控签名并重跑；不得提交签名材料或绕过签名 |
| OHOS 下载入口需要华为账号 | 未登录、未传输账号信息 | 工具链取得受外部账号与授权约束 | 取得项目所有者明确授权后才登录或使用受限下载 |
| 正式签名材料未提供 | 仅有无签名 debug/simulator 产物 | P0 空 HAP 与 P6 正式发布均不能完成 | Apple、Google、Microsoft、HarmonyOS 账号/证书单独授权并安全注入 |
| 领域详情与平台能力仍有证据缺口 | 十二项详情 golden、查询/确认、十项写入读后核对和无签名平台抽象已有确定性测试；真实设备/签名不可用 | 不能把 Mock 或无签名产物称为正式发布证据 | 无签名执行目标已闭合；设备、签名、安全存储验证保持后置 `BLOCKED` |

当前结论为 **NO-GO（正式签名发布）/ GO（无签名 RC 与跨平台确定性开发）**。官方 Flutter 五平台
native debug 矩阵已在 run `33541980112` 全部通过并上传独立产物，提交 `62ec048` 的合同
run `33541980109` 也全部通过；随后文档提交 `8fd836a` 的合同 run `33542479679` 成功。
OHOS 签名 HAP 与实体机 hello 是后置发布项而非本轮无签名目标阻断。该结论只允许继续不依赖
签名和真实写入的实现、确定性测试及只读验证，不允许将任何 debug/无签名产物称为正式版。

2026-09-02 终态复核补充：原生 run `33599670789`（提交 `1ca6ed8`）的 Windows、Linux、macOS、
iOS simulator、Android APK 全部成功，macOS 另通过宿主 integration smoke；合同 run `33600117413`
（提交 `993f5a2`）的三个 job 全部成功。两条 run 均为无签名确定性证据，不替代 OHOS 签名、实体设备
或正式发布门禁。

提交 `5dc6dcf` 的 UI 增量保持平台边界不变：博雅状态门禁只消费 bridge 白名单字段，场馆多时段只在
同站点/日期/空间内组合 typed 选择，避免呈现桥接合同必拒绝的跨空间组合，最终资格和冲突仍由 Core prepare 校验。该变化由 `ubaa_ui` 42 项测试和
`just flutter-check` 覆盖，不增加原生 handler、凭据、权限或签名要求；平台矩阵仍按无签名 Debug/静态证据
与实体设备后置 `BLOCKED` 分开记录。
