"""分发产物后保留 Release 草稿，已发布版本和已分发的构建号不得覆盖。"""
from contextlib import chdir
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('distribute', ROOT / 'scripts/release/distribute.py')
distribute = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribute)


def option(args, name):
    return args[args.index(name) + 1]


class DistributionTest(unittest.TestCase):
    def setUp(self):
        parent = ROOT / '.ubaa_local/release_draft/tests'
        parent.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=parent)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.enterContext(chdir(self.root))
        self.folder = Path('.ubaa_local/release/public')
        self.folder.mkdir(parents=True)
        for suffix in ('android-arm64-v8a.apk', 'android-armeabi-v7a.apk', 'android-x86_64.apk',
                       'windows-x64.exe', 'linux-x64.tar.gz', 'linux-arm64.tar.gz',
                       'macos-arm64.dmg', 'macos-x86_64.dmg'):
            (self.folder / f'UBAA-2.0.0-{suffix}').write_bytes(b'synthetic artifact')
        (self.folder / 'licenses.zip').write_bytes(b'synthetic licenses')
        self.enterContext(patch.dict(os.environ, {
            'RELEASE_VERSION': '2.0.0', 'RELEASE_TAG': 'v2.0.0', 'RELEASE_SHA': 'candidate',
            'RELEASE_BUILD': '2003', 'CLOUDFLARE_ACCOUNT_ID': 'synthetic',
            'R2_BUCKET': 'synthetic', 'R2_PUBLIC_URL': 'https://example.invalid',
        }))
        self.release = None
        self.uploaded = []
        self.r2 = {}
        self.calls = self.enterContext(patch.object(distribute.subprocess, 'run', side_effect=self.command))
        self.enterContext(patch.object(distribute.urllib.request, 'urlopen', side_effect=self.download))

    def command(self, args, **kwargs):
        if args[:3] == ['gh', 'release', 'view']:
            if self.release is None:
                return subprocess.CompletedProcess(args, 1, '', 'release not found\n')
            return subprocess.CompletedProcess(args, 0, json.dumps(self.release), '')
        if args[:3] == ['gh', 'release', 'create']:
            if self.release is not None:
                raise subprocess.CalledProcessError(1, args)
            self.release = {'isDraft': '--draft' in args, 'targetCommitish': option(args, '--target')}
        if args[:3] == ['gh', 'release', 'edit']:
            if '--draft=false' in args:
                self.release['isDraft'] = False
            if '--target' in args:
                self.release['targetCommitish'] = option(args, '--target')
        if args[:3] == ['gh', 'release', 'upload']:
            self.uploaded = [Path(value).name for value in args[4:] if not value.startswith('--')]
        if args[:3] == ['aws', 's3api', 'head-object']:
            key = option(args, '--key')
            if key not in self.r2:
                return subprocess.CompletedProcess(
                    args, 254, '', 'An error occurred (404) when calling the HeadObject operation: Not Found\n')
            return subprocess.CompletedProcess(args, 0, json.dumps({'Metadata': self.r2[key]}), '')
        if args[:3] == ['aws', 's3', 'cp']:
            key = urlparse(args[4]).path.lstrip('/')
            metadata = dict(item.split('=', 1) for item in option(args, '--metadata').split(',')) \
                if '--metadata' in args else {}
            self.r2[key] = metadata
        return subprocess.CompletedProcess(args, 0)

    def download(self, request, **kwargs):
        data = (self.folder / Path(urlparse(request.full_url).path).name).read_bytes()
        response = io.BytesIO(data)
        response.headers = {'Content-Length': str(len(data))}
        return response

    def commands(self, *prefix):
        return [call.args[0] for call in self.calls.call_args_list if call.args[0][:len(prefix)] == list(prefix)]

    def test_新建与重跑均保留完整草稿(self):
        for initial in (None, {'isDraft': True, 'targetCommitish': 'candidate'}):
            with self.subTest(initial=initial):
                self.release = initial
                distribute.main()
                self.assertEqual(self.release, {'isDraft': True, 'targetCommitish': 'candidate'})
                self.assertCountEqual(self.uploaded, [path.name for path in self.folder.iterdir()])
                manifest = json.loads((self.folder / 'release.json').read_text())
                self.assertEqual(manifest['commit'], 'candidate')
                self.assertEqual(len(manifest['assets']), 9)

    def test_公开清单记录每个文件的SHA256供下载页校验(self):
        distribute.main()
        manifest = json.loads((self.folder / 'release.json').read_text())
        for asset in manifest['assets']:
            with self.subTest(asset=asset['name']):
                expected = hashlib.sha256((self.folder / asset['name']).read_bytes()).hexdigest()
                self.assertEqual(asset['sha256'], expected)
                self.assertTrue(asset['url'].startswith('https://download.ubaa.top:10443/releases/v2.0.0/2003/'))

    def test_旧产物中的HarmonyOS商店包不进入公开分发(self):
        store = self.folder / 'UBAA-2.0.0-harmonyos-arm64.app'
        store.write_bytes(b'synthetic store package')
        distribute.main()
        self.assertNotIn(store.name, self.uploaded)
        manifest = json.loads((self.folder / 'release.json').read_text())
        self.assertNotIn(store.name, [asset['name'] for asset in manifest['assets']])
        self.assertFalse(any(key.endswith('.app') for key in self.r2))

    def test_草稿目标与候选不同时先改目标再写入产物(self):
        self.release = {'isDraft': True, 'targetCommitish': 'previous'}
        distribute.main()
        self.assertEqual(self.release['targetCommitish'], 'candidate')
        order = [call.args[0][:3] for call in self.calls.call_args_list]
        self.assertLess(order.index(['gh', 'release', 'edit']), order.index(['gh', 'release', 'upload']))

    def test_已发布版本在任何远端写入前拒绝(self):
        self.release = {'isDraft': False, 'targetCommitish': 'candidate'}
        with self.assertRaisesRegex(ValueError, '已发布'):
            distribute.main()
        self.assertEqual(self.release, {'isDraft': False, 'targetCommitish': 'candidate'})
        self.assertEqual([call.args[0][:3] for call in self.calls.call_args_list], [['gh', 'release', 'view']])

    def test_平台产物不完整时不生成草稿(self):
        (self.folder / 'UBAA-2.0.0-windows-x64.exe').unlink()
        with self.assertRaisesRegex(ValueError, '产物不完整'):
            distribute.main()
        self.calls.assert_not_called()

    def test_许可证缺失时不生成草稿(self):
        (self.folder / 'licenses.zip').unlink()
        with self.assertRaisesRegex(ValueError, '产物不完整'):
            distribute.main()
        self.calls.assert_not_called()

    def test_查询失败时不创建草稿也不写入R2(self):
        def failed_view(args, **kwargs):
            if args[:3] == ['gh', 'release', 'view']:
                return subprocess.CompletedProcess(args, 1, '', 'HTTP 502: Bad Gateway\n')
            return self.command(args, **kwargs)
        self.calls.side_effect = failed_view
        with self.assertRaisesRegex(RuntimeError, 'GitHub Release'):
            distribute.main()
        self.assertEqual([call.args[0][:3] for call in self.calls.call_args_list], [['gh', 'release', 'view']])

    def test_清单地址按构建号隔离(self):
        distribute.main()
        manifest = json.loads((self.folder / 'release.json').read_text())
        self.assertTrue(all('/releases/v2.0.0/2003/' in asset['url'] for asset in manifest['assets']))
        self.assertEqual(self.commands('aws'), [])


class SourceMetadataTest(unittest.TestCase):
    def setUp(self):
        self.run = {'path': '.github/workflows/release.yml', 'head_branch': 'main',
                    'event': 'workflow_dispatch', 'head_sha': 'original-candidate'}
        self.jobs = [{'jobs': [{'name': 'ready', 'conclusion': 'success'}]}]
        self.enterContext(patch.dict(os.environ, {'GH_REPO': 'synthetic/repository'}))
        self.commands = self.enterContext(patch.object(distribute.subprocess, 'run'))
        self.query = self.enterContext(patch.object(distribute.subprocess, 'check_output',
                                                   side_effect=self.read))

    def read(self, args, **kwargs):
        if args[:2] == ['git', 'show']:
            self.assertEqual(args[2], 'original-candidate:version.toml')
            return 'version = "2.0.0"\nbuild_number = 2004\n'
        return json.dumps(self.jobs if '--paginate' in args else self.run)

    def test_重分发保留原始提交和版本(self):
        self.assertEqual(distribute.source_metadata('123'),
                         {'version': '2.0.0', 'build': 2004, 'tag': 'v2.0.0', 'sha': 'original-candidate'})
        self.commands.assert_called_once_with(
            ['git', 'merge-base', '--is-ancestor', 'original-candidate', 'origin/main'], check=True)

    def test_拒绝其他工作流和分支的产物(self):
        for key, value in [('path', '.github/workflows/ci.yml'), ('head_branch', 'dev'),
                           ('event', 'pull_request')]:
            with self.subTest(key=key), patch.dict(self.run, {key: value}):
                with self.assertRaisesRegex(ValueError, 'main 手动 Release'):
                    distribute.source_metadata('123')
        self.commands.assert_not_called()

    def test_发布验收失败或缺失时拒绝(self):
        for result in ['failure', 'cancelled', 'skipped', None]:
            self.jobs[0]['jobs'][0]['conclusion'] = result
            with self.assertRaisesRegex(ValueError, '尚未通过发布验收'):
                distribute.source_metadata('123')
        self.jobs[0]['jobs'] = []
        with self.assertRaisesRegex(ValueError, '尚未通过发布验收'):
            distribute.source_metadata('123')
        self.commands.assert_not_called()


if __name__ == '__main__':
    unittest.main()
