# Development Commands

The workspace uses Rust 1.95.0 from `rust-toolchain.toml` and `just` recipes for repeatable checks.

```bash
just refs                         # verify or clone fixed ignored references
cargo metadata --locked           # verify the locked workspace graph
just check                        # fmt, Clippy, tests, build, docs, diff check
just check-sensitive              # scan tracked paths and obvious secret shapes
cargo test -p ubaa-cli             # CLI unit, contract, and binary tests
just verify-live mode=direct       # real Direct login; local credentials only
just verify-live mode=webvpn       # real WebVPN login; local credentials only
```

`just verify-live` accepts the exact `mode=direct` and `mode=webvpn` forms shown above. It requires `jq` and `.env.local` with non-empty `UBAA_TEST_USERNAME` and `UBAA_TEST_PASSWORD`; the file is ignored and its values are never printed or passed as command-line arguments. If JSON login reports a captcha, an interactive `/dev/tty` is also required for the automatic human fallback.

CI runs `just refs`, `scripts/check-sensitive.sh`, and `just check`. CI never runs live authentication and therefore never needs `.env.local`.

Common failures:

- A dirty or wrong-head `ubaa_old/` or `examples/buaa-api/` causes `just refs` to stop. Inspect the reference worktree without modifying it.
- `cargo metadata --locked` or build failures indicate a dependency/toolchain problem; do not regenerate the lockfile casually.
- A live `captcha_required_noninteractive` result means the automatic fallback had no controlling terminal. Rerun the same verifier command in a terminal; do not pipe, log, or retain the captcha answer or image.
