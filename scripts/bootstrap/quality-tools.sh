#!/usr/bin/env bash
# 显式联网准备固定开发依赖；不修改产品依赖或系统 Python。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../tools/environment.sh
source "$script_dir/../tools/environment.sh"
python3 -m venv "$quality_root"
"$quality_python" -m pip install --disable-pip-version-check --require-hashes \
  --only-binary=:all: --index-url https://pypi.org/simple -r "$quality_requirements"
bash "$script_dir/../tools/python.sh" -c 'print("固定开发工具已准备；后续检查离线运行")'
