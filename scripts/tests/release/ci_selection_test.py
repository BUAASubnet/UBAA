"""CI 生成选择、测试分组与汇总必须保留完整覆盖。"""
import importlib.util
import unittest
import subprocess
import tempfile
import zipfile
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

    def test_Android单架构检查拒绝缺少库和混入其他架构(self):
        private = ROOT / '.ubaa_local'
        private.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=private) as folder:
            artifact = Path(folder) / 'app.apk'
            base = ['classes.dex', 'assets/flutter_assets/AssetManifest.bin',
                    'lib/arm64-v8a/libubaa_flutter_bridge.so', 'lib/arm64-v8a/libflutter.so']
            for files, abi, expected in [(base, 'arm64-v8a', 0),
                                          (base[:-1], 'arm64-v8a', 1),
                                          (base + ['lib/x86_64/libextra.so'], 'arm64-v8a', 1),
                                          (base, 'unknown', 2), (base, '', 1)]:
                with self.subTest(abi=abi, files=files):
                    with zipfile.ZipFile(artifact, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                        for name in files:
                            archive.writestr(name, 'fixture')
                    result = subprocess.run(['bash', str(ROOT / 'scripts/release/verify-flutter-artifact.sh'),
                                             'android-apk', str(artifact), abi], capture_output=True, text=True)
                    self.assertEqual(result.returncode, expected, result.stdout + result.stderr)

    def test_Android产物检查拒绝任意未压缩原生库(self):
        private = ROOT / '.ubaa_local'
        private.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=private) as folder:
            artifact = Path(folder) / 'app.apk'
            for abi in ('', 'arm64-v8a'):
                for stored in (False, True):
                    with self.subTest(abi=abi, stored=stored):
                        with zipfile.ZipFile(artifact, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                            archive.writestr('classes.dex', 'fixture')
                            archive.writestr('assets/flutter_assets/AssetManifest.bin', 'fixture')
                            abis = (abi,) if abi else ('arm64-v8a', 'armeabi-v7a', 'x86_64')
                            for target in abis:
                                for name in ('libubaa_flutter_bridge.so', 'libflutter.so'):
                                    archive.writestr(f'lib/{target}/{name}', 'fixture')
                            archive.writestr('lib/arm64-v8a/libextra.so', 'fixture',
                                             compress_type=zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED)
                        result = subprocess.run(['bash', str(ROOT / 'scripts/release/verify-flutter-artifact.sh'),
                                                 'android-apk', str(artifact), abi], capture_output=True, text=True)
                        self.assertEqual(result.returncode, 1 if stored else 0, result.stdout + result.stderr)

if __name__ == '__main__':
    unittest.main()
