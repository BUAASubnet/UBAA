#!/usr/bin/env bash
# 无头生成应用商店宣传图。原图与成品分开存放，便于人工复核后提交。
set -euo pipefail
umask 077

test_name='^宣传图 (iphone|ipad|desktop)$'
if [[ $# -eq 1 && $1 == --all-sizes ]]; then
  test_name='^宣传图 '
elif [[ $# -ne 0 ]]; then
  printf '%s\n' '用法：bash scripts/release/store-screenshots.sh [--all-sizes]' >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
cd "$(ubaa_repo_root)"

if ! command -v magick >/dev/null; then
  printf '%s\n' '请先安装 ImageMagick 7（需要 magick 命令）。' >&2
  exit 1
fi

mkdir -p .ubaa_local/store_screenshots
run_dir=$(mktemp -d "$PWD/.ubaa_local/store_screenshots/run.XXXXXX")
raw_dir="$run_dir/raw"
ready_dir="$run_dir/ready"
mkdir -p "$raw_dir" "$ready_dir"
printf '本次渲染目录：%s\n' "$run_dir"

(
  cd apps/ubaa_flutter
  TZ=Asia/Shanghai UBAA_UI_EVIDENCE_DIR="$raw_dir" \
    just flutter test --no-pub --concurrency=1 --reporter expanded --name "$test_name" store/screenshots_test.dart
)

shopt -s nullglob
images=("$raw_dir"/*/*.png)
if ((${#images[@]} == 0)); then
  printf '%s\n' '渲染结束后没有找到 PNG。' >&2
  exit 1
fi
for image in "${images[@]}"; do
  relative=${image#"$raw_dir/"}
  case "${relative%/*}" in
    iphone) group=phone ;;
    ipad) group=tablet ;;
    desktop) group=desktop ;;
    iphone_large) group=phone/1320x2868 ;;
    iphone_medium) group=phone/1206x2622 ;;
    android) group=phone/1080x1920 ;;
    *) printf '未知截图规格：%s\n' "${relative%/*}" >&2; exit 1 ;;
  esac
  mkdir -p "$ready_dir/$group"
  magick "$image" -alpha off -strip "PNG24:$ready_dir/$group/${relative##*/}"
done
printf '已生成 %s 张 RGB PNG：%s\n' "${#images[@]}" "$ready_dir"
