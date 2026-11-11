#!/usr/bin/env bash
# 纯静态校验 CLI、Bridge 和应用服务版本；不调用构建工具或访问网络。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
contract_root=${UBAA_CONTRACT_ROOT:-$(cd "$script_dir/../.." && pwd -P)}
error_count=0
extracted_version=

report_error() {
  error_count=$((error_count + 1))
  printf 'contract version check: %s\n' "$1" >&2
}

read_single_version() {
  local path=$1
  local expression=$2
  local label=$3
  local values count

  extracted_version=
  if [[ ! -f "$contract_root/$path" ]]; then
    report_error "缺少 ${path}"
    return 1
  fi
  values=$(LC_ALL=C sed -nE "$expression" "$contract_root/$path")
  count=$(printf '%s\n' "$values" | LC_ALL=C awk 'NF { count += 1 } END { print count + 0 }')
  if [[ $count -ne 1 ]]; then
    report_error "${path} 必须恰好声明一个 ${label}"
    return 1
  fi
  extracted_version=$values
}

require_literal() {
  local path=$1
  local literal=$2
  if [[ ! -f "$contract_root/$path" ]]; then
    report_error "缺少 ${path}"
  elif ! LC_ALL=C grep -F -- "$literal" "$contract_root/$path" >/dev/null; then
    report_error "${path} 未声明当前版本：${literal}"
  fi
}

cli_version=
if read_single_version \
  'crates/ubaa_command/src/io/schema.rs' \
  's/.*pub const CLI_JSON_SCHEMA_VERSION: u32 = ([0-9]+);.*/\1/p' \
  'CLI_JSON_SCHEMA_VERSION'; then
  cli_version=$extracted_version
fi

bridge_version=
if read_single_version \
  'crates/ubaa_flutter_bridge/src/api/client.rs' \
  's/.*pub const BRIDGE_CONTRACT_VERSION: u32 = ([0-9]+);.*/\1/p' \
  'BRIDGE_CONTRACT_VERSION'; then
  bridge_version=$extracted_version
fi

dart_bridge_version=
if read_single_version \
  'packages/ubaa_app/lib/src/bridge/bridge_backend.dart' \
  's/.*const _supportedBridgeContractVersion = ([0-9]+);.*/\1/p' \
  '_supportedBridgeContractVersion'; then
  dart_bridge_version=$extracted_version
fi

if [[ -n $bridge_version && -n $dart_bridge_version && $bridge_version != "$dart_bridge_version" ]]; then
  report_error \
    "packages/ubaa_app/lib/src/bridge/bridge_backend.dart 接受 v${dart_bridge_version}，但 Rust Bridge 为 v${bridge_version}"
fi

schema_path='docs/contracts/cli-json.schema.json'
if [[ ! -f "$contract_root/$schema_path" ]]; then
  report_error "缺少 ${schema_path}"
elif [[ -n $cli_version ]]; then
  if schema_versions=$(python3 - "$contract_root/$schema_path" <<'JSON'
import json
from pathlib import Path
import sys


def versions(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "schemaVersion":
                if not isinstance(item, dict) or type(item.get("const")) is not int:
                    raise ValueError("schemaVersion 必须声明整数 const")
                yield item["const"]
            else:
                yield from versions(item)
    elif isinstance(value, list):
        for item in value:
            yield from versions(item)


try:
    found = list(versions(json.loads(Path(sys.argv[1]).read_text())))
    if not found:
        raise ValueError("缺少 schemaVersion const")
except (OSError, ValueError):
    sys.exit("JSON Schema 无法读取或缺少有效的 schemaVersion const")
print("\n".join(map(str, found)))
JSON
  ); then
    while IFS= read -r schema_version; do
      if [[ $schema_version != "$cli_version" ]]; then
        report_error \
          "${schema_path} 含 v${schema_version}，但 CLI_JSON_SCHEMA_VERSION 为 v${cli_version}"
      fi
    done <<<"$schema_versions"
  else
    report_error "${schema_path} 未声明有效 schemaVersion const"
  fi
fi

if [[ -n $cli_version ]]; then
  require_literal 'docs/contracts/auth-and-user.md' "CLI JSON schema v${cli_version}"
  require_literal 'docs/contracts/readonly-features.md' "schema-v${cli_version} 路由 envelope"
  require_literal 'docs/project/status.md' "CLI JSON schema v${cli_version}"
fi

if [[ -n $bridge_version ]]; then
  require_literal 'docs/contracts/flutter-bridge.md' "合同版本为 \`${bridge_version}\`"
  require_literal 'docs/contracts/flutter-bridge.md' "\`u32=${bridge_version}\`"
  require_literal 'docs/project/status.md' "Flutter bridge contract v${bridge_version}"
fi

app_service_version=
if read_single_version \
  'crates/ubaa_core/src/app_service/mod.rs' \
  's/^pub const APP_SERVICE_SCHEMA_VERSION: u32 = ([0-9]+);$/\1/p' \
  'APP_SERVICE_SCHEMA_VERSION'; then
  app_service_version=$extracted_version
fi

worker_schema_path='services/app_service/src/schema.ts'
if read_single_version \
  "$worker_schema_path" \
  's/^export const APP_SERVICE_SCHEMA_VERSION = ([0-9]+);$/\1/p' \
  'APP_SERVICE_SCHEMA_VERSION' && [[ -n $app_service_version && $app_service_version != "$extracted_version" ]]; then
  report_error "${worker_schema_path} 声明 v${extracted_version}，但 Rust Core 为 v${app_service_version}"
fi

if [[ -n $app_service_version ]]; then
  require_literal 'docs/contracts/app-service.md' "接口载荷版本为 \`schema: ${app_service_version}\`"
  app_schema_path='docs/contracts/app-service.schema.json'
  if ! app_schema_error=$(python3 - "$contract_root/$app_schema_path" "$app_service_version" 2>&1 <<'JSON'
import json
from pathlib import Path
import sys


def check_version(path, expected):
    definitions = json.loads(path.read_text(encoding="utf-8"))["$defs"]
    version = definitions["schemaVersion"]["const"]
    if type(version) is not int or version != expected:
        raise ValueError(f"schemaVersion 必须声明整数 const {expected}")

    for name in ("telemetryRequest", "eraseRequest", "bootstrapResponse"):
        field = definitions[name]["properties"]["schema"]
        if field.get("$ref") != "#/$defs/schemaVersion" or "const" in field:
            raise ValueError(f"{name} 的 schema 必须引用共用的 schemaVersion")

    query = definitions["bootstrapRequest"]["properties"]["schema"]
    if query.get("const") != str(expected):
        raise ValueError(f"bootstrapRequest 的 schema 必须声明字符串 const {expected}")


try:
    check_version(Path(sys.argv[1]), int(sys.argv[2]))
except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
    sys.exit(str(error))
JSON
  ); then
    report_error "${app_schema_path}：${app_schema_error}"
  fi
fi

if [[ $error_count -ne 0 ]]; then
  printf 'contract version check failed: %d 个问题\n' "$error_count" >&2
  exit 1
fi

printf 'contract version check passed: CLI v%s / Bridge v%s / 应用服务 v%s\n' \
  "$cli_version" "$bridge_version" "$app_service_version"
