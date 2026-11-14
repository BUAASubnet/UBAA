#!/usr/bin/env python3
"""服务器固定部署入口，仅接收部署密钥通过标准输入传入的运行描述。"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

ROOT = Path('/srv/ubaa')
STATE = Path('/var/lib/ubaa')


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def atomic_json(path, data):
    temporary = path.with_suffix('.pending')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


def point(link, target):
    temporary = link.with_name(link.name + '.pending')
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    temporary.replace(link)


def download(url, destination):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or not (
        parsed.hostname.endswith('.blob.core.windows.net')
        or parsed.hostname.endswith('.githubusercontent.com')):
        raise ValueError('不是 GitHub 产物下载地址')
    # 临时签名地址仅走 stdin，日志与进程参数不包含签名。
    run('curl', '--noproxy', '*', '--fail', '--silent', '--show-error', '--location',
        '--connect-timeout', '20', '--max-time', '1800', '--retry', '3',
        '--config', '-', '--output', str(destination),
        input='url = ' + json.dumps(url) + '\n', text=True)


def extract(artifacts, folder):
    for index, artifact in enumerate(artifacts):
        archive = folder / f'{index}.zip'
        download(artifact['url'], archive)
        with zipfile.ZipFile(archive) as package:
            for entry in package.infolist():
                path = Path(entry.filename)
                if path.is_absolute() or '..' in path.parts:
                    raise ValueError('无效的产物路径')
                if entry.is_dir():
                    continue
                target = folder / path
                if target.exists():
                    raise ValueError('产物包含重复路径')
                target.parent.mkdir(parents=True, exist_ok=True)
                with package.open(entry) as source, target.open('wb') as output:
                    shutil.copyfileobj(source, output)
        archive.unlink()


def healthy():
    for _ in range(20):
        try:
            with urllib.request.urlopen('http://127.0.0.1:10080/healthz', timeout=2) as response:
                if response.status == 200:
                    return True
        except OSError:
            pass
        time.sleep(1)
    return False


def application(folder, identifier):
    destination = ROOT / 'app_service' / identifier
    destination.mkdir(parents=True, exist_ok=False)
    with tarfile.open(folder / 'app_service.tar.gz') as package:
        package.extractall(destination, filter='data')
    run('chown', '-R', 'ubaa:ubaa', str(destination))
    run('runuser', '-u', 'ubaa', '--', 'npm', 'ci', '--omit=dev', '--no-audit', '--no-fund', cwd=destination)
    run('systemd-run', '--quiet', '--wait', '--pipe', '--collect',
        '--property=User=ubaa', '--property=EnvironmentFile=/etc/ubaa/service.env',
        '/usr/local/bin/node', str(destination / '.generated/build/server.js'), '--migrate')
    publisher = folder / 'bhpan-publish'
    if publisher.exists():
        run('install', '-m', '755', str(publisher), '/opt/ubaa/bin/bhpan-publish')
    link = ROOT / 'app_service/current'
    previous = link.resolve() if link.exists() else None
    content_path = STATE / 'content.json'
    previous_content = content_path.read_text() if content_path.exists() else None
    content = json.loads((destination / 'content.json').read_text())
    published = STATE / 'published.json'
    if published.exists() and previous_content:
        content['channels']['github'] = json.loads(previous_content)['channels']['github']
    atomic_json(content_path, content)
    run('chown', 'ubaa:ubaa', str(content_path))
    point(link, destination)
    run('systemctl', 'restart', 'ubaa-app.service')
    if not healthy():
        if previous_content:
            content_path.write_text(previous_content)
        if previous:
            point(link, previous)
            run('systemctl', 'restart', 'ubaa-app.service')
        raise RuntimeError('新服务健康检查失败，已恢复原应用版本')
    run('install', '-m', '755', str(destination / 'deploy.py'), '/usr/local/lib/ubaa/deploy.py')


def docs(folder, identifier):
    destination = ROOT / 'docs' / identifier
    shutil.move(str(folder), destination)
    # 缓存中的旧 HTML 仍会引用旧摘要文件，静态资源跨版本保留。
    shutil.copytree(destination / 'assets', ROOT / 'docs/assets', dirs_exist_ok=True)
    run('chmod', '-R', 'a+rX', str(ROOT / 'docs/assets'))
    run('chmod', '-R', 'a+rX', str(destination))
    point(ROOT / 'docs/current', destination)


def release(folder, manifest):
    version, build = manifest['version'], str(manifest['build'])
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not build.isdecimal():
        raise ValueError('无效的发布版本')
    destination = ROOT / 'downloads/releases' / ('v' + version) / build
    destination.mkdir(parents=True, exist_ok=True)
    for asset in manifest['assets']:
        name = asset['name']
        if Path(name).name != name:
            raise ValueError('无效文件名')
        matches = list(folder.rglob(name))
        if len(matches) != 1:
            raise ValueError('发布产物不完整')
        source = matches[0]
        for candidate in [source, *([destination / name] if (destination / name).exists() else [])]:
            with candidate.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            if candidate.stat().st_size != asset['size'] or digest != asset['sha256']:
                raise ValueError('发布产物与清单不符，构建号不可复用')
        if not (destination / name).exists():
            shutil.move(source, destination / name)
    atomic_json(destination / 'release.json', manifest)
    run('chmod', '-R', 'a+rX', str(destination))
    # 发布程序通过 facade 执行 Direct 上传，学校凭据仅由服务器读取。
    run('systemd-run', '--quiet', '--wait', '--pipe', '--collect',
        '--property=User=ubaa', '--property=EnvironmentFile=/etc/ubaa/bhpan.env',
        '/opt/ubaa/bin/bhpan-publish', str(destination))
    atomic_json(destination / 'distribution.json', {'complete': True, 'build': build})


def publish(tag):
    candidates = ROOT / 'downloads/releases' / tag
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('无效发布标签')
    # 发布事件必须与 GitHub 已公开 Release 的清单完全对应，不能取目录中的最新构建。
    url = f'https://github.com/BUAASubnet/UBAA/releases/download/{tag}/release.json'
    with urllib.request.urlopen(url, timeout=60) as response:
        manifest = json.load(response)
    build = str(manifest['build'])
    if not build.isdecimal():
        raise ValueError('无效构建号')
    directory = candidates / build
    if not (directory / 'distribution.json').exists() or json.loads((directory / 'release.json').read_text()) != manifest:
        raise ValueError('公开 Release 尚未完成服务器和云盘分发')
    atomic_json(STATE / 'published.json', manifest)
    run('chown', 'ubaa:ubaa', str(STATE / 'published.json'))
    content = json.loads((ROOT / 'app_service/current/content.json').read_text())
    content['channels']['github'] = {
        'latest_version': manifest['version'] + '+' + build,
        'min_supported_version': '2.0.0',
        'url': 'https://www.ubaa.top/download', 'release_notes': '更新说明：https://www.ubaa.top/guide/ubaa2',
    }
    atomic_json(STATE / 'content.json', content)
    run('chown', 'ubaa:ubaa', str(STATE / 'content.json'))
    run('systemctl', 'restart', 'ubaa-app.service')


def main():
    os.umask(0o022)
    payload = json.load(sys.stdin)
    operation = payload['operation']
    if operation not in ('app', 'docs', 'release', 'publish'):
        raise ValueError('无效部署操作')
    if not str(payload['run']).isdecimal() or not re.fullmatch('[a-f0-9]{40}', payload['sha']):
        raise ValueError('无效运行标识')
    ROOT.mkdir(parents=True, exist_ok=True)
    with (ROOT / 'deploy.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if operation == 'publish':
            publish(payload['tag'])
        else:
            staging = ROOT / 'staging'
            staging.mkdir(exist_ok=True, mode=0o700)
            with tempfile.TemporaryDirectory(dir=staging) as temporary:
                folder = Path(temporary)
                extract(payload['artifacts'], folder)
                identifier = str(payload['run']) + '-' + payload['sha'][:12] + '-' + str(time.time_ns())
                if operation == 'app':
                    application(folder, identifier)
                elif operation == 'docs':
                    docs(folder, identifier)
                else:
                    release(folder, payload['manifest'])
        print('服务器部署完成：' + operation, flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # 下载地址和学校认证上下文不进入 Actions 日志。
        print('服务器部署失败：' + type(error).__name__, file=sys.stderr)
        sys.exit(1)
