#!/usr/bin/env bash
# 验证 Flutter SDK 精确版本；所有调用方都使用绝对路径，不依赖 shell PATH。
set -euo pipefail

mode=${1:-all}
official_root=${UBAA_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-3.41.9}
ohos_root=${UBAA_OHOS_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-ohos-3.41.10}
official_commit=00b0c91f06209d9e4a41f71b7a512d6eb3b9c694
ohos_commit=adaf911c35c9136a7d18fc424d714c9ec7724e60
ohos_tag=3.41.10-ohos-1.0.1

check_sdk() {
  local label=$1
  local root=$2
  local expected_commit=$3
  local expected_version=$4

  if [[ "$root" != /* || ! -x "$root/bin/flutter" ]]; then
    printf 'error: %s SDK 必须是包含 bin/flutter 的绝对路径：%s\n' "$label" "$root" >&2
    return 1
  fi
  local actual_commit
  actual_commit=$(git -C "$root" rev-parse HEAD)
  if [[ "$actual_commit" != "$expected_commit" ]]; then
    printf 'error: %s commit 不匹配：期望 %s，实际 %s\n' \
      "$label" "$expected_commit" "$actual_commit" >&2
    return 1
  fi
  local version_line
  version_line=$("$root/bin/flutter" --version | head -n 1)
  if [[ "$version_line" != *"$expected_version"* ]]; then
    printf 'error: %s 版本不匹配：%s\n' "$label" "$version_line" >&2
    return 1
  fi
  printf '%s 已锁定：%s @ %s\n' "$label" "$expected_version" "$expected_commit"
}

case "$mode" in
  official)
    check_sdk 官方Flutter "$official_root" "$official_commit" 3.41.9
    ;;
  ohos)
    check_sdk OHOS-Flutter "$ohos_root" "$ohos_commit" "$ohos_tag"
    ;;
  all)
    check_sdk 官方Flutter "$official_root" "$official_commit" 3.41.9
    check_sdk OHOS-Flutter "$ohos_root" "$ohos_commit" "$ohos_tag"
    ;;
  *)
    printf 'error: 未知工具链检查模式：%s\n' "$mode" >&2
    exit 2
    ;;
esac
