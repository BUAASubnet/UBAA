#!/usr/bin/env python3
"""读取 R2 上指定构建的公开清单，校验后原样写入文档站下载页数据。"""
import importlib.util
import json
from pathlib import Path
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
PUBLIC_URL = 'https://r2.ubaa.top'
OUTPUT = ROOT / 'docs/site/download.json'

_spec = importlib.util.spec_from_file_location('distribute', Path(__file__).with_name('distribute.py'))
_distribute = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_distribute)


def expected_names(version):
    return [f'UBAA-{version}-{suffix}' for suffix in _distribute.PUBLIC_SUFFIXES] + ['licenses.zip']


def validate(manifest, tag, build):
    """清单必须属于请求的版本与构建，并完整列出可下载文件的大小和地址。"""
    version = tag.removeprefix('v')
    if not tag.startswith('v') or manifest.get('version') != version:
        raise ValueError(f'清单版本 {manifest.get("version")!r} 与 {tag} 不符')
    if str(manifest.get('build')) != str(build):
        raise ValueError(f'清单构建号 {manifest.get("build")!r} 与 {build} 不符')
    assets = manifest.get('assets')
    if not isinstance(assets, list):
        raise ValueError('清单缺少 assets 列表')
    names = [asset.get('name') for asset in assets]
    if sorted(names) != sorted(expected_names(version)):
        raise ValueError('清单文件与公开安装包不一致：' + '、'.join(map(str, names)))
    prefix = f'{PUBLIC_URL}/releases/{tag}/{build}/'
    for asset in assets:
        name = asset['name']
        if not isinstance(asset.get('size'), int) or asset['size'] <= 0:
            raise ValueError(f'{name} 缺少有效大小')
        if asset.get('url') != prefix + name:
            raise ValueError(f'{name} 的下载地址不在 {prefix}')
    return manifest


def fetch(tag, build):
    url = f'{PUBLIC_URL}/releases/{tag}/{build}/release.json'
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.loads(response.read())


def main(arguments, load=fetch, output=OUTPUT):
    if len(arguments) != 2:
        raise ValueError('用法：download_manifest.py <tag> <build>，例如 v2.0.0 2004')
    tag, build = arguments
    manifest = validate(load(tag, build), tag, build)
    output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(f'下载页数据已更新为 {tag} 构建 {build}：{output.relative_to(ROOT)}')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from None
