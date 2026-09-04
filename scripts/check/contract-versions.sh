#!/usr/bin/env bash
# 纯静态校验 CLI/Bridge 版本常量、JSON Schema 与当前合同文档一致；不调用构建工具或访问网络。
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
  'apps/ubaa-cli/src/io/schema.rs' \
  's/.*pub const CLI_JSON_SCHEMA_VERSION: u32 = ([0-9]+);.*/\1/p' \
  'CLI_JSON_SCHEMA_VERSION'; then
  cli_version=$extracted_version
fi

bridge_version=
if read_single_version \
  'crates/ubaa-flutter-bridge/src/api/client.rs' \
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
  schema_versions=$(LC_ALL=C sed -nE \
    's/.*"schemaVersion"[[:space:]]*:[[:space:]]*\{[[:space:]]*"const"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' \
    "$contract_root/$schema_path")
  if [[ -z $schema_versions ]]; then
    report_error "${schema_path} 未声明 schemaVersion const"
  else
    while IFS= read -r schema_version; do
      if [[ $schema_version != "$cli_version" ]]; then
        report_error \
          "${schema_path} 含 v${schema_version}，但 CLI_JSON_SCHEMA_VERSION 为 v${cli_version}"
      fi
    done <<<"$schema_versions"
  fi
fi

if [[ -n $cli_version ]]; then
  require_literal 'README.md' "human/JSON schema v${cli_version}"
  require_literal 'README.md' "schema-v${cli_version} 信封"
  require_literal 'docs/contracts/auth-and-user.md' "CLI JSON schema v${cli_version}"
  require_literal 'docs/contracts/readonly-features.md' "schema-v${cli_version} 路由 envelope"
  require_literal 'docs/architecture/overview.md' "CLI JSON schema v${cli_version}"
  require_literal 'docs/architecture/overview.md' "schema-v${cli_version} 聚合"
  require_literal 'docs/architecture/overview.md' "CLI envelope 的 schema v${cli_version}"
  require_literal 'docs/migration/status.md' "CLI JSON schema v${cli_version}"
  require_literal 'docs/migration/status.md' "CLI schema v${cli_version}、bridge v${bridge_version}"
  require_literal 'docs/migration/status.md' "| CLI | schema v${cli_version} envelope"
  require_literal 'docs/development/testing.md' "human/JSON schema v${cli_version}"
  require_literal 'docs/development/testing.md' "当前 CLI envelope 显式升为 schema v${cli_version}"
  require_literal 'docs/development/engineering-standards.md' "human/JSON schema v${cli_version}"
  require_literal 'docs/development/engineering-standards.md' "当前 CLI envelope 为 schema v${cli_version}"
  require_literal 'docs/runbooks/live-auth-verification.md' "schema-v${cli_version} envelope"
  require_literal 'packages/ubaa_platform/README.md' "当前 CLI schema-v${cli_version}"
  require_literal 'docs/migration/source-parity.md' "当前 CLI envelope 只使用 schema v${cli_version}"
fi

if [[ -n $bridge_version ]]; then
  require_literal 'README.md' "当前 Flutter bridge contract 为 v${bridge_version}"
  require_literal 'docs/contracts/flutter-bridge.md' "合同版本为 \`${bridge_version}\`"
  require_literal 'docs/contracts/flutter-bridge.md' "\`u32=${bridge_version}\`"
  require_literal 'docs/architecture/overview.md' "Flutter bridge contract v${bridge_version}"
  require_literal 'docs/migration/status.md' "Flutter bridge contract v${bridge_version}"
  require_literal 'docs/development/testing.md' "Flutter bridge contract 升为 v${bridge_version}"
  require_literal 'docs/development/engineering-standards.md' "Flutter bridge 当前 contract 为 v${bridge_version}"
fi

if [[ $error_count -ne 0 ]]; then
  printf 'contract version check failed: %d 个问题\n' "$error_count" >&2
  exit 1
fi

printf 'contract version check passed: CLI v%s / Bridge v%s\n' "$cli_version" "$bridge_version"
