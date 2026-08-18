# Development Commands

The workspace uses Rust 1.95.0 from `rust-toolchain.toml` and `just` recipes for repeatable checks.

```bash
just refs                                                   # verify or clone fixed ignored references
cargo metadata --locked --no-deps --format-version 1        # verify Cargo.lock without fetching target-only crates
just check                                                  # locked metadata, fmt, Clippy, tests, build, docs, diff
just check-sensitive                                        # scan tracked paths and obvious secret shapes
cargo test --locked -p ubaa-cli --all-targets               # CLI unit, contract, and binary tests
just verify-live mode=direct                                 # real Direct login; local credentials only
just verify-live mode=webvpn                                 # real WebVPN login; local credentials only
just verify-live feature=auth route=direct                   # route-matrix authentication evidence
just verify-live feature=all route=auto                       # all six read-only features via auto
```

`just verify-live` accepts the phase-5 `mode=direct|webvpn` forms and the phase-11 `feature=<name> route=<auto|direct|webvpn>` forms. It requires `jq` and `.env.local` with non-empty `UBAA_TEST_USERNAME` and `UBAA_TEST_PASSWORD`; the file is ignored and its values are never printed or passed as command-line arguments. If login reports a captcha, an interactive `/dev/tty` is also required for the automatic human fallback.

CI runs `just refs`, `scripts/check-sensitive.sh`, and `just check`. CI never runs live authentication and therefore never needs `.env.local`.

Common failures:

- A dirty or wrong-head `ubaa_old/` or `examples/buaa-api/` causes `just refs` to stop. Inspect the reference worktree without modifying it.
- Locked metadata or build failures indicate a dependency/toolchain problem; do not regenerate the lockfile casually.
- A live `captcha_required_noninteractive` result means the automatic fallback had no controlling terminal. Rerun the same verifier command in a terminal; do not pipe, log, or retain the captcha answer or image.
