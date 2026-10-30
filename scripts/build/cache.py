#!/usr/bin/env python3
"""查看并按范围清理仓库内可重建的构建缓存；默认只显示占用，不删除。

只处理下表登记、被 Git 忽略且不含受跟踪文件的真实目录。`.ubaa_local`、
运行会话、冻结引用和仓库外的工具链缓存都不在清理范围内。
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True

SCOPES = {
    'rust-incremental': ('全部 Cargo 目录的增量缓存，删除后只影响下次编译速度', [
        'target/**/incremental', 'apps/ubaa_flutter/build/**/incremental',
        'packages/ubaa_bindings/ohos/.cxx/**/incremental']),
    'rust': ('根目录 Rust 全部产物（含依赖）', ['target']),
    'flutter-macos': ('macOS 宿主与其 Rust 产物', ['apps/ubaa_flutter/build/macos']),
    'flutter-ios': ('iOS 宿主与其 Rust 产物', ['apps/ubaa_flutter/build/ios']),
    'flutter-android': ('Android 宿主与其 Rust 产物', [
        'apps/ubaa_flutter/build/app', 'apps/ubaa_flutter/build/ubaa_bindings']),
    'flutter-linux': ('Linux 宿主与其 Rust 产物', ['apps/ubaa_flutter/build/linux']),
    'flutter-windows': ('Windows 宿主与其 Rust 产物', ['apps/ubaa_flutter/build/windows']),
    'flutter-test': ('Flutter 测试缓存', [
        'apps/ubaa_flutter/build/test_cache', 'apps/ubaa_flutter/build/unit_test_assets',
        'packages/*/build']),
    'ohos': ('OHOS 宿主、HAR 与其 Rust 产物', [
        'packages/ubaa_bindings/ohos/.cxx', 'packages/*/ohos/build',
        'apps/ubaa_ohos/build', 'apps/ubaa_ohos/ohos/build', 'apps/ubaa_ohos/ohos/entry/build']),
}
# 只显示、不清理：可能含运行日志或验收记录，由使用者自行判断。
REPORT_ONLY = {'.ubaa_local': '本地日志与验收记录（只显示，不清理）'}


def directories(root, patterns):
    found = []
    for pattern in patterns:
        for path in sorted(root.glob(pattern)):
            # ** 也会匹配 Gradle 等工具的同名目录，只认 Cargo profile 目录下的增量缓存。
            if path.name == 'incremental' and '**' in pattern and not (path.parent / '.fingerprint').is_dir():
                continue
            if path.is_dir() or path.is_symlink():
                found.append(path)
    # 父目录已入选时不再重复计入子目录。
    found = sorted(set(found))
    return [path for path in found if not any(other != path and other in path.parents for other in found)]


def disk_usage(path, seen):
    total = 0
    for current, names, files in os.walk(path, followlinks=False):
        for name in names + files:
            stat = os.lstat(os.path.join(current, name))
            if (stat.st_dev, stat.st_ino) not in seen:
                seen.add((stat.st_dev, stat.st_ino))
                total += stat.st_blocks * 512
    return total


def human(size):
    for unit in ('B', 'KiB', 'MiB', 'GiB'):
        if size < 1024 or unit == 'GiB':
            return f'{size:.1f} {unit}' if unit != 'B' else f'{size} B'
        size /= 1024
    return f'{size:.1f} GiB'


def git(root, *args):
    return subprocess.run(['git', '-C', str(root), *args], capture_output=True, text=True)


def refusal(root, path):
    """返回拒绝删除的原因；可以删除时返回 None。"""
    if path.is_symlink() or not path.is_dir():
        return '不是真实目录'
    resolved = path.resolve()
    if resolved == root or root not in resolved.parents:
        return '不在仓库内'
    relative = str(path.relative_to(root))
    if git(root, 'ls-files', '--', relative).stdout.strip():
        return '包含受跟踪文件'
    if git(root, 'check-ignore', '-q', '--no-index', relative).returncode != 0:
        return '没有被 Git 忽略'
    return None


def show(root):
    print(f'{"范围":<18}{"占用":>12}  说明')
    for name, (description, patterns) in SCOPES.items():
        # 范围之间可能重叠（如 rust 含 rust-incremental），各自独立计算，合计去重。
        paths = [path for path in directories(root, patterns) if not path.is_symlink()]
        size = sum(disk_usage(path, set()) for path in paths)
        print(f'{name:<18}{human(size):>12}  {description}')
    total = 0
    for path in directories(root, [pattern for _, patterns in SCOPES.values() for pattern in patterns]):
        if not path.is_symlink():
            total += disk_usage(path, set())
    for name, description in REPORT_ONLY.items():
        path = root / name
        size = disk_usage(path, set()) if path.is_dir() else 0
        print(f'{name:<18}{human(size):>12}  {description}')
    print(f'{"可清理合计":<16}{human(total):>12}')
    print('清理：just cache-clean <范围…>，例如 just cache-clean rust-incremental ohos')


def clean(root, scopes):
    unknown = [scope for scope in scopes if scope not in SCOPES]
    if not scopes or unknown:
        raise SystemExit('请指定清理范围：' + '、'.join(SCOPES) + (f'；未知范围：{"、".join(unknown)}' if unknown else ''))
    targets = directories(root, [pattern for scope in scopes for pattern in SCOPES[scope][1]])
    problems = [f'{path.relative_to(root)}：{reason}' for path in targets
                if (reason := refusal(root, path)) is not None]
    if problems:
        # 任一目录不安全时整体放弃，避免只清理一半。
        raise SystemExit('拒绝清理，未删除任何目录：\n' + '\n'.join(problems))
    seen = set()
    freed = 0
    for path in targets:
        freed += disk_usage(path, seen)
        shutil.rmtree(path)
        print(f'已删除 {path.relative_to(root)}')
    print(f'释放约 {human(freed)}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default=str(Path(__file__).resolve().parents[2]), help=argparse.SUPPRESS)
    parser.add_argument('action', nargs='?', choices=['show', 'clean'], default='show')
    parser.add_argument('scopes', nargs='*')
    args = parser.parse_args()
    root = Path(args.root).resolve()
    if args.action == 'show':
        show(root)
    else:
        clean(root, args.scopes)


if __name__ == '__main__':
    main()
