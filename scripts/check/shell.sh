#!/usr/bin/env bash
# 检查仓库 Shell；宽松模式允许缺少 ShellCheck，严格模式必须执行 ShellCheck。
set -euo pipefail

mode=${1:-lenient}
case "$mode" in
  lenient|strict) ;;
  *)
    printf 'error: 不支持的 Shell 检查模式：%s\n' "$mode" >&2
    exit 2
    ;;
esac

while IFS= read -r -d '' script; do
  [[ -f "$script" ]] || continue
  case "$script" in
    packages/ubaa_bindings/cargokit/*) continue ;;
  esac
  bash -n "$script"
done < <(git ls-files --cached --others --exclude-standard -z -- '*.sh')

shellcheck_bin=${UBAA_SHELLCHECK_BIN:-}
if [[ -z "$shellcheck_bin" ]]; then
  shellcheck_bin=$(command -v shellcheck || true)
fi
if [[ -z "$shellcheck_bin" || ! -x "$shellcheck_bin" ]]; then
  if [[ "$mode" == strict ]]; then
    printf '%s\n' 'error: 严格门禁要求 ShellCheck，但当前环境未提供可执行文件' >&2
    exit 1
  fi
  printf '%s\n' 'SKIP: ShellCheck 未执行（当前环境未安装）'
  exit 0
fi

if [[ "$mode" == strict ]]; then
  set +e
  shellcheck_version_output=$("$shellcheck_bin" --version 2>/dev/null)
  shellcheck_version_status=$?
  set -e
  shellcheck_version=$(awk '/^version:/ { print $2; exit }' <<<"$shellcheck_version_output")
  shellcheck_version=${shellcheck_version:-unknown}
  if [[ $shellcheck_version_status -ne 0 || "$shellcheck_version" != 0.11.0 ]]; then
    printf 'error: 严格门禁要求 ShellCheck 版本 0.11.0，检测到 %s\n' \
      "$shellcheck_version" >&2
    exit 1
  fi
fi

while IFS= read -r -d '' script; do
  [[ -f "$script" ]] || continue
  case "$script" in
    packages/ubaa_bindings/cargokit/*) continue ;;
  esac
  "$shellcheck_bin" -x -P SCRIPTDIR "$script"
done < <(git ls-files --cached --others --exclude-standard -z -- '*.sh')
