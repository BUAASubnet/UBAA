#!/usr/bin/env python3
"""在原生 runner 上验证发布目录中的命令入口、终端解析和退出码。"""
import os
from pathlib import Path
import subprocess
import sys


def check(arguments, *, environment=None, status=0):
    result = subprocess.run(arguments, env=environment, capture_output=True,
                            text=True, encoding='utf-8', timeout=60)
    if result.returncode != status:
        raise RuntimeError(f'命令退出码应为 {status}，实际为 {result.returncode}：{result.stderr}')
    if status == 0 and 'ubaa-cli' not in result.stdout.lower():
        raise RuntimeError('命令帮助未写入标准输出')


def main():
    platform, directory = sys.argv[1:]
    artifact = Path(directory).resolve()
    command = {
        'linux': [str(artifact / 'ubaa-cli')],
        'windows': [str(artifact / 'ubaa-cli.exe')],
        'macos': [str(artifact / 'Contents/MacOS/UBAA'), '--command'],
    }[platform]
    check([*command, '--help'])
    check([*command, '--ubaa-invalid-option'], status=2)
    if platform == 'linux':
        check([str(artifact / 'UBAA'), '--command', '--help'])
    if platform == 'windows':
        environment = {**os.environ, 'PATH': str(artifact) + os.pathsep + os.environ['PATH']}
        check(['cmd', '/d', '/c', 'ubaa-cli --help'], environment=environment)
        check(['pwsh', '-NoProfile', '-NonInteractive', '-Command',
               'ubaa-cli --help; exit $LASTEXITCODE'], environment=environment)
    print(f'{platform}：命令入口、帮助输出与错误退出码通过')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    main()
