# Flutter 六平台交付与发布流程

本文规定 UBAA v2.0 的候选验收、签名与分发流程。旧流程见[归档](../archive/history/flutter-release-before-engineering-2026-10-07.md)，当前结果见[实现与验证状态](../project/status.md)。账号与发布操作遵守 [AGENTS](../../AGENTS.md#真实账号与验收范围)。

## v2.0.0 发布准备

发布主线为 `main`，日常开发进入 `dev`，旧版保存在 `ubaa1`。各平台统一使用展示版本 `2.0.0` 和构建号 `2003`，正式 Tag 使用 `v2.0.0`。各平台版本来源与递增规则见[版本约定](../development/conventions.md#版本号与依赖)。

版本唯一来源为根 [version.toml](../../version.toml)。后续更新使用 `just version <版本号> <构建号>`，或修改该文件后运行 `just version`，不逐个编辑平台声明。

正式分发前，按实际平台完成以下准备：

| 发布材料 | 要求与入口 |
|---|---|
| 源码候选 | 固定已验收提交，核对该提交的 CI 和平台作业结果，完整检查见[开发命令](../development/commands.md#检查选择与完成条件) |
| 安装包 | 选择本次实际分发的平台和架构，核对产物内的版本、构建号、应用标识和签名，操作见[签名手册](app-signing.md) |
| 旧版升级 | 使用旧版正式安装包验证覆盖安装、重新登录、数据保留与回退；Android 已发布 v1.8.2 的源码构建号为 35，商店渠道另核对已用构建号 |
| 许可证材料 | 在干净候选运行严格 `release-preflight` 并保存报告，另执行联网依赖审计 |
| 应用服务 | 正式 HTTPS 端点、分发渠道与隐私选择已验证；需要启用 CD 时配置 `main` 和受保护环境，见[部署手册](app-service.md) |
| 用户说明 | 使用[新版变化](../site/guide/ubaa2.md)与[更新日志](../site/changelog/index.md)，明确实际平台、最低系统要求、升级方式和已知限制 |

原生 Actions 提供六平台 Debug 构建与验收，Release 工作流构建签名后的正式包并分发。只有实际分发时才创建 Tag 和 GitHub Release，并把更新日志中的待发布状态改为正式日期。不要把本机版本号变更当作已经发布。

## 自动发布

[Release 工作流](../../.github/workflows/release.yml) 接收两种触发：在 main 手动运行，或发布与 main 提交关联的 GitHub Release。Tag 必须与 version.toml 的展示版本一致，例如 v2.0.0。手动运行可以省略 Tag，由工作流生成当前版本的名称。

工作流固定主线候选，关联已经成功的完整验收，再并行构建各平台产物。全部构建、签名和商店上传均使用 GitHub 托管 runner。HarmonyOS 环境安装说明见[开发环境](../development/setup.md#harmonyos-的-github-托管构建)。

完整 CI 的 main-required 成功后保存 merge-acceptance 记录，包含实际检出提交、Git tree、PR、运行编号和运行次数。Release 核对 GitHub 运行成功状态、记录来源和完整源码树。PR 临时合并提交与 main 的 SHA 可以不同，但必须属于实际合入该候选的 PR，且完整源码树一致；工作流、工具清单、锁文件和测试也包含在树中。没有匹配记录或记录已过期时重新执行完整验收，失败、取消和不明来源不会被复用。正式构建、签名、公证、上传与产物检查每次执行。

iOS 合并验收、正式归档和上传显式选择 `versions.env` 中的 Xcode 26.3，使用 iOS 26 SDK，满足 [Apple 自 2026 年 4 月 28 日起的上传要求](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)。不依赖托管镜像的默认 Xcode。

| 平台 | 正式产物与渠道 |
|---|---|
| Android | arm64-v8a、armeabi-v7a、x86_64 各一个带签名 APK，每个 APK 只包含目标 ABI，构建号保持一致 |
| Windows | x64 EXE 安装器 |
| Linux | x64、arm64 各一个含 GUI 和命令入口的 tar.gz |
| macOS | arm64、x86_64 各一个 Developer ID 签名并公证的 DMG |
| iOS / iPadOS | App Store IPA，上传后等待 Apple 处理完成 |
| HarmonyOS | arm64 发布 APP 包，上传后等待 AppGallery 软件包解析完成 |

公开产物与许可证材料分发到 GitHub Release 和 `https://r2.ubaa.top/releases/<tag>/`。`release.json` 列出版本、构建号、源码提交、文件大小和下载地址。HarmonyOS APP 是商店提交包，安装通过 AppGallery 进行。iOS IPA 保存在 Actions 产物中并上传商店。

`release-production` Environment 仅允许 main 和 v 开头的 Tag。平台签名步骤读取对应平台 Secrets，分发步骤读取 R2 凭据，商店步骤读取对应服务账号。商店工作流只上传和检查处理状态，由维护者自行选择构建、补齐商店资料并提交审核。商店版本实际可下载之后，再更新应用服务的渠道配置。

构建或上传失败时保留同次运行的成功产物，未修改源码时可以重新运行失败作业。修改源码或构建配置后，按新候选重新验收和构建。已经分发产物或上传商店的构建号不复用，后续候选递增统一构建号。已发布 Tag 不移动到其他源码提交。

## 候选与证据

为每轮记录源码候选 SHA、工作树状态、工具链、命令、平台/设备、路线、退出码、产物摘要和未执行原因。确定性、原生合成、真实插件通道、设备、Core-live、真实 App、签名/发布独立记账。

先完成并提交源码候选，再在同一候选验证。后续新增纯证据文档必须分别记录文档提交与被验证源码 SHA，不得将旧日志改称新 HEAD 全部通过；任何源码、测试、生成、锁文件或构建配置变化都使对应门禁失效。远端 workflow 以实际 head_sha、job 终态核对，不能以本地 ahead 或历史 run 推断当前 CI。

## 环境准备

首次缺少冻结引用时显式执行 `just refs-bootstrap`；已有引用只运行 `just refs`。质量工具依赖由显式 `just quality-tools-bootstrap` 建立；首次用 `cargo fetch --locked` 预取所有目标、`just flutter-dependencies` 准备八个 Pub workspace 成员。preflight 不隐式联网安装。官方 Flutter/OHOS、Rust、FRB 固定版本及路径见[平台矩阵](../architecture/flutter-platforms.md)。

## 验收入口

完整确定性清单、原生/发布候选的默认集成集合及平台专项只在[开发命令](../development/commands.md#检查选择与完成条件)维护。按该清单运行并保留实际结果；普通 Flutter、FRB 和原生测试分别记账。原生集合中的插件网络读取/订阅只证明 handler 行为，不证明校园可达。

## 无签名构建与交付材料

在对应 runner 上执行实际目标，不在缺工具平台声称完成：

```bash
just flutter-build platform=macos mode=debug
just flutter-build platform=linux mode=debug
just flutter-build platform=windows mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug
UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
just flutter-artifact-check platform=android-apk artifact=/绝对路径/app-debug.apk
just release-preflight /项目绝对路径/UBAA2/.ubaa_local/release/license_report
```

`release-preflight` 要求工作树干净、报告目录为空，只运行纯 refs/敏感检查并生成 Dart/OHOS 许可证材料。Rust 依赖的许可与安全公告由 `just dependency-audit`（cargo-deny）检查，发布前单独运行。源码以提交 SHA 标识，不再另生成逐文件源码清单或 SBOM。Dart/OHOS 许可材料应列出锁定来源、许可证证据及缺失项；包名/版本清单不称作许可批准。默认严格模式遇到材料缺口会保留报告并以状态 3 阻断发布。仅报告模式仍列出缺口，但不能用于判定发布通过，日常 CI 不运行本入口；参数与实际边界见[开发命令](../development/commands.md#构建与发布命令)。

产物结构检查覆盖宿主入口、Flutter资源和Rust动态库；macOS还核验实际签名权限。无签名Debug包和HAP不能证明商店签名、安装升级、设备HUKS或正式发布。共享日志、报告和工件不能包含凭据、Cookie、token、原始响应、完整个人资料或本机敏感路径；本地原始调试材料与 UI 媒体统一保存在被忽略的 `.ubaa_local/` 任务子目录。

## 设备、真实路线与签名

各平台材料、旧版升级身份、本机配置与 CI secret 映射统一见[应用签名配置](app-signing.md)。

Android/iOS/OHOS实体机权限、前后台、网络订阅及安全材料写读删需要独立设备证据。Core-live/真实App只在当前会话用户已授权的路线和只读范围内执行，空结果、静态回退与Mock不能当作真实按钮验收。真实写入必须有具体操作、目标、路线及时间授权；unknown立即停止，不重试。

正式签名、公证和上传只能在相应授权和环境满足后进行。签名材料由平台安全存储和隔离runner管理，不进入源码、argv、普通日志或artifact；发布前核对候选SHA、校验摘要、许可材料、安装/升级/卸载和平台权限。

## 回退

OHOS 正式首发使用统一构建号 `2003`。已经安装构建号 `1000000` 或 `1000001` 开发包的设备不能直接覆盖安装该版本，需要单独保留和迁移测试数据。

保存上一份已验证产物、源码/生成/锁文件版本、独立磁盘Session/config/cache schema及兼容说明。失败时停止分发，先判定旧版本能否读取新格式，再回退产物；不能删除用户Session或密钥来掩盖不兼容。数据不可逆或旧版不支持的情形必须标明不能安全自动回退。回退后重新验证原平台启动、离线内容、安全材料和只读恢复，不重放写入。


### 候选输入与产物关联

原生工作流的 build-record.json 将候选 SHA、工作树是否干净和 GitHub 作业关联，源码内容由提交 SHA 唯一确定；原生工作流同时生成 artifact-files.json，使用相对路径及逐文件摘要，避免同一产物因本机绝对目录不同而得到不同内容摘要。外部 SDK、系统库、下载依赖和签名环境仍需按平台登记，这不是可复现构建证明。

## OHOS 原生依赖材料

OHPM 的本地依赖分两类处理。受 Git 跟踪、位于本仓库内的纯 `.d.ts` 包记录版本与文件摘要，并沿用项目许可证；这类记录不包含实际动态库。三个 OHOS 插件依赖的 `@ohos/flutter_ohos`（Flutter embedding HAR）来自锁定的 OHOS Flutter SDK：报告器读取 `.env` 中的 `UBAA_OHOS_FLUTTER_HOME`，确认其提交等于 `versions.env` 的 `OHOS_FLUTTER_COMMIT` 后，收集 SDK 根目录与 `bin/cache/artifacts/engine/ohos-arm64/` 中的许可证正文，并记录 `OHOS_FLUTTER_REMOTE`、提交和版本。不需要手写材料清单。

SDK 未配置或提交不符时，该依赖保留为缺口，严格模式以状态 3 阻止发布。来源字段来自锁定 SDK，不能独立证明二进制由该源码构建；实际 HAP、动态库架构、签名和构建关联仍按本手册的产物验收执行。
