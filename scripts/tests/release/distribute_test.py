"""分发产物后保留 Release 草稿，已发布版本不得覆盖。"""
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
        self.calls = self.enterContext(patch.object(distribute.subprocess, 'run', side_effect=self.command))
        self.enterContext(patch.object(distribute.urllib.request, 'urlopen', side_effect=self.download))

    def command(self, args, **kwargs):
        if args[:3] == ['gh', 'release', 'view']:
            return subprocess.CompletedProcess(args, 1 if self.release is None else 0,
                                               json.dumps(self.release), '')
        if args[:3] == ['gh', 'release', 'create']:
            if self.release is not None:
                raise subprocess.CalledProcessError(1, args)
            self.release = {'isDraft': '--draft' in args}
        if args[:3] == ['gh', 'release', 'edit'] and '--draft=false' in args:
            self.release['isDraft'] = False
        if args[:3] == ['gh', 'release', 'upload']:
            self.uploaded = [Path(value).name for value in args[4:] if not value.startswith('--')]
        return subprocess.CompletedProcess(args, 0)

    def download(self, request, **kwargs):
        data = (self.folder / Path(urlparse(request.full_url).path).name).read_bytes()
        response = io.BytesIO(data)
        response.headers = {'Content-Length': str(len(data))}
        return response

    def test_新建与重跑均保留完整草稿(self):
        for initial in (None, {'isDraft': True}):
            with self.subTest(initial=initial):
                self.release = initial
                distribute.main()
                self.assertEqual(self.release, {'isDraft': True})
                self.assertCountEqual(self.uploaded, [path.name for path in self.folder.iterdir()])
                manifest = json.loads((self.folder / 'release.json').read_text())
                self.assertEqual(manifest['commit'], 'candidate')
                self.assertEqual(len(manifest['assets']), 10)

    def test_已发布版本在任何远端写入前拒绝(self):
        self.release = {'isDraft': False}
        with self.assertRaisesRegex(ValueError, '已发布'):
            distribute.main()
        self.assertEqual(self.release, {'isDraft': False})
        self.assertEqual([call.args[0][:3] for call in self.calls.call_args_list], [['gh', 'release', 'view']])

    def test_平台产物不完整时不生成草稿(self):
        (self.folder / 'UBAA-2.0.0-windows-x64.exe').unlink()
        with self.assertRaisesRegex(ValueError, '产物不完整'):
            distribute.main()
        self.calls.assert_not_called()

    def test_查询失败且已有版本时不覆盖R2(self):
        self.release = {'isDraft': False}
        def failed_view(args, **kwargs):
            if args[:3] == ['gh', 'release', 'view']:
                return subprocess.CompletedProcess(args, 1, '', 'synthetic failure')
            return self.command(args, **kwargs)
        self.calls.side_effect = failed_view
        with self.assertRaises(subprocess.CalledProcessError):
            distribute.main()
        self.assertFalse(any(call.args[0][0] == 'aws' for call in self.calls.call_args_list))


if __name__ == '__main__':
    unittest.main()
