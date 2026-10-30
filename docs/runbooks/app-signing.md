# 应用签名配置

UBAA 2 作为旧版更新发布。Android、iOS、macOS、Linux 和 OHOS 的产品应用标识统一为 `cn.edu.ubaa`。Android 更新必须继续使用原来的应用签名密钥，iOS 更新必须使用原 App Store Connect 应用记录和所属 Team。二次开发者使用自己的应用标识、开发者账号和密钥。

本手册统一材料保存位置、平台配置步骤和 CI 字段映射。平台构建仍使用现有入口，签名和商店上传使用平台原生工具。仓库目前没有自动加载 `.env.signing`、统一签名生成器或六平台发布流水线。完整发布验收见[发布手册](flutter-release.md)，命令与门禁见[开发命令](../development/commands.md)。

## 先确认应用身份

| 平台 | 官方应用配置 | 二次开发修改位置 |
|---|---|---|
| Android | `cn.edu.ubaa`，延续旧版签名 | [app/build.gradle.kts](../../apps/ubaa_flutter/android/app/build.gradle.kts) 的 `applicationId` |
| iOS / iPadOS | `cn.edu.ubaa`，延续旧应用和 Team | [project.pbxproj](../../apps/ubaa_flutter/ios/Runner.xcodeproj/project.pbxproj) 的 Runner 三个构建配置及测试 target 的 Bundle ID |
| macOS | `cn.edu.ubaa` | [AppInfo.xcconfig](../../apps/ubaa_flutter/macos/Runner/Configs/AppInfo.xcconfig) 的 `PRODUCT_BUNDLE_IDENTIFIER`，同时检查测试 target |
| HarmonyOS / OHOS | `cn.edu.ubaa` | [app.json5](../../apps/ubaa_ohos/ohos/AppScope/app.json5) 的 `bundleName` |
| Linux | `cn.edu.ubaa` | [CMakeLists.txt](../../apps/ubaa_flutter/linux/CMakeLists.txt) 的 `APPLICATION_ID` |
| Windows | 非商店 MSIX Identity Name 采用 `cn.edu.ubaa`，商店包使用 Partner Center 指定的身份 | 建立安装器时配置发布者、包身份或 MSI UpgradeCode，后续更新保持稳定 |

Android 的 `namespace` 是 Kotlin 类和资源的命名空间，允许与 `applicationId` 不同，不需要为了保持旧包名移动 Kotlin 文件。二次开发者还应修改应用显示名称、图标、网站和商店记录。

macOS、Windows、Linux 旧版使用不同的桌面打包工具。正式覆盖升级前，要从实际旧安装包提取 Bundle ID、安装器身份和数据目录，再确定迁移方式；不要把统一后的工程值当作已经核验的旧版身份。OHOS 本轮没有取得旧版发布包证据，后续发布 Profile 必须匹配统一后的包名。macOS 从先前开发标识切换后，沙盒容器和 Keychain 访问可能变化，需要保留原数据并验证迁移，不能通过删除旧容器解决。

## 材料保存约定

建议每个发布者在仓库外建立独立目录。例如 macOS/Linux：

```bash
install -d -m 700 "$HOME/.config/ubaa/signing"
install -d -m 700 "$HOME/.config/ubaa/signing/android"
install -d -m 700 "$HOME/.config/ubaa/signing/apple"
install -d -m 700 "$HOME/.config/ubaa/signing/ohos"
install -d -m 700 "$HOME/.config/ubaa/signing/windows"
```

Windows 可使用当前用户目录下的独立私有目录，并限制 NTFS 访问权限。示例路径只是目录约定，平台配置中填实际绝对路径。不要把密码、私钥或 Profile 写入仓库示例、提交、命令行参数、截图或普通构建日志。`.env.toolchain` 只配置工具和非秘密路径，`.env.local` 继续只用于已有真实账号流程。

| 平台 | 准备的材料 | 保存位置 |
|---|---|---|
| Android | 原发布 keystore、store password、key alias、key password | 私有目录；密码配置见下一节 |
| iOS | Apple Distribution 证书和对应私钥、Team、匹配 Bundle ID 的分发 Profile | 本机 Keychain 和 Xcode；CI 使用加密导出的 `.p12` 与密码 |
| macOS 官网分发 | Developer ID Application 证书及私钥、公证认证方式 | Keychain；公证凭据通过 Keychain profile 或 CI secret 管理 |
| OHOS | `.p12`、别名和密码、发布 `.cer`、发布 `.p7b` | 私有目录，由 DevEco 导入 |
| Windows 可信签名 | 受信代码签名证书及其私钥访问方式，或签名服务 | 系统证书存储、硬件设备或服务，不要求必须存在可导出的 PFX |
| Linux 可选签名 | GPG 私钥、公钥和备份 | GPG 密钥环 |

保留加密备份并记录证书用途、公开指纹、到期时间和管理人。Android 原密钥丢失会影响自行分发包的后续更新，不能随意重新生成替代；Google Play 的上传密钥和应用签名密钥要分别管理。

## Android：本地配置与 CI 共用同一组字段

现有 Gradle 入口支持以下四个字段，可通过 Gradle property 或环境变量提供。Gradle property 优先，四项必须完整。

```properties
# 放入当前用户的 ~/.gradle/gradle.properties，不放进项目目录。
# 以下值均为示例，替换成自己的材料；路径建议使用正斜杠。
UBAA_RELEASE_STORE_FILE=/私有目录/signing/android/release.jks
UBAA_RELEASE_STORE_PASSWORD=替换为密钥库密码
UBAA_RELEASE_KEY_ALIAS=替换为密钥别名
UBAA_RELEASE_KEY_PASSWORD=替换为密钥密码
```

macOS/Linux 将该用户配置权限设为 `0600`。该文件会被当前用户的其他 Gradle 项目读取；共用构建机应使用独立账号或临时 CI 环境变量。Java properties 对反斜杠有转义规则，路径与含反斜杠的密码必须正确转义；不要给值额外加引号。

构建入口：

```bash
just flutter-build platform=android-apk mode=release
just flutter-build platform=android-appbundle mode=release
```

没有提供任何字段时，当前入口生成无签名 release；只提供部分字段时失败。构建成功后必须用 Android SDK 的 `apksigner verify --verbose --print-certs` 验证 APK，并与旧正式 APK 的证书比较。AAB 是商店输入，安装验收应使用最终分发 APK。

版本号从宿主 pubspec 维护，正式 `versionCode` 必须高于已发布版本。当前 `0.1.0+1` 不能直接当作旧版更新发布。二次开发首次发布可生成自己的 keystore，之后持续使用相同应用身份。

## iOS：配置 Team、Profile 与导出方式

1. 将有效分发证书和对应私钥导入登录 Keychain；Xcode 的 Manage Certificates 应能看到对应身份。只有 `.cer` 文件而没有私钥时无法本地签名。
2. 打开 `apps/ubaa_flutter/ios/Runner.xcworkspace`。在 Runner → Signing & Capabilities 中选择原应用所属 Team，确认 Bundle ID 为 `cn.edu.ubaa`。测试 target 使用自己的后缀。
3. 可让 Xcode 自动管理匹配的 Profile。手动管理时，在开发者后台选择准确的 App ID、分发证书及分发类型，再下载 Profile。App Store/TestFlight 和 Ad Hoc 使用不同类型的 Profile；Ad Hoc 还需登记设备。
4. 在 Xcode 中 Archive，随后通过 Organizer 的 Distribute App 导出或上传。团队与签名选择产生的本机修改要在提交前审阅，不提交个人身份、证书材料或凭据。

现有 `just flutter-build platform=ios-device mode=release` 明确带有 `--no-codesign`，只用于无签名构建。命令行正式导出可在宿主目录使用 `just flutter build ipa --release --export-options-plist=/私有目录/signing/apple/ExportOptions.plist`，前提是 Xcode 的 Team/签名已正确配置。ExportOptions 由当前 Xcode Organizer 导出流程生成并复用，避免手写过时的导出字段。

CI 需将 `.p12` 导入临时 Keychain、安装匹配 Profile，并在结束时清理。App Store Connect API 密钥用于上传认证，不能替代签名证书和私钥。官方更新继续使用原商店记录；二次开发者注册自己的 App ID、Team 和商店记录。

## macOS：开发签名与发布签名分别配置

当前 [AppInfo.xcconfig](../../apps/ubaa_flutter/macos/Runner/Configs/AppInfo.xcconfig) 支持被 Git 忽略的 `LocalSigning.xcconfig`。本机开发继续使用既有 Apple Development 身份。官网分发时，在独立发布 checkout 中创建同路径的本机配置：

```xcconfig
// apps/ubaa_flutter/macos/Runner/Configs/LocalSigning.xcconfig
UBAA_CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM = 替换为发布Team
CODE_SIGN_IDENTITY = 替换为DeveloperIDApplication证书指纹
ENABLE_HARDENED_RUNTIME = YES
```

以上配置会影响该 checkout 的构建，因此不要覆盖日常开发 checkout 中已经使用的个人配置。构建 Release 后检查主程序、Framework 和 Rust 动态库的签名及权限，再通过 Xcode Organizer 或 `notarytool` 提交公证并装订票据。正式包不得包含 Debug 的调试权限。签名与公证失败时停止分发。

官网 `.app`/`.dmg` 使用 Developer ID Application；签名 `.pkg` 还需 Developer ID Installer。Mac App Store 使用商店分发证书、对应 Profile 和商店能力配置，不能套用 Developer ID 流程。已有 App Store Connect API 密钥能否用于公证，要核对所属 Team、权限和当前工具支持，不能只凭 secret 名称判断。

## OHOS：使用发布证书和发布 Profile

在 DevEco 中生成或导入 `.p12` 密钥及 CSR，向 AppGallery Connect 申请发布证书 `.cer`，为准确的 `bundleName` 申请发布 Profile `.p7b`。调试 Profile 不能代替发布 Profile。

建议在专用发布 checkout 中打开 OHOS 工程，在 Signing Configs 中配置 Store File、Store Password、Key Alias、Key Password、Certpath File 和 Profile File，使用 SDK 要求的签名算法。当前 [build-profile.json5](../../apps/ubaa_ohos/ohos/build-profile.json5) 的 `signingConfigs` 为空，产品引用 `default`，签名配置名称应匹配。

DevEco 可能把签名字段写入受 Git 跟踪的 build-profile.json5。即使密码显示为加密字符串，该配置也不得提交。只在专用发布 checkout 中保存本机修改，完成后确认工作区差异和材料都没有进入 Git。不要使用 `assume-unchanged` 隐藏秘密改动。

配置后执行 `just ohos-check mode=release`。`UBAA_OHOS_NO_CODESIGN=1` 只用于 Debug 内容检查。HAP 的设备安装、HUKS 与版本更新需要实体设备验收；上架还应通过 DevEco 生成渠道要求的发布 APP 包，不能直接把无签名 HAP 当成商店发布包。

## Windows 与 Linux

Windows 普通 EXE/ZIP 可以无签名分发。需要可信发布者签名时，使用证书存储或签名服务对最终 EXE、DLL 和安装器按渠道规则签名，并使用可信时间戳。MSIX 需要有效签名，Manifest 的 Publisher 必须与证书匹配。Microsoft Store 包的 Name 和 Publisher 还必须与 Partner Center 的 Product Identity 一致，不能强行覆盖为通用标识。通过 Microsoft Store 分发 MSIX 时可由商店签名。向商店提交 EXE/MSI 的规则不同，需要开发者自行完成签名。代码签名不保证立即消除 SmartScreen 的信誉提示。

Linux 普通压缩包和 AppImage 不强制代码签名。可以用 GPG 提供可验证的签名，并公开发布公钥和校验摘要。发行版仓库按对应包管理器规则签名。当前仓库只有 Flutter 桌面构建入口，尚未提供统一的 Windows 安装器、Linux 仓库或签名自动化。

## GitHub Actions 的材料映射

当前仓库已有下列旧版 secrets 条目。只能确认条目存在，仍需验证内容、密码、证书状态和 Profile 是否匹配。Fork 默认不继承这些 secrets，维护者应在自己的仓库重新配置。

| 既有 secret | 用途与 UBAA2 接线 |
|---|---|
| `SIGNING_KEY` | Base64 编码的 Android keystore，解码到 runner 临时私有目录，将文件路径传给 `UBAA_RELEASE_STORE_FILE` |
| `SIGNING_STORE_PASSWORD` | 映射为 `UBAA_RELEASE_STORE_PASSWORD` |
| `SIGNING_KEY_ALIAS` | 映射为 `UBAA_RELEASE_KEY_ALIAS` |
| `SIGNING_KEY_PASSWORD` | 映射为 `UBAA_RELEASE_KEY_PASSWORD` |
| `IOS_CERTIFICATE_P12_BASE64`、`IOS_CERTIFICATE_PASSWORD` | 导入 Apple 分发证书及私钥 |
| `IOS_PROVISIONING_PROFILE_BASE64` | 安装对应应用和渠道的 Profile |
| `APPSTORE_KEY_ID`、`APPSTORE_ISSUER_ID`、`APPSTORE_PRIVATE_KEY` | App Store Connect 上传认证 |

以上是现有字段到发布流程的映射，UBAA2 当前 CI 只构建 Debug，没有自动使用这些 secrets。后续发布作业应只在可信分支、明确发布触发条件下读取材料，不能向 Fork PR 暴露密钥；临时文件与 Keychain 在成功、失败时都清理，不上传到 artifact。Base64 是编码，不提供加密保护。

## 配置完成后的检查

签名前按[开发命令](../development/commands.md#检查选择与完成条件)完成对应候选的检查，签名后按[发布流程](flutter-release.md)完成发布验收。重点核对最终包的应用标识、签名证书、版本号、权限，以及旧正式版本覆盖安装后的启动、数据保留和回退行为。

同包名和正确签名仅满足升级身份条件。旧版 Kotlin 与新版 Flutter/Rust 的配置、数据库和凭据格式可能不同，仍需检查数据兼容；首次启动要求重新登录或无法回退的情况必须明确告知用户。不要通过先卸载旧版来替代覆盖升级验收。

官方参考：[Android 签名](https://developer.android.com/studio/publish/app-signing)、[Apple Profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)、[Developer ID](https://developer.apple.com/developer-id/)、[MSIX 签名](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)、[AppImage 签名](https://docs.appimage.org/packaging-guide/optional/signatures.html)。
