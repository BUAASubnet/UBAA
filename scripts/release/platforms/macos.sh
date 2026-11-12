#!/usr/bin/env bash
# 按架构构建 Developer ID 应用，公证后生成 DMG。
set -euo pipefail
repo_root=$(pwd)
arch=${RELEASE_ARCH:?需要发布架构}
output="$repo_root/.ubaa_local/release/macos"
mkdir -p "$output" "$repo_root/.ubaa_local/release/public"
config=apps/ubaa_flutter/macos/Runner/Configs/LocalSigning.xcconfig
cat > "$config" <<CONFIG
UBAA_CODE_SIGN_STYLE = Manual
CODE_SIGNING_ALLOWED = NO
ARCHS = $arch
ONLY_ACTIVE_ARCH = YES
CONFIG
export FLUTTER_XCODE_ARCHS="$arch"
just flutter-build platform=macos mode=release
app=apps/ubaa_flutter/build/macos/Build/Products/Release/UBAA.app
# 从内部动态库到 Framework 再到主应用签名，保留相同的 Developer ID。
while IFS= read -r -d '' library; do
  codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$library"
done < <(find "$app/Contents" -name '*.dylib' -type f -print0)
while IFS= read -r -d '' framework; do
  codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$framework"
done < <(find "$app/Contents/Frameworks" -depth -name '*.framework' -type d -print0)
codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" \
  --entitlements apps/ubaa_flutter/macos/Runner/Release.entitlements "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/UBAA" -verify_arch "$arch"
ditto -c -k --keepParent "$app" "$output/notarize.zip"
xcrun notarytool submit "$output/notarize.zip" \
  --key "$API_PRIVATE_KEYS_DIR/AuthKey_${APPSTORE_KEY_ID}.p8" \
  --key-id "$APPSTORE_KEY_ID" --issuer "$APPSTORE_ISSUER_ID" --output-format json > "$output/submission.json"
submission=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$output/submission.json")
printf 'Apple 公证提交：%s\n' "$submission"
xcrun notarytool wait "$submission" \
  --key "$API_PRIVATE_KEYS_DIR/AuthKey_${APPSTORE_KEY_ID}.p8" \
  --key-id "$APPSTORE_KEY_ID" --issuer "$APPSTORE_ISSUER_ID" --timeout 2h --output-format json > "$output/notary.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print("公证状态："+r["status"]); sys.exit(0 if r["status"]=="Accepted" else 1)' "$output/notary.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
mkdir -p "$output/image"
ditto "$app" "$output/image/UBAA.app"
ln -s /Applications "$output/image/Applications"
hdiutil create -volname UBAA -srcfolder "$output/image" -ov -format UDZO \
  "$repo_root/.ubaa_local/release/public/UBAA-${RELEASE_VERSION}-macos-${arch}.dmg"
