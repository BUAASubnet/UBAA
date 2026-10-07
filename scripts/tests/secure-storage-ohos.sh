#!/usr/bin/env bash
# 用DevEco携带的TypeScript编译器执行OHOS插件源码的确定性合同。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
deveco_root=${UBAA_DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}
typescript="$deveco_root/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js"
node_bin="$deveco_root/tools/node/bin/node"
if [[ ! -x "$node_bin" ]]; then
  node_bin="$deveco_root/tool/node/bin/node"
fi
if [[ ! -x "$node_bin" || ! -f "$typescript" ]]; then
  printf 'error: 缺少DevEco Node或TypeScript编译器，请设置UBAA_DEVECO_HOME\n' >&2
  exit 2
fi
for test_name in channel storage; do
  "$node_bin" "$repo_root/packages/flutter_secure_storage_ohos/test/native/$test_name.test.cjs" "$typescript"
done
