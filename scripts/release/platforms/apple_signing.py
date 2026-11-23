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

PRIVATE = Path(os.environ['RUNNER_TEMP']) / 'ubaa_release_signing'
IOS_PROFILES = (
    ('cn.edu.ubaa', 'IOS_PROVISIONING_PROFILE_BASE64', 'IOS_PROFILE_UUID'),
    ('cn.edu.ubaa.widget', 'IOS_WIDGET_PROVISIONING_PROFILE_BASE64', 'IOS_WIDGET_PROFILE_UUID'),
)


def security(*args):
    result = subprocess.run(['security', '-i'], input=shlex.join(args) + '\n', text=True,
                            capture_output=True)
    if result.returncode or 'SecKeychain' in result.stderr or 'SecItem' in result.stderr:
        raise RuntimeError('临时 Keychain 操作失败，请检查签名材料')


def validate_ios_profile(profile, team, bundle):
    entitlements = profile.get('Entitlements', {})
    if entitlements.get('application-identifier') != f'{team}.{bundle}':
        raise ValueError(f'{bundle} 的 iOS Profile 应用或 Team 不匹配')
    if entitlements.get('get-task-allow') or 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices'):
        raise ValueError(f'{bundle} 必须使用 App Store Profile')
    if 'group.cn.edu.ubaa' not in entitlements.get('com.apple.security.application-groups', []):
        raise ValueError(f'{bundle} 的 iOS Profile 缺少 App Group group.cn.edu.ubaa')


def install_ios_profiles(team, identity, values):
    profiles = {}
    copies = {}
    profile_directory = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
    for bundle, secret, variable in IOS_PROFILES:
        profile_file = PRIVATE / f'{bundle}.mobileprovision'
        profile_file.write_bytes(base64.b64decode(os.environ[secret]))
        decoded = subprocess.run(['security', 'cms', '-D', '-i', str(profile_file)], capture_output=True)
        if decoded.returncode:
            raise ValueError(f'无法解码 {secret} 中的 iOS Profile')
        profile = plistlib.loads(decoded.stdout)
        validate_ios_profile(profile, team, bundle)
        uuid = profile['UUID']
        profiles[bundle] = values[variable] = uuid
        copies[profile_file] = profile_directory / f'{uuid}.mobileprovision'
    profile_directory.mkdir(parents=True, exist_ok=True)
    (PRIVATE / 'installed_profiles.json').write_text(json.dumps([str(path) for path in copies.values()]))
    for source, installed in copies.items():
        shutil.copy2(source, installed)
    options = {'method': 'app-store-connect', 'destination': 'export', 'signingStyle': 'manual',
               'teamID': team, 'signingCertificate': identity, 'provisioningProfiles': profiles,
               'manageAppVersionAndBuildNumber': False, 'stripSwiftSymbols': True, 'uploadSymbols': True}
    (PRIVATE / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))


def prepare(platform):
    if platform == 'ios':
        for bundle, secret, _ in IOS_PROFILES:
            if not os.environ.get(secret, '').strip():
                raise ValueError(f'缺少 {secret}，请为 {bundle} 配置 App Store Profile secret')
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
        install_ios_profiles(team, identity[0], values)
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
    profiles = PRIVATE / 'installed_profiles.json'
    if profiles.exists():
        for path in json.loads(profiles.read_text()):
            Path(path).unlink(missing_ok=True)
    shutil.rmtree(PRIVATE, ignore_errors=True)


if __name__ == '__main__':
    if sys.argv[1] == 'cleanup':
        cleanup()
    else:
        prepare(sys.argv[1])
