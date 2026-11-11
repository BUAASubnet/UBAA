#!/usr/bin/env python3
"""从根 version.toml 同步产品版本，锁定文件交给对应包管理器刷新。"""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import tomllib

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from repo import ROOT, workspace_members


def validate(version, build):
    if not isinstance(version, str) or not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise ValueError('产品版本必须是三段数字，例如 2.0.1')
    if any(int(part) > 65535 for part in version.split('.')):
        raise ValueError('Windows 文件版本的每段数字不能超过 65535')
    if type(build) is not int or not 1 <= build <= 65535:
        raise ValueError('统一构建号必须为 1 至 65535 的整数')


def replace_one(text, pattern, replacement, path):
    if len(re.findall(pattern, text, flags=re.MULTILINE)) != 1:
        raise ValueError(f'{path} 必须恰好包含一个对应的版本字段')
    return re.sub(pattern, lambda _: replacement, text, flags=re.MULTILINE)


def declarations(version, build):
    """只更新自有包声明，保留上游插件、工具链和协议版本。"""
    result = {}

    def change(relative, pattern, replacement):
        path = ROOT / relative
        text = result.get(path, path.read_text(encoding='utf-8'))
        result[path] = replace_one(text, pattern, replacement, relative)

    change('Cargo.toml', r'^version = "[^"]+"$', f'version = "{version}"')
    members = [*workspace_members(ROOT / 'pubspec.yaml'), 'apps/ubaa_ohos']
    for member in members:
        value = f'{version}+{build}' if member.startswith('apps/') else version
        change(f'{member}/pubspec.yaml', r'^version: .+$', f'version: {value}')
    change('apps/ubaa_ohos/ohos/AppScope/app.json5', r'^    "versionName": "[^"]+",$',
           f'    "versionName": "{version}",')
    change('apps/ubaa_ohos/ohos/AppScope/app.json5', r'^    "versionCode": \d+,$',
           f'    "versionCode": {build},')
    for relative in (
        'apps/ubaa_ohos/ohos/oh-package.json5',
        'apps/ubaa_ohos/ohos/entry/oh-package.json5',
        'packages/ubaa_bindings/ohos/oh-package.json5',
        'packages/ubaa_bindings/ohos/src/main/cpp/types/libubaa_flutter_bridge/oh-package.json5',
    ):
        change(relative, r'^  "version": "[^"]+",$', f'  "version": "{version}",')
    for platform in ('ios', 'macos'):
        change(f'packages/ubaa_bindings/{platform}/ubaa_bindings.podspec',
               r"^  s\.version\s*= '[^']+'$", f"  s.version          = '{version}'")
    change('packages/ubaa_bindings/android/build.gradle', r"^version '[^']+'$",
           f"version '{version}'")
    return result


def lock_refreshes(version):
    """返回自有包版本发生变化的锁文件及其刷新命令，不升级第三方依赖。"""
    result = []
    cargo = tomllib.loads((ROOT / 'Cargo.toml').read_text(encoding='utf-8'))
    rust_names = {
        tomllib.loads((ROOT / member / 'Cargo.toml').read_text(encoding='utf-8'))['package']['name']
        for member in cargo['workspace']['members']
    }
    for relative in ('Cargo.lock', 'crates/ubaa_core/tests/compile/Cargo.lock'):
        lock = tomllib.loads((ROOT / relative).read_text(encoding='utf-8'))
        if any(package['name'] in rust_names and package.get('source') is None
               and package['version'] != version for package in lock['package']):
            command = ['cargo', 'update', '--offline', '--workspace']
            if relative != 'Cargo.lock':
                command += ['--manifest-path', str(Path(relative).with_name('Cargo.toml'))]
            result.append((relative, ROOT, command))
    for relative, project, sdk in (
        ('pubspec.lock', 'apps/ubaa_flutter', 'flutter'),
        ('apps/ubaa_ohos/pubspec.lock', 'apps/ubaa_ohos', 'flutter-ohos'),
    ):
        text = (ROOT / relative).read_text(encoding='utf-8')
        blocks = re.findall(r'^  (ubaa_\w+):\n(.*?)(?=^  \w+:|\Z)', text, re.MULTILINE | re.DOTALL)
        for _, block in blocks:
            if not re.search(r'^    source: path$', block, re.MULTILINE):
                continue
            found = re.search(r'^    version: "([^"]+)"$', block, re.MULTILINE)
            if found is None:
                raise ValueError(f'{relative} 的自有路径包缺少版本字段')
            if found[1] != version:
                result.append((relative, ROOT / project, ['just', sdk, 'pub', 'get', '--offline']))
                break
    for platform in ('ios', 'macos'):
        relative = f'apps/ubaa_flutter/{platform}/Podfile.lock'
        text = (ROOT / relative).read_text(encoding='utf-8')
        found = re.search(r'^  - ubaa_bindings \(([^)]+)\):$', text, re.MULTILINE)
        if found is None:
            raise ValueError(f'{relative} 缺少 ubaa_bindings 的锁定版本')
        if found[1] != version:
            result.append((relative, ROOT / f'apps/ubaa_flutter/{platform}',
                           ['pod', 'update', 'ubaa_bindings', '--no-repo-update']))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version', nargs='?', default='')
    parser.add_argument('build', nargs='?', default='')
    parser.add_argument('--check', action='store_true', help='只读核对声明与锁文件')
    args = parser.parse_args()
    if bool(args.version) != bool(args.build):
        raise ValueError('更新版本时同时提供版本号和构建号，例如 just version 2.0.1 2004')
    if args.check and args.version:
        raise ValueError('只读检查不接受新的版本参数')
    config_path = ROOT / 'version.toml'
    source = config_path.read_text(encoding='utf-8')
    config = tomllib.loads(source)
    version = args.version or config['version']
    if args.build and not args.build.isdecimal():
        raise ValueError('构建号必须是整数，例如 2004')
    build = int(args.build) if args.build else config['build_number']
    validate(version, build)
    config_text = source
    if args.version:
        config_text = replace_one(source, r'^[ \t]*version\s*=.*$', f'version = "{version}"', 'version.toml')
        config_text = replace_one(config_text, r'^[ \t]*build_number\s*=.*$', f'build_number = {build}', 'version.toml')
    pending = {config_path: config_text, **declarations(version, build)}
    changed = {path: text for path, text in pending.items() if path.read_text(encoding='utf-8') != text}
    refreshes = lock_refreshes(version)
    if args.check:
        mismatches = [str(path.relative_to(ROOT)) for path in changed] + [path for path, _, _ in refreshes]
        if mismatches:
            raise ValueError('产品版本未同步，请运行 just version：\n' + '\n'.join(mismatches))
        print(f'产品版本一致：{version}+{build}')
        return
    for path, text in changed.items():
        path.write_text(text, encoding='utf-8')
    if any(command[0] == 'pod' for _, _, command in refreshes):
        # Flutter 为新 checkout 准备 Apple 平台配置及插件链接，不运行构建。
        subprocess.run(['just', 'flutter', 'pub', 'get', '--offline'],
                       cwd=ROOT / 'apps/ubaa_flutter', check=True)
    for relative, cwd, command in refreshes:
        print(f'刷新版本锁定：{relative}', flush=True)
        subprocess.run(command, cwd=cwd, check=True)
    print(f'产品版本已同步：{version}+{build}，更新 {len(changed)} 个声明文件、{len(refreshes)} 个锁文件')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit('版本声明已保存，锁文件刷新尚未完成；处理工具错误后重跑 just version。') from error
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error)) from None
