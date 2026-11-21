#!/usr/bin/env bash
# 分别统计 index 与工作树的手写源码规模。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
if ! repo_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null); then
  printf '%s\n' 'layout check: 无法从脚本位置定位 Git 仓库' >&2
  exit 1
fi
PYTHONDONTWRITEBYTECODE=1 python3 "$script_dir/../lib/layout.py" "$repo_root"
