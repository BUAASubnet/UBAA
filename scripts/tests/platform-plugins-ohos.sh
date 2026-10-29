#!/usr/bin/env bash
# 对社区网络插件适配运行真实源码的合成系统边界测试。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
deveco_root=${UBAA_DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}
export UBAA_TYPESCRIPT="$deveco_root/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js"
node_bin="$deveco_root/tools/node/bin/node"
if [[ ! -x "$node_bin" ]]; then
  node_bin="$deveco_root/tool/node/bin/node"
fi
if [[ ! -x "$node_bin" || ! -f "$UBAA_TYPESCRIPT" ]]; then
  printf 'error: 缺少DevEco Node或TypeScript编译器，请设置UBAA_DEVECO_HOME\n' >&2
  exit 2
fi
"$node_bin" "$repo_root/packages/connectivity_plus_ohos/test/native/contracts.cjs"
