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
