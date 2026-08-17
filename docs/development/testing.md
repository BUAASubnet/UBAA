# Testing Strategy

Tests are deliberately separated by evidence level:

| Layer | Location | What it proves |
|---|---|---|
| Unit/contract | `crates/ubaa-core/tests/` | DTOs, errors, URL conversion, cookies, persistence, and stable JSON shape |
| Sanitized fixture | `fixtures/`, `crates/ubaa-test-support/` | Parser behavior and request scripts using synthetic values only |
| Mock integration | `crates/ubaa-test-support/tests/auth.rs` | Direct/WebVPN state-machine sequencing, captcha, risk continuation, status invalidation, and logout without a network |
| CLI contract | `apps/ubaa-cli/tests/cli_contract.rs` | Human/JSON rendering, redaction, captcha exit 4, serialized-envelope schema validation, and stable exits |
| CLI binary | `apps/ubaa-cli/tests/binary_e2e.rs` | Help surface, missing-session behavior, and saved-session logout cleanup through the real process host |
| Shell contract | `scripts/test-verify-live.sh` | Synthetic JSON-captcha to human fallback, non-interactive failure, and suppression of human profile output |
| Real integration | `scripts/verify-live.sh` | Actual Direct and WebVPN SSO, User Center parsing, and persisted-session `auth status` |

Run deterministic tests with `cargo test --workspace` or `just check`. Linux CI owns the pinned-reference, sensitive-data, and complete shell-aware gates. macOS and Windows CI independently run Rust formatting, Clippy, tests, builds, and docs. The real verifier is never part of CI: run each mode explicitly with `just verify-live mode=direct` and `just verify-live mode=webvpn` only when `.env.local` is present. A fixture or mock pass does not establish live protocol success.

Every new behavior starts with a failing focused test. Keep fixtures synthetic, assert that sensitive values are absent from output, and add a migration or contract note when an upstream fact changes.
