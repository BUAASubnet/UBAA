#!/usr/bin/env python3
"""向 Shell 入口提供同一官方包清单，未知包失败关闭。"""
import sys
sys.dont_write_bytecode = True
from repo import official_packages
PACKAGES = official_packages()

try:
    for name in sys.argv[1:] or PACKAGES:
        print(PACKAGES[name])
except KeyError:
    raise SystemExit('未登记的官方 Flutter 包') from None
