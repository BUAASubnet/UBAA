#!/usr/bin/env bash
# 在固定官方 SDK 下逐一检查共享 package 与官方五平台宿主。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
check_mode=${1:-check}
if [[ $# -gt 0 ]]; then shift; fi
if [[ "$check_mode" != check && "$check_mode" != dependencies ]]; then
  printf '%s\n' 'error: 只接受 check 或 dependencies 模式' >&2
  exit 2
fi
flutter_root=${UBAA_FLUTTER_HOME:?请设置 UBAA_FLUTTER_HOME 为锁定 Flutter SDK 的绝对路径}
flutter_bin=$flutter_root/bin/flutter
dart_bin=$flutter_root/bin/dart

"$repo_root/scripts/check/flutter-toolchains.sh" official

package_list=$(python3 "$repo_root/scripts/lib/packages.py" "$@") || exit 2
packages=()
while IFS= read -r package_dir; do
  packages+=("$package_dir")
done <<<"$package_list"

for package_dir in "${packages[@]}"; do
  printf '检查 %s\n' "$package_dir"
  (
    cd "$repo_root/$package_dir"
    "$flutter_bin" pub get --enforce-lockfile
    if [[ "$check_mode" == dependencies ]]; then
      exit 0
    fi
    format_targets=()
    for candidate in lib test integration_test; do
      if [[ -d "$candidate" ]]; then
        format_targets+=("$candidate")
      fi
    done
    "$dart_bin" format --output=none --set-exit-if-changed "${format_targets[@]}"
    "$flutter_bin" analyze
    "$flutter_bin" test
  )
done
