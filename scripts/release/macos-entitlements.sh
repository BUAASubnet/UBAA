#!/usr/bin/env bash
# macOS 实际签名权限检查函数；正式入口负责传入固定系统工具，测试可传入隔离夹具。

verify_macos_entitlements() (
  set -euo pipefail
  local artifact=${1:-}
  local codesign_bin=${2:-}
  local plist_buddy_bin=${3:-}
  local entitlements_file key value_xml

  if [[ -z "$artifact" || -z "$codesign_bin" || -z "$plist_buddy_bin" ]]; then
    printf '%s\n' 'error: macOS 实际签名权限检查参数不完整' >&2
    return 2
  fi
  if [[ ! -x "$codesign_bin" ]]; then
    printf '%s\n' 'error: 无法读取 macOS 产物的实际签名权限：缺少 codesign' >&2
    return 1
  fi
  if [[ ! -x "$plist_buddy_bin" ]]; then
    printf '%s\n' 'error: 无法解析 macOS 产物的实际签名权限：缺少 PlistBuddy' >&2
    return 1
  fi

  entitlements_file=$(mktemp "${TMPDIR:-/tmp}/ubaa-macos-entitlements.XXXXXX")
  trap 'rm -f -- "$entitlements_file"' EXIT
  if ! "$codesign_bin" --display --entitlements - --xml "$artifact" \
    >"$entitlements_file" 2>/dev/null; then
    printf '%s\n' 'error: 无法读取 macOS 产物的实际签名权限' >&2
    return 1
  fi
  if ! "$plist_buddy_bin" -c Print "$entitlements_file" >/dev/null 2>&1; then
    printf '%s\n' 'error: 无法解析 macOS 产物的实际签名权限' >&2
    return 1
  fi

  for key in \
    com.apple.security.app-sandbox \
    com.apple.security.network.client; do
    if ! value_xml=$("$plist_buddy_bin" -x -c "Print :$key" "$entitlements_file" 2>/dev/null); then
      printf 'error: macOS 产物实际签名权限 %s 必须为 true\n' "$key" >&2
      return 1
    fi
    value_xml=$(LC_ALL=C tr -d '[:space:]' <<<"$value_xml")
    if [[ "$value_xml" != *'<plistversion="1.0"><true/></plist>' ]]; then
      printf 'error: macOS 产物实际签名权限 %s 必须为 true\n' "$key" >&2
      return 1
    fi
  done

  printf '%s\n' 'macOS 产物实际签名权限通过：Sandbox=true network.client=true'
)
