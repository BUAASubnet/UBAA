# Testing Strategy

Tests are deliberately separated by evidence level:

| Layer | Location | What it proves |
|---|---|---|
| Unit/contract | `crates/ubaa-core/tests/` | DTOs, errors, URL conversion, cookies, no-follow/revisioned persistence, and stable JSON shape |
| Sanitized fixture | `fixtures/`, `crates/ubaa-test-support/` | Parser behavior and request scripts using synthetic values only |
| Mock integration | `crates/ubaa-test-support/tests/auth.rs` | Direct/WebVPN sequencing, captcha/risk continuation, invalidation, revision conflicts, and logout without a network |
| CLI contract | `apps/ubaa-cli/tests/cli_contract.rs` | Human/JSON rendering, redaction, captcha exit 4, serialized-envelope schema validation, and stable exits |
| CLI binary | `apps/ubaa-cli/tests/binary_e2e.rs` | Help/JSON-argument surface, facade-only host access, locked Cargo gates, missing sessions, and saved-session logout through the real host |
| Shell contract | `scripts/test-verify-live.sh` | Captcha fallback, no-captcha completion, non-interactive failure, terminal echo/restore, signal child cleanup, and profile suppression |
| Real integration | `scripts/verify-live.sh` | Actual Direct and WebVPN SSO, User Center parsing, and persisted-session `auth status` |

Run deterministic tests with `cargo test --locked --workspace --all-targets` or `just check`. `just check` first validates `Cargo.lock` through no-dependency metadata and uses `--locked` for every dependency-resolving Cargo command. Linux CI owns the pinned-reference, sensitive-data, and complete shell-aware gates. macOS and Windows CI independently run locked Rust Clippy, tests, builds, and docs plus formatting. The real verifier is never part of CI: run each mode explicitly with `just verify-live mode=direct` and `just verify-live mode=webvpn` only when `.env.local` is present. A fixture or mock pass does not establish live protocol success.

Every new behavior starts with a failing focused test. Keep fixtures synthetic, assert that sensitive values are absent from output, and add a migration or contract note when an upstream fact changes.
