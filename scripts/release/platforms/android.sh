#!/usr/bin/env bash
# 每个作业只编译一种 ABI，保持各平台共用的构建号。
set -euo pipefail
: "${ANDROID_ABI:?需要 Android ABI}"
repo_root=$(pwd)
# shellcheck source=../../tools/versions.env
source scripts/tools/versions.env
cd apps/ubaa_flutter
just flutter pub get --enforce-lockfile
just flutter build apk --release --target-platform="$ANDROID_TARGET" \
  --dart-define="UBAA_APP_SERVICE_URL=$UBAA_APP_SERVICE_URL" \
  --dart-define=UBAA_DISTRIBUTION_CHANNEL=github
apk=build/app/outputs/flutter-apk/app-release.apk
bash "$repo_root/scripts/release/verify-flutter-artifact.sh" android-apk "$apk" "$ANDROID_ABI"
tools="$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS"
"$tools/apksigner" verify "$apk"
"$tools/zipalign" -c -P 16 4 "$apk"
badging="${RUNNER_TEMP:?}/ubaa_release_signing/android_badging.txt"
"$tools/aapt2" dump badging "$apk" > "$badging"
python3 - "$apk" "$badging" <<'PY'
import os,sys,zipfile
from pathlib import Path
with zipfile.ZipFile(sys.argv[1]) as archive:
    abis={path.split('/')[1] for path in archive.namelist() if path.startswith('lib/') and path.endswith('.so')}
    assert abis=={os.environ['ANDROID_ABI']}, abis
    for library in ('libapp.so', 'libflutter.so', 'libubaa_flutter_bridge.so'):
        assert f"lib/{os.environ['ANDROID_ABI']}/{library}" in archive.namelist(), library
badging=Path(sys.argv[2]).read_text()
assert "name='cn.edu.ubaa'" in badging
assert "versionName='"+os.environ['RELEASE_VERSION']+"'" in badging
assert "versionCode='"+os.environ['RELEASE_BUILD']+"'" in badging
assert 'application-debuggable' not in badging
print('Android 应用标识、版本、单 ABI、签名和对齐检查通过')
PY
mkdir -p "$repo_root/dist/release/public"
cp "$apk" "$repo_root/dist/release/public/UBAA-${RELEASE_VERSION}-android-${ANDROID_ABI}.apk"
