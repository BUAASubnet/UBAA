#!/usr/bin/env bash
# 公开合同版本静态门禁测试；全部样例都在临时目录中运行，不读取真实账号或构建缓存。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
checker_source="$repo_root/scripts/check/contract-versions.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ubaa-contract-versions.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM

if [[ ! -f "$checker_source" ]]; then
  printf '%s\n' 'RED: 缺少 scripts/check/contract-versions.sh' >&2
  exit 1
fi

pass_count=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  pass_count=$((pass_count + 1))
  printf 'ok %d - %s\n' "$pass_count" "$1"
}

new_fixture() {
  local name=$1
  local fixture="$test_root/$name"
  mkdir -p \
    "$fixture/apps/ubaa-cli/src/io" \
    "$fixture/crates/ubaa-flutter-bridge/src/api" \
    "$fixture/packages/ubaa_app/lib/src/bridge" \
    "$fixture/packages/ubaa_platform" \
    "$fixture/docs/contracts" \
    "$fixture/docs/architecture" \
    "$fixture/docs/development" \
    "$fixture/docs/migration" \
    "$fixture/docs/runbooks" \
    "$fixture/scripts/check"
  cp "$checker_source" "$fixture/scripts/check/contract-versions.sh"
  chmod +x "$fixture/scripts/check/contract-versions.sh"

  printf '%s\n' 'pub const CLI_JSON_SCHEMA_VERSION: u32 = 10;' \
    >"$fixture/apps/ubaa-cli/src/io/schema.rs"
  printf '%s\n' 'pub const BRIDGE_CONTRACT_VERSION: u32 = 9;' \
    >"$fixture/crates/ubaa-flutter-bridge/src/api/client.rs"
  printf '%s\n' 'const _supportedBridgeContractVersion = 9;' \
    >"$fixture/packages/ubaa_app/lib/src/bridge/bridge_backend.dart"
  printf '%s\n' \
    '{"properties":{"schemaVersion":{"const":10}}}' \
    >"$fixture/docs/contracts/cli-json.schema.json"
  # Markdown 反引号属于文档样例，不执行命令替换。
  # shellcheck disable=SC2016
  printf '%s\n' \
    '合同版本为 `9`' \
    '| `contractVersion` | 无 | `u32=9` |' \
    >"$fixture/docs/contracts/flutter-bridge.md"
  printf '%s\n' \
    'CLI JSON schema v10；Flutter bridge contract v9。' \
    'human/JSON schema v10 命令行宿主' \
    'schema-v10 信封' \
    '当前 Flutter bridge contract 为 v9' \
    >"$fixture/README.md"
  printf '%s\n' 'CLI JSON schema v10' \
    >"$fixture/docs/contracts/auth-and-user.md"
  printf '%s\n' \
    'CLI JSON schema v10' \
    'schema-v10 聚合' \
    'CLI envelope 的 schema v10' \
    'Flutter bridge contract v9' \
    >"$fixture/docs/architecture/overview.md"
  printf '%s\n' \
    'CLI JSON schema v10；Flutter bridge contract v9。' \
    'CLI schema v10、bridge v9' \
    '| CLI | schema v10 envelope' \
    >"$fixture/docs/migration/status.md"
  printf '%s\n' 'schema-v10 路由 envelope' \
    >"$fixture/docs/contracts/readonly-features.md"
  printf '%s\n' \
    'human/JSON schema v10' \
    '当前 CLI envelope 显式升为 schema v10、Flutter bridge contract 升为 v9' \
    >"$fixture/docs/development/testing.md"
  printf '%s\n' \
    'human/JSON schema v10' \
    '当前 CLI envelope 为 schema v10' \
    'Flutter bridge 当前 contract 为 v9' \
    >"$fixture/docs/development/engineering-standards.md"
  printf '%s\n' 'schema-v10 envelope' \
    >"$fixture/docs/runbooks/live-auth-verification.md"
  # shellcheck disable=SC2016
  printf '%s\n' '当前 CLI schema-v10 的 `error` envelope' \
    >"$fixture/packages/ubaa_platform/README.md"
  printf '%s\n' '当前 CLI envelope 只使用 schema v10' \
    >"$fixture/docs/migration/source-parity.md"

  printf '%s\n' "$fixture"
}

run_checker() {
  local fixture=$1
  UBAA_CONTRACT_ROOT="$fixture" bash "$fixture/scripts/check/contract-versions.sh"
}

expect_pass() {
  local name=$1
  local fixture=$2
  local output status
  set +e
  output=$(run_checker "$fixture" 2>&1)
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    printf '%s\n' "$output" >&2
    fail "$name"
  fi
  pass "$name"
}

expect_rejected() {
  local name=$1
  local fixture=$2
  local expected_path=$3
  local output status
  set +e
  output=$(run_checker "$fixture" 2>&1)
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    fail "${name}：预期拒绝，实际通过"
  fi
  if [[ $output != *"$expected_path"* ]]; then
    printf '%s\n' "$output" >&2
    fail "${name}：诊断未包含 $expected_path"
  fi
  pass "$name"
}

fixture=$(new_fixture matching)
expect_pass '源码、schema 与当前文档版本一致时通过' "$fixture"

fixture=$(new_fixture dart-mismatch)
printf '%s\n' 'const _supportedBridgeContractVersion = 8;' \
  >"$fixture/packages/ubaa_app/lib/src/bridge/bridge_backend.dart"
expect_rejected \
  'Dart 接受的 Bridge 版本落后时拒绝' \
  "$fixture" \
  'packages/ubaa_app/lib/src/bridge/bridge_backend.dart'

fixture=$(new_fixture schema-mismatch)
printf '%s\n' '{"properties":{"schemaVersion":{"const":9}}}' \
  >"$fixture/docs/contracts/cli-json.schema.json"
expect_rejected \
  'CLI JSON Schema 常量落后时拒绝' \
  "$fixture" \
  'docs/contracts/cli-json.schema.json'

fixture=$(new_fixture stale-document)
printf '%s\n' 'human/JSON schema v9 命令行宿主' \
  >"$fixture/README.md"
expect_rejected '当前文档仍声明旧版本时拒绝' "$fixture" 'README.md'

printf '%s\n' "contract version shell contracts passed: $pass_count"
