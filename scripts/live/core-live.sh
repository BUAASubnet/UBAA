#!/usr/bin/env bash
# Core-live 二进制启动器：只负责参数校验、构建和 stdin 转发。
{ set +x; } 2>/dev/null
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
# shellcheck source=../lib/live-features.sh
source "$script_dir/../lib/live-features.sh"
repo_root=$(ubaa_repo_root)
binary=${UBAA_CORE_LIVE_BINARY:-$repo_root/target/debug/core-live}

route=
feature=all
config_dir=
date_value=${UBAA_VERIFY_DATE:-$(TZ=Asia/Shanghai date +%F)}
campus_id=${UBAA_VERIFY_CAMPUS_ID:-1}

for argument in "$@"; do
  case "$argument" in
    route=direct|--route=direct) route=direct ;;
    route=webvpn|--route=webvpn) route=webvpn ;;
    route=auto|--route=auto)
      printf '%s\n' 'Core-live 真实验证只允许 direct 或 webvpn；auto 仅用于确定性路由测试' >&2
      exit 2
      ;;
    feature=*) feature=${argument#feature=} ;;
    --feature=*) feature=${argument#--feature=} ;;
    date=*) date_value=${argument#date=} ;;
    campus-id=*) campus_id=${argument#campus-id=} ;;
    --date=*) date_value=${argument#--date=} ;;
    --campus-id=*) campus_id=${argument#--campus-id=} ;;
    config-dir=*) config_dir=${argument#config-dir=} ;;
    --config-dir=*) config_dir=${argument#--config-dir=} ;;
    '') ;;
    *) printf 'Core-live 参数无效: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

case "$route" in
  direct|webvpn) ;;
  *) printf '%s\n' 'Core-live 必须指定 route=direct 或 route=webvpn' >&2; exit 2 ;;
esac

if ! ubaa_live_feature_supported "$feature"; then
  printf 'Core-live 不支持 feature=%s\n' "$feature" >&2
  exit 2
fi

if [[ ! -d "$repo_root" ]]; then
  printf '%s\n' '仓库目录不可用' >&2
  exit 2
fi

if [[ -z "$config_dir" ]]; then
  config_dir=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-core-live.XXXXXX")
  cleanup_config=yes
else
  cleanup_config=no
fi

cleanup_config_dir() {
  if [[ ${cleanup_config:-no} == yes && -n ${config_dir:-} ]]; then
    rm -rf -- "$config_dir" || true
  fi
}

# 统一使用 EXIT 收尾；信号先转为退出，再由 EXIT 删除自动创建的目录。
trap cleanup_config_dir EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [[ ! -x "$binary" || ${UBAA_CORE_LIVE_BUILD:-yes} == yes ]]; then
  cargo build --locked --quiet --manifest-path "$repo_root/Cargo.toml" -p ubaa-cli --bin core-live
fi

if "$binary" \
  --route "$route" \
  --feature "$feature" \
  --config-dir "$config_dir" \
  --date "$date_value" \
  --campus-id "$campus_id" \
  --username-stdin \
  --password-stdin; then
  status=0
else
  status=$?
fi
exit "$status"
