"""真实临时 Git 仓库中的输入变更、产物关联和路径独立性。"""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("source_manifest", ROOT / "scripts/release/source_manifest.py")
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)


class SourceManifestTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        for name in ["crates/ubaa-core/src/lib.rs", "Cargo.lock", "Cargo.toml",
                     "rust-toolchain.toml", "scripts/build/flutter.sh", "packages/app/lib/main.dart"]:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("合成构建输入\n")
        self.git("add", ".")
        self.git("-c", "user.name=测试", "-c", "user.email=fixture@example.invalid",
                 "commit", "-qm", "合成候选")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True).strip()

    def test_Core锁文件及脚本变化均改变输入摘要(self):
        for name in ["crates/ubaa-core/src/lib.rs", "Cargo.lock", "scripts/build/flutter.sh"]:
            with self.subTest(name=name):
                before = manifest.source_lines(self.root)
                path = self.root / name
                path.write_text(path.read_text() + "变更\n")
                self.assertNotEqual(before, manifest.source_lines(self.root))

    def test_未跟踪凭据不进入清单而工具链进入(self):
        (self.root / ".env.local").write_text("合成私密输入")
        lines = manifest.source_lines(self.root)
        self.assertNotIn(".env.local", lines)
        self.assertIn("rust-toolchain.toml", lines)

    def test_产物摘要不依赖绝对路径且关联候选(self):
        records = []
        for name in ["bundle-a", "bundle-b"]:
            artifact = self.root / name
            artifact.mkdir()
            (artifact / "app").write_bytes(b"synthetic binary")
            output = self.root / (name + "-report")
            manifest.write_report(self.root, output, artifact, "linux")
            record = json.loads((output / "build-record.json").read_text())
            self.assertEqual(record["source_commit"], self.git("rev-parse", "HEAD"))
            self.assertNotIn(str(self.root), json.dumps(record))
            records.append(record)
        self.assertEqual(records[0]["artifact"], records[1]["artifact"])


if __name__ == "__main__":
    unittest.main()
