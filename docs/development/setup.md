# Development Setup

Install Git, Rustup, and `just`. The pinned `rust-toolchain.toml` selects Rust 1.95.0 with rustfmt and Clippy.

From a clean checkout:

```bash
just refs
cargo metadata --locked
just check
```

`just refs` creates missing ignored references at fixed commits and refuses to overwrite or normalize existing directories. Live tests additionally need an ignored `.env.local` created from `.env.example`; never commit its values.

