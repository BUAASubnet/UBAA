#!/usr/bin/env python3
"""检查 iOS 源配置或导出 IPA 中的相册用途说明。"""
from pathlib import Path
import plistlib
import sys
import zipfile


def verify(path):
    path = Path(path)
    if path.suffix == '.ipa':
        with zipfile.ZipFile(path) as archive:
            data = archive.read('Payload/Runner.app/Info.plist')
    else:
        data = path.read_bytes()
    info = plistlib.loads(data)
    purpose = info.get('NSPhotoLibraryUsageDescription')
    if not isinstance(purpose, str) or not purpose.strip():
        raise ValueError('iOS 选图需要非空的 NSPhotoLibraryUsageDescription 用途说明')
    return info


if __name__ == '__main__':
    verify(sys.argv[1])
    print('iOS 相册用途说明检查通过')
