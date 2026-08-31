# 开发命令

工作区使用 `rust-toolchain.toml` 中的 Rust 1.95.0，并通过 `just` 固化可重复检查。

```bash
just refs                                                   # verify or clone fixed ignored references
cargo metadata --locked --no-deps --format-version 1        # verify Cargo.lock without fetching target-only crates
just check                                                  # locked metadata, fmt, Clippy, tests, build, docs, diff
just check-sensitive                                        # scan tracked paths and obvious secret shapes
cargo test --locked -p ubaa-cli --all-targets               # CLI unit, contract, and binary tests
just verify-live mode=direct                                 # Direct 真实只读矩阵
just verify-live mode=webvpn                                 # WebVPN 真实只读矩阵
just verify-live feature=auth route=direct                   # 单项认证只读证据
just verify-live feature=all route=webvpn                    # 单个 Core client 的全量只读证据
just core-live route=direct feature=cgyy                      # 已有凭据 stdin 的 Core-live 启动器
```

排查 Cgyy 时只打开窄范围的 stderr 诊断日志；JSON/摘要仍写 stdout，便于单独解析：

```bash
RUST_LOG='ubaa::cgyy=debug' UBAA_SHOW_LOGS=yes \
  just verify-live feature=cgyy route=direct
```

`UBAA_SHOW_LOGS=yes` 仅控制验证器是否透传子进程 stderr，默认值为关闭。`RUST_LOG=ubaa::cgyy=debug` 将 Cgyy 的 `info`/`debug`/`warn` 事件发送到 stderr；事件只含操作名、方法和路径、脱敏参数键/长度、HTTP 状态、最终主机和路径、响应长度/哈希、耗时及稳定错误码。认证材料、Cookie、令牌、签名、验证码、表单值、查询字符串和原始响应正文禁止进入日志。不要使用全局 `trace` 过滤器，也不要将用户名、密码或 `UBAA_VERIFY_DIGEST_SALT` 放在命令参数中。

实时排查顺序建议为 `feature=cgyy route=direct` 和 `feature=cgyy route=webvpn`；`auto` 只运行确定性 Mock 路由测试。每次只读运行都应保留路线、操作、状态、错误码和安全计数，失败时记录到 `docs/migration/status.md`，而不是复制 stderr 或上游响应。需要复现日期时可临时设置 `UBAA_VERIFY_DATE=YYYY-MM-DD`；该值不包含凭据，测试后应取消设置。

`just verify-live` 接受 `mode=direct|webvpn` 和 `feature=<name> route=direct|webvpn` 形式，拒绝真实 `auto`。它安全读取被忽略的 `.env.local` 中非空 `UBAA_TEST_USERNAME`、`UBAA_TEST_PASSWORD`（兼容无前缀名称），构建 `core-live` 后一次性经 stdin 注入；凭据不会出现在参数、日志或文件中。Core-live 在一个固定路线 `RouteClient` 内顺序执行只读 facade，认证交互页面直接报告 `upstream_changed`，不保存验证码材料。

CI runs `just refs`, `scripts/check-sensitive.sh`, and `just check`. CI never runs live authentication and therefore never needs `.env.local`.

常见失败：

- `ubaa_old/` 或 `examples/buaa-api/` 脏或不在固定提交会使 `just refs` 停止；只读检查引用目录，不要修改。
- 锁定元数据或构建失败表示依赖/工具链问题，不要随意重生成锁文件。
- 真实 `upstream_changed` 且安全消息指出交互验证时，记录路线、操作、状态和重跑条件；不要添加验证码绕过或保存上游验证材料。
