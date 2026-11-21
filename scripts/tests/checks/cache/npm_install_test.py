#!/usr/bin/env python3
"""检查锁文件未变化时复用 npm 安装，并在 CI 重新安装。"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
INSTALLER = ROOT / 'scripts/check/app_service/npm-install.sh'


class NpmInstallTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.package = self.root / 'package with spaces'
        self.package.mkdir()
        (self.package / 'package-lock.json').write_text('{}')
        bin_path = self.root / 'bin'
        bin_path.mkdir()
        self.log = self.root / 'npm.log'
        self.npm = bin_path / 'npm'
        self.npm.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$NPM_LOG"\n')
        self.npm.chmod(0o755)
        self.environment = {'PATH': f'{bin_path}{os.pathsep}{os.environ.get("PATH", "")}',
                            'NPM_LOG': str(self.log)}

    def install(self, *, ci=False):
        environment = dict(self.environment)
        if ci:
            environment['CI'] = ''
        return subprocess.run(['bash', str(INSTALLER), str(self.package)], cwd=self.root,
                              env=environment, text=True, capture_output=True)

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_lock_marker_skips_unchanged_install_and_refreshes_after_lock_change(self):
        self.assertEqual(self.install().returncode, 0)
        self.assertTrue((self.package / 'node_modules/.ubaa-npm-ci').is_file())
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        lock_file = self.package / 'package-lock.json'
        marker = self.package / 'node_modules/.ubaa-npm-ci'
        os.utime(lock_file, ns=(marker.stat().st_mtime_ns + 2_000_000_000,) * 2)
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(len(self.calls()), 2)

    def test_ci_always_runs_npm_ci_even_when_marker_is_current(self):
        self.assertEqual(self.install().returncode, 0)
        self.assertEqual(self.install(ci=True).returncode, 0)
        self.assertEqual(len(self.calls()), 2)

    def test_failed_install_does_not_mark_dependencies_current(self):
        self.npm.write_text('#!/bin/sh\nexit 9\n')
        self.assertEqual(self.install().returncode, 9)
        self.assertFalse((self.package / 'node_modules/.ubaa-npm-ci').exists())


if __name__ == '__main__':
    unittest.main()
