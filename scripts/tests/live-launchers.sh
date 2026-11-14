#!/usr/bin/env bash
# verify-live 启动器合同测试，不访问真实上游。
set -Eeuo pipefail
trap 'printf "启动器测试失败：第 %s 行\n" "$LINENO" >&2' ERR

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
mkdir -p "$repo_root/.ubaa_local/live_launcher_tests"
test_root=$(mktemp -d "$repo_root/.ubaa_local/live_launcher_tests/run.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/tmp"
export TMPDIR="$test_root/tmp"

mkdir -p "$test_root/scripts/live" "$test_root/scripts/lib"
cp "$repo_root/scripts/live/verify.sh" "$test_root/scripts/live/verify.sh"
cp "$repo_root/scripts/lib/repo.sh" "$test_root/scripts/lib/repo.sh"
cp "$repo_root/scripts/lib/live-features.sh" "$test_root/scripts/lib/live-features.sh"
for name in environment.py toolchain.py repo.py; do
  cp "$repo_root/scripts/lib/$name" "$test_root/scripts/lib/$name"
done
chmod +x "$test_root/scripts/live/verify.sh"

cat >"$test_root/scripts/fake-core-live.sh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf 'route=%s feature=%s\n' "${1#route=}" "${2#feature=}"
read -r fake_user
read -r fake_password
printf 'stdin_lines=2\n'
for key in UBAA_USERNAME UBAA_PASSWORD UBAA_TEST_USERNAME UBAA_TEST_PASSWORD CLOUDFLARE_API_TOKEN; do
  [[ -z ${!key+x} ]] || exit 32
done
printf 'argv=%s\n' "$*" >&2
if [[ $fake_user != test-user || $fake_password != test-password ]]; then
  exit 31
fi
FAKE
chmod +x "$test_root/scripts/fake-core-live.sh"
export CLOUDFLARE_API_TOKEN
printf -v CLOUDFLARE_API_TOKEN '%s' synthetic-token
unset UBAA_USERNAME UBAA_PASSWORD UBAA_TEST_USERNAME UBAA_TEST_PASSWORD

printf 'UBAA_%s\n' 'USERNAME=test-user' 'PASSWORD=test-password' >"$test_root/.env"

output=$(UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/live/verify.sh" mode=webvpn feature=cgyy date=2026-08-31 campus-id=2 2>"$test_root/stderr")
[[ $output == *'route=webvpn feature=cgyy'* ]]
[[ $output == *'stdin_lines=2'* ]]
if grep -F 'test-password' "$test_root/stderr" >/dev/null; then
  printf '%s\n' '启动器诊断泄露了测试密码' >&2
  exit 1
fi
grep -F 'argv=route=webvpn feature=cgyy date=2026-08-31 campus-id=2' "$test_root/stderr" >/dev/null

# 同时通过真实启动器覆盖文档主名称，兼容名称与主名称选择规则由解析器测试保护。
printf 'UBAA_TEST_%s\n' 'USERNAME=test-user' 'PASSWORD=test-password' >"$test_root/.env"
output=$(UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/live/verify.sh" mode=direct feature=auth 2>"$test_root/primary.err")
[[ $output == *'route=direct feature=auth'* && $output == *'stdin_lines=2'* ]]
if grep -F 'test-password' "$test_root/primary.err" >/dev/null; then
  printf '%s\n' '主名称启动器诊断泄露了测试密码' >&2
  exit 1
fi

if UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/live/verify.sh" mode=auto >/dev/null 2>"$test_root/auto.err"; then
  printf '%s\n' 'auto 未被拒绝' >&2
  exit 1
fi
grep -F '不执行 auto' "$test_root/auto.err" >/dev/null

mv "$test_root/.env" "$test_root/saved.env"
if UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
  "$test_root/scripts/live/verify.sh" mode=direct >/dev/null 2>"$test_root/missing.err"; then
  printf '%s\n' '缺少凭据时未失败' >&2
  exit 1
fi
grep -F '请在 .env 或进程环境设置' "$test_root/missing.err" >/dev/null
mv "$test_root/saved.env" "$test_root/.env"

if UBAA_CORE_LIVE_SCRIPT="$test_root/scripts/fake-core-live.sh" \
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
  : >"$TMPDIR/core-live-ready"
  sleep 10
fi
exit "${FAKE_CORE_LIVE_EXIT:-0}"
FAKE_RUNTIME
chmod +x "$test_root/scripts/fake-core-live-runtime.sh"

run_core_live() {
  local expected=$1
  shift
  local output status
  if output=$(
    trap - ERR
    UBAA_CORE_LIVE_BINARY="$test_root/scripts/fake-core-live-runtime.sh" UBAA_CORE_LIVE_BUILD=no \
      "$repo_root/scripts/live/core-live.sh" "$@" 2>"$test_root/core.err"
  ); then
    status=0
  else
    status=$?
  fi
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
UBAA_CORE_LIVE_BINARY="$test_root/scripts/fake-core-live-runtime.sh" UBAA_CORE_LIVE_BUILD=no \
  "$repo_root/scripts/live/core-live.sh" route=direct feature=auth config-dir="$explicit_dir" >/dev/null 2>"$test_root/explicit.err"
[[ -f "$explicit_dir/session.json" && -f "$explicit_dir/.session.lock" ]]
grep -F -- '--route direct --feature auth --config-dir' "$explicit_dir/argv.txt" >/dev/null

# 构建失败也必须清理自动目录。
mkdir -p "$test_root/fake-bin"
cat >"$test_root/fake-bin/cargo" <<'FAKE_CARGO'
#!/usr/bin/env bash
exit 37
FAKE_CARGO
chmod +x "$test_root/fake-bin/cargo"
if PATH="$test_root/fake-bin:$PATH" UBAA_CORE_LIVE_BINARY="$test_root/missing-core-live" \
  UBAA_CORE_LIVE_BUILD=yes "$repo_root/scripts/live/core-live.sh" route=direct \
  >/dev/null 2>"$test_root/build.err"; then
  build_status=0
else
  build_status=$?
fi
[[ $build_status -eq 37 ]]
automatic_dir=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'ubaa-core-live.*' -print -quit)
[[ -z "$automatic_dir" ]]

# 中断父进程时，信号陷阱转为退出并触发同一清理路径。
FAKE_CORE_LIVE_SLEEP=yes UBAA_CORE_LIVE_BINARY="$test_root/scripts/fake-core-live-runtime.sh" \
  UBAA_CORE_LIVE_BUILD=no "$repo_root/scripts/live/core-live.sh" route=direct \
  >/dev/null 2>"$test_root/signal.err" &
core_pid=$!
# 假程序启动时，父进程已安装信号与清理陷阱。
for ((attempt = 0; attempt < 500; attempt++)); do
  [[ ! -f "$TMPDIR/core-live-ready" ]] || break
  kill -0 "$core_pid"
  sleep 0.01
done
if [[ ! -f "$TMPDIR/core-live-ready" ]]; then
  printf '%s\n' 'Core-live 假程序未在五秒内就绪' >&2
  kill -TERM "$core_pid"
  wait "$core_pid" || true
  exit 1
fi
kill -TERM "$core_pid"
if wait "$core_pid"; then
  signal_status=0
else
  signal_status=$?
fi
[[ $signal_status -eq 143 ]]
automatic_dir=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'ubaa-core-live.*' -print -quit)
[[ -z "$automatic_dir" ]]

printf '%s\n' 'verify-live shell tests passed'
