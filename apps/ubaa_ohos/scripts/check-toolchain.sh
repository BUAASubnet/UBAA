#!/usr/bin/env bash
# 只读检查 HarmonyOS 构建前置条件；不会生成工程、下载依赖或改写配置。
set -euo pipefail

expected_flutter_tag=3.41.10-ohos-1.0.1
expected_flutter_commit=adaf911c35c9136a7d18fc424d714c9ec7724e60
required_api=26
required_rust_target=aarch64-unknown-linux-ohos

error_count=0
warning_count=0

pass() {
  printf '[通过] %s\n' "$1"
}

warn() {
  printf '[警告] %s\n' "$1" >&2
  warning_count=$((warning_count + 1))
}

fail() {
  printf '[失败] %s\n' "$1" >&2
  error_count=$((error_count + 1))
}

resolve_flutter_root() {
  if [[ -n ${UBAA_OHOS_FLUTTER_HOME:-} ]]; then
    printf '%s' "$UBAA_OHOS_FLUTTER_HOME"
    return
  fi
  if [[ -x /Users/moorefoss/Dev/flutter-ohos-3.41.10/bin/flutter ]]; then
    printf '%s' /Users/moorefoss/Dev/flutter-ohos-3.41.10
    return
  fi
  local flutter_command
  flutter_command=$(command -v flutter 2>/dev/null || true)
  if [[ -n "$flutter_command" ]]; then
    cd "$(dirname "$flutter_command")/.." && pwd
  fi
}

flutter_root=$(resolve_flutter_root)
deveco_home=${UBAA_DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}
hmos_sdk_home=${UBAA_HMOS_SDK_HOME:-$deveco_home/sdk}
if [[ -d "$deveco_home/tools" ]]; then
  deveco_node_home="$deveco_home/tools/node"
  deveco_ohpm="$deveco_home/tools/ohpm/bin/ohpm"
  deveco_hvigor="$deveco_home/tools/hvigor/bin/hvigorw"
else
  deveco_node_home="$deveco_home/tool/node"
  deveco_ohpm="$deveco_home/ohpm/bin/ohpm"
  deveco_hvigor="$deveco_home/hvigor/bin/hvigorw"
fi
node_home=${UBAA_OHOS_NODE_HOME:-$deveco_node_home}
ohos_native_home=${OHOS_SDK_HOME:-$hmos_sdk_home/default/openharmony/native}

if [[ -z "$flutter_root" || ! -x "$flutter_root/bin/flutter" ]]; then
  fail '未找到 Flutter OH；请设置 UBAA_OHOS_FLUTTER_HOME'
else
  actual_commit=$(git -C "$flutter_root" rev-parse HEAD 2>/dev/null || true)
  actual_tag=$(git -C "$flutter_root" describe --tags --exact-match 2>/dev/null || true)
  if [[ "$actual_commit" == "$expected_flutter_commit" ]]; then
    pass "Flutter OH commit 为 $expected_flutter_commit"
  else
    fail "Flutter OH commit 不匹配：期望 ${expected_flutter_commit}，实际 ${actual_commit:-未知}"
  fi
  if [[ "$actual_tag" == "$expected_flutter_tag" ]]; then
    pass "Flutter OH tag 为 $expected_flutter_tag"
  else
    fail "Flutter OH tag 不匹配：期望 ${expected_flutter_tag}，实际 ${actual_tag:-未知}"
  fi
  flutter_version=$($flutter_root/bin/flutter --version 2>&1 | head -n 1 || true)
  if [[ "$flutter_version" == *"$expected_flutter_tag"* ]]; then
    pass "$flutter_version"
  else
    fail "Flutter OH 版本输出异常：${flutter_version:-无输出}"
  fi
fi

if [[ ! -d "$deveco_home" ]]; then
  fail "DevEco Studio 不存在：$deveco_home"
else
  product_info=$deveco_home/Resources/product-info.json
  deveco_version=
  if [[ -f "$product_info" && $(uname -s) == Darwin ]] && command -v plutil >/dev/null; then
    deveco_version=$(plutil -extract version raw "$product_info" 2>/dev/null || true)
  elif [[ -f "$deveco_home/version.txt" ]]; then
    deveco_version=$(awk -F: '/^# Version:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$deveco_home/version.txt")
  fi
  if [[ "$deveco_version" == 26.* ]]; then
    pass "DevEco Studio 版本为 $deveco_version"
  else
    fail "当前 DevEco Studio 为 ${deveco_version:-未知版本}；该 fork 的发布门槛是 26.0.0 Beta2"
  fi
fi

sdk_manifest=$hmos_sdk_home/default/openharmony/toolchains/oh-uni-package.json
if [[ ! -f "$sdk_manifest" ]]; then
  fail "找不到 OpenHarmony SDK 清单：$sdk_manifest"
else
  sdk_api=$(awk -F'"' '/"apiVersion"/ { print $4; exit }' "$sdk_manifest")
  if [[ "$sdk_api" == "$required_api" ]]; then
    pass "OpenHarmony SDK API 为 $sdk_api"
  else
    fail "OpenHarmony SDK API 为 ${sdk_api:-未知}；必须使用 API ${required_api}，不能伪装或降级"
  fi
fi

if [[ -d "$ohos_native_home" ]]; then
  pass "OHOS native SDK 可用：$ohos_native_home"
else
  fail "OHOS native SDK 不存在：$ohos_native_home"
fi
if [[ "$ohos_native_home" =~ [[:space:]] ]]; then
  fail "OHOS native SDK 路径不能包含空白：$ohos_native_home"
fi
if [[ -x "$ohos_native_home/llvm/bin/clang" ]]; then
  pass "OHOS clang 可用"
else
  fail "OHOS clang 不存在：$ohos_native_home/llvm/bin/clang"
fi
if [[ -x "$ohos_native_home/llvm/bin/llvm-ar" ]]; then
  pass "OHOS llvm-ar 可用"
else
  fail "OHOS llvm-ar 不存在：$ohos_native_home/llvm/bin/llvm-ar"
fi
if [[ -d "$ohos_native_home/sysroot" ]]; then
  pass "OHOS sysroot 可用"
else
  fail "OHOS sysroot 不存在：$ohos_native_home/sysroot"
fi

if [[ -x "$node_home/bin/node" ]]; then
  node_version=$($node_home/bin/node --version 2>/dev/null || true)
  pass "Node 可用：${node_version:-未知版本}"
else
  fail "DevEco Node 不可用：$node_home/bin/node"
fi

check_executable() {
  local name=$1
  local path=$2
  local version_argument=$3
  if [[ ! -x "$path" ]]; then
    fail "$name 不可用：$path"
    return
  fi
  local version
  version=$($path "$version_argument" 2>&1 | head -n 1 || true)
  pass "$name 可用：${version:-未报告版本}"
}

check_executable ohpm "$deveco_ohpm" --version
check_executable hvigor "$deveco_hvigor" --version
check_executable hdc "$hmos_sdk_home/default/openharmony/toolchains/hdc" -v

if command -v java >/dev/null 2>&1; then
  java_version=$(java -version 2>&1 | head -n 1 || true)
  if [[ "$java_version" =~ (17|18|19|20|21|22|23|24|25|26) ]]; then
    pass "Java 可用：$java_version"
  else
    fail "Java 版本不满足 JDK 17+：${java_version:-未知版本}"
  fi
else
  fail '未找到 Java；需要 JDK 17 或更高版本'
fi

if command -v rustup >/dev/null 2>&1; then
  if rustup target list --installed | grep -Fx "$required_rust_target" >/dev/null; then
    pass "Rust target 已安装：$required_rust_target"
  else
    fail "Rust target 未安装：$required_rust_target"
  fi
else
  fail '未找到 rustup，无法验证 OHOS Rust target'
fi

if [[ ! -d "$flutter_root"/bin/cache ]]; then
  warn 'Flutter OH 缓存尚未初始化，首次构建需要下载固定版本产物'
fi

if [[ ! -d "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ohos" ]]; then
  warn 'ohos/ runner 尚未生成；工具链全通过后再执行 flutter create --platforms ohos .'
fi

printf '\n检查完成：%d 个失败，%d 个警告。\n' "$error_count" "$warning_count"
if (( error_count > 0 )); then
  exit 1
fi
