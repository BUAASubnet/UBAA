#!/usr/bin/env python3
"""按 Git 改动规划本地确定性检查；未知输入保守执行完整门禁。"""
import argparse
import json
from pathlib import Path
import re
import subprocess

import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from repo import ROOT, official_packages
PACKAGES = official_packages()

CODEGEN = ['just', 'flutter-codegen-check']


def git_paths(root, *args):
    output = subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)
    return {p.decode('utf-8', errors='surrogateescape') for p in output.split(b'\0') if p}


def changed_paths(root, base=''):
    base = base.removeprefix('base=')
    # --no-renames 同时保留移动前后的路径，避免漏掉原模块。
    paths = git_paths(root, 'diff', '--name-only', '--no-renames', '-z', '--')
    paths |= git_paths(root, 'diff', '--cached', '--name-only', '--no-renames', '-z', 'HEAD', '--')
    paths |= git_paths(root, 'ls-files', '--others', '--exclude-standard', '-z')
    if base:
        revision = subprocess.check_output(
            ['git', '-C', str(root), 'rev-parse', '--verify', '--end-of-options', f'{base}^{{commit}}'],
            text=True, stderr=subprocess.PIPE).strip()
        paths |= git_paths(root, 'diff', '--name-only', '--no-renames', '-z', f'{revision}...HEAD', '--')
    return sorted(paths)


def dependents(root, seeds):
    # 同时读取 dependencies 与 dev_dependencies，避免漏掉使用生产包的测试消费者。
    owners = {(root / path).resolve(): name for name, path in PACKAGES.items()}
    graph = {}
    for name, path in PACKAGES.items():
        source = (root / path / 'pubspec.yaml').read_text()
        dependencies = set()
        for line in source.splitlines():
            if not re.search(r'\bpath\s*:', line) or re.match(r'^  path:', line):
                continue
            match = re.fullmatch(r' {4,}path:\s*([^\s#]+)\s*(?:#.*)?', line)
            if match is None:
                raise ValueError('无法可靠识别本地依赖，改用完整检查')
            target = (root / path / match[1].strip('\'"')).resolve()
            if target not in owners:
                raise ValueError('发现未登记本地依赖，改用完整检查')
            dependencies.add(owners[target])
        graph[name] = dependencies
    affected = set(seeds)
    while True:
        expanded = affected | {name for name, deps in graph.items() if deps & affected}
        if expanded == affected:
            return affected
        affected = expanded


def select_checks(root, paths):
    selected, production = set(), set()
    rust = full = codegen = site = False
    notes = set()
    for path in paths:
        site |= path.startswith('docs/site/') or path in {'package.json', 'package-lock.json'}
        if (path in {'README.md', 'CONTRIBUTING.md', 'goal.md', 'scripts/README.md'}
                or path in {folder + '/README.md' for folder in PACKAGES.values()}
                or path.startswith('docs/')):
            continue
        owner = next((name for name, folder in PACKAGES.items() if path.startswith(folder + '/')), None)
        if owner:
            relative = path[len(PACKAGES[owner]) + 1:]
            if relative.startswith('test/'):
                selected.add(owner)
            elif relative.startswith(('lib/', 'assets/')):
                production.add(owner)
                if owner == 'ubaa_bindings':
                    rust = codegen = True
            elif relative.startswith('integration_test/'):
                selected.add(owner)
                notes.add('原生能力测试变更：按 integration-list 在适用设备执行保留集合。')
            else:
                full = True
                notes.add('包配置或平台目录变更：原生能力还需在对应平台验证。')
        elif path.startswith(('apps/ubaa_ohos/', 'packages/flutter_secure_storage_ohos/', 'packages/connectivity_plus_ohos/', 'packages/package_info_plus_ohos/')):
            full = True
            notes.add('OHOS 专属改动：另需 just ohos-check 及相应设备验证，官方 Flutter 检查不能替代。')
        elif path.startswith('crates/ubaa_core/') or path.startswith('crates/ubaa_flutter_bridge/'):
            rust = codegen = True
            selected.update(PACKAGES)
        elif path.startswith(('crates/', 'apps/ubaa_cli/', 'fixtures/')) or path in {'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'}:
            rust = True
            if path in {'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'}:
                codegen = True
                selected.update(PACKAGES)
        else:
            full = True
    try:
        if production:
            selected |= dependents(root, production)
    except (OSError, ValueError):
        full = True
    if full:
        rust = codegen = True
        selected.update(PACKAGES)
    return {'rust': rust, 'packages': [name for name in PACKAGES if name in selected],
            'extra': ([CODEGEN] if codegen else []) + ([['npm', 'run', 'docs:build']] if site else []), 'notes': sorted(notes)}


def commands(plan):
    result = [['just', 'refs'], ['just', 'check-sensitive'], ['git', 'diff', '--check'],
              ['just', 'contract-version-check'], ['just', 'docs-link-check']]
    if plan['rust']:
        result.append(['just', 'check'])
    elif plan['packages']:
        result.extend([['just', 'layout-check'], ['just', 'module-check']])
    if plan['packages']:
        result.append(['bash', 'scripts/check/flutter-workspace.sh', 'check', *plan['packages']])
    result.extend(plan['extra'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='', help='可选比较基线；包含基线后提交及全部本地改动')
    parser.add_argument('--run', action='store_true', help='执行计划；默认仅显示')
    args = parser.parse_args()
    paths = changed_paths(ROOT, args.base)
    if not paths:
        print('没有待检查改动；检查已提交分支时请传入 --base。')
        return
    plan = select_checks(ROOT, paths)
    print(json.dumps({'改动': paths, '命令': commands(plan), '专项说明': plan['notes']}, ensure_ascii=False, indent=2), flush=True)
    if args.run:
        for command in commands(plan):
            subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
