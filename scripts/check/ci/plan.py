#!/usr/bin/env python3
"""合并验收的生成选择、Flutter 分组及必需检查汇总。"""
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from changed_checks import CODEGEN, select_checks
from repo import ROOT, workspace_packages
PACKAGES = workspace_packages()


def codegen_required(paths):
    if paths is None:
        return True
    if any(path.startswith('.github/') or path in {
        'scripts/tools/versions.env', 'scripts/check/flutter-codegen.sh',
        'scripts/lib/native_bindings.py', 'scripts/check/ci/plan.py',
    } for path in paths):
        return True
    return CODEGEN in select_checks(ROOT, paths)['extra']


def flutter_files(root, package, group):
    folder = root / PACKAGES[package]
    files = sorted(str(path.relative_to(folder)) for path in (folder / 'test').rglob('*_test.dart'))
    if package != 'ubaa_ui':
        if group != 'all':
            raise ValueError('普通包只接受完整测试组')
        return files
    golden = [path for path in files if path.startswith('test/visual/')]
    if group == 'golden':
        return golden
    if group not in {'0', '1'}:
        raise ValueError('UI 测试组必须为 golden、0 或 1')
    return [path for index, path in enumerate(path for path in files if path not in golden)
            if index % 2 == int(group)]


def flutter_matrix(root):
    return {'include': [
        {'package': package, 'group': group,
         'os': 'macos-15' if group == 'golden' else 'ubuntu-24.04'}
        for package in PACKAGES
        for group in (('0', '1', 'golden') if package == 'ubaa_ui' else ('all',))
        if flutter_files(root, package, group)
    ]}


def accepted(jobs, codegen):
    return bool(jobs) and all(
        value['result'] == 'success' or
        (name == 'codegen' and not codegen and value['result'] == 'skipped')
        for name, value in jobs.items()
    )


def main():
    operation = sys.argv[1]
    if operation == 'plan':
        base = os.environ.get('BASE_SHA')
        paths = subprocess.check_output(['git', 'diff', '--name-only', '--no-renames', base, 'HEAD'], text=True).splitlines() if base else None
        values = {'codegen': str(codegen_required(paths)).lower(),
                  'flutter': json.dumps(flutter_matrix(ROOT), separators=(',', ':'))}
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
            for key, value in values.items():
                output.write(f'{key}={value}\n')
        print('FRB 生成检查：' + values['codegen'])
    elif operation == 'test':
        package, group = sys.argv[2:]
        files = flutter_files(ROOT, package, group)
        if not files:
            raise ValueError('测试组不能为空')
        subprocess.run(['just', 'flutter', 'test', '--no-pub', *files], cwd=ROOT / PACKAGES[package], check=True)
    elif operation == 'gate':
        jobs = json.loads(os.environ['NEEDS'])
        print(json.dumps(jobs, ensure_ascii=False))
        if not accepted(jobs, os.environ['CODEGEN_REQUIRED'] == 'true'):
            raise SystemExit(1)
    else:
        raise ValueError('未知 CI 操作')


if __name__ == '__main__':
    main()
