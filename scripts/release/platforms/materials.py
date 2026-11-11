#!/usr/bin/env python3
"""将当前平台签名 Secrets 还原到私有目录，只导出文件路径。"""
import base64
import os
from pathlib import Path
import sys

platform = sys.argv[1]
private = Path('.ubaa_local/release/signing').resolve()
private.mkdir(parents=True, exist_ok=True, mode=0o700)
os.umask(0o077)
fields = {'ANDROID_KEYSTORE_BASE64': ('android.jks', 'ANDROID_STORE_FILE')} if platform == 'android' else {
    'OHOS_KEYSTORE_BASE64': ('ohos.p12', 'OHOS_STORE_FILE'),
    'OHOS_CERTIFICATE_BASE64': ('ohos.cer', 'OHOS_CERT_FILE'),
    'OHOS_PROFILE_BASE64': ('ohos.p7b', 'OHOS_PROFILE_FILE'),
}
with Path(os.environ['GITHUB_ENV']).open('a') as output:
    for secret, (name, variable) in fields.items():
        path = private / name
        path.write_bytes(base64.b64decode(os.environ[secret]))
        output.write(f'{variable}={path}\n')
print(platform + ' 签名文件已准备')
