#!/usr/bin/env bash
# 从已审阅的宣传图生成网站用图：截图页的 WebP 和链接分享图。只写 docs/site/public/。
set -euo pipefail

if [[ $# -ne 0 ]]; then
  printf '%s\n' '用法：bash scripts/release/site-images.sh' >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
cd "$(ubaa_repo_root)"

if ! command -v magick >/dev/null; then
  printf '%s\n' '请先安装带 WebP 支持的 ImageMagick 7（需要 magick 命令）。' >&2
  exit 1
fi

public=docs/site/public
creative=docs/site/store_assets/ubaa-app-store-creative.png

# 截图页显示 WebP，点击打开同目录的原始 PNG；手机图按卡片宽度、平板和桌面按两列宽度的两倍生成。
shopt -s nullglob
for group in phone tablet desktop; do
  width=900
  [[ $group == phone ]] && width=600
  for png in "$public/screenshots/$group"/*.png; do
    magick "$png" -resize "${width}x" -strip -quality 80 "${png%.png}.webp"
  done
done

# 分享卡片使用 1200x630，从横版宣传图居中裁切。
magick "$creative" -resize 1200x -gravity center -crop 1200x630+0+0 +repage -strip -quality 85 "$public/og.jpg"

printf '%s\n' "网站用图已更新：$public/screenshots/*/*.webp、$public/og.jpg"
