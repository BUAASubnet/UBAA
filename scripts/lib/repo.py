"""Python 入口共用的仓库位置与 Flutter 包清单。"""
import json
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[2]


def official_packages():
    return json.loads((ROOT / 'scripts/tools/flutter-packages.json').read_text())


def _manifest_string(value):
    """只接受单行字符串；复杂 YAML 写法明确失败，避免静默漏掉包。"""
    match = re.fullmatch(r'''("(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[^\s#'"][^\s#]*)(?:\s+#.*)?\s*''', value)
    if match is None:
        raise ValueError(f'无法解析 pubspec 字符串：{value!r}')
    literal = match.group(1)
    if literal.startswith('"'):
        return json.loads(literal)
    if literal.startswith("'"):
        return literal[1:-1].replace("''", "'")
    return literal


def workspace_members(manifest):
    """解析当前根 pubspec 的简单 workspace 列表，不依赖外部 YAML 库。"""
    lines = manifest.read_text().splitlines()
    try:
        start = next(index for index, line in enumerate(lines)
                     if re.fullmatch(r'workspace:\s*(?:#.*)?', line))
    except StopIteration as error:
        raise ValueError('Flutter workspace manifest 缺少顶层 workspace 列表') from error
    members = []
    for line in lines[start + 1:]:
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        if not line[0].isspace() and not stripped.startswith('- '):
            break
        match = re.fullmatch(r'-\s+(.+)', stripped)
        if match is None:
            raise ValueError(f'workspace 列表包含无法解析的项：{line!r}')
        value = _manifest_string(match.group(1))
        if not value:
            raise ValueError('workspace 列表不能包含空路径')
        members.append(value)
    if not members:
        raise ValueError('Flutter workspace 列表不能为空')
    return members


def workspace_packages():
    """返回需要执行 Flutter 门禁的全部 Pub workspace 成员。

    `official_packages` 保持七个正式发布包的既有语义；测试辅助包属于同一
    Pub workspace，虽然不发布，也必须参与格式、分析和测试检查。
    """
    packages = official_packages()
    manifest = ROOT / 'pubspec.yaml'
    if not manifest.is_file():
        raise FileNotFoundError(f'缺少 Flutter workspace manifest：{manifest}')
    members = workspace_members(manifest)
    for path in members:
        path = path.strip()
        if not path or Path(path).is_absolute() or '..' in Path(path).parts:
            raise ValueError(f'workspace 成员路径无效：{path!r}')
        child = ROOT / path / 'pubspec.yaml'
        if not child.is_file():
            raise FileNotFoundError(f'workspace 成员缺少 pubspec.yaml：{child}')
        name = next((_manifest_string(line.removeprefix('name:').strip())
                     for line in child.read_text().splitlines() if line.startswith('name:')), None)
        if name is None:
            raise ValueError(f'workspace 成员缺少 name：{child}')
        if name in packages and packages[name] != path:
            raise ValueError(f'workspace 成员与正式包路径冲突：{name}')
        packages.setdefault(name, path)
    return packages
