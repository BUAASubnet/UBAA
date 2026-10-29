#!/usr/bin/env bash
# 对一个包或领域运行快速回归，不隐式选择设备和真实账号入口。
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
package=${1:?缺少包名}
test_path=${2:-test}
relative=$(python3 "$repo_root/scripts/lib/packages.py" "$package") || exit 2
package_dir="$repo_root/$relative"
case "$test_path" in
  test | test/*) ;;
  *) printf '%s\n' 'error: 此入口只接受包内 test 路径，原生/真实验证使用专项入口' >&2; exit 2 ;;
esac
if [[ "$test_path" == *'..'* || ! -e "$package_dir/$test_path" ]]; then
  printf '%s\n' 'error: 测试路径不存在或越出包目录' >&2
  exit 2
fi
flutter_root=${UBAA_FLUTTER_HOME:?请设置 UBAA_FLUTTER_HOME 为锁定 Flutter SDK 的绝对路径}
bash "$repo_root/scripts/check/flutter-toolchains.sh" official
cd "$package_dir"
exec "$flutter_root/bin/flutter" test --no-pub "$test_path"
