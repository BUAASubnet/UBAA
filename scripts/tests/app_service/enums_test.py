"""验证应用服务枚举门禁拒绝客户端与 Schema 的实际差异。"""

import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest


ROOT = Path(__file__).resolve().parents[3]
CHECKER = ROOT / 'scripts/check/app_service/enums.py'
FEATURES = 'packages/ubaa_domain/lib/src/feature/catalog.dart'
ERRORS = 'crates/ubaa_core/src/error/mod.rs'
SCHEMA = 'docs/contracts/app-service.schema.json'


class AppServiceEnumsTest(unittest.TestCase):
    def setUp(self):
        workspace = TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        self.root = Path(workspace.name)
        self.write(FEATURES, '''enum FeatureId { grades }
extension FeatureIdText on FeatureId {
  String get wireName => switch (this) {
    FeatureId.grades => 'grades',
  };
}
''')
        self.write(ERRORS, '''#[derive(Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorKind {
    Upstream,
}
''')
        self.schema = {'$defs': {
            'feature': {'enum': ['app', 'auth', 'grades']},
            'errorKind': {'enum': ['upstream']},
        }}

    def write(self, path, source):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source, encoding='utf-8')

    def check(self):
        self.write(SCHEMA, json.dumps(self.schema))
        return subprocess.run(
            [sys.executable, str(CHECKER), '--root', str(self.root)],
            capture_output=True, text=True, check=False,
        )

    def test_matching_wire_names_pass(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_new_feature_wire_name_missing_from_schema_fails(self):
        features = (self.root / FEATURES).read_text(encoding='utf-8')
        self.write(FEATURES, features.replace('{ grades }', '{ grades, newFeature }').replace(
            "    FeatureId.grades => 'grades',", "    FeatureId.grades => 'grades',\n"
            "    FeatureId.newFeature => 'new_feature',",
        ))
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('feature 缺少：new_feature', result.stderr)

    def test_schema_feature_without_dart_wire_name_fails(self):
        self.schema['$defs']['feature']['enum'].append('extra_feature')
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('feature 多出：extra_feature', result.stderr)

    def test_new_rust_error_kind_is_compared_as_serde_snake_case(self):
        errors = (self.root / ERRORS).read_text(encoding='utf-8')
        self.write(ERRORS, errors.replace('Upstream,', 'Upstream,\n    TestFailure,'))
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('error_kind 缺少：test_failure', result.stderr)
        self.schema['$defs']['errorKind']['enum'].append('test_failure')
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
