#!/usr/bin/env bash
# 独立临时桌面会话中的合成安全材料测试；不接触用户钥匙串。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
flutter_root=${UBAA_FLUTTER_HOME:?需要固定官方 Flutter SDK}
if [[ ${1:-} == --keyring-session ]]; then
  printf '%s' 'ubaa-ci-synthetic' | gnome-keyring-daemon --unlock --components=secrets
  cd "$repo_root/apps/ubaa_flutter"
  exec "$flutter_root/bin/flutter" test --no-pub -d linux \
    integration_test/platform/credentials/linux_test.dart \
    --dart-define=UBAA_SECURE_STORAGE_AVAILABLE=true
fi
storage_test_dir=$(mktemp -d)
trap 'rm -rf -- "$storage_test_dir"' EXIT
export XDG_DATA_HOME="$storage_test_dir/data"
export XDG_CONFIG_HOME="$storage_test_dir/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
cd "$repo_root/apps/ubaa_flutter"

# 真实插件连接不到 Secret Service 时必须安全失败。
DBUS_SESSION_BUS_ADDRESS="unix:path=$storage_test_dir/absent-bus" xvfb-run -a \
  "$flutter_root/bin/flutter" test --no-pub -d linux \
  integration_test/platform/credentials/linux_test.dart \
  --dart-define=UBAA_SECURE_STORAGE_AVAILABLE=false

# 密码仅用于本次空的临时合成钥匙串；会话退出后不保留任何材料。
xvfb-run -a dbus-run-session -- bash "$script_dir/linux-secure-storage.sh" --keyring-session
