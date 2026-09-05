# 开发命令

工作区使用 `rust-toolchain.toml` 锁定 Rust 1.95.0；官方 Flutter、OHOS fork、FRB 与平台工具版本见
[Flutter 平台矩阵](../architecture/flutter-platforms.md)。当前 recipe 由根 `justfile` 提供。

## 基线与确定性门禁

```bash
just refs-bootstrap                                         # 仅首次缺失时联网建立固定引用；验证阶段不调用
just refs                                                   # 纯只读校验 remote、HEAD 与干净工作树
just layout-check                                           # 1000 行/16 文件结构棘轮与当前 baseline
just contract-version-check                                 # CLI/Bridge 常量、schema、Dart 与当前文档纯静态一致性
cargo metadata --locked --no-deps --format-version 1        # 校验 Cargo.lock 与 workspace 元数据
just check-sensitive                                        # 扫描 tracked 和非 ignored 候选文件中的敏感路径/模式
just shell-check                                             # 全部 Shell 执行 bash -n；可用时再执行 ShellCheck
just check                                                  # Rust/Cargo/CLI/Shell 合同、构建、文档与 git diff；不含 Flutter
CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check
just flutter-check                                          # 七个 package/app 执行 pub get、format、analyze、test
git diff --check
```

`just check` 内部也运行 layout、contract-version、refs、live 四类 Shell 合同以及 layout/公开版本 checker；
独立列出两个静态 checker 是为了让结构或版本漂移尽早失败。Rust、Flutter/codegen 仍是独立证据，任何一个通过都不能推导另一个通过；结构治理阶段
还要运行实施计划指定的 focused test。

常用 focused 命令：

```bash
cargo test --locked -p ubaa-cli --all-targets
cargo test --locked -p ubaa-core --all-targets
cargo test --locked -p ubaa-test-support --all-targets
just core-test-contract
```

`cargo test --locked -p ubaa-core` 的默认配置不开放 facade 测试注入。`just core-test-contract` 分别运行默认 Core
单元/集成与 Rustdoc、启用 `test-contract` 的全目标测试，以及测试注入关闭时的预期编译失败合同；修改
Core 可见性、测试构造器或宿主依赖边界时使用该完整入口。

## Flutter 与无签名平台构建

```bash
just flutter-build platform=macos mode=debug
just flutter-build platform=linux mode=debug
just flutter-build platform=windows mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug

just flutter-artifact-check macos /绝对路径/ubaa_flutter.app
just flutter-artifact-check android-apk /绝对路径/app-debug.apk

UBAA_DEVECO_HOME=/绝对路径/DevEco或命令行工具 \
  UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
```

这些命令只证明相应无签名构建或产物结构。`UBAA_OHOS_NO_CODESIGN=1` 只允许 Debug；生成的 HAP 不得用于发布
或实体设备验收。签名、安装、设备和安全存储证据必须单独记录。

## 发布前置

```bash
just release-preflight /绝对路径/ubaa-release-report
```

该命令要求工作树干净，生成 Cargo 元数据、CycloneDX 风格 SBOM、Dart/Flutter 锁文件与许可证清单、源码摘要
和安全状态；不签名、不上传、不访问真实账号。完整流程见[Flutter 发布 Runbook](../runbooks/flutter-release.md)。

## 真实只读验证

```bash
just verify-live mode=direct
just verify-live mode=webvpn
just verify-live feature=auth route=direct
just verify-live feature=cgyy route=webvpn
```

真实验证只接受 Direct/WebVPN，拒绝 `auto`。它从被忽略的 `.env.local` 读取非空测试凭据，经 stdin 一次注入
Core-live；每条路线使用一个固定 `RouteClient` 串行执行。只保留路线、操作、状态、错误码、耗时和安全计数，
不得复制 stderr、URL 查询、上游正文或个人数据到文档。

排查 Cgyy 时只打开窄范围日志：

```bash
RUST_LOG='ubaa::cgyy=debug' just verify-live feature=cgyy route=direct
```

禁止全局 `trace`。日志不得含凭据、Cookie、Token、签名、验证码、表单值、查询值或原始响应。`auto` 只运行
Core/Mock 确定性路由测试。

## 常见失败边界

- `just refs` 发现缺失、错误 remote/HEAD 或脏树时立即停止；缺失时显式运行 `just refs-bootstrap`，其它错误不要
  修改、清理或重置冻结目录。
- 锁定元数据/构建失败时不要随意重生成锁文件或放宽 lint。
- FRB codegen 必须精确为 2.13.0；生成后任何未解释 diff 都阻止提交。
- `upstream_changed` 只说明当前响应不满足已证明合同；记录安全状态并按条件重跑，不猜测新字段或绕过挑战。
- 真实写入没有逐操作授权时保持 BLOCKED，不用 CLI/Flutter 的确认参数绕过授权边界。
