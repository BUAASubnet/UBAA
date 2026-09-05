#!/usr/bin/env bash
# verify-live 启动器合同测试，不访问真实上游。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-verify-live-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/scripts/live" "$test_root/scripts/lib"
cp "$repo_root/scripts/live/verify.sh" "$test_root/scripts/live/verify.sh"
cp "$repo_root/scripts/lib/repo.sh" "$test_root/scripts/lib/repo.sh"
cp "$repo_root/scripts/lib/live-features.sh" "$test_root/scripts/lib/live-features.sh"
chmod +x "$test_root/scripts/live/verify.sh"

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
  "$test_root/scripts/live/verify.sh" mode=webvpn feature=cgyy date=2026-08-31 campus-id=2 2>"$test_root/stderr")
[[ $output == *'route=webvpn feature=cgyy'* ]]
[[ $output == *'stdin_lines=2'* ]]
if grep -F 'test-password' "$test_root/stderr" >/dev/null; then
  printf '%s\n' '启动器诊断泄露了测试密码' >&2
  exit 1
fi
grep -F 'argv=route=webvpn feature=cgyy date=2026-08-31 campus-id=2' "$test_root/stderr" >/dev/null

if UBAA_ENV_FILE="$test_root/.env.local" \
  UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/live/verify.sh" mode=auto >/dev/null 2>"$test_root/auto.err"; then
  printf '%s\n' 'auto 未被拒绝' >&2
  exit 1
fi
grep -F '不执行 auto' "$test_root/auto.err" >/dev/null

if UBAA_ENV_FILE="$test_root/missing.env" \
  UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/live/verify.sh" mode=direct >/dev/null 2>"$test_root/missing.err"; then
  printf '%s\n' '缺少凭据文件时未失败' >&2
  exit 1
fi
grep -F '凭据文件不存在' "$test_root/missing.err" >/dev/null

if UBAA_ENV_FILE="$test_root/.env.local" \
  UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/live/verify.sh" mode=direct feature=unknown >/dev/null 2>"$test_root/feature.err"; then
  printf '%s\n' '未知功能未被拒绝' >&2
  exit 1
fi
grep -F '不支持 feature=unknown' "$test_root/feature.err" >/dev/null

# core-live 启动器合同：自动目录必须清理，显式目录不能被删除。
cat >"$test_root/scripts/fake-core-live-runtime.sh" <<'FAKE_RUNTIME'
#!/usr/bin/env bash
set -euo pipefail
config_dir=
expect_dir=no
for argument in "$@"; do
  if [[ $argument == --config-dir ]]; then
    expect_dir=yes
  elif [[ $expect_dir == yes ]]; then
    config_dir=$argument
    expect_dir=no
  fi
done
[[ -n "$config_dir" ]]
printf '%s\n' "$*" >"$config_dir/argv.txt"
printf '%s\n' 'session-material' >"$config_dir/session.json"
printf '%s\n' 'lock-material' >"$config_dir/.session.lock"
if [[ ${FAKE_CORE_LIVE_SLEEP:-no} == yes ]]; then
  sleep 10
fi
exit "${FAKE_CORE_LIVE_EXIT:-0}"
FAKE_RUNTIME
chmod +x "$test_root/scripts/fake-core-live-runtime.sh"

run_core_live() {
  local expected=$1
  shift
  local output status
  set +e
  output=$(UBAA_CORE_LIVE_BINARY="$test_root/scripts/fake-core-live-runtime.sh" UBAA_CORE_LIVE_BUILD=no \
    "$repo_root/scripts/live/core-live.sh" "$@" 2>"$test_root/core.err")
  status=$?
  set -e
  [[ $status -eq $expected ]]
  [[ -z "$output" ]]
}

run_core_live 0 route=direct feature=all date=2026-08-31 campus-id=2
automatic_dir=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'ubaa-core-live.*' -print -quit)
[[ -z "$automatic_dir" ]]

FAKE_CORE_LIVE_EXIT=31 run_core_live 31 route=webvpn feature=cgyy
automatic_dir=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'ubaa-core-live.*' -print -quit)
[[ -z "$automatic_dir" ]]

explicit_dir="$test_root/explicit"
mkdir -p "$explicit_dir"
set +e
UBAA_CORE_LIVE_BINARY="$test_root/scripts/fake-core-live-runtime.sh" UBAA_CORE_LIVE_BUILD=no \
  "$repo_root/scripts/live/core-live.sh" route=direct feature=auth config-dir="$explicit_dir" >/dev/null 2>"$test_root/explicit.err"
explicit_status=$?
set -e
[[ $explicit_status -eq 0 ]]
[[ -f "$explicit_dir/session.json" && -f "$explicit_dir/.session.lock" ]]
grep -F -- '--route direct --feature auth --config-dir' "$explicit_dir/argv.txt" >/dev/null

# 构建失败也必须清理自动目录。
mkdir -p "$test_root/fake-bin"
cat >"$test_root/fake-bin/cargo" <<'FAKE_CARGO'
#!/usr/bin/env bash
exit 37
FAKE_CARGO
chmod +x "$test_root/fake-bin/cargo"
set +e
PATH="$test_root/fake-bin:$PATH" UBAA_CORE_LIVE_BINARY="$test_root/missing-core-live" \
  UBAA_CORE_LIVE_BUILD=yes "$repo_root/scripts/live/core-live.sh" route=direct \
  >/dev/null 2>"$test_root/build.err"
build_status=$?
set -e
[[ $build_status -eq 37 ]]
automatic_dir=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'ubaa-core-live.*' -print -quit)
[[ -z "$automatic_dir" ]]

# 中断父进程时，信号陷阱转为退出并触发同一清理路径。
set +e
FAKE_CORE_LIVE_SLEEP=yes UBAA_CORE_LIVE_BINARY="$test_root/scripts/fake-core-live-runtime.sh" \
  UBAA_CORE_LIVE_BUILD=no "$repo_root/scripts/live/core-live.sh" route=direct \
  >/dev/null 2>"$test_root/signal.err" &
core_pid=$!
sleep 0.05
kill -TERM "$core_pid"
wait "$core_pid"
signal_status=$?
set -e
[[ $signal_status -eq 143 ]]
automatic_dir=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'ubaa-core-live.*' -print -quit)
[[ -z "$automatic_dir" ]]

printf '%s\n' 'verify-live shell tests passed'
