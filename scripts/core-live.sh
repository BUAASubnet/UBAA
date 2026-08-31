#!/usr/bin/env bash
# Core-live 二进制启动器：只负责参数校验、构建和 stdin 转发。
{ set +x; } 2>/dev/null
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
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

case "$feature" in
  all|auth|user|schedule|exam|grades|classroom|spoc|judge|signin|ygdk|libbook|bykc|cgyy|evaluation) ;;
  *) printf 'Core-live 不支持 feature=%s\n' "$feature" >&2; exit 2 ;;
esac

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
trap 'if [[ ${cleanup_config:-no} == yes ]]; then rm -rf -- "$config_dir"; fi' EXIT

if [[ ! -x "$binary" || ${UBAA_CORE_LIVE_BUILD:-yes} == yes ]]; then
  cargo build --locked --quiet --manifest-path "$repo_root/Cargo.toml" -p ubaa-cli --bin core-live
fi

exec "$binary" \
  --route "$route" \
  --feature "$feature" \
  --config-dir "$config_dir" \
  --date "$date_value" \
  --campus-id "$campus_id" \
  --username-stdin \
  --password-stdin
