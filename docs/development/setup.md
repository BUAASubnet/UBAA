# 开发环境设置

SDK 路径配置在本地 `.env.toolchain`，模板为 `.env.toolchain.example`。just 自动加载工具配置，文件缺失不影响非 SDK 配方；直接运行脚本也通过 `scripts/lib/toolchain.py` 的唯一回退解析器读取同一文件。已导出的环境变量优先。工具入口绝不加载 `.env.local`，凭据与工具链分开。Dart/Flutter 一律通过 `just dart`、`just flutter` 调用，OHOS 使用 `just flutter-ohos`，不写 SDK 绝对路径，不依赖 PATH 中的 Dart/Flutter。所有命令均在 UBAA2 仓库根目录执行。

## 工具与版本

下表记录当前仓库检查脚本、锁文件和 CI 使用的版本。未锁定的通用工具列出所需能力，不把维护者机器上的版本当作要求。

| 工具 | 版本或能力 | 用途 |
|---|---|---|
| Git、Bash、just | Git 支持 worktree；Bash 3.2+；just 1.51.0 已验证 dotenv 设置与位置参数透传 | 所有脚本入口；just 目前未锁版本 |
| Rustup、Rust、rustfmt、Clippy | `rust-toolchain.toml`：Rust 1.95.0，含 rustfmt、Clippy | Rust 构建、测试和文档 |
| Python | 3.11+，含 venv、pip | Python 门禁与质量工具环境 |
| Python 开发依赖 | `scripts/tools/requirements.txt` 中的版本及哈希 | JSON Schema、YAML/JSON5 解析；显式 bootstrap 安装 |
| ShellCheck | 精确 0.11.0 | `check-strict`；可通过 `UBAA_SHELLCHECK_BIN` 指定 |
| 官方 Flutter / Dart | Flutter 3.41.9，commit `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`；Dart 3.11.5 | 共享七包和官方宿主 |
| FRB codegen / cargo-expand | 精确 2.13.0 / 1.0.126 | FRB 生成检查；运行时与生成器须一致 |
| ripgrep | 提供 `rg --files` | `just source-files` |
| zip、unzip、file、tar、curl | 平台可用版本；tar 支持 xz | 合同夹具、归档、产物检查和显式工具下载 |
| SHA-256 工具 | `shasum -a 256`；发布 preflight 当前还要求 `sha256sum` | 产物及源码摘要；两种入口的兼容性差异留待门禁阶段处理 |
| Node.js、npm | Node 22，至少 22.12.0；npm 支持 `npm ci` | 根 `package.json` 仅用于 VitePress 文档站 |
| OHOS Flutter | tag `3.41.10-ohos-1.0.1`，commit `adaf911c35c9136a7d18fc424d714c9ec7724e60` | OHOS 独立 SDK，不能用官方 SDK 替代 |
| DevEco / SDK | DevEco/CLI 26.0.0.821（26 Beta2）、API26；Hvigor 6.26.4、ohpm 26.0.0.630 | OHOS 检查与构建；支持 Studio `tools/` 和 CLI `tool/` 布局 |
| JDK | 17+ | OHOS 预检；Android 使用对应 Gradle/Flutter 支持的 JDK |
| 平台构建工具 | Apple：Xcode、Command Line Tools、CocoaPods；Android：SDK/NDK；Linux：Clang、CMake、Ninja、GTK 开发库；Windows：Visual Studio C++ 桌面工具 | 按需原生构建；用 `just flutter doctor -v` 检查当前平台 |

平台目标与既有验收范围见[平台矩阵](../architecture/flutter-platforms.md)。macOS 产物检查使用系统 `/usr/bin/codesign` 和 `/usr/libexec/PlistBuddy`。键盘截图驱动使用 macOS 的 `xcrun simctl`，历史 E3c 采集器使用系统 `screencapture`。

## 空白机器上的最短路径

先用操作系统包管理器安装上述通用工具、Rustup、Python 3.11+ 和 ShellCheck 0.11.0。以下准备过程会从 Git、crates.io、Python 和 Dart 依赖源下载固定工具或锁定依赖。无需学校账号。

```bash
# 先进入刚 clone 的 UBAA2 根目录，再编辑 .env.toolchain 中的本机 SDK 位置。
cp .env.toolchain.example .env.toolchain
# 下列安装示例须与刚编辑的 UBAA_FLUTTER_HOME 保持一致。
export UBAA_FLUTTER_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/ubaa2_sdks/flutter"
git clone --branch 3.41.9 --depth 1 https://github.com/flutter/flutter.git "$UBAA_FLUTTER_HOME"
git -C "$UBAA_FLUTTER_HOME" checkout --detach 00b0c91f06209d9e4a41f71b7a512d6eb3b9c694
export PATH="$HOME/.cargo/bin:$PATH"
rustup toolchain install 1.95.0 --profile minimal --component rustfmt --component clippy
bash scripts/check/flutter-toolchains.sh official
just flutter precache
cargo install --locked cargo-expand --version '=1.0.126'
cargo install --locked flutter_rust_bridge_codegen --version '=2.13.0'
export UBAA_FRB_CODEGEN="$(command -v flutter_rust_bridge_codegen)"
just refs-bootstrap
just quality-tools-bootstrap
cargo fetch --locked
just flutter-dependencies
```

首次建立缺失冻结引用才执行 `just refs-bootstrap`，之后只用 `just refs` 只读校验。质量环境缺失或依赖锁变更时显式重跑 `just quality-tools-bootstrap`。普通 checker 不会自动安装 Python 依赖。Cargo 和 Flutter 检查可能补充依赖缓存，均不主动访问学校上游。

环境准备后的检查方式见[命令说明](commands.md)和[测试说明](testing.md)。FRB 生成检查单独执行；2026-10-29 阶段 1 验证使用锁定生成器 2.13.0，生成零漂移，审计记录的漂移未复现。当前验证范围见[迁移状态](../migration/status.md)。完整 Flutter golden 测试使用 macOS 渲染基准。

文档站另执行 `npm ci` 和 `npm run docs:build`。原生构建再安装对应平台工具，并执行 `just flutter doctor -v`。OHOS 另行安装上述 fork 与 DevEco/API26，配置下表路径，然后安装 `rustup target add aarch64-unknown-linux-ohos`，先运行 `bash apps/ubaa_ohos/scripts/check-toolchain.sh` 预检。

## UBAA 环境变量

`.env.toolchain.example` 提供工具配置模板，`.env.example` 提供凭据模板。工具变量填入 `.env.toolchain`，也可用当前终端导出的同名变量覆盖。配置只支持 `KEY=value`、引号、注释和 `$HOME` / `${HOME}` 这类变量引用；含下划线的引用使用 `${NAME_WITH_UNDERSCORE}`，不执行 Shell 命令。示例中的 `<sdk-root>`、`<private-evidence>` 和 `<repo-root>` 均为逻辑占位，运行前必须换成当前机器的绝对路径。Windows Bash 使用 SDK 能识别的绝对路径，工具链检查支持 `cygpath` 转换。

| 变量 | 默认值、示例与作用 |
|---|---|
| `UBAA_FLUTTER_HOME` | 必填：官方 Flutter SDK 根目录，如 `<sdk-root>/flutter`，必须包含 `bin/flutter` |
| `UBAA_OHOS_FLUTTER_HOME` | OHOS 入口必填：`<sdk-root>/flutter_ohos`，必须匹配锁定 fork |
| `UBAA_FRB_CODEGEN` | 默认在 PATH 查找 `flutter_rust_bridge_codegen`；示例为该程序的绝对路径 |
| `UBAA_FLUTTER_VERBOSE` | 默认 `0`，`1` 为构建添加 `-v` |
| `UBAA_DEVECO_HOME` | macOS 默认 `/Applications/DevEco-Studio.app/Contents`，其他系统或 CLI 安装须显式指定 DevEco/CLI 根目录 |
| `UBAA_HMOS_SDK_HOME` | OHOS 预检默认 `$UBAA_DEVECO_HOME/sdk`；如 `<sdk-root>/deveco/sdk` |
| `UBAA_OHOS_NODE_HOME` | OHOS 预检默认 DevEco 的 `tools/node` 或 `tool/node`；构建入口仍使用 DevEco 配套 Node |
| `UBAA_OHOS_NO_CODESIGN` | 默认 `0`；`1` 仅允许无签名 debug HAP，不能用作发布或实体设备通过证据 |
| `UBAA_SHELLCHECK_BIN` | 默认在 PATH 查找 ShellCheck；覆盖为 0.11.0 程序的绝对路径 |
| `UBAA_QUALITY_TOOLS_DIR` | 默认 `${XDG_CACHE_HOME:-$HOME/.cache}/ubaa2-quality/<key>`，key 含 Python 主次版本和 requirements 摘要；覆盖值须为绝对目录 |
| `UBAA_RELEASE_REPORT_DIR` | 发布 preflight 的默认输出目录；须为空的绝对目录。未配置且无位置参数时使用临时目录，退出删除 |
| `UBAA_UI_EVIDENCE_DIR` | 截图驱动必填，仓库外新建或空的私有绝对目录，如 `<private-evidence>/2026-10-29/run_01`；包含符号链接时按实际目标校验 |
| `UBAA_KEYBOARD_RUN_ID`、`UBAA_UI_SIMULATOR_ID` | 键盘截图握手标识、当前机器的模拟器 UUID；前者须与测试侧同名 dart-define 一致 |
| `UBAA_ENV_FILE` | 默认 `<repo-root>/.env.local`，显式 live launcher 的凭据文件路径 |
| `UBAA_TEST_USERNAME`、`UBAA_TEST_PASSWORD` | 凭据文件中的主名称，无默认值；只交给显式真实验证入口，不用于普通回归 |
| `UBAA_USERNAME`、`UBAA_PASSWORD` | 兼容旧凭据名称，主名称为空时回退；本阶段保留兼容行为，新配置使用主名称 |
| `UBAA_VERIFY_DATE`、`UBAA_VERIFY_CAMPUS_ID` | live CLI 默认校园时区当天、校区 `1`；示例 `2026-10-29`、`1` |
| `UBAA_CONFIG_DIR` | 原生真实验证使用的独立配置目录，无默认值；普通回归执行器主动移除此变量 |
| `UBAA_LIVE_MATERIAL_SCOPE` | 真实离线启动测量的材料归属标识，由 runner 生成；禁止填入个人资料 |
| `UBAA_STARTUP_OUTPUT` | 真实启动测量输出目录，由 runner 传入，须在仓库外 |
| `UBAA_STARTUP_MODE`、`UBAA_STARTUP_SCENARIO` | 测量 driver 的运行模式与场景，由 `scripts/live/offline_startup/run.py` 配置，按该入口参数使用 |
| `UBAA_CORE_LIVE_BINARY`、`UBAA_CORE_LIVE_BUILD` | 默认 `<repo-root>/target/debug/core-live`、`yes`；`no` 复用已构建程序 |
| `UBAA_CORE_LIVE_SCRIPT` | 默认 `scripts/live/core-live.sh`；测试可替换 launcher，不作为凭据入口 |

质量缓存位于仓库外。需要回收旧 key 时，先停止使用对应环境的进程，再删除确认已不用的 key 目录。`PUB_CACHE` 默认使用 Dart 的用户缓存（通常 `$HOME/.pub-cache`），发布依赖报告在缺少依赖源码时记为 `source_unavailable`，应据此补齐发布材料。OHOS native 编译还使用 `OHOS_SDK_HOME`，默认从 DevEco SDK 派生，路径不能包含空白；`DEVECO_SDK_HOME`、`DEVECO_NODE_HOME` 由 OHOS 构建入口设置。常用标准变量还有 `JAVA_HOME`、Android SDK/NDK 变量、`XDG_CACHE_HOME`、`TMPDIR`。

## dart-define、测试注入与构建内部变量

以下同样使用 UBAA 前缀，但不是日常 `.env.local` 配置。dart-define 通过 `--dart-define=名称=值` 传入，不能只设置终端环境变量。

| 名称 | 用途与示例 |
|---|---|
| `UBAA_UI_STATE` | 合成巡检状态，如 `normal`，供 manual/synthetic 入口使用 |
| `UBAA_UI_SOURCE_SHA` | 合成/原生证据的源码标识，如当前 Git SHA；无默认值 |
| `UBAA_LIVE_READONLY`、`UBAA_LIVE_RETRY_FAILED` | 显式只读实测及失败项重试开关，默认 false |
| `UBAA_EXPECTED_ROUTE` | 真实验证预期路线，`direct` 或 `webvpn`；部分测量 driver 同时读取同名环境变量 |
| `UBAA_VERIFY_WEBVPN` | 课表组件通道验证选择 WebVPN，默认 false |
| `UBAA_SECURE_STORAGE_AVAILABLE` | Linux 安全存储能力的预期值，默认 false |
| `UBAA_ROTATION_RUN_ID`、`UBAA_ROTATION_USER_THEME` | 旋转测试的握手标识与用户主题开关，后者默认 false |
| `UBAA_STARTUP_LOCK_DIR` | 外部合成启动锁夹具，由 `startup_lock_runner.py` 自动注入临时目录 |
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

真实验证仍须遵守仓库的凭据与请求边界，普通环境搭建和质量检查不需要创建凭据文件。媒体、日志的归档写法见[证据存储规则](../design/evidence/README.md)。
