"""Python 入口共用的仓库位置与 Flutter 包清单。"""
import json
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[2]


def official_packages():
    return json.loads((ROOT / 'scripts/tools/flutter-packages.json').read_text())


def workspace_packages():
    """返回需要执行 Flutter 门禁的全部 Pub workspace 成员。

    `official_packages` 保持七个正式发布包的既有语义；测试辅助包属于同一
    Pub workspace，虽然不发布，也必须参与格式、分析和测试检查。
    """
    packages = official_packages()
    manifest = ROOT / 'pubspec.yaml'
    if not manifest.is_file():
        raise FileNotFoundError(f'缺少 Flutter workspace manifest：{manifest}')
    lines = manifest.read_text().splitlines()
    try:
        start = next(index for index, line in enumerate(lines) if line.strip() == 'workspace:')
    except StopIteration as error:
        raise ValueError('Flutter workspace manifest 缺少 workspace 列表') from error
    for line in lines[start + 1:]:
        if line and not line[0].isspace():
            break
        match = re.fullmatch(r'\s+-\s+([^\s#]+)\s*', line)
        if match is None:
            continue
        path = match.group(1).strip('"\'')
        child = ROOT / path / 'pubspec.yaml'
        if not child.is_file():
            raise FileNotFoundError(f'workspace 成员缺少 pubspec.yaml：{child}')
        name = next(
            (value.group(1) for value in (
                re.fullmatch(r'\s*name:\s*["\']?([^"\'#\s]+)["\']?\s*', child_line)
                for child_line in child.read_text().splitlines()
            ) if value is not None),
            None,
        )
        if name is None:
            raise ValueError(f'workspace 成员缺少 name：{child}')
        if name in packages and packages[name] != path:
            raise ValueError(f'workspace 成员与正式包路径冲突：{name}')
        packages.setdefault(name, path)
    return packages
