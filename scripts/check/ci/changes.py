#!/usr/bin/env python3
"""开发 CI 只按改动选择语言检查，完整验收始终由 main 工作流执行。"""
import os
import subprocess
from pathlib import Path


def select(paths):
    shared = any(path.startswith(('.github/', 'scripts/')) or path == 'justfile' for path in paths)
    return {
        'rust': shared or any(path.startswith(('crates/', 'tools/', 'fixtures/')) or
                             path in {'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'} for path in paths),
        'flutter': shared or any(path.startswith(('apps/', 'packages/')) or
                                path in {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'} for path in paths),
        'worker': shared or any(path.startswith(('services/app_service/', 'docs/contracts/app-service',
                                                 'docs/site/announcements/')) or
                               path in {'package.json', 'package-lock.json'} for path in paths),
    }


def main():
    base = os.environ.get('BASE_SHA', '')
    if not base or set(base) == {'0'}:
        result = dict.fromkeys(('rust', 'flutter', 'worker'), True)
    else:
        paths = subprocess.check_output(['git', 'diff', '--name-only', '--no-renames', base, 'HEAD'], text=True).splitlines()
        result = select(paths)
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        for key, value in result.items():
            output.write(f'{key}={str(value).lower()}\n')


if __name__ == '__main__':
    main()
