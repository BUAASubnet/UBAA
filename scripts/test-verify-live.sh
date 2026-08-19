#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-verify-live-test.XXXXXX")
cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

project_root="$test_root/project"
fake_bin="$test_root/bin"
fake_state="$test_root/state"
mkdir -p "$project_root/scripts" "$project_root/target/debug" "$fake_bin" "$fake_state"
cp "$repo_root/scripts/verify-live.sh" "$project_root/scripts/verify-live.sh"
chmod 700 "$project_root/scripts/verify-live.sh"

{
  printf 'UBAA_TEST_%s=%s\n' USERNAME fixture-user
  printf 'UBAA_TEST_%s=%s\n' PASSWORD fixture-password
} >"$project_root/.env.local"

cat >"$fake_bin/cargo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 700 "$fake_bin/cargo"

real_stty=$(command -v stty)
cat >"$fake_bin/stty" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

"$REAL_STTY" "$@"
if [[ " $* " == *" -echo " && -f "$FAKE_STATE_DIR/interrupt-after-echo" ]]; then
  kill -TERM "$PPID"
fi
EOF
chmod 700 "$fake_bin/stty"

cat >"$project_root/target/debug/ubaa" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

arguments=" $* "
if [[ "$arguments" == *" auth login "* && "$arguments" == *" --json "* ]]; then
  IFS= read -r supplied_password
  [[ "$supplied_password" == "fixture-password" ]]
  printf '%s\n' '{"schemaVersion":1,"ok":false,"error":{"code":"captcha_required","kind":"authentication","message":"captcha input is required","retryable":true,"challenge":{"id":"fixture","execution":"e1"}},"meta":{"connectionMode":"direct"}}'
  exit 4
fi

if [[ "$arguments" == *" auth login "* ]]; then
  IFS= read -r supplied_password
  if [[ -f "$FAKE_STATE_DIR/human-login-blocks" ]]; then
    printf '%s\n' "$$" >"$FAKE_STATE_DIR/human-child-pid"
    trap '' HUP
    trap ': >"$FAKE_STATE_DIR/human-child-stopped"' INT TERM
    while :; do
      sleep 1
    done
  fi
  if [[ -f "$FAKE_STATE_DIR/human-login-needs-no-captcha" ]]; then
    printf 'password=%q\n' "$supplied_password" >"$FAKE_STATE_DIR/human-input"
    [[ "$supplied_password" == "fixture-password" ]]
    : >"$FAKE_STATE_DIR/human-login-used"
    exit 0
  fi
  : >"$FAKE_STATE_DIR/human-awaiting-captcha"
  IFS= read -r supplied_captcha
  supplied_captcha=${supplied_captcha%$'\r'}
  printf 'password=%q\ncaptcha=%q\n' "$supplied_password" "$supplied_captcha" >"$FAKE_STATE_DIR/human-input"
  [[ "$supplied_password" == "fixture-password" ]]
  [[ "$supplied_captcha" == "fixture-captcha" ]]
  : >"$FAKE_STATE_DIR/human-login-used"
  printf '%s\n' 'RAW-PROFILE-MUST-BE-SUPPRESSED'
  exit 0
fi

if [[ "$arguments" == *" user show "* ]]; then
  printf '%s\n' '{"schemaVersion":1,"ok":true,"data":{"name":"Fixture User","schoolId":"TEST-04"},"meta":{"connectionMode":"direct"}}'
  exit 0
fi

if [[ "$arguments" == *" auth status "* ]]; then
  printf '%s\n' '{"schemaVersion":1,"ok":true,"data":{"user":{"name":"Fixture User","schoolId":"TEST-04"},"authenticatedAt":1000,"lastActivity":1001},"meta":{"connectionMode":"direct"}}'
  exit 0
fi

exit 90
EOF
chmod 700 "$project_root/target/debug/ubaa"

export FAKE_STATE_DIR="$fake_state"
export REAL_STTY="$real_stty"
export PATH="$fake_bin:$PATH"
export VERIFY_LIVE_COPY="$project_root/scripts/verify-live.sh"

send_fixture_captcha() {
  for _ in {1..100}; do
    if [[ -f "$fake_state/human-awaiting-captcha" ]]; then
      break
    fi
    sleep 0.05
  done
  sleep 0.1
  printf '%s\n' 'fixture-captcha'
}

set +e
case "$(uname -s)" in
  Darwin)
    output=$(send_fixture_captcha | script -q -e /dev/null /bin/bash -c \
      'before=$(stty -g); "$VERIFY_LIVE_COPY" direct; code=$?; after=$(stty -g); [[ "$before" == "$after" ]] && printf "%s\n" terminal-state-restored; exit "$code"' 2>&1)
    code=$?
    ;;
  Linux)
    output=$(send_fixture_captcha | script -q -e -c \
      'before=$(stty -g); "$VERIFY_LIVE_COPY" direct; code=$?; after=$(stty -g); [[ "$before" == "$after" ]] && printf "%s\n" terminal-state-restored; exit "$code"' \
      /dev/null 2>&1)
    code=$?
    ;;
  *)
    echo "verify-live shell test supports Darwin and Linux" >&2
    exit 2
    ;;
esac
set -e

if [[ "$code" -ne 0 ]]; then
  printf 'captcha fallback test failed with exit %s\n%s\n' "$code" "$output" >&2
  if [[ -f "$fake_state/human-input" ]]; then
    cat "$fake_state/human-input" >&2
  fi
  exit 1
fi
if [[ ! -f "$fake_state/human-login-used" ]]; then
  echo "captcha fallback did not invoke human login" >&2
  exit 1
fi
if [[ "$output" != *"mode=direct outcome=success stage=auth_status"* ]]; then
  echo "captcha fallback did not reach the redacted success summary" >&2
  exit 1
fi
if [[ "$output" == *"RAW-PROFILE-MUST-BE-SUPPRESSED"* ]]; then
  echo "human profile stdout was not suppressed" >&2
  exit 1
fi
if [[ "$output" == *"fixture-password"* ]]; then
  echo "password leaked through verifier output" >&2
  exit 1
fi
if [[ "$output" == *"fixture-captcha"* ]]; then
  echo "captcha answer leaked through terminal echo" >&2
  exit 1
fi
if [[ "$output" == *"name_prefix="* || "$output" == *"school_id_suffix="* ]]; then
  echo "partial personal profile fields leaked through verifier output" >&2
  exit 1
fi
if [[ "$output" != *"terminal-state-restored"* ]]; then
  echo "verifier did not restore the terminal state" >&2
  exit 1
fi

: >"$fake_state/interrupt-after-echo"
set +e
case "$(uname -s)" in
  Darwin)
    interrupted_output=$(script -q -e /dev/null /bin/bash -c \
      'before=$(stty -g); "$VERIFY_LIVE_COPY" direct; code=$?; after=$(stty -g); [[ "$before" == "$after" ]] && printf "%s\n" interrupted-terminal-state-restored; exit "$code"' \
      </dev/null 2>&1)
    interrupted_code=$?
    ;;
  Linux)
    interrupted_output=$(script -q -e -c \
      'before=$(stty -g); "$VERIFY_LIVE_COPY" direct; code=$?; after=$(stty -g); [[ "$before" == "$after" ]] && printf "%s\n" interrupted-terminal-state-restored; exit "$code"' \
      /dev/null </dev/null 2>&1)
    interrupted_code=$?
    ;;
esac
set -e
rm -f "$fake_state/interrupt-after-echo"
if [[ "$interrupted_code" -ne 143 ]]; then
  printf 'interrupted terminal test exited with %s instead of 143\n' "$interrupted_code" >&2
  exit 1
fi
if [[ "$interrupted_output" != *"interrupted-terminal-state-restored"* ]]; then
  echo "signal after disabling echo left the terminal altered" >&2
  exit 1
fi

no_captcha_tty="$test_root/no-captcha-tty"
no_captcha_config="$test_root/no-captcha-config"
mkfifo "$no_captcha_tty"
mkdir -p "$no_captcha_config"
: >"$fake_state/human-login-needs-no-captcha"
rm -f "$fake_state/no-captcha-completed"
(
  sleep 3
  printf '%s\n' unused
) >"$no_captcha_tty" &
delayed_tty_writer=$!
(
  source "$repo_root/scripts/verify-live.sh"
  binary="$project_root/target/debug/ubaa"
  config_dir="$no_captcha_config"
  mode=direct
  username=fixture-user
  password=fixture-password
  CLI_CODE=0
  CLI_ELAPSED_MS=0
  run_human_login "$no_captcha_tty"
  : >"$fake_state/no-captcha-completed"
) &
no_captcha_login=$!

for _ in {1..30}; do
  if [[ -f "$fake_state/no-captcha-completed" ]]; then
    break
  fi
  sleep 0.05
done
if [[ ! -f "$fake_state/no-captcha-completed" ]]; then
  wait "$no_captcha_login" || true
  wait "$delayed_tty_writer" || true
  echo "human login waited for captcha after the client exited" >&2
  exit 1
fi
kill "$delayed_tty_writer" 2>/dev/null || true
wait "$delayed_tty_writer" 2>/dev/null || true
wait "$no_captcha_login"

signal_output="$test_root/signal-output"
signal_config="$test_root/signal-config"
mkdir -p "$signal_config"
: >"$fake_state/human-login-blocks"
rm -f "$fake_state/human-child-pid" "$fake_state/human-child-stopped"
(
  source "$repo_root/scripts/verify-live.sh"
  config_dir="$signal_config"
  human_input_fifo=
  human_binary_pid=
  human_input_open=no
  install_cleanup_traps
  "$project_root/target/debug/ubaa" --config-dir "$config_dir" auth login \
    --mode direct --username fixture-user --password-stdin \
    <<<"fixture-password" >/dev/null &
  human_binary_pid=$!
  wait "$human_binary_pid"
) >"$signal_output" 2>&1 &
signal_job=$!

for _ in {1..100}; do
  if [[ -s "$fake_state/human-child-pid" ]]; then
    break
  fi
  sleep 0.05
done
if [[ ! -s "$fake_state/human-child-pid" ]]; then
  kill "$signal_job" 2>/dev/null || true
  wait "$signal_job" 2>/dev/null || true
  cat "$signal_output" >&2 || true
  echo "signal cleanup test did not reach the blocking human login" >&2
  exit 1
fi

human_child_pid=$(cat "$fake_state/human-child-pid")
kill -TERM "$signal_job"
for _ in {1..100}; do
  if ! kill -0 "$human_child_pid" 2>/dev/null; then
    break
  fi
  sleep 0.05
done
if kill -0 "$human_child_pid" 2>/dev/null; then
  kill -KILL "$human_child_pid" 2>/dev/null || true
  kill -KILL "$signal_job" 2>/dev/null || true
  wait "$signal_job" 2>/dev/null || true
  cat "$signal_output" >&2 || true
  echo "terminating the verifier left the human login child running" >&2
  exit 1
fi
if [[ ! -f "$fake_state/human-child-stopped" ]]; then
  echo "human login child did not run its termination handler" >&2
  exit 1
fi
set +e
wait "$signal_job"
signal_code=$?
set -e
if [[ "$signal_code" -ne 143 ]]; then
  printf 'signal cleanup exited with %s instead of 143\n' "$signal_code" >&2
  cat "$signal_output" >&2 || true
  exit 1
fi

noninteractive_output=$(
  source "$repo_root/scripts/verify-live.sh"
  mode=direct
  username=fixture-user
  password=fixture-password
  CLI_CODE=0
  CLI_OUTPUT=
  run_json() {
    CLI_CODE=4
    CLI_OUTPUT='{"error":{"code":"captcha_required"}}'
  }
  if login_with_captcha_fallback "$test_root/missing-tty"; then
    exit 1
  else
    branch_code=$?
  fi
  [[ "$branch_code" -eq 4 ]]
)
if [[ "$noninteractive_output" != *"error=captcha_required_noninteractive"* ]]; then
  echo "non-interactive captcha branch did not return its actionable summary" >&2
  exit 1
fi

judge_sample_call="$test_root/judge-sample-call"
set +e
judge_output=$(
  source "$repo_root/scripts/verify-live.sh"
  mode=auto
  route=auto
  feature=judge
  CLI_CODE=0
  CLI_OUTPUT=
  run_json() {
    local stdin_value=$1
    shift
    [[ "$stdin_value" == none ]]
    if [[ "$*" == "judge assignments" ]]; then
      CLI_CODE=0
      CLI_OUTPUT='{"ok":true,"data":[{"courseId":"course-old","assignmentId":"assignment-old"},{"courseId":"course-new","assignmentId":"assignment-new"}]}'
    elif [[ "$*" == "judge assignment show --course-id course-old --id assignment-old" ]]; then
      CLI_CODE=0
      CLI_OUTPUT='{"ok":true,"data":{"assignmentId":"assignment-old"}}'
      printf '%s\n' "$*" >"$judge_sample_call"
    else
      CLI_CODE=6
      CLI_OUTPUT='{"ok":false,"error":{"code":"upstream_changed"}}'
    fi
  }
  run_readonly_feature
)
judge_code=$?
set -e
if [[ "$judge_code" -ne 0 || ! -s "$judge_sample_call" ]]; then
  printf 'Judge verifier did not select the first stable assignment sample\n%s\n' "$judge_output" >&2
  exit 1
fi
