#!/usr/bin/env python3
"""just 参数在一处规范化；参数数组直接传递，不拼接 Shell 代码。"""
import os
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from repo import ROOT, hand_off

SPECS = {
    'integration-test': [('suite', 'ci'), ('platform', 'macos'), ('device', '')],
    'check-plan': [('base', ''), ('mode', 'commit')],
    'check-changed': [('base', ''), ('mode', 'commit')],
    'release-preflight': [('report_dir', ''), ('mode', 'strict')],
    'flutter-test': [('package', None), ('path', 'test')],
    'flutter-build': [('platform', 'host'), ('mode', 'debug')],
    'flutter-artifact-check': [('platform', None), ('artifact', None)],
    'ohos-check': [('mode', 'release')],
}


def values(name, arguments):
    spec = dict(SPECS[name])
    provided = {}
    for argument in arguments:
        key, separator, value = argument.partition('=')
        if separator and key in spec:
            if key in provided:
                raise ValueError(f'参数 {key} 重复')
        else:
            if separator and not any(c in key for c in '/\\'):
                raise ValueError(f'未知参数：{key}')
            key = next((key for key in spec if key not in provided), None)
            if key is None:
                raise ValueError('参数过多')
            value = argument
        provided[key] = value
    result = [provided.get(key, default) for key, default in spec.items()]
    if any(value is None for value in result):
        raise ValueError('缺少必填参数：' + '、'.join(key for key, default in spec.items()
                                              if default is None and key not in provided))
    return result


def main():
    name = sys.argv[1]
    args = values(name, sys.argv[2:])
    commands = {
        'integration-test': [sys.executable, 'scripts/check/integration_catalog.py', 'run'],
        'release-preflight': ['bash', 'scripts/release/preflight.sh', *args],
        'flutter-test': ['bash', 'scripts/tests/flutter-package.sh', *args],
        'flutter-build': ['bash', 'scripts/build/flutter.sh', *args],
        'flutter-artifact-check': ['bash', 'scripts/release/verify-flutter-artifact.sh', *args],
        'ohos-check': ['bash', 'scripts/build/ohos.sh', *args],
    }
    if name in {'check-plan', 'check-changed'}:
        commands[name] = [sys.executable, 'scripts/check/changed_checks.py', '--base', args[0], '--mode', args[1]]
        if name == 'check-changed':
            commands[name].append('--run')
    if name == 'integration-test':
        commands[name] += ['--suite', args[0], '--platform', args[1], '--device', args[2]]
    os.chdir(ROOT)
    hand_off(commands[name], os.environ)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from None
