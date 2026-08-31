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

verify-live *args:
    ./scripts/verify-live.sh {{args}}

core-live *args:
    ./scripts/core-live.sh {{args}}

# 固定 SDK 下重生成 FRB 绑定并要求零漂移。
flutter-codegen-check:
    ./scripts/flutter-codegen-check.sh

# 固定官方 Flutter SDK 下逐 package 执行依赖、静态分析和测试。
flutter-check:
    ./scripts/flutter-check.sh

# 在当前原生 runner 构建指定平台；例如 platform=macos、android-apk、ios-simulator。
flutter-build platform="host" mode="debug":
    ./scripts/flutter-build.sh "{{platform}}" "{{mode}}"

# 固定 OHOS fork、CLI/API26、native SDK 和 HAP 构建门禁。
ohos-check mode="release":
    ./scripts/ohos-check.sh "{{mode}}"
