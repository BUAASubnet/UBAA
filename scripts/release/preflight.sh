#!/usr/bin/env bash
# 生成无签名 RC 的可审计依赖和产物前置报告；不签名、不上传、不访问真实账号。
set -euo pipefail
# shellcheck source=../lib/checksum.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/checksum.sh"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/toolchain.sh
source "$script_dir/../lib/toolchain.sh"
# shellcheck source=../lib/repo.sh
source "$script_dir/../lib/repo.sh"
repo_root=$(ubaa_repo_root)
output_dir=${1:-${UBAA_RELEASE_REPORT_DIR:-}}
mode=${2:-strict}
if [[ "$mode" != strict && "$mode" != report ]]; then
  printf 'error: 发布前置模式只接受 strict 或 report\n' >&2
  exit 2
fi
keep_output=1
preserve_output=0
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
  if [[ "$keep_output" == 0 && "$preserve_output" == 0 ]]; then
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
dependency_status=0
dependency_args=(--metadata "$metadata_file" --output "$output_dir")
if [[ -n "${UBAA_OHOS_EVIDENCE:-}" ]]; then
  if [[ "$UBAA_OHOS_EVIDENCE" != /* ]]; then
    printf 'error: OHOS 材料清单必须是绝对路径\n' >&2
    exit 2
  fi
  dependency_args+=(--ohos-evidence "$UBAA_OHOS_EVIDENCE")
fi
if [[ "$mode" == report ]]; then
  dependency_args+=(--report-only)
fi
set +e
bash "$repo_root/scripts/tools/python.sh" "$script_dir/dependency_report.py" \
  "${dependency_args[@]}"
dependency_status=$?
set -e
if [[ "$dependency_status" -ne 0 && "$dependency_status" -ne 3 ]]; then
  exit "$dependency_status"
fi
if [[ "$dependency_status" -eq 3 ]]; then
  preserve_output=1
  printf 'error: 许可证材料存在发布阻塞；报告已保留：%s\n' "$output_dir" >&2
fi
if [[ "$mode" == report ]]; then
  preserve_output=1
fi
material_summary=$(python3 - "$output_dir/license-evidence.json" <<'PY'
import json
from pathlib import Path
import sys
report = json.loads(Path(sys.argv[1]).read_text())
print(f'许可证材料状态：{report["material_status"]}；发布阻塞：{len(report["release_blockers"])}')
PY
)

lock_manifest="$output_dir/pubspec-locks.txt"
: >"$lock_manifest"
: >"$output_dir/pubspec-locks.sha256"
while IFS= read -r -d '' lockfile; do
  printf '%s\n' "$lockfile" >>"$lock_manifest"
  ubaa_sha256 "$lockfile" >>"$output_dir/pubspec-locks.sha256"
done < <(git ls-files -z -- 'pubspec.lock' 'apps/**/pubspec.lock' 'packages/**/pubspec.lock' | sort -z)

python3 "$script_dir/source_manifest.py" --output "$output_dir"

cat >"$output_dir/summary.txt" <<EOF
UBAA 无签名 RC 前置报告
$material_summary
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

if [[ "$mode" == report ]]; then
  printf '执行模式：仅报告；材料缺口保留在清单中，本命令不判定发布通过。\n' >>"$output_dir/summary.txt"
fi
if [[ "$dependency_status" -eq 3 ]]; then
  printf '许可证材料存在发布阻塞；详见 license-evidence.json。\n' >>"$output_dir/summary.txt"
fi

if [[ "$mode" == report ]]; then
  printf '无签名 RC 依赖报告已生成；%s；未判定发布通过：%s\n' "$material_summary" "$output_dir"
elif [[ "$keep_output" == 1 ]]; then
  printf '无签名 RC 前置报告已生成；许可缺口见材料清单：%s\n' "$output_dir"
elif [[ "$dependency_status" -eq 3 ]]; then
  printf '无签名 RC 前置报告存在发布阻塞，报告已保留：%s\n' "$output_dir"
else
  printf '无签名 RC 前置报告校验完成；临时报告将在退出时清理，保留报告请设置 report_dir。\n'
fi
printf '报告仅包含依赖元数据、锁文件列表、校验摘要和安全状态，不包含凭据或原始响应。\n'
if [[ "$dependency_status" -ne 0 ]]; then
  exit "$dependency_status"
fi
