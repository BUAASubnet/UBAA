"""集成清单必须完整，批量回归不能意外选择真实账号入口。"""

import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check" / "integration_catalog.py"
spec = importlib.util.spec_from_file_location("catalog", SCRIPT)
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class CatalogTest(unittest.TestCase):
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
