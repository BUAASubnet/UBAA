# 开发环境设置

安装 Git、Rustup、`just`、Bash 以及确定性验证器使用的平台 Shell 工具。固定的
`rust-toolchain.toml` 选择 Rust 1.95.0，并启用 rustfmt 与 Clippy。实时验证是非交互式的，
凭据只通过 stdin 使用。

在干净工作树中执行：

```bash
just refs
cargo metadata --locked --no-deps --format-version 1
just check
```

`just refs` 会按固定提交创建缺失的忽略引用目录，并拒绝覆盖或规范化已有目录。`just check`
校验锁文件、使用锁定依赖解析，且从不读取 `.env.local`。实时测试还需要根据 `.env.example`
创建被忽略的 `.env.local`；绝不提交其中的值。

Linux CI 任务运行完整 `just` 门禁。macOS 和 Windows 任务使用相同的固定 Rust 工具链，并
运行带锁定依赖的 Clippy、测试、构建、文档和格式化命令，使平台相关的会话替换、revision
锁和 no-follow 打开逻辑得到覆盖；Windows 不需要 Bash Fixture。
