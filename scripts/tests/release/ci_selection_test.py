"""CI 生成选择、测试分组与汇总必须保留完整覆盖。"""
import importlib.util
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('ci_plan', ROOT / 'scripts/check/ci/plan.py')
plan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plan)

class SelectionTest(unittest.TestCase):
    def test_生成输入与实现改动分别选择(self):
        for path in ('crates/ubaa_flutter_bridge/src/api/account.rs', 'Cargo.lock',
                     'packages/ubaa_bindings/flutter_rust_bridge.yaml',
                     'packages/ubaa_bindings/lib/src/rust/frb_generated.dart'):
            self.assertTrue(plan.codegen_required([path]), path)
        for path in ('crates/ubaa_core/src/auth.rs', 'docs/site/guide/start.md',
                     'packages/ubaa_app/lib/state.dart'):
            self.assertFalse(plan.codegen_required([path]), path)
        self.assertTrue(plan.codegen_required(None))
        self.assertTrue(plan.codegen_required(['new_unknown_input']))

    def test_每个测试文件只分配一次且golden保持macOS(self):
        matrix = plan.flutter_matrix(ROOT)
        found = []
        for group in matrix['include']:
            paths = plan.flutter_files(ROOT, group['package'], group['group'])
            self.assertTrue(paths)
            found.extend((group['package'], path) for path in paths)
            if group['group'] == 'golden':
                self.assertEqual(group['os'], 'macos-15')
        expected = [(package, str(path.relative_to(ROOT / directory)))
                    for package, directory in plan.PACKAGES.items()
                    for path in (ROOT / directory / 'test').rglob('*_test.dart')]
        self.assertCountEqual(found, expected)
        self.assertEqual(len(found), len(set(found)))

    def test_只允许明确不需要的生成作业跳过(self):
        jobs = {'plan': {'result': 'success'}, 'rust-tests': {'result': 'success'},
                'codegen': {'result': 'skipped'}}
        self.assertTrue(plan.accepted(jobs, False))
        self.assertFalse(plan.accepted(jobs, True))
        for result in ('failure', 'cancelled', 'skipped'):
            jobs['rust-tests']['result'] = result
            self.assertFalse(plan.accepted(jobs, False))

if __name__ == '__main__':
    unittest.main()
