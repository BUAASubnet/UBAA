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

restore_human_tty() {
  if [[ ${human_tty_configured:-no} == yes ]]; then
    stty "$human_tty_state" <"$human_tty_path" 2>/dev/null || true
    human_tty_configured=no
    human_tty_path=
    human_tty_state=
  fi
}

run_human_login() {
  local tty_path=$1
  local started ended
  local captcha_answer read_code
  started=$(date +%s)
  human_input_fifo="$config_dir/.human-input.$$"
  if ! mkfifo -m 600 "$human_input_fifo"; then
    CLI_CODE=7
    return 1
  fi
  human_tty_path=
  human_tty_state=
  human_tty_configured=no
  if [[ -c "$tty_path" ]]; then
    human_tty_path=$tty_path
    if ! human_tty_state=$(stty -g <"$tty_path" 2>/dev/null) || \
      ! stty -echo <"$tty_path" 2>/dev/null; then
      rm -f -- "$human_input_fifo"
      human_input_fifo=
      human_tty_path=
      human_tty_state=
      CLI_CODE=7
      return 1
    fi
    human_tty_configured=yes
  fi

  "$binary" --config-dir "$config_dir" auth login --mode "$mode" \
    --username "$username" --password-stdin <"$human_input_fifo" >/dev/null &
  human_binary_pid=$!
  if ! exec 9>"$human_input_fifo"; then
    cleanup_human_login
    CLI_CODE=7
    return 1
  fi
  human_input_open=yes

  if printf '%s\n' "$password" >&9; then
    while kill -0 "$human_binary_pid" 2>/dev/null; do
      captcha_answer=
      if IFS= read -r -s -t 1 captcha_answer <"$tty_path"; then
        printf '\n' >"$tty_path"
        if ! printf '%s\n' "$captcha_answer" >&9; then
          break
        fi
        if [[ -n "$captcha_answer" ]]; then
          break
        fi
      else
        read_code=$?
        if [[ "$read_code" -eq 1 ]]; then
          break
        fi
      fi
    done
  fi
  unset captcha_answer
  exec 9>&-
  human_input_open=no
  restore_human_tty

  if wait "$human_binary_pid"; then
    CLI_CODE=0
  else
    CLI_CODE=$?
  fi
  human_binary_pid=
  rm -f -- "$human_input_fifo"
  human_input_fifo=
  ended=$(date +%s)
  CLI_ELAPSED_MS=$(( (ended - started) * 1000 ))
  [[ "$CLI_CODE" -eq 0 ]]
}

cleanup_human_login() {
  local attempt
  if [[ ${human_input_open:-no} == yes ]]; then
    exec 9>&- 2>/dev/null || true
    human_input_open=no
  fi
  restore_human_tty
  if [[ -n ${human_binary_pid:-} ]]; then
    kill -TERM "$human_binary_pid" 2>/dev/null || true
    for attempt in {1..20}; do
      if ! kill -0 "$human_binary_pid" 2>/dev/null; then
        break
      fi
      sleep 0.05
    done
    if kill -0 "$human_binary_pid" 2>/dev/null; then
      kill -KILL "$human_binary_pid" 2>/dev/null || true
    fi
    wait "$human_binary_pid" 2>/dev/null || true
    human_binary_pid=
  fi
  if [[ -n ${human_input_fifo:-} ]]; then
    rm -f -- "$human_input_fifo"
    human_input_fifo=
  fi
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
  cleanup_human_login
  if [[ -n ${build_log:-} ]]; then
    rm -f -- "$build_log"
  fi
  if [[ -n ${config_dir:-} ]]; then
    rm -rf -- "$config_dir"
  fi
  unset password username
}

install_cleanup_traps() {
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
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
  human_input_fifo=
  human_binary_pid=
  human_input_open=no
  human_tty_path=
  human_tty_state=
  human_tty_configured=no
  install_cleanup_traps
  if ! cargo build --locked --quiet --manifest-path "$repo_root/Cargo.toml" -p ubaa-cli >"$build_log" 2>&1; then
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
