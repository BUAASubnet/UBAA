#!/usr/bin/env bash
# 在固定官方 SDK 下检查共享 package 与官方五平台宿主：格式与静态分析各执行一次，
# 测试默认逐包串行。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
check_mode=${1:-check}
if [[ $# -gt 0 ]]; then shift; fi
if [[ "$check_mode" != check && "$check_mode" != dependencies ]]; then
  printf '%s\n' 'error: 只接受 check 或 dependencies 模式' >&2
  exit 2
fi
# 单个 flutter test 已按核数并发执行测试文件；8 核本机实测 3 包并行比串行更慢，
# 默认串行，核数更多的机器可调大。
test_jobs=${UBAA_FLUTTER_TEST_JOBS:-1}
if [[ ! "$test_jobs" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' 'error: UBAA_FLUTTER_TEST_JOBS 必须是正整数' >&2
  exit 2
fi
flutter_root=${UBAA_FLUTTER_HOME:?请设置 UBAA_FLUTTER_HOME 为锁定 Flutter SDK 的绝对路径}
flutter_bin=$flutter_root/bin/flutter
dart_bin=$flutter_root/bin/dart

"$repo_root/scripts/check/flutter-toolchains.sh" official

package_list=$(python3 "$repo_root/scripts/lib/packages.py" "$@") || exit 2
packages=()
while IFS= read -r package_dir; do
  packages+=("$package_dir")
done <<<"$package_list"

# Pub workspace 由根 manifest 统一解析并生成唯一锁文件。OHOS 宿主没有加入
# 这个 workspace，仍由自己的工具链和锁文件独立处理。
cd "$repo_root"
if [[ -f pubspec.yaml ]] && grep -Eq '^workspace:' pubspec.yaml; then
  "$flutter_bin" pub get --enforce-lockfile
else
  for package_dir in "${packages[@]}"; do
    (cd "$package_dir" && "$flutter_bin" pub get --enforce-lockfile)
  done
fi
if [[ "$check_mode" == dependencies ]]; then
  exit 0
fi

format_targets=()
for package_dir in "${packages[@]}"; do
  for candidate in lib test integration_test; do
    if [[ -d "$package_dir/$candidate" ]]; then
      format_targets+=("$package_dir/$candidate")
    fi
  done
done
printf '格式检查 %s 个包\n' "${#packages[@]}"
"$dart_bin" format --output=none --set-exit-if-changed "${format_targets[@]}"

# 一个分析服务按各包自己的 analysis_options 分析全部目录，共享依赖只解析一次。
# flutter_lints 当前会把既有风格提示作为 info 输出；只让 error 阻断门禁，
# implementation_imports 等 analyzer error 仍然严格失败。
printf '静态分析 %s 个包\n' "${#packages[@]}"
"$flutter_bin" analyze --no-fatal-infos "${packages[@]}"

# 依赖已在上面统一解析，测试不再各自运行 pub get。
if ((test_jobs == 1)); then
  for package_dir in "${packages[@]}"; do
    printf '测试 %s\n' "$package_dir"
    (cd "$repo_root/$package_dir" && "$flutter_bin" test --no-pub)
  done
  exit 0
fi

log_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-flutter-test.XXXXXX")
trap 'rm -rf -- "$log_root"' EXIT
run_tests() {
  local index=$1
  local status=0
  (cd "$repo_root/${packages[$index]}" && "$flutter_bin" test --no-pub) \
    >"$log_root/$index.log" 2>&1 || status=$?
  printf '%s\n' "$status" >"$log_root/$index.status"
}

# 并行时日志按包收集，结束后按登记顺序输出。
printf '测试 %s 个包（并行 %s）\n' "${#packages[@]}" "$test_jobs"
# 测试文件多的包先启动，缩短整体耗时；macOS 自带 bash 3.2 没有 wait -n，用运行中的作业数限流。
schedule=$(for index in "${!packages[@]}"; do
  printf '%s %s\n' "$(($(find "${packages[$index]}/test" -name '*_test.dart' 2>/dev/null | wc -l)))" "$index"
done | sort -rn | cut -d' ' -f2)
for index in $schedule; do
  while (($(jobs -pr | wc -l) >= test_jobs)); do
    sleep 0.2
  done
  run_tests "$index" &
done
wait

failed=()
for index in "${!packages[@]}"; do
  status=$(cat "$log_root/$index.status")
  printf '测试 %s：退出码 %s\n' "${packages[$index]}" "$status"
  if [[ "$status" != 0 ]]; then
    cat "$log_root/$index.log"
    failed+=("${packages[$index]}")
  else
    tail -n 1 "$log_root/$index.log"
  fi
done
if ((${#failed[@]} > 0)); then
  printf 'error: 测试失败：%s\n' "${failed[*]}" >&2
  exit 1
fi
