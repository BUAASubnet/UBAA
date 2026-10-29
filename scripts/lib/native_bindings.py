#!/usr/bin/env python3
"""FRB 2.13 的 no-web 输出和 Dart 接口注解做稳定的原生归一化。"""
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

    # FRB 2.13 在重复生成时会交替为 BridgeClient.dispose 添加 @override；
    # 注解不属于协议，统一去掉以保证门禁可重复执行。
    client = root / 'api' / 'client.dart'
    if client.exists():
        client_source = client.read_text()
        client_source, override_count = re.subn(
            r'(?m)^  @override\n(?=  Future<void> dispose\(\);\n)',
            '',
            client_source,
        )
        if override_count > 1:
            raise ValueError('BridgeClient.dispose 注解结构重复，请先审阅生成器')
        client.write_text(client_source)


if __name__ == '__main__':
    normalize(Path(sys.argv[1]))
