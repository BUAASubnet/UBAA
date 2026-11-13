# Flutter 六平台交付与发布流程

本手册供发布正式版本的维护者使用，说明候选验收、无签名构建、签名、构建与手动发布、分发和回退的步骤。签名材料的配置见[应用签名配置](app-signing.md)，账号与发布操作的授权遵守 [AGENTS 真实账号与验收范围](../../AGENTS.md#真实账号与验收范围)。旧流程见[归档](../archive/history/flutter-release-before-engineering-2026-10-07.md)。

## 何时使用

- 准备一个正式版本（GitHub Release、R2、App Store、AppGallery）。
- 验收一个发布候选，或重新构建失败的发布作业。
- 发布出现问题需要回退。

## 前提

### 分支与版本

- 发布主线为 `main`，日常开发在 `dev`，旧版保存在 `ubaa1`。
- 各平台统一使用根 [version.toml](../../version.toml) 中的展示版本和构建号，正式 Tag 为 `v<version>`。更新使用 `just version <版本号> <构建号>`，或修改该文件后运行 `just version`，不逐个编辑平台声明。版本来源与递增规则见[版本约定](../development/conventions.md#版本号与依赖)。
- 本机修改版本号不等于已经发布。只有实际分发时才创建 Tag 和 GitHub Release，并把更新日志中的待发布状态改为正式日期。

### 发布材料

正式分发前，按实际平台准备：

| 发布材料 | 要求与入口 |
|---|---|
| 源码候选 | 固定已验收提交，核对该提交的 CI 和平台作业结果，完整检查见[开发命令](../development/commands.md#检查选择与完成条件) |
| 安装包 | 选择本次实际分发的平台和架构，核对产物内的版本、构建号、应用标识和签名，操作见[签名手册](app-signing.md) |
| 旧版升级 | 使用旧版正式安装包验证覆盖安装、重新登录、数据保留与回退；Android 已发布 v1.8.2 的源码构建号为 35，商店渠道另核对已用构建号 |
| 许可证材料 | 在干净候选运行严格 `release-preflight` 并保存报告，另执行联网依赖审计 |
| 应用服务 | 正式 HTTPS 端点、分发渠道与隐私选择已验证；需要启用 CD 时配置 `main` 和受保护环境，见[部署手册](app-service.md) |
| 商店宣传图 | 从[已审阅的宣传图](../site/public/screenshots/)选择对应平台的 PNG；界面有变化时按下文重新生成 |
| 用户说明 | 使用[新版变化](../site/guide/ubaa2.md)与[更新日志](../site/changelog/index.md)，明确实际平台、最低系统要求、升级方式和已知限制 |

### 环境准备

- 冻结引用：首次缺失时显式执行 `just refs-bootstrap`，之后只运行 `just refs`。
- 质量工具：显式执行 `just quality-tools-bootstrap`。
- 依赖：首次用 `cargo fetch --locked` 预取所有目标，用 `just flutter-dependencies` 准备八个 Pub workspace 成员。
- preflight 不会隐式联网安装。官方 Flutter/OHOS、Rust、FRB 的固定版本及路径见[平台矩阵](../architecture/flutter-platforms.md)。

## 步骤

### 1. 固定候选并记录证据

先完成并提交源码候选，再在同一候选上验证。每轮记录：源码候选 SHA、工作树状态、工具链、命令、平台/设备、路线、退出码、产物摘要和未执行原因。

- 确定性、原生合成、真实插件通道、设备、Core-live、真实 App、签名与发布的结果分别记录。
- 任何源码、测试、生成文件、锁文件或构建配置变化都使对应检查失效。
- 后续新增纯证据文档时，分别记录文档提交与被验证的源码 SHA，不把旧日志说成新提交全部通过。
- 远端 workflow 以实际 `head_sha` 和 job 终态核对，不以本地 ahead 或历史运行推断当前 CI。

### 2. 运行验收入口

按[检查选择与完成条件](../development/commands.md#检查选择与完成条件)运行完整确定性清单、默认原生集成集合和平台专项，保留实际结果；普通 Flutter、FRB 和原生测试分别记录。原生集合中的插件网络读取和订阅只证明 handler 行为，不证明校园网可达。

### 3. 无签名构建与交付材料

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

在对应 runner 上执行实际目标，缺少工具的平台不声称完成。

`release-preflight`：

- 要求工作树干净、报告目录为空；只运行纯 refs/敏感检查，并生成 Dart/OHOS 许可证材料。
- 许可材料列出锁定来源、许可证证据及缺失项；包名/版本清单不等于许可批准。
- 默认严格模式遇到材料缺口时保留报告，以状态 3 阻断发布。仅报告模式仍列出缺口，但不能用于判定发布通过。日常 CI 不运行此入口。参数见[构建与发布命令](../development/commands.md#构建与发布命令)。
- Rust 依赖的许可与安全公告由 `just dependency-audit`（cargo-deny）检查，发布前单独运行。
- 源码以提交 SHA 标识，不另生成逐文件源码清单或 SBOM。

产物结构检查覆盖宿主入口、Flutter 资源和 Rust 动态库，macOS 还核验实际签名权限。无签名 Debug 包和 HAP 不能证明商店签名、安装升级、设备 HUKS 或正式发布。

共享的日志、报告和工件不包含凭据、Cookie、Token、原始响应、完整个人资料或本机敏感路径；本地原始调试材料与 UI 媒体保存在被忽略的 `.ubaa_local/` 任务子目录。

#### 生成商店宣传图

宣传图由 Flutter 的无头测试引擎绘制正式应用界面。入口在 [Flutter 宿主的 store 目录](../../apps/ubaa_flutter/store/)，使用固定日期和纯合成数据，不启动模拟器，不读取真实账号、校园响应或用户缓存。

在仓库根目录运行：

```bash
just flutter-dependencies
bash scripts/release/store-screenshots.sh
```

本机需要 ImageMagick 7 的 `magick` 命令，以及 Noto Sans CJK SC（思源黑体）的 `Regular`、`Medium`、`Bold`、`Black` 四个 OTF 字重。文件名形如 `NotoSansCJKsc-Regular.otf`。可在执行脚本时用 `UBAA_STORE_FONT_DIR` 指向字体目录；同一套字体有助于重现排版。

默认按设备生成三组图片：

| 成品目录 | 尺寸（像素） | 用途 |
|---|---:|---|
| `phone/` | 1179 × 2556 | 手机代表图、iPhone 中屏竖图 |
| `tablet/` | 2732 × 2048 | 平板代表图、13 英寸 iPad 横图 |
| `desktop/` | 2880 × 1800 | 桌面版宣传 |

运行 `bash scripts/release/store-screenshots.sh --all-sizes` 可在同一批次额外生成以下商店素材：

- `ready/phone/1320x2868/`：iPhone 大屏档。
- `ready/phone/1206x2622/`：iPhone 中屏档的另一种尺寸。
- `ready/appgallery/`：六张 1080 × 1920 的 AppGallery 手机竖图。
- `ready/appgallery/tablet/`：六张 1920 × 1280（3:2）的 AppGallery 平板横图。

单独生成 AppGallery 手机图时使用 `bash scripts/release/store-screenshots.sh --appgallery`，生成平板图时使用 `bash scripts/release/store-screenshots.sh --appgallery-tablet`。两组各展示首页、课表、日程、成绩、SPOC 作业和考试。[华为开发者中心素材规范](https://developer.huawei.com/consumer/cn/doc/app/agc-help-app-visual-asset-spec-0000002277607976/)按设备分别列出要求：HarmonyOS 手机和平板的应用介绍截图各可上传 3 至 10 张，PNG 单张不超过 5 MB。

脚本把原图写入 `.ubaa_local/store_screenshots/run.*/raw/`，将不带透明通道的 RGB PNG 写入同批次的 `ready/` 并打印实际路径。核对界面、文案、尺寸与清晰度后，把默认三组 PNG 复制到[网站宣传资源目录](../site/public/screenshots/)。AppGallery 手机图复制到 [AppGallery 素材目录](../site/public/press/appgallery/)，平板图复制到其 [`tablet/` 子目录](../site/public/press/appgallery/tablet/)。Git 追踪这些成品、源数据和渲染代码；额外的 iPhone 尺寸留在本地。网站代表图换名或增删时同步调整[应用截图页](../site/features/screenshots.md)，执行 `npm run docs:build`。

上传前按 [App Store Connect 截图规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)与华为开发者中心的素材规范复核目标规格。宣传图生成与网站构建不执行商店上传。

### 4. 设备与签名

各平台材料、旧版升级身份、本机配置与 CI secret 映射统一见[应用签名配置](app-signing.md)。

- Android/iOS/OHOS 实体机上的权限、前后台、网络订阅及安全材料写读删，需要独立的设备证据。
- 常规发布验收使用确定性测试、原生集成和发布产物检查。学校协议变更需要的真实验证按 [AGENTS 真实账号与验收范围](../../AGENTS.md#真实账号与验收范围)独立执行，发布工作流不接收学校账号。
- 正式签名、公证和上传只在相应授权和环境满足后进行。签名材料由平台安全存储和隔离 runner 管理，不进入源码、argv、普通日志或 artifact。
- 发布前核对候选 SHA、校验摘要、许可材料、安装/升级/卸载和平台权限。

### 5. 构建与手动发布

[Release 工作流](../../.github/workflows/release.yml) 在 main 手动运行。Tag 必须与 version.toml 的展示版本一致，例如 v2.0.0。可以省略 Tag，由工作流生成当前版本的名称。各平台构建成功后，工作流上传附件并保留 GitHub Release 草稿，由维护者手动发布。发布草稿不会再次触发构建。

工作流固定主线候选，关联已经成功的完整验收，再并行构建各平台产物。全部构建、签名和商店上传均使用 GitHub 托管 runner。HarmonyOS 环境安装说明见[开发环境](../development/setup.md#harmonyos-的-github-托管构建)。

完整 CI 的 main-required 成功后保存 merge-acceptance 记录，包含实际检出提交、Git tree、PR、运行编号和运行次数。Release 核对 GitHub 运行成功状态、记录来源和完整源码树。PR 临时合并提交与 main 的 SHA 可以不同，但必须属于实际合入该候选的 PR，且完整源码树一致；工作流、工具清单、锁文件和测试也包含在树中。没有匹配记录或记录已过期时重新执行完整验收，失败、取消和不明来源不会被复用。正式构建、签名、公证、上传与产物检查每次执行。

iOS 合并验收、正式归档和上传使用 GitHub 的 `xcode-27` 镜像，并显式选择 `versions.env` 中的 Xcode 27.2，使用 iOS 27.2 SDK，满足 [Apple 自 2026 年 4 月 28 日起的上传要求](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)。`xcode-27` 当前为 GitHub 公开预览镜像，Xcode 27.2 为正式版本；工作流按固定路径选择工具链。

| 平台 | 正式产物与渠道 |
|---|---|
| Android | arm64-v8a、armeabi-v7a、x86_64 各一个带签名 APK，每个 APK 只包含目标 ABI，构建号保持一致 |
| Windows | x64 EXE 安装器 |
| Linux | x64、arm64 各一个含 GUI 和命令入口的 tar.gz |
| macOS | arm64、x86_64 各一个 Developer ID 签名并公证的 DMG |
| iOS / iPadOS | App Store IPA，上传后等待 Apple 处理完成 |
| HarmonyOS | arm64 发布 APP 包，上传后等待 AppGallery 软件包解析完成 |

公开产物与许可证材料上传到 GitHub Release 草稿和 `https://r2.ubaa.top/releases/<tag>/<构建号>/`。R2 上传后即可通过下载地址访问，不等待 GitHub 草稿发布。R2 产物带一年的 immutable 缓存，同一路径只写一次：相同内容重跑时跳过上传，内容不同则在覆盖前拒绝。`release.json` 列出版本、构建号、源码提交、文件大小和下载地址。HarmonyOS APP 是商店提交包，安装通过 AppGallery 进行。iOS IPA 保存在 Actions 产物中并上传商店。

维护者按以下顺序发布 GitHub Release：

1. 在 Actions 中选择 **Release 构建与草稿**，选择 main 并点击 **Run workflow**。
2. 等待整次工作流成功，包括各平台构建、R2 分发和商店处理。仅看到草稿时，商店上传可能仍在运行。
3. 在 Releases 中打开对应版本的草稿，核对附件、版本说明和候选提交，再点击 **Publish release**。

`release-production` Environment 仅允许 main。平台签名步骤读取对应平台 Secrets，分发步骤读取 R2 凭据，商店步骤读取对应服务账号。商店工作流只上传和检查处理状态，由维护者自行选择构建、补齐商店资料并提交审核。商店版本实际可下载之后，再更新应用服务的渠道配置。

构建或上传失败时保留同次运行的成功产物，未修改源码时可以重新运行失败作业。未发布的草稿可以接收新候选：分发前把草稿目标改到当前候选提交，再覆盖附件。已经发布的 Release 会在分发写入前被拒绝，后续发布使用新版本。修改源码或构建配置后，按新候选重新验收和构建。已经分发产物或上传商店的构建号不复用，后续候选递增统一构建号。已发布 Tag 不移动到其他源码提交。

## 验证

发布后核对：`release.json` 中的版本、构建号、源码提交和文件摘要与候选一致；商店上传已处理完成；渠道配置只在商店版本实际可下载后更新。

### 候选输入与产物关联

- 原生工作流的 `build-record.json` 把候选 SHA、工作树是否干净和 GitHub 作业关联起来，源码内容由提交 SHA 唯一确定。
- `artifact-files.json` 使用相对路径及逐文件摘要，避免同一产物因本机绝对目录不同而得到不同摘要。
- 外部 SDK、系统库、下载依赖和签名环境仍需按平台登记；这些记录不是可复现构建证明。

## OHOS 原生依赖材料

OHPM 的本地依赖分两类处理。受 Git 跟踪、位于本仓库内的纯 `.d.ts` 包记录版本与文件摘要，并沿用项目许可证；这类记录不包含实际动态库。三个 OHOS 插件依赖的 `@ohos/flutter_ohos`（Flutter embedding HAR）来自锁定的 OHOS Flutter SDK：报告器读取 `.env` 中的 `UBAA_OHOS_FLUTTER_HOME`，确认其提交等于 `versions.env` 的 `OHOS_FLUTTER_COMMIT` 后，收集 SDK 根目录与 `bin/cache/artifacts/engine/ohos-arm64/` 中的许可证正文，并记录 `OHOS_FLUTTER_REMOTE`、提交和版本。不需要手写材料清单。

SDK 未配置或提交不符时，该依赖保留为缺口，严格模式以状态 3 阻止发布。来源字段来自锁定 SDK，不能独立证明二进制由该源码构建；实际 HAP、动态库架构、签名和构建关联仍按本手册的产物验收执行。

## 故障处理

### 回退

发布前保存上一份已验证的产物、源码/生成/锁文件版本、磁盘 Session/config/cache 格式版本及兼容说明。出现问题时：

1. 停止分发。
2. 判定旧版本能否读取新格式，再回退产物。不删除用户 Session 或密钥来掩盖不兼容；数据不可逆或旧版不支持的情形，标明不能安全自动回退。
3. 回退后重新验证原平台的启动、离线内容、安全材料和只读恢复，不重放写入。

构建或上传失败的处理见“构建与手动发布”末段。OHOS 正式首发使用统一构建号 `2003`；已经安装构建号 `1000000` 或 `1000001` 开发包的设备不能直接覆盖安装，需要单独保留和迁移测试数据。
