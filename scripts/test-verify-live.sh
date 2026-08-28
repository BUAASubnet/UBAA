#!/usr/bin/env bash
set -euo pipefail

# This harness runs the live verifier against a deterministic local CLI. It
# sends credentials over stdin and records only CLI argv for leakage checks.
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-verify-live-test.XXXXXX")
cleanup() { rm -rf -- "$test_root"; }
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

real_jq=$(command -v jq)
cat >"$fake_bin/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n ${FAKE_JQ_FORBIDDEN_ARG_MARKER:-} ]]; then
  for argument in "$@"; do
    [[ "$argument" == *"$FAKE_JQ_FORBIDDEN_ARG_MARKER"* ]] && exit 97
  done
fi
exec "$REAL_JQ" "$@"
EOF
chmod 700 "$fake_bin/jq"

cat >"$project_root/target/debug/ubaa" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

arguments=" $* "
state_dir=${FAKE_STATE_DIR:?}
if [[ "$arguments" == *" auth login "* ]]; then
  printf '%s\n' "$*" >>"$state_dir/login-argv"
  IFS= read -r supplied_username
  IFS= read -r supplied_password
  [[ "$supplied_username" == fixture-user && "$supplied_password" == fixture-password ]]
fi

profile='{"idCardType":null,"idCardTypeName":null,"phone":null,"schoolId":"TEST-04","name":"Fixture User","idCardNumber":null,"email":null,"username":"fixture-user"}'
if [[ "$arguments" == *" auth login "* ]]; then
  if [[ "$arguments" == *" --mode "* ]]; then
    printf '%s\n' "{\"schemaVersion\":2,\"ok\":true,\"data\":$profile,\"meta\":{\"routePolicy\":\"direct\",\"networkState\":\"unknown\",\"initialRoute\":\"direct\",\"resolvedRoute\":\"direct\",\"usedFallback\":false,\"feature\":\"auth\"}}"
  else
    printf '%s\n' "{\"schemaVersion\":2,\"ok\":true,\"data\":{\"readiness\":\"all_ready\",\"routes\":[{\"route\":\"direct\",\"state\":\"ready\"},{\"route\":\"webvpn\",\"state\":\"ready\"}],\"profile\":$profile},\"meta\":{\"routePolicy\":\"auto\",\"resolvedRoutes\":[\"direct\",\"webvpn\"],\"feature\":\"auth\"}}"
  fi
  exit 0
fi

if [[ "$arguments" == *" user show "* ]]; then
  printf '%s\n' "{\"schemaVersion\":2,\"ok\":true,\"data\":$profile,\"meta\":{\"routePolicy\":\"direct\",\"networkState\":\"unknown\",\"initialRoute\":\"direct\",\"resolvedRoute\":\"direct\",\"usedFallback\":false,\"feature\":\"user\"}}"
  exit 0
fi
if [[ "$arguments" == *" auth status "* ]]; then
  printf '%s\n' "{\"schemaVersion\":2,\"ok\":true,\"data\":{\"readiness\":\"all_ready\",\"routes\":[{\"route\":\"direct\",\"state\":\"ready\"},{\"route\":\"webvpn\",\"state\":\"ready\"}],\"profile\":$profile},\"meta\":{\"routePolicy\":\"direct\",\"resolvedRoutes\":[\"direct\",\"webvpn\"],\"feature\":\"auth\"}}"
  exit 0
fi

route_policy=direct
network_state=unknown
resolved_route=direct
if [[ "$arguments" != *" --mode direct "* && "$arguments" != *" --mode webvpn "* ]]; then
  route_policy=auto
fi
if [[ "$arguments" == *" --mode webvpn "* ]]; then
  resolved_route=webvpn
fi
meta="\"meta\":{\"routePolicy\":\"$route_policy\",\"networkState\":\"$network_state\",\"initialRoute\":\"$resolved_route\",\"resolvedRoute\":\"$resolved_route\",\"usedFallback\":false"
if [[ "$arguments" == *" spoc diagnostics "* ]]; then
  printf '%s\n' "{\"schemaVersion\":2,\"ok\":true,\"data\":{\"globalPageCount\":1,\"result\":{\"termCode\":\"2025-20262\",\"termName\":\"Spring\",\"assignments\":[]}},$meta,\"feature\":\"spoc\"}}"
  exit 0
fi
if [[ "$arguments" == *" spoc assignment show "* ]]; then
  printf '%s\n' "{\"schemaVersion\":2,\"ok\":true,\"data\":{\"assignmentId\":\"assignment-1\",\"courseId\":\"course-1\",\"courseName\":\"Course\",\"teacherName\":null,\"title\":\"Assignment\",\"startTime\":null,\"dueTime\":null,\"score\":null,\"submissionStatus\":\"UNKNOWN\",\"submissionStatusText\":\"未知状态\",\"contentPlainText\":null,\"submittedAt\":null},$meta,\"feature\":\"spoc\"}}"
  exit 0
fi
if [[ "$arguments" == *" judge diagnostics "* ]]; then
  printf '%s\n' "{\"schemaVersion\":2,\"ok\":true,\"data\":{\"courseCount\":0,\"rawAnchorCount\":0,\"filteredUniqueCount\":0,\"summaries\":[]},$meta,\"feature\":\"judge\"}}"
  exit 0
fi
if [[ "$arguments" == *" judge assignments "* ]]; then
  printf '%s\n' "{\"schemaVersion\":2,\"ok\":true,\"data\":[],$meta,\"feature\":\"judge\"}}"
  exit 0
fi
exit 90
EOF
chmod 700 "$project_root/target/debug/ubaa"

export FAKE_STATE_DIR="$fake_state"
export REAL_JQ="$real_jq"
export PATH="$fake_bin:$PATH"
export VERIFY_LIVE_COPY="$project_root/scripts/verify-live.sh"
export TRACE_PROJECT_ROOT="$project_root"

xtrace_output=$(bash -x -c '
  source "$VERIFY_LIVE_COPY"
  username=fixture-user
  password=fixture-password
  binary="$TRACE_PROJECT_ROOT/target/debug/ubaa"
  config_dir="$TRACE_PROJECT_ROOT"
  run_json credentials auth login --mode direct --username-stdin --password-stdin
  UBAA_VERIFY_DIGEST_SALT=fixture-trace-salt
  salted_assignment_digest TRACE-ASSIGNMENT-SENTINEL >/dev/null
' 2>&1)
for trace_secret in fixture-user fixture-password fixture-trace-salt TRACE-ASSIGNMENT-SENTINEL; do
  if [[ "$xtrace_output" == *"$trace_secret"* ]]; then
    echo "verify-live exposed a private value while inherited xtrace was enabled" >&2
    exit 1
  fi
done
if grep -Fq fixture-user "$fake_state/login-argv" \
  || grep -Fq fixture-password "$fake_state/login-argv" \
  || grep -Fq fixture-trace-salt "$fake_state/login-argv"; then
  echo "verify-live passed a private value through the login process argv" >&2
  exit 1
fi
unset xtrace_output trace_secret

for salted_feature in judge all; do
  set +e
  missing_salt_output=$(unset UBAA_VERIFY_DIGEST_SALT; "$VERIFY_LIVE_COPY" \
    feature="$salted_feature" route=direct 2>&1)
  missing_salt_code=$?
  set -e
  if [[ "$missing_salt_code" -ne 2 \
    || "$missing_salt_output" != *"requires UBAA_VERIFY_DIGEST_SALT"* ]]; then
    printf '%s verification did not reject a missing digest salt\n%s\n' \
      "$salted_feature" "$missing_salt_output" >&2
    exit 1
  fi
done

(
  source "$repo_root/scripts/verify-live.sh"
  digest_payload='[["course-fixture","assignment-fixture"]]'
  UBAA_VERIFY_DIGEST_SALT=fixture-salt-a
  first=$(salted_assignment_digest "$digest_payload")
  second=$(salted_assignment_digest "$digest_payload")
  UBAA_VERIFY_DIGEST_SALT=fixture-salt-b
  third=$(salted_assignment_digest "$digest_payload")
  [[ -n "$first" && "$first" == "$second" && "$first" != "$third" ]]
)

set +e
auth_output=$(UBAA_VERIFY_DIGEST_SALT=fixture-salt "$VERIFY_LIVE_COPY" direct 2>&1)
auth_code=$?
set -e
if [[ "$auth_code" -ne 0 \
  || "$auth_output" != *"mode=direct outcome=success stage=auth_status"* \
  || "$auth_output" == *"fixture-password"* \
  || "$auth_output" == *"fixture-user"* ]]; then
  printf 'explicit auth verification failed or exposed private output\n%s\n' "$auth_output" >&2
  exit 1
fi

set +e
spoc_output=$(UBAA_VERIFY_DIGEST_SALT=fixture-salt "$VERIFY_LIVE_COPY" feature=spoc route=auto 2>&1)
spoc_code=$?
set -e
if [[ "$spoc_code" -ne 0 \
  || "$spoc_output" != *"feature=spoc outcome=success"* \
  || "$spoc_output" != *"global_page_count=1"* \
  || "$spoc_output" == *"fixture-password"* ]]; then
  printf 'SPOC verification failed or exposed private output\n%s\n' "$spoc_output" >&2
  exit 1
fi

set +e
judge_output=$(UBAA_VERIFY_DIGEST_SALT=fixture-salt "$VERIFY_LIVE_COPY" feature=judge route=auto 2>&1)
judge_code=$?
set -e
if [[ "$judge_code" -ne 0 \
  || "$judge_output" != *"feature=judge outcome=success"* \
  || "$judge_output" != *"digest_comparable=yes"* \
  || "$judge_output" == *"fixture-password"* ]]; then
  printf 'Judge verification failed or exposed private output\n%s\n' "$judge_output" >&2
  exit 1
fi

set +e
judge_argv_output=$(
  export FAKE_JQ_FORBIDDEN_ARG_MARKER=34
  source "$repo_root/scripts/verify-live.sh"
  mode=direct
  route=direct
  feature=judge
  UBAA_VERIFY_DIGEST_SALT=fixture-salt
  CLI_CODE=0
  CLI_OUTPUT=
  run_json() {
    local stdin_value=$1
    shift
    [[ "$stdin_value" == none ]]
    CLI_CODE=0
    CLI_ELAPSED_MS=0
    if [[ "$*" == "judge diagnostics --include-expired" ]]; then
        CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"courseCount":1,"rawAnchorCount":1,"filteredUniqueCount":1,"summaries":[{"courseId":"12","courseName":"Course","assignmentId":"34","title":"Assignment","startTime":null,"dueTime":null,"maxScore":null,"myScore":null,"totalProblems":0,"submittedCount":0,"submissionStatus":"UNKNOWN","submissionStatusText":"未知状态"}]},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"judge"}}'
    elif [[ "$*" == "judge assignments" ]]; then
        CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":[{"courseId":"12","courseName":"Course","assignmentId":"34","title":"Assignment","startTime":null,"dueTime":null,"maxScore":null,"myScore":null,"totalProblems":0,"submittedCount":0,"submissionStatus":"UNKNOWN","submissionStatusText":"未知状态"}],"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"judge"}}'
    elif [[ "$*" == "judge assignment show --course-id 12 --id 34" ]]; then
        CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"courseId":"12","courseName":"Course","assignmentId":"34","title":"Assignment","startTime":null,"dueTime":null,"maxScore":null,"myScore":null,"totalProblems":0,"submittedCount":0,"submissionStatus":"UNKNOWN","submissionStatusText":"未知状态","problems":[],"contentPlainText":null},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"judge"}}'
    else
        CLI_CODE=6
        CLI_OUTPUT='{"schemaVersion":2,"ok":false,"error":{"code":"upstream_changed","kind":"upstream","message":"fixture","retryable":false}}'
    fi
  }
  run_readonly_feature
)
judge_argv_code=$?
set -e
if [[ "$judge_argv_code" -ne 0 \
  || "$judge_argv_output" != *"feature=judge outcome=success"* ]]; then
  printf 'Judge verifier passed an identifier to jq argv or rejected stdin comparison\n%s\n' \
    "$judge_argv_output" >&2
  exit 1
fi

set +e
spoc_identity_output=$(
  source "$repo_root/scripts/verify-live.sh"
  mode=auto
  route=auto
  feature=spoc
  CLI_CODE=0
  CLI_OUTPUT=
  run_json() {
    local stdin_value=$1
    shift
    [[ "$stdin_value" == none ]]
    CLI_CODE=0
    CLI_ELAPSED_MS=0
    if [[ "$*" == "spoc diagnostics" ]]; then
      CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"globalPageCount":1,"result":{"termCode":"2025-20262","termName":"Spring","assignments":[{"assignmentId":"assignment-1","courseId":"course-10","courseName":"Course","teacherName":null,"title":"Assignment","startTime":null,"dueTime":null,"score":null,"submissionStatus":"UNKNOWN","submissionStatusText":"未知状态(9)"}]}},"meta":{"routePolicy":"auto","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"spoc"}}'
    elif [[ "$*" == "spoc assignment show --id assignment-1" ]]; then
      CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"assignmentId":"assignment-1","courseId":"course-999","courseName":"Course","teacherName":null,"title":"Assignment","startTime":null,"dueTime":null,"score":null,"submissionStatus":"UNKNOWN","submissionStatusText":"未知状态","contentPlainText":null,"submittedAt":null},"meta":{"routePolicy":"auto","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"spoc"}}'
    else
      CLI_CODE=6
      CLI_OUTPUT='{"schemaVersion":2,"ok":false,"error":{"code":"upstream_changed","kind":"upstream","message":"fixture","retryable":false}}'
    fi
  }
  run_readonly_feature
)
spoc_identity_code=$?
set -e
if [[ "$spoc_identity_code" -ne 1 \
  || "$spoc_identity_output" != *"stage=spoc_detail"* \
  || "$spoc_identity_output" != *"error=invalid_semantics"* ]]; then
  printf 'SPOC verifier accepted a detail from a different course\n%s\n' \
    "$spoc_identity_output" >&2
  exit 1
fi

set +e
mixed_route_output=$(
  source "$repo_root/scripts/verify-live.sh"
  mode=auto
  route=auto
  feature=judge
  UBAA_VERIFY_DIGEST_SALT=fixture-salt
  CLI_CODE=0
  CLI_OUTPUT=
  run_json() {
    local stdin_value=$1
    shift
    [[ "$stdin_value" == none ]]
    CLI_CODE=0
    CLI_ELAPSED_MS=0
    if [[ "$*" == "judge diagnostics --include-expired" ]]; then
      CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"courseCount":0,"rawAnchorCount":0,"filteredUniqueCount":0,"summaries":[]},"meta":{"routePolicy":"auto","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"judge"}}'
    elif [[ "$*" == "judge assignments" ]]; then
      CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":[],"meta":{"routePolicy":"auto","networkState":"off_campus","initialRoute":"webvpn","resolvedRoute":"webvpn","usedFallback":false,"feature":"judge"}}'
    else
      CLI_CODE=6
      CLI_OUTPUT='{"schemaVersion":2,"ok":false,"error":{"code":"upstream_changed","kind":"upstream","message":"fixture","retryable":false}}'
    fi
  }
  run_readonly_feature
)
mixed_route_code=$?
set -e
if [[ "$mixed_route_code" -eq 0 ]]; then
  printf 'Judge verifier accepted mixed auto routes\n%s\n' "$mixed_route_output" >&2
  exit 1
fi

(
  source "$repo_root/scripts/verify-live.sh"
  mode=direct
  route=direct
  feature=spoc
  assert_rejected() {
    local label=$1
    shift
    if "$@"; then
      printf 'semantic verifier accepted invalid case: %s\n' "$label" >&2
      exit 1
    fi
  }
  assert_accepted() {
    local label=$1
    shift
    if ! "$@"; then
      printf 'semantic verifier rejected valid case: %s\n' "$label" >&2
      exit 1
    fi
  }

  valid_spoc='{"schemaVersion":2,"ok":true,"data":{"globalPageCount":1,"result":{"termCode":"2025-20262","termName":"Spring","assignments":[]}},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"spoc"}}'
  CLI_OUTPUT="$valid_spoc"
  assert_accepted valid_routed_output validate_feature_data spoc_diagnostics

  feature=schedule
  valid_schedule_current='{"schemaVersion":2,"ok":true,"data":{"arrangedList":[],"code":"2025-2026","name":"Spring Term"},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"schedule"}}'
  CLI_OUTPUT="$valid_schedule_current"
  assert_accepted schedule_current_shape validate_feature_data schedule_current
  assert_accepted schedule_current_code_is_independent_of_request validate_schedule_code

  CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"arrangedList":[],"code":"","name":"Spring Term"},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"schedule"}}'
  assert_rejected empty_schedule_code validate_schedule_code

  CLI_OUTPUT='{"schemaVersion":1,"ok":true,"data":{"termCode":"2025-20262","assignments":[]},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"spoc"}}'
  assert_rejected schema_v1 validate_feature_data spoc_diagnostics

  CLI_OUTPUT=$'{"schemaVersion":2,"ok":true,"data":{"termCode":"2025-20262","termName":"Spring","assignments":[]},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"spoc"}}\n{"schemaVersion":2,"ok":true,"data":{"termCode":"2025-20262","termName":"Spring","assignments":[]},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"spoc"}}'
  assert_rejected multiple_json_values validate_feature_data spoc_diagnostics

  mode=auto
  route=auto
  CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"termCode":"2025-20262","termName":"Spring","assignments":[]},"meta":{"routePolicy":"auto","networkState":"campus","initialRoute":"webvpn","resolvedRoute":"webvpn","usedFallback":false,"feature":"spoc"}}'
  assert_rejected contradictory_auto_route validate_feature_data spoc_diagnostics

  mode=direct
  route=direct
  CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"termCode":"2025-20262","termName":"Spring","assignments":[],"rawBody":"VERIFY-LIVE-SENSITIVE-SENTINEL"},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"spoc"}}'
  assert_rejected unsafe_output_key validate_feature_data spoc_diagnostics

  CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"readiness":"all_ready","routes":[{"route":"direct","state":"ready"},{"route":"webvpn","state":"ready"}],"profile":{"idCardType":null,"idCardTypeName":null,"phone":"UNMASKED-PHONE","schoolId":"TEST-04","name":"Fixture User","idCardNumber":"UNMASKED-ID","email":null,"username":"fixture-user"}},"meta":{"routePolicy":"direct","resolvedRoutes":["direct","webvpn"],"feature":"auth"}}'
  assert_rejected unmasked_aggregate_profile validate_aggregate_auth_success all

  CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"readiness":"partial","routes":[{"route":"direct","state":"ready"},{"route":"webvpn","state":"failed","error":{"code":"upstream_unavailable","kind":"upstream","message":"fixture","retryable":"true"}}],"profile":{"idCardType":null,"idCardTypeName":null,"phone":null,"schoolId":"TEST-04","name":"Fixture User","idCardNumber":null,"email":null,"username":"fixture-user"}},"meta":{"routePolicy":"direct","resolvedRoutes":["direct","webvpn"],"feature":"auth"}}'
  assert_rejected non_boolean_route_error validate_aggregate_auth_success direct

  CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":{"termCode":"2025-20262","termName":"Spring","assignments":[{"assignmentId":"assignment-1","courseId":"course-1","courseName":"Course","teacherName":null,"title":"Assignment","startTime":null,"dueTime":null,"score":null,"submissionStatus":"SUBMITTED","submissionStatusText":"未提交"}]},"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"spoc"}}'
  assert_rejected spoc_status_text_mismatch validate_feature_data spoc_diagnostics

  feature=judge
  CLI_OUTPUT='{"schemaVersion":2,"ok":true,"data":[{"courseId":"12","courseName":"Course","assignmentId":"34","title":"Assignment","startTime":null,"dueTime":null,"maxScore":"PRIVATE","myScore":null,"totalProblems":0,"submittedCount":0,"submissionStatus":"UNKNOWN","submissionStatusText":"未知状态"}],"meta":{"routePolicy":"direct","networkState":"unknown","initialRoute":"direct","resolvedRoute":"direct","usedFallback":false,"feature":"judge"}}'
  assert_rejected arbitrary_judge_score validate_feature_data judge
)

set +e
extension_calls_output=$(
  source "$repo_root/scripts/verify-live.sh"
  mode=direct
  route=direct
  UBAA_VERIFY_DATE=2026-08-29
  CLI_CODE=0
  CLI_OUTPUT=
  FEATURE_RESOLVED_ROUTE=direct
  validate_routed_success() { return 0; }
  capture_resolved_route() { FEATURE_RESOLVED_ROUTE=direct; return 0; }
  validate_feature_data() { return 0; }
  redacted_failure() { return 91; }
  semantic_failure() { return 92; }
  run_json() {
    local stdin_value=$1
    shift
    [[ "$stdin_value" == none ]]
    local command="$*"
    printf '%s\n' "$command"
    CLI_CODE=0
    CLI_ELAPSED_MS=0
    if [[ "$command" == "ygdk overview" ]]; then CLI_OUTPUT='{"data":{"items":[]}}'
    elif [[ "$command" == ygdk\ records* ]]; then CLI_OUTPUT='{"data":{"content":[],"page":1,"size":20,"hasMore":false}}'
    elif [[ "$command" == libbook\ libraries* ]]; then CLI_OUTPUT='{"data":[]}'
    elif [[ "$command" == libbook\ bookings* ]]; then CLI_OUTPUT='{"data":{"bookings":[],"page":1,"limit":20,"total":0}}'
    elif [[ "$command" == "bykc profile" ]]; then CLI_OUTPUT='{"data":{}}'
    elif [[ "$command" == bykc\ courses* ]]; then CLI_OUTPUT='{"data":{"content":[]}}'
    elif [[ "$command" == "bykc chosen" ]]; then CLI_OUTPUT='{"data":[]}'
    elif [[ "$command" == "bykc statistics" ]]; then CLI_OUTPUT='{"data":{}}'
    elif [[ "$command" == "cgyy sites" ]]; then CLI_OUTPUT='{"data":[]}'
    elif [[ "$command" == "cgyy purposes" ]]; then CLI_OUTPUT='{"data":[]}'
    elif [[ "$command" == cgyy\ orders* ]]; then CLI_OUTPUT='{"data":{"content":[]}}'
    elif [[ "$command" == "cgyy lock-code" ]]; then CLI_OUTPUT='{"data":{"rawData":{}}}'
    elif [[ "$command" == "evaluation all" ]]; then CLI_OUTPUT='{"data":{"courses":[]}}'
    elif [[ "$command" == "evaluation pending" ]]; then CLI_OUTPUT='{"data":[]}'
    elif [[ "$command" == "user show" ]]; then CLI_OUTPUT='{"data":{"idCardType":null,"idCardTypeName":null,"phone":null,"schoolId":"TEST-04","name":"Fixture User","idCardNumber":null,"email":null,"username":"fixture-user"}}'
    else CLI_CODE=93; return 93
    fi
  }
  for feature in user ygdk libbook bykc cgyy evaluation; do
    run_readonly_feature || exit $?
  done
)
extension_calls_code=$?
set -e
if [[ "$extension_calls_code" -ne 0 \
  || "$extension_calls_output" != *"ygdk overview"* \
  || "$extension_calls_output" != *"user show"* \
  || "$extension_calls_output" != *"ygdk records --page 1 --size 20"* \
  || "$extension_calls_output" != *"libbook libraries --day 2026-08-29"* \
  || "$extension_calls_output" != *"libbook bookings --page 1 --limit 20"* \
  || "$extension_calls_output" != *"bykc profile"* \
  || "$extension_calls_output" != *"bykc chosen"* \
  || "$extension_calls_output" != *"bykc statistics"* \
  || "$extension_calls_output" != *"cgyy purposes"* \
  || "$extension_calls_output" != *"cgyy orders --page 0 --size 20"* \
  || "$extension_calls_output" != *"cgyy lock-code"* \
  || "$extension_calls_output" != *"evaluation pending"* ]]; then
  printf '扩展只读验证器未逐操作调用，或调用失败\n%s\n' "$extension_calls_output" >&2
  exit 1
fi

echo 'verify-live shell tests passed'
