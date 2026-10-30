#!/usr/bin/env bash
# 发布前检查干净工作树、敏感扫描与 Dart/OHOS 许可证材料；不签名、不上传、不访问真实账号。
set -euo pipefail

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
  if [[ "$keep_output" == 0 && "$preserve_output" == 0 ]]; then
    rm -rf "$output_dir"
  fi
}
trap cleanup EXIT

cd "$repo_root"
if [[ -n "$(git status --porcelain)" ]]; then
  printf 'error: 发布前置要求工作树干净\n' >&2
  git status --short >&2
  exit 1
fi

bash ./scripts/check/references.sh
bash ./scripts/check/sensitive.sh

# 固定工具离线使用；依赖准备由显式 bootstrap 完成。Rust 依赖许可由 cargo-deny 检查。
dependency_status=0
dependency_args=(--output "$output_dir")
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

cat >"$output_dir/summary.txt" <<EOF
UBAA 发布前置报告
$material_summary
提交：$(git rev-parse HEAD)
分支：$(git branch --show-current)
Dart/OHOS 许可证材料与缺口：license-evidence.json、dependency-audit.txt、licenses/
Rust 依赖许可与安全公告：由 just dependency-audit（cargo-deny）检查，不在本报告重复
签名、证书、实体设备和真实写入：本报告不执行
EOF

if [[ "$mode" == report ]]; then
  printf '执行模式：仅报告；材料缺口保留在清单中，本命令不判定发布通过。\n' >>"$output_dir/summary.txt"
fi
if [[ "$dependency_status" -eq 3 ]]; then
  printf '许可证材料存在发布阻塞；详见 license-evidence.json。\n' >>"$output_dir/summary.txt"
fi

if [[ "$mode" == report ]]; then
  printf '发布前置报告已生成；%s；未判定发布通过：%s\n' "$material_summary" "$output_dir"
elif [[ "$keep_output" == 1 ]]; then
  printf '发布前置报告已生成；许可缺口见材料清单：%s\n' "$output_dir"
elif [[ "$dependency_status" -eq 3 ]]; then
  printf '发布前置报告存在发布阻塞，报告已保留：%s\n' "$output_dir"
else
  printf '发布前置报告校验完成；临时报告将在退出时清理，保留报告请设置 report_dir。\n'
fi
printf '报告仅包含许可证材料、摘要和状态，不包含凭据或原始响应。\n'
if [[ "$dependency_status" -ne 0 ]]; then
  exit "$dependency_status"
fi
