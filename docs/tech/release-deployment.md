# 发布与部署

仓库有三类发布：应用 release 构建、Web Wasm 发布、docs 静态站发布。docs 站点由 `dev` 分支 push 触发，构建后通过 SSH rsync 同步到服务器静态目录。

## 应用 Release

`.github/workflows/release.yml` 在 GitHub Release published 或手动触发时构建。发布 Release 时，各平台产物上传到对应的 GitHub Release：

- Android APK。
- Desktop Linux deb。
- Server fat jar。
- Web Wasm zip。
- Web JS zip。
- iOS IPA、调试符号和 Kotlin framework；IPA 同时上传到 App Store Connect。
- Windows exe。

### iOS App Store Connect 发布

`build-ios` 使用 `macos-15` 上的 Xcode 26.3 和 JDK 21，从共享的 `iosApp` scheme 构建完整 App。Xcode 构建阶段调用 `:composeApp:embedAndSignAppleFrameworkForXcode`，把 Kotlin 代码和 Compose 资源集成到 App；`iosApp/Configuration/Config.xcconfig` 配置 framework 搜索路径及链接参数。

流程依次校验版本和签名材料、创建临时 Keychain、执行 `xcodebuild archive`、以 `app-store-connect` 方式导出签名 IPA，最后使用 App Store Connect API Key 上传。签名采用现有 Apple Distribution 证书与 App Store Connect 描述文件；API Key 用于上传认证，不代替签名证书。上传不会自动提交 App Store 审核，Apple 处理完成后可在 TestFlight 中查看构建。

#### GitHub Secrets

在仓库 **Settings → Secrets and variables → Actions → Repository secrets** 配置以下内容：

| Secret | 内容 |
| --- | --- |
| `IOS_CERTIFICATE_P12_BASE64` | Apple Distribution 证书及对应私钥导出的 `.p12` 文件，进行 Base64 编码。 |
| `IOS_CERTIFICATE_PASSWORD` | 导出上述 `.p12` 时设置的密码。 |
| `IOS_PROVISIONING_PROFILE_BASE64` | 对应 App ID 的 App Store Connect 分发 `.mobileprovision` 文件，进行 Base64 编码。 |
| `APPSTORE_KEY_ID` | App Store Connect 团队 API Key 的 Key ID。 |
| `APPSTORE_ISSUER_ID` | 团队 API Key 的 Issuer ID。 |
| `APPSTORE_PRIVATE_KEY` | 下载的 `.p8` 文件完整原文，保留 PEM 首尾行和换行，**不进行 Base64 编码**。 |
| `API_ENDPOINT` | 已有的应用 API 地址，继续沿用其他平台的配置。 |

`.p12` 可在 macOS「钥匙串访问」中选中 Apple Distribution 身份及其私钥后导出。描述文件必须是同一证书签发的 App Store Connect 类型，且未过期；流程会拒绝开发、Ad Hoc、企业、错误 App ID、错误 Team ID，以及不匹配或已撤销的签名身份。

可以通过 `gh` 直接读取文件设置 Secrets，避免把私钥或 Base64 内容粘贴到命令历史中：

```bash
base64 -i /安全目录/UBAA-distribution.p12 | gh secret set IOS_CERTIFICATE_P12_BASE64
gh secret set IOS_CERTIFICATE_PASSWORD
base64 -i /安全目录/UBAA.mobileprovision | gh secret set IOS_PROVISIONING_PROFILE_BASE64
gh secret set APPSTORE_PRIVATE_KEY < /安全目录/AuthKey_KEYID.p8
gh secret set APPSTORE_KEY_ID
gh secret set APPSTORE_ISSUER_ID
```

API Key 在 App Store Connect 的「用户和访问 → 集成 → App Store Connect API」中创建，需具备目标 App 的上传权限，例如 Developer、App Manager 或 Admin。App Store Connect 中须已存在与 Bundle ID 对应的 App，开发者会员和必要协议须有效。

仓库 Variables 可选配置 `IOS_BUNDLE_ID` 和 `IOS_TEAM_ID`，默认分别为当前工程的 `cn.edu.ubaa` 和 `59KR48BHSR`。更换 App 或开发者团队时，应同时更新签名材料和对应 Variable。

#### 触发与版本号

发布与源码版本相符的 GitHub Release（例如 `v1.8.0`）会构建全部平台，并自动上传 iOS App。iOS 营销版本读取 `gradle.properties` 的 `project.version`，Release tag 必须等于该版本号或其 `v` 前缀形式。

独立运行 iOS 时，在 **Actions → Build and Release → Run workflow** 中选择包含此流程的分支，勾选 `ios_only`。`ios_upload` 默认开启；关闭后仍会验证签名并生成 IPA，但不上传 App Store Connect。也可以使用：

```bash
# 独立构建并上传 iOS；dev 必须已包含此工作流改动。
gh workflow run release.yml --ref dev -f ios_only=true -f ios_upload=true

# 仅验证完整签名构建，并在 Actions 下载产物。
gh workflow run release.yml --ref dev -f ios_only=true -f ios_upload=false
```

构建号默认为 `(project.version.code + GITHUB_RUN_NUMBER).GITHUB_RUN_ATTEMPT`，例如版本代码 `30`、运行序号 `41`、首次运行对应 `71.1`，重试为 `71.2`。也可填写 `ios_build_number` 指定一个尚未上传且高于 App Store Connect 当前构建的号码。号码遵守 Apple 的格式限制：首段为最多 4 位的正整数，后续最多两段、每段最多 2 位。重新运行较早的工作流时，如果已有更新的构建上传，应新开一次运行或指定更大的构建号。

手动构建全部平台时，应选择已有 Release 对应的 tag，因为其他平台会直接向 GitHub Release 上传资产。`ios_only=true` 可以直接使用分支；iOS 仅在 Release 事件或 tag 上向 GitHub Release 上传资产。

#### 产物与排错

每次成功导出后，Actions 都保存 `UBAA-iOS-v{版本}-{构建号}` artifact，保留 14 天，包含 IPA、dSYM 压缩包和原有 Kotlin framework 压缩包。上传 Apple 失败时，这些产物仍可下载。运行摘要记录版本、构建号、Bundle ID 和源码 SHA；正式 Release 或 tag 运行也会将这些文件附加到 GitHub Release。

签名材料只写入 runner 临时目录，临时 Keychain 和安装的描述文件会在成功、失败或取消后的清理步骤移除，不进入构建产物和 Gradle 缓存。`.p12`、`.p8`、`.mobileprovision`、`.ipa` 和 `.xcarchive` 均已加入 Git 忽略规则。

- 缺失 Secret、描述文件过期或证书不匹配：按日志提示更新相应 Secret，再运行 iOS。
- App Store Connect 返回构建号重复：新开一次运行，或填写更大的 `ios_build_number`。
- API 认证失败：检查 Key ID、Issuer ID、`.p8` 原文及 API Key 权限。
- 上传成功但 TestFlight 暂不可见：等待 Apple 处理，并在 App Store Connect 查看处理状态或出口合规要求。

本地可运行 `python3 -m unittest discover -s .github/scripts -p 'test_ios_release.py'` 检查版本号和签名校验规则；`actionlint .github/workflows/release.yml .github/workflows/test.yml` 检查工作流。规则测试、Xcode 归档、GitHub Actions 签名构建和 App Store Connect 实际上传分别提供对应阶段的证据。

## Web Wasm 发布

当前没有独立的 `.github/workflows/upload.yml`。Web Wasm 发布在 `.github/workflows/release.yml` 的 `build-web-wasm` job 中完成：

1. 使用 `:composeApp:wasmJsBrowserDistribution` 构建 `composeApp/build/dist/wasmJs/productionExecutable`。
2. 将 Web Wasm 产物压缩为 `UBAA-Web-Wasm-v{VERSION}.zip` 并上传到 GitHub Release。
3. 使用 Cloudflare Wrangler 将同一目录部署到 Pages 项目 `ubaa`，命令显式传入 `--branch=main`。
4. 调用 Cloudflare API 刷新 `app.buaa.team` 缓存。

## Docs 发布

`.github/workflows/docs.yml` 在 `dev` 分支推送或手动触发时执行：

1. Checkout。
2. Setup Node 22。
3. `npm ci`。
4. `npm run docs:build`。
5. 校验 SSH Secrets。
6. 写入 SSH key 并执行 `ssh-keyscan`。
7. 在服务器创建目标目录。
8. `rsync -az --delete docs/.vitepress/dist/` 到 `DOCS_DEPLOY_PATH`。
9. 调用 Cloudflare API 刷新 `www.buaa.team` 缓存。

服务器需要自行配置 Nginx、Caddy 或其他静态文件服务。本仓库只负责同步构建产物。

## bhpan 发布资产任务

根 Gradle 构建脚本注册了两个 bhpan 相关任务：

- `verifyBhpanReadOnly`：读取 `local.properties` 中的 bhpan 配置，做只读认证链验证。
- `uploadLatestReleaseToBhpan`：读取 GitHub 最新 release，选择 `UBAA-*` 资产，删除 bhpan 中已有的同名前缀文件并重新上传。

`uploadLatestReleaseToBhpan` 会改变真实网盘文件，不属于普通构建验证命令；只有在明确授权真实发布/上传时才运行。

## 来源文件

- `.github/workflows/release.yml`
- `.github/workflows/docs.yml`
- `build.gradle.kts`
- `buildSrc/src/main/kotlin/cn/edu/ubaa/gradle/UploadLatestReleaseToBhpanTask.kt`
- `composeApp/src/webMain/resources/index.html`
- `composeApp/src/webMain/resources/sw.js`
- `package.json`
- `package-lock.json`
