#!/usr/bin/env bash
# 用锁定 FRB 重新生成绑定，并拒绝任何生成漂移。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
flutter_root=${UBAA_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-3.41.9}
codegen=${UBAA_FRB_CODEGEN:-$(command -v flutter_rust_bridge_codegen || true)}

"$repo_root/scripts/check-flutter-toolchains.sh" official
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
  crates/ubaa-flutter-bridge/src/frb_generated.rs \
  packages/ubaa_bindings/lib/src/rust
printf 'FRB 生成零漂移\n'
