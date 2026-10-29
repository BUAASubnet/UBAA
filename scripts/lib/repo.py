"""Python 入口共用的仓库位置与官方包清单。"""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]


def official_packages():
    return json.loads((ROOT / 'scripts/tools/flutter-packages.json').read_text())
