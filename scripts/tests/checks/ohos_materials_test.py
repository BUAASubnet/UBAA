"""OHOS 原生依赖材料从锁定 SDK 推导；SDK 缺失或提交不符时保留缺口。"""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('dependency_report', ROOT / 'scripts/release/dependency_report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class OhosMaterialsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'LICENSE').write_text('项目许可正文')
        self.manifests = []
        for name in ['one', 'two', 'three']:
            p = self.root / name / 'oh-package.json5'
            p.parent.mkdir()
            p.write_text(json.dumps({'name': name, 'version': '1',
                                     'dependencies': {'@ohos/flutter_ohos': 'file:./har/flutter.har'}}))
            self.manifests.append(p)
        self.sdk = self.root.parent / (self.root.name + '-sdk')
        self.sdk.mkdir()
        self.addCleanup(lambda: subprocess.run(['rm', '-rf', str(self.sdk)], check=True))
        (self.sdk / 'LICENSE').write_text('上游许可证正文')
        (self.sdk / 'LICENSE_HW').write_text('附加许可证正文')
        subprocess.run(['git', 'init', '-q', str(self.sdk)], check=True)
        subprocess.run(['git', '-C', str(self.sdk), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.sdk), '-c', 'user.name=测试', '-c',
                        'user.email=fixture@example.invalid', 'commit', '-qm', '合成 SDK'], check=True)
        head = subprocess.check_output(['git', '-C', str(self.sdk), 'rev-parse', 'HEAD'], text=True).strip()
        self.pins = {'OHOS_FLUTTER_COMMIT': head, 'OHOS_FLUTTER_VERSION': '3.41.10-ohos-1.0.1',
                     'OHOS_FLUTTER_REMOTE': 'https://example.invalid/flutter_ohos.git'}

    def collect(self, sdk='default'):
        sdk = self.sdk if sdk == 'default' else sdk
        return [r for r in report.ohos_evidence(self.root, self.root / 'output', self.manifests, sdk, self.pins)
                if r['ecosystem'] == 'ohos-dependency']

    def test_锁定SDK推导唯一HAR材料并合并引用(self):
        records = self.collect()
        self.assertEqual(len(records), 1)
        record = records[0]
        self.assertEqual(record['evidence_status'], 'collected')
        self.assertEqual(record['revision'], self.pins['OHOS_FLUTTER_COMMIT'])
        self.assertEqual(record['references'], ['one/oh-package.json5', 'three/oh-package.json5', 'two/oh-package.json5'])
        self.assertEqual([f['name'] for f in record['files']], ['LICENSE', 'LICENSE_HW'])
        self.assertEqual((self.root / 'output' / record['files'][0]['artifact']).read_text(), '上游许可证正文')
        self.assertNotIn(str(self.sdk), json.dumps(record))

    def test_SDK提交不符时不收集许可证(self):
        self.pins['OHOS_FLUTTER_COMMIT'] = 'a' * 40
        records = self.collect()
        self.assertEqual(len(records), 3)
        self.assertTrue(all(r['evidence_status'] == 'native_evidence_missing' for r in records))
        self.assertIn('OHOS_FLUTTER_COMMIT', records[0]['material_input'])

    def test_未配置SDK时保留缺口(self):
        records = self.collect(sdk=None)
        self.assertTrue(all(r['evidence_status'] == 'native_evidence_missing' for r in records))
        self.assertIn('UBAA_OHOS_FLUTTER_HOME', records[0]['material_input'])

    def test_自有类型声明记录版本摘要并继承许可证(self):
        manifest = self.manifests[0]
        target = manifest.parent / 'types/bridge'
        target.mkdir(parents=True)
        (target / 'oh-package.json5').write_text('{"name":"libbridge.so","version":"1","types":"./Index.d.ts"}')
        (target / 'Index.d.ts').write_text('// 合成类型声明\n')
        manifest.write_text('{"name":"plugin","version":"1","dependencies":{"libbridge.so":"file:./types/bridge"}}')
        self.manifests = [manifest]
        import subprocess
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', '-C', str(self.root), 'add', 'one', 'LICENSE'], check=True)
        records = report.ohos_evidence(self.root, self.root / 'output', self.manifests, None, self.pins)
        self.assertEqual(records[1]['evidence_status'], 'collected')
        self.assertEqual(records[1]['scope'], 'type-declarations')
        self.assertEqual(records[1]['version'], '1')
        self.assertTrue(records[1]['source_files'])



if __name__ == '__main__':
    unittest.main()
