#!/usr/bin/env bash
# 在固定官方 SDK 下逐一检查共享 package 与官方五平台宿主。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
flutter_root=${UBAA_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-3.41.9}
flutter_bin=$flutter_root/bin/flutter

"$repo_root/scripts/check-flutter-toolchains.sh" official

packages=(
  packages/ubaa_domain
  packages/ubaa_platform
  packages/ubaa_app
  packages/ubaa_ui
  packages/ubaa_bindings
  apps/ubaa_flutter
)

for package_dir in "${packages[@]}"; do
  printf '检查 %s\n' "$package_dir"
  (
    cd "$repo_root/$package_dir"
    "$flutter_bin" pub get --enforce-lockfile
    "$flutter_bin" analyze
    "$flutter_bin" test
  )
done
