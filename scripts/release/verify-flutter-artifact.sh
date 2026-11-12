#!/usr/bin/env bash
# 检查 Flutter 产物结构；不签名、不安装、不读取运行时数据。
set -euo pipefail
# shellcheck source=../lib/checksum.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/checksum.sh"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=macos-entitlements.sh
source "$script_dir/macos-entitlements.sh"

platform=${1:-}
artifact=${2:-}
platform=${platform#platform=}
artifact=${artifact#artifact=}
temporary_files=()

cleanup() {
  local file
  for file in "${temporary_files[@]+"${temporary_files[@]}"}"; do
    rm -f -- "$file"
  done
}
trap cleanup EXIT

if [[ -z "$platform" || -z "$artifact" ]]; then
  printf '用法：verify-flutter-artifact.sh <platform> <artifact-path>\n' >&2
  exit 2
fi
if [[ ! -e "$artifact" ]]; then
  printf 'error: %s 产物不存在：%s\n' "$platform" "$artifact" >&2
  exit 1
fi

require_file() {
  local path=$1
  if [[ ! -f "$path" ]]; then
    printf 'error: %s 缺少文件：%s\n' "$platform" "$path" >&2
    exit 1
  fi
}

require_dir() {
  local path=$1
  if [[ ! -d "$path" ]]; then
    printf 'error: %s 缺少目录：%s\n' "$platform" "$path" >&2
    exit 1
  fi
}

require_zip_entry() {
  local entry=$1
  if ! unzip -Z1 "$artifact" | awk -v wanted="$entry" '$0 == wanted { found = 1 } END { exit !found }'; then
    printf 'error: %s 缺少归档条目：%s\n' "$platform" "$entry" >&2
    exit 1
  fi
}

case "$platform" in
  linux)
    require_file "$artifact/UBAA"
    require_file "$artifact/ubaa-cli"
    require_file "$artifact/data/flutter_assets/AssetManifest.bin"
    ;;
  windows)
    require_file "$artifact/UBAA.exe"
    require_file "$artifact/ubaa-cli.exe"
    require_file "$artifact/data/flutter_assets/AssetManifest.bin"
    ;;
  macos)
    require_file "$artifact/Contents/MacOS/UBAA"
    require_dir "$artifact/Contents/Frameworks/App.framework"
    require_file "$artifact/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/AssetManifest.bin"
    verify_macos_entitlements "$artifact" /usr/bin/codesign /usr/libexec/PlistBuddy
    ;;
  ios-simulator)
    require_file "$artifact/Runner"
    require_dir "$artifact/Frameworks/App.framework"
    require_file "$artifact/Frameworks/App.framework/flutter_assets/AssetManifest.bin"
    ;;
  android-apk)
    require_zip_entry 'classes.dex'
    require_zip_entry 'assets/flutter_assets/AssetManifest.bin'
    abis=(arm64-v8a armeabi-v7a x86_64)
    if [[ -n "${3:-}" ]]; then
      case "$3" in
        arm64-v8a|armeabi-v7a|x86_64) abis=("$3") ;;
        *) printf 'error: 不支持的 Android 产物架构\n' >&2; exit 2 ;;
      esac
      require_zip_entry "lib/$3/libflutter.so"
      if ! unzip -Z1 "$artifact" | awk -F/ -v abi="$3" '$1 == "lib" && $NF ~ /\.so$/ && $2 != abi { bad = 1 } END { exit bad }'; then
        printf 'error: Android 产物混入其他 ABI\n' >&2
        exit 1
      fi
    fi
    for abi in "${abis[@]}"; do
      require_zip_entry "lib/$abi/libubaa_flutter_bridge.so"
    done
    python3 - "$artifact" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    for entry in archive.infolist():
        if entry.filename.startswith('lib/') and entry.filename.endswith('.so'):
            if entry.compress_type != zipfile.ZIP_DEFLATED:
                sys.exit(f'error: Android 原生库必须压缩：{entry.filename}')
PY
    ;;
  *)
    printf 'error: 不支持的 Flutter 产物平台：%s\n' "$platform" >&2
    exit 2
    ;;
esac


if [[ -f "$artifact" ]]; then
  size=$(stat -f '%z' "$artifact" 2>/dev/null || stat -c '%s' "$artifact")
  digest=$(ubaa_sha256 "$artifact" | awk '{print $1}')
else
  size=$(du -sk "$artifact" | awk '{print $1 * 1024}')
  digest_input=$(mktemp)
  temporary_files+=("$digest_input")
  while IFS= read -r -d '' file; do
    ubaa_sha256 "$file" >>"$digest_input"
  done < <(find "$artifact" -type f -print0 | sort -z)
  digest=$(ubaa_sha256 "$digest_input" | awk '{print $1}')
fi
printf 'Flutter 产物结构通过：平台=%s 路径=%s 大小=%s 字节 sha256=%s\n' \
  "$platform" "$artifact" "$size" "$digest"
