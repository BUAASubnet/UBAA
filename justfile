set dotenv-load
set dotenv-required := false
set dotenv-path := ".env.toolchain"

export PYTHONDONTWRITEBYTECODE := "1"

set shell := ["bash", "-euo", "pipefail", "-c"]

# 项目级 SDK 转发使用位置参数，保留空格、空参数及 Shell 元字符。
[no-cd]
[positional-arguments]
dart *args:
    @python3 "{{justfile_directory()}}/scripts/lib/toolchain.py" dart "$@"

[no-cd]
[positional-arguments]
flutter *args:
    @python3 "{{justfile_directory()}}/scripts/lib/toolchain.py" flutter "$@"

[no-cd]
[positional-arguments]
flutter-ohos *args:
    @python3 "{{justfile_directory()}}/scripts/lib/toolchain.py" flutter-ohos "$@"

default:
    @just --list

# 标注 [env("CARGO_INCREMENTAL", "0")] 的门禁只跑一次，不保留增量缓存；
# 否则每种 feature 组合各积累一份，单日可达数 GiB。日常 Rust 与 Flutter 运行仍保留增量。

# 只读汇总本机工具与锁定版本的差异；不联网、不安装。
doctor:
    python3 scripts/bootstrap/doctor.py

# 显式联网准备本机开发环境；已一致的工具跳过，不改写已有 SDK 或 .env.toolchain。
setup:
    bash ./scripts/bootstrap/setup.sh

refs:
    bash ./scripts/check/references.sh

# 唯一允许联网并创建缺失冻结引用的显式入口。
refs-bootstrap:
    bash ./scripts/bootstrap/references.sh

fmt:
    cargo fmt --all -- --check

[env("CARGO_INCREMENTAL", "0")]
test:
    just core-test-contract
    cargo test --locked --workspace --exclude ubaa-core

# Core 单元/集成只执行一次；默认配置保留编译、文档与关闭态负向合同。
[env("CARGO_INCREMENTAL", "0")]
core-test-contract:
    cargo check --locked -p ubaa-core --no-default-features --all-targets
    cargo test --locked -p ubaa-core --no-default-features --doc
    cargo test --locked -p ubaa-core --features test-contract --all-targets
    bash ./scripts/tests/facade-test-contract.sh

# 日常反馈：可用 base=origin/ubaa2 覆盖本分支已提交改动；默认包含全部本地改动。
[positional-arguments]
[env("CARGO_INCREMENTAL", "0")]
check-changed *args:
    @python3 scripts/lib/recipe.py check-changed "$@"

[positional-arguments]
check-plan *args:
    @python3 scripts/lib/recipe.py check-plan "$@"

[env("CARGO_INCREMENTAL", "0")]
check:
    just shell-check
    just _rust-shell-contracts

# 维护验收和 CI 使用的严格入口；ShellCheck 缺失或版本不是 0.11.0 时立即失败。
[env("CARGO_INCREMENTAL", "0")]
check-strict:
    just shell-check-strict
    just _rust-shell-contracts

# 文档、脚本与工作流使用独立轻检查，不编译 Rust 或原生宿主。
script-check:
    just shell-check-strict
    just _script-contracts

_script-contracts:
    just script-test
    just integration-check
    bash ./scripts/tests/layout.sh
    bash ./scripts/tests/contract-versions.sh
    bash ./scripts/tests/references.sh
    bash ./scripts/tests/flutter-toolchains.sh
    bash ./scripts/tests/maintenance-gates.sh
    just layout-check
    just contract-version-check
    just docs-link-check
    just tool-version-check
    just cargo-lock-check
    bash ./scripts/tests/live-launchers.sh
    git diff --check

_rust-shell-contracts:
    just _script-contracts
    cargo metadata --locked --no-deps --format-version 1 >/dev/null
    cargo fmt --all -- --check
    cargo clippy --locked --workspace --all-targets --all-features -- -D warnings
    just core-test-contract
    cargo test --locked --workspace --exclude ubaa-core
    cargo build --locked --workspace
    cargo doc --locked --workspace --no-deps

check-sensitive:
    bash ./scripts/check/sensitive.sh

# 结构 checker 与当前违例 baseline；合同测试由 just check 独立执行。
layout-check:
    bash ./scripts/check/layout.sh
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/check/directory_names.py

# 纯静态交叉校验 CLI/Bridge 常量、schema、Dart 接受版本和当前文档声明。
contract-version-check:
    bash ./scripts/check/contract-versions.sh

docs-link-check:
    python3 scripts/check/docs_links.py

tool-version-check:
    python3 scripts/check/tool_versions.py

# 与 CLI 二进制合同相同的命令扫描，文档和脚本改动也必须执行。
cargo-lock-check:
    python3 scripts/lib/cargo_locks.py

# 显式联网更新 RustSec advisory 数据库并运行 cargo-deny；不属于纯校验门禁。
dependency-audit:
    bash ./scripts/release/dependency-audit.sh

# 检查仓库候选 Shell，显式排除锁定 Cargokit；路径全程使用 NUL 分隔。
shell-check:
    bash ./scripts/check/shell.sh lenient

# 与 shell-check 扫描范围相同，但要求 ShellCheck 0.11.0 可执行文件存在。
shell-check-strict:
    bash ./scripts/check/shell.sh strict

# 生成不含签名、账号或真实响应的无签名 RC 依赖/源码校验报告。
[positional-arguments]
release-preflight *args:
    @python3 scripts/lib/recipe.py release-preflight "$@"

[positional-arguments]
verify-live *args:
    bash ./scripts/live/verify.sh "$@"

[positional-arguments]
core-live *args:
    bash ./scripts/live/core-live.sh "$@"

# 固定 SDK 下重生成 FRB 绑定并要求零漂移。
[env("CARGO_INCREMENTAL", "0")]
flutter-codegen-check:
    bash ./scripts/check/flutter-codegen.sh

# 固定官方 Flutter SDK 下逐 package 执行依赖、静态分析和测试。
[env("CARGO_INCREMENTAL", "0")]
flutter-check:
    bash ./scripts/check/flutter-workspace.sh

# 显式准备根 Pub workspace 的正式包和测试辅助包锁定依赖，供离线材料收集使用；不运行测试。
flutter-dependencies:
    bash ./scripts/check/flutter-workspace.sh dependencies

# 普通测试快速入口，例如 just flutter-test ubaa_app test/features/grades。
[positional-arguments]
flutter-test *args:
    @python3 scripts/lib/recipe.py flutter-test "$@"

# 默认定位手写源码；历史验收元数据不混入结果。
source-files:
    rg --files apps crates packages scripts -g '!**/cargokit/**' -g '!**/frb_generated.rs' -g '!**/lib/src/rust/**'

# 不访问学校或设备的 Python 行为合同。
script-test:
    bash scripts/tools/python.sh scripts/tests/checks/ohos_materials_test.py
    python3 scripts/tests/native/lock_holder_test.py
    python3 scripts/tests/integration_catalog_test.py
    python3 scripts/tests/checks/native_bindings_test.py
    python3 scripts/tests/checks/ohos_native_library_test.py
    python3 scripts/tests/checks/codegen_gate_test.py
    python3 scripts/tests/checks/docs_links_test.py
    python3 scripts/tests/checks/environment_test.py
    python3 scripts/tests/checks/recipe_args_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/checks/directory_names_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/checks/changed_checks_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/checks/cargo_locks_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/checks/build_cache_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/module_graph_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/checks/toolchain_entry_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/sensitive_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/checks/repo_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/checks/release_preflight_test.py
    bash scripts/tools/python.sh scripts/tests/release_metadata_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/build_record_test.py
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/checks/doctor_test.py
    node --test scripts/tests/checks/ohos_hvigor_test.cjs
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/live/offline_startup/analyze_test.py

# 显式联网准备固定开发依赖；检查入口本身不安装依赖。
quality-tools-bootstrap:
    bash scripts/bootstrap/quality-tools.sh

module-check:
    python3 scripts/check/module_graph.py

# 在当前原生 runner 构建指定平台；例如 platform=macos、android-apk、ios-simulator。
[positional-arguments]
flutter-build *args:
    @python3 scripts/lib/recipe.py flutter-build "$@"

# 只读显示仓库内各类构建缓存占用；不删除任何文件。
cache:
    python3 scripts/build/cache.py show

# 按范围清理可重建缓存，例如 just cache-clean rust-incremental ohos；范围见 just cache。
[positional-arguments]
cache-clean *args:
    @python3 scripts/build/cache.py clean "$@"

# 检查已构建 Flutter 产物结构；macOS 还核验实际签名权限，不执行签名或安装。
[positional-arguments]
flutter-artifact-check *args:
    @python3 scripts/lib/recipe.py flutter-artifact-check "$@"

# 固定 OHOS fork、CLI/API26、native SDK 和 HAP 构建门禁。
[positional-arguments]
[env("CARGO_INCREMENTAL", "0")]
ohos-check *args:
    @python3 scripts/lib/recipe.py ohos-check "$@"

# 登记原生能力、FFI/启动锁和最小宿主 smoke，默认设备由平台回退。
integration-check:
    python3 scripts/check/integration_catalog.py check

integration-list:
    python3 scripts/check/integration_catalog.py list

[positional-arguments]
[env("CARGO_INCREMENTAL", "0")]
integration-test *args:
    @python3 scripts/lib/recipe.py integration-test "$@"
