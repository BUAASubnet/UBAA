# shellcheck shell=bash
# 直接运行的 Shell 入口使用与 just 相同的公共白名单。
ubaa_toolchain_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# 构建父进程保留调用方注入的签名字段；只有最终 SDK 构建命令加载对应平台材料。
ubaa_toolchain_arguments=()
if [[ "${1:-}" == build ]]; then ubaa_toolchain_arguments=(build); fi
ubaa_toolchain_exports=$(python3 "$ubaa_toolchain_script_dir/toolchain.py" shell ${ubaa_toolchain_arguments[@]+"${ubaa_toolchain_arguments[@]}"}) || return
# 解析器只输出固定的取消导出指令和经 shlex.quote 转义的公共赋值。
eval "$ubaa_toolchain_exports"
unset ubaa_toolchain_exports ubaa_toolchain_script_dir ubaa_toolchain_arguments

# 先拒绝相对路径，再由 Git Bash 转换盘符路径；保留空格和中文。
ubaa_toolchain_absolute_path() {
  case "$1" in
    /* | [[:alpha:]]:[/\\]*) ;;
    *) return 2 ;;
  esac
  if command -v cygpath >/dev/null 2>&1; then
    local converted
    converted=$(cygpath -u "$1") || return
    [[ "$converted" == /* ]] || return 2
    printf '%s\n' "$converted"
  else
    [[ "$1" == /* ]] || return 2
    printf '%s\n' "$1"
  fi
}
