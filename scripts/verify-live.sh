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
  local route_value=${route:-$mode}
  local feature_value=${feature:-auth}
  local code=unknown
  code=$(jq -r '.error.code // "invalid_output"' <<<"$CLI_OUTPUT" 2>/dev/null || true)
  printf 'mode=%s route=%s feature=%s outcome=failed stage=%s exit_code=%s error=%s\n' \
    "$mode" "$route_value" "$feature_value" "$stage" "$CLI_CODE" "$code"
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
    if ! human_tty_state=$(stty -g <"$tty_path" 2>/dev/null); then
      rm -f -- "$human_input_fifo"
      human_input_fifo=
      human_tty_path=
      human_tty_state=
      CLI_CODE=7
      return 1
    fi
    human_tty_configured=yes
    if ! stty -echo <"$tty_path" 2>/dev/null; then
      restore_human_tty
      rm -f -- "$human_input_fifo"
      human_input_fifo=
      CLI_CODE=7
      return 1
    fi
  fi

  if [[ "${route:-$mode}" == auto ]]; then
    "$binary" --config-dir "$config_dir" auth login --username "$username" \
      --password-stdin <"$human_input_fifo" >/dev/null &
  else
    "$binary" --config-dir "$config_dir" auth login --mode "$mode" \
      --username "$username" --password-stdin <"$human_input_fifo" >/dev/null &
  fi
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
  local route_value=${route:-$mode}
  local feature_value=${feature:-auth}
  LOGIN_USED_HUMAN=no
  if [[ "${route:-$mode}" == auto ]]; then
    run_json password auth login --username "$username" --password-stdin
  else
    run_json password auth login --mode "$mode" --username "$username" --password-stdin
  fi
  if [[ "$CLI_CODE" -eq 0 ]]; then
    return 0
  fi
  if [[ "$CLI_CODE" -ne 4 ]]; then
    redacted_failure login
    return "$CLI_CODE"
  fi
  if ! tty_available "$tty_path"; then
    printf 'mode=%s route=%s feature=%s outcome=failed stage=login exit_code=4 error=captcha_required_noninteractive\n' "$mode" "$route_value" "$feature_value"
    return 4
  fi
  if ! run_human_login "$tty_path"; then
    printf 'mode=%s route=%s feature=%s outcome=failed stage=login_human exit_code=%s error=human_login_failed\n' \
      "$mode" "$route_value" "$feature_value" "$CLI_CODE"
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
  feature=auth
  route=auto
  mode=
  for argument in "$@"; do
    case "$argument" in
      feature=*) feature=${argument#feature=} ;;
      route=*) route=${argument#route=} ;;
      mode=*) mode=${argument#mode=} ;;
      direct|webvpn) mode=$argument; route=$argument ;;
      '') ;;
      *)
        echo "usage: $0 [direct|webvpn] [feature=auth|all|schedule|exam|grades|classroom|spoc|judge] [route=auto|direct|webvpn]" >&2
        exit 2
        ;;
    esac
  done
  if [[ -n "$mode" && "$route" == auto ]]; then
    route=$mode
  fi
  if [[ -z "$mode" ]]; then
    mode=$route
  fi

  case "$feature" in
    auth|all|schedule|exam|grades|classroom|spoc|judge) ;;
    *) echo "unsupported feature: $feature" >&2; exit 2 ;;
  esac
  case "$route" in
    direct|webvpn|auto) ;;
    *) echo "unsupported route: $route" >&2; exit 2 ;;
  esac
  if [[ "$route" == auto ]]; then
    mode=auto
  fi

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
  printf 'schema_version = 1\n\n[route]\ndefault = "%s"\n' "$route" >"$config_dir/config.toml"
  chmod 600 "$config_dir/config.toml"
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
    printf 'mode=%s route=%s feature=%s outcome=failed stage=login exit_code=0 error=invalid_json\n' "$mode" "$route" "$feature"
      exit 1
    fi

    name_present=$(jq -r 'if (.data.name // .data.profile.name // "") != "" then "yes" else "no" end' <<<"$CLI_OUTPUT")
    school_id_present=$(jq -r 'if (.data.schoolId // .data.profile.schoolId // "") != "" then "yes" else "no" end' <<<"$CLI_OUTPUT")
    if [[ "$name_present" != yes || "$school_id_present" != yes ]]; then
      printf 'mode=%s route=%s feature=%s outcome=failed stage=login exit_code=0 error=missing_user_fields\n' "$mode" "$route" "$feature"
      exit 1
    fi
  fi

  if [[ "$feature" != auth ]]; then
    run_readonly_feature
    exit "$CLI_CODE"
  fi

  run_json none user show
  if [[ "$CLI_CODE" -ne 0 ]]; then
    redacted_failure user_show
    exit "$CLI_CODE"
  fi
  if ! jq -e '.ok == true and (.data | type == "object")' >/dev/null 2>&1 <<<"$CLI_OUTPUT"; then
    printf 'mode=%s route=%s feature=%s outcome=failed stage=user_show exit_code=0 error=invalid_json\n' "$mode" "$route" "$feature"
    exit 1
  fi

  run_json none auth status
  if [[ "$CLI_CODE" -ne 0 ]]; then
    redacted_failure auth_status
    exit "$CLI_CODE"
  fi
  if ! jq -e '.ok == true and ((.data.user.name // .data.profile.name // "") != "") and ((.data.user.schoolId // .data.profile.schoolId // "") != "")' \
    >/dev/null 2>&1 <<<"$CLI_OUTPUT"; then
    printf 'mode=%s route=%s feature=%s outcome=failed stage=auth_status exit_code=0 error=missing_status_fields\n' "$mode" "$route" "$feature"
    exit 1
  fi

  printf 'mode=%s outcome=success stage=auth_status exit_code=0 route=%s feature=%s elapsed_ms=%s parsed_user=yes\n' \
    "$mode" "$route" "$feature" "$CLI_ELAPSED_MS"
}

run_readonly_feature() {
  local term week date campus count original_feature subfeature
  if [[ "$feature" == all ]]; then
    original_feature=$feature
    local first_failure=0
    for subfeature in schedule exam grades classroom spoc judge; do
      feature=$subfeature
      if ! run_readonly_feature; then
        if [[ "$first_failure" -eq 0 ]]; then
          first_failure=${CLI_CODE:-1}
        fi
      fi
    done
    feature=$original_feature
    if [[ "$first_failure" -ne 0 ]]; then
      CLI_CODE=$first_failure
      printf 'mode=%s route=%s feature=all outcome=failed stage=all exit_code=%s error=one_or_more_features_failed\n' "$mode" "$route" "$CLI_CODE"
      return "$CLI_CODE"
    fi
    CLI_CODE=0
    printf 'mode=%s route=%s feature=all outcome=success stage=all exit_code=0\n' "$mode" "$route"
    return 0
  fi
  case "$feature" in
    schedule)
      run_json none schedule terms
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_terms; return "$CLI_CODE"; fi
      term=$(jq -r '([.data[] | select(.selected == true)] | if length == 1 then .[0].itemCode else empty end) // .data[0].itemCode // empty' <<<"$CLI_OUTPUT")
      [[ -n "$term" ]] || { printf 'mode=%s route=%s feature=%s outcome=failed stage=schedule_terms exit_code=1 error=empty_terms\n' "$mode" "$route" "$feature"; return 1; }
      run_json none schedule weeks --term "$term"
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_weeks; return "$CLI_CODE"; fi
      week=$(jq -r '([.data[] | select(.curWeek == true)] | if length == 1 then .[0].serialNumber else empty end) // .data[0].serialNumber // empty' <<<"$CLI_OUTPUT")
      [[ "$week" =~ ^[1-9][0-9]*$ ]] || { printf 'mode=%s route=%s feature=%s outcome=failed stage=schedule_weeks exit_code=1 error=empty_weeks\n' "$mode" "$route" "$feature"; return 1; }
      run_json none schedule current --term "$term" --week "$week"
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_current; return "$CLI_CODE"; fi
      run_json none schedule today
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_today; return "$CLI_CODE"; fi
      printf 'mode=%s route=%s feature=%s outcome=success stage=schedule exit_code=0 term_present=yes week=%s\n' "$mode" "$route" "$feature" "$week"
      ;;
    exam|grades)
      run_json none schedule terms
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_terms; return "$CLI_CODE"; fi
      term=$(jq -r '([.data[] | select(.selected == true)] | if length == 1 then .[0].itemCode else empty end) // .data[0].itemCode // empty' <<<"$CLI_OUTPUT")
      [[ -n "$term" ]] || { printf 'mode=%s route=%s feature=%s outcome=failed stage=schedule_terms exit_code=1 error=empty_terms\n' "$mode" "$route" "$feature"; return 1; }
      if [[ "$feature" == exam ]]; then
        run_json none exam list --term "$term"
      else
        run_json none grades list --term "$term"
      fi
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure "$feature"; return "$CLI_CODE"; fi
      printf 'mode=%s route=%s feature=%s outcome=success stage=%s exit_code=0 term_present=yes\n' "$mode" "$route" "$feature" "$feature"
      ;;
    classroom)
      date=${UBAA_VERIFY_DATE:-$(TZ=Asia/Shanghai date +%F)}
      campus=${UBAA_VERIFY_CAMPUS_ID:-1}
      run_json none classroom search --campus "$campus" --date "$date"
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure classroom; return "$CLI_CODE"; fi
      count=$(jq -r '[.data.floors[]?[]?] | length' <<<"$CLI_OUTPUT" 2>/dev/null || printf '0')
      printf 'mode=%s route=%s feature=%s outcome=success stage=classroom exit_code=0 result_count=%s date=%s\n' "$mode" "$route" "$feature" "$count" "$date"
      ;;
    spoc)
      run_json none spoc assignments
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure spoc; return "$CLI_CODE"; fi
      count=$(jq -r '.data.assignments | length' <<<"$CLI_OUTPUT" 2>/dev/null || printf '0')
      if [[ "$count" -gt 0 ]]; then
        local assignment_id
        assignment_id=$(jq -r '.data.assignments[0].assignmentId // empty' <<<"$CLI_OUTPUT")
        run_json none spoc assignment show --id "$assignment_id"
        if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure spoc_detail; return "$CLI_CODE"; fi
      fi
      printf 'mode=%s route=%s feature=%s outcome=success stage=spoc exit_code=0 result_count=%s\n' "$mode" "$route" "$feature" "$count"
      ;;
    judge)
      run_json none judge assignments
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure judge; return "$CLI_CODE"; fi
      count=$(jq -r '.data | length' <<<"$CLI_OUTPUT" 2>/dev/null || printf '0')
      if [[ "$count" -gt 0 ]]; then
        local course_id assignment_id
        # The first returned assignment is the verifier's single detail sample.
        # A later list can change while the separate detail CLI process starts;
        # choosing the first response item avoids inventing a stale-ID contract.
        course_id=$(jq -r '.data[0].courseId // empty' <<<"$CLI_OUTPUT")
        assignment_id=$(jq -r '.data[0].assignmentId // empty' <<<"$CLI_OUTPUT")
        run_json none judge assignment show --course-id "$course_id" --id "$assignment_id"
        if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure judge_detail; return "$CLI_CODE"; fi
      fi
      printf 'mode=%s route=%s feature=%s outcome=success stage=judge exit_code=0 result_count=%s\n' "$mode" "$route" "$feature" "$count"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
