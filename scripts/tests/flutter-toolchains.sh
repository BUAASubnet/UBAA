#!/usr/bin/env bash
# Flutter 工具链检查合同；假 SDK 与 Git 仅存在于临时目录，不启动真实 Flutter。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
checker=$repo_root/scripts/check/flutter-toolchains.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-flutter-toolchains.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT
sdk_root=$test_root/sdk
mkdir -p "$sdk_root/bin" "$test_root/fake-bin"

cat >"$test_root/fake-bin/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 4 || $1 != -C || $2 != "$UBAA_TEST_SDK_ROOT" || $3 != rev-parse || $4 != HEAD ]]; then
  printf '%s\n' '测试禁止访问假 SDK 之外的 Git 路径或命令' >&2
  exit 97
fi
printf '%s\n' "$UBAA_TEST_SDK_COMMIT"
FAKE_GIT

cat >"$sdk_root/bin/flutter" <<'FAKE_FLUTTER'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 && $1 == --version ]] || exit 98
printf '%s\n' 'bootstrap 诊断写入 stderr' >&2
if [[ $UBAA_TEST_SDK_OUTPUT == cold ]]; then
  # 锁定 Flutter 的 update_dart_sdk.sh:146/160 将 curl 进度以 2>&1 合入 stdout。
  printf '\n%s\n%s\n%s\r\n\n' \
    'Downloading Linux x64 Dart SDK from Flutter engine 42d3d75a56efe1a2e9902f52dc8006099c45d937...' \
    '  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current' \
    '100  221M  100  221M    0     0  40.0M      0  0:00:05  0:00:05 --:--:-- 40.0M'
  printf '%s\n' '下载诊断中的 Flutter 0.0.0 不是版本行'
fi
printf '%s\n' "$UBAA_TEST_SDK_VERSION"
if [[ $UBAA_TEST_SDK_OUTPUT == fail ]]; then
  printf '%s\n' '假 Flutter 执行失败' >&2
  exit 73
fi
if [[ $UBAA_TEST_SDK_OUTPUT == long ]]; then
  # 多次写入超过管道缓冲区的输出，使提前关闭的读取端稳定触发失败。
  printf -v chunk '%4096s' x
  for ((index = 0; index < 1024; index++)); do
    printf '%s\n' "$chunk"
  done
fi
if [[ $UBAA_TEST_SDK_OUTPUT == later-banner ]]; then
  printf '%s\n' 'Flutter 3.41.9'
fi
printf '%s\n' '后续诊断包含 Flutter 3.41.9，但不能替代独立版本行'
printf '%s\n' 'stdout 已完整写出' >"$UBAA_TEST_SDK_COMPLETED"
FAKE_FLUTTER
chmod +x "$test_root/fake-bin/git" "$sdk_root/bin/flutter"

pass_count=0
official_commit=00b0c91f06209d9e4a41f71b7a512d6eb3b9c694
ohos_commit=adaf911c35c9136a7d18fc424d714c9ec7724e60

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  pass_count=$((pass_count + 1))
  printf 'ok %d - %s\n' "$pass_count" "$1"
}

run_checker() {
  local name=$1 commit=$2 version=$3 output=$4 mode=${5:-official}
  PATH="$test_root/fake-bin:$PATH" \
    UBAA_FLUTTER_HOME="$sdk_root" UBAA_OHOS_FLUTTER_HOME="$sdk_root" \
    UBAA_TEST_SDK_ROOT="$sdk_root" UBAA_TEST_SDK_COMMIT="$commit" \
    UBAA_TEST_SDK_VERSION="$version" UBAA_TEST_SDK_OUTPUT="$output" \
    UBAA_TEST_SDK_COMPLETED="$test_root/$name.complete" \
    bash "$checker" "$mode" >"$test_root/$name.out" 2>"$test_root/$name.err"
}

if run_checker long "$official_commit" 'Flutter 3.41.9' long; then
  [[ -f "$test_root/long.complete" ]] || fail '成功检查必须等待 stdout 全部写出'
  [[ $(<"$test_root/long.out") == "官方Flutter 已锁定：3.41.9 @ $official_commit" ]] \
    || fail '版本检查输出必须只保留确认信息'
  grep -F 'bootstrap 诊断写入 stderr' "$test_root/long.err" >/dev/null
else
  status=$?
  fail "正确版本的长多段 stdout 必须完整消费，实际退出码 $status"
fi
pass '正确官方版本的长多段 stdout 被完整消费，bootstrap stderr 不参与版本匹配'

if run_checker wrong-version "$official_commit" 'Flutter 0.0.0' later-banner; then
  fail '第一条版本行错误时被后续正确版本行错误接受'
fi
grep -F '版本不匹配' "$test_root/wrong-version.err" >/dev/null
pass '第一条版本行错误时拒绝，即使后续存在正确版本行'

if run_checker wrong-commit 0000000000000000000000000000000000000000 'Flutter 3.41.9' short; then
  fail '错误 commit 被接受'
fi
grep -F 'commit 不匹配' "$test_root/wrong-commit.err" >/dev/null
[[ ! -e "$test_root/wrong-commit.complete" ]] || fail 'commit 不符时不得执行 Flutter'
pass '错误 commit 在启动 Flutter 前被拒绝'

if run_checker failed "$official_commit" 'Flutter 3.41.9' fail; then
  fail 'Flutter 输出正确版本后执行失败被错误接受'
else
  status=$?
  [[ $status -eq 73 ]] || fail "Flutter 失败退出码丢失：$status"
fi
pass '正确版本之后的 Flutter 执行失败仍按原退出码拒绝'

if run_checker empty "$official_commit" '' short; then
  fail '未发现独立版本行时被诊断中的版本文本错误接受'
fi
grep -F '版本不匹配' "$test_root/empty.err" >/dev/null
pass '未发现独立版本行时拒绝，即使诊断中包含 Flutter'

if run_checker ohos "$ohos_commit" 'Flutter 3.41.10-ohos-1.0.1' long ohos; then
  [[ -f "$test_root/ohos.complete" ]] || fail 'OHOS 检查提前停止消费 stdout'
else
  fail '锁定 OHOS 版本的长多段输出被错误拒绝'
fi
pass 'OHOS 同样完整消费 stdout 并接受其锁定版本'

if run_checker cold "$official_commit" 'Flutter 3.41.9' cold; then
  [[ -f "$test_root/cold.complete" ]] || fail '冷启动输出未被完整消费'
else
  status=$?
  fail "冷启动进度、下载文案和空行之后的正确版本必须通过，实际退出码 $status"
fi
pass '允许冷启动进度、下载文案及空行出现在真正版本行之前'

if run_checker version-collision "$official_commit" 'Flutter 3.41.90' short; then
  fail '版本前缀碰撞 3.41.90 被错误接受为 3.41.9'
fi
grep -F '版本不匹配' "$test_root/version-collision.err" >/dev/null
pass '精确比较版本 token，拒绝 3.41.90 前缀碰撞'

printf 'Flutter 工具链 Shell 合同通过：%s 项\n' "$pass_count"
