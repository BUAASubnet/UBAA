# Testing Strategy

Tests are deliberately separated by evidence level:

| Layer | Location | What it proves |
|---|---|---|
| Unit/contract | `crates/ubaa-core/tests/` | DTOs, errors, URL conversion, cookies, no-follow/revisioned persistence, and stable JSON shape |
| Sanitized fixture | `fixtures/`, `crates/ubaa-test-support/` | Parser behavior and request scripts using synthetic values only |
| Mock integration | `crates/ubaa-test-support/tests/auth.rs`, `readonly.rs` | Authentication sequencing plus exact read-only request URLs, forms, headers, pagination and Direct/WebVPN route locking without a network |
| CLI contract | `apps/ubaa-cli/tests/cli_contract.rs` | Human/JSON rendering, redaction, unsupported-interactive-step handling, serialized-envelope schema validation, and stable exits |
| CLI binary | `apps/ubaa-cli/tests/binary_e2e.rs` | Help/JSON-argument surface, facade-only host access, locked Cargo gates, missing sessions, and saved-session logout through the real host |
| Shell contract | `scripts/test-verify-live.sh` | 验证凭据只经 stdin、不会进入参数或 xtrace，拒绝 `auto`/未知功能，并确保 verify-live 只调用一次 Core-live |
| Core-live 入口 | `apps/ubaa-cli/src/bin/core-live.rs` | 单个固定路线客户端的一次登录、逐操作只读调用、依赖状态和安全摘要；源码不包含任何写操作调用 |
| Real integration | `scripts/verify-live.sh` + `scripts/core-live.sh` | Direct/WebVPN 各自一次 Core-live 批次；每项输出 `PASS/FAIL/BLOCKED/NOT_APPLICABLE`，不在 Shell 重复网络或 DTO 解析 |

运行确定性测试使用 `cargo test --locked --workspace --all-targets` 或 `just check`。`just check` 先用无依赖元数据校验 `Cargo.lock`，所有依赖解析命令都带 `--locked`。CI 不执行真实认证；仅在安全凭据存在时，人工分别运行 Direct 与 WebVPN 的 `feature=all`，并把逐操作结果写入 `docs/migration/status.md`。`auto` 只有 Mock/确定性路由证据，Fixture 或 Mock 通过不能建立真实协议成功。

Every new behavior starts with a failing focused test. Keep fixtures synthetic, assert that sensitive values are absent from output, and add a migration or contract note when an upstream fact changes.
