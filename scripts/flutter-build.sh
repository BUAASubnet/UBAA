#!/usr/bin/env bash
# 在当前原生 runner 上构建一个明确的平台目标。
set -euo pipefail

platform=${1:-host}
mode=${2:-debug}
platform=${platform#platform=}
mode=${mode#mode=}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
flutter_root=${UBAA_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-3.41.9}
flutter_bin=$flutter_root/bin/flutter
app_root=$repo_root/apps/ubaa_flutter

"$repo_root/scripts/check-flutter-toolchains.sh" official
if [[ "$mode" != debug && "$mode" != release ]]; then
  printf 'error: 构建模式只能是 debug 或 release\n' >&2
  exit 2
fi

(
  cd "$app_root"
  "$flutter_bin" pub get --enforce-lockfile
  case "$platform" in
    host)
      case "$(uname -s)" in
        Darwin) "$flutter_bin" build macos --"$mode" ;;
        Linux) "$flutter_bin" build linux --"$mode" ;;
        MINGW*|MSYS*|CYGWIN*) "$flutter_bin" build windows --"$mode" ;;
        *) printf 'error: 不支持的 host：%s\n' "$(uname -s)" >&2; exit 2 ;;
      esac
      ;;
    macos) "$flutter_bin" build macos --"$mode" ;;
    linux) "$flutter_bin" build linux --"$mode" ;;
    windows) "$flutter_bin" build windows --"$mode" ;;
    android-apk) "$flutter_bin" build apk --"$mode" ;;
    android-appbundle) "$flutter_bin" build appbundle --"$mode" ;;
    ios-simulator)
      if [[ "$mode" == release ]]; then
        printf 'error: iOS simulator 不支持 release；请使用 debug\n' >&2
        exit 2
      fi
      "$flutter_bin" build ios --simulator --debug --no-codesign
      ;;
    ios-device) "$flutter_bin" build ios --"$mode" --no-codesign ;;
    *) printf 'error: 未知平台：%s\n' "$platform" >&2; exit 2 ;;
  esac
)
