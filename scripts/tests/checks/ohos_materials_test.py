"""OHOS 材料按实际依赖类型收集，补充材料必须与声明及文件一致。"""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('dependency_report', ROOT / 'scripts/release/dependency_report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


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
            p.write_text(json.dumps({'name': name, 'version': '1', 'dependencies': {'flutter': 'file:./flutter.har'}}))
            self.manifests.append(p)
        self.artifact = self.root / 'flutter.har'
        self.artifact.write_bytes(b'fixture artifact')
        self.license = self.root / 'flutter_LICENSE'
        self.license.write_text('独立上游许可证正文')
        self.entry = {'name': 'flutter', 'version': '1',
                      'artifact': {'path': 'flutter.har', 'sha256': digest(self.artifact)},
                      'source': {'repository': 'https://example.invalid/flutter.git', 'revision': 'a' * 40},
                      'references': [{'manifest': str(p.relative_to(self.root)), 'sha256': digest(p)} for p in self.manifests],
                      'licenses': [{'path': 'flutter_LICENSE', 'sha256': digest(self.license)}]}
        self.evidence = self.root / 'evidence.json'

    def collect(self, entries=None):
        self.evidence.write_text(json.dumps({'schema': 1, 'artifacts': entries if entries is not None else [self.entry]}))
        return report.ohos_evidence(self.root, self.root / 'output', self.manifests, self.evidence)

    def test_同一产物合并引用且复制真实许可证(self):
        records = self.collect()
        deps = [r for r in records if r['ecosystem'] == 'ohos-dependency']
        self.assertEqual(len(deps), 1)
        self.assertEqual(deps[0]['evidence_status'], 'collected')
        self.assertEqual(len(deps[0]['references']), 3)
        self.assertEqual(report.release_exit_code(records), 0)
        file = deps[0]['files'][0]
        self.assertEqual((self.root / 'output' / file['artifact']).read_bytes(), self.license.read_bytes())
        self.assertNotIn(str(self.root), json.dumps(records))

    def test_产物许可证或声明变更不能沿用旧材料(self):
        for path in [self.artifact, self.license, self.manifests[0]]:
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.write_bytes(original + b' ')
                with self.assertRaises(ValueError):
                    self.collect()
                path.write_bytes(original)

    def test_缺许可证材料仍阻断(self):
        self.entry['licenses'] = []
        with self.assertRaises(ValueError):
            self.collect()
        records = self.collect([])
        self.assertEqual(report.release_exit_code(records), 3)
        self.assertTrue(all(r['evidence_status'] == 'native_evidence_missing'
                            for r in records if r['ecosystem'] == 'ohos-dependency'))

    def test_未使用材料与含敏感信息来源拒绝(self):
        self.entry['name'] = 'unknown'
        with self.assertRaises(ValueError):
            self.collect()
        self.entry['name'] = 'flutter'
        self.entry['source']['repository'] = 'https://user:secret@example.invalid/repo'
        with self.assertRaises(ValueError):
            self.collect()

    def test_相同产物的冲突来源不能被合并掩盖(self):
        import copy
        second = copy.deepcopy(self.entry)
        self.entry['references'] = self.entry['references'][:1]
        second['references'] = second['references'][1:]
        second['source']['revision'] = 'b' * 40
        with self.assertRaisesRegex(ValueError, '冲突'):
            self.collect([self.entry, second])

    def test_重复映射拒绝而不同产物保留两条(self):
        import copy
        second = copy.deepcopy(self.entry)
        with self.assertRaisesRegex(ValueError, '重复'):
            self.collect([self.entry, second])
        self.entry['references'] = self.entry['references'][:1]
        second['references'] = second['references'][1:]
        another = self.root / 'another.har'
        another.write_bytes(b'another build')
        second['artifact'] = {'path': 'another.har', 'sha256': digest(another)}
        deps = [r for r in self.collect([self.entry, second]) if r['ecosystem'] == 'ohos-dependency']
        self.assertEqual(len(deps), 2)

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
        records = self.collect([])
        self.assertEqual(records[1]['evidence_status'], 'collected')
        self.assertEqual(records[1]['scope'], 'type-declarations')
        self.assertEqual(records[1]['version'], '1')
        self.assertTrue(records[1]['source_files'])


if __name__ == '__main__':
    unittest.main()
