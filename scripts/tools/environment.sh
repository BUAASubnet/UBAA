#!/usr/bin/env bash
# 固定开发工具的环境路径；调用方决定是否显式联网准备。
quality_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/toolchain.sh
source "$quality_script_dir/../lib/toolchain.sh"
quality_requirements="$quality_script_dir/requirements.txt"
quality_key=$(python3 - "$quality_requirements" <<'PY'
import hashlib
from pathlib import Path
import sys
if sys.version_info < (3, 11):
    raise SystemExit('error: 开发工具需要 Python 3.11 或更高版本')
digest = hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()[:16]
print(f'py{sys.version_info.major}.{sys.version_info.minor}-{digest}')
PY
)
quality_root=${UBAA_QUALITY_TOOLS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ubaa2-quality/$quality_key}
if [[ "$quality_root" != /* ]]; then
  printf '%s\n' 'error: UBAA_QUALITY_TOOLS_DIR 必须是绝对路径' >&2
  exit 2
fi
# 由 source 本文件的执行入口消费。
# shellcheck disable=SC2034
quality_python="$quality_root/bin/python"
