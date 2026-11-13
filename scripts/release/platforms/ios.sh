#!/usr/bin/env bash
# 使用 Flutter 准备原生工程，再由 Xcode 归档和导出 App Store IPA。
set -euo pipefail
repo_root=$(pwd)
python3 scripts/release/platforms/ios_privacy.py apps/ubaa_flutter/ios/Runner/Info.plist
signing="$repo_root/.ubaa_local/release/signing"
output="$repo_root/.ubaa_local/release/ios"
mkdir -p "$output" "$repo_root/.ubaa_local/release/store"
cd apps/ubaa_flutter
just flutter pub get --enforce-lockfile
just flutter build ios --release --config-only --no-codesign \
  --dart-define="UBAA_APP_SERVICE_URL=$UBAA_APP_SERVICE_URL" \
  --dart-define=UBAA_DISTRIBUTION_CHANNEL=app_store
(cd ios && pod install)
ruby -rxcodeproj -e '
project = Xcodeproj::Project.open("ios/Runner.xcodeproj")
project.targets.find { |target| target.name == "Runner" }.build_configurations.each do |config|
  config.build_settings["DEVELOPMENT_TEAM"] = ENV.fetch("APPLE_TEAM_ID")
  config.build_settings["CODE_SIGN_STYLE"] = "Manual"
  config.build_settings["CODE_SIGN_IDENTITY[sdk=iphoneos*]"] = ENV.fetch("APPLE_SIGNING_IDENTITY")
  config.build_settings["PROVISIONING_PROFILE_SPECIFIER"] = ENV.fetch("IOS_PROFILE_UUID")
end
project.save
'
xcodebuild archive -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$output/UBAA.xcarchive"
xcodebuild -exportArchive -archivePath "$output/UBAA.xcarchive" \
  -exportPath "$output/export" -exportOptionsPlist "$signing/ExportOptions.plist"
cp "$output/export/"*.ipa "$repo_root/.ubaa_local/release/store/UBAA-${RELEASE_VERSION}-ios-arm64.ipa"
python3 "$repo_root/scripts/release/platforms/ios_privacy.py" "$repo_root/.ubaa_local/release/store/UBAA-${RELEASE_VERSION}-ios-arm64.ipa"
