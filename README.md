# UBAA 2

UBAA 2 是面向北京航空航天大学服务的 Rust Core 与宿主应用。本阶段提供自动直连/WebVPN 路由、双路线认证、用户中心以及六类校园只读功能。

## 当前状态

认证、Core 管理的路由策略、原子双会话协调器、CLI schema v2 及六类只读实现均有确定性测试覆盖。修正后的 2026-08-26 提交已通过 Direct/WebVPN 认证，以及 auto、Direct 和最新 WebVPN 六功能真实聚合验证。严格的 WebVPN 希冀验证曾记录上游列表快照短暂漂移，立即完整重跑后通过。安全证据和重跑条件记录于 `docs/migration/status.md`；fixture、Mock 或验证脚本通过不等于真实协议通过。

## 使用准备

```bash
just refs
cargo build --locked --workspace
cargo install --locked --path apps/ubaa-cli
```

开发期间可用 `cargo run --locked -p ubaa-cli -- --help` 运行 CLI。

```bash
# 交互输入密码；普通登录会同时准备两条内部路线。
cargo run --locked -p ubaa-cli -- auth login --username YOUR_USERNAME

# 复用并验证已持久化会话。
cargo run --locked -p ubaa-cli -- auth status
cargo run --locked -p ubaa-cli -- user show
cargo run --locked -p ubaa-cli -- auth logout

# 自动化流程从标准输入读取一行密码，并输出一个 JSON 信封。
printf '%s\n' "$UBAA_TEST_PASSWORD" |
  cargo run --locked -p ubaa-cli -- --json auth login \
    --username "$UBAA_TEST_USERNAME" --password-stdin
```

默认会话位置是操作系统的用户配置目录。隔离测试可使用 `--config-dir <path>`。输出合同见 `docs/contracts/auth-and-user.md` 和 `docs/contracts/cli-json.schema.json`。

`config.toml` 为每项功能配置 `auto|direct|webvpn` 策略。使用 `auto` 时，Core facade 会在 500 毫秒总预算内探测 `gw.buaa.edu.cn:80` 的 TCP 可达性，并在进程内缓存结果；校园网解析为 Direct，校外网解析为 WebVPN。普通用户无需选择内部连接模式；测试和真实验证器使用隐藏的诊断命令及路线覆盖参数。

每次 JSON 成功或失败都只输出一个 schema-v2 信封。`config.toml` 格式版本 1 和 `session.json` 格式版本 2 是相互独立的磁盘合同，不是 CLI schema 版本。

只读命令示例：

```bash
cargo run --locked -p ubaa-cli -- schedule terms
cargo run --locked -p ubaa-cli -- grades list --term 2025-2026-1
cargo run --locked -p ubaa-cli -- classroom search --campus 1 --date 2026-09-01
cargo run --locked -p ubaa-cli -- judge assignments
```

## 验证

```bash
just refs
just check-sensitive
just check
just verify-live feature=auth route=direct
just verify-live feature=auth route=webvpn

# Judge/all 路线比较摘要必须使用；不要持久化该值。
export UBAA_VERIFY_DIGEST_SALT="$(openssl rand -hex 16)"
just verify-live feature=all route=auto
unset UBAA_VERIFY_DIGEST_SALT
```

真实验证需要在已忽略的 `.env.local` 中配置 `UBAA_TEST_USERNAME` 和 `UBAA_TEST_PASSWORD`；验证 `feature=judge|all` 时还需提供 `UBAA_VERIFY_DIGEST_SALT`。CLI 从不接受命令行明文密码，验证器只输出安全的路线、耗时、数量、存在性和加盐摘要。运行完整矩阵前请先阅读两份真实验证手册。

## 范围

本阶段覆盖认证、会话管理、用户中心，以及课表、考试、成绩、空教室、SPOC 和希冀只读访问。人类输出和 JSON 输出都会遮盖手机号及证件号码。Flutter、MCP、服务器中转和所有写操作仍不在范围内。
