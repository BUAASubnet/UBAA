#!/usr/bin/env bash
# 在固定官方 SDK 下逐一检查共享 package 与官方五平台宿主。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
flutter_root=${UBAA_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-3.41.9}
flutter_bin=$flutter_root/bin/flutter
dart_bin=$flutter_root/bin/dart

"$repo_root/scripts/check/flutter-toolchains.sh" official

packages=(
  packages/ubaa_domain
  packages/ubaa_platform
  packages/ubaa_app
  packages/ubaa_ui
  packages/ubaa_bindings
  packages/ubaa_host
  apps/ubaa_flutter
)

for package_dir in "${packages[@]}"; do
  printf '检查 %s\n' "$package_dir"
  (
    cd "$repo_root/$package_dir"
    "$flutter_bin" pub get --enforce-lockfile
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
