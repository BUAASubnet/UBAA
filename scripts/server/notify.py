#!/usr/bin/env python3
"""向部署用户传递本次运行的临时下载地址，服务器直接拉取产物。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def artifact_url(repository, artifact_id):
    request = urllib.request.Request(
        f'https://api.github.com/repos/{repository}/actions/artifacts/{artifact_id}/zip',
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json'})
    try:
        urllib.request.build_opener(NoRedirect).open(request, timeout=30)
    except urllib.error.HTTPError as error:
        if error.code == 302:
            return error.headers['Location']
        raise RuntimeError('无法取得产物临时地址') from None
    raise RuntimeError('GitHub 未返回产物临时地址')


def main():
    operation = sys.argv[1]
    run = os.environ.get('SOURCE_RUN', os.environ['GITHUB_RUN_ID'])
    repository = os.environ['GITHUB_REPOSITORY']
    # 内容发布不跳过旧提交：后续提交可能不改内容，不会再次触发发布；同组运行按推送顺序执行。
    if operation in ('app', 'docs'):
        branch = 'main' if operation == 'app' else 'dev'
        head = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repository}/git/ref/heads/{branch}'], text=True))
        if head['object']['sha'] != os.environ['GITHUB_SHA']:
            print('部署分支已有新提交，跳过旧候选')
            return
    payload = {'operation': operation, 'run': run, 'sha': os.environ['GITHUB_SHA']}
    if operation == 'publish':
        payload['tag'] = os.environ['RELEASE_TAG']
    elif operation == 'content':
        # 渠道和公告体积很小，直接随运行描述传入，不经产物下载。
        payload['content'] = json.loads(Path('dist/app_service/app_content.json').read_text())
    else:
        pages = json.loads(subprocess.check_output([
            'gh', 'api', '--paginate', '--slurp',
            f'repos/{repository}/actions/runs/{run}/artifacts?per_page=100'], text=True))
        selected = [a for page in pages for a in page['artifacts']
                    if not a['expired'] and (
                        a['name'].startswith('public-') if operation == 'release'
                        else a['name'] == {'app': 'app-service', 'docs': 'docs-site'}[operation])]
        if not selected:
            raise ValueError('本次运行缺少部署产物')
        payload['artifacts'] = [{'name': a['name'], 'url': artifact_url(repository, a['id'])} for a in selected]
        if operation == 'release':
            payload['manifest'] = json.loads(Path('dist/release/public/release.json').read_text())
    directory = Path(os.environ['RUNNER_TEMP']) / 'ubaa_server_notify'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    key, hosts = directory / 'key', directory / 'known_hosts'
    try:
        key.write_text(os.environ['UBAA_DEPLOY_KEY'].strip() + '\n')
        key.chmod(0o600)
        hosts.write_text(os.environ['UBAA_DEPLOY_HOST_KEYS'].strip() + '\n')
        subprocess.run(['ssh', '-i', str(key), '-p', '10022',
                        '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                        '-o', f'UserKnownHostsFile={hosts}', '-o', 'ConnectTimeout=20',
                        '-o', 'ServerAliveInterval=20', '-o', 'ServerAliveCountMax=6',
                        'ubaa-deploy@bt.botium.cn', 'deploy'],
                       input=json.dumps(payload), text=True, check=True)
    finally:
        shutil.rmtree(directory)


if __name__ == '__main__':
    main()
