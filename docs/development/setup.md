# Development Setup

Install Git, Rustup, `just`, Bash, `jq`, and the platform shell utilities used by the deterministic verifier. The pinned `rust-toolchain.toml` selects Rust 1.95.0 with rustfmt and Clippy. Live verification is non-interactive and uses credentials only through stdin.

From a clean checkout:

```bash
just refs
cargo metadata --locked --no-deps --format-version 1
just check
```

`just refs` creates missing ignored references at fixed commits and refuses to overwrite or normalize existing directories. `just check` validates the lockfile, uses locked dependency resolution, and never reads `.env.local`. Live tests additionally need an ignored `.env.local` created from `.env.example`; never commit its values.

The Linux CI job runs the complete `just` gates. macOS and Windows jobs use the same pinned Rust toolchain and locked Rust-only Clippy, test, build, and documentation commands plus formatting, so platform-specific session replacement, revision locking, and no-follow opens remain exercised without requiring Bash fixtures on Windows.
