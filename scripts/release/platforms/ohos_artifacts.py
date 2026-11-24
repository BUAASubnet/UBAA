#!/usr/bin/env python3
"""收集 HarmonyOS 商店包及其内含的签名 HAP。"""
import os
from pathlib import Path
import shutil
import zipfile


def collect(build, output, version):
    apps = list(build.rglob('*-signed.app'))
    if len(apps) != 1:
        raise ValueError('未生成唯一的签名 APP')
    with zipfile.ZipFile(apps[0]) as archive:
        haps = [name for name in archive.namelist() if name.endswith('.hap')]
        if len(haps) != 1:
            raise ValueError('签名 APP 中未包含唯一的 HAP')
        public = output / 'public'
        public.mkdir(parents=True, exist_ok=True)
        with archive.open(haps[0]) as source, (public / f'UBAA-{version}-harmonyos-arm64.hap').open('wb') as target:
            shutil.copyfileobj(source, target)
    store = output / 'store'
    store.mkdir(parents=True, exist_ok=True)
    shutil.copy2(apps[0], store / f'UBAA-{version}-harmonyos-arm64.app')


if __name__ == '__main__':
    collect(Path('apps/ubaa_ohos/build/ohos'), Path('dist/release'), os.environ['RELEASE_VERSION'])
