#!/usr/bin/env bash
# 严格 Shell 门禁与 Flutter 产物权限合同；全部产物和命令夹具位于临时目录。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
artifact_checker=$repo_root/scripts/release/verify-flutter-artifact.sh
entitlements_helper=$repo_root/scripts/release/macos-entitlements.sh
artifact_bash=/usr/bin/bash
if [[ ! -x "$artifact_bash" ]]; then
  artifact_bash=/bin/bash
fi
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-maintenance-gates.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM

pass_count=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  pass_count=$((pass_count + 1))
  printf 'ok %d - %s\n' "$pass_count" "$1"
}

run_just_shell_gate() {
  local recipe=$1
  local output_file=$2
  local status
  set +e
  (
    cd "$repo_root"
    UBAA_SHELLCHECK_BIN="$test_root/missing-shellcheck" just "$recipe"
  ) >"$output_file" 2>&1
  status=$?
  set -e
  printf '%s\n' "$status"
}

lenient_status=$(run_just_shell_gate shell-check "$test_root/lenient.out")
[[ $lenient_status -eq 0 ]] || fail '宽松 Shell 门禁在缺少 ShellCheck 时应通过'
grep -F 'SKIP: ShellCheck 未执行' "$test_root/lenient.out" >/dev/null || \
  fail '宽松 Shell 门禁未明确报告 SKIP'
pass '宽松 Shell 门禁在缺少 ShellCheck 时保留 SKIP'

strict_status=$(run_just_shell_gate shell-check-strict "$test_root/strict.out")
[[ $strict_status -ne 0 ]] || fail '严格 Shell 门禁在缺少 ShellCheck 时错误通过'
grep -F 'error: 严格门禁要求 ShellCheck' "$test_root/strict.out" >/dev/null || \
  fail '严格 Shell 门禁未报告缺少 ShellCheck 的真实失败原因'
pass '严格 Shell 门禁在缺少 ShellCheck 时失败'

mkdir -p "$test_root/fake-bin"
cat >"$test_root/fake-bin/shellcheck" <<'FAKE_SHELLCHECK'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'ShellCheck - shell script analysis tool' 'version: 0.11.0'
  exit 0
fi
printf '%s\n' "$*" >>"$UBAA_TEST_SHELLCHECK_LOG"
exit "${UBAA_TEST_SHELLCHECK_EXIT:-0}"
FAKE_SHELLCHECK
chmod +x "$test_root/fake-bin/shellcheck"

set +e
true_bin=$(type -P true)
(
  cd "$repo_root"
  UBAA_SHELLCHECK_BIN="$true_bin" just shell-check-strict
) >"$test_root/not-shellcheck.out" 2>&1
not_shellcheck_status=$?
set -e
[[ $not_shellcheck_status -ne 0 ]] || fail '严格 Shell 门禁错误接受 true 可执行文件'
grep -F '要求 ShellCheck 版本 0.11.0' "$test_root/not-shellcheck.out" >/dev/null || \
  fail '严格 Shell 门禁未说明固定版本要求'
pass '严格 Shell 门禁拒绝非 ShellCheck 可执行文件'

cat >"$test_root/fake-bin/shellcheck-old" <<'FAKE_OLD_SHELLCHECK'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'ShellCheck - shell script analysis tool' 'version: 0.10.0'
fi
FAKE_OLD_SHELLCHECK
chmod +x "$test_root/fake-bin/shellcheck-old"
set +e
(
  cd "$repo_root"
  UBAA_SHELLCHECK_BIN="$test_root/fake-bin/shellcheck-old" just shell-check-strict
) >"$test_root/old-shellcheck.out" 2>&1
old_shellcheck_status=$?
set -e
[[ $old_shellcheck_status -ne 0 ]] || fail '严格 Shell 门禁错误接受 ShellCheck 0.10.0'
grep -F '检测到 0.10.0' "$test_root/old-shellcheck.out" >/dev/null || \
  fail '严格 Shell 门禁未报告实际 ShellCheck 版本'
pass '严格 Shell 门禁拒绝非固定版本'

set +e
(
  cd "$repo_root"
  UBAA_SHELLCHECK_BIN="$test_root/fake-bin/shellcheck" \
    UBAA_TEST_SHELLCHECK_LOG="$test_root/shellcheck.log" \
    UBAA_TEST_SHELLCHECK_EXIT=73 \
    just shell-check-strict
) >"$test_root/shellcheck-failure.out" 2>&1
shellcheck_failure_status=$?
set -e
[[ $shellcheck_failure_status -eq 73 ]] || \
  fail "严格 Shell 门禁未传播 ShellCheck 失败退出码：$shellcheck_failure_status"
[[ -s "$test_root/shellcheck.log" ]] || fail '严格 Shell 门禁未实际执行注入的 ShellCheck'
pass '严格 Shell 门禁传播 ShellCheck 的真实失败'

mkdir -p "$test_root/artifacts/macos.app/Contents/MacOS"
mkdir -p "$test_root/artifacts/macos.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets"
printf '%s\n' 'fixture executable' >"$test_root/artifacts/macos.app/Contents/MacOS/ubaa_flutter"
printf '%s\n' 'fixture assets' \
  >"$test_root/artifacts/macos.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/AssetManifest.bin"

mkdir -p "$test_root/artifacts/linux/data/flutter_assets"
printf '%s\n' 'fixture executable' >"$test_root/artifacts/linux/ubaa_flutter"
printf '%s\n' 'fixture assets' >"$test_root/artifacts/linux/data/flutter_assets/AssetManifest.bin"

mkdir -p "$test_root/artifacts/windows/data/flutter_assets"
printf '%s\n' 'fixture executable' >"$test_root/artifacts/windows/ubaa_flutter.exe"
printf '%s\n' 'fixture assets' >"$test_root/artifacts/windows/data/flutter_assets/AssetManifest.bin"

apk_root=$test_root/apk-root
apk_artifact=$test_root/artifacts/app-debug.apk
mkdir -p "$apk_root/assets/flutter_assets"
for abi in arm64-v8a armeabi-v7a x86_64; do
  mkdir -p "$apk_root/lib/$abi"
  printf '%s\n' "fixture $abi bridge" >"$apk_root/lib/$abi/libubaa_flutter_bridge.so"
done
printf '%s\n' 'fixture dex' >"$apk_root/classes.dex"
printf '%s\n' 'fixture assets' >"$apk_root/assets/flutter_assets/AssetManifest.bin"
(
  cd "$apk_root"
  zip -q "$apk_artifact" \
    classes.dex \
    assets/flutter_assets/AssetManifest.bin \
    lib/arm64-v8a/libubaa_flutter_bridge.so \
    lib/armeabi-v7a/libubaa_flutter_bridge.so \
    lib/x86_64/libubaa_flutter_bridge.so
)

cat >"$test_root/fake-bin/codesign" <<'FAKE_CODESIGN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$UBAA_TEST_CODESIGN_LOG"
case "$UBAA_TEST_ENTITLEMENTS" in
  valid)
    cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
    ;;
  missing-network)
    cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
</dict></plist>
PLIST
    ;;
  sandbox-disabled)
    cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><false/>
<key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
    ;;
  string-sandbox)
    cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><string>true</string>
<key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
    ;;
  string-network)
    cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><string>true</string>
</dict></plist>
PLIST
    ;;
  malformed)
    printf '%s\n' 'not a property list'
    ;;
  read-failure)
    exit 74
    ;;
  *)
    exit 75
    ;;
esac
FAKE_CODESIGN
chmod +x "$test_root/fake-bin/codesign"

cat >"$test_root/fake-bin/PlistBuddy" <<'FAKE_PLIST_BUDDY'
#!/usr/bin/env python3
import os
import plistlib
import sys

arguments = sys.argv[1:]
with open(os.environ["UBAA_TEST_PLIST_LOG"], "a", encoding="utf-8") as log:
    log.write(" ".join(arguments) + "\n")

xml_output = bool(arguments and arguments[0] == "-x")
if xml_output:
    arguments = arguments[1:]
if len(arguments) != 3 or arguments[0] != "-c":
    sys.exit(76)

command = arguments[1]
try:
    with open(arguments[2], "rb") as source:
        value = plistlib.load(source)
except (OSError, plistlib.InvalidFileException):
    sys.exit(77)

if command != "Print":
    prefix = "Print :"
    if not command.startswith(prefix) or not isinstance(value, dict):
        sys.exit(78)
    key = command[len(prefix):]
    if key not in value:
        sys.exit(1)
    value = value[key]

if xml_output:
    sys.stdout.buffer.write(plistlib.dumps(value))
elif isinstance(value, bool):
    print(str(value).lower())
elif isinstance(value, dict):
    print("Dict")
else:
    print(value)
FAKE_PLIST_BUDDY
chmod +x "$test_root/fake-bin/PlistBuddy"

run_artifact_checker() {
  local platform=$1
  local artifact=$2
  local output_file=$3
  local status
  set +e
  "$artifact_bash" "$artifact_checker" "$platform" "$artifact" >"$output_file" 2>&1
  status=$?
  set -e
  printf '%s\n' "$status"
}

run_entitlements_helper() {
  local entitlement_case=$1
  local output_file=$2
  local status
  set +e
  (
    # shellcheck source=../release/macos-entitlements.sh
    source "$entitlements_helper"
    UBAA_TEST_CODESIGN_LOG="$test_root/codesign.log" \
      UBAA_TEST_PLIST_LOG="$test_root/plist.log" \
      UBAA_TEST_ENTITLEMENTS="$entitlement_case" \
      verify_macos_entitlements "$macos_artifact" \
      "$test_root/fake-bin/codesign" "$test_root/fake-bin/PlistBuddy"
  ) >"$output_file" 2>&1
  status=$?
  set -e
  printf '%s\n' "$status"
}

: >"$test_root/codesign.log"
: >"$test_root/plist.log"
for platform in linux windows; do
  non_macos_status=$(run_artifact_checker "$platform" "$test_root/artifacts/$platform" \
    "$test_root/$platform.out")
  [[ $non_macos_status -eq 0 ]] || fail "$platform 产物检查被 macOS 权限门禁误伤"
done
[[ ! -s "$test_root/codesign.log" ]] || fail '非 macOS 产物检查不应调用 codesign'
pass 'Linux 与 Windows 产物检查不受 macOS 权限门禁影响'

apk_status=$(run_artifact_checker android-apk "$apk_artifact" "$test_root/android-apk.out")
[[ $apk_status -eq 0 ]] || {
  cat "$test_root/android-apk.out" >&2
  fail "真实 ZIP APK 结构检查退出码错误：$apk_status"
}
grep -F 'Flutter 产物结构通过：平台=android-apk' "$test_root/android-apk.out" >/dev/null || \
  fail '真实 ZIP APK 未完成结构检查'
pass '系统 Bash 下真实 ZIP APK 完整 CLI 检查通过'

macos_artifact=$test_root/artifacts/macos.app
macos_before=$(find "$macos_artifact" -type f -exec cksum {} + | sort)

set +e
UBAA_CODESIGN_BIN="$test_root/fake-bin/codesign" \
  UBAA_PYTHON_BIN=/usr/bin/python3 \
  UBAA_TEST_CODESIGN_LOG="$test_root/formal-codesign.log" \
  UBAA_TEST_ENTITLEMENTS=valid \
  bash "$artifact_checker" macos "$macos_artifact" \
  >"$test_root/formal-entry.out" 2>&1
formal_entry_status=$?
set -e
[[ $formal_entry_status -ne 0 ]] || fail '正式 artifact CLI 被环境覆盖绕过了系统签名读取'
[[ ! -s "$test_root/formal-codesign.log" ]] || fail '正式 artifact CLI 调用了环境注入的 codesign'
pass '正式 artifact CLI 忽略工具环境覆盖'

valid_status=$(run_entitlements_helper valid "$test_root/macos-valid.out")
[[ $valid_status -eq 0 ]] || fail '具备 Sandbox 与 network.client 的 macOS 产物被拒绝'
grep -F 'macOS 产物实际签名权限通过：Sandbox=true network.client=true' \
  "$test_root/macos-valid.out" >/dev/null || fail 'macOS checker 未输出实际签名权限通过证据'
grep -Fx -- "--display --entitlements - --xml $macos_artifact" "$test_root/codesign.log" >/dev/null || \
  fail 'macOS checker 未以只读参数提取实际签名权限'
pass 'macOS checker 接受实际签名中的必要权限'

expect_macos_rejected() {
  local entitlement_case=$1
  local expected_message=$2
  local output_file=$test_root/macos-$entitlement_case.out
  local status
  status=$(run_entitlements_helper "$entitlement_case" "$output_file")
  [[ $status -ne 0 ]] || fail "$entitlement_case 权限样例被错误接受"
  grep -F "$expected_message" "$output_file" >/dev/null || \
    fail "$entitlement_case 权限样例缺少明确失败诊断"
}

expect_macos_rejected missing-network 'com.apple.security.network.client 必须为 true'
pass 'macOS checker 拒绝缺少客户端联网权限的产物'

expect_macos_rejected sandbox-disabled 'com.apple.security.app-sandbox 必须为 true'
pass 'macOS checker 拒绝关闭沙箱的产物'

expect_macos_rejected string-sandbox 'com.apple.security.app-sandbox 必须为 true'
pass 'macOS checker 拒绝字符串型沙箱权限'

expect_macos_rejected string-network 'com.apple.security.network.client 必须为 true'
pass 'macOS checker 拒绝字符串型客户端联网权限'

expect_macos_rejected malformed '无法解析 macOS 产物的实际签名权限'
pass 'macOS checker 拒绝不可解析的签名权限'

expect_macos_rejected read-failure '无法读取 macOS 产物的实际签名权限'
pass 'macOS checker 拒绝签名权限读取失败'

expected_codesign="--display --entitlements - --xml $macos_artifact"
[[ $(wc -l <"$test_root/codesign.log") -eq 7 ]] || fail 'macOS checker 每次检查只能调用一次 codesign'
awk -v expected="$expected_codesign" '$0 != expected { exit 1 }' "$test_root/codesign.log" || \
  fail 'macOS checker 调用了写入或重签参数'
if grep -E '^(-c )?Print :com\.apple\.security\.' "$test_root/plist.log" >/dev/null; then
  fail 'macOS checker 未使用 XML 类型读取权限键'
fi
macos_after=$(find "$macos_artifact" -type f -exec cksum {} + | sort)
[[ $macos_after == "$macos_before" ]] || fail 'macOS checker 修改了被检查产物'
pass 'macOS checker 只读检查且不修改产物'

printf 'maintenance gates shell contract passed: %d tests\n' "$pass_count"
