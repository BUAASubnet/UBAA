set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

refs:
    ./scripts/ensure-references.sh

fmt:
    cargo fmt --all -- --check

test:
    cargo test --workspace

check:
    cargo fmt --all -- --check
    cargo clippy --workspace --all-targets --all-features -- -D warnings
    cargo test --workspace
    ./scripts/test-verify-live.sh
    cargo build --workspace
    cargo doc --workspace --no-deps
    git diff --check

check-sensitive:
    ./scripts/check-sensitive.sh

verify-live mode:
    ./scripts/verify-live.sh "{{mode}}"
