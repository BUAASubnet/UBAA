"""下载页数据只接受与请求版本、构建一致的完整公开清单。"""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('download_manifest', ROOT / 'scripts/release/download_manifest.py')
download_manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(download_manifest)


def synthetic(tag='v9.9.9', build='9001'):
    version = tag.removeprefix('v')
    return {
        'version': version, 'build': build, 'commit': 'synthetic',
        'assets': [{'name': name, 'size': 1024,
                    'url': f'https://r2.ubaa.top/releases/{tag}/{build}/{name}'}
                   for name in download_manifest.expected_names(version)],
    }


class DownloadManifestTest(unittest.TestCase):
    def setUp(self):
        parent = ROOT / '.ubaa_local/download_manifest/tests'
        parent.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=parent)
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name) / 'download.json'

    def run_main(self, manifest, tag='v9.9.9', build='9001'):
        requested = []

        def load(*args):
            requested.append(args)
            return copy.deepcopy(manifest)

        download_manifest.main([tag, build], load=load, output=self.output)
        return requested

    def test_完整清单原样写入下载页数据(self):
        manifest = synthetic()
        self.assertEqual(self.run_main(manifest), [('v9.9.9', '9001')])
        self.assertEqual(json.loads(self.output.read_text()), manifest)

    def test_不合格的清单不写入(self):
        def missing_asset(value):
            value['assets'].pop()

        def other_build(value):
            value['build'] = '9000'

        def foreign_url(value):
            value['assets'][1]['url'] = 'https://example.invalid/UBAA.apk'

        def empty_size(value):
            value['assets'][2]['size'] = 0

        for mutate in (missing_asset, other_build, foreign_url, empty_size):
            with self.subTest(case=mutate.__name__):
                manifest = synthetic()
                mutate(manifest)
                with self.assertRaises(ValueError):
                    self.run_main(manifest)
                self.assertFalse(self.output.exists())

    def test_参数缺失时说明用法(self):
        with self.assertRaisesRegex(ValueError, '用法'):
            download_manifest.main(['v9.9.9'], load=lambda *args: synthetic(), output=self.output)

    def test_站点当前数据满足同一校验(self):
        current = json.loads((ROOT / 'docs/site/download.json').read_text())
        download_manifest.validate(current, 'v' + current['version'], current['build'])


if __name__ == '__main__':
    unittest.main()
