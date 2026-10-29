#!/usr/bin/env bash
# 验证 Flutter SDK 精确版本；所有调用方都使用绝对路径，不依赖 shell PATH。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"

mode=${1:-all}
official_root=${UBAA_FLUTTER_HOME:-}
ohos_root=${UBAA_OHOS_FLUTTER_HOME:-}
official_commit=00b0c91f06209d9e4a41f71b7a512d6eb3b9c694
ohos_commit=adaf911c35c9136a7d18fc424d714c9ec7724e60
ohos_tag=3.41.10-ohos-1.0.1

check_sdk() {
  local label=$1
  local root=$2
  local expected_commit=$3
  local expected_version=$4
  local variable=$5

  if [[ -z "$root" ]]; then
    printf 'error: 请设置 %s 为 %s SDK 的绝对路径（版本 %s）\n' "$variable" "$label" "$expected_version" >&2
    return 1
  fi

  # Windows runner 会把 GITHUB_ENV 中的 /d/... 重新表示为 D:/...；在 Git Bash
  # 内先还原成 POSIX 绝对路径，再执行同一套版本和可执行文件检查。
  if command -v cygpath >/dev/null 2>&1; then
    root=$(cygpath -u "$root")
  fi

  if [[ "$root" != /* || ! -x "$root/bin/flutter" ]]; then
    printf 'error: %s 必须是包含 bin/flutter 的绝对路径（%s）：%s\n' "$variable" "$label" "$root" >&2
    return 1
  fi
  local actual_commit
  actual_commit=$(git -C "$root" rev-parse HEAD)
  if [[ "$actual_commit" != "$expected_commit" ]]; then
    printf 'error: %s commit 不匹配：期望 %s，实际 %s\n' \
      "$label" "$expected_commit" "$actual_commit" >&2
    return 1
  fi
  local version_output version_line='' actual_version='' line
  version_output=$("$root/bin/flutter" --version)
  # 冷启动的 curl 进度可能写入 stdout；只采用第一条独立 Flutter 版本行。
  while IFS= read -r line; do
    if [[ $line == 'Flutter '* ]]; then
      version_line=$line
      read -r _ actual_version _ <<<"$version_line"
      break
    fi
  done <<<"$version_output"
  if [[ "$actual_version" != "$expected_version" ]]; then
    printf 'error: %s 版本不匹配：%s\n' "$label" "$version_line" >&2
    return 1
  fi
  printf '%s 已锁定：%s @ %s\n' "$label" "$expected_version" "$expected_commit"
}

case "$mode" in
  official)
    check_sdk 官方Flutter "$official_root" "$official_commit" 3.41.9 UBAA_FLUTTER_HOME
    ;;
  ohos)
    check_sdk OHOS-Flutter "$ohos_root" "$ohos_commit" "$ohos_tag" UBAA_OHOS_FLUTTER_HOME
    ;;
  all)
    check_sdk 官方Flutter "$official_root" "$official_commit" 3.41.9 UBAA_FLUTTER_HOME
    check_sdk OHOS-Flutter "$ohos_root" "$ohos_commit" "$ohos_tag" UBAA_OHOS_FLUTTER_HOME
    ;;
  *)
    printf 'error: 未知工具链检查模式：%s\n' "$mode" >&2
    exit 2
    ;;
esac
