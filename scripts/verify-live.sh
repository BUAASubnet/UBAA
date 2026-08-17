#!/usr/bin/env bash
set -euo pipefail

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

run_json() {
  local stdin_value=$1
  shift
  local started ended
  started=$(date +%s)
  set +e
  if [[ "$stdin_value" == password ]]; then
    CLI_OUTPUT=$(printf '%s\n' "$password" | "$binary" --json --config-dir "$config_dir" "$@" 2>/dev/null)
  else
    CLI_OUTPUT=$("$binary" --json --config-dir "$config_dir" "$@" 2>/dev/null)
  fi
  CLI_CODE=$?
  set -e
  ended=$(date +%s)
  CLI_ELAPSED_MS=$(( (ended - started) * 1000 ))
}

redacted_failure() {
  local stage=$1
  local code=unknown
  code=$(jq -r '.error.code // "invalid_output"' <<<"$CLI_OUTPUT" 2>/dev/null || true)
  printf 'mode=%s outcome=failed stage=%s exit_code=%s error=%s\n' \
    "$mode" "$stage" "$CLI_CODE" "$code"
}

feed_human_input() {
  local tty_path=$1
  local captcha_answer
  printf '%s\n' "$password"
  while IFS= read -r captcha_answer; do
    printf '%s\n' "$captcha_answer"
    if [[ -n "$captcha_answer" ]]; then
      unset captcha_answer
      return 0
    fi
  done <"$tty_path"
  unset captcha_answer
}

run_human_login() {
  local tty_path=$1
  local started ended
  local pipeline_codes
  started=$(date +%s)
  set +e
  set +o pipefail
  feed_human_input "$tty_path" |
    "$binary" --config-dir "$config_dir" auth login --mode "$mode" \
      --username "$username" --password-stdin >/dev/null
  pipeline_codes=("${PIPESTATUS[@]}")
  set -o pipefail
  set -e
  CLI_CODE=${pipeline_codes[1]:-7}
  ended=$(date +%s)
  CLI_ELAPSED_MS=$(( (ended - started) * 1000 ))
  [[ "$CLI_CODE" -eq 0 ]]
}

tty_available() {
  local tty_path=$1
  [[ -r "$tty_path" && -w "$tty_path" ]] && (exec 9<>"$tty_path") 2>/dev/null
}

login_with_captcha_fallback() {
  local tty_path=$1
  LOGIN_USED_HUMAN=no
  run_json password auth login --mode "$mode" --username "$username" --password-stdin
  if [[ "$CLI_CODE" -eq 0 ]]; then
    return 0
  fi
  if [[ "$CLI_CODE" -ne 4 ]]; then
    redacted_failure login
    return "$CLI_CODE"
  fi
  if ! tty_available "$tty_path"; then
    printf 'mode=%s outcome=failed stage=login exit_code=4 error=captcha_required_noninteractive\n' "$mode"
    return 4
  fi
  if ! run_human_login "$tty_path"; then
    printf 'mode=%s outcome=failed stage=login_human exit_code=%s error=human_login_failed\n' \
      "$mode" "$CLI_CODE"
    return "$CLI_CODE"
  fi
  LOGIN_USED_HUMAN=yes
}

cleanup() {
  if [[ -n ${build_log:-} ]]; then
    rm -f -- "$build_log"
  fi
  if [[ -n ${config_dir:-} ]]; then
    rm -rf -- "$config_dir"
  fi
  unset password username
}

main() {
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

  if ! command -v jq >/dev/null 2>&1; then
    echo "live verification requires jq" >&2
    exit 2
  fi

  env_file="$repo_root/.env.local"
  if [[ ! -f "$env_file" ]]; then
    echo "live verification requires .env.local (kept outside Git)" >&2
    exit 2
  fi

  username=$(read_env_value UBAA_TEST_USERNAME)
  password=$(read_env_value UBAA_TEST_PASSWORD)
  if [[ -z "$username" || -z "$password" ]]; then
    unset password
    echo "live verification requires non-empty UBAA_TEST_USERNAME and UBAA_TEST_PASSWORD" >&2
    exit 2
  fi

  build_log=$(mktemp)
  config_dir=
  trap cleanup EXIT
  if ! cargo build --quiet --manifest-path "$repo_root/Cargo.toml" -p ubaa-cli >"$build_log" 2>&1; then
    echo "mode=$mode outcome=failed stage=build error=build_failed" >&2
    exit 1
  fi
  rm -f -- "$build_log"
  build_log=

  binary="$repo_root/target/debug/ubaa"
  config_dir=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-live.XXXXXX")
  chmod 700 "$config_dir"
  CLI_OUTPUT=
  CLI_CODE=0
  CLI_ELAPSED_MS=0
  LOGIN_USED_HUMAN=no

  if login_with_captcha_fallback /dev/tty; then
    :
  else
    exit "$CLI_CODE"
  fi
  if [[ "$LOGIN_USED_HUMAN" != yes ]]; then
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
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
