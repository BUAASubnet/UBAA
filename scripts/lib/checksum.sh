# shellcheck shell=bash
# macOS/BSD 与 GNU 使用相同 SHA-256 输出格式。
ubaa_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$@"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    printf 'error: 缺少 shasum 或 sha256sum，无法生成摘要\n' >&2
    return 1
  fi
}
