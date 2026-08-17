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
  if [[ -f "$FAKE_STATE_DIR/human-login-needs-no-captcha" ]]; then
    printf 'password=%q\n' "$supplied_password" >"$FAKE_STATE_DIR/human-input"
    [[ "$supplied_password" == "fixture-password" ]]
    : >"$FAKE_STATE_DIR/human-login-used"
    exit 0
  fi
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
export PATH="$fake_bin:$PATH"
export VERIFY_LIVE_COPY="$project_root/scripts/verify-live.sh"

set +e
case "$(uname -s)" in
  Darwin)
    output=$({ sleep 1; printf '%s\n' 'fixture-captcha'; } | script -q -e /dev/null /bin/bash -c 'stty -echo; exec "$VERIFY_LIVE_COPY" direct' 2>&1)
    code=$?
    ;;
  Linux)
    output=$({ sleep 1; printf '%s\n' 'fixture-captcha'; } | script -q -e -c 'stty -echo; exec "$VERIFY_LIVE_COPY" direct' /dev/null 2>&1)
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
