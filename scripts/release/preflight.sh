#!/usr/bin/env bash
# 生成无签名 RC 的可审计依赖和产物前置报告；不签名、不上传、不访问真实账号。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
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

bash ./scripts/check/references.sh
bash ./scripts/check/sensitive.sh
cargo metadata --locked --format-version 1 >"$output_dir/cargo-metadata.json"

# 将 Cargo 解析后的依赖投影为不含路径/凭据的 CycloneDX 风格 SBOM。
python3 - "$output_dir/cargo-metadata.json" "$output_dir/sbom.cdx.json" <<'PY'
import json
import sys

source, target = sys.argv[1:]
metadata = json.load(open(source, encoding="utf-8"))
components = []
for package in metadata.get("packages", []):
    component = {
        "type": "library",
        "bom-ref": f"cargo:{package['name']}@{package['version']}",
        "name": package["name"],
        "version": package["version"],
        "scope": "required",
    }
    license_name = package.get("license")
    if license_name:
        component["licenses"] = [{"license": {"id": license_name}}]
    components.append(component)
document = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "version": 1,
    "metadata": {"tools": [{"vendor": "UBAA", "name": "release-preflight"}]},
    "components": components,
}
with open(target, "w", encoding="utf-8") as handle:
    json.dump(document, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
PY

lock_manifest="$output_dir/pubspec-locks.txt"
: >"$lock_manifest"
: >"$output_dir/pubspec-locks.sha256"
while IFS= read -r -d '' lockfile; do
  printf '%s\n' "$lockfile" >>"$lock_manifest"
  sha256sum "$lockfile" >>"$output_dir/pubspec-locks.sha256"
done < <(git ls-files -z -- 'apps/**/pubspec.lock' 'packages/**/pubspec.lock' | sort -z)

dependency_audit="$output_dir/dependency-audit.txt"
{
  printf 'UBAA 无签名 RC 依赖/许可证审计\n'
  printf 'Cargo SBOM：sbom.cdx.json（许可证取自 Cargo 包元数据）\n'
  printf 'Dart/Flutter 锁文件及包版本：\n'
  while IFS= read -r -d '' lockfile; do
    printf '\n[%s]\n' "$lockfile"
    awk '
      /^packages:/ { in_packages=1; next }
      /^sdks:/ { in_packages=0 }
      in_packages && /^  [A-Za-z0-9_+.-]+:/ { name=$1; sub(/:$/, "", name); printf "  %s", name }
      in_packages && /^    version:/ { print " " $2 }
    ' "$lockfile"
  done < <(git ls-files -z -- 'apps/**/pubspec.lock' 'packages/**/pubspec.lock' | sort -z)
  printf '\n审计边界：只读取锁定依赖和许可证元数据；不联网、不上传、不读取账号或运行时响应。\n'
} >"$dependency_audit"

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
SBOM：sbom.cdx.json
Dart/Flutter 锁文件清单：pubspec-locks.txt
Dart/Flutter 依赖许可证审计：dependency-audit.txt
源码校验清单：source-manifest.sha256
签名、证书、实体设备和真实写入：本报告不执行
EOF

printf '无签名 RC 前置检查通过：%s\n' "$output_dir"
printf '报告仅包含依赖元数据、锁文件列表、校验摘要和安全状态，不包含凭据或原始响应。\n'
