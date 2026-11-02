# shellcheck shell=bash
# 直接运行的 Shell 入口与 just 共用工具链配置，禁止 source 凭据文件。
ubaa_toolchain_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ubaa_toolchain_exports=$(python3 "$ubaa_toolchain_script_dir/toolchain.py" shell) || return
# 解析器仅输出经过 shlex.quote 转义的赋值，不把配置作为 Shell 程序执行。
eval "$ubaa_toolchain_exports"
unset ubaa_toolchain_exports ubaa_toolchain_script_dir

# 先拒绝相对路径，再由 Git Bash 转换盘符路径；保留空格和中文。
ubaa_toolchain_absolute_path() {
  case "$1" in
    /* | [[:alpha:]]:[/\\]*) ;;
    *) return 2 ;;
  esac
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s\n' "$1"
  fi
}
