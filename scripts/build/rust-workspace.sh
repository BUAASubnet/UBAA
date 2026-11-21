#!/usr/bin/env bash
set -euo pipefail

mode=${1:?缺少 Rust 检查模式}
shift

cargo_packages=()
if (($#)); then
  for package in "$@"; do
    if [[ "$mode" == risk && "$package" == ubaa-core ]]; then
      continue
    fi
    cargo_packages+=(--package "$package")
  done
  if [[ ${#cargo_packages[@]} == 0 ]]; then
    exit 0
  fi
elif [[ "$mode" == risk ]]; then
  cargo_packages+=(--workspace --exclude ubaa-core)
else
  cargo_packages+=(--workspace)
fi

case "$mode" in
  clippy)
    cargo clippy --locked "${cargo_packages[@]}" --all-targets -- -D warnings
    ;;
  test|risk)
    cargo test --locked "${cargo_packages[@]}"
    ;;
  *)
    printf '未知的 Rust 检查模式：%s\n' "$mode" >&2
    exit 2
    ;;
esac
