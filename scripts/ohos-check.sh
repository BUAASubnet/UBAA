#!/usr/bin/env bash
# 使用独立 OHOS SDK 完成工具链、Dart 和 HAP/native library 门禁。
set -euo pipefail

mode=${1:-release}
mode=${mode#mode=}
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
flutter_root=${UBAA_OHOS_FLUTTER_HOME:-/Users/moorefoss/Dev/flutter-ohos-3.41.10}
flutter_bin=$flutter_root/bin/flutter
app_root=$repo_root/apps/ubaa_ohos
deveco_home=${UBAA_DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}
export OHOS_SDK_HOME=${OHOS_SDK_HOME:-$deveco_home/sdk/default/openharmony/native}

# Flutter OH 会从 PATH 调用 hvigorw。固定使用同一 DevEco 安装提供的
# Hvigor、ohpm、Node 和 SDK，避免 shell 中残留的旧 command-line-tools
# 把 API26 工程误编译成旧 API。
export DEVECO_SDK_HOME="$deveco_home/sdk"
if [[ -d "$deveco_home/tools" ]]; then
  DEVECO_NODE_HOME="$deveco_home/tools/node"
  deveco_hvigor_home="$deveco_home/tools/hvigor"
  deveco_ohpm_home="$deveco_home/tools/ohpm"
else
  DEVECO_NODE_HOME="$deveco_home/tool/node"
  deveco_hvigor_home="$deveco_home/hvigor"
  deveco_ohpm_home="$deveco_home/ohpm"
fi
export DEVECO_NODE_HOME
export PATH="$deveco_hvigor_home/bin:$deveco_ohpm_home/bin:$DEVECO_NODE_HOME/bin:$PATH"

if [[ "$mode" != debug && "$mode" != release ]]; then
  printf 'error: 构建模式只能是 debug 或 release\n' >&2
  exit 2
fi

"$repo_root/scripts/check-flutter-toolchains.sh" ohos
(
  cd "$app_root"
  "$flutter_bin" pub get --enforce-lockfile
  "$flutter_bin" analyze
  "$flutter_bin" test
)

(cd "$app_root" && ./scripts/check-toolchain.sh)
if [[ ! -d "$app_root/ohos" ]]; then
  printf 'error: 缺少由锁定 fork 生成的 OHOS runner\n' >&2
  exit 1
fi

(
  cd "$app_root"
  hap_args=(--"$mode" --target-platform ohos-arm64)
  if [[ "${UBAA_OHOS_NO_CODESIGN:-0}" == "1" ]]; then
    if [[ "$mode" != "debug" ]]; then
      printf 'error: UBAA_OHOS_NO_CODESIGN=1 只允许 debug 构建\n' >&2
      exit 2
    fi
    hap_args+=(--no-codesign)
    printf 'warning: 以无签名 debug 模式构建 OHOS HAP；该产物不可作为发布或实体设备验收证据\n' >&2
  fi
  "$flutter_bin" build hap "${hap_args[@]}"
)

hap_root=$app_root/build/ohos/hap
hap_path=$(find "$hap_root" -type f -name '*.hap' -print -quit)
if [[ -z "$hap_path" ]]; then
  printf 'error: 未生成 HAP\n' >&2
  exit 1
fi
bridge_lib=$(unzip -Z1 "$hap_path" | grep -E '(^|/)libs/arm64-v8a/libubaa_(bindings|flutter_bridge)\.so$' | head -n 1 || true)
if [[ -z "$bridge_lib" ]]; then
  printf 'error: HAP 内未包含 arm64 UBAA Rust bridge 动态库\n' >&2
  exit 1
fi
bridge_tmp=$(mktemp)
trap 'rm -f "$bridge_tmp"' EXIT
unzip -p "$hap_path" "$bridge_lib" >"$bridge_tmp"
bridge_file=$(file -b "$bridge_tmp")
if ! grep -Eq 'ELF 64-bit.*ARM aarch64' <<<"$bridge_file"; then
  printf 'error: HAP 内 bridge 动态库不是 arm64 ELF（%s）\n' "$bridge_file" >&2
  exit 1
fi
printf 'OHOS HAP 与 arm64 Rust 动态库门禁通过（%s）：%s\n' "$bridge_lib" "$hap_path"
