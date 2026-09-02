# 开发环境设置

安装 Git、Rustup、`just`、Bash 以及确定性验证器使用的平台 Shell 工具。固定的
`rust-toolchain.toml` 选择 Rust 1.95.0，并启用 rustfmt 与 Clippy。实时验证是非交互式的，
凭据只通过 stdin 使用。

在干净工作树中执行：

```bash
just refs-bootstrap
just refs
just layout-check
cargo metadata --locked --no-deps --format-version 1
just check
```

`just refs-bootstrap` 是唯一允许联网的引用入口：它只在同父目录临时路径完成 clone、固定提交 checkout 和
纯校验，成功后原子移动到目标；任一步失败都会清理该临时目录，且不会覆盖或规范化已有路径。完成首次设置后，
普通验证只运行 `just refs`；它只读校验 remote、HEAD 和干净工作树，缺失或不匹配时失败并提示 bootstrap。
`just check` 校验锁文件、使用锁定依赖解析，且从不读取 `.env.local`。实时测试还需要根据 `.env.example`
创建被忽略的 `.env.local`；绝不提交其中的值。

Linux CI 固定安装 ShellCheck 0.11.0，并在全新 checkout 中先以独立 setup step 运行 `just refs-bootstrap`，
随后所有合同和 release preflight 只运行 `just refs`。macOS 和 Windows 任务使用相同的固定 Rust 工具链，并
运行带锁定依赖的 Clippy、测试、构建、文档和格式化命令，使平台相关的会话替换、revision
锁和 no-follow 打开逻辑得到覆盖；Windows 不需要 Bash Fixture。
