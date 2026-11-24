#!/usr/bin/env bash
set -euo pipefail

package_dir=${1:?缺少 npm 包目录}
lock_file="$package_dir/package-lock.json"
node_modules="$package_dir/node_modules"
marker="$node_modules/.ubaa-npm-ci"

if [[ ! -f "$lock_file" ]]; then
  printf '缺少 npm 锁文件：%s\n' "$lock_file" >&2
  exit 2
fi

if [[ -n "${CI+x}" || ! -d "$node_modules" || ! -f "$marker" || "$lock_file" -nt "$marker" ]]; then
  npm --prefix "$package_dir" ci --no-audit --no-fund
  mkdir -p "$node_modules"
  touch "$marker"
fi
