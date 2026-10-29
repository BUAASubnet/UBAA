#!/usr/bin/env bash
# CI 显式下载精确 SDK；普通检查不运行此安装入口。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
# shellcheck source=../lib/versions.sh
source "$script_dir/../lib/versions.sh"
repo_root=$(ubaa_repo_root)
flutter_root=${RUNNER_TEMP:?此安装入口需要 CI 的 RUNNER_TEMP}/flutter
if command -v cygpath >/dev/null 2>&1; then
  flutter_root=$(cygpath -u "$flutter_root")
fi
git init "$flutter_root"
git -C "$flutter_root" remote add origin "$FLUTTER_REMOTE"
git -C "$flutter_root" fetch --depth=1 origin "refs/tags/$FLUTTER_VERSION:refs/tags/$FLUTTER_VERSION"
git -C "$flutter_root" checkout --detach "$FLUTTER_COMMIT"
# Git Bash 内使用 POSIX 路径，跨步骤环境使用 Windows 原生进程可识别的绝对路径。
flutter_environment_root=$flutter_root
if command -v cygpath >/dev/null 2>&1; then
  flutter_environment_root=$(cygpath -m "$flutter_root")
fi
printf 'UBAA_FLUTTER_HOME=%s\n' "$flutter_environment_root" >> "${GITHUB_ENV:?需要 GITHUB_ENV}"
export UBAA_FLUTTER_HOME="$flutter_root"
bash "$repo_root/scripts/check/flutter-toolchains.sh" official
