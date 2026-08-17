set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

refs:
    ./scripts/ensure-references.sh

fmt:
    cargo fmt --all -- --check

test:
    cargo test --locked --workspace

check:
    cargo metadata --locked --no-deps --format-version 1 >/dev/null
    cargo fmt --all -- --check
    cargo clippy --locked --workspace --all-targets --all-features -- -D warnings
    cargo test --locked --workspace
    ./scripts/test-verify-live.sh
    cargo build --locked --workspace
    cargo doc --locked --workspace --no-deps
    git diff --check

check-sensitive:
    ./scripts/check-sensitive.sh

verify-live mode:
    ./scripts/verify-live.sh "{{mode}}"
