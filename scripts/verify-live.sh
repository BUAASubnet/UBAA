#!/usr/bin/env bash
{ set +x; } 2>/dev/null
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
  if [[ "$stdin_value" == credentials ]]; then
    CLI_OUTPUT=$(printf '%s\n%s\n' "$username" "$password" | "$binary" --json --config-dir "$config_dir" "$@" 2>/dev/null)
  elif [[ "$stdin_value" == password ]]; then
    CLI_OUTPUT=$(printf '%s\n' "$password" | "$binary" --json --config-dir "$config_dir" "$@" 2>/dev/null)
  else
    CLI_OUTPUT=$("$binary" --json --config-dir "$config_dir" "$@" 2>/dev/null)
  fi
  CLI_CODE=$?
  set -e
  ended=$(date +%s)
  CLI_ELAPSED_MS=$(( (ended - started) * 1000 ))
  if [[ ${TRACK_FEATURE_TIME:-no} == yes ]]; then
    FEATURE_ELAPSED_MS=$(( ${FEATURE_ELAPSED_MS:-0} + CLI_ELAPSED_MS ))
  fi
}

validate_safe_schema_v2() {
  jq -s -e '
    def forbidden_key:
      (ascii_downcase | gsub("[_-]"; "")) as $key
      | ($key | test("execution|cookie|token|authorization|password|secret|credential|sessionid|jwt|bearer|ticket"))
        or ($key | test("html|body|header|url"))
        or ($key | test("^(raw|source|request|response|session|requesttext|responsetext|requestdata|responsedata|rawrequest|rawresponse|rawpayload|rawdata|payload|connectionmode|rolecode)$"));
    def safe_error_ok:
      type == "object"
        and ((keys | sort) == (["code", "kind", "message", "retryable"] | sort))
        and ((keys | length) == 4)
        and (.code | IN(
          "invalid_input",
          "authentication_required",
          "invalid_credentials",
          "password_risk_confirmation_failed",
          "permission_denied",
          "network_error",
          "timeout",
          "upstream_unavailable",
          "upstream_changed",
          "parse_error",
          "internal_error"
        ))
        and (.kind | IN("input", "authentication", "network", "upstream", "parse", "internal"))
        and ((.message | type) == "string")
        and ((.retryable | type) == "boolean");
    length == 1 and (.[0] |
      .schemaVersion == 2
        and ((.ok | type) == "boolean")
        and ([.. | objects | select(has("error")) | .error] | all(safe_error_ok))
        and (([
          paths as $path
          | select(($path[-1] | type) == "string")
          | $path[-1]
          | select(forbidden_key)
        ] | length) == 0)
        and (([
          .. | strings
          | select(
              test("(?is)^\\s*<!doctype\\s+html\\b")
                or (
                  test("(?is)^\\s*<html\\b")
                    and test("(?is)(?:</html\\s*>|<(?:head|body)\\b)")
                )
                or test("(?is)<form\\b[^>]*>.*name=[\"\\u0027]execution[\"\\u0027]")
            )
        ] | length) == 0)
        and ((tostring | contains("VERIFY-LIVE-SENSITIVE-SENTINEL")) | not)
    )
  ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
}

validate_user_profile() {
  local aggregate=${1:-no}
  jq -e --arg aggregate "$aggregate" '
    (if $aggregate == "yes" then .data.profile else .data end) as $profile
    | ($profile | type) == "object"
      and (($profile | keys | sort) == ([
        "idCardType",
        "idCardTypeName",
        "phone",
        "schoolId",
        "name",
        "idCardNumber",
        "email",
        "username"
      ] | sort))
      and (($profile.name // "") | type) == "string"
      and (($profile.name // "") | length) > 0
      and (($profile.schoolId // "") | type) == "string"
      and (($profile.schoolId // "") | length) > 0
      and ($profile | to_entries | all(.value == null or (.value | type) == "string"))
      and ($profile.phone == null or $profile.phone == ""
        or ($profile.phone | test("^(?:\\*{1,4}|..\\*+..)$")))
      and ($profile.idCardNumber == null or $profile.idCardNumber == ""
        or ($profile.idCardNumber | test("^(?:\\*{1,4}|..\\*+..)$")))
  ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
}

validate_routed_success() {
  local expected_feature=$1
  local expected_policy=${route:-$mode}
  validate_safe_schema_v2 && jq -e \
    --arg feature "$expected_feature" \
    --arg policy "$expected_policy" '
      .ok == true
        and has("data")
        and (has("error") | not)
        and ((keys | sort) == (["schemaVersion", "ok", "data", "meta"] | sort))
        and ((.meta | keys | sort) == ([
          "routePolicy",
          "networkState",
          "initialRoute",
          "resolvedRoute",
          "usedFallback",
          "feature"
        ] | sort))
        and (.meta.feature == $feature)
        and (.meta.routePolicy == $policy)
        and (.meta.usedFallback == false)
        and (.meta.initialRoute == .meta.resolvedRoute)
        and (
          if $policy == "direct" then
            .meta.networkState == "unknown" and .meta.resolvedRoute == "direct"
          elif $policy == "webvpn" then
            .meta.networkState == "unknown" and .meta.resolvedRoute == "webvpn"
          else
            (.meta.networkState == "campus" and .meta.resolvedRoute == "direct")
              or (.meta.networkState == "off_campus" and .meta.resolvedRoute == "webvpn")
              or (.meta.networkState == "unknown" and .meta.resolvedRoute == "direct")
          end
        )
    ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
}

validate_aggregate_auth_success() {
  local required_route=$1
  local expected_policy=${route:-$mode}
  validate_safe_schema_v2 && jq -e \
    --arg policy "$expected_policy" \
    --arg required "$required_route" '
      .ok == true
        and ((keys | sort) == (["schemaVersion", "ok", "data", "meta"] | sort))
        and (has("error") | not)
        and (.meta == {
          routePolicy: $policy,
          resolvedRoutes: ["direct", "webvpn"],
          feature: "auth"
        })
        and ((.data | keys | sort) == (["readiness", "routes", "profile"] | sort))
        and ((.data.routes | type) == "array")
        and (.data.routes | length == 2)
        and (.data.routes[0].route == "direct")
        and (.data.routes[1].route == "webvpn")
        and (.data.routes | all(
          if .state == "ready" then
            ((keys | sort) == (["route", "state"] | sort))
          elif .state == "failed" then
            ((keys | sort) == (["route", "state", "error"] | sort))
              and ((.error | keys | sort) == (["code", "kind", "message", "retryable"] | sort))
          else false
          end
        ))
        and ((.data.profile.name // "") | length > 0)
        and ((.data.profile.schoolId // "") | length > 0)
        and (
          ([.data.routes[] | select(.state == "ready")] | length) as $ready
          | if $ready == 2 then .data.readiness == "all_ready"
            elif $ready == 1 then .data.readiness == "partial"
            else .data.readiness == "none_ready"
            end
        )
        and (
          if $required == "all" then
            .data.readiness == "all_ready"
              and (.data.routes | all(.state == "ready"))
          else
            (.data.readiness == "all_ready" or .data.readiness == "partial")
              and (.data.routes | any(.route == $required and .state == "ready"))
          end
        )
    ' >/dev/null 2>&1 <<<"$CLI_OUTPUT" && validate_user_profile yes
}

validate_explicit_login_success() {
  validate_routed_success auth && validate_user_profile no
}

validate_feature_data() {
  local expected_feature=$1
  local meta_feature=$expected_feature
  case "$expected_feature" in
    schedule_terms|schedule_weeks|schedule_current|schedule_today) meta_feature=schedule ;;
    spoc_detail|spoc_diagnostics) meta_feature=spoc ;;
    judge_detail|judge_diagnostics) meta_feature=judge ;;
  esac
  validate_routed_success "$meta_feature" || return 1
  case "$expected_feature" in
    schedule_terms)
      jq -e '
        (.data | type) == "array" and (.data | all(
          ((keys | sort) == (["itemCode", "itemName", "selected", "itemIndex"] | sort))
            and (.itemCode | type) == "string" and (.itemCode | length) > 0
            and (.itemName | type) == "string"
            and (.selected | type) == "boolean"
            and (.itemIndex | type == "number" and floor == . and . >= -2147483648 and . <= 2147483647)
        ))
      ' \
        >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    schedule_weeks)
      jq -e '
        (.data | type) == "array" and (.data | all(
          ((keys | sort) == (["startDate", "endDate", "term", "curWeek", "serialNumber", "name"] | sort))
            and (.startDate | type) == "string"
            and (.endDate | type) == "string"
            and (.term | type) == "string"
            and (.curWeek | type) == "boolean"
            and (.serialNumber | type == "number" and floor == . and . > 0 and . <= 2147483647)
            and (.name | type) == "string"
        ))
      ' \
        >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    schedule_today)
      jq -e '
        (.data | type) == "array" and (.data | all(
          ((keys | sort) == (["bizName", "place", "time", "shortName"] | sort))
            and (.bizName | type) == "string"
            and ((.place == null) or ((.place | type) == "string"))
            and ((.time == null) or ((.time | type) == "string"))
            and ((.shortName == null) or ((.shortName | type) == "string"))
        ))
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    schedule_current)
      jq -e '
        (.data | type) == "object"
          and ((.data | keys | sort) == (["arrangedList", "code", "name"] | sort))
          and ((.data.arrangedList | type) == "array")
          and (.data.arrangedList | all(
            ((keys | sort) == ([
              "courseCode",
              "courseName",
              "courseSerialNo",
              "credit",
              "beginTime",
              "endTime",
              "beginSection",
              "endSection",
              "placeName",
              "weeksAndTeachers",
              "teachingTarget",
              "color",
              "dayOfWeek"
            ] | sort))
              and (.courseCode | type) == "string"
              and (.courseName | type) == "string"
              and ((.courseSerialNo == null) or ((.courseSerialNo | type) == "string"))
              and ((.credit == null) or ((.credit | type) == "string"))
              and ((.beginTime == null) or ((.beginTime | type) == "string"))
              and ((.endTime == null) or ((.endTime | type) == "string"))
              and ((.beginSection == null) or (.beginSection | type == "number" and floor == . and . >= -2147483648 and . <= 2147483647))
              and ((.endSection == null) or (.endSection | type == "number" and floor == . and . >= -2147483648 and . <= 2147483647))
              and ((.placeName == null) or ((.placeName | type) == "string"))
              and ((.weeksAndTeachers == null) or ((.weeksAndTeachers | type) == "string"))
              and ((.teachingTarget == null) or ((.teachingTarget | type) == "string"))
              and ((.color == null) or ((.color | type) == "string"))
              and ((.dayOfWeek == null) or (.dayOfWeek | type == "number" and floor == . and . >= 1 and . <= 7))
          ))
          and ((.data.code | type) == "string")
          and ((.data.name | type) == "string")
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    exam)
      jq -e '
        (.data | type) == "object"
          and ((.data | keys | sort) == (["arranged", "notArranged"] | sort))
          and ((.data.arranged | type) == "array")
          and ((.data.notArranged | type) == "array")
          and ((.data.arranged + .data.notArranged) | all(
            ((keys | sort) == ([
              "courseName",
              "courseNo",
              "examTimeDescription",
              "examDate",
              "startTime",
              "endTime",
              "examPlace",
              "examSeatNo",
              "week",
              "examStatus",
              "examType",
              "taskId"
            ] | sort))
              and (.courseName | type) == "string"
              and ((.courseNo == null) or ((.courseNo | type) == "string"))
              and ((.examTimeDescription == null) or ((.examTimeDescription | type) == "string"))
              and ((.examDate == null) or ((.examDate | type) == "string"))
              and ((.startTime == null) or ((.startTime | type) == "string"))
              and ((.endTime == null) or ((.endTime | type) == "string"))
              and ((.examPlace == null) or ((.examPlace | type) == "string"))
              and ((.examSeatNo == null) or ((.examSeatNo | type) == "string"))
              and ((.week == null) or (.week | type == "number" and floor == . and . >= -2147483648 and . <= 2147483647))
              and ((.examStatus == null) or (.examStatus | type == "number" and floor == . and . >= -2147483648 and . <= 2147483647))
              and ((.examType == null) or ((.examType | type) == "string"))
              and ((.taskId == null) or ((.taskId | type) == "string"))
          ))
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    grades)
      jq -e '
        .data as $result
        | ($result | type) == "object"
          and (($result | keys | sort) == (["termCode", "grades"] | sort))
          and (($result.termCode | type) == "string" and ($result.termCode | length) > 0)
          and (($result.grades | type) == "array")
          and ($result.grades | all(
            ((keys | sort) == ([
              "courseName",
              "courseCode",
              "credit",
              "score",
              "gradePoint",
              "courseType",
              "scoreType",
              "termCode"
            ] | sort))
              and ((.courseName == null) or ((.courseName | type) == "string"))
              and ((.courseCode == null) or ((.courseCode | type) == "string"))
              and ((.credit == null) or ((.credit | type) == "number"))
              and ((.score == null) or ((.score | type) == "string"))
              and ((.gradePoint == null) or ((.gradePoint | type) == "string"))
              and ((.courseType == null) or ((.courseType | type) == "string"))
              and ((.scoreType == null) or ((.scoreType | type) == "string"))
              and ((.termCode | type) == "string" and .termCode == $result.termCode)
          ))
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    classroom)
      jq -e '
        (.data | type) == "object"
          and ((.data | keys | sort) == (["code", "message", "floors"] | sort))
          and .data.code == 0
          and ((.data.message | type) == "string")
          and ((.data.floors | type) == "object")
          and (.data.floors | all(.[]; (type) == "array"))
          and ([.data.floors[]?[]?] | all(
            ((keys | sort) == (["id", "floorId", "name", "availableSections"] | sort))
              and (.id | type) == "string"
              and (.floorId | type) == "string"
              and (.name | type) == "string"
              and (.availableSections | type) == "string"
          ))
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    spoc)
      jq -e '
        def unknown_summary_text:
          . as $text
          | if ($text | test("^未知状态\\(.+\\)$")) then
              ($text | capture("^未知状态\\((?<raw>.+)\\)$").raw) as $raw
              | ($raw == ($raw | gsub("^\\s+|\\s+$"; "")))
                and ($raw | IN("1", "已做", "已提交", "0", "未做", "未提交") | not)
            else false
            end;
        (.data | type) == "object"
          and ((.data | keys | sort) == (["termCode", "termName", "assignments"] | sort))
          and ((.data.termCode | type) == "string" and (.data.termCode | length) > 0)
          and ((.data.termName == null) or ((.data.termName | type) == "string"))
          and ((.data.assignments | type) == "array")
          and (.data.assignments | all(
            ((keys | sort) == ([
              "assignmentId",
              "courseId",
              "courseName",
              "teacherName",
              "title",
              "startTime",
              "dueTime",
              "score",
              "submissionStatus",
              "submissionStatusText"
            ] | sort))
              and (.assignmentId | type) == "string" and (.assignmentId | length) > 0
              and (.courseId | type) == "string"
              and (.courseName | type) == "string"
              and ((.teacherName == null) or ((.teacherName | type) == "string"))
              and (.title | type) == "string" and (.title | length) > 0
              and ((.startTime == null) or ((.startTime | type) == "string"))
              and ((.dueTime == null) or ((.dueTime | type) == "string"))
              and ((.score == null) or ((.score | type) == "string"))
              and (.submissionStatus | IN("SUBMITTED", "UNSUBMITTED", "UNKNOWN"))
              and (.submissionStatusText | type) == "string"
              and (if .submissionStatus == "SUBMITTED" then .submissionStatusText == "已提交"
                elif .submissionStatus == "UNSUBMITTED" then .submissionStatusText == "未提交"
                else (.submissionStatusText | unknown_summary_text)
                end)
          ))
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    spoc_detail)
      jq -e '
        def unknown_summary_text:
          . as $text
          | if ($text | test("^未知状态\\(.+\\)$")) then
              ($text | capture("^未知状态\\((?<raw>.+)\\)$").raw) as $raw
              | ($raw == ($raw | gsub("^\\s+|\\s+$"; "")))
                and ($raw | IN("1", "已做", "已提交", "0", "未做", "未提交") | not)
            else false
            end;
        (.data | type) == "object"
          and ((.data | keys | sort) == ([
            "assignmentId",
            "courseId",
            "courseName",
            "teacherName",
            "title",
            "startTime",
            "dueTime",
            "score",
            "submissionStatus",
            "submissionStatusText",
            "contentPlainText",
            "submittedAt"
          ] | sort))
          and ((.data.assignmentId | type) == "string" and (.data.assignmentId | length) > 0)
          and ((.data.courseId | type) == "string")
          and ((.data.courseName | type) == "string")
          and ((.data.teacherName == null) or ((.data.teacherName | type) == "string"))
          and ((.data.title | type) == "string" and (.data.title | length) > 0)
          and ((.data.startTime == null) or ((.data.startTime | type) == "string"))
          and ((.data.dueTime == null) or ((.data.dueTime | type) == "string"))
          and ((.data.score == null) or ((.data.score | type) == "string"))
          and (.data.submissionStatus | IN("SUBMITTED", "UNSUBMITTED", "UNKNOWN"))
          and ((.data.submissionStatusText | type) == "string")
          and (if .data.submissionStatus == "SUBMITTED" then .data.submissionStatusText == "已提交"
            elif .data.submissionStatus == "UNSUBMITTED" then .data.submissionStatusText == "未提交"
            else (.data.submissionStatusText == "未知状态"
              or (.data.submissionStatusText | unknown_summary_text))
            end)
          and ((.data.contentPlainText == null) or ((.data.contentPlainText | type) == "string"))
          and ((.data.submittedAt == null) or ((.data.submittedAt | type) == "string"))
          and (.data | has("contentHtml") | not)
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    spoc_diagnostics)
      jq -e '
        def unknown_summary_text:
          . as $text
          | if ($text | test("^未知状态\\(.+\\)$")) then
              ($text | capture("^未知状态\\((?<raw>.+)\\)$").raw) as $raw
              | ($raw == ($raw | gsub("^\\s+|\\s+$"; "")))
                and ($raw | IN("1", "已做", "已提交", "0", "未做", "未提交") | not)
            else false
            end;
        (.data | type) == "object"
          and ((.data | keys | sort) == (["globalPageCount", "result"] | sort))
          and (.data.globalPageCount | type == "number" and floor == . and . >= 1 and . <= 4294967295)
          and ((.data.result | type) == "object")
          and ((.data.result | keys | sort) == (["termCode", "termName", "assignments"] | sort))
          and ((.data.result.termCode | type) == "string" and (.data.result.termCode | length) > 0)
          and ((.data.result.termName == null) or ((.data.result.termName | type) == "string"))
          and ((.data.result.assignments | type) == "array")
          and (.data.result.assignments | all(
            ((keys | sort) == ([
              "assignmentId",
              "courseId",
              "courseName",
              "teacherName",
              "title",
              "startTime",
              "dueTime",
              "score",
              "submissionStatus",
              "submissionStatusText"
            ] | sort))
              and (.assignmentId | type) == "string" and (.assignmentId | length) > 0
              and (.courseId | type) == "string"
              and (.courseName | type) == "string"
              and ((.teacherName == null) or ((.teacherName | type) == "string"))
              and (.title | type) == "string" and (.title | length) > 0
              and ((.startTime == null) or ((.startTime | type) == "string"))
              and ((.dueTime == null) or ((.dueTime | type) == "string"))
              and ((.score == null) or ((.score | type) == "string"))
              and (.submissionStatus | IN("SUBMITTED", "UNSUBMITTED", "UNKNOWN"))
              and (.submissionStatusText | type) == "string"
              and (if .submissionStatus == "SUBMITTED" then .submissionStatusText == "已提交"
                elif .submissionStatus == "UNSUBMITTED" then .submissionStatusText == "未提交"
                else (.submissionStatusText | unknown_summary_text)
                end)
          ))
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    judge)
      jq -e '
        def numeric_id:
          type == "string" and length > 0 and test("^\\d+$");
        def captured_score:
          . == null or (type == "string" and test("^[0-9]+(?:\\.[0-9]+)?$"));
        def judge_status_text_ok:
          if .submissionStatus == "SUBMITTED" then
            if .myScore != null and .myScore != "" and .maxScore != null and .maxScore != "" then
              . as $item
              | "^已完成 (?<mine>[0-9]+(?:\\.[0-9]+)?)/(?<maximum>[0-9]+(?:\\.[0-9]+)?)$" as $pattern
              | ($item.submissionStatusText | test($pattern)) as $matches
              | if $matches then
                  ($item.submissionStatusText | capture($pattern)) as $scores
                  | (($scores.mine | tonumber) == ($item.myScore | tonumber))
                    and (($scores.maximum | tonumber) == ($item.maxScore | tonumber))
                else false
                end
            else .submissionStatusText == "已完成"
            end
          elif .submissionStatus == "PARTIAL" then
            .submissionStatusText == ("进行中(" + (.submittedCount | tostring) + "/" + (.totalProblems | tostring) + ")")
          elif .submissionStatus == "UNSUBMITTED" then .submissionStatusText == "未提交"
          else .submissionStatusText == "未知状态"
          end;
        (.data | type) == "array"
          and (.data | all(
            ((keys | sort) == ([
              "courseId",
              "courseName",
              "assignmentId",
              "title",
              "startTime",
              "dueTime",
              "maxScore",
              "myScore",
              "totalProblems",
              "submittedCount",
              "submissionStatus",
              "submissionStatusText"
            ] | sort))
              and (.courseId | numeric_id) and .courseId != "0"
              and (.courseName | type) == "string" and (.courseName | length) > 0
              and (.assignmentId | numeric_id)
              and (.title | type) == "string" and (.title | length) > 0
              and ((.startTime == null) or ((.startTime | type) == "string"))
              and ((.dueTime == null) or ((.dueTime | type) == "string"))
              and (.maxScore | captured_score)
              and (.myScore | captured_score)
              and (.totalProblems | type == "number" and floor == . and . >= 0 and . <= 2147483647)
              and (.submittedCount | type == "number" and floor == . and . >= 0 and . <= 2147483647)
              and (.submissionStatus | IN("SUBMITTED", "PARTIAL", "UNSUBMITTED", "UNKNOWN"))
              and (.submissionStatusText | type) == "string"
              and (
                if .totalProblems <= 0 then .submissionStatus == "UNKNOWN"
                elif .submittedCount <= 0 then .submissionStatus == "UNSUBMITTED"
                elif .submittedCount < .totalProblems then .submissionStatus == "PARTIAL"
                else .submissionStatus == "SUBMITTED"
                end
              )
              and judge_status_text_ok
          ))
          and (([.data[] | [.courseId, .assignmentId]] | unique | length) == (.data | length))
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    judge_diagnostics)
      jq -e '
        def safe_count:
          type == "number" and floor == . and . >= 0 and . <= 9007199254740991;
        def numeric_id:
          type == "string" and length > 0 and test("^\\d+$");
        def captured_score:
          . == null or (type == "string" and test("^[0-9]+(?:\\.[0-9]+)?$"));
        def judge_status_text_ok:
          if .submissionStatus == "SUBMITTED" then
            if .myScore != null and .myScore != "" and .maxScore != null and .maxScore != "" then
              . as $item
              | "^已完成 (?<mine>[0-9]+(?:\\.[0-9]+)?)/(?<maximum>[0-9]+(?:\\.[0-9]+)?)$" as $pattern
              | ($item.submissionStatusText | test($pattern)) as $matches
              | if $matches then
                  ($item.submissionStatusText | capture($pattern)) as $scores
                  | (($scores.mine | tonumber) == ($item.myScore | tonumber))
                    and (($scores.maximum | tonumber) == ($item.maxScore | tonumber))
                else false
                end
            else .submissionStatusText == "已完成"
            end
          elif .submissionStatus == "PARTIAL" then
            .submissionStatusText == ("进行中(" + (.submittedCount | tostring) + "/" + (.totalProblems | tostring) + ")")
          elif .submissionStatus == "UNSUBMITTED" then .submissionStatusText == "未提交"
          else .submissionStatusText == "未知状态"
          end;
        (.data | type) == "object"
          and ((.data | keys | sort) == ([
            "courseCount",
            "rawAnchorCount",
            "filteredUniqueCount",
            "summaries"
          ] | sort))
          and (.data.courseCount | safe_count)
          and (.data.rawAnchorCount | safe_count)
          and (.data.filteredUniqueCount | safe_count)
          and (.data.rawAnchorCount >= .data.filteredUniqueCount)
          and ((.data.summaries | type) == "array")
          and (.data.filteredUniqueCount == (.data.summaries | length))
          and (([.data.summaries[].courseId] | unique | length) <= .data.courseCount)
          and (if .data.courseCount == 0 then
            .data.rawAnchorCount == 0
              and .data.filteredUniqueCount == 0
              and (.data.summaries | length) == 0
            else true
            end)
          and (.data.summaries | all(
            ((keys | sort) == ([
              "courseId",
              "courseName",
              "assignmentId",
              "title",
              "startTime",
              "dueTime",
              "maxScore",
              "myScore",
              "totalProblems",
              "submittedCount",
              "submissionStatus",
              "submissionStatusText"
            ] | sort))
              and (.courseId | numeric_id) and .courseId != "0"
              and (.courseName | type) == "string" and (.courseName | length) > 0
              and (.assignmentId | numeric_id)
              and (.title | type) == "string" and (.title | length) > 0
              and ((.startTime == null) or ((.startTime | type) == "string"))
              and ((.dueTime == null) or ((.dueTime | type) == "string"))
              and (.maxScore | captured_score)
              and (.myScore | captured_score)
              and (.totalProblems | type == "number" and floor == . and . >= 0 and . <= 2147483647)
              and (.submittedCount | type == "number" and floor == . and . >= 0 and . <= 2147483647)
              and (.submissionStatus | IN("SUBMITTED", "PARTIAL", "UNSUBMITTED", "UNKNOWN"))
              and (.submissionStatusText | type) == "string"
              and (
                if .totalProblems <= 0 then .submissionStatus == "UNKNOWN"
                elif .submittedCount <= 0 then .submissionStatus == "UNSUBMITTED"
                elif .submittedCount < .totalProblems then .submissionStatus == "PARTIAL"
                else .submissionStatus == "SUBMITTED"
                end
              )
              and judge_status_text_ok
          ))
          and (([.data.summaries[] | [.courseId, .assignmentId]] | unique | length)
            == (.data.summaries | length))
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    judge_detail)
      jq -e '
        def numeric_id:
          type == "string" and length > 0 and test("^\\d+$");
        def captured_score:
          . == null or (type == "string" and test("^[0-9]+(?:\\.[0-9]+)?$"));
        def problem_score:
          . == null or (type == "string" and test("^[0-9]+(?:\\.[0-9]+)?$"));
        def judge_status_text_ok:
          if .submissionStatus == "SUBMITTED" then
            if .myScore != null and .myScore != "" and .maxScore != null and .maxScore != "" then
              . as $item
              | "^已完成 (?<mine>[0-9]+(?:\\.[0-9]+)?)/(?<maximum>[0-9]+(?:\\.[0-9]+)?)$" as $pattern
              | ($item.submissionStatusText | test($pattern)) as $matches
              | if $matches then
                  ($item.submissionStatusText | capture($pattern)) as $scores
                  | (($scores.mine | tonumber) == ($item.myScore | tonumber))
                    and (($scores.maximum | tonumber) == ($item.maxScore | tonumber))
                else false
                end
            else .submissionStatusText == "已完成"
            end
          elif .submissionStatus == "PARTIAL" then
            .submissionStatusText == ("进行中(" + (.submittedCount | tostring) + "/" + (.totalProblems | tostring) + ")")
          elif .submissionStatus == "UNSUBMITTED" then .submissionStatusText == "未提交"
          else .submissionStatusText == "未知状态"
          end;
        (.data | type) == "object"
          and ((.data | keys | sort) == ([
            "courseId",
            "courseName",
            "assignmentId",
            "title",
            "startTime",
            "dueTime",
            "maxScore",
            "myScore",
            "totalProblems",
            "submittedCount",
            "submissionStatus",
            "submissionStatusText",
            "problems",
            "contentPlainText"
          ] | sort))
          and (.data.assignmentId | numeric_id)
          and (.data.courseId | numeric_id) and .data.courseId != "0"
          and ((.data.courseName | type) == "string" and (.data.courseName | length) > 0)
          and ((.data.title | type) == "string" and (.data.title | length) > 0)
          and ((.data.startTime == null) or ((.data.startTime | type) == "string"))
          and ((.data.dueTime == null) or ((.data.dueTime | type) == "string"))
          and (.data.maxScore | captured_score)
          and (.data.myScore | captured_score)
          and ((.data.contentPlainText == null) or ((.data.contentPlainText | type) == "string"))
          and (.data.totalProblems | type == "number" and floor == . and . >= 0 and . <= 2147483647)
          and (.data.submittedCount | type == "number" and floor == . and . >= 0 and . <= 2147483647)
          and (.data.submissionStatus | IN("SUBMITTED", "PARTIAL", "UNSUBMITTED", "UNKNOWN"))
          and ((.data.submissionStatusText | type) == "string")
          and ((.data.problems | type) == "array")
          and (.data.problems | all(
            ((keys | sort) == (["name", "score", "maxScore", "status", "statusText"] | sort))
              and (.name | type) == "string"
              and (.score | problem_score)
              and (.maxScore | problem_score)
              and (.status | IN("SUBMITTED", "UNSUBMITTED"))
              and (.statusText | type) == "string"
              and (if .status == "SUBMITTED" then .statusText == "已提交"
                else .statusText == "未提交"
                end)
          ))
          and (
            if .data.totalProblems <= 0 then .data.submissionStatus == "UNKNOWN"
            elif .data.submittedCount <= 0 then .data.submissionStatus == "UNSUBMITTED"
            elif .data.submittedCount < .data.totalProblems then .data.submissionStatus == "PARTIAL"
            else .data.submissionStatus == "SUBMITTED"
            end
          )
          and (.data | judge_status_text_ok)
          and (
            if (.data.problems | length) > 0 then
              .data.totalProblems > 0
                and .data.submittedCount
                == ([.data.problems[] | select(.status != "UNSUBMITTED")] | length)
            else true
            end
          )
      ' >/dev/null 2>&1 <<<"$CLI_OUTPUT"
      ;;
    *) return 1 ;;
  esac
}

validate_weeks_term() {
  local expected_term=$1
  jq -e --arg term "$expected_term" \
    '(.data | type) == "array" and (.data | all(.term == $term))' \
    >/dev/null 2>&1 <<<"$CLI_OUTPUT"
}

validate_schedule_code() {
  jq -e '(.data.code | type) == "string" and (.data.code | length) > 0' \
    >/dev/null 2>&1 <<<"$CLI_OUTPUT"
}

semantic_failure() {
  local stage=$1
  local route_value=${route:-$mode}
  CLI_CODE=1
  printf 'mode=%s route=%s feature=%s outcome=failed stage=%s exit_code=1 error=invalid_semantics\n' \
    "$mode" "$route_value" "$feature" "$stage"
}

feature_failure() {
  local stage=$1
  local error=$2
  local route_value=${route:-$mode}
  CLI_CODE=1
  printf 'mode=%s route=%s feature=%s outcome=failed stage=%s exit_code=1 error=%s\n' \
    "$mode" "$route_value" "$feature" "$stage" "$error"
}

capture_resolved_route() {
  local candidate
  candidate=$(jq -r '.meta.resolvedRoute // empty' <<<"$CLI_OUTPUT" 2>/dev/null)
  [[ "$candidate" == direct || "$candidate" == webvpn ]] || return 1
  if [[ -z ${FEATURE_RESOLVED_ROUTE:-} ]]; then
    FEATURE_RESOLVED_ROUTE=$candidate
  else
    [[ "$FEATURE_RESOLVED_ROUTE" == "$candidate" ]]
  fi
}

salted_assignment_digest() {
  local payload=$1
  local salt=${UBAA_VERIFY_DIGEST_SALT:-}
  [[ -n "$salt" ]] || return 1
  if command -v shasum >/dev/null 2>&1; then
    printf '%s%s' "$salt" "$payload" | shasum -a 256 | awk '{ print substr($1, 1, 16) }'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s%s' "$salt" "$payload" | sha256sum | awk '{ print substr($1, 1, 16) }'
  else
    return 1
  fi
}

redacted_failure() {
  local stage=$1
  local route_value=${route:-$mode}
  local feature_value=${feature:-auth}
  local code=unknown
  code=$(jq -r '.error.code // "invalid_output"' <<<"$CLI_OUTPUT" 2>/dev/null || true)
  case "$code" in
    invalid_input|authentication_required|invalid_credentials|password_risk_confirmation_failed|permission_denied|network_error|timeout|upstream_unavailable|upstream_changed|parse_error|internal_error) ;;
    *) code=invalid_output ;;
  esac
  printf 'mode=%s route=%s feature=%s outcome=failed stage=%s exit_code=%s error=%s\n' \
    "$mode" "$route_value" "$feature_value" "$stage" "$CLI_CODE" "$code"
}

run_login() {
  if [[ ${LOGIN_AGGREGATE:-no} == yes ]]; then
    run_json credentials auth login --username-stdin --password-stdin
  else
    run_json credentials auth login --mode "$mode" --username-stdin --password-stdin
  fi
  if [[ "$CLI_CODE" -ne 0 ]]; then
    redacted_failure login
    return "$CLI_CODE"
  fi
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
        echo "usage: $0 [direct|webvpn] [feature=auth|user|all|schedule|exam|grades|classroom|spoc|judge|signin|ygdk|libbook|bykc|cgyy|evaluation] [route=auto|direct|webvpn]" >&2
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
    auth|user|all|schedule|exam|grades|classroom|spoc|judge|signin|ygdk|libbook|bykc|cgyy|evaluation) ;;
    *) echo "unsupported feature: $feature" >&2; exit 2 ;;
  esac
  case "$route" in
    direct|webvpn|auto) ;;
    *) echo "unsupported route: $route" >&2; exit 2 ;;
  esac
  if [[ "$feature" == judge || "$feature" == all ]] \
    && [[ -z ${UBAA_VERIFY_DIGEST_SALT:-} ]]; then
    echo "Judge live verification requires UBAA_VERIFY_DIGEST_SALT for route comparison" >&2
    exit 2
  fi
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
  if [[ "$feature" != auth || "$route" == auto ]]; then
    LOGIN_AGGREGATE=yes
  else
    LOGIN_AGGREGATE=no
  fi

  if run_login; then
    :
  else
    exit "$CLI_CODE"
  fi
  if [[ "$LOGIN_AGGREGATE" == yes ]]; then
    login_valid=0
    validate_aggregate_auth_success all || login_valid=$?
  else
    login_valid=0
    validate_explicit_login_success || login_valid=$?
  fi
  if [[ "$login_valid" -ne 0 ]]; then
    semantic_failure login
    exit 1
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
  if ! validate_routed_success user || ! validate_user_profile no; then
    semantic_failure user_show
    exit 1
  fi

  run_json none auth status
  if [[ "$CLI_CODE" -ne 0 ]]; then
    redacted_failure auth_status
    exit "$CLI_CODE"
  fi
  required_status_route=$route
  if [[ "$route" == auto ]]; then
    required_status_route=all
  fi
  if ! validate_aggregate_auth_success "$required_status_route"; then
    semantic_failure auth_status
    exit 1
  fi

  printf 'mode=%s outcome=success stage=auth_status exit_code=0 route=%s feature=%s elapsed_ms=%s parsed_user=yes\n' \
    "$mode" "$route" "$feature" "$CLI_ELAPSED_MS"
}

run_readonly_feature() {
  local term week date campus count original_feature subfeature child_failure
  if [[ "$feature" == all ]]; then
    original_feature=$feature
    local first_failure=0
    for subfeature in user schedule exam grades classroom spoc judge signin ygdk libbook bykc cgyy evaluation; do
      feature=$subfeature
      if run_readonly_feature; then
        :
      else
        child_failure=$?
        if [[ "$child_failure" -eq 0 ]]; then
          child_failure=1
        fi
        if [[ "$first_failure" -eq 0 ]]; then
          first_failure=$child_failure
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
  FEATURE_ELAPSED_MS=0
  FEATURE_RESOLVED_ROUTE=
  TRACK_FEATURE_TIME=yes
  case "$feature" in
    user)
      run_json none user show
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure user; return "$CLI_CODE"; fi
      if ! validate_routed_success user || ! validate_user_profile no || ! capture_resolved_route; then semantic_failure user; return 1; fi
      printf 'mode=%s route=%s resolved_route=%s feature=user outcome=success stage=user exit_code=0 elapsed_ms=%s\n' "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$FEATURE_ELAPSED_MS"
      ;;
    schedule)
      run_json none schedule terms
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_terms; return "$CLI_CODE"; fi
      if ! validate_feature_data schedule_terms || ! capture_resolved_route; then semantic_failure schedule_terms; return 1; fi
      term=$(jq -r '([.data[] | select(.selected == true)] | if length == 1 then .[0].itemCode else empty end) // .data[0].itemCode // empty' <<<"$CLI_OUTPUT")
      [[ -n "$term" ]] || { feature_failure schedule_terms empty_terms; return 1; }
      run_json none schedule weeks --term "$term"
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_weeks; return "$CLI_CODE"; fi
      if ! validate_feature_data schedule_weeks \
        || ! validate_weeks_term "$term" \
        || ! capture_resolved_route; then
        semantic_failure schedule_weeks
        return 1
      fi
      week=$(jq -r '([.data[] | select(.curWeek == true)] | if length == 1 then .[0].serialNumber else empty end) // .data[0].serialNumber // empty' <<<"$CLI_OUTPUT")
      [[ "$week" =~ ^[1-9][0-9]*$ ]] || { feature_failure schedule_weeks empty_weeks; return 1; }
      run_json none schedule current --term "$term" --week "$week"
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_current; return "$CLI_CODE"; fi
      if ! validate_feature_data schedule_current \
        || ! validate_schedule_code \
        || ! capture_resolved_route; then
        semantic_failure schedule_current
        return 1
      fi
      run_json none schedule today
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_today; return "$CLI_CODE"; fi
      if ! validate_feature_data schedule_today || ! capture_resolved_route; then semantic_failure schedule_today; return 1; fi
      if ! capture_resolved_route; then semantic_failure schedule_route; return 1; fi
      printf 'mode=%s route=%s resolved_route=%s feature=%s outcome=success stage=schedule exit_code=0 elapsed_ms=%s term_present=yes week=%s\n' \
        "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$feature" "$FEATURE_ELAPSED_MS" "$week"
      ;;
    exam|grades)
      run_json none schedule terms
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure schedule_terms; return "$CLI_CODE"; fi
      if ! validate_feature_data schedule_terms || ! capture_resolved_route; then semantic_failure schedule_terms; return 1; fi
      term=$(jq -r '([.data[] | select(.selected == true)] | if length == 1 then .[0].itemCode else empty end) // .data[0].itemCode // empty' <<<"$CLI_OUTPUT")
      [[ -n "$term" ]] || { feature_failure schedule_terms empty_terms; return 1; }
      if [[ "$feature" == exam ]]; then
        run_json none exam list --term "$term"
      else
        run_json none grades list --term "$term"
      fi
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure "$feature"; return "$CLI_CODE"; fi
      if ! validate_feature_data "$feature" || ! capture_resolved_route; then semantic_failure "$feature"; return 1; fi
      if [[ "$feature" == grades && ! "$term" =~ ^[0-9]{4}-[0-9]{4}-[12]$ ]]; then
        semantic_failure grades_term
        return 1
      fi
      if [[ "$feature" == grades ]] \
        && ! jq -e --arg term "$term" '.data.termCode == $term' >/dev/null 2>&1 <<<"$CLI_OUTPUT"; then
        semantic_failure grades_term_mismatch
        return 1
      fi
      if ! capture_resolved_route; then semantic_failure "${feature}_route"; return 1; fi
      printf 'mode=%s route=%s resolved_route=%s feature=%s outcome=success stage=%s exit_code=0 elapsed_ms=%s term_present=yes\n' \
        "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$feature" "$feature" "$FEATURE_ELAPSED_MS"
      ;;
    classroom)
      date=${UBAA_VERIFY_DATE:-$(TZ=Asia/Shanghai date +%F)}
      campus=${UBAA_VERIFY_CAMPUS_ID:-1}
      run_json none classroom search --campus "$campus" --date "$date"
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure classroom; return "$CLI_CODE"; fi
      if ! validate_feature_data classroom || ! capture_resolved_route; then semantic_failure classroom; return 1; fi
      count=$(jq -r '[.data.floors[]?[]?] | length' <<<"$CLI_OUTPUT" 2>/dev/null || printf '0')
      if ! capture_resolved_route; then semantic_failure classroom_route; return 1; fi
      printf 'mode=%s route=%s resolved_route=%s feature=%s outcome=success stage=classroom exit_code=0 elapsed_ms=%s result_count=%s date=%s\n' \
        "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$feature" "$FEATURE_ELAPSED_MS" "$count" "$date"
      ;;
    spoc)
      local spoc_pages spoc_assignments_json
      run_json none spoc diagnostics
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure spoc; return "$CLI_CODE"; fi
      if ! validate_feature_data spoc_diagnostics || ! capture_resolved_route; then semantic_failure spoc; return 1; fi
      spoc_assignments_json=$CLI_OUTPUT
      spoc_pages=$(jq -r '.data.globalPageCount' <<<"$CLI_OUTPUT")
      count=$(jq -r '.data.result.assignments | length' <<<"$CLI_OUTPUT" 2>/dev/null || printf '0')
      if [[ "$count" -gt 0 ]]; then
        local assignment_id course_id
        assignment_id=$(jq -r '.data.result.assignments[0].assignmentId // empty' <<<"$CLI_OUTPUT")
        course_id=$(jq -r '.data.result.assignments[0].courseId // empty' <<<"$CLI_OUTPUT")
        run_json none spoc assignment show --id "$assignment_id"
        if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure spoc_detail; return "$CLI_CODE"; fi
        if ! validate_feature_data spoc_detail || ! capture_resolved_route; then
          semantic_failure spoc_detail
          return 1
        fi
        if ! printf '%s\n%s\n' "$spoc_assignments_json" "$CLI_OUTPUT" | jq -s -e '
          .[0].data.result.assignments[0] as $expected
          | .[1].data.courseId == $expected.courseId
            and .[1].data.assignmentId == $expected.assignmentId
        ' >/dev/null 2>&1; then
          semantic_failure spoc_detail
          return 1
        fi
      fi
      printf 'mode=%s route=%s resolved_route=%s feature=%s outcome=success stage=spoc exit_code=0 elapsed_ms=%s result_count=%s global_page_count=%s detail_success=%s\n' \
        "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$feature" "$FEATURE_ELAPSED_MS" \
        "$count" "$spoc_pages" "$([[ "$count" -gt 0 ]] && printf yes || printf not_applicable)"
      ;;
    judge)
      local all_json all_count current_json current_count course_count cutoff_skip_count
      local raw_anchor_count filtered_unique_count assignment_payload assignment_digest
      local detail_success digest_comparable sample_json
      run_json none judge diagnostics --include-expired
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure judge_all; return "$CLI_CODE"; fi
      if ! validate_feature_data judge_diagnostics || ! capture_resolved_route; then semantic_failure judge_all; return 1; fi
      all_json=$CLI_OUTPUT
      all_count=$(jq -r '.data.summaries | length' <<<"$all_json")
      course_count=$(jq -r '.data.courseCount' <<<"$all_json")
      raw_anchor_count=$(jq -r '.data.rawAnchorCount' <<<"$all_json")
      filtered_unique_count=$(jq -r '.data.filteredUniqueCount' <<<"$all_json")
      run_json none judge assignments
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure judge; return "$CLI_CODE"; fi
      if ! validate_feature_data judge || ! capture_resolved_route; then semantic_failure judge; return 1; fi
      current_json=$CLI_OUTPUT
      current_count=$(jq -r '.data | length' <<<"$current_json")
      if ! printf '%s\n%s\n' "$all_json" "$current_json" | jq -s -e '
        .[0] as $all
        | .[1] as $current
        | ($all.data.summaries | map([.courseId, .assignmentId])) as $all_keys
        | ($current.data | all([.courseId, .assignmentId] as $key | $all_keys | any(. == $key)))
      ' >/dev/null 2>&1; then
        semantic_failure judge_cutoff
        return 1
      fi
      count=$current_count
      cutoff_skip_count=$(( all_count - current_count ))
      assignment_payload=$(jq -c '[.data.summaries[] | [.courseId, .assignmentId]] | sort' <<<"$all_json")
      digest_comparable=yes
      assignment_digest=$(salted_assignment_digest "$assignment_payload") || {
        semantic_failure judge_digest
        return 1
      }
      detail_success=not_applicable
      sample_json=$current_json
      if [[ "$current_count" -eq 0 && "$all_count" -gt 0 ]]; then
        sample_json=$all_json
      fi
      if [[ "$all_count" -gt 0 ]]; then
        local course_id assignment_id
        # The first returned assignment is the verifier's single detail sample.
        # A later list can change while the separate detail CLI process starts;
        # choosing the first response item avoids inventing a stale-ID contract.
        course_id=$(jq -r 'if (.data | type) == "array" then .data[0].courseId else .data.summaries[0].courseId end // empty' <<<"$sample_json")
        assignment_id=$(jq -r 'if (.data | type) == "array" then .data[0].assignmentId else .data.summaries[0].assignmentId end // empty' <<<"$sample_json")
        run_json none judge assignment show --course-id "$course_id" --id "$assignment_id"
        if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure judge_detail; return "$CLI_CODE"; fi
        if ! validate_feature_data judge_detail || ! capture_resolved_route; then
          semantic_failure judge_detail
          return 1
        fi
        if ! printf '%s\n%s\n' "$sample_json" "$CLI_OUTPUT" | jq -s -e '
          .[0].data as $source
          | ($source | if type == "array" then .[0] else .summaries[0] end) as $expected
          | .[1].data.courseId == $expected.courseId
            and .[1].data.assignmentId == $expected.assignmentId
        ' >/dev/null 2>&1; then
          semantic_failure judge_detail
          return 1
        fi
        detail_success=yes
      fi
      if ! capture_resolved_route; then semantic_failure judge_route; return 1; fi
      printf 'mode=%s route=%s resolved_route=%s feature=%s outcome=success stage=judge exit_code=0 elapsed_ms=%s course_count=%s raw_anchor_count=%s filtered_unique_count=%s current_count=%s cutoff_skip_count=%s detail_success=%s digest=%s digest_comparable=%s\n' \
        "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$feature" "$FEATURE_ELAPSED_MS" \
        "$course_count" "$raw_anchor_count" "$filtered_unique_count" "$current_count" \
        "$cutoff_skip_count" "$detail_success" "$assignment_digest" "$digest_comparable"
      ;;
    signin)
      run_json none signin today
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure signin; return "$CLI_CODE"; fi
      if ! validate_routed_success signin || ! jq -e '(.data | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure signin; return 1; fi
      count=$(jq -r '.data | length' <<<"$CLI_OUTPUT")
      printf 'mode=%s route=%s resolved_route=%s feature=signin outcome=success stage=signin exit_code=0 elapsed_ms=%s result_count=%s\n' "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$FEATURE_ELAPSED_MS" "$count"
      ;;
    ygdk)
      run_json none ygdk overview
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure ygdk; return "$CLI_CODE"; fi
      if ! validate_routed_success ygdk || ! jq -e '(.data | type) == "object" and (.data.items | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure ygdk; return 1; fi
      count=$(jq -r '.data.items | length' <<<"$CLI_OUTPUT")
      run_json none ygdk records --page 1 --size 20
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure ygdk_records; return "$CLI_CODE"; fi
      if ! validate_routed_success ygdk || ! jq -e '(.data | type) == "object" and (.data.content | type) == "array" and (.data.page | type) == "number" and (.data.size | type) == "number" and (.data.hasMore | type) == "boolean"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure ygdk_records; return 1; fi
      printf 'mode=%s route=%s resolved_route=%s feature=ygdk outcome=success stage=ygdk exit_code=0 elapsed_ms=%s item_count=%s\n' "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$FEATURE_ELAPSED_MS" "$count"
      ;;
    libbook)
      date=${UBAA_VERIFY_DATE:-$(TZ=Asia/Shanghai date +%F)}
      run_json none libbook libraries --day "$date"
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure libbook; return "$CLI_CODE"; fi
      if ! validate_routed_success libbook || ! jq -e '(.data | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure libbook; return 1; fi
      count=$(jq -r '.data | length' <<<"$CLI_OUTPUT")
      local premises_id storey_id area_id
      premises_id=$(jq -r '.data[0].id // empty' <<<"$CLI_OUTPUT")
      storey_id=$(jq -r '.data[0].storeys[0].id // empty' <<<"$CLI_OUTPUT")
      if [[ -n "$premises_id" ]]; then
        if [[ -n "$storey_id" ]]; then
          run_json none libbook areas --premises-id "$premises_id" --storey-id "$storey_id" --day "$date"
        else
          run_json none libbook areas --premises-id "$premises_id" --day "$date"
        fi
        if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure libbook_areas; return "$CLI_CODE"; fi
        if ! validate_routed_success libbook || ! jq -e '(.data | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure libbook_areas; return 1; fi
        area_id=$(jq -r '.data[0].id // empty' <<<"$CLI_OUTPUT")
        if [[ -n "$area_id" ]]; then
          run_json none libbook area-detail --area-id "$area_id"
          if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure libbook_area_detail; return "$CLI_CODE"; fi
          if ! validate_routed_success libbook || ! jq -e '(.data | type) == "object" and (.data.id | type) == "string" and (.data.timeSlots | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure libbook_area_detail; return 1; fi
          run_json none libbook seats --area-id "$area_id" --day "$date" --start-time 00:00 --end-time 23:59
          if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure libbook_seats; return "$CLI_CODE"; fi
          if ! validate_routed_success libbook || ! jq -e '(.data | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure libbook_seats; return 1; fi
        fi
      fi
      run_json none libbook bookings --page 1 --limit 20
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure libbook_bookings; return "$CLI_CODE"; fi
      if ! validate_routed_success libbook || ! jq -e '(.data | type) == "object" and (.data.bookings | type) == "array" and (.data.page | type) == "number" and (.data.limit | type) == "number" and (.data.total | type) == "number"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure libbook_bookings; return 1; fi
      printf 'mode=%s route=%s resolved_route=%s feature=libbook outcome=success stage=libbook exit_code=0 elapsed_ms=%s library_count=%s\n' "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$FEATURE_ELAPSED_MS" "$count"
      ;;
    bykc)
      run_json none bykc profile
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure bykc_profile; return "$CLI_CODE"; fi
      if ! validate_routed_success bykc || ! jq -e '(.data | type) == "object"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure bykc_profile; return 1; fi
      run_json none bykc courses --page 1 --size 20
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure bykc; return "$CLI_CODE"; fi
      if ! validate_routed_success bykc || ! jq -e '(.data | type) == "object" and (.data.content | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure bykc; return 1; fi
      count=$(jq -r '.data.content | length' <<<"$CLI_OUTPUT")
      local bykc_course_id
      bykc_course_id=$(jq -r '.data.content[0].id // empty' <<<"$CLI_OUTPUT")
      if [[ -n "$bykc_course_id" ]]; then
        run_json none bykc course --id "$bykc_course_id"
        if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure bykc_course; return "$CLI_CODE"; fi
        if ! validate_routed_success bykc || ! jq -e '(.data | type) == "object"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure bykc_course; return 1; fi
      fi
      run_json none bykc chosen
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure bykc_chosen; return "$CLI_CODE"; fi
      if ! validate_routed_success bykc || ! jq -e '(.data | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure bykc_chosen; return 1; fi
      run_json none bykc statistics
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure bykc_statistics; return "$CLI_CODE"; fi
      if ! validate_routed_success bykc || ! jq -e '(.data | type) == "object"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure bykc_statistics; return 1; fi
      printf 'mode=%s route=%s resolved_route=%s feature=bykc outcome=success stage=bykc exit_code=0 elapsed_ms=%s course_count=%s\n' "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$FEATURE_ELAPSED_MS" "$count"
      ;;
    cgyy)
      run_json none cgyy sites
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure cgyy; return "$CLI_CODE"; fi
      if ! validate_routed_success cgyy || ! jq -e '(.data | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure cgyy; return 1; fi
      count=$(jq -r '.data | length' <<<"$CLI_OUTPUT")
      local cgyy_site_id cgyy_date cgyy_order_id
      cgyy_site_id=$(jq -r '.data[0].id // empty' <<<"$CLI_OUTPUT")
      printf 'mode=%s route=%s resolved_route=%s feature=cgyy outcome=success stage=cgyy exit_code=0 elapsed_ms=%s site_count=%s\n' "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$FEATURE_ELAPSED_MS" "$count"
      run_json none cgyy purposes
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure cgyy_purposes; return "$CLI_CODE"; fi
      if ! validate_routed_success cgyy || ! jq -e '(.data | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure cgyy_purposes; return 1; fi
      cgyy_date=${UBAA_VERIFY_DATE:-$(TZ=Asia/Shanghai date +%F)}
      if [[ -n "$cgyy_site_id" ]]; then
        run_json none cgyy day --site-id "$cgyy_site_id" --date "$cgyy_date"
        if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure cgyy_day; return "$CLI_CODE"; fi
        if ! validate_routed_success cgyy || ! jq -e '(.data | type) == "object" and (.data.timeSlots | type) == "array" and (.data.spaces | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure cgyy_day; return 1; fi
      fi
      run_json none cgyy orders --page 0 --size 20
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure cgyy_orders; return "$CLI_CODE"; fi
      if ! validate_routed_success cgyy || ! jq -e '(.data | type) == "object" and (.data.content | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure cgyy_orders; return 1; fi
      cgyy_order_id=$(jq -r '.data.content[0].id // empty' <<<"$CLI_OUTPUT")
      if [[ -n "$cgyy_order_id" ]]; then
        run_json none cgyy detail --id "$cgyy_order_id"
        if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure cgyy_detail; return "$CLI_CODE"; fi
        if ! validate_routed_success cgyy || ! jq -e '(.data | type) == "object" and (.data.id | type) == "number"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure cgyy_detail; return 1; fi
      fi
      run_json none cgyy lock-code
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure cgyy_lock_code; return "$CLI_CODE"; fi
      if ! validate_routed_success cgyy || ! jq -e '(.data | type) == "object" and (.data | has("rawData"))' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure cgyy_lock_code; return 1; fi
      ;;
    evaluation)
      run_json none evaluation all
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure evaluation; return "$CLI_CODE"; fi
      if ! validate_routed_success evaluation || ! jq -e '(.data | type) == "object" and (.data.courses | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure evaluation; return 1; fi
      local count
      count=$(jq -r '.data.courses | length' <<<"$CLI_OUTPUT")
      run_json none evaluation pending
      if [[ "$CLI_CODE" -ne 0 ]]; then redacted_failure evaluation_pending; return "$CLI_CODE"; fi
      if ! validate_routed_success evaluation || ! jq -e '(.data | type) == "array"' >/dev/null 2>&1 <<<"$CLI_OUTPUT" || ! capture_resolved_route; then semantic_failure evaluation_pending; return 1; fi
      printf 'mode=%s route=%s resolved_route=%s feature=evaluation outcome=success stage=evaluation exit_code=0 elapsed_ms=%s course_count=%s\n' "$mode" "$route" "$FEATURE_RESOLVED_ROUTE" "$FEATURE_ELAPSED_MS" "$count"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
