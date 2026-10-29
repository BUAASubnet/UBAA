#!/usr/bin/env python3
"""FRB 2.13 的 no-web 仍输出条件导入，原生项目机械选择 IO 分支。"""
from pathlib import Path
import re
import sys


def normalize(root):
    entry = root / 'frb_generated.dart'
    source = entry.read_text()
    native, count = re.subn(r"import 'frb_generated\.io\.dart'\s+if \(dart\.library\.js_interop\) 'frb_generated\.web\.dart';",
                            "import 'frb_generated.io.dart';", source)
    if count != 1:
        raise ValueError('FRB 平台导入结构变化，请先审阅生成器再更新原生转换')
    entry.write_text(native)
    (root / 'frb_generated.web.dart').unlink(missing_ok=True)


if __name__ == '__main__':
    normalize(Path(sys.argv[1]))
