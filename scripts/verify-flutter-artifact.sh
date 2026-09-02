#!/usr/bin/env bash
# 检查 Flutter 无签名 Debug 产物的结构；不签名、不安装、不读取运行时数据。
set -euo pipefail

platform=${1:-}
artifact=${2:-}
platform=${platform#platform=}
artifact=${artifact#artifact=}

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
    require_file "$artifact/ubaa_flutter"
    require_file "$artifact/data/flutter_assets/AssetManifest.bin"
    ;;
  windows)
    require_file "$artifact/ubaa_flutter.exe"
    require_file "$artifact/data/flutter_assets/AssetManifest.bin"
    ;;
  macos)
    require_file "$artifact/Contents/MacOS/ubaa_flutter"
    require_dir "$artifact/Contents/Frameworks/App.framework"
    require_file "$artifact/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/AssetManifest.bin"
    ;;
  ios-simulator)
    require_file "$artifact/Runner"
    require_dir "$artifact/Frameworks/App.framework"
    require_file "$artifact/Frameworks/App.framework/flutter_assets/AssetManifest.bin"
    ;;
  android-apk)
    require_zip_entry 'classes.dex'
    require_zip_entry 'assets/flutter_assets/AssetManifest.bin'
    for abi in arm64-v8a armeabi-v7a x86_64; do
      require_zip_entry "lib/$abi/libubaa_flutter_bridge.so"
    done
    ;;
  *)
    printf 'error: 不支持的 Flutter 产物平台：%s\n' "$platform" >&2
    exit 2
    ;;
esac

if [[ -f "$artifact" ]]; then
  size=$(stat -f '%z' "$artifact" 2>/dev/null || stat -c '%s' "$artifact")
  digest=$(shasum -a 256 "$artifact" 2>/dev/null | awk '{print $1}' || sha256sum "$artifact" | awk '{print $1}')
else
  size=$(du -sk "$artifact" | awk '{print $1 * 1024}')
  digest=$(find "$artifact" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')
fi
printf 'Flutter 产物结构通过：平台=%s 路径=%s 大小=%s 字节 sha256=%s\n' \
  "$platform" "$artifact" "$size" "$digest"
