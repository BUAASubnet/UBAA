"""分发产物后保留 Release 草稿，已发布版本和已分发的构建号不得覆盖。"""
from contextlib import chdir
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
                       'macos-arm64.dmg', 'macos-x86_64.dmg', 'harmonyos-arm64.app'):
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
                self.assertEqual(len(manifest['assets']), 10)

    def test_草稿目标与候选不同时先改目标再写入产物(self):
        self.release = {'isDraft': True, 'targetCommitish': 'previous'}
        distribute.main()
        self.assertEqual(self.release['targetCommitish'], 'candidate')
        order = [call.args[0][:3] for call in self.calls.call_args_list]
        self.assertLess(order.index(['gh', 'release', 'edit']), order.index(['aws', 's3', 'cp']))

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

    def test_查询失败时不创建草稿也不写入R2(self):
        def failed_view(args, **kwargs):
            if args[:3] == ['gh', 'release', 'view']:
                return subprocess.CompletedProcess(args, 1, '', 'HTTP 502: Bad Gateway\n')
            return self.command(args, **kwargs)
        self.calls.side_effect = failed_view
        with self.assertRaisesRegex(RuntimeError, 'GitHub Release'):
            distribute.main()
        self.assertEqual([call.args[0][:3] for call in self.calls.call_args_list], [['gh', 'release', 'view']])

    def test_R2按构建号隔离且相同内容重跑不重复上传(self):
        distribute.main()
        manifest = json.loads((self.folder / 'release.json').read_text())
        self.assertTrue(all('/releases/v2.0.0/2003/' in asset['url'] for asset in manifest['assets']))
        self.assertIn('releases/v2.0.0/2003/release.json', self.r2)
        self.calls.reset_mock()
        distribute.main()
        self.assertEqual([args[3] for args in self.commands('aws', 's3', 'cp')],
                         ['.ubaa_local/release/public/release.json'])

    def test_同一构建号已分发其他内容时拒绝覆盖R2(self):
        distribute.main()
        (self.folder / 'UBAA-2.0.0-windows-x64.exe').write_bytes(b'rebuilt artifact')
        self.calls.reset_mock()
        with self.assertRaisesRegex(ValueError, '构建号'):
            distribute.main()
        self.assertFalse(any(args[4].endswith('windows-x64.exe') for args in self.commands('aws', 's3', 'cp')))
        self.assertEqual(self.commands('gh', 'release', 'upload'), [])

    def test_R2状态查询失败时不上传(self):
        def failed_head(args, **kwargs):
            if args[:3] == ['aws', 's3api', 'head-object']:
                return subprocess.CompletedProcess(args, 255, '', 'Could not connect to the endpoint URL\n')
            return self.command(args, **kwargs)
        self.calls.side_effect = failed_head
        with self.assertRaisesRegex(RuntimeError, 'R2'):
            distribute.main()
        self.assertEqual(self.commands('aws', 's3', 'cp'), [])


if __name__ == '__main__':
    unittest.main()
