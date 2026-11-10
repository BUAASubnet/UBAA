#!/usr/bin/env bash
# 在当前原生 runner 上构建一个明确的平台目标。
set -euo pipefail

platform=${1:-host}
mode=${2:-debug}
platform=${platform#platform=}
mode=${mode#mode=}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
flutter_root=${UBAA_FLUTTER_HOME:?请设置 UBAA_FLUTTER_HOME 为锁定 Flutter SDK 的绝对路径}
flutter_bin=$flutter_root/bin/flutter
app_root=$repo_root/apps/ubaa_flutter

app_service_defines=()
for key in UBAA_APP_SERVICE_URL UBAA_DISTRIBUTION_CHANNEL; do
  if [[ -n "${!key:-}" ]]; then
    app_service_defines+=("--dart-define=$key=${!key}")
  fi
done

flutter_build() {
  if [[ ${UBAA_FLUTTER_VERBOSE:-0} == 1 ]]; then
    "$flutter_bin" build "$@" ${app_service_defines[@]+"${app_service_defines[@]}"} -v
  else
    "$flutter_bin" build "$@" ${app_service_defines[@]+"${app_service_defines[@]}"}
  fi
}

"$repo_root/scripts/check/flutter-toolchains.sh" official
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
        Darwin) flutter_build macos --"$mode" ;;
        Linux) flutter_build linux --"$mode" ;;
        MINGW*|MSYS*|CYGWIN*) flutter_build windows --"$mode" ;;
        *) printf 'error: 不支持的 host：%s\n' "$(uname -s)" >&2; exit 2 ;;
      esac
      ;;
    macos) flutter_build macos --"$mode" ;;
    linux) flutter_build linux --"$mode" ;;
    windows) flutter_build windows --"$mode" ;;
    android-apk) flutter_build apk --"$mode" ;;
    android-appbundle) flutter_build appbundle --"$mode" ;;
    ios-simulator)
      if [[ "$mode" == release ]]; then
        printf 'error: iOS simulator 不支持 release；请使用 debug\n' >&2
        exit 2
      fi
      # Xcode 27.2 的 lipo 无法一次校验多个架构，Flutter 的 debug_unpack_ios 会误报缺架构；
      # 此时只编本机架构，旧版 Xcode 仍构建 arm64 + x86_64。
      # 仅匹配参数解析错误；探针缺少架构或工具不可用时不改变构建目标。
      lipo_diagnostic=$(LC_ALL=C lipo /usr/bin/true -verify_arch x86_64 arm64e 2>&1) || true
      if [[ "$lipo_diagnostic" == *'-verify_arch requires exactly one input file'* ]]; then
        export FLUTTER_XCODE_ARCHS=${FLUTTER_XCODE_ARCHS:-$(uname -m)}
        printf 'note: lipo 不支持多架构校验，模拟器只构建 %s\n' "$FLUTTER_XCODE_ARCHS" >&2
      fi
      flutter_build ios --simulator --debug --no-codesign
      ;;
    ios-device) flutter_build ios --"$mode" --no-codesign ;;
    *) printf 'error: 未知平台：%s\n' "$platform" >&2; exit 2 ;;
  esac
)

# Linux GUI bundle 同时交付无图形会话命令，复用 Cargokit 已构建的同一 Rust 库。
if [[ "$platform" == linux || ( "$platform" == host && "$(uname -s)" == Linux ) ]]; then
  case "$(uname -m)" in
    aarch64|arm64) command_arch=arm64 ;;
    x86_64) command_arch=x64 ;;
    *) printf '%s\n' 'Linux 命令不支持当前构建架构' >&2; exit 2 ;;
  esac
  python3 "$script_dir/command.py" linux-bundle "$mode" "$app_root/build/linux/$command_arch/$mode/bundle"
fi
