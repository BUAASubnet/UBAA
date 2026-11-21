"""用假 SDK 验证已锁定 Flutter 工具链的实际入口。"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
CHECKER = ROOT / 'scripts/check/flutter-toolchains.sh'
VERSIONS = dict(line.split('=', 1) for line in (ROOT / 'scripts/tools/versions.env').read_text().splitlines()
                if line.startswith(('FLUTTER_', 'OHOS_FLUTTER_')))


class FlutterToolchainsTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        (self.root / 'bin').mkdir()
        self.executable('git', r'''#!/bin/bash
[[ "$#" == 4 && "$1" == -C && "$2" == "$FAKE_SDK" && "$3 $4" == 'rev-parse HEAD' ]] || exit 97
printf '%s\n' "$FAKE_COMMIT"
''')
        self.executable('bin/flutter', r'''#!/bin/bash
set -eu
[[ "$*" == --version ]] || exit 98
printf '%s\n' 'bootstrap 诊断写入 stderr' >&2
if [[ "$FAKE_OUTPUT" == cold ]]; then
  printf '\n%s\n%s\r\n\n' 'Downloading Dart SDK' '下载诊断中的 Flutter 0.0.0'
fi
printf '%s\n' "$FAKE_BANNER"
case "$FAKE_OUTPUT" in
  fail) exit 73 ;;
  long) printf -v chunk '%4096s' x; for ((index=0; index<1024; index++)); do printf '%s\n' "$chunk"; done ;;
  later) printf 'Flutter %s\n' "$FAKE_EXPECTED_VERSION" ;;
esac
printf '后续诊断包含 Flutter %s\n' "$FAKE_EXPECTED_VERSION"
touch "$FAKE_SDK/complete"
''')

    def executable(self, relative, text):
        target = self.root / relative
        target.write_text(text)
        target.chmod(0o700)

    def run_checker(self, mode='official', *, banner=None, commit=None, output='', configured=True):
        prefix = 'OHOS_FLUTTER' if mode == 'ohos' else 'FLUTTER'
        version = VERSIONS[f'{prefix}_VERSION']
        locked = VERSIONS[f'{prefix}_COMMIT']
        sdk = str(self.root) if configured else ''
        (self.root / 'complete').unlink(missing_ok=True)
        return subprocess.run(['bash', str(CHECKER), mode], cwd=ROOT, text=True, capture_output=True,
                              env={'PATH': f'{self.root}{os.pathsep}{os.environ["PATH"]}',
                                   'UBAA_FLUTTER_HOME': sdk, 'UBAA_OHOS_FLUTTER_HOME': sdk,
                                   'FAKE_SDK': str(self.root), 'FAKE_COMMIT': commit or locked,
                                   'FAKE_EXPECTED_VERSION': version, 'FAKE_OUTPUT': output,
                                   'FAKE_BANNER': f'Flutter {version}' if banner is None else banner})

    def test_missing_sdk_reports_each_configuration_key(self):
        for mode, key in (('official', 'UBAA_FLUTTER_HOME'), ('ohos', 'UBAA_OHOS_FLUTTER_HOME')):
            with self.subTest(mode=mode):
                result = self.run_checker(mode, configured=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(key, result.stderr)

    def test_full_output_and_bootstrap_progress(self):
        for mode, output in (('official', 'long'), ('ohos', 'long'), ('official', 'cold')):
            with self.subTest(mode=mode, output=output):
                result = self.run_checker(mode, output=output)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue((self.root / 'complete').is_file())
                self.assertIn('bootstrap 诊断写入 stderr', result.stderr)
                self.assertEqual(len(result.stdout.splitlines()), 1, result.stdout[:200])
                self.assertIn('已锁定', result.stdout)

    def test_first_version_line_must_match_exactly(self):
        for banner, output in (('Flutter 0.0.0', 'later'), ('', ''),
                               (f'Flutter {VERSIONS["FLUTTER_VERSION"]}0', '')):
            with self.subTest(banner=banner, output=output):
                result = self.run_checker(banner=banner, output=output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('版本不匹配', result.stderr)

    def test_wrong_commit_never_starts_flutter(self):
        result = self.run_checker(commit='0' * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('commit 不匹配', result.stderr)
        self.assertNotIn('bootstrap 诊断', result.stderr)

    def test_sdk_failure_propagates_after_a_valid_banner(self):
        self.assertEqual(self.run_checker(output='fail').returncode, 73)
