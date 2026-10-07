# 开发环境设置

安装 Git、Rustup、`just`、Bash 以及确定性验证器使用的平台 Shell 工具。macOS 产物权限检查还固定使用
系统自带的 `/usr/bin/codesign` 与 `/usr/libexec/PlistBuddy` 只读提取、解析实际签名 entitlements。固定的
`rust-toolchain.toml` 选择 Rust 1.95.0，并启用 rustfmt 与 Clippy。实时验证是非交互式的，
凭据只通过 stdin 使用。

在干净工作树中执行：

```bash
just refs-bootstrap
just quality-tools-bootstrap
cargo fetch --locked
just flutter-dependencies
just refs
just layout-check
cargo metadata --locked --no-deps --format-version 1
just check
```

`just refs-bootstrap` 是唯一允许联网的引用入口：它只在同父目录临时路径完成 clone、固定提交 checkout 和
纯校验，成功后原子移动到目标；任一步失败都会清理该临时目录，且不会覆盖或规范化已有路径。完成首次设置后，
普通验证只运行 `just refs`；它只读校验 remote、HEAD 和干净工作树，缺失或不匹配时失败并提示 bootstrap。
`just check` 校验锁文件、使用锁定依赖解析，且从不读取 `.env.local`；未安装 ShellCheck 时会明确报告 SKIP。
安装 ShellCheck 0.11.0 后，维护验收应改用 `just check-strict`，该入口在 ShellCheck 缺失、版本不符或检查失败时非零退出。实时测试还需要根据 `.env.example`
创建被忽略的 `.env.local`；绝不提交其中的值。

Linux CI 固定安装 ShellCheck 0.11.0，并通过 `just check-strict` 强制执行；它在全新 checkout 中先以独立 setup step 运行 `just refs-bootstrap`，
随后所有合同和 release preflight 只运行 `just refs`。macOS 和 Windows 任务使用相同的固定 Rust 工具链，并
运行带锁定依赖的 Clippy、测试、构建、文档和格式化命令，使平台相关的会话替换、revision
锁和 no-follow 打开逻辑得到覆盖；Windows 不需要 Bash Fixture。

质量工具环境使用固定版本及哈希的 Python 开发依赖，用于 JSON Schema 与锁文件解析。首次准备或依赖锁变更后显式运行 `just quality-tools-bootstrap`；日常 checker/preflight 不联网安装，缺少环境时明确失败。它不是产品运行时依赖，不改变 Flutter/Rust 包版本。

离线发布材料需要完整依赖源：首次显式执行 `cargo fetch --locked` 预取所有目标，`just flutter-dependencies` 按完整七包列表准备锁定 Dart 依赖而不跑测试。OHOS fork 原生材料仍须对应工具链/产物核对；缺失项如实列入发布材料缺口。
