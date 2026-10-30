"""真实临时 Git 仓库中的候选关联、产物摘要和路径独立性。"""
import importlib.util
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("build_record", ROOT / "scripts/release/build_record.py")
manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest)


class BuildRecordTest(unittest.TestCase):
    def test_系统默认cp1252时中文输入和材料仍固定UTF8(self):
        path = self.root / "中文输入.rs"
        path.write_bytes(b"synthetic input")
        self.git("add", "中文输入.rs")
        original = Path.open

        def legacy_open(path, mode="r", buffering=-1, encoding=None, errors=None, newline=None):
            if "b" not in mode and encoding in (None, "locale"):
                encoding = "cp1252"
            return original(path, mode, buffering, encoding, errors, newline)

        artifact = self.root / "artifact.bin"
        artifact.write_bytes(b"synthetic artifact")
        output = self.root / "utf8-report"
        with patch.object(Path, "open", legacy_open):
            manifest.write_report(self.root, output, artifact, "windows")
        self.assertFalse((output / "source-manifest.sha256").exists())
        record = json.loads((output / "build-record.json").read_text(encoding="utf-8"))
        self.assertEqual(record["artifact"]["manifest_sha256"],
                         hashlib.sha256((output / "artifact-files.json").read_bytes()).hexdigest())
        self.assertNotIn(b"\r\n", (output / "artifact-files.json").read_bytes())

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        for name in ["crates/ubaa_core/src/lib.rs", "Cargo.lock", "Cargo.toml", "pubspec.lock",
                     "rust-toolchain.toml", "scripts/build/flutter.sh", "packages/app/lib/main.dart"]:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("合成构建输入\n", encoding="utf-8")
        self.git("add", ".")
        self.git("-c", "user.name=测试", "-c", "user.email=fixture@example.invalid",
                 "commit", "-qm", "合成候选")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True).strip()

    def test_产物摘要不依赖绝对路径且关联候选(self):
        records = []
        for name in ["bundle-a", "bundle-b"]:
            artifact = self.root / name
            artifact.mkdir()
            (artifact / "app").write_bytes(b"synthetic binary")
            output = self.root / (name + "-report")
            manifest.write_report(self.root, output, artifact, "linux")
            record = json.loads((output / "build-record.json").read_text(encoding="utf-8"))
            self.assertEqual(record["source_commit"], self.git("rev-parse", "HEAD"))
            self.assertNotIn(str(self.root), json.dumps(record))
            records.append(record)
        self.assertEqual(records[0]["artifact"], records[1]["artifact"])


if __name__ == "__main__":
    unittest.main()
