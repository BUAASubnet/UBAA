#!/usr/bin/env python3
"""准备同一候选的 GitHub Release 草稿，并分发和验证 R2 下载产物。"""
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import subprocess
import urllib.parse
import urllib.request


def prepare_draft(tag, sha, version):
    """草稿只在确认不存在时创建；已存在的草稿改到当前候选，已发布版本拒绝写入。"""
    existing = subprocess.run(['gh', 'release', 'view', tag, '--json', 'isDraft,targetCommitish'],
                              capture_output=True, text=True)
    if existing.returncode:
        if 'release not found' not in existing.stderr:
            raise RuntimeError('无法确认 GitHub Release 状态：' + existing.stderr.strip())
        subprocess.run(['gh', 'release', 'create', tag, '--draft', '--target', sha,
                        '--title', 'UBAA ' + version, '--notes', ''], check=True)
        return
    release = json.loads(existing.stdout)
    if not release['isDraft']:
        raise ValueError('GitHub Release 已发布，不能覆盖正式产物；请使用新版本')
    if release['targetCommitish'] != sha:
        subprocess.run(['gh', 'release', 'edit', tag, '--target', sha], check=True)


def r2_digest(bucket, key, endpoint):
    """返回 R2 已有对象记录的 SHA-256；对象不存在时返回 None。"""
    head = subprocess.run(['aws', 's3api', 'head-object', '--bucket', bucket, '--key', key,
                           '--endpoint-url', endpoint, '--region', 'auto'], capture_output=True, text=True)
    if head.returncode == 0:
        return json.loads(head.stdout).get('Metadata', {}).get('sha256', '')
    if '(404)' in head.stderr:
        return None
    raise RuntimeError(f'无法确认 R2 对象 {key} 的状态：' + head.stderr.strip())


def main():
    folder = Path('.ubaa_local/release/public')
    version, tag, sha, build = (os.environ[key] for key in ('RELEASE_VERSION', 'RELEASE_TAG', 'RELEASE_SHA', 'RELEASE_BUILD'))
    names = [f'UBAA-{version}-{suffix}' for suffix in (
        'android-arm64-v8a.apk', 'android-armeabi-v7a.apk', 'android-x86_64.apk',
        'windows-x64.exe', 'linux-x64.tar.gz', 'linux-arm64.tar.gz',
        'macos-arm64.dmg', 'macos-x86_64.dmg', 'harmonyos-arm64.app',
    )]
    files = [folder / name for name in names]
    if any(not path.is_file() or path.stat().st_size == 0 for path in files):
        raise ValueError('发布产物不完整')
    prepare_draft(tag, sha, version)
    endpoint = f"https://{os.environ['CLOUDFLARE_ACCOUNT_ID']}.r2.cloudflarestorage.com"
    bucket, public = os.environ['R2_BUCKET'], os.environ['R2_PUBLIC_URL'].rstrip('/')
    # 产物带一年 immutable 缓存，同一路径只能写入一次；路径含构建号，新候选递增构建号后写入新路径。
    prefix = f'releases/{tag}/{build}'
    assets = []
    for path in [*files, folder / 'licenses.zip']:
        key = f'{prefix}/{path.name}'
        with path.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        existing = r2_digest(bucket, key, endpoint)
        if existing is None:
            subprocess.run(['aws', 's3', 'cp', str(path), f's3://{bucket}/{key}', '--endpoint-url', endpoint,
                            '--region', 'auto', '--only-show-errors', '--content-type',
                            mimetypes.guess_type(path.name)[0] or 'application/octet-stream',
                            '--cache-control', 'public, max-age=31536000, immutable',
                            '--content-disposition', f'attachment; filename="{path.name}"',
                            '--metadata', f'sha256={digest}'], check=True)
        elif existing != digest:
            raise ValueError(f'R2 的 {key} 已分发其他内容；已分发的构建号不能复用，请递增构建号')
        url = public + '/' + urllib.parse.quote(key)
        with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=60) as response:
            if int(response.headers['Content-Length']) != path.stat().st_size:
                raise ValueError(f'{path.name} 的公开下载长度不符')
        with urllib.request.urlopen(urllib.request.Request(url, headers={'Range': 'bytes=0-4095'}), timeout=60) as response:
            downloaded = response.read(4096)
        with path.open('rb') as source:
            if downloaded != source.read(4096):
                raise ValueError(f'{path.name} 的公开下载内容不符')
        assets.append({'name': path.name, 'size': path.stat().st_size, 'url': url})
        print('R2 下载验证通过：' + path.name, flush=True)
    manifest = folder / 'release.json'
    manifest.write_text(json.dumps({'version': version, 'build': build, 'commit': sha, 'assets': assets}, ensure_ascii=False, indent=2) + '\n')
    subprocess.run(['aws', 's3', 'cp', str(manifest), f's3://{bucket}/{prefix}/release.json', '--endpoint-url', endpoint, '--region', 'auto', '--only-show-errors', '--content-type', 'application/json'], check=True)
    notes = folder.parent / 'release_notes.md'
    notes.write_text(f'UBAA {version}\n\n版本说明：https://www.ubaa.top/guide/ubaa2\n\n下载：\n\n' + '\n'.join(f'- [{asset["name"]}]({asset["url"]})' for asset in assets) + '\n')
    subprocess.run(['gh', 'release', 'upload', tag, *[str(path) for path in folder.iterdir() if path.is_file()], '--clobber'], check=True)
    subprocess.run(['gh', 'release', 'edit', tag, '--notes-file', str(notes)], check=True)
    print('GitHub Release 草稿与 R2 产物已准备完成；请在工作流全部成功后手动发布草稿')


if __name__ == '__main__':
    main()
