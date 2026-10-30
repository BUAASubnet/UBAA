#!/usr/bin/env python3
"""静态检查文档和执行入口中的 Cargo 依赖解析均已锁定。"""
import argparse
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from repo import ROOT


def violations(root):
    # 与 CLI 的 repository_cargo_gates_lock_dependency_resolution 保持相同范围。
    paths = subprocess.check_output([
        'git', '-C', str(root), 'ls-files', '-z', '--cached', '--others',
        '--exclude-standard', '--', 'justfile', '*.md', '.github/workflows/*', 'scripts/*.sh',
    ])
    failures = []
    metadata = 'cargo metadata --locked --no-deps --format-version 1'
    if metadata not in (root / 'justfile').read_text():
        failures.append('justfile 缺少锁定的 cargo metadata 检查')
    for name in sorted(set(paths.decode().split('\0')) - {''}):
        path = root / name
        if not path.is_file():
            continue
        try:
            source = path.read_text()
        except (OSError, UnicodeError) as error:
            failures.append(f'{name}: 无法读取命令来源：{error}')
            continue
        for number, line in enumerate(source.splitlines(), 1):
            index = line.find('cargo ')
            if index < 0:
                continue
            command = line[index:]
            if not command.startswith('cargo fmt ') and '--locked' not in command:
                failures.append(f'{name}:{number}: Cargo 命令缺少 --locked：{command}')
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    args = parser.parse_args()
    failures = violations(args.root)
    if failures:
        raise SystemExit('\n'.join(failures))
    print('Cargo 命令锁定检查通过')


if __name__ == '__main__':
    try:
        main()
    except (OSError, UnicodeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'Cargo 命令锁定检查失败：{error}') from None
