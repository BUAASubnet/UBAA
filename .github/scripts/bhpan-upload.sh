#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
SSO_URL="https://sso.buaa.edu.cn"
BHPAN_URL="https://bhpan.buaa.edu.cn"
COOKIE_JAR="$(mktemp)"
ARTIFACT_DIR="${1:?Usage: $0 <artifact-directory>}"

cleanup() { rm -f "$COOKIE_JAR"; }
trap cleanup EXIT

# --- Helpers ---
get_token() {
  grep "client.oauth2_token" "$COOKIE_JAR" 2>/dev/null | awk '{print $NF}' | tr -d '\r'
}

api_call() {
  local method="$1" endpoint="$2"
  shift 2
  local token
  token=$(get_token)
  curl -sSf --connect-timeout 30 --max-time 60 \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X "$method" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${token}" \
    "$@" \
    "${BHPAN_URL}${endpoint}"
}

# --- SSO Login ---
sso_login() {
  echo "Logging in to SSO..."

  # Step 1: GET login page, extract execution token
  local login_page
  login_page=$(curl -sS --connect-timeout 30 \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    "${SSO_URL}/login")

  local execution
  execution=$(echo "$login_page" | sed -n 's/.*name="execution" value="\([^"]*\)".*/\1/p' | head -1)
  if [[ -z "$execution" ]]; then
    echo "::error::Failed to extract execution token from SSO login page"
    exit 1
  fi

  # Step 2: POST login form
  curl -sS --connect-timeout 30 --max-time 60 \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -L -o /dev/null \
    -X POST "${SSO_URL}/login" \
    --data-urlencode "username=${BHPAN_SSO_USERNAME}" \
    --data-urlencode "password=${BHPAN_SSO_PASSWORD}" \
    --data-urlencode "submit=LOGIN" \
    --data-urlencode "type=username_password" \
    --data-urlencode "execution=${execution}" \
    --data-urlencode "_eventId=submit"

  # Step 3: Handle potential security warning (ignoreAndContinue)
  local has_tgc
  has_tgc=$(grep -c "TGC" "$COOKIE_JAR" 2>/dev/null || true)
  if [[ "$has_tgc" -eq 0 ]]; then
    local cont_page
    cont_page=$(curl -sS --connect-timeout 30 \
      -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
      "${SSO_URL}/login")
    execution=$(echo "$cont_page" | sed -n 's/.*name="execution" value="\([^"]*\)".*/\1/p' | head -1)
    if [[ -n "$execution" ]]; then
      curl -sS --connect-timeout 30 --max-time 60 \
        -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
        -L -o /dev/null \
        -X POST "${SSO_URL}/login" \
        --data-urlencode "username=${BHPAN_SSO_USERNAME}" \
        --data-urlencode "password=${BHPAN_SSO_PASSWORD}" \
        --data-urlencode "submit=LOGIN" \
        --data-urlencode "type=username_password" \
        --data-urlencode "execution=${execution}" \
        --data-urlencode "_eventId=ignoreAndContinue"
    fi
  fi

  echo "SSO login completed."
}

# --- Cloud Disk OAuth2 Auth ---
bhpan_auth() {
  echo "Authenticating with BUAA Cloud Disk..."

  # Hop 1: /anyshare/oauth2/login -> /oauth2/auth
  local auth_url
  auth_url=$(curl -sS --connect-timeout 30 \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -o /dev/null -w "%{redirect_url}" \
    "${BHPAN_URL}/anyshare/oauth2/login?redirect=%2Fanyshare%2Fzh-cn%2Fportal")

  if [[ -z "$auth_url" ]]; then
    echo "::error::No redirect from OAuth2 login endpoint"
    exit 1
  fi

  # Hop 2: /oauth2/auth -> /oauth2/signin?login_challenge=...
  local signin_url
  signin_url=$(curl -sS --connect-timeout 30 \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -o /dev/null -w "%{redirect_url}" \
    "$auth_url")

  local login_challenge
  login_challenge=$(echo "$signin_url" | sed -n 's/.*login_challenge=\([^&]*\).*/\1/p')

  if [[ -z "$login_challenge" ]]; then
    echo "::error::No login_challenge in redirect chain"
    exit 1
  fi

  # Set login_challenge cookie (required by bhpan)
  echo "#HttpOnly_bhpan.buaa.edu.cn	FALSE	/	TRUE	0	login_challenge	${login_challenge}" >> "$COOKIE_JAR"

  # Hop 3: SSO with service param (uses existing SSO session, redirects back to bhpan)
  local callback_url
  callback_url=$(curl -sS --connect-timeout 30 --max-time 60 \
    -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -L -o /dev/null -w "%{url_effective}" \
    "${SSO_URL}/login?service=https%3A%2F%2Fbhpan.buaa.edu.cn%2Foauth2%2Fsignin")

  if [[ "$callback_url" != *"/login/callback"* ]]; then
    echo "::error::OAuth2 redirect did not land on callback. Got: ${callback_url}"
    exit 1
  fi

  # Verify we got the OAuth token
  if ! grep -q "client.oauth2_token" "$COOKIE_JAR" 2>/dev/null; then
    echo "::error::Failed to obtain OAuth2 token from bhpan"
    exit 1
  fi

  echo "Cloud Disk authentication completed."
}

# --- Directory Listing ---
list_dir() {
  local docid="$1"
  api_call POST "/api/efast/v1/dir/list" \
    -d "{\"by\":\"name\",\"docid\":\"${docid}\",\"sort\":\"asc\"}"
}

# --- Delete Old Files ---
delete_old_files() {
  echo "Listing files in shared folder..."
  local listing
  listing=$(list_dir "$BHPAN_SHARED_FOLDER_DOCID")

  # Extract docids of files starting with "UBAA-"
  local old_docids
  old_docids=$(echo "$listing" | jq -r '.files[] | select(.name | startswith("UBAA-")) | .docid' | tr -d '\r')

  local count
  count=$(echo "$old_docids" | grep -c '.' || true)
  echo "Found ${count} old UBAA files to delete."

  while IFS= read -r docid; do
    [[ -z "$docid" ]] && continue
    local name
    name=$(echo "$listing" | jq -r ".files[] | select(.docid == \"${docid}\") | .name" | tr -d '\r')
    echo "  Deleting: ${name}"
    api_call POST "/api/efast/v1/file/delete" \
      -d "{\"docid\":\"${docid}\"}" || echo "  Warning: failed to delete ${name}, continuing..."
  done <<< "$old_docids"

  echo "Old file cleanup completed."
}

# --- Upload Single File ---
upload_file() {
  local filepath="$1"
  local filename
  filename=$(basename "$filepath")
  local filesize
  filesize=$(stat -c%s "$filepath")
  local client_mtime
  client_mtime=$(date +%s%3N)

  echo "  Uploading: ${filename} (${filesize} bytes)"

  # Step 1: Begin upload
  local begin_response
  begin_response=$(api_call POST "/api/efast/v1/file/osbeginupload" \
    -d "{\"client_mtime\":${client_mtime},\"docid\":\"${BHPAN_SHARED_FOLDER_DOCID}\",\"length\":${filesize},\"name\":\"${filename}\",\"ondup\":1}")

  local put_url docid rev
  put_url=$(echo "$begin_response" | jq -r '.authrequest[1]' | tr -d '\r')
  docid=$(echo "$begin_response" | jq -r '.docid' | tr -d '\r')
  rev=$(echo "$begin_response" | jq -r '.rev' | tr -d '\r')

  if [[ "$put_url" == "null" || -z "$put_url" ]]; then
    echo "::error::Failed to begin upload for ${filename}"
    echo "  Response: ${begin_response}"
    return 1
  fi

  # Step 2: PUT file content with auth headers (authrequest is an array: [method, url, header1, header2, ...])
  local -a header_flags=()
  local header_count
  header_count=$(echo "$begin_response" | jq '.authrequest | length')
  for ((i = 2; i < header_count; i++)); do
    local hdr
    hdr=$(echo "$begin_response" | jq -r ".authrequest[$i]" | tr -d '\r')
    header_flags+=(-H "$hdr")
  done

  local max_retries=3
  local attempt=1
  while true; do
    if curl -sS --connect-timeout 30 --max-time 600 \
      -X PUT \
      "${header_flags[@]}" \
      -T "$filepath" \
      -o /dev/null \
      "$put_url"; then
      break
    fi
    if [[ $attempt -ge $max_retries ]]; then
      echo "::error::Failed to upload ${filename} after ${max_retries} attempts"
      return 1
    fi
    echo "  Retry ${attempt}/${max_retries} for ${filename}..."
    attempt=$((attempt + 1))
    sleep 5
  done

  # Step 3: End upload
  local end_response
  end_response=$(api_call POST "/api/efast/v1/file/osendupload" \
    -d "{\"docid\":\"${docid}\",\"rev\":\"${rev}\"}")

  if [[ -z "$end_response" ]] || echo "$end_response" | jq -e '.error' > /dev/null 2>&1; then
    echo "::error::osendupload failed for ${filename}"
    echo "  Response: ${end_response}"
    return 1
  fi

  echo "  Uploaded: ${filename}"
}

# --- Upload All Artifacts ---
upload_all() {
  local count=0
  for filepath in "${ARTIFACT_DIR}"/UBAA-*; do
    [[ -f "$filepath" ]] || continue
    upload_file "$filepath"
    count=$((count + 1))
  done
  echo "Uploaded ${count} files to BUAA Cloud Disk."
}

# --- Main ---
echo "=== BUAA Cloud Disk Upload ==="
echo "Artifact directory: ${ARTIFACT_DIR}"

# Validate environment
if [[ -z "${BHPAN_SSO_USERNAME:-}" || -z "${BHPAN_SSO_PASSWORD:-}" || -z "${BHPAN_SHARED_FOLDER_DOCID:-}" ]]; then
  echo "::error::Missing required environment variables (BHPAN_SSO_USERNAME, BHPAN_SSO_PASSWORD, BHPAN_SHARED_FOLDER_DOCID)"
  exit 1
fi

# Validate artifact directory
if [[ ! -d "$ARTIFACT_DIR" ]]; then
  echo "::error::Artifact directory does not exist: ${ARTIFACT_DIR}"
  exit 1
fi

artifact_count=$(ls "${ARTIFACT_DIR}"/UBAA-* 2>/dev/null | wc -l)
if [[ "$artifact_count" -eq 0 ]]; then
  echo "::error::No UBAA-* artifacts found in ${ARTIFACT_DIR}"
  exit 1
fi
echo "Found ${artifact_count} artifacts to upload."

sso_login
bhpan_auth
delete_old_files
upload_all

echo "=== Upload complete ==="
