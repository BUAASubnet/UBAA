#!/usr/bin/env python3
"""在发布 runner 的临时 Keychain 中准备 Apple 身份，密码只经 stdin 传递。"""
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
PRIVATE = ROOT / '.ubaa_local/release/signing'


def security(*args):
    result = subprocess.run(['security', '-i'], input=shlex.join(args) + '\n', text=True,
                            capture_output=True)
    if result.returncode or 'SecKeychain' in result.stderr or 'SecItem' in result.stderr:
        raise RuntimeError('临时 Keychain 操作失败，请检查签名材料')


def prepare(platform):
    os.umask(0o077)
    PRIVATE.mkdir(parents=True, exist_ok=True)
    prefix = 'IOS' if platform == 'ios' else 'MACOS'
    certificate = PRIVATE / 'certificate.p12'
    certificate.write_bytes(base64.b64decode(os.environ[prefix + '_CERTIFICATE_P12_BASE64']))
    keychain = PRIVATE / 'release.keychain-db'
    password = secrets.token_hex(24)
    original = subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True)
    (PRIVATE / 'keychains.json').write_text(json.dumps(shlex.split(original)))
    security('create-keychain', '-p', password, str(keychain))
    security('set-keychain-settings', '-lut', '21600', str(keychain))
    security('unlock-keychain', '-p', password, str(keychain))
    security('import', str(certificate), '-P', os.environ[prefix + '_CERTIFICATE_PASSWORD'],
             '-k', str(keychain), '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
    security('set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain))
    security('list-keychains', '-d', 'user', '-s', str(keychain), *shlex.split(original))
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)], text=True)
    kind = 'Apple Distribution:' if platform == 'ios' else 'Developer ID Application:'
    identity = next((item for item in re.findall(r'^\s*\d+\)\s+([A-F0-9]{40}) "([^"]+)"\s*$', identities, re.MULTILINE) if item[1].startswith(kind)), None)
    if not identity:
        raise ValueError('P12 中没有可用的 ' + kind)
    team = re.search(r'\(([A-Z0-9]+)\)$', identity[1])[1]
    certificate.unlink()
    key = os.environ['APPSTORE_PRIVATE_KEY']
    if 'BEGIN PRIVATE KEY' not in key:
        key = base64.b64decode(key).decode()
    (PRIVATE / ('AuthKey_' + os.environ['APPSTORE_KEY_ID'] + '.p8')).write_text(key)
    values = {'APPLE_SIGNING_IDENTITY': identity[0], 'APPLE_TEAM_ID': team,
              'API_PRIVATE_KEYS_DIR': str(PRIVATE), 'APPLE_KEYCHAIN': str(keychain)}
    if platform == 'ios':
        profile_file = PRIVATE / 'profile.mobileprovision'
        profile_file.write_bytes(base64.b64decode(os.environ['IOS_PROVISIONING_PROFILE_BASE64']))
        profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(profile_file)]))
        if profile['Entitlements']['application-identifier'] != team + '.cn.edu.ubaa':
            raise ValueError('iOS Profile 的应用或 Team 不匹配')
        if profile['Entitlements'].get('get-task-allow') or 'ProvisionedDevices' in profile:
            raise ValueError('iOS 必须使用 App Store Profile')
        installed = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles' / (profile['UUID'] + '.mobileprovision')
        installed.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(profile_file, installed)
        (PRIVATE / 'installed_profile.txt').write_text(str(installed))
        options = {'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'manual',
                   'teamID': team, 'signingCertificate': identity[0], 'provisioningProfiles': {'cn.edu.ubaa': profile['UUID']},
                   'manageAppVersionAndBuildNumber': False, 'stripSwiftSymbols': True, 'uploadSymbols': True}
        (PRIVATE / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
        values['IOS_PROFILE_UUID'] = profile['UUID']
    with Path(os.environ['GITHUB_ENV']).open('a') as output:
        for key, value in values.items():
            output.write(f'{key}={value}\n')
    print(platform + ' 发布签名材料已准备')


def cleanup():
    original = PRIVATE / 'keychains.json'
    if original.exists():
        security('list-keychains', '-d', 'user', '-s', *json.loads(original.read_text()))
    keychain = PRIVATE / 'release.keychain-db'
    if keychain.exists():
        security('delete-keychain', str(keychain))
    profile = PRIVATE / 'installed_profile.txt'
    if profile.exists():
        Path(profile.read_text()).unlink(missing_ok=True)
    shutil.rmtree(PRIVATE, ignore_errors=True)


if __name__ == '__main__':
    if sys.argv[1] == 'cleanup':
        cleanup()
    else:
        prepare(sys.argv[1])
