# 从零开始运行 App

本页给第一次参与开发的贡献者，列出从 clone 仓库到在本机运行 UBAA 客户端的最短路径。各工具的版本和变量说明见[开发环境](setup.md)，所有检查命令见[开发命令](commands.md)。陌生术语可查[术语表](glossary.md)。

整个过程不需要学校账号，也不会请求学校服务。准备阶段会从 Git、crates.io、Python 和 Dart 依赖源下载锁定的工具与依赖。

## 1. 安装基础工具

用操作系统的包管理器安装：

- Git、Bash、[just](https://github.com/casey/just)
- Rustup（Rust 版本由仓库的 `rust-toolchain.toml` 自动选择）
- Python 3.11+（含 venv、pip）
- ShellCheck 0.11.0
- 本机平台的原生构建工具：macOS 需要 Xcode、Command Line Tools 和 CocoaPods；Linux 需要 Clang、CMake、Ninja、GTK 开发库和 libsecret 开发库；Windows 需要 Visual Studio C++ 桌面工具

不需要预先安装 Flutter，下一步会安装锁定版本。完整工具表见[工具与版本](setup.md#工具与版本)。

## 2. 克隆仓库并创建本机配置

```bash
git clone https://github.com/BUAASubnet/UBAA.git UBAA2
cd UBAA2
(umask 077; cp -n .env.example .env)
```

编辑根目录的 `.env`，把 `UBAA_FLUTTER_HOME` 设为准备存放官方 Flutter SDK 的绝对路径，目录可以还不存在。其他键可以先留空：

- 应用服务地址 `UBAA_APP_SERVICE_URL` 留空时，客户端停用更新提示和统计。
- 签名、部署和学校账号相关的键只在发布或真实验证时使用。

`.env` 只保存在本机，不要提交。

## 3. 安装锁定工具和依赖

```bash
just setup
just doctor
```

- `just setup` 克隆锁定的 Flutter，安装 Rust 工具链、FRB codegen 等工具，并建立冻结参考、Python 质量环境、Cargo 和 Dart 依赖。已经一致的项目会跳过；已有 SDK 不是锁定版本时会停止，不会改写。
- `just doctor` 只读核对本机工具与锁定版本，必需项不符时退出 1。

然后确认本机平台的原生工具链：

```bash
just flutter doctor -v
```

所有 Dart/Flutter 命令都通过 `just dart`、`just flutter` 调用，不直接使用 PATH 中的 Flutter，原因见 [AGENTS 项目工具链入口](../../AGENTS.md#项目工具链入口)。

## 4. 构建并运行客户端

先确认本机平台可以完成一次 Debug 构建：

```bash
just flutter-build platform=host mode=debug
```

`host` 会按当前系统选择 macOS、Linux 或 Windows。构建过程会通过 Cargokit 编译 Rust Core，第一次耗时较长。其他目标（`android-apk`、`ios-simulator` 等）见[构建与发布命令](commands.md#构建与发布命令)。

构建通过后，在官方宿主目录用项目转发的 Flutter 启动 App。`just flutter` 保留调用目录，参数原样传给 Flutter：

```bash
cd apps/ubaa_flutter
just flutter run -d macos
```

把 `macos` 换成 `linux` 或 `windows` 即可在对应桌面运行。在 App 中登录会使用你自己的学校账号访问学校服务，这属于你本人的使用；自动化的真实账号验证另有授权规则，见[来源对照与真实验证](commands.md#来源对照与真实验证)。

HarmonyOS 使用独立的 OHOS Flutter 和 DevEco 工具链，步骤见 [OHOS 宿主说明](../../apps/ubaa_ohos/README.md)。macOS 上反复重建并测试钥匙串时，可以配置固定的本机开发签名，见[官方宿主说明](../../apps/ubaa_flutter/README.md)。

## 5. 修改代码后运行检查

先运行与改动相关的聚焦测试，例如：

```bash
just flutter-test ubaa_app test/features/grades
cargo test --locked -p ubaa-command --all-targets
```

提交前，用开始工作时的提交作为基线，查看并执行按改动选择的检查：

```bash
just check-plan base=<开始工作时的提交>
just check-changed base=<开始工作时的提交>
```

检查范围和完成条件见[检查选择与完成条件](commands.md#检查选择与完成条件)。

## 下一步

- [架构导读](../architecture/overview.md)：分层职责、一次请求如何流转、从哪里开始读代码。
- [开发约定](conventions.md)：命名、提交、版本和文档规范。
- [测试策略](testing.md)：各层测试的分工。
