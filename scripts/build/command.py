#!/usr/bin/env python3
"""构建共同命令入口；Linux 只编译 Dart AOT、Rust 和 Secret Service 适配。"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from toolchain import load_environment
from repo import ROOT


def run(arguments, environment):
    subprocess.run(arguments, cwd=ROOT, env=environment, check=True)


def compile_linux(output, environment, mode, *, standalone=False):
    (output / 'lib').mkdir(parents=True, exist_ok=True)
    flags = subprocess.check_output(['pkg-config', '--cflags', '--libs', 'libsecret-1'], text=True).split()
    run(['c++', '-std=c++17', '-fPIC', '-shared', '-fvisibility=hidden',
         str(ROOT / 'packages/ubaa_platform/native/linux/command_materials.cc'),
         '-o', str(output / 'lib/libubaa_command_materials.so'), *flags], environment)
    defines = [f'-DUBAA_COMMAND_RELEASE={str(mode == "release").lower()}']
    for name in ('UBAA_APP_SERVICE_URL', 'UBAA_DISTRIBUTION_CHANNEL'):
        if value := environment.get(name):
            defines.append(f'-D{name}={value}')
    if standalone:
        metadata = (ROOT / 'apps/ubaa_flutter/pubspec.yaml').read_text(encoding='utf-8')
        if version := re.search(r'^version:\s*(\S+)', metadata, re.MULTILINE):
            defines.append(f'-DUBAA_COMMAND_APP_VERSION={version[1]}')
    run(['just', 'dart', 'compile', 'exe', '--packages=.dart_tool/package_config.json',
         *defines, 'apps/ubaa_flutter/bin/ubaa.dart', '-o', str(output / 'ubaa')], environment)
    print(f'命令入口：{output / "ubaa"}')


def main():
    platform = sys.argv[1] if len(sys.argv) > 1 else 'host'
    mode = sys.argv[2] if len(sys.argv) > 2 else 'release'
    if platform == 'host':
        platform = {'darwin': 'macos', 'win32': 'windows', 'linux': 'linux'}[sys.platform]
    if mode not in {'debug', 'release'}:
        raise ValueError('命令构建仅接受 debug 或 release')
    environment = load_environment()
    if platform == 'linux-bundle':
        if sys.platform != 'linux' or len(sys.argv) != 4:
            raise ValueError('Linux App 组装需要本机 bundle 目录')
        output = Path(sys.argv[3]).resolve()
        if not (output / 'lib/libubaa_flutter_bridge.so').is_file():
            raise ValueError('Linux App 缺少已构建的 Rust 库')
        compile_linux(output, environment, mode)
        return
    if platform in {'macos', 'windows'}:
        run(['just', 'flutter-build', f'platform={platform}', f'mode={mode}'], environment)
        if platform == 'macos':
            output = ROOT / 'build/command/macos'
            source = ROOT / 'apps/ubaa_flutter/build/macos/Build/Products' / mode.title() / 'UBAA.app'
            output.mkdir(parents=True, exist_ok=True)
            destination = output / 'UBAA.app'
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(source, destination, symlinks=True)
            launcher = output / 'ubaa'
            launcher.write_text('#!/bin/sh\nexec "$(dirname "$0")/UBAA.app/Contents/MacOS/UBAA" --command "$@"\n')
            launcher.chmod(0o755)
        return
    if platform != 'linux' or sys.platform != 'linux':
        raise ValueError('Linux 命令在 Linux 主机或容器中构建')
    output = Path(environment.get('UBAA_COMMAND_BUILD_DIR', ROOT / 'build/command/linux')).resolve()
    (output / 'lib').mkdir(parents=True, exist_ok=True)
    cargo = ['cargo', 'build', '--locked', '-p', 'ubaa_flutter_bridge']
    if mode == 'release':
        cargo.append('--release')
    run(cargo, environment)
    target = Path(environment.get('CARGO_TARGET_DIR', ROOT / 'target'))
    shutil.copy2(target / mode / 'libubaa_flutter_bridge.so', output / 'lib')
    compile_linux(output, environment, mode, standalone=True)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
