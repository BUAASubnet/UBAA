# shellcheck shell=bash
# 只加载受跟踪的静态版本数据，不读取任何本地凭据或 SDK 路径。
ubaa_versions_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../tools/versions.env
source "$ubaa_versions_dir/../tools/versions.env"
unset ubaa_versions_dir
