#!/usr/bin/env python3
"""验证 Pub workspace 清单的 YAML 解析边界。"""

import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("repo", ROOT / "scripts/lib/repo.py")
repo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repo)


class RepoTest(unittest.TestCase):
    def test_workspace成员支持行尾和列表中的注释(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pubspec.yaml").write_text(
                "workspace:\n"
                "# 顶格注释不能截断列表\n"
                "  - packages/extra # 行尾注释\n"
            )
            child = root / "packages/extra"
            child.mkdir(parents=True)
            (child / "pubspec.yaml").write_text("name: extra\n")
            previous = repo.ROOT
            previous_official = repo.official_packages
            repo.ROOT = root
            repo.official_packages = lambda: {}
            try:
                self.assertEqual(repo.workspace_packages(), {"extra": "packages/extra"})
            finally:
                repo.ROOT = previous
                repo.official_packages = previous_official

    def test_workspace声明与包名支持行尾注释(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pubspec.yaml").write_text(
                "workspace: # 公共工作区\n  - 'packages/extra' # 测试辅助包\n"
            )
            child = root / "packages/extra"
            child.mkdir(parents=True)
            (child / "pubspec.yaml").write_text("name: extra # 包名\n")
            previous = repo.ROOT
            previous_official = repo.official_packages
            repo.ROOT = root
            repo.official_packages = lambda: {}
            try:
                self.assertEqual(repo.workspace_packages(), {"extra": "packages/extra"})
            finally:
                repo.ROOT = previous
                repo.official_packages = previous_official

    def test_workspace不能静默截断未缩进的合法列表(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "pubspec.yaml"
            manifest.write_text("workspace:\n- packages/one\n- packages/two\nname: root\n")
            self.assertEqual(repo.workspace_members(manifest), ["packages/one", "packages/two"])

    def test_workspace成员拒绝越界路径(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pubspec.yaml").write_text("workspace:\n  - ../outside\n")
            previous = repo.ROOT
            previous_official = repo.official_packages
            repo.ROOT = root
            repo.official_packages = lambda: {}
            try:
                with self.assertRaises(ValueError):
                    repo.workspace_packages()
            finally:
                repo.ROOT = previous
                repo.official_packages = previous_official


if __name__ == "__main__":
    unittest.main()
