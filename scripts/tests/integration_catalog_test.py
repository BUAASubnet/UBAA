"""集成清单必须完整，批量回归不能意外选择真实账号入口。"""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "check" / "integration_catalog.py"
spec = importlib.util.spec_from_file_location("catalog", SCRIPT)
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class CatalogTest(unittest.TestCase):
    def test_执行预览也要求显式SDK路径(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(catalog, "ROOT", Path(directory)), patch.dict(catalog.os.environ, {}, clear=True), patch.object(
            catalog.sys, "argv", [str(SCRIPT), "run", "--dry-run"]
        ):
            self.assertRaisesRegex(ValueError, "UBAA_FLUTTER_HOME", catalog.main)

    def entry(self, **overrides):
        return dict(path="sample_test.dart", kind="synthetic", domain="home",
                    platforms=["macos"], ci=True, inspection=False, **overrides)

    def test_未登记入口必须失败(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("void main() {}")
            self.assertRaisesRegex(ValueError, "未登记", catalog.validate, [], root)

    def test_人工驱动入口也必须登记(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "inspection_driver.dart").write_text("void main() {}")
            self.assertRaisesRegex(ValueError, "未登记", catalog.validate, [], root)

    def test_不能通过辅助文件藏入真实账号入口(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("import 'support.dart';")
            (root / "support.dart").write_text("UBAA_LIVE_READONLY")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate,
                                   [self.entry()], root)

    def test_不能通过根外共享辅助隐藏账号入口(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            root = workspace / "integration_test"
            root.mkdir()
            (root / "sample_test.dart").write_text("import '../support.dart';")
            (workspace / "support.dart").write_text("const mode = 'UBAA_LIVE_READONLY';")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate,
                                   [self.entry()], root)

    def test_条件导入也必须检查真实标记(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text(
                "import 'stub.dart' if (dart.library.io) 'support.dart';")
            (root / "stub.dart").write_text("")
            (root / "support.dart").write_text("const mode = 'UBAA_LIVE_READONLY';")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate,
                                   [self.entry()], root)

    def test_本地辅助缺失不能宣称分类完整(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("import 'missing.dart';")
            self.assertRaisesRegex(ValueError, "不存在", catalog.validate,
                                   [self.entry()], root)

    def test_自有package辅助不能隐藏账号入口(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            root = workspace / "integration_test"
            root.mkdir()
            package = workspace / "packages/shared"
            (package / "lib").mkdir(parents=True)
            (package / "pubspec.yaml").write_text("name: shared\n")
            (package / "lib/support.dart").write_text("const mode = 'UBAA_LIVE_READONLY';")
            (root / "sample_test.dart").write_text("export 'package:shared/support.dart';")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate, [self.entry()], root)

    def test_URI编码不能选择不同于Dart的字面路径(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("import 'h%65lper.dart';")
            (root / "h%65lper.dart").write_text("const ordinary = true;")
            (root / "helper.dart").write_text("const mode = 'UBAA_LIVE_READONLY';")
            self.assertRaisesRegex(ValueError, "URI", catalog.validate, [self.entry()], root)

    def test_真实账号入口不能登记到CI(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("UBAA_LIVE_READONLY")
            entry = self.entry()
            entry["kind"] = "live"
            self.assertRaisesRegex(ValueError, "CI", catalog.validate, [entry], root)

    def test_真实标记不能伪装为合成测试(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("UBAA_LIVE_READONLY")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate,
                                   [self.entry()], root)

    def test_重复入口必须失败(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("void main() {}")
            self.assertRaisesRegex(ValueError, "重复", catalog.validate,
                                   [self.entry(), self.entry()], root)

    def test_批量选择排除真实与人工入口(self):
        safe = self.entry()
        live = {**safe, "path": "live_test.dart", "kind": "live", "ci": False}
        manual = {**safe, "path": "manual_test.dart", "kind": "manual", "ci": False}
        self.assertEqual(catalog.select([safe, live, manual], "ci", "macos"), [safe])
        self.assertRaisesRegex(ValueError, "显式", catalog.select,
                               [live], "live_test.dart", "macos")

    def test_平台不匹配不能静默跳过(self):
        self.assertRaisesRegex(ValueError, "平台", catalog.select,
                               [self.entry()], "sample_test.dart", "linux")


if __name__ == "__main__":
    unittest.main()
