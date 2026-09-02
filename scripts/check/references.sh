#!/usr/bin/env bash
# 纯只读校验冻结引用；禁止 clone、fetch、pull 或改写已有引用。
set -euo pipefail

references_check_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$references_check_dir/../lib/repo.sh"

check_reference() {
  local root=$1
  local path=$2
  local expected_remote=$3
  local expected_commit=$4
  local label=${path#"$root"/}

  if [[ ! -d "$path/.git" ]]; then
    if [[ -e "$path" ]]; then
      printf 'error: 冻结引用路径存在但不是 Git 仓库：%s\n' "$label" >&2
    else
      printf 'error: 缺少冻结引用：%s\n' "$label" >&2
    fi
    printf '%s\n' '请显式运行 just refs-bootstrap 建立缺失引用，然后重试 just refs' >&2
    return 1
  fi

  local actual_remote actual_head worktree_status
  if ! actual_remote=$(GIT_OPTIONAL_LOCKS=0 git -C "$path" remote get-url origin 2>/dev/null); then
    printf 'error: 无法读取冻结引用远端：%s\n' "$label" >&2
    return 1
  fi
  if [[ "$actual_remote" != "$expected_remote" ]]; then
    printf 'error: 冻结引用远端不匹配：%s\n期望：%s\n实际：%s\n' \
      "$label" "$expected_remote" "$actual_remote" >&2
    return 1
  fi

  if ! actual_head=$(GIT_OPTIONAL_LOCKS=0 git -C "$path" rev-parse HEAD 2>/dev/null); then
    printf 'error: 无法读取冻结引用提交：%s\n' "$label" >&2
    return 1
  fi
  if [[ "$actual_head" != "$expected_commit" ]]; then
    printf 'error: 冻结引用提交不匹配：%s\n期望：%s\n实际：%s\n' \
      "$label" "$expected_commit" "$actual_head" >&2
    return 1
  fi

  if ! worktree_status=$(GIT_OPTIONAL_LOCKS=0 git -C "$path" status --porcelain 2>/dev/null); then
    printf 'error: 无法读取冻结引用工作树：%s\n' "$label" >&2
    return 1
  fi
  if [[ -n "$worktree_status" ]]; then
    printf 'error: 冻结引用工作树不干净：%s\n' "$label" >&2
    return 1
  fi

  printf '已验证冻结引用：%s @ %s\n' "$label" "$expected_commit"
}

check_references_main() {
  local repo_root
  repo_root=$(ubaa_repo_root)
  check_reference \
    "$repo_root" \
    "$repo_root/ubaa_old" \
    'https://github.com/BUAASubnet/UBAA.git' \
    '6e75e120a26b0eefb3ab4a6f8251d1230db4a62e'
  check_reference \
    "$repo_root" \
    "$repo_root/examples/buaa-api" \
    'https://github.com/fontlos/buaa-api.git' \
    'efb7976bf513f38364b88aeb83d704586cff9b2a'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  check_references_main "$@"
fi
