#!/usr/bin/env bash
# 显式联网建立缺失冻结引用；已有路径只校验，不覆盖、不拉取、不规范化。
set -euo pipefail

references_bootstrap_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../check/references.sh
source "$references_bootstrap_dir/../check/references.sh"

cleanup_reference_temp() {
  local temp_path=$1
  local parent=$2
  local reference_name=$3
  local temp_name

  if [[ -z "$temp_path" || ! -e "$temp_path" ]]; then
    return 0
  fi
  temp_name=$(basename "$temp_path")
  if [[ $(dirname "$temp_path") != "$parent" || "$temp_name" != ".ubaa-reference.$reference_name."* ]]; then
    printf 'error: 拒绝清理未验证的临时路径：%s\n' "$temp_path" >&2
    return 1
  fi
  rm -rf -- "$temp_path"
}

bootstrap_reference() (
  local root=$1
  local path=$2
  local remote=$3
  local commit=$4
  local label=${path#"$root"/}

  if [[ -d "$path/.git" ]]; then
    check_reference "$root" "$path" "$remote" "$commit"
    return
  fi
  if [[ -e "$path" ]]; then
    printf 'error: 冻结引用路径存在但不是 Git 仓库：%s\n' "$label" >&2
    return 1
  fi

  local parent reference_name temp_path status
  parent=$(dirname "$path")
  reference_name=$(basename "$path")
  mkdir -p "$parent"
  parent=$(cd "$parent" && pwd)
  temp_path=$(mktemp -d "$parent/.ubaa-reference.$reference_name.XXXXXX")
  trap 'cleanup_reference_temp "$temp_path" "$parent" "$reference_name"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  printf '正在临时目录建立冻结引用：%s\n' "$label"
  if git clone --no-checkout "$remote" "$temp_path"; then
    :
  else
    status=$?
    cleanup_reference_temp "$temp_path" "$parent" "$reference_name"
    return "$status"
  fi
  if git -C "$temp_path" fetch --depth 1 origin "$commit"; then
    :
  else
    status=$?
    cleanup_reference_temp "$temp_path" "$parent" "$reference_name"
    return "$status"
  fi
  if git -C "$temp_path" checkout --detach "$commit"; then
    :
  else
    status=$?
    cleanup_reference_temp "$temp_path" "$parent" "$reference_name"
    return "$status"
  fi
  if check_reference "$root" "$temp_path" "$remote" "$commit" >/dev/null; then
    :
  else
    status=$?
    cleanup_reference_temp "$temp_path" "$parent" "$reference_name"
    return "$status"
  fi
  if [[ -e "$path" ]]; then
    printf 'error: 冻结引用目标在 bootstrap 期间出现：%s\n' "$label" >&2
    cleanup_reference_temp "$temp_path" "$parent" "$reference_name"
    return 1
  fi
  if mv "$temp_path" "$path"; then
    temp_path=
  else
    status=$?
    cleanup_reference_temp "$temp_path" "$parent" "$reference_name"
    return "$status"
  fi

  printf '已建立冻结引用：%s @ %s\n' "$label" "$commit"
)

bootstrap_references_main() {
  local repo_root
  repo_root=$(ubaa_repo_root)
  bootstrap_reference \
    "$repo_root" \
    "$repo_root/ubaa_old" \
    'https://github.com/BUAASubnet/UBAA.git' \
    '6e75e120a26b0eefb3ab4a6f8251d1230db4a62e'
  bootstrap_reference \
    "$repo_root" \
    "$repo_root/examples/buaa-api" \
    'https://github.com/fontlos/buaa-api.git' \
    'efb7976bf513f38364b88aeb83d704586cff9b2a'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  bootstrap_references_main "$@"
fi
