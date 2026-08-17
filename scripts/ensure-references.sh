#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

verify_reference() {
  local path=$1
  local remote=$2
  local commit=$3

  if [[ ! -d "$path/.git" ]]; then
    if [[ -e "$path" ]]; then
      echo "reference path exists but is not a Git repository: $path" >&2
      return 1
    fi
    git clone --no-checkout "$remote" "$path"
    git -C "$path" fetch --depth 1 origin "$commit"
    git -C "$path" checkout --detach "$commit"
  fi

  local actual_remote actual_head
  actual_remote=$(git -C "$path" remote get-url origin)
  actual_head=$(git -C "$path" rev-parse HEAD)

  if [[ "$actual_remote" != "$remote" ]]; then
    echo "unexpected origin for $path: $actual_remote" >&2
    return 1
  fi
  if [[ "$actual_head" != "$commit" ]]; then
    echo "unexpected HEAD for $path: $actual_head" >&2
    return 1
  fi
  if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
    echo "reference worktree is dirty: $path" >&2
    return 1
  fi

  echo "verified reference: ${path#"$repo_root"/} @ $commit"
}

verify_reference \
  "$repo_root/ubaa_old" \
  "https://github.com/BUAASubnet/UBAA.git" \
  "6e75e120a26b0eefb3ab4a6f8251d1230db4a62e"
verify_reference \
  "$repo_root/examples/buaa-api" \
  "https://github.com/fontlos/buaa-api.git" \
  "efb7976bf513f38364b88aeb83d704586cff9b2a"

