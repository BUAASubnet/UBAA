# 开发环境设置

本页供准备本机开发环境的贡献者使用，说明需要的工具与版本、安装步骤和全部 `.env` 变量。只想尽快运行 App 时，先看[从零开始运行 App](getting-started.md)。除另有说明外，命令都在仓库根目录执行；Dart/Flutter 的调用规则见 [AGENTS 项目工具链入口](../../AGENTS.md#项目工具链入口)。

## 工具与版本

下表列出检查脚本、锁文件和 CI 使用的版本，精确版本数据以 [`scripts/tools/versions.env`](../../scripts/tools/versions.env) 为准。未锁定的通用工具只列出所需能力。

| 工具 | 版本或能力 | 用途 |
|---|---|---|
| Git、Bash、just | Git 支持 worktree；Bash 3.2+；just 1.59.0 已验证位置参数透传 | 所有脚本入口；版本由 `just doctor` 核对 |
| Rustup、Rust、rustfmt、Clippy | `rust-toolchain.toml`：Rust 1.100.0，含 rustfmt、Clippy | Rust 构建、测试和文档 |
| Python | 3.11+，本机使用 3.15.2；含 venv、pip | Python 门禁与质量工具环境 |
| Python 开发依赖 | `scripts/tools/requirements.txt` 中的版本及哈希 | YAML/JSON5 解析；显式 bootstrap 安装，缺少 wheel 时构建经摘要校验的源码包 |
| ShellCheck | 精确 0.11.0 | `check-strict`；可通过 `UBAA_SHELLCHECK_BIN` 指定 |
| cargo-deny | 精确 0.20.2 | `just dependency-audit`；版本来自 `scripts/tools/versions.env` |
| 官方 Flutter / Dart | Flutter 3.50.0，commit `ab2912035e160d9cad6306df307576da6128ebdb`；Dart 3.14.0 | 根 Pub workspace 的七个正式包、测试辅助包和官方宿主 |
| FRB codegen / cargo-expand | 精确 2.13.0 / 1.0.127 | FRB 生成检查；运行时与生成器须一致 |
| ripgrep | 提供 `rg --files` | `just source-files` |
| zip、unzip、file、tar、curl | 平台可用版本；tar 支持 xz | 合同夹具、归档、产物检查和显式工具下载 |
| SHA-256 工具 | `shasum -a 256` 或 `sha256sum` | 产物、源码和发布锁文件摘要共用同一回退逻辑 |
| Node.js、npm | Node 26，至少 26.13.1；npm 支持 `npm ci` | 根 `package.json` 用于 VitePress 文档站；应用服务使用独立的 npm 项目 |
| OHOS Flutter | tag `3.41.10-ohos-1.0.1`，commit `adaf911c35c9136a7d18fc424d714c9ec7724e60` | OHOS 独立 SDK，不能用官方 SDK 替代 |
| DevEco / SDK | DevEco/CLI 26.0.0.821（Release）、API26；Hvigor 6.26.4、ohpm 26.0.0.630 | OHOS 检查与构建；支持 Studio `tools/` 和 CLI `tool/` 布局 |
| JDK | 17+ | OHOS 预检；Android 使用对应 Gradle/Flutter 支持的 JDK |
| 平台构建工具 | Apple：Xcode、Command Line Tools、CocoaPods；Android：SDK/NDK；Linux：Clang、CMake、Ninja、GTK 开发库；Windows：Visual Studio C++ 桌面工具 | 按需原生构建；用 `just flutter doctor -v` 检查当前平台 |

平台目标见[平台矩阵](../architecture/flutter-platforms.md)。macOS 产物检查使用系统 `/usr/bin/codesign` 和 `/usr/libexec/PlistBuddy`。

## 空白机器上的最短路径

先用操作系统包管理器安装上述通用工具、Rustup、Python 3.11+ 和 ShellCheck 0.11.0。以下准备过程会从 Git、crates.io、Python 和 Dart 依赖源下载固定工具或锁定依赖。无需学校账号。

```bash
(umask 077; cp -n .env.example .env)
```

编辑 `.env`，至少把 `UBAA_FLUTTER_HOME` 设为准备放官方 Flutter 的绝对路径（目录可以还不存在）。然后运行：

```bash
just setup
```

`just setup` 按 `versions.env` 克隆锁定的 Flutter、安装 Rust 工具链和 cargo-expand/FRB codegen/cargo-deny，并依次执行 refs-bootstrap、质量环境、`cargo fetch --locked` 与 Dart 依赖准备。已一致的工具直接跳过；已有 SDK 不是锁定提交时停止，不改写。具体步骤见 [setup.sh](../../scripts/bootstrap/setup.sh)，它也是手工安装的参考。

之后任何时候都可以运行只读的 `just doctor`，逐项对照锁定版本，必需项不符时退出 1。

后续维护：

- 首次建立缺失冻结引用才执行 `just refs-bootstrap`，之后只用 `just refs` 只读校验。
- 质量环境缺失或依赖锁变更时，显式重跑 `just quality-tools-bootstrap`。普通 checker 不会自动安装 Python 依赖。
- Cargo 和 Flutter 检查可能补充依赖缓存，但都不访问学校服务。

环境准备后的检查方式见[开发命令](commands.md)和[测试策略](testing.md)。FRB 生成检查单独执行；完整 Flutter golden 测试使用 macOS 渲染基准。

### 按需准备的其他环境

- 文档站：执行 `npm ci` 和 `npm run docs:build`。
- 应用服务：`just app-service-check` 按应用服务的独立锁文件安装依赖并运行检查。此检查需要 PostgreSQL 17 工具（macOS 可用 `brew install postgresql@17`），会自动启动和清理隔离测试数据库。
- 原生构建：安装对应平台工具，再执行 `just flutter doctor -v`。
- OHOS：安装上述 fork 与 DevEco/API26，配置下表中的路径，执行 `rustup target add aarch64-unknown-linux-ohos`，然后运行 `bash apps/ubaa_ohos/scripts/check-toolchain.sh` 预检。

### Cargokit 的 Rust 版本

Cargokit 使用 `crates/ubaa_flutter_bridge/cargokit.yaml` 中各构建模式的精确 Rust 版本：

- 该文件采用 JSON 兼容的 YAML。`just tool-version-check` 逐模式核对 `rust-toolchain.toml`，修改 Rust 锁定版本时必须同步此配置。
- 工具链主机遵循 `rustup show` 的 `Default host`，与 Cargo 的 `--target` 编译目标分别处理。安装检测、安装后重查和目标组件操作都使用补全后的完整工具链名称。
- vendored Cargokit 在上游通道配置的基础上增加了精确版本支持，改动范围登记在 `packages/ubaa_bindings/cargokit/UPSTREAM.json`。
- Cargokit 回归可在其 `build_tool` 目录通过根 justfile 的 `dart test/toolchain_test.dart` 入口直接运行。

### Windows

Windows runner 的 MSVC 目标已在 CMake 中设置 `/utf-8`，构建时无须再设置 `CL=/utf-8`。本机有多套 Visual Studio 时，选择包含 ATL 的实例。

## 迁移旧配置

旧文件不会自动读取。由配置所有者在仓库根目录运行：

```bash
python3 scripts/lib/toolchain.py migrate
```

如还需迁移旧部署目标，在同一命令附加 `--target <旧目标 JSON 路径>`，选择一个目标。命令合并旧工具链、学校账号和选定的部署目标，保留 `.env` 已有键及原文件，输出不含配置值。手工迁移也可按 `.env.example` 逐键填写；旧目标的 `account_id`、`worker_name`、`database_id`、`kv_namespace_id`、`domain` 对应下表中五个部署目标键。

## UBAA 环境变量

### 配置来源

| 内容 | 维护位置 |
|---|---|
| 本机工具路径、构建渠道、部署目标、已接入的 Android/OHOS 签名参数 | 根目录 `.env`；键和用途见 [`.env.example`](../../.env.example) |
| CI 的同名参数与凭据 | GitHub Environment Variables/Secrets；通过进程环境注入，无需生成或上传完整 `.env` |
| 渠道最新版本、最低支持版本、下载地址 | [`channels.json`](../../services/app_service/config/channels.json)，确认渠道可下载后更新 |
| 公告与隐私政策 | `docs/site/` 下的 Markdown 源文件 |
| 工具链版本、正式应用版本、依赖版本 | `scripts/tools/versions.env`、应用版本声明和锁文件，随源码审阅 |
| 检查与部署分支 | `.github/workflows/`，环境的部署分支限制在 GitHub 设置中维护 |

客户端构建渠道用于选择安装包的分发渠道，渠道 JSON 描述该渠道已经可下载的版本。构建新版本不会自动提高渠道的最低支持版本。证书、keystore 等二进制文件保存在 `.sign/`，`.env` 只引用路径；Apple 签名继续使用 Keychain/Xcode，细节见[应用签名配置](../runbooks/app-signing.md)。

根目录 `.env` 是本机唯一的项目环境配置文件，`.env.example` 列出可用键及导出范围。

- 权限：macOS 和 Linux 使用 `0600`，Windows 限制为当前用户可读写。
- 语法：不要用 Shell 执行该文件。只支持 `KEY=value`、引号和注释；非机密值支持 `$HOME`、`${HOME}` 和前面已定义的非机密键，含下划线的引用写为 `${NAME_WITH_UNDERSCORE}`。账号和 Token 按字面读取，不展开变量。
- 优先级：已导出的同名变量优先。
- 占位：示例中的 `<sdk-root>`、`<private-evidence>` 和 `<repo-root>` 都是逻辑占位，运行前换成本机绝对路径。Windows Bash 使用 SDK 能识别的绝对路径，工具链检查支持 `cygpath` 转换。

| 变量 | 默认值、示例与作用 |
|---|---|
| `UBAA_FLUTTER_HOME` | 必填：官方 Flutter SDK 根目录，如 `<sdk-root>/flutter`，必须包含 `bin/flutter` |
| `UBAA_OHOS_FLUTTER_HOME` | OHOS 入口必填：`<sdk-root>/flutter_ohos`，必须匹配锁定 fork |
| `UBAA_FRB_CODEGEN` | 默认在 PATH 查找 `flutter_rust_bridge_codegen`；示例为该程序的绝对路径 |
| `UBAA_FLUTTER_VERBOSE` | 默认 `0`，`1` 为构建添加 `-v` |
| `UBAA_DEVECO_HOME` | OHOS 检查和构建必须显式指定 DevEco/CLI 根目录；macOS Studio 常见位置为 `/Applications/DevEco-Studio.app/Contents` |
| `UBAA_HMOS_SDK_HOME` | OHOS 预检默认 `$UBAA_DEVECO_HOME/sdk`；如 `<sdk-root>/deveco/sdk` |
| `UBAA_OHOS_NODE_HOME` | 默认 DevEco 的 `tools/node` 或 `tool/node`；预检、插件合同与构建共用该解析规则 |
| `UBAA_OHOS_NO_CODESIGN` | 默认 `0`；`1` 仅允许无签名 debug HAP，不能用作发布或实体设备通过证据 |
| `UBAA_SHELLCHECK_BIN` | 默认在 PATH 查找 ShellCheck；覆盖为 0.11.0 程序的绝对路径 |
| `UBAA_QUALITY_TOOLS_DIR` | 默认 `${XDG_CACHE_HOME:-$HOME/.cache}/ubaa2-quality/<key>`，key 含 Python 主次版本和 requirements 摘要；覆盖值须为绝对目录 |
| `UBAA_RELEASE_REPORT_DIR` | 发布 preflight 的默认输出目录；须为空的绝对目录。未配置且无位置参数时使用临时目录，退出删除 |
| `UBAA_UI_EVIDENCE_DIR` | UI 验收媒体目录，必须位于被忽略的 `.ubaa_local/` 任务子目录 |
| `UBAA_APP_SERVICE_URL`、`UBAA_DISTRIBUTION_CHANNEL` | 客户端构建参数；任一为空即停用应用服务。正式包使用已验收的 HTTPS 地址，渠道为 `github`、`app_store` 或 `app_gallery` |
| `UBAA_TEST_USERNAME`、`UBAA_TEST_PASSWORD` | 学校账号和密码的主名称；只交给显式真实验证入口 |
| `UBAA_USERNAME`、`UBAA_PASSWORD` | 兼容旧凭据名称，主名称为空时回退；新配置使用主名称 |

### 构建签名参数

Android 使用 `ANDROID_STORE_FILE`、`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。OHOS 使用对应的 `OHOS_*` 四项，加上 `OHOS_CERT_FILE` 和 `OHOS_PROFILE_FILE`，可选 `OHOS_SIGN_ALG`，默认 `SHA256withECDSA`。OHOS Debug 使用独立的 `OHOS_DEBUG_*` 同名字段。模板和构建示例见[签名手册](../runbooks/app-signing.md)。

每组参数先选进程环境，再选 `.env`。进程提供组内任一字段时，整组都取自进程，缺项立即报错，避免 CI keystore 与本机密码混用。路径支持公共变量引用，相对路径以仓库根目录为基准；密码、别名和签名算法按字面读取。Android 四个字段全部显式留空时禁用该组签名，并覆盖旧本机文件。未配置统一字段时，原有原生工具配置仍可使用。

`just flutter-build`、`just ohos-check` 和直接执行的构建脚本只在最终 SDK 构建时读取对应材料。`just flutter build apk/appbundle` 的 Release 模式和 `just flutter-ohos build hap/app` 也使用相同规则。依赖准备、分析、测试与 `--no-codesign` 不取得签名环境变量。原生 IDE 不自动读取根 `.env`，继续使用原生签名配置。

### 调用时设置的变量

下列变量由调用者、平台签名工具或测试入口设置，根 `.env` 不导出。

| 变量 | 默认值、示例与作用 |
|---|---|
| `UBAA_RELEASE_STORE_FILE`、`UBAA_RELEASE_STORE_PASSWORD`、`UBAA_RELEASE_KEY_ALIAS`、`UBAA_RELEASE_KEY_PASSWORD` | 既有 Android 原生入口字段；统一配置使用上节的 `ANDROID_*`，旧字段只在未提供统一字段时读取 |
| `UBAA_VERIFY_DATE`、`UBAA_VERIFY_CAMPUS_ID` | live CLI 默认校园时区当天、校区 `1`；示例 `2026-10-29`、`1` |
| `UBAA_CONFIG_DIR` | 显式真实验证可指定被忽略的私有配置目录，隔离默认会话 |
| `UBAA_LIVE_MATERIAL_SCOPE` | 真实离线启动测量的材料归属标识，由 runner 生成；禁止填入个人资料 |
| `UBAA_CORE_LIVE_BINARY`、`UBAA_CORE_LIVE_BUILD` | 默认 `<repo-root>/target/debug/core-live`、`yes`；`no` 复用已构建程序 |
| `UBAA_CORE_LIVE_SCRIPT` | 默认 `scripts/live/core-live.sh`；测试可替换 launcher，不作为凭据入口 |

其他相关变量与缓存：

- 质量缓存位于仓库外。回收旧 key 时，先停止使用对应环境的进程，再删除确认已不用的 key 目录。
- `PUB_CACHE` 默认使用 Dart 的用户缓存（通常 `$HOME/.pub-cache`）。发布依赖报告在缺少依赖源码时记为 `source_unavailable`，据此补齐发布材料。
- OHOS native 编译使用 `OHOS_SDK_HOME`，默认从 DevEco SDK 派生，路径不能包含空白；`DEVECO_SDK_HOME`、`DEVECO_NODE_HOME` 由 OHOS 构建入口设置。
- 常用标准变量还有 `JAVA_HOME`、Android SDK/NDK 变量、`XDG_CACHE_HOME`、`TMPDIR`。

## 测试注入与构建内部变量

以下变量同样使用 UBAA 前缀，但只用于测试或构建内部，不在本地配置白名单内。

| 名称 | 用途与示例 |
|---|---|
| `UBAA_CODESIGN_BIN`、`UBAA_PYTHON_BIN` | 产物检查的负向合同夹具使用；正式 macOS 检查固定系统程序，不能据此绕过签名检查 |
| `UBAA_CODE_SIGN_STYLE` | Xcode 配置内部变量，默认 `Automatic`；本地签名覆盖见宿主 README |
| `UBAA_CONTRACT_ROOT` | 合同版本 checker 的合成仓库根覆盖，日常不设置 |
| `UBAA_TYPESCRIPT` | OHOS 网络插件合同脚本导出的 DevEco TypeScript 文件位置 |
| `UBAA_NETWORK_PLUGIN_SOURCE` | 网络插件原生合同测试的源码覆盖，日常不设置 |
| `UBAA_RUST_CRATE_DIR` | CMake 构建内部变量，指向 Rust crate；不是终端环境配置 |
| `UBAA_BRIDGE_LOG_CHILD`、`UBAA_TEST_LOCK_DIRECTORY` | Rust 子进程日志与锁预算测试的内部标记/目录 |
| `UBAA_TEST_SDK_ROOT`、`UBAA_TEST_SDK_COMMIT`、`UBAA_TEST_SDK_VERSION`、`UBAA_TEST_SDK_OUTPUT`、`UBAA_TEST_SDK_COMPLETED` | 假 SDK 的临时路径、版本、输出与完成标记，由工具链合同测试设置 |
| `UBAA_TEST_SHELLCHECK_LOG`、`UBAA_TEST_SHELLCHECK_EXIT` | 假 ShellCheck 的调用记录和退出码 |
| `UBAA_TEST_CODESIGN_LOG`、`UBAA_TEST_PLIST_LOG`、`UBAA_TEST_ENTITLEMENTS` | 假签名程序的日志与 entitlements 样本选择 |

真实验证仍须遵守仓库的凭据与请求边界，普通环境搭建和质量检查可以将机密键留空。媒体、日志的归档写法见[证据存储规则](../design/evidence/README.md)。

## HarmonyOS 的 GitHub 托管构建

完整原生验收和 Release 都在 GitHub 的 Ubuntu 24.04 runner 构建 HarmonyOS。`scripts/bootstrap/ohos.sh` 安装锁定的 Flutter OHOS、DevEco CLI 26.0.0.821 和 API26，并使用 runner 预装的 JDK 21。CLI 归档取自固定版本的 [SDK 镜像](https://github.com/ErBWs/ohos-sdk/releases/tag/26.0.0.821)，下载后按版本清单中的固定摘要校验。版本与组件对应关系以[华为发布说明](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/deveco-studio-new-features-2600/)为准。

检查作业使用无签名 Debug HAP。Release 作业在 release-production 环境取得签名材料，构建商店 APP 包；上传与处理状态检查由独立商店作业执行。全部作业使用 GitHub 托管 runner，不依赖维护者电脑在线。
