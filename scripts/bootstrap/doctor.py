#!/usr/bin/env python3
"""只读汇总本机工具与锁定版本的差异；不联网、不安装、不输出本机路径。"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from environment import read_values
from repo import ROOT
from toolchain import deveco_environment, load_environment


def run(command, cwd=ROOT, env=None):
    try:
        result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


def find(name, environment, override=None):
    if override and environment.get(override):
        return environment[override]
    search = os.pathsep.join([environment.get('PATH', ''), str(Path.home() / '.cargo/bin')])
    return shutil.which(name, path=search)


def version_of(executable, pattern):
    output = run([executable, '--version']) if executable else None
    match = re.search(pattern, output or '')
    return match[1] if match else None


def git_head(path):
    if not path or not Path(path).is_dir():
        return None
    output = run(['git', '-C', path, 'rev-parse', 'HEAD'])
    return output.strip() if output else None


def ohos_local_properties(environment):
    """DevEco 直接构建只读 local.properties；它必须与 .env.toolchain 指向同一组 SDK。"""
    path = ROOT / 'apps/ubaa_ohos/ohos/local.properties'
    if not path.is_file() or not environment.get('UBAA_OHOS_FLUTTER_HOME'):
        return None
    values = dict(line.split('=', 1) for line in path.read_text().splitlines() if '=' in line)
    try:
        expected_sdk = deveco_environment(environment).get('DEVECO_SDK_HOME')
    except ValueError:
        return None
    same = lambda a, b: bool(a and b) and Path(a).resolve() == Path(b).resolve()
    if same(values.get('flutter.sdk'), environment['UBAA_OHOS_FLUTTER_HOME']) and \
            same(values.get('hwsdk.dir'), expected_sdk):
        return '一致'
    return '不一致'


def collect(environment, pins):
    """返回 (名称, 是否必需, 期望, 实际)；实际为 None 表示缺失。"""
    rust = run(['rustup', 'toolchain', 'list'])
    rust_actual = pins['RUST_VERSION'] if rust and re.search(
        rf'^{re.escape(pins["RUST_VERSION"])}-', rust, re.M) else None
    node = version_of(find('node', environment), r'v(\d+)\.')
    quality = run(['bash', str(ROOT / 'scripts/tools/python.sh'), '-c', 'pass'], env=environment)
    short = lambda commit: commit[:12] if commit else None
    rows = [
        ('just', True, pins['JUST_VERSION'], version_of(find('just', environment), r'just (\S+)')),
        ('Rust 工具链', True, pins['RUST_VERSION'], rust_actual),
        ('Python', True, '3.11+', '.'.join(map(str, sys.version_info[:2])) if sys.version_info >= (3, 11) else None),
        ('Python 质量环境', True, '已准备', '已准备' if quality is not None else None),
        ('官方 Flutter', True, short(pins['FLUTTER_COMMIT']), short(git_head(environment.get('UBAA_FLUTTER_HOME')))),
        ('FRB codegen', True, pins['FRB_VERSION'],
         version_of(find('flutter_rust_bridge_codegen', environment, 'UBAA_FRB_CODEGEN'), r'codegen (\S+)')),
        ('cargo-expand', True, pins['CARGO_EXPAND_VERSION'],
         version_of(find('cargo-expand', environment), r'cargo-expand (\S+)')),
        ('ShellCheck', True, pins['SHELLCHECK_VERSION'],
         version_of(find('shellcheck', environment, 'UBAA_SHELLCHECK_BIN'), r'version: (\S+)')),
        ('cargo-deny', False, pins['CARGO_DENY_VERSION'],
         version_of(find('cargo-deny', environment), r'cargo-deny (\S+)')),
        ('Node.js', True, pins['NODE_VERSION'] + '+', node),
        ('OHOS Flutter', False, short(pins['OHOS_FLUTTER_COMMIT']),
         short(git_head(environment.get('UBAA_OHOS_FLUTTER_HOME')))),
        ('OHOS local.properties', False, '一致', ohos_local_properties(environment)),
        ('DevEco', False, '已配置', '已配置' if environment.get('UBAA_DEVECO_HOME')
         and Path(environment['UBAA_DEVECO_HOME']).is_dir() else None),
    ]
    for label, key in (('冻结引用 ubaa_old', 'UBAA_OLD_COMMIT'), ('冻结引用 buaa-api', 'BUAA_API_COMMIT')):
        path = ROOT / 'examples' / ('ubaa_old' if 'old' in label else 'buaa-api')
        rows.append((label, True, short(pins[key]), short(git_head(str(path)))))
    return rows


def matches(expected, actual):
    if actual is None:
        return False
    if expected.endswith('+'):
        number = lambda text: tuple(int(part) for part in re.findall(r'\d+', text))
        return number(actual) >= number(expected)
    return actual == expected


def main():
    pins = read_values(ROOT / 'scripts/tools/versions.env')
    rows = collect(load_environment(), pins)
    failed = 0
    width = max(len(name) for name, *_ in rows)
    for name, required, expected, actual in rows:
        ok = matches(expected, actual)
        mark = '✓' if ok else ('✗' if required else '-')
        failed += required and not ok
        print(f'{mark} {name:<{width}}  期望 {expected:<14} 实际 {actual or "缺失"}')
    if any(name == 'OHOS local.properties' and actual == '不一致' for name, _, _, actual in rows):
        print('OHOS local.properties 与 .env.toolchain 不一致：检查 flutter-ohos config --ohos-sdk，'
              '然后在 apps/ubaa_ohos 运行 just flutter-ohos pub get', file=sys.stderr)
    if failed:
        print(f'{failed} 项必需工具不符；运行 just setup 或按 docs/development/setup.md 安装', file=sys.stderr)
        return 1
    print('必需工具均与锁定版本一致；- 表示可选项未就绪')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
