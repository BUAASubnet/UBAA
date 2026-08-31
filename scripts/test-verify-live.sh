#!/usr/bin/env bash
# verify-live 启动器合同测试，不访问真实上游。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-verify-live-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/scripts"
cp "$repo_root/scripts/verify-live.sh" "$test_root/scripts/verify-live.sh"
chmod +x "$test_root/scripts/verify-live.sh"

cat >"$test_root/scripts/fake-core-live.sh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf 'route=%s feature=%s\n' "${1#route=}" "${2#feature=}"
read -r fake_user
read -r fake_password
printf 'stdin_lines=2\n'
printf 'argv=%s\n' "$*" >&2
if [[ $fake_user != test-user || $fake_password != test-password ]]; then
  exit 31
fi
FAKE
chmod +x "$test_root/scripts/fake-core-live.sh"

cat >"$test_root/.env.local" <<'ENV'
UBAA_USERNAME=test-user
UBAA_PASSWORD=test-password
ENV

output=$(UBAA_ENV_FILE="$test_root/.env.local" \
  UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/verify-live.sh" mode=webvpn feature=cgyy date=2026-08-31 campus-id=2 2>"$test_root/stderr")
[[ $output == *'route=webvpn feature=cgyy'* ]]
[[ $output == *'stdin_lines=2'* ]]
! grep -F 'test-password' "$test_root/stderr"
grep -F 'argv=route=webvpn feature=cgyy date=2026-08-31 campus-id=2' "$test_root/stderr" >/dev/null

if UBAA_ENV_FILE="$test_root/.env.local" \
  UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/verify-live.sh" mode=auto >/dev/null 2>"$test_root/auto.err"; then
  printf '%s\n' 'auto 未被拒绝' >&2
  exit 1
fi
grep -F '不执行 auto' "$test_root/auto.err" >/dev/null

if UBAA_ENV_FILE="$test_root/missing.env" \
  UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/verify-live.sh" mode=direct >/dev/null 2>"$test_root/missing.err"; then
  printf '%s\n' '缺少凭据文件时未失败' >&2
  exit 1
fi
grep -F '凭据文件不存在' "$test_root/missing.err" >/dev/null

if UBAA_ENV_FILE="$test_root/.env.local" \
  UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/verify-live.sh" mode=direct feature=unknown >/dev/null 2>"$test_root/feature.err"; then
  printf '%s\n' '未知功能未被拒绝' >&2
  exit 1
fi
grep -F '不支持 feature=unknown' "$test_root/feature.err" >/dev/null

printf '%s\n' 'verify-live shell tests passed'
