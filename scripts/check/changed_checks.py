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
from repo import ROOT, workspace_packages
PACKAGES = workspace_packages()

CODEGEN = ['env', 'CARGO_INCREMENTAL=0', 'CARGO_BUILD_JOBS=1', 'just', 'flutter-codegen-check']


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


# 路径只能识别已知边界；审阅发现新的安全/协议等影响时必须显式用 mode=full。
BOUNDARIES = (
    'crates/ubaa_core/', 'crates/ubaa_flutter_bridge/', 'crates/ubaa_test_support/',
    'fixtures/', 'packages/ubaa_bindings/', 'packages/ubaa_platform/lib/',
    'packages/ubaa_host/lib/', 'packages/ubaa_domain/lib/',
    'packages/ubaa_ui/lib/src/write', 'packages/ubaa_ui/lib/src/app/shell_write.dart',
    'packages/ubaa_ui/lib/src/app/cache_settings.dart',
    'apps/ubaa_cli/src/execute/', 'apps/ubaa_cli/src/backend/',
    'apps/ubaa_cli/src/bin/core_live/', 'apps/ubaa_cli/src/command/',
    'apps/ubaa_cli/src/io/input.rs', 'apps/ubaa_cli/src/routing.rs',
    'scripts/live/', 'scripts/check/sensitive', 'scripts/lib/sensitive',
    'scripts/lib/environment.py', 'scripts/lib/live-features.sh',
    'scripts/release/macos-entitlements.sh',
)
NATIVE_PARTS = {'android', 'ios', 'macos', 'linux', 'windows', 'ohos', 'native', 'cargokit'}
MANIFESTS = {'pubspec.yaml', 'pubspec.lock', 'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml',
             'flutter_rust_bridge.yaml'}
OHOS = ('apps/ubaa_ohos/', 'packages/flutter_secure_storage_ohos/',
        'packages/connectivity_plus_ohos/', 'packages/package_info_plus_ohos/')
DOCUMENT_ROOTS = ('docs/', 'scripts/', '.github/', 'apps/ubaa_cli/',
                  'crates/ubaa_core/', 'crates/ubaa_flutter_bridge/', 'crates/ubaa_test_support/',
                  *OHOS, *(folder + '/' for folder in PACKAGES.values()))
SCRIPT_EXTENSIONS = {'.py', '.sh', '.cjs', '.js', '.ts', '.pl', '.yml', '.yaml', '.json', '.txt', '.env'}


def select_checks(root, paths, mode='commit'):
    if mode not in {'commit', 'push', 'full'}:
        raise ValueError('检查模式只接受 commit、push 或 full')
    selected, production = set(), set()
    rust = scripts = native = site = False
    full = mode == 'full'
    codegen = full
    notes = set()
    for path in paths:
        site |= path.startswith('docs/site/') or path in {'package.json', 'package-lock.json'}
        # Markdown 与已知文档资源无需编译。合同 schema、未知扩展仍保守处理。
        if ((path.endswith('.md') and ('/' not in path or path.startswith(DOCUMENT_ROOTS)))
                or path.startswith('docs/site/')
                or (path.startswith('docs/') and Path(path).suffix in {'.svg', '.png', '.jpg', '.jpeg'})
                or path in {'package.json', 'package-lock.json'}):
            continue
        if path == 'scripts/release/dependency-audit.sh':
            notes.add('发布依赖审计入口改动：just dependency-audit 仍需显式联网运行。')
        if path.startswith(OHOS):
            full = True
            notes.add('OHOS 专属改动：另需 just ohos-check 及相应设备验证，官方 Flutter 检查不能替代。')
        # Bridge API、生成文件及依赖配置是生成输入。Core 实现变化保留完整测试，
        # 未改生成输入时省去重复重生成。未知影响仍包含生成检查。
        rust_test = ('tests' in Path(path).parts or Path(path).name == 'tests.rs'
                     or Path(path).name.endswith('_tests.rs'))
        codegen |= ((path.startswith('crates/ubaa_flutter_bridge/src/api/') and not rust_test)
                    or path in {'crates/ubaa_flutter_bridge/src/api.rs', 'crates/ubaa_flutter_bridge/src/lib.rs',
                                'crates/ubaa_flutter_bridge/src/frb_generated.rs'}
                    or path.startswith('packages/ubaa_bindings/lib/src/rust/')
                    or Path(path).name in MANIFESTS)
        app_boundary = (path.startswith('packages/ubaa_app/lib/')
                        and not path.startswith('packages/ubaa_app/lib/src/presentation/'))
        platform_security = (Path(path).suffix == '.entitlements' or Path(path).name in {'AndroidManifest.xml', 'Info.plist'})
        if path.startswith(BOUNDARIES) or Path(path).name in MANIFESTS or app_boundary or platform_security:
            full = True
            continue
        if ((path.startswith(('scripts/', '.github/')) and Path(path).suffix in SCRIPT_EXTENSIONS)
                or path == 'justfile'):
            scripts = True
            continue
        owner = next((name for name, folder in PACKAGES.items() if path.startswith(folder + '/')), None)
        if owner:
            relative = path[len(PACKAGES[owner]) + 1:]
            if relative.startswith(('test/', 'integration_test/')):
                selected.add(owner)
                native |= relative.startswith('integration_test/')
            elif relative.startswith(('lib/', 'assets/')):
                production.add(owner)
            elif set(Path(relative).parts) & NATIVE_PARTS:
                selected.add(owner)
                native = True
            elif relative == 'analysis_options.yaml':
                production.add(owner)
            else:
                full = codegen = True
        elif path.startswith('apps/ubaa_cli/') and Path(path).suffix == '.rs':
            rust = True
        elif path == 'analysis_options.yaml':
            selected.update(PACKAGES)
        else:
            full = codegen = True
    try:
        if production:
            selected |= dependents(root, production)
    except (OSError, ValueError):
        full = codegen = True
        notes.add('无法可靠解析本地依赖：执行完整验收。')
    if full:
        rust = native = True
        selected.update(PACKAGES)
        notes.add('边界、依赖配置、未知影响或显式 full：提交前执行完整确定性验收。')
    elif mode == 'push' and (rust or selected or native):
        selected.update(PACKAGES)
    if native and not full and mode == 'commit':
        notes.add('原生改动：提交前检查所属包，推送前 mode=push 或 CI 执行原生集成及对应平台专项。')
    return {'rust': rust, 'scripts': scripts, 'full': full, 'strict': full or mode == 'push',
            'native': native and (full or mode == 'push'),
            'packages': [name for name in PACKAGES if name in selected],
            'extra': ([CODEGEN] if codegen else []) + ([['npm', 'run', 'docs:build']] if site else []),
            'notes': sorted(notes)}


def commands(plan):
    result = [['just', 'refs'], ['just', 'check-sensitive'], ['git', 'diff', '--check']]
    if plan['rust']:
        # check 已包含脚本、布局、合同和文档检查，不能再展开一次公共检查。
        result.append(['just', 'check-strict' if plan['strict'] else 'check'])
    elif plan['scripts']:
        result.append(['just', 'script-check'])
    else:
        result.extend([['just', 'contract-version-check'], ['just', 'docs-link-check'],
                       ['just', 'cargo-lock-check']])
        if plan['packages']:
            result.append(['just', 'layout-check'])
    if plan['packages']:
        result.append(['bash', 'scripts/check/flutter-workspace.sh', 'check', *plan['packages']])
    if plan['native']:
        result.append(['just', 'integration-test'])
    result.extend(plan['extra'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='', help='可选比较基线；包含基线后提交及全部本地改动')
    parser.add_argument('--mode', choices=['commit', 'push', 'full'], default='commit', help='提交分级、推送验收或完整验收')
    parser.add_argument('--run', action='store_true', help='执行计划；默认仅显示')
    args = parser.parse_args()
    paths = changed_paths(ROOT, args.base)
    if not paths and args.mode != 'full':
        print('没有待检查改动；检查已提交分支时请传入 --base。')
        return
    plan = select_checks(ROOT, paths, args.mode)
    print(json.dumps({'改动': paths, '命令': commands(plan), '专项说明': plan['notes']}, ensure_ascii=False, indent=2), flush=True)
    if args.run:
        for command in commands(plan):
            subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
