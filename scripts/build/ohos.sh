#!/usr/bin/env bash
# 使用独立 OHOS SDK 完成工具链、Dart 和 HAP/native library 门禁。
set -euo pipefail

mode=${1:-release}
mode=${mode#mode=}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
flutter_root=${UBAA_OHOS_FLUTTER_HOME:?请设置 UBAA_OHOS_FLUTTER_HOME 为锁定 Flutter SDK 的绝对路径}
flutter_bin=$flutter_root/bin/flutter
app_root=$repo_root/apps/ubaa_ohos
# shellcheck source=../lib/deveco.sh
source "$script_dir/../lib/deveco.sh"
ubaa_deveco_layout
export OHOS_SDK_HOME="$ohos_native_home"
export DEVECO_SDK_HOME="$hmos_sdk_home"
export DEVECO_NODE_HOME="$node_home"
export PATH="$deveco_hvigor_home/bin:$deveco_ohpm_home/bin:$node_home/bin:$PATH"

if [[ "$mode" != debug && "$mode" != release ]]; then
  printf 'error: 构建模式只能是 debug 或 release\n' >&2
  exit 2
fi

"$repo_root/scripts/check/flutter-toolchains.sh" ohos
(
  cd "$app_root"
  "$flutter_bin" pub get --enforce-lockfile
  "$flutter_bin" analyze
  "$flutter_bin" test
)

(cd "$app_root" && ./scripts/check-toolchain.sh)
bash "$repo_root/scripts/tests/secure-storage-ohos.sh"
bash "$repo_root/scripts/tests/platform-plugins-ohos.sh"
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

# OHOS fork 会移动 buildinfo 模板；从本次配置恢复，保留本地的渲染选项。
buildinfo=apps/ubaa_ohos/ohos/entry/src/main/resources/base/profile/buildinfo.json5
if [[ ! -e "$repo_root/$buildinfo" ]]; then
  cp "$app_root/ohos/entry/src/main/resources/rawfile/buildinfo.json5" "$repo_root/$buildinfo"
fi

hap_root=$app_root/build/ohos/hap
hap_path=$(find "$hap_root" -type f -name '*.hap' -print -quit)
if [[ -z "$hap_path" ]]; then
  printf 'error: 未生成 HAP\n' >&2
  exit 1
fi
bridge_lib=$(unzip -Z1 "$hap_path" | grep -E '^libs/arm64-v8a/libubaa_flutter_bridge\.so$' | head -n 1 || true)
if [[ -z "$bridge_lib" ]]; then
  printf 'error: HAP 内缺少 Dart 实际加载的 arm64 动态库 libubaa_flutter_bridge.so\n' >&2
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
