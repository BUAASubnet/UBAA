"""模块门禁关注真实 library 和依赖，不能仅通过拆文件绕过规模限制。"""

import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "check" / "module_graph.py"
spec = importlib.util.spec_from_file_location("module_graph", SCRIPT)
module_graph = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module_graph)


class ModuleGraphTest(unittest.TestCase):
    def scan(self, files, limit=100):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, source in files.items():
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(source)
            return module_graph.inspect(root, limit)

    def test_拆成part仍计入同一个library(self):
        self.assertRaisesRegex(ValueError, "规模", self.scan, {
            "entry.dart": "part 'first.dart';\npart 'second.dart';\n",
            "first.dart": "part of 'entry.dart';\nclass First {}\n",
            "second.dart": "part of 'entry.dart';\nclass Second {}\n",
        }, 5)

    def test_拒绝循环依赖(self):
        self.assertRaisesRegex(ValueError, "循环", self.scan, {
            "first.dart": "import 'second.dart';\n",
            "second.dart": "import 'first.dart';\n",
        })

    def test_条件导入不能隐藏循环(self):
        self.assertRaisesRegex(ValueError, "循环", self.scan, {
            "first.dart": "import 'stub.dart' if (dart.library.io) 'second.dart';\n",
            "stub.dart": "class Stub {}\n",
            "second.dart": "import 'first.dart';\n",
        })

    def test_条件导出和具名包导入参与同一个图(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            (package / "first.dart").write_text(
                "export 'stub.dart' if (dart.library.io == 'true') 'second.dart' show Thing;")
            (package / "stub.dart").write_text("class Thing {}")
            (package / "second.dart").write_text("import 'package:sample/first.dart';")
            self.assertRaisesRegex(ValueError, "循环", module_graph.inspect,
                                   package, 100, "sample", package)

    def test_不支持的指令不能静默忽略(self):
        self.assertRaisesRegex(ValueError, "不支持", self.scan, {
            "entry.dart": "augment import 'target.dart';\n",
            "target.dart": "class Target {}",
        })

    def test_脚本首行不能隐藏依赖(self):
        self.assertRaisesRegex(ValueError, "循环", self.scan, {
            "entry.dart": "#!/usr/bin/env dart\nimport 'other.dart';\n",
            "other.dart": "import 'entry.dart';\n",
        })

    def test_URI查询片段反斜线明确拒绝(self):
        for suffix in ('?value', '#fragment', '\\other'):
            with self.subTest(suffix=suffix):
                self.assertRaisesRegex(ValueError, "URI|指令", self.scan, {
                    "entry.dart": f"import r'other.dart{suffix}';\n",
                    "other.dart": "class Other {}\n",
                })

    def test_跨扫描域仍拒绝循环(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            (package / "bridge").mkdir()
            (package / "controller").mkdir()
            (package / "bridge/a.dart").write_text("import '../controller/b.dart';\n")
            (package / "controller/b.dart").write_text("import '../bridge/a.dart';\n")
            self.assertRaisesRegex(ValueError, "循环", module_graph.inspect,
                                   package / "bridge", 100, "sample", package)

    def test_注释换行和同行指令仍参与图(self):
        self.assertRaisesRegex(ValueError, "循环", self.scan, {
            "first.dart": "/* 前导 */ import /* 说明 */ 'second.dart';\n",
            "second.dart": "export 'stub.dart'; import 'first.dart';\n",
            "stub.dart": "class Stub {}\n",
        })

    def test_失效本地导入必须失败(self):
        self.assertRaisesRegex(ValueError, "不存在", self.scan, {
            "entry.dart": "import 'missing.dart';\n",
        })

    def test_拒绝未注册的part(self):
        self.assertRaisesRegex(ValueError, "归属", self.scan, {
            "entry.dart": "class Entry {}\n",
            "part.dart": "part of 'entry.dart';\nclass Hidden {}\n",
        })

    def test_拒绝跨library借用part(self):
        self.assertRaisesRegex(ValueError, "归属", self.scan, {
            "entry.dart": "part 'part.dart';\n",
            "other.dart": "part 'part.dart';\n",
            "part.dart": "part of 'entry.dart';\n",
        })

    def test_允许无环的明确依赖(self):
        result = self.scan({
            "entry.dart": "import 'feature.dart';\n",
            "feature.dart": "import 'shared.dart';\n",
            "shared.dart": "class Shared {}\n",
        })
        self.assertEqual(result["libraries"], 3)


if __name__ == "__main__":
    unittest.main()
