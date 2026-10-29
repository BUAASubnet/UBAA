#!/usr/bin/env bash
# 仅使用已准备且版本一致的开发工具；从不隐式安装或联网。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=environment.sh
source "$script_dir/environment.sh"
if [[ ! -x "$quality_python" ]]; then
  printf '%s\n' 'error: 固定开发工具未准备；请显式执行 just quality-tools-bootstrap' >&2
  exit 2
fi
"$quality_python" - "$quality_requirements" <<'PY'
import importlib.metadata
from pathlib import Path
import re
import sys
for name, version in re.findall(r'^([A-Za-z0-9_-]+)==([^\s]+)', Path(sys.argv[1]).read_text(), re.M):
    try:
        actual = importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        actual = '缺失'
    if actual != version:
        raise SystemExit(f'error: 开发工具 {name} 版本不符；请执行 just quality-tools-bootstrap')
PY
export PYTHONDONTWRITEBYTECODE=1
exec "$quality_python" "$@"
