"""服务器下载完整性、构建号不可覆盖和分发完成条件。"""
import os
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('server_deploy', ROOT / 'scripts/server/deploy.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class DeployTest(unittest.TestCase):
    def setUp(self):
        parent = Path(os.environ.get('UBAA_TEST_TMP') or ROOT / 'target/test_tmp') / 'server_deploy'
        parent.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=parent)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.enterContext(patch.object(deploy, 'ROOT', self.root / 'server'))
        self.enterContext(patch.object(deploy, 'STATE', self.root / 'state'))
        deploy.STATE.mkdir()
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

    def test_文档换版后保留缓存页面引用的旧静态资源(self):
        (deploy.ROOT / 'docs').mkdir(parents=True)
        for identifier in ['old', 'new']:
            source = self.root / identifier
            (source / 'assets').mkdir(parents=True)
            (source / 'assets' / (identifier + '.js')).write_text(identifier)
            deploy.docs(source, identifier)
        self.assertEqual((deploy.ROOT / 'docs/assets/old.js').read_text(), 'old')
        self.assertEqual((deploy.ROOT / 'docs/assets/new.js').read_text(), 'new')
        self.assertEqual((deploy.ROOT / 'docs/current').resolve(), deploy.ROOT / 'docs/new')

    def content(self, app_store=None, github=None, announcements=()):
        return {'channels': {'github': github, 'app_store': app_store, 'app_gallery': None},
                'announcements': list(announcements)}

    def live(self):
        return json.loads((deploy.STATE / 'content.json').read_text())

    def package(self, content):
        folder = self.root / 'package'
        folder.mkdir()
        (folder / 'content.json').write_text(json.dumps(content))
        (folder / 'deploy.py').write_text('')
        with tarfile.open(folder / 'app_service.tar.gz', 'w:gz') as archive:
            for name in ['content.json', 'deploy.py']:
                archive.add(folder / name, arcname=name)
        return folder

    def test_应用部署保留线上已发布的渠道和公告(self):
        published = self.content(app_store={'latest_version': '2.0.2'}, announcements=[{'id': 'a'}])
        deploy.atomic_json(deploy.STATE / 'content.json', published)
        with patch.object(deploy, 'healthy', return_value=True):
            deploy.application(self.package(self.content()), 'next')
        self.assertEqual(self.live(), published)

    def test_首次应用部署用包内内容初始化(self):
        initial = self.content(app_store={'latest_version': '2.0.0'})
        with patch.object(deploy, 'healthy', return_value=True):
            deploy.application(self.package(initial), 'first')
        self.assertEqual(self.live(), initial)

    def test_内容发布替换渠道和公告并保留正式发布的GitHub渠道(self):
        github = {'latest_version': '2.0.2+2020'}
        deploy.atomic_json(deploy.STATE / 'content.json', self.content(github=github))
        deploy.atomic_json(deploy.STATE / 'published.json', {})
        incoming = self.content(app_store={'latest_version': '2.0.3'}, announcements=[{'id': 'b'}])
        with patch.object(deploy, 'healthy', return_value=True):
            deploy.content(incoming)
        self.assertEqual(self.live(), {**incoming, 'channels': {**incoming['channels'], 'github': github}})
        self.run.assert_any_call('systemctl', 'restart', 'ubaa-app.service')

    def test_内容发布健康检查失败时恢复原内容(self):
        previous = self.content(app_store={'latest_version': '2.0.2'})
        deploy.atomic_json(deploy.STATE / 'content.json', previous)
        with patch.object(deploy, 'healthy', return_value=False), self.assertRaises(RuntimeError):
            deploy.content(self.content())
        self.assertEqual(self.live(), previous)

    def test_内容发布拒绝不完整的结构且不改写线上内容(self):
        previous = self.content()
        deploy.atomic_json(deploy.STATE / 'content.json', previous)
        for invalid in [{'channels': {'github': None}, 'announcements': []},
                        {'channels': previous['channels'], 'announcements': {}},
                        {**previous, 'extra': 1}]:
            with self.assertRaises(ValueError):
                deploy.content(invalid)
        self.assertEqual(self.live(), previous)
        self.run.assert_not_called()

    def test_正式发布基于线上内容更新GitHub渠道(self):
        manifest = {'version': '2.0.3', 'build': '2030'}
        directory = deploy.ROOT / 'downloads/releases/v2.0.3/2030'
        directory.mkdir(parents=True)
        deploy.atomic_json(directory / 'release.json', manifest)
        deploy.atomic_json(directory / 'distribution.json', {'complete': True})
        (deploy.ROOT / 'app_service/current').mkdir(parents=True)
        deploy.atomic_json(deploy.ROOT / 'app_service/current/content.json', self.content())
        live = self.content(app_store={'latest_version': '2.0.2'}, announcements=[{'id': 'c'}])
        deploy.atomic_json(deploy.STATE / 'content.json', live)
        with patch.object(deploy.urllib.request, 'urlopen',
                          return_value=io.BytesIO(json.dumps(manifest).encode())):
            deploy.publish('v2.0.3')
        result = self.live()
        self.assertEqual(result['channels']['github']['latest_version'], '2.0.3+2030')
        self.assertEqual(result['channels']['app_store'], live['channels']['app_store'])
        self.assertEqual(result['announcements'], live['announcements'])


if __name__ == '__main__':
    unittest.main()
