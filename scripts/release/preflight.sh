#!/usr/bin/env bash
# 生成无签名 RC 的可审计依赖和产物前置报告；不签名、不上传、不访问真实账号。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
output_dir=${1:-${UBAA_RELEASE_REPORT_DIR:-}}
keep_output=1
metadata_file=''
if [[ -z "$output_dir" ]]; then
  output_dir=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-release-preflight.XXXXXX")
  keep_output=0
fi
if [[ "$output_dir" != /* ]]; then
  printf 'error: 报告目录必须是绝对路径：%s\n' "$output_dir" >&2
  exit 2
fi
mkdir -p "$output_dir"
python3 - "$output_dir" <<'PY'
from pathlib import Path
import sys
if any(Path(sys.argv[1]).iterdir()):
    raise SystemExit('error: 发布报告目录必须为空；请使用新的目录，避免混入历史材料')
PY

cleanup() {
  if [[ -n "$metadata_file" ]]; then
    rm -f "$metadata_file"
  fi
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

bash ./scripts/check/references.sh
bash ./scripts/check/sensitive.sh
metadata_file=$(mktemp "${TMPDIR:-/tmp}/ubaa-cargo-metadata.XXXXXX")
cargo metadata --offline --locked --format-version 1 >"$metadata_file"

# 固定工具和 schema 均离线使用；依赖准备由显式 bootstrap 完成。
bash "$repo_root/scripts/tools/python.sh" "$script_dir/dependency_report.py" \
  --metadata "$metadata_file" --output "$output_dir"

lock_manifest="$output_dir/pubspec-locks.txt"
: >"$lock_manifest"
: >"$output_dir/pubspec-locks.sha256"
while IFS= read -r -d '' lockfile; do
  printf '%s\n' "$lockfile" >>"$lock_manifest"
  sha256sum "$lockfile" >>"$output_dir/pubspec-locks.sha256"
done < <(git ls-files -z -- 'apps/**/pubspec.lock' 'packages/**/pubspec.lock' | sort -z)

python3 "$script_dir/source_manifest.py" --output "$output_dir"

cat >"$output_dir/summary.txt" <<EOF
UBAA 无签名 RC 前置报告
提交：$(git rev-parse HEAD)
分支：$(git branch --show-current)
Cargo 依赖清单与离线 schema 校验后的 SBOM：sbom.cdx.json
原始 Cargo metadata：仅临时转换输入，不保存到发布材料
Dart/Flutter 锁文件清单：pubspec-locks.txt
Dart/OHOS 许可证材料与缺口：license-evidence.json、dependency-audit.txt、licenses/
全部 Git 跟踪输入的校验清单：source-manifest.sha256
候选与输入摘要关联：build-record.json（外部 SDK、系统库和下载依赖不属于源码清单）
签名、证书、实体设备和真实写入：本报告不执行
EOF

printf '无签名 RC 前置报告已生成；许可缺口见材料清单：%s\n' "$output_dir"
printf '报告仅包含依赖元数据、锁文件列表、校验摘要和安全状态，不包含凭据或原始响应。\n'
