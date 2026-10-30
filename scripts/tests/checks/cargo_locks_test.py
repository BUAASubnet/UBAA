#!/usr/bin/env python3
"""验证轻量 Cargo 锁文件门禁，无需编译 CLI。"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
CHECKER = ROOT / 'scripts/lib/cargo_locks.py'


class CargoLocksTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.write('justfile', 'check:\n    cargo metadata --locked --no-deps --format-version 1\n')

    def write(self, name, source):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)

    def check(self):
        return subprocess.run(['python3', str(CHECKER), '--root', str(self.root)],
                              text=True, capture_output=True)

    def test_文档脚本和工作流中的未锁定命令均失败(self):
        for name in ['AGENTS.md', 'docs/development/commands.md',
                     'scripts/check/nested.sh', '.github/workflows/ci.yml']:
            with self.subTest(name=name):
                self.write(name, 'cargo test --workspace\n')
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name + ':1:', result.stderr)
                (self.root / name).unlink()

    def test_锁定命令和无需解析依赖的格式检查通过(self):
        self.write('docs/commands.md', 'cargo test --locked --workspace\ncargo fmt --all -- --check\n')
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_删除文件与含空格路径正确处理(self):
        self.write('docs/deleted.md', 'cargo test --workspace\n')
        subprocess.run(['git', '-C', str(self.root), 'add', '--', 'docs/deleted.md'], check=True)
        (self.root / 'docs/deleted.md').unlink()
        self.write('docs/path with spaces.md', 'cargo test --locked\n')
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_缺少元数据锁定检查时失败(self):
        self.write('justfile', 'check:\n    cargo test --locked --workspace\n')
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('metadata', result.stderr)

    def test_无效文本读取失败不静默跳过(self):
        (self.root / 'README.md').write_bytes(b'\xff')
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('README.md', result.stderr)


if __name__ == '__main__':
    unittest.main()
