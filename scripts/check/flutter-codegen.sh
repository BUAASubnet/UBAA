#!/usr/bin/env bash
# 用锁定 FRB 重新生成绑定，并拒绝任何生成漂移。
set -euo pipefail

# shellcheck source=../lib/versions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/versions.sh"

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
  printf 'error: 找不到 flutter_rust_bridge_codegen %s\n' "$FRB_VERSION" >&2
  exit 1
fi
if [[ $("$codegen" --version) != "flutter_rust_bridge_codegen $FRB_VERSION" ]]; then
  printf 'error: FRB codegen 必须精确为 %s\n' "$FRB_VERSION" >&2
  exit 1
fi

(
  cd "$repo_root/packages/ubaa_bindings"
  PATH="$flutter_root/bin:$PATH" "$codegen" generate --config-file flutter_rust_bridge.yaml
)
python3 "$repo_root/scripts/lib/native_bindings.py" "$repo_root/packages/ubaa_bindings/lib/src/rust"
# 只格式化生成的 Rust 文件，绝不改写手写源码。
rustfmt --edition "$RUST_EDITION" "$repo_root/crates/ubaa_flutter_bridge/src/frb_generated.rs"
paths=(crates/ubaa_flutter_bridge/src/frb_generated.rs packages/ubaa_bindings/lib/src/rust)
# porcelain 同时覆盖 index、工作区、删除项和未跟踪文件。
status=$(git -C "$repo_root" status --porcelain --untracked-files=all -- "${paths[@]}")
if [[ -n "$status" ]]; then
  printf 'error: FRB 生成发生漂移：\n%s\n' "$status" >&2
  exit 1
fi
printf 'FRB 生成零漂移\n'
