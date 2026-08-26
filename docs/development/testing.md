# Testing Strategy

Tests are deliberately separated by evidence level:

| Layer | Location | What it proves |
|---|---|---|
| Unit/contract | `crates/ubaa-core/tests/` | DTOs, errors, URL conversion, cookies, no-follow/revisioned persistence, and stable JSON shape |
| Sanitized fixture | `fixtures/`, `crates/ubaa-test-support/` | Parser behavior and request scripts using synthetic values only |
| Mock integration | `crates/ubaa-test-support/tests/auth.rs`, `readonly.rs` | Authentication sequencing plus exact read-only request URLs, forms, headers, pagination and Direct/WebVPN route locking without a network |
| CLI contract | `apps/ubaa-cli/tests/cli_contract.rs` | Human/JSON rendering, redaction, unsupported-interactive-step handling, serialized-envelope schema validation, and stable exits |
| CLI binary | `apps/ubaa-cli/tests/binary_e2e.rs` | Help/JSON-argument surface, facade-only host access, locked Cargo gates, missing sessions, and saved-session logout through the real host |
| Shell contract | `scripts/test-verify-live.sh` | Non-interactive credential stdin and inherited-xtrace suppression, plus rejection of non-v2 output, unsafe errors, open metadata, wrong aggregate route order, invalid integer ranges, cross-request term or SPOC identity/status drift, missing SPOC global-query proof, invalid/duplicate/causally impossible Judge semantics, route contradictions, sensitive/raw aliases, obvious complete HTML while preserving literal tag text, Judge data in process arguments, and digest salt/stability violations |
| Real integration | `scripts/verify-live.sh` | Actual Direct/WebVPN aggregate SSO and User Center status plus semantic checks for all six read-only features on one resolved route per feature |

Run deterministic tests with `cargo test --locked --workspace --all-targets` or `just check`. `just check` first validates `Cargo.lock` through no-dependency metadata and uses `--locked` for every dependency-resolving Cargo command. Linux CI owns the pinned-reference, sensitive-data, and complete shell-aware gates. macOS and Windows CI independently run locked Rust Clippy, tests, builds, and docs plus formatting. The real verifier is never part of CI: run `feature=auth` on Direct/WebVPN, `feature=all route=auto`, and every feature on both explicit routes only when `.env.local` is present. `feature=judge|all` also requires one ephemeral `UBAA_VERIFY_DIGEST_SALT` shared across the compared runs. The corrected 2026-08-26 matrix and transient WebVPN Judge snapshot failures are recorded in `docs/migration/status.md`. A fixture or Mock pass does not establish live protocol success.

Every new behavior starts with a failing focused test. Keep fixtures synthetic, assert that sensitive values are absent from output, and add a migration or contract note when an upstream fact changes.
