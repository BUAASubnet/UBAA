#!/usr/bin/env bash
# 对社区网络插件适配运行真实源码的合成系统边界测试。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
# shellcheck source=../lib/deveco.sh
source "$script_dir/../lib/deveco.sh"
ubaa_deveco_layout
typescript="$hmos_sdk_home/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js"
node_bin="$node_home/bin/node"
if [[ ! -x "$node_bin" || ! -f "$typescript" ]]; then
  printf 'error: 缺少DevEco Node或TypeScript编译器，请设置UBAA_DEVECO_HOME\n' >&2
  exit 2
fi
export UBAA_TYPESCRIPT="$typescript"
"$node_bin" "$repo_root/packages/connectivity_plus_ohos/test/native/contracts.cjs"
