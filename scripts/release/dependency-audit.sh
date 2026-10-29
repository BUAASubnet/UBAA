#!/usr/bin/env bash
# 显式联网的 Rust 依赖安全、许可证、重复版本和来源审计。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../tools/versions.env
source "$script_dir/../tools/versions.env"
if ! command -v cargo-deny >/dev/null 2>&1; then
  printf 'error: 缺少 cargo-deny %s；请先安装固定版本后再运行 dependency-audit\n' "$CARGO_DENY_VERSION" >&2
  exit 2
fi
actual=$(cargo-deny --version)
if [[ "$actual" != "cargo-deny $CARGO_DENY_VERSION" ]]; then
  printf 'error: cargo-deny 版本不匹配：需要 %s，实际 %s\n' "$CARGO_DENY_VERSION" "$actual" >&2
  exit 2
fi
# advisories 数据库可能被更新；因此该命令必须由调用方显式承担网络访问。
cargo-deny check
