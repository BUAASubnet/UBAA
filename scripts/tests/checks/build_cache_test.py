#!/usr/bin/env python3
"""验证构建缓存的增长控制与分范围清理入口，不编译 Rust 或 Flutter。"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[3]
CACHE = ROOT / 'scripts/build/cache.py'
# 一次性门禁不复用增量缓存，留着只会按 feature 组合堆积。
GATES = {'test', 'core-test-contract', 'check', 'check-strict', 'check-changed',
         'flutter-codegen-check', 'flutter-check', 'integration-test', 'ohos-check'}


class GateCacheTest(unittest.TestCase):
    def test_门禁入口关闭增量编译(self):
        dump = json.loads(subprocess.check_output(
            ['just', '--justfile', str(ROOT / 'justfile'), '--dump', '--dump-format', 'json'], text=True))
        for name in sorted(GATES):
            with self.subTest(recipe=name):
                attributes = dump['recipes'][name]['attributes']
                self.assertIn({'env': ['CARGO_INCREMENTAL', '0']}, attributes)

    def test_开发构建只保留行号调试信息(self):
        profile = tomllib.loads((ROOT / 'Cargo.toml').read_text()).get('profile', {})
        self.assertEqual(profile.get('dev', {}).get('debug'), 'line-tables-only')


class CacheCommandTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / 'repo'
        self.root.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.write('.gitignore', '/target/\n/apps/ubaa_flutter/build/\n/packages/*/ohos/.cxx\n')

    def write(self, name, data='x' * 4096):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def run_cache(self, *args):
        return subprocess.run(['python3', str(CACHE), '--root', str(self.root), *args],
                              text=True, capture_output=True)

    def test_默认只显示占用(self):
        self.write('target/debug/incremental/a/s-1/dep-graph.bin')
        self.write('packages/ubaa_bindings/ohos/.cxx/default/lib.so')
        result = self.run_cache()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('rust-incremental', result.stdout)
        self.assertIn('ohos', result.stdout)
        self.assertTrue((self.root / 'target/debug/incremental').exists())
        self.assertTrue((self.root / 'packages/ubaa_bindings/ohos/.cxx').exists())

    def test_只清理指定范围(self):
        self.write('target/debug/.fingerprint/a/hash')
        self.write('target/debug/incremental/a/s-1/dep-graph.bin')
        cargokit = 'apps/ubaa_flutter/build/macos/Pods.build/aarch64-apple-darwin/debug'
        self.write(cargokit + '/.fingerprint/a/hash')
        self.write(cargokit + '/incremental/a/s-1/dep-graph.bin')
        gradle = self.write('apps/ubaa_flutter/build/app/intermediates/incremental/merge/state.xml')
        kept = self.write('target/debug/deps/libubaa_core.rlib')
        result = self.run_cache('clean', 'rust-incremental')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'target/debug/incremental').exists())
        self.assertFalse((self.root / cargokit / 'incremental').exists())
        self.assertTrue(kept.exists())
        self.assertTrue(gradle.exists())

    def test_受跟踪文件所在目录拒绝删除且不做任何清理(self):
        self.write('.gitignore', '/apps/ubaa_flutter/build/\n')
        self.write('target/debug/keep.rs', 'tracked')
        subprocess.run(['git', '-C', str(self.root), 'add', '-f', 'target/debug/keep.rs'], check=True)
        self.write('apps/ubaa_flutter/build/macos/lib.a')
        result = self.run_cache('clean', 'flutter-macos', 'rust')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('target', result.stderr)
        self.assertTrue((self.root / 'target/debug/keep.rs').exists())
        self.assertTrue((self.root / 'apps/ubaa_flutter/build/macos/lib.a').exists())

    def test_符号链接不跟随也不删除目标(self):
        outside = Path(self.directory.name) / 'outside'
        outside.mkdir()
        (outside / 'precious').write_text('keep')
        (self.root / 'apps/ubaa_flutter/build').mkdir(parents=True)
        os.symlink(outside, self.root / 'apps/ubaa_flutter/build/macos')
        result = self.run_cache('clean', 'flutter-macos')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((outside / 'precious').exists())

    def test_未知范围和空范围失败(self):
        self.assertNotEqual(self.run_cache('clean', 'everything').returncode, 0)
        self.assertNotEqual(self.run_cache('clean').returncode, 0)


if __name__ == '__main__':
    unittest.main()
