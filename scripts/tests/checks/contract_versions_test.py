"""公开合同的代码版本一致性检查。"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
CHECKER = ROOT / 'scripts/check/contract-versions.sh'


class ContractVersionsTest(unittest.TestCase):
    def fixture(self):
        root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        files = {
            'crates/ubaa_command/src/io/schema.rs':
                'pub const CLI_JSON_SCHEMA_VERSION: u32 = 18;\n',
            'crates/ubaa_flutter_bridge/src/api/client.rs':
                'pub const BRIDGE_CONTRACT_VERSION: u32 = 78;\n',
            'packages/ubaa_app/lib/src/bridge/bridge_backend.dart':
                'const _supportedBridgeContractVersion = 78;\n',
            'crates/ubaa_core/src/app_service/mod.rs':
                'pub const APP_SERVICE_SCHEMA_VERSION: u32 = 1;\n',
            'services/app_service/src/schema.ts':
                'export const APP_SERVICE_SCHEMA_VERSION = 1;\n',
            'docs/contracts/cli-json.schema.json': json.dumps({
                'properties': {'schemaVersion': {'const': 18}},
            }, indent=2),
            'docs/contracts/app-service.schema.json': json.dumps({'$defs': {
                'schemaVersion': {'const': 1},
                'telemetryRequest': {'properties': {'schema': {'$ref': '#/$defs/schemaVersion'}}},
                'eraseRequest': {'properties': {'schema': {'$ref': '#/$defs/schemaVersion'}}},
                'bootstrapResponse': {'properties': {'schema': {'$ref': '#/$defs/schemaVersion'}}},
                'bootstrapRequest': {'properties': {'schema': {'type': 'string', 'const': '1'}}},
            }}),
        }
        for relative, contents in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        return root

    def run_checker(self, root):
        return subprocess.run(
            ['bash', str(CHECKER)], cwd=ROOT,
            env={'PATH': os.environ['PATH'],
                 'UBAA_CONTRACT_ROOT': str(root)},
            text=True, capture_output=True, check=False,
        )

    def test_document_version_differences_do_not_fail(self):
        root = self.fixture()
        docs = {
                'docs/contracts/auth-and-user.md': 'CLI JSON schema v17\n',
                'docs/contracts/readonly-features.md': 'schema-v16 路由 envelope\n',
                'docs/project/status.md': 'CLI JSON schema v1；Flutter bridge contract v2。\n',
                'docs/contracts/flutter-bridge.md': '合同版本为 `1`；`u32=2`。\n',
                'docs/contracts/app-service.md': '接口载荷版本为 `schema: 9`。\n',
        }
        for relative, contents in docs.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        result = self.run_checker(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_no_markdown_required(self):
        result = self.run_checker(self.fixture())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rust_schema_dart_and_service_versions_must_match(self):
        cases = {
            'packages/ubaa_app/lib/src/bridge/bridge_backend.dart':
                'const _supportedBridgeContractVersion = 77;\n',
            'services/app_service/src/schema.ts': 'export const APP_SERVICE_SCHEMA_VERSION = 2;\n',
            'docs/contracts/cli-json.schema.json': json.dumps({'oneOf': [
                {'properties': {'schemaVersion': {'const': 18}}},
                {'properties': {'schemaVersion': {'const': 17}}},
            ]}, indent=2),
        }
        for relative, contents in cases.items():
            with self.subTest(relative=relative):
                root = self.fixture()
                (root / relative).write_text(contents)
                self.assert_rejected(root, relative)

    def test_app_service_schema_versions_and_references_must_match(self):
        for definition, field in (
            ('schemaVersion', {'const': 2}),
            ('bootstrapRequest', {'type': 'string', 'const': '2'}),
            ('eraseRequest', {'type': 'integer', 'const': 2}),
        ):
            with self.subTest(definition=definition):
                root = self.fixture()
                path = root / 'docs/contracts/app-service.schema.json'
                schema = json.loads(path.read_text())
                definitions = schema['$defs']
                if definition == 'schemaVersion':
                    definitions[definition] = field
                else:
                    definitions[definition]['properties']['schema'] = field
                path.write_text(json.dumps(schema))
                self.assert_rejected(root, definition)

    def assert_rejected(self, root, diagnostic):
        result = self.run_checker(root)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(diagnostic, result.stderr)
