#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

candidate_files=$(git ls-files --cached --others --exclude-standard)
forbidden_paths=$(printf '%s\n' "$candidate_files" | rg '(^|/)(ubaa_old|examples)(/|$)|(^|/)\.env\.local$|(^|/)(session\.json|.*\.session\.json)$' || true)
if [[ -n "$forbidden_paths" ]]; then
  printf 'forbidden sensitive path is tracked:\n%s\n' "$forbidden_paths" >&2
  exit 1
fi

patterns=(
  "UBAA_TEST_(USERNAME|PASSWORD)=[\"']?[[:alnum:]]"
  '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----'
  '\b1[3-9][0-9]{9}\b'
  'data:image/(png|jpe?g|gif);base64,[A-Za-z0-9+/]{24,}={0,2}'
  'gh[pousr]_[A-Za-z0-9]{36,}'
  'AKIA[0-9A-Z]{16}'
)
for pattern in "${patterns[@]}"; do
  matches=$(git ls-files --cached --others --exclude-standard -z | xargs -0 rg -n --hidden --no-messages -- "$pattern" || true)
  if [[ -n "$matches" ]]; then
    printf 'possible sensitive content matched %s:\n%s\n' "$pattern" "$matches" >&2
    exit 1
  fi
done

printf 'sensitive scan passed: %s repository files checked\n' "$(printf '%s\n' "$candidate_files" | awk 'NF { count++ } END { print count + 0 }')"
