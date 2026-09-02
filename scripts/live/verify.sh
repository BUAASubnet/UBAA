#!/usr/bin/env bash
# 真实验证外层入口：校验参数和凭据后，转发至单进程 Core-live。
{ set +x; } 2>/dev/null
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
# shellcheck source=../lib/live-features.sh
source "$script_dir/../lib/live-features.sh"
repo_root=$(ubaa_repo_root)
core_live=${UBAA_CORE_LIVE_SCRIPT:-$repo_root/scripts/live/core-live.sh}
env_file=${UBAA_ENV_FILE:-$repo_root/.env.local}

read_env_value() {
  local key=$1 value
  value=$(awk -v key="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    $1 ~ ("^" key "=") {
      sub(/^[[:space:]]*/, "")
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$env_file")
  value=${value%$'\r'}
  if [[ ${#value} -ge 2 && ${value:0:1} == '"' && ${value: -1} == '"' ]]; then
    value=${value:1:${#value}-2}
  elif [[ ${#value} -ge 2 && ${value:0:1} == "'" && ${value: -1} == "'" ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s' "$value"
}

route=
feature=all
date_value=${UBAA_VERIFY_DATE:-$(TZ=Asia/Shanghai date +%F)}
campus_id=${UBAA_VERIFY_CAMPUS_ID:-1}

for argument in "$@"; do
  case "$argument" in
    mode=direct|route=direct|--route=direct) route=direct ;;
    mode=webvpn|route=webvpn|--route=webvpn) route=webvpn ;;
    mode=auto|route=auto|--route=auto)
      printf '%s\n' '真实验证不执行 auto；auto 只用于确定性路由测试' >&2
      exit 2
      ;;
    feature=*) feature=${argument#feature=} ;;
    --feature=*) feature=${argument#--feature=} ;;
    date=*) date_value=${argument#date=} ;;
    --date=*) date_value=${argument#--date=} ;;
    campus-id=*) campus_id=${argument#campus-id=} ;;
    --campus-id=*) campus_id=${argument#--campus-id=} ;;
    '') ;;
    *) printf 'verify-live 参数无效: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

case "$route" in
  direct|webvpn) ;;
  *) printf '%s\n' '必须指定 mode=direct 或 mode=webvpn' >&2; exit 2 ;;
esac
if ! ubaa_live_feature_supported "$feature"; then
  printf '不支持 feature=%s\n' "$feature" >&2
  exit 2
fi

if [[ ! -f "$env_file" ]]; then
  printf '凭据文件不存在: %s\n' "$env_file" >&2
  exit 2
fi
username=$(read_env_value UBAA_TEST_USERNAME)
password=$(read_env_value UBAA_TEST_PASSWORD)
if [[ -z "$username" ]]; then
  username=$(read_env_value UBAA_USERNAME)
fi
if [[ -z "$password" ]]; then
  password=$(read_env_value UBAA_PASSWORD)
fi
if [[ -z "$username" || -z "$password" ]]; then
  printf '%s\n' '凭据文件缺少 UBAA_TEST_USERNAME/UBAA_TEST_PASSWORD（或兼容名称）' >&2
  exit 2
fi

if [[ ! -x "$core_live" ]]; then
  printf 'Core-live 启动器不可执行: %s\n' "$core_live" >&2
  exit 2
fi

set +x
printf '%s\n%s\n' "$username" "$password" |
  "$core_live" "route=$route" "feature=$feature" "date=$date_value" "campus-id=$campus_id"
