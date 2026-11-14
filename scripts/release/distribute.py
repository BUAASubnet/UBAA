#!/usr/bin/env python3
"""准备同一候选的 GitHub Release 草稿，并生成服务器分发清单。"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib
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


# 直接下载的安装包；文档站下载页按同一组文件校验清单。
PUBLIC_SUFFIXES = (
    'android-arm64-v8a.apk', 'android-armeabi-v7a.apk', 'android-x86_64.apk',
    'windows-x64.exe', 'linux-x64.tar.gz', 'linux-arm64.tar.gz',
    'macos-arm64.dmg', 'macos-x86_64.dmg',
)


def main():
    folder = Path('.ubaa_local/release/public')
    version, tag, sha, build = (os.environ[key] for key in ('RELEASE_VERSION', 'RELEASE_TAG', 'RELEASE_SHA', 'RELEASE_BUILD'))
    names = [f'UBAA-{version}-{suffix}' for suffix in PUBLIC_SUFFIXES]
    files = [folder / name for name in names]
    public_files = [*files, folder / 'licenses.zip']
    if any(not path.is_file() or path.stat().st_size == 0 for path in public_files):
        raise ValueError('发布产物不完整')
    prepare_draft(tag, sha, version)
    public = 'https://download.ubaa.top:10443'
    prefix = f'releases/{tag}/{build}'
    assets = []
    for path in public_files:
        with path.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        url = public + '/' + urllib.parse.quote(f'{prefix}/{path.name}')
        assets.append({'name': path.name, 'size': path.stat().st_size, 'url': url, 'sha256': digest})
    manifest = folder / 'release.json'
    manifest.write_text(json.dumps({'version': version, 'build': build, 'commit': sha, 'assets': assets}, ensure_ascii=False, indent=2) + '\n')
    notes = folder.parent / 'release_notes.md'
    notes.write_text(f'UBAA {version}\n\n版本说明：https://www.ubaa.top/guide/ubaa2\n\n下载：\n\n' + '\n'.join(f'- [{asset["name"]}]({asset["url"]})' for asset in assets) + '\n')
    subprocess.run(['gh', 'release', 'upload', tag, *[str(path) for path in [*public_files, manifest]], '--clobber'], check=True)
    subprocess.run(['gh', 'release', 'edit', tag, '--notes-file', str(notes)], check=True)
    print('GitHub Release 草稿已准备完成；服务器分发通过后由维护者手动发布草稿')


def source_metadata(run_id):
    """从已通过发布验收的原始运行读取版本，重分发仍保留原产物提交。"""
    if not run_id.isdecimal():
        raise ValueError('需要有效的 Release 运行编号')
    endpoint = f'repos/{os.environ["GH_REPO"]}/actions/runs/{run_id}'
    run = json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))
    if (run['path'] != '.github/workflows/release.yml' or run['head_branch'] != 'main'
            or run['event'] != 'workflow_dispatch'):
        raise ValueError('只能重分发 main 手动 Release 的产物')
    pages = json.loads(subprocess.check_output(
        ['gh', 'api', '--paginate', '--slurp', endpoint + '/jobs?per_page=100'], text=True))
    if not any(job['name'] == 'ready' and job['conclusion'] == 'success'
               for page in pages for job in page['jobs']):
        raise ValueError('原 Release 尚未通过发布验收')
    sha = run['head_sha']
    subprocess.run(['git', 'merge-base', '--is-ancestor', sha, 'origin/main'], check=True)
    version = tomllib.loads(subprocess.check_output(['git', 'show', f'{sha}:version.toml'], text=True))
    return {'version': version['version'], 'build': version['build_number'],
            'tag': 'v' + version['version'], 'sha': sha}


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--source-run':
        values = source_metadata(sys.argv[2])
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
            for key, value in values.items():
                output.write(f'{key}={value}\n')
    else:
        main()
