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

# Pub workspace 由根 manifest 统一解析并生成唯一锁文件。OHOS 宿主没有加入
# 这个 workspace，仍由自己的工具链和锁文件独立处理。
workspace_root=false
if [[ -f "$repo_root/pubspec.yaml" ]] && grep -Eq '^workspace:' "$repo_root/pubspec.yaml"; then
  workspace_root=true
  (
    cd "$repo_root"
    "$flutter_bin" pub get --enforce-lockfile
  )
fi

for package_dir in "${packages[@]}"; do
  printf '检查 %s\n' "$package_dir"
  (
    cd "$repo_root/$package_dir"
    if [[ "$workspace_root" == false ]]; then
      "$flutter_bin" pub get --enforce-lockfile
    fi
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
    # flutter_lints 当前会把既有风格提示作为 info 输出；只让 error 阻断门禁，
    # implementation_imports 等 analyzer error 仍然严格失败。
    "$flutter_bin" analyze --no-fatal-infos
    "$flutter_bin" test
  )
done
