#!/usr/bin/env bash
# 独立临时桌面会话中的合成安全材料测试；不接触用户钥匙串。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
umask 077
if [[ ${1:-} == --keyring-session ]]; then
  : "${UBAA_SYNTHETIC_SECRET_SERVICE_ROOT:?必须由外层创建独立材料会话}"
  if [[ ${XDG_DATA_HOME:-} != "$UBAA_SYNTHETIC_SECRET_SERVICE_ROOT/data" ||
        ${XDG_CONFIG_HOME:-} != "$UBAA_SYNTHETIC_SECRET_SERVICE_ROOT/config" ||
        ${XDG_RUNTIME_DIR:-} != "$UBAA_SYNTHETIC_SECRET_SERVICE_ROOT/runtime" ||
        -z ${DBUS_SESSION_BUS_ADDRESS:-} || -n ${GNOME_KEYRING_CONTROL:-} ]]; then
    printf '%s\n' '隔离材料会话前提不完整，拒绝启动 Secret Service' >&2
    exit 2
  fi
  printf '%s' 'ubaa-ci-synthetic' | gnome-keyring-daemon --unlock --components=secrets
  cd "$repo_root/apps/ubaa_flutter"
  exec just --justfile "$repo_root/justfile" flutter test --no-pub -d linux \
    integration_test/platform/credentials/linux_test.dart \
    --dart-define=UBAA_SECURE_STORAGE_AVAILABLE=true \
    --dart-define=UBAA_SYNTHETIC_SECRET_SERVICE=true
fi
mkdir -p "$repo_root/.ubaa_local/linux_secure_storage"
storage_test_dir=$(mktemp -d "$repo_root/.ubaa_local/linux_secure_storage/session_XXXXXX")
export UBAA_SYNTHETIC_SECRET_SERVICE_ROOT="$storage_test_dir"
trap 'rm -rf -- "$storage_test_dir"' EXIT
export XDG_DATA_HOME="$storage_test_dir/data"
export XDG_CONFIG_HOME="$storage_test_dir/config"
export XDG_RUNTIME_DIR="$storage_test_dir/runtime"
unset GNOME_KEYRING_CONTROL GNOME_KEYRING_PID SSH_AUTH_SOCK
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR"
cd "$repo_root/apps/ubaa_flutter"

# 真实插件连接不到 Secret Service 时必须安全失败。
DBUS_SESSION_BUS_ADDRESS="unix:path=$storage_test_dir/absent-bus" xvfb-run -a \
  just --justfile "$repo_root/justfile" flutter test --no-pub -d linux \
  integration_test/platform/credentials/linux_test.dart \
  --dart-define=UBAA_SECURE_STORAGE_AVAILABLE=false \
  --dart-define=UBAA_SYNTHETIC_SECRET_SERVICE=true

# 密码仅用于本次空的临时合成钥匙串；会话退出后不保留任何材料。
xvfb-run -a dbus-run-session -- bash "$script_dir/linux-secure-storage.sh" --keyring-session
