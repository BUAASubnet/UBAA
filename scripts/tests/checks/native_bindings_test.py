#!/usr/bin/env python3
"""关闭 Web 后只保留原生 import，生成器结构变化时失败关闭。"""
import importlib.util
from pathlib import Path
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('native_bindings', ROOT / 'scripts/lib/native_bindings.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class NativeBindingsTest(unittest.TestCase):
    def test_native_import_and_stale_web_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            entry = root / 'frb_generated.dart'
            entry.write_text("import 'frb_generated.io.dart'\n    if (dart.library.js_interop) 'frb_generated.web.dart';\n// 其他内容\n")
            web = root / 'frb_generated.web.dart'
            web.write_text('// 过时的 Web 生成物')
            native.normalize(root)
            self.assertEqual(entry.read_text(), "import 'frb_generated.io.dart';\n// 其他内容\n")
            self.assertFalse(web.exists())

    def test_unknown_generator_shape_is_rejected_without_deletion(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'frb_generated.dart').write_text('// 未知结构')
            (root / 'frb_generated.web.dart').touch()
            with self.assertRaises(ValueError):
                native.normalize(root)
            self.assertTrue((root / 'frb_generated.web.dart').exists())


if __name__ == '__main__':
    unittest.main()
