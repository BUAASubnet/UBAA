"""服务器下载完整性、构建号不可覆盖和分发完成条件。"""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('server_deploy', ROOT / 'scripts/server/deploy.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class DeployTest(unittest.TestCase):
    def setUp(self):
        parent = ROOT / '.ubaa_local/server_tests'
        parent.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=parent)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.enterContext(patch.object(deploy, 'ROOT', self.root / 'server'))
        self.run = self.enterContext(patch.object(deploy, 'run'))
        self.folder = self.root / 'staging'
        self.folder.mkdir()
        self.manifest = {'version': '2.0.0', 'build': '2007', 'commit': 'a' * 40, 'assets': [
            {'name': 'package.apk', 'size': 4, 'sha256': hashlib.sha256(b'test').hexdigest()}]}
        self.file = self.folder / 'package.apk'
        self.file.write_bytes(b'test')
        self.destination = deploy.ROOT / 'downloads/releases/v2.0.0/2007'

    def test_下载损坏时不调用云盘发布(self):
        self.file.write_bytes(b'xxxx')
        with self.assertRaisesRegex(ValueError, '清单不符'):
            deploy.release(self.folder, self.manifest)
        self.run.assert_not_called()

    def test_构建号已有不同内容时拒绝覆盖(self):
        self.destination.mkdir(parents=True)
        (self.destination / self.file.name).write_bytes(b'old!')
        with self.assertRaisesRegex(ValueError, '构建号'):
            deploy.release(self.folder, self.manifest)
        self.assertEqual((self.destination / self.file.name).read_bytes(), b'old!')
        self.run.assert_not_called()

    def test_云盘失败时不能标记分发完成(self):
        self.run.side_effect = [None, RuntimeError('合成上传失败')]
        with self.assertRaises(RuntimeError):
            deploy.release(self.folder, self.manifest)
        self.assertFalse((self.destination / 'distribution.json').exists())
        self.assertTrue((self.destination / 'release.json').exists())

    def test_成功分发后保留清单和完成标记(self):
        deploy.release(self.folder, self.manifest)
        self.assertEqual(json.loads((self.destination / 'release.json').read_text()), self.manifest)
        self.assertTrue(json.loads((self.destination / 'distribution.json').read_text())['complete'])
        self.assertIn('/opt/ubaa/bin/bhpan-publish', self.run.call_args.args)


if __name__ == '__main__':
    unittest.main()
