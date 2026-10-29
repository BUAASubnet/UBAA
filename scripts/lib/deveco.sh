# shellcheck shell=bash
# DevEco Studio 与独立命令行工具共用布局；显式覆盖值优先。
# 函数输出由构建与只读预检调用方消费；独立检查库时无本地读取。
# shellcheck disable=SC2034
ubaa_deveco_layout() {
  deveco_home=${UBAA_DEVECO_HOME:?请设置 UBAA_DEVECO_HOME 为 DevEco 或命令行工具根目录}
  hmos_sdk_home=${UBAA_HMOS_SDK_HOME:-$deveco_home/sdk}
  if [[ -d "$deveco_home/tools" ]]; then
    deveco_node_home="$deveco_home/tools/node"
    deveco_hvigor_home="$deveco_home/tools/hvigor"
    deveco_ohpm_home="$deveco_home/tools/ohpm"
  else
    deveco_node_home="$deveco_home/tool/node"
    deveco_hvigor_home="$deveco_home/hvigor"
    deveco_ohpm_home="$deveco_home/ohpm"
  fi
  node_home=${UBAA_OHOS_NODE_HOME:-$deveco_node_home}
  ohos_native_home=${OHOS_SDK_HOME:-$hmos_sdk_home/default/openharmony/native}
  deveco_ohpm="$deveco_ohpm_home/bin/ohpm"
  deveco_hvigor="$deveco_hvigor_home/bin/hvigorw"
}
