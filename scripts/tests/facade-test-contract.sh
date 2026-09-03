#!/usr/bin/env bash
# 独立验证测试注入 feature 的开启/关闭编译边界，以及生产宿主默认 feature 构建。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fixtures="$repo_root/crates/ubaa-core/tests/compile"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-facade-contract.XXXXXX")
off_log="$test_root/feature-off.log"
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM

cmp "$fixtures/facade_testing_feature_off/src/main.rs" \
  "$fixtures/facade_testing_feature_on/src/main.rs"

CARGO_TARGET_DIR="$repo_root/target" cargo check --locked --offline \
  --manifest-path "$fixtures/Cargo.toml" \
  -p facade-testing-feature-on

if CARGO_TARGET_DIR="$repo_root/target" CARGO_TERM_COLOR=never cargo check --locked --offline \
  --manifest-path "$fixtures/Cargo.toml" \
  -p facade-testing-feature-off >"$off_log" 2>&1; then
  printf '%s\n' '错误：关闭 test-contract 后仍可访问 facade 测试注入面' >&2
  exit 1
fi

if ! grep -Eq 'could not find `?testing`? in `?facade`?|no `?testing`? in `?facade`?' "$off_log"; then
  printf '%s\n' '错误：feature-off 夹具并非因 facade 测试注入面关闭而失败' >&2
  sed -n '1,120p' "$off_log" >&2
  exit 1
fi

# 不能让 workspace 测试依赖的 feature 合并掩盖生产宿主误用测试构造器。
cargo check --locked -p ubaa-cli --lib --bins
cargo check --locked -p ubaa_flutter_bridge --lib

printf '%s\n' 'facade test-contract compile gate passed'
