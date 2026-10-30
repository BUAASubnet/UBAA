#!/usr/bin/env bash
# 显式联网准备本机开发环境：按 versions.env 安装缺失的锁定工具，已一致的项直接跳过。
# 不改写已有 SDK、不修改 .env.toolchain、不安装系统包，最后运行只读的 doctor。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
# shellcheck source=../lib/versions.sh
source "$script_dir/../lib/versions.sh"
repo_root=$(ubaa_repo_root)
cd "$repo_root"

if [[ ! -f .env.toolchain ]]; then
  cp .env.toolchain.example .env.toolchain
  printf '%s\n' '已从模板创建 .env.toolchain；请填写 UBAA_FLUTTER_HOME 等 SDK 位置后重新运行 just setup' >&2
  exit 2
fi
eval "$(python3 scripts/lib/toolchain.py shell)"
export PATH="$HOME/.cargo/bin:$PATH"

flutter_root=${UBAA_FLUTTER_HOME:-}
if [[ -z "$flutter_root" || "$flutter_root" != /* || "$flutter_root" == *'<'* ]]; then
  printf '%s\n' 'error: 请在 .env.toolchain 中把 UBAA_FLUTTER_HOME 设为绝对路径' >&2
  exit 2
fi
if [[ ! -e "$flutter_root" ]]; then
  printf '安装官方 Flutter %s\n' "$FLUTTER_VERSION"
  git clone --branch "$FLUTTER_VERSION" --depth 1 "$FLUTTER_REMOTE" "$flutter_root"
  git -C "$flutter_root" checkout --detach "$FLUTTER_COMMIT"
elif [[ "$(git -C "$flutter_root" rev-parse HEAD 2>/dev/null)" != "$FLUTTER_COMMIT" ]]; then
  printf 'error: UBAA_FLUTTER_HOME 已存在但不是锁定提交 %s；不会改写已有 SDK\n' "$FLUTTER_COMMIT" >&2
  exit 1
fi

rustup toolchain install "$RUST_VERSION" --profile minimal --component rustfmt --component clippy

install_cargo_tool() {
  local crate=$1 version=$2 binary=$3
  if [[ "$("$binary" --version 2>/dev/null || true)" == *" $version" ]]; then
    printf '%s %s 已安装\n' "$crate" "$version"
    return
  fi
  cargo install --locked "$crate" --version "=$version"
}
install_cargo_tool cargo-expand "$CARGO_EXPAND_VERSION" cargo-expand
install_cargo_tool flutter_rust_bridge_codegen "$FRB_VERSION" "${UBAA_FRB_CODEGEN:-flutter_rust_bridge_codegen}"
install_cargo_tool cargo-deny "$CARGO_DENY_VERSION" cargo-deny

just refs-bootstrap
just quality-tools-bootstrap
cargo fetch --locked
just flutter-dependencies

if ! command -v "${UBAA_SHELLCHECK_BIN:-shellcheck}" >/dev/null 2>&1; then
  printf 'ShellCheck %s 需用系统包管理器安装，或在 .env.toolchain 设置 UBAA_SHELLCHECK_BIN\n' "$SHELLCHECK_VERSION"
fi
python3 scripts/bootstrap/doctor.py
