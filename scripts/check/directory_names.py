#!/usr/bin/env python3
"""检查项目自有目录使用下划线，保留冻结与工具规定的路径。"""
from pathlib import Path
import subprocess
import re

import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from repo import ROOT



# 这些目录保留上游命名或历史归档索引，不接受自有源码扩展。
FROZEN = (
    'examples/', 'packages/ubaa_bindings/cargokit/',
    'scripts/tools/cyclonedx-1.5/', 'docs/design/evidence/ui-ux/',
)
ANDROID_RESOURCE = re.compile(
    r'apps/ubaa_flutter/android/app/src/(?:main|debug|profile|test|androidTest)/res/'
    r'[a-z_]+(?:-[A-Za-z0-9]+)+$'
)


def find_violations(paths):
    violations = set()
    for path in paths:
        if path.startswith(FROZEN):
            continue
        parts = path.split('/')[:-1]
        for index, name in enumerate(parts):
            if '-' not in name:
                continue
            directory = '/'.join(parts[:index + 1])
            if not ANDROID_RESOURCE.fullmatch(directory):
                violations.add(directory)
    return sorted(violations)


def main():
    output = subprocess.check_output([
        'git', '-C', str(ROOT), 'ls-files', '--cached', '--others',
        '--exclude-standard', '-z',
    ])
    paths = {p.decode('utf-8') for p in output.split(b'\0') if p}
    errors = find_violations(p for p in paths if (ROOT / p).exists())
    if errors:
        raise SystemExit('目录命名检查失败，请使用下划线：\n' + '\n'.join(errors))
    print('目录命名检查通过')


if __name__ == '__main__':
    main()
