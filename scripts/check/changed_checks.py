#!/usr/bin/env python3
"""按 Git 改动规划本地确定性检查；未知输入保守执行完整门禁。"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tomllib

import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from repo import ROOT, workspace_packages
import rust_workspace
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


def previous_reader(root, base=''):
    """读取比较起点的文件内容：有基线时取与 HEAD 的合并基点，否则取 HEAD；读不到返回 None。"""
    base = base.removeprefix('base=')
    revision = 'HEAD'
    if base:
        revision = subprocess.check_output(['git', '-C', str(root), 'merge-base', base, 'HEAD'],
                                           text=True, stderr=subprocess.PIPE).strip()

    def read(path):
        try:
            return subprocess.check_output(['git', '-C', str(root), 'show', f'{revision}:{path}'],
                                           text=True, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            return None
    return read


BRIDGE = 'ubaa_flutter_bridge'


def bridge_closure(lock_text):
    packages = {}
    for package in tomllib.loads(lock_text)['package']:
        packages.setdefault(package['name'], []).append(package)

    def resolve(dependency):
        name, *rest = dependency.split(' ')
        candidates = packages.get(name, [])
        if rest:
            candidates = [package for package in candidates if package['version'] == rest[0]]
        if len(candidates) != 1:
            raise ValueError('锁文件依赖无法唯一解析')
        return candidates[0]

    closure, stack = {}, [resolve(BRIDGE)]
    while stack:
        package = stack.pop()
        key = (package['name'], package['version'], package.get('source'))
        if key not in closure:
            closure[key] = package.get('checksum')
            stack.extend(resolve(dependency) for dependency in package.get('dependencies', []))
    return closure


def rust_only_manifest(root, path, previous):
    if path == 'tools/core_live/Cargo.toml':
        return True
    if path not in {'Cargo.lock', 'Cargo.toml'} or previous is None:
        return False
    try:
        old_lock = previous('Cargo.lock')
        new_lock = (root / 'Cargo.lock').read_text()
        if old_lock is None:
            raise ValueError('缺少 Cargo.lock 基线')
        old_closure, new_closure = bridge_closure(old_lock), bridge_closure(new_lock)
        if old_closure != new_closure:
            return False
        if path == 'Cargo.lock':
            return True
        old_text = previous('Cargo.toml')
        if old_text is None:
            raise ValueError('缺少 Cargo.toml 基线')
        old, new = tomllib.loads(old_text), tomllib.loads((root / 'Cargo.toml').read_text())
        old_deps = old.get('workspace', {}).pop('dependencies', {})
        new_deps = new.get('workspace', {}).pop('dependencies', {})
        if old != new:
            return False
        changed = set()
        for name in old_deps.keys() | new_deps.keys():
            if old_deps.get(name) != new_deps.get(name):
                for table in (old_deps, new_deps):
                    entry = table.get(name)
                    changed.add(entry.get('package', name) if isinstance(entry, dict) else name)
        bridge_dependencies = {name for name, _, _ in old_closure} | {name for name, _, _ in new_closure}
        return not (changed & bridge_dependencies)
    except (OSError, ValueError, KeyError, TypeError, tomllib.TOMLDecodeError) as error:
        raise ValueError('无法可靠解析 Rust 依赖') from error


CORE = 'crates/ubaa_core/src/'
BRIDGE_SRC = 'crates/ubaa_flutter_bridge/src/'
PLATFORM_LIB = 'packages/ubaa_platform/lib/'
APP_LIB = 'packages/ubaa_app/lib/src/'
SECURE_STORAGE = (
    *(CORE + path for path in ('session/file_store.rs', 'session/file_safety.rs', 'session/storage.rs',
                               'cache/crypto.rs')),
    *(PLATFORM_LIB + path for path in ('credentials.dart', 'shared_accounts.dart', 'src/credentials.dart',
                                       'src/local_accounts.dart', 'src/secure_material.dart', 'src/material/')),
)
PROTOCOL = tuple(CORE + path for path in (
    'auth/', 'session/', 'connection/', 'connection.rs', 'connection_codec.rs', 'config.rs',
    'internal/route_state/', 'internal/runtime.rs', 'internal/runtime/main_session.rs',
    'internal/runtime/bearer.rs', 'internal/runtime/school_gate.rs', 'internal/runtime/request_batch.rs',
    'ports/reqwest_transport.rs', 'upstream/mod.rs', 'upstream/interactive_auth.rs',
    'facade/auth.rs', 'facade/auth/', 'facade/interactive_auth/', 'facade/required_recovery/',
    'facade/routing.rs', 'facade/routing/', 'facade/write/', 'facade/read/write_readback.rs',
    'facade/agenda_sync/remote.rs',
))
FFI = (
    BRIDGE_SRC + 'api/', BRIDGE_SRC + 'api.rs', BRIDGE_SRC + 'lib.rs', BRIDGE_SRC + 'android_tls.rs',
    'packages/ubaa_bindings/lib/ubaa_bindings.dart', 'packages/ubaa_bindings/lib/src/',
    'packages/ubaa_bindings/cargokit/',
    *(f'packages/ubaa_bindings/{platform}/' for platform in ('android', 'ios', 'macos', 'linux', 'windows', 'ohos')),
)
HIGH_RISK = (
    *PROTOCOL, *SECURE_STORAGE, *FFI,
    *(CORE + path for path in (
        'error/', 'cache/files.rs', 'cache/mod.rs', 'cache/store.rs', 'cache/store/', 'cache/profile/mod.rs',
        'internal/sqlite.rs', 'agenda/operations.rs', 'agenda/sqlite.rs', 'agenda/store.rs', 'agenda/sync/',
        'app_service/privacy.rs', 'app_service/queue.rs', 'app_service/sqlite.rs', 'app_service/upload.rs',
        'ports/reqwest_object.rs', 'features/libbook/service.rs', 'features/libbook/crypto.rs',
        'facade/mod.rs', 'facade/client.rs', 'facade/client/app_service.rs', 'facade/client/observation.rs',
        'facade/client/readonly.rs', 'facade/client/operation_control.rs',
        'facade/offline.rs', 'facade/offline/grade_baseline.rs', 'facade/offline/refresh.rs',
        'facade/shared_account/', 'facade/agenda_sync/', 'facade/schedule_import/mod.rs',
        'facade/academic_cache.rs', 'facade/bykc_cache.rs', 'facade/cgyy_cache.rs',
        'facade/evaluation_cache.rs', 'facade/home_cache.rs', 'facade/libbook_cache.rs',
        'facade/ygdk_cache.rs', 'facade/profile_cache/', 'facade/campus/cache.rs',
        'facade/evaluation_cache/', 'facade/home_cache/', 'facade/ygdk_cache/',
        'facade/sensitive/', 'facade/diagnostic.rs', 'facade/diagnostic/cgyy.rs', 'facade/diagnostic/evaluation.rs',
        'facade/judge_scan/routing.rs', 'facade/judge_refresh/recovery.rs', 'facade/cloud_print/mod.rs',
        'facade/bhpan/mod.rs', 'facade/bhpan/state.rs', 'facade/bhpan/write.rs', 'facade/bhpan/object_upload.rs',
        'facade/bhpan/upload.rs', 'facade/bhpan/versions.rs', 'facade/bhpan/download_file.rs',
    )),
    *(APP_LIB + path for path in (
        'bridge/auth/', 'bridge/write/', 'bridge/cache/account.dart', 'controller/recovery/',
        'controller/session/', 'controller/reads/session.dart', 'controller/write/', 'write/',
        'contracts/interactive_auth.dart', 'contracts/recovery.dart', 'contracts/session_recovery.dart',
        'services/session_recovery.dart',
    )),
    'packages/ubaa_ui/lib/src/write', 'packages/ubaa_ui/lib/src/app/shell_write.dart',
    'packages/ubaa_ui/lib/src/app/cache_settings.dart',
    'crates/ubaa_command/src/execute/', 'crates/ubaa_command/src/backend/',
    'crates/ubaa_command/src/command/', 'crates/ubaa_command/src/runtime/', 'crates/ubaa_command/src/agenda/',
    'crates/ubaa_command/src/io/input.rs', 'crates/ubaa_command/src/routing.rs',
    'tools/core_live/src/', 'scripts/live/', 'scripts/check/sensitive', 'scripts/lib/sensitive',
    'scripts/lib/environment.py', 'scripts/lib/live-features.sh', 'scripts/release/macos-entitlements.sh',
    'scripts/release/platforms/apple_signing.py', 'scripts/release/platforms/ohos_signing.mjs',
    'Cargo.lock', 'pubspec.lock', 'rust-toolchain.toml', 'packages/ubaa_bindings/flutter_rust_bridge.yaml',
)
NATIVE_PARTS = {'android', 'ios', 'macos', 'linux', 'windows', 'ohos', 'native', 'cargokit'}
MANIFESTS = {'pubspec.yaml', 'pubspec.lock', 'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml',
             'flutter_rust_bridge.yaml'}
OHOS = ('apps/ubaa_ohos/', 'packages/ubaa_bindings/ohos/', 'packages/flutter_secure_storage_ohos/',
        'packages/connectivity_plus_ohos/', 'packages/package_info_plus_ohos/')
DOCUMENT_ROOTS = ('docs/', 'scripts/', '.github/', 'crates/ubaa_command/', 'tools/core_live/',
                  'crates/ubaa_core/', 'crates/ubaa_flutter_bridge/', 'crates/ubaa_test_support/',
                  *OHOS, *(folder + '/' for folder in PACKAGES.values()))
SCRIPT_EXTENSIONS = {'.py', '.sh', '.cjs', '.js', '.mjs', '.ts', '.pl', '.yml', '.yaml', '.json', '.txt', '.env'}
MAINTENANCE_INPUTS = {
    'justfile', 'scripts/check/shell.sh', 'scripts/tests/maintenance-gates.sh',
    'scripts/build/flutter.sh', 'scripts/release/verify-flutter-artifact.sh',
    'scripts/release/macos-entitlements.sh', 'scripts/release/platforms/apple_signing.py',
    'scripts/release/platforms/ohos_signing.mjs', 'scripts/tools/versions.env',
}
LIVE_LAUNCHER_INPUTS = {
    'scripts/tests/live-launchers.sh', 'scripts/lib/environment.py',
    'scripts/lib/live-features.sh', 'scripts/lib/repo.sh', 'scripts/lib/toolchain.sh',
    'scripts/lib/toolchain.py',
}
APP_SERVICE_INPUTS = {
    'docs/contracts/app-service.schema.json', 'docs/contracts/app-service.md',
    'scripts/check/contract-versions.sh', 'scripts/tests/checks/contract_versions_test.py',
    'scripts/check/changed_checks.py', 'scripts/tests/checks/changed_checks_test.py',
    'crates/ubaa_core/src/error/mod.rs', 'packages/ubaa_domain/lib/src/feature/catalog.dart',
    '.github/workflows/ci.yml', '.github/actions/versions/action.yml',
    '.github/actions/toolchain/action.yml', 'scripts/tools/versions.env', 'justfile',
}
PRIVACY_POLICY_INPUTS = {
    'docs/site/tech/privacy-policy.md',
    'packages/ubaa_domain/lib/src/privacy/bundled_policy.dart',
    'scripts/check/app_service/privacy_policy.py',
    'scripts/tests/app_service/privacy_policy_test.py',
}
TOOL_VERSION_INPUTS = {
    'scripts/tools/versions.env', 'scripts/check/tool_versions.py', 'scripts/lib/environment.py',
    'Cargo.toml', 'rust-toolchain.toml', 'crates/ubaa_flutter_bridge/Cargo.toml',
    'crates/ubaa_flutter_bridge/cargokit.yaml', 'packages/ubaa_bindings/pubspec.yaml',
}
VERSION_INPUTS = {
    'version.toml', 'scripts/release/version.py', 'Cargo.toml', 'Cargo.lock',
    'crates/ubaa_core/tests/compile/Cargo.lock', 'pubspec.yaml', 'pubspec.lock',
    'apps/ubaa_ohos/pubspec.yaml', 'apps/ubaa_ohos/pubspec.lock',
    'apps/ubaa_ohos/ohos/AppScope/app.json5', 'apps/ubaa_ohos/ohos/oh-package.json5',
    'apps/ubaa_ohos/ohos/entry/oh-package.json5', 'packages/ubaa_bindings/ohos/oh-package.json5',
    'packages/ubaa_bindings/ohos/src/main/cpp/types/libubaa_flutter_bridge/oh-package.json5',
    'packages/ubaa_bindings/android/build.gradle',
    *(f'{folder}/pubspec.yaml' for folder in PACKAGES.values()),
    *(f'apps/ubaa_flutter/{platform}/Podfile.lock' for platform in ('ios', 'macos')),
    *(f'packages/ubaa_bindings/{platform}/ubaa_bindings.podspec' for platform in ('ios', 'macos')),
}
SITE_INPUTS = {
    'package.json', 'package-lock.json', 'docs/contracts/app-service.schema.json',
    'scripts/check/app_service/content.mjs', 'services/app_service/src/version.mjs',
}
APP_SERVICE_CONTENT_INPUTS = SITE_INPUTS | {
    'docs/contracts/app-service.md', 'services/app_service/config/channels.json',
    'scripts/tests/app_service/content_test.mjs', 'scripts/tests/app_service/announcements_site_test.mjs',
    'scripts/tests/app_service/release_test.mjs',
    'justfile', 'scripts/lib/recipe.py',
    'scripts/check/changed_checks.py', 'scripts/tests/checks/changed_checks_test.py',
    '.github/workflows/ci.yml', '.github/workflows/docs.yml', '.github/workflows/app-content.yml',
    'scripts/server/content.mjs',
}
APP_SERVICE_CONTENT_PATHS = (
    'docs/site/announcements/', 'docs/site/.vitepress/',
    'scripts/release/app_service/', 'fixtures/app_service/announcements/',
)


def select_checks(root, paths, mode='commit', previous=None):
    if mode not in {'commit', 'full'}:
        raise ValueError('检查模式只接受 commit 或 full')
    paths = tuple(paths)
    selected, production = set(), set()
    rust_paths, risk_paths, native_checks = set(), set(), set()
    rust_crates = set()
    scripts = site = app_service = privacy_policy = maintenance = False
    app_service_content = False
    full = mode == 'full'
    codegen = protocol = False
    host_platform = {'darwin': 'macos', 'win32': 'windows'}.get(sys.platform, 'linux')
    notes = set()
    for path in paths:
        filename = Path(path).name
        site |= path.startswith('docs/site/') or path in SITE_INPUTS
        app_service_content |= (path in APP_SERVICE_CONTENT_INPUTS
                                or path.startswith(APP_SERVICE_CONTENT_PATHS))
        privacy_policy |= path in PRIVACY_POLICY_INPUTS
        app_service |= path in APP_SERVICE_INPUTS or path.startswith((
            'services/app_service/', 'fixtures/app_service/', 'crates/ubaa_core/src/app_service/',
            'scripts/check/app_service/', 'scripts/tests/app_service/',
        ))
        if path.startswith('services/app_service/'):
            continue
        # Markdown 与已知文档资源无需编译。合同 schema、未知扩展仍保守处理。
        markdown = path.endswith('.md') and ('/' not in path or path.startswith(DOCUMENT_ROOTS))
        if (markdown
                or path.startswith('docs/site/')
                or (path.startswith('docs/') and Path(path).suffix in {'.svg', '.png', '.jpg', '.jpeg'})
                or path in {'package.json', 'package-lock.json', 'version.toml'}):
            continue
        if path == 'scripts/release/dependency-audit.sh':
            notes.add('发布依赖审计入口改动：just dependency-audit 仍需显式联网运行。')
        ohos = path.startswith(OHOS)
        if ohos:
            notes.add('OHOS 专属改动：另需 just ohos-check 及相应设备验证，官方 Flutter 检查不能替代。')
        try:
            skip_codegen = (not full and filename in {'Cargo.lock', 'Cargo.toml'}
                            and rust_only_manifest(root, path, previous))
        except ValueError:
            full = True
            skip_codegen = False
            notes.add('无法可靠解析 Rust 依赖：执行完整验收。')
        rust_test = ('tests' in Path(path).parts or filename == 'tests.rs' or filename.endswith('_tests.rs'))
        generated_binding = path.startswith('packages/ubaa_bindings/lib/src/rust/')
        codegen |= ((path.startswith('crates/ubaa_flutter_bridge/src/api/') and not rust_test)
                    or path in {'crates/ubaa_flutter_bridge/src/api.rs', 'crates/ubaa_flutter_bridge/src/lib.rs',
                                'crates/ubaa_flutter_bridge/src/frb_generated.rs'}
                    or generated_binding
                    or (filename in MANIFESTS and not skip_codegen))
        feature_protocol = (path.startswith(CORE + 'features/') and not rust_test
                            and filename in {'auth.rs', 'write.rs', 'upload.rs'})
        protocol |= feature_protocol or path.startswith(PROTOCOL)
        ffi = path.startswith(FFI) and not rust_test and not generated_binding
        platform_parts = set(Path(path).parts) & (NATIVE_PARTS - {'ohos', 'native', 'cargokit'})
        if path.startswith(SECURE_STORAGE) and not ohos:
            if filename.startswith('linux_'):
                platform_parts = {'linux'}
            elif filename.startswith('windows_'):
                platform_parts = {'windows'}
            native_checks.update(('platform/credentials/material_test.dart', platform)
                                 for platform in platform_parts or {host_platform})
        elif ffi and not ohos:
            if filename == 'android_tls.rs':
                platform_parts = {'android'}
            native_checks.update((suite, platform) for platform in platform_parts or {host_platform}
                                 for suite in ('synthetic/cache/bridge_test.dart', 'synthetic/app/smoke_test.dart'))
        platform_security = Path(path).suffix == '.entitlements' or filename in {'AndroidManifest.xml', 'Info.plist'}
        maintenance |= (platform_security or path in MAINTENANCE_INPUTS
                        or path.startswith(('scripts/release/platforms/', '.github/actions/shellcheck/')))
        if (path.startswith(HIGH_RISK) and not generated_binding) or feature_protocol or platform_security:
            risk_paths.add(path)
        if ohos:
            continue
        if ((path.startswith(('scripts/', '.github/')) and Path(path).suffix in SCRIPT_EXTENSIONS)
                or path == 'justfile'):
            scripts = True
            continue
        owner = next((name for name, folder in PACKAGES.items() if path.startswith(folder + '/')), None)
        if path == 'packages/ubaa_bindings/flutter_rust_bridge.yaml':
            production.add('ubaa_bindings')
        elif owner:
            relative = path[len(PACKAGES[owner]) + 1:]
            if relative.startswith(('test/', 'integration_test/')):
                selected.add(owner)
                if relative.startswith('integration_test/'):
                    native_checks.add(('ci', host_platform))
                    risk_paths.add(path)
            elif relative.startswith(('lib/', 'assets/')) or relative == 'pubspec.yaml':
                production.add(owner)
            elif set(Path(relative).parts) & NATIVE_PARTS:
                selected.add(owner)
                risk_paths.add(path)
                if not ffi:
                    native_checks.update(('ci', platform) for platform in platform_parts or {host_platform})
            elif relative == 'analysis_options.yaml':
                production.add(owner)
            else:
                full = True
        elif path in {'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'} or (
                path.startswith(('crates/', 'tools/'))
                and (Path(path).suffix == '.rs' or filename == 'Cargo.toml')):
            rust_paths.add(path)
        elif path in {'analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock'}:
            selected.update(PACKAGES)
            if path == 'pubspec.yaml':
                production.update(PACKAGES)
        elif path.startswith('fixtures/'):
            if not path.startswith('fixtures/app_service/'):
                rust_paths.add('crates/ubaa_test_support/Cargo.toml')
        else:
            full = codegen = True
    risk = bool(risk_paths) and not full
    try:
        if not full:
            seeds = selected | production if risk else production
            if seeds:
                selected |= dependents(root, seeds)
            if rust_paths:
                packages = rust_workspace.members(root)
                owners = {
                    Path(package['manifest_path']).parent.resolve().relative_to(root.resolve()).as_posix() + '/': name
                    for name, package in packages.items()
                }
                for rust_path in sorted(rust_paths - {'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'}):
                    owner = next((name for prefix, name in sorted(owners.items(), key=lambda item: len(item[0]), reverse=True)
                                  if rust_path.startswith(prefix)), None)
                    if owner is None:
                        raise ValueError('未登记的 Rust crate')
                    rust_crates.add(owner)
                rust_crates = set(rust_workspace.affected(packages, rust_crates))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        full = True
        notes.add('无法可靠解析本地依赖：执行完整验收。')
    if full:
        selected.update(PACKAGES)
        notes.add('未知范围、依赖解析失败或显式 full：执行完整验收。')
    elif risk:
        notes.add('高风险改动：增加 check-risk、受影响包的消费者测试及专项检查。')
        if protocol:
            notes.add('涉及协议变更时，按来源对照门禁记录。')
    docs = any(path.endswith('.md') for path in paths)
    return {'rust': bool(rust_paths) or full, 'rust_crates': sorted(rust_crates),
            'rust_workspace': bool(rust_paths & {'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'}),
            'scripts': scripts, 'docs': docs, 'full': full, 'risk': risk and not full,
            'cargo_lock': scripts or docs,
            'maintenance': maintenance,
            'live_launchers': any(path.startswith('scripts/live/') or path in LIVE_LAUNCHER_INPUTS
                                  for path in paths),
            'tool_versions': any(path in TOOL_VERSION_INPUTS
                                 or (path.startswith('.github/') and path.endswith('.yml'))
                                 for path in paths),
            'versions': any(path in VERSION_INPUTS for path in paths),
            'native': [['just', 'integration-test']] if full else [
                ['just', 'integration-test', f'suite={suite}', f'platform={platform}']
                for suite, platform in sorted(native_checks)],
            'app_service': app_service or full,
            'app_service_content': app_service_content or full,
            'privacy_policy': privacy_policy,
            'packages': [name for name in PACKAGES if name in selected],
            'extra': ([CODEGEN] if codegen or full else []) + ([['npm', 'run', 'docs:build']] if site else []),
            'notes': sorted(notes)}


def commands(plan):
    result = [['just', 'check-sensitive'], ['git', 'diff', '--check']]
    if plan['app_service_content']:
        result.append(['just', 'app-service-content-check'])
    if plan['app_service']:
        result.append(['just', 'app-service-check'])
    if plan['full']:
        result.append(['just', 'check-strict'])
    else:
        crates = [] if plan['rust_workspace'] else plan['rust_crates']
        if plan['rust']:
            result.append(['just', 'check', *crates])
        if plan['risk']:
            result.append(['just', 'check-risk', *crates])
        if plan['scripts']:
            result.append(['just', 'script-check', 'scoped'])
        if plan['docs']:
            result.append(['just', 'docs-link-check'])
        if plan['cargo_lock']:
            result.append(['just', 'cargo-lock-check'])
        if plan['maintenance']:
            result.append(['bash', './scripts/tests/maintenance-gates.sh'])
        if plan['live_launchers']:
            result.append(['bash', './scripts/tests/live-launchers.sh'])
        if plan['privacy_policy']:
            result.append(['just', 'privacy-policy-check'])
        if plan['tool_versions']:
            result.append(['just', 'tool-version-check'])
        if plan['versions']:
            result.append(['just', 'version-check'])
    if plan['packages']:
        if not plan['full'] and not plan['scripts']:
            result.append(['just', 'module-check'])
        result.append(['bash', 'scripts/check/flutter-workspace.sh', 'check', *plan['packages']])
    result.extend(plan['native'])
    result.extend(plan['extra'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='', help='可选比较基线；包含基线后提交及全部本地改动')
    parser.add_argument('--mode', choices=['commit', 'full'], default='commit', help='提交分级或完整验收')
    parser.add_argument('--run', action='store_true', help='执行计划；默认仅显示')
    args = parser.parse_args()
    paths = changed_paths(ROOT, args.base)
    if not paths and args.mode != 'full':
        print('没有待检查改动；检查已提交分支时请传入 --base。')
        return
    plan = select_checks(ROOT, paths, args.mode, previous_reader(ROOT, args.base))
    level = 'full' if plan['full'] else 'L1+' if plan['risk'] else 'L1'
    print(json.dumps({'级别': level, '改动': paths, '命令': commands(plan), '专项说明': plan['notes']},
                     ensure_ascii=False, indent=2), flush=True)
    if args.run:
        for command in commands(plan):
            subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
