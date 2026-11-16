#!/usr/bin/env bash
# 在 GitHub 托管 Linux runner 上构建带发布签名的 APP 和 HAP。
set -euo pipefail
repo_root=$(pwd)
# shellcheck source=../../lib/toolchain.sh
source scripts/lib/toolchain.sh build
# shellcheck source=../../lib/deveco.sh
source scripts/lib/deveco.sh
ubaa_deveco_layout
export OHOS_SDK_HOME="$ohos_native_home" DEVECO_SDK_HOME="$hmos_sdk_home" DEVECO_NODE_HOME="$node_home"
export PATH="$deveco_hvigor_home/bin:$deveco_ohpm_home/bin:$node_home/bin:$PATH"
encrypted_passwords=$(node scripts/release/platforms/ohos_signing.mjs)
read -r OHOS_STORE_PASSWORD OHOS_KEY_PASSWORD <<< "$encrypted_passwords"
export OHOS_STORE_PASSWORD OHOS_KEY_PASSWORD
unset encrypted_passwords
node scripts/release/platforms/ohos_profile.mjs just ohos-check mode=release
cd apps/ubaa_ohos
node ../../scripts/release/platforms/ohos_profile.mjs just flutter-ohos build app --release --target-platform ohos-arm64 \
  --dart-define="UBAA_APP_SERVICE_URL=$UBAA_APP_SERVICE_URL" \
  --dart-define=UBAA_DISTRIBUTION_CHANNEL=app_gallery
cd "$repo_root"
python3 scripts/release/platforms/ohos_artifacts.py
