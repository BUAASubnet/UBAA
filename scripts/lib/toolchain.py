#!/usr/bin/env python3
"""项目工具链配置的唯一回退解析器；不执行配置内容，不读取凭据文件。"""
import os
from pathlib import Path
import re
import shlex
import sys

ROOT = Path(__file__).resolve().parents[2]
VARIABLE = re.compile(r'\$(?:\{([A-Za-z_][A-Za-z_0-9]*)\}|([A-Za-z][A-Za-z0-9]*))')


def load_environment(root=ROOT):
    environment = os.environ.copy()
    config = root / '.env.toolchain'
    if not config.exists():
        return environment
    for number, line in enumerate(config.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r'(?:export\s+)?([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(.*)', line)
        if match is None:
            raise ValueError(f'.env.toolchain 第 {number} 行格式无效；请使用 KEY=value')
        key, raw = match.groups()
        try:
            parts = shlex.split(raw, comments=True, posix=True)
        except ValueError as error:
            raise ValueError(f'.env.toolchain 第 {number} 行引号无效') from error
        if len(parts) > 1:
            raise ValueError(f'.env.toolchain 第 {number} 行包含空格，请用引号包围值')
        value = parts[0] if parts else ''
        if not raw.startswith("'"):
            value = VARIABLE.sub(lambda m: environment.get(m[1] or m[2], ''), value)
        # 与 just 默认 dotenv 行为一致：已导出的环境变量（含空值）优先。
        environment.setdefault(key, value)
    return environment


def main():
    environment = load_environment()
    if len(sys.argv) < 2:
        raise ValueError('需要 dart、flutter、flutter-ohos 或 shell 子命令')
    command = sys.argv[1]
    if command == 'shell':
        for key, value in environment.items():
            if key not in os.environ:
                print(f'export {key}={shlex.quote(value)}')
        return
    if command not in {'dart', 'flutter', 'flutter-ohos'}:
        raise ValueError('未知工具链子命令')
    variable = 'UBAA_OHOS_FLUTTER_HOME' if command == 'flutter-ohos' else 'UBAA_FLUTTER_HOME'
    root = environment.get(variable, '')
    tool = 'flutter' if command == 'flutter-ohos' else command
    executable = Path(root) / 'bin' / tool
    if not root or not Path(root).is_absolute() or not executable.is_file():
        raise ValueError(f'请在 .env.toolchain 中设置 {variable} 为包含 bin/{tool} 的 SDK 绝对路径')
    os.execvpe(str(executable), [str(executable), *sys.argv[2:]], environment)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
