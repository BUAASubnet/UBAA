#!/usr/bin/env bash
# 使用 Flutter 准备原生工程，再由 Xcode 归档和导出 App Store IPA。
set -euo pipefail
repo_root=$(pwd)
python3 scripts/release/platforms/ios_privacy.py apps/ubaa_flutter/ios/Runner/Info.plist
signing="${RUNNER_TEMP:?}/ubaa_release_signing"
output="$repo_root/target/release_ios"
mkdir -p "$output" "$repo_root/dist/release/store"
cd apps/ubaa_flutter
just flutter pub get --enforce-lockfile
just flutter build ios --release --config-only --no-codesign \
  --dart-define="UBAA_APP_SERVICE_URL=$UBAA_APP_SERVICE_URL" \
  --dart-define=UBAA_DISTRIBUTION_CHANNEL=app_store
(cd ios && pod install)
ruby -rxcodeproj -e '
project = Xcodeproj::Project.open("ios/Runner.xcodeproj")
{"Runner" => "IOS_PROFILE_UUID", "ScheduleWidget" => "IOS_WIDGET_PROFILE_UUID"}.each do |name, variable|
  target = project.targets.find { |candidate| candidate.name == name } or abort "找不到 iOS 签名目标 #{name}"
  target.build_configurations.each do |config|
    config.build_settings["DEVELOPMENT_TEAM"] = ENV.fetch("APPLE_TEAM_ID")
    config.build_settings["CODE_SIGN_STYLE"] = "Manual"
    config.build_settings["CODE_SIGN_IDENTITY[sdk=iphoneos*]"] = ENV.fetch("APPLE_SIGNING_IDENTITY")
    config.build_settings["PROVISIONING_PROFILE_SPECIFIER"] = ENV.fetch(variable)
  end
end
project.save
'
xcodebuild archive -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$output/UBAA.xcarchive"
xcodebuild -exportArchive -archivePath "$output/UBAA.xcarchive" \
  -exportPath "$output/export" -exportOptionsPlist "$signing/ExportOptions.plist"
cp "$output/export/"*.ipa "$repo_root/dist/release/store/UBAA-${RELEASE_VERSION}-ios-arm64.ipa"
python3 "$repo_root/scripts/release/platforms/ios_privacy.py" "$repo_root/dist/release/store/UBAA-${RELEASE_VERSION}-ios-arm64.ipa"
