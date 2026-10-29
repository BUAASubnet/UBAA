"""敏感扫描必须覆盖待提交 blob，并明确拒绝未能读取的候选。"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MARKER = "UBAA_TEST_" + "USERNAME=synthetic-check-only"


class SensitiveTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts/check").mkdir(parents=True)
        (self.root / "scripts/lib").mkdir()
        for name in ["scripts/check/sensitive.sh", "scripts/lib/repo.sh"]:
            shutil.copyfile(ROOT / name, self.root / name)
        checker = ROOT / "scripts/check/sensitive.py"
        if checker.exists():
            shutil.copyfile(checker, self.root / "scripts/check/sensitive.py")
        self.git("init", "-q")

    def git(self, *arguments):
        return subprocess.run(["git", "-C", str(self.root), *arguments],
                              check=True, capture_output=True)

    def scan(self):
        return subprocess.run(["bash", str(self.root / "scripts/check/sensitive.sh")],
                              capture_output=True, text=True)

    def test_暂存敏感正文不能被工作区清理遮盖(self):
        sample = self.root / "sample.txt"
        sample.write_text(MARKER)
        self.git("add", "sample.txt")
        sample.write_text("已清理的工作区版本")
        result = self.scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(MARKER, result.stdout + result.stderr)

    def test_未暂存新文件也必须检查且不输出正文(self):
        (self.root / "new.txt").write_text(MARKER)
        result = self.scan()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(MARKER, result.stdout + result.stderr)

    def test_断开的符号链接必须失败关闭(self):
        (self.root / "unreadable.txt").symlink_to(self.root / "absent")
        result = self.scan()
        self.assertNotEqual(result.returncode, 0)

    def test_暂存后删除工作区仍检查原blob(self):
        sample = self.root / "deleted.txt"
        sample.write_text(MARKER)
        self.git("add", "deleted.txt")
        sample.unlink()
        self.assertNotEqual(self.scan().returncode, 0)

    def test_安全文件及忽略的本地凭据不被读取(self):
        (self.root / ".gitignore").write_text(".env.local\n")
        (self.root / ".env.local").write_text(MARKER)
        (self.root / "safe.txt").write_text("普通源码")
        self.assertEqual(self.scan().returncode, 0)

    def test_家目录路径在工作区与暂存区均拒绝且不输出正文(self):
        for prefix in ("/" + "Users/", "/" + "home/", "C:" + "\\Users\\"):
            for user in ("synthetic-person", "<private-evidence>", "<username>", "private"):
                marker = prefix + user + ("\\" if "\\" in prefix else "/") + "report.txt"
                with self.subTest(prefix=prefix, user=user):
                    sample = self.root / "personal.txt"
                    sample.write_text(marker)
                    result = self.scan()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn(marker, result.stdout + result.stderr)
                    self.git("add", "personal.txt")
                    sample.write_text("工作区已清理")
                    self.assertNotEqual(self.scan().returncode, 0)
                    self.git("rm", "-f", "--cached", "personal.txt")
                    sample.unlink()

    def test_逻辑占位和业务home路径允许(self):
        (self.root / "safe.txt").write_text(
            "<private-evidence>/run/log.txt\n<repo-root>/apps\n"
            "https://example.invalid/api/home/student/data\n../features/home/reader.dart\n")
        self.assertEqual(self.scan().returncode, 0)

    def test_Git读取失败明确退出且不打印工具正文(self):
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        fake_git = fake_bin / "git"
        fake_git.write_text("#!/bin/sh\nprintf '不应转发的底层错误正文' >&2\nexit 2\n")
        fake_git.chmod(0o755)
        environment = dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ['PATH'])
        result = subprocess.run(["bash", str(self.root / "scripts/check/sensitive.sh")],
                                capture_output=True, text=True, env=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Git 读取失败", result.stderr)
        self.assertNotIn("不应转发的底层错误正文", result.stderr)


if __name__ == "__main__":
    unittest.main()
