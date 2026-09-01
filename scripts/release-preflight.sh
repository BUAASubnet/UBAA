#!/usr/bin/env bash
# 生成无签名 RC 的可审计依赖和产物前置报告；不签名、不上传、不访问真实账号。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output_dir=${1:-${UBAA_RELEASE_REPORT_DIR:-}}
keep_output=1
if [[ -z "$output_dir" ]]; then
  output_dir=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-release-preflight.XXXXXX")
  keep_output=0
fi
if [[ "$output_dir" != /* ]]; then
  printf 'error: 报告目录必须是绝对路径：%s\n' "$output_dir" >&2
  exit 2
fi
mkdir -p "$output_dir"

cleanup() {
  if [[ "$keep_output" == 0 ]]; then
    rm -rf "$output_dir"
  fi
}
trap cleanup EXIT

cd "$repo_root"
if [[ -n "$(git status --porcelain)" ]]; then
  printf 'error: 无签名 RC 前置要求工作树干净\n' >&2
  git status --short >&2
  exit 1
fi

./scripts/ensure-references.sh
./scripts/check-sensitive.sh
cargo metadata --locked --format-version 1 >"$output_dir/cargo-metadata.json"

lock_manifest="$output_dir/pubspec-locks.txt"
: >"$lock_manifest"
: >"$output_dir/pubspec-locks.sha256"
while IFS= read -r lockfile; do
  printf '%s\n' "$lockfile" >>"$lock_manifest"
  sha256sum "$lockfile" >>"$output_dir/pubspec-locks.sha256"
done < <(find apps packages -name pubspec.lock -type f -print | sort)

git ls-files -z \
  'apps/ubaa_flutter/**' \
  'apps/ubaa_ohos/**' \
  'packages/**' \
  'crates/ubaa-flutter-bridge/**' \
  'docs/runbooks/flutter-release.md' \
  | xargs -0 sha256sum >"$output_dir/source-manifest.sha256"

cat >"$output_dir/summary.txt" <<EOF
UBAA 无签名 RC 前置报告
提交：$(git rev-parse HEAD)
分支：$(git branch --show-current)
Cargo 依赖元数据：cargo-metadata.json
Dart/Flutter 锁文件清单：pubspec-locks.txt
源码校验清单：source-manifest.sha256
签名、证书、实体设备和真实写入：本报告不执行
EOF

printf '无签名 RC 前置检查通过：%s\n' "$output_dir"
printf '报告仅包含依赖元数据、锁文件列表、校验摘要和安全状态，不包含凭据或原始响应。\n'
