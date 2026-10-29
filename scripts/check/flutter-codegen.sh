#!/usr/bin/env bash
# 用锁定 FRB 重新生成绑定，并拒绝任何生成漂移。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
flutter_root=${UBAA_FLUTTER_HOME:?请设置 UBAA_FLUTTER_HOME 为锁定 Flutter SDK 的绝对路径}
codegen=${UBAA_FRB_CODEGEN:-$(command -v flutter_rust_bridge_codegen || true)}

"$repo_root/scripts/check/flutter-toolchains.sh" official
if [[ -z "$codegen" || ! -x "$codegen" ]]; then
  printf 'error: 找不到 flutter_rust_bridge_codegen 2.13.0\n' >&2
  exit 1
fi
if [[ $("$codegen" --version) != 'flutter_rust_bridge_codegen 2.13.0' ]]; then
  printf 'error: FRB codegen 必须精确为 2.13.0\n' >&2
  exit 1
fi

(
  cd "$repo_root/packages/ubaa_bindings"
  PATH="$flutter_root/bin:$PATH" "$codegen" generate --config-file flutter_rust_bridge.yaml
)
cargo fmt --manifest-path "$repo_root/Cargo.toml" --all

git -C "$repo_root" diff --exit-code -- \
  crates/ubaa_flutter_bridge/src/frb_generated.rs \
  packages/ubaa_bindings/lib/src/rust
printf 'FRB 生成零漂移\n'
