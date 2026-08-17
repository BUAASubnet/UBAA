# Development Setup

Install Git, Rustup, `just`, Bash, `jq`, and the platform `script` utility (BSD `script` on macOS or util-linux on Linux). The pinned `rust-toolchain.toml` selects Rust 1.95.0 with rustfmt and Clippy. Live captcha verification also requires an interactive controlling terminal with `/dev/tty`.

From a clean checkout:

```bash
just refs
cargo metadata --locked
just check
```

`just refs` creates missing ignored references at fixed commits and refuses to overwrite or normalize existing directories. `just check` uses `script` only for a synthetic captcha-fallback shell test and never reads `.env.local`. Live tests additionally need an ignored `.env.local` created from `.env.example`; never commit its values.
