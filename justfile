set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

refs:
    bash ./scripts/check/references.sh

# 唯一允许联网并创建缺失冻结引用的显式入口。
refs-bootstrap:
    bash ./scripts/bootstrap/references.sh

fmt:
    cargo fmt --all -- --check

test:
    just core-test-contract
    cargo test --locked --workspace --exclude ubaa-core

# 分别验证 Core 默认单元/文档合同、显式测试注入合同和关闭态编译失败。
core-test-contract:
    cargo test --locked -p ubaa-core --no-default-features --lib --tests
    cargo test --locked -p ubaa-core --no-default-features --doc
    cargo test --locked -p ubaa-core --features test-contract --all-targets
    bash ./scripts/tests/facade-test-contract.sh

check:
    just shell-check
    bash ./scripts/tests/layout.sh
    bash ./scripts/tests/contract-versions.sh
    bash ./scripts/tests/references.sh
    just layout-check
    just contract-version-check
    cargo metadata --locked --no-deps --format-version 1 >/dev/null
    cargo fmt --all -- --check
    cargo clippy --locked --workspace --all-targets --all-features -- -D warnings
    just core-test-contract
    cargo test --locked --workspace --exclude ubaa-core
    bash ./scripts/tests/live-launchers.sh
    cargo build --locked --workspace
    cargo doc --locked --workspace --no-deps
    git diff --check

check-sensitive:
    bash ./scripts/check/sensitive.sh

# 结构 checker 与当前违例 baseline；合同测试由 just check 独立执行。
layout-check:
    bash ./scripts/check/layout.sh

# 纯静态交叉校验 CLI/Bridge 常量、schema、Dart 接受版本和当前文档声明。
contract-version-check:
    bash ./scripts/check/contract-versions.sh

# 检查仓库候选 Shell，显式排除锁定 Cargokit；路径全程使用 NUL 分隔。
shell-check:
    git ls-files --cached --others --exclude-standard -z -- '*.sh' | while IFS= read -r -d '' script; do [[ -f "$script" ]] || continue; case "$script" in packages/ubaa_bindings/cargokit/*) continue ;; esac; bash -n "$script"; done
    if command -v shellcheck >/dev/null 2>&1; then git ls-files --cached --others --exclude-standard -z -- '*.sh' | while IFS= read -r -d '' script; do [[ -f "$script" ]] || continue; case "$script" in packages/ubaa_bindings/cargokit/*) continue ;; esac; shellcheck "$script"; done; else printf '%s\n' 'SKIP: ShellCheck 未执行（当前环境未安装）'; fi

# 生成不含签名、账号或真实响应的无签名 RC 依赖/源码校验报告。
release-preflight report_dir="":
    bash ./scripts/release/preflight.sh "{{report_dir}}"

verify-live *args:
    bash ./scripts/live/verify.sh {{args}}

core-live *args:
    bash ./scripts/live/core-live.sh {{args}}

# 固定 SDK 下重生成 FRB 绑定并要求零漂移。
flutter-codegen-check:
    bash ./scripts/check/flutter-codegen.sh

# 固定官方 Flutter SDK 下逐 package 执行依赖、静态分析和测试。
flutter-check:
    bash ./scripts/check/flutter-workspace.sh

# 在当前原生 runner 构建指定平台；例如 platform=macos、android-apk、ios-simulator。
flutter-build platform="host" mode="debug":
    bash ./scripts/build/flutter.sh "{{platform}}" "{{mode}}"

# 检查已构建 Flutter 产物的最小可加载结构，不执行签名或安装。
flutter-artifact-check platform artifact:
    bash ./scripts/release/verify-flutter-artifact.sh "{{platform}}" "{{artifact}}"

# 固定 OHOS fork、CLI/API26、native SDK 和 HAP 构建门禁。
ohos-check mode="release":
    bash ./scripts/build/ohos.sh "{{mode}}"
