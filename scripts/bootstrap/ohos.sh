#!/usr/bin/env bash
# GitHub 托管 Linux runner 使用锁定的 DevEco CLI/API26 与 Flutter OHOS。
set -euo pipefail
# shellcheck source=../lib/versions.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/versions.sh"
if [[ "${RUNNER_ENVIRONMENT:-}" != github-hosted || "${RUNNER_OS:-}" != Linux ]]; then
  printf '%s\n' 'OHOS CI 安装入口仅用于 GitHub 托管 Linux runner' >&2
  exit 2
fi
export JAVA_HOME="${JAVA_HOME_21_X64:?GitHub runner 需要预装 JDK 21}"
export PATH="$JAVA_HOME/bin:$PATH"
printf 'JAVA_HOME=%s\n' "$JAVA_HOME" >> "${GITHUB_ENV:?}"
printf '%s\n' "$JAVA_HOME/bin" >> "${GITHUB_PATH:?}"
sdk_root="${RUNNER_TEMP:?}/ubaa-ohos-sdk"
flutter_root="$RUNNER_TEMP/flutter-ohos"
archive="$RUNNER_TEMP/ohos-sdk-linux-amd64.tar.gz"
mkdir -p "$sdk_root"
for part in aa ab; do
  curl --retry 4 --retry-delay 3 -fSL \
    "$DEVECO_CLI_MIRROR/$DEVECO_CLI_VERSION/ohos-sdk-linux-amd64.tar.gz.$part" -o "$archive.$part"
done
cat "$archive.aa" "$archive.ab" > "$archive"
printf '%s  %s\n' "$DEVECO_CLI_LINUX_SHA256" "$archive" | sha256sum -c -
tar -xzf "$archive" -C "$sdk_root"
rm "$archive" "$archive.aa" "$archive.ab"
export UBAA_DEVECO_HOME="$sdk_root/command-line-tools"
grep -F "# Version: $DEVECO_CLI_VERSION" "$UBAA_DEVECO_HOME/version.txt"
git init "$flutter_root"
git -C "$flutter_root" remote add origin "$OHOS_FLUTTER_REMOTE"
git -C "$flutter_root" fetch --depth=1 origin "refs/tags/$OHOS_FLUTTER_VERSION:refs/tags/$OHOS_FLUTTER_VERSION"
git -C "$flutter_root" checkout --detach "$OHOS_FLUTTER_COMMIT"
export UBAA_OHOS_FLUTTER_HOME="$flutter_root"
export UBAA_HMOS_SDK_HOME="$UBAA_DEVECO_HOME/sdk"
{
  printf 'UBAA_DEVECO_HOME=%s\n' "$UBAA_DEVECO_HOME"
  printf 'UBAA_OHOS_FLUTTER_HOME=%s\n' "$UBAA_OHOS_FLUTTER_HOME"
  printf 'UBAA_HMOS_SDK_HOME=%s\n' "$UBAA_HMOS_SDK_HOME"
} >> "${GITHUB_ENV:?}"
rustup target add "$OHOS_RUST_TARGET"
just flutter-ohos config --ohos-sdk "$UBAA_HMOS_SDK_HOME"
bash apps/ubaa_ohos/scripts/check-toolchain.sh
