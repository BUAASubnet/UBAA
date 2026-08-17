#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-}
mode=${mode#mode=}

case "$mode" in
  direct|webvpn) ;;
  *)
    echo "usage: $0 direct|webvpn" >&2
    exit 2
    ;;
esac

env_file="$repo_root/.env.local"
if [[ ! -f "$env_file" ]]; then
  echo "live verification requires .env.local (kept outside Git)" >&2
  exit 2
fi

read_env_value() {
  local key=$1
  local value
  value=$(awk -v key="$key" '
    $0 ~ /^[[:space:]]*#/ { next }
    $1 ~ ("^" key "=") {
      sub(/^[[:space:]]*/, "")
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$env_file")
  value=${value%$'\r'}
  if [[ ${#value} -ge 2 && ${value:0:1} == "\"" && ${value: -1} == "\"" ]]; then
    value=${value:1:${#value}-2}
  elif [[ ${#value} -ge 2 && ${value:0:1} == "'" && ${value: -1} == "'" ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s' "$value"
}

username=$(read_env_value UBAA_TEST_USERNAME)
password=$(read_env_value UBAA_TEST_PASSWORD)
if [[ -z "$username" || -z "$password" ]]; then
  unset password
  echo "live verification requires non-empty UBAA_TEST_USERNAME and UBAA_TEST_PASSWORD" >&2
  exit 2
fi

build_log=$(mktemp)
trap 'rm -f "$build_log"; unset password username' EXIT
if ! cargo build --quiet --manifest-path "$repo_root/Cargo.toml" -p ubaa-cli >"$build_log" 2>&1; then
  rm -f "$build_log"
  echo "mode=$mode outcome=failed stage=build error=build_failed" >&2
  exit 1
fi
rm -f "$build_log"

binary="$repo_root/target/debug/ubaa"
config_dir=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-live.XXXXXX")
chmod 700 "$config_dir"
trap 'rm -rf "$config_dir"; unset password username' EXIT

run_json() {
  local stdin_value=$1
  shift
  local started ended
  started=$(date +%s%N)
  set +e
  if [[ "$stdin_value" == password ]]; then
    CLI_OUTPUT=$(printf '%s\n' "$password" | "$binary" --json --config-dir "$config_dir" "$@" 2>/dev/null)
  else
    CLI_OUTPUT=$("$binary" --json --config-dir "$config_dir" "$@" 2>/dev/null)
  fi
  CLI_CODE=$?
  set -e
  ended=$(date +%s%N)
  CLI_ELAPSED_MS=$(( (ended - started) / 1000000 ))
}

redacted_failure() {
  local stage=$1
  local code=unknown
  code=$(jq -r '.error.code // "invalid_output"' <<<"$CLI_OUTPUT" 2>/dev/null || true)
  printf 'mode=%s outcome=failed stage=%s exit_code=%s error=%s\n' \
    "$mode" "$stage" "$CLI_CODE" "$code"
}

run_json password auth login --mode "$mode" --username "$username" --password-stdin
if [[ "$CLI_CODE" -ne 0 ]]; then
  redacted_failure login
  exit "$CLI_CODE"
fi
if ! jq -e '.ok == true and (.data | type == "object")' >/dev/null 2>&1 <<<"$CLI_OUTPUT"; then
  printf 'mode=%s outcome=failed stage=login exit_code=0 error=invalid_json\n' "$mode"
  exit 1
fi

name_present=$(jq -r 'if (.data.name // "") != "" then "yes" else "no" end' <<<"$CLI_OUTPUT")
school_id_present=$(jq -r 'if (.data.schoolId // "") != "" then "yes" else "no" end' <<<"$CLI_OUTPUT")
if [[ "$name_present" != yes || "$school_id_present" != yes ]]; then
  printf 'mode=%s outcome=failed stage=login exit_code=0 error=missing_user_fields\n' "$mode"
  exit 1
fi

run_json none user show
if [[ "$CLI_CODE" -ne 0 ]]; then
  redacted_failure user_show
  exit "$CLI_CODE"
fi
if ! jq -e '.ok == true and (.data | type == "object")' >/dev/null 2>&1 <<<"$CLI_OUTPUT"; then
  printf 'mode=%s outcome=failed stage=user_show exit_code=0 error=invalid_json\n' "$mode"
  exit 1
fi

run_json none auth status
if [[ "$CLI_CODE" -ne 0 ]]; then
  redacted_failure auth_status
  exit "$CLI_CODE"
fi
if ! jq -e '.ok == true and (.data.user.name // "") != "" and (.data.user.schoolId // "") != ""' \
  >/dev/null 2>&1 <<<"$CLI_OUTPUT"; then
  printf 'mode=%s outcome=failed stage=auth_status exit_code=0 error=missing_status_fields\n' "$mode"
  exit 1
fi

name_prefix=$(jq -r '.data.user.name | strings | .[0:1]' <<<"$CLI_OUTPUT")
school_suffix=$(jq -r '.data.user.schoolId | strings | .[-2:]' <<<"$CLI_OUTPUT")
printf 'mode=%s outcome=success stage=auth_status exit_code=0 elapsed_ms=%s parsed_user=yes name_prefix=%s school_id_suffix=%s\n' \
  "$mode" "$CLI_ELAPSED_MS" "$name_prefix" "$school_suffix"
