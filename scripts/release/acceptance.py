#!/usr/bin/env python3
"""关联完整合并验收与正式发布候选，Git tree 同时覆盖源码和检查输入。"""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlencode
import zipfile


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def api(path, binary=False):
    data = subprocess.check_output(['gh', 'api', path], stderr=subprocess.PIPE)
    return data if binary else json.loads(data)


def matches(record, run, repository, sha, tree, pr=None):
    if (record.get('schema') != 1 or record.get('repository') != repository or
            record.get('tree') != tree or run.get('conclusion') != 'success' or
            run.get('path') != '.github/workflows/ci.yml' or
            record.get('run_id') != run.get('id') or
            record.get('run_attempt') != run.get('run_attempt') or
            record.get('event') != run.get('event')):
        return False
    if run['event'] == 'workflow_dispatch':
        return record.get('checked_sha') == sha == run.get('head_sha')
    if run['event'] != 'pull_request' or not pr:
        return False
    return bool(record.get('checked_sha') and record.get('base_sha') and
                pr.get('merged_at') and pr.get('merge_commit_sha') == sha and
                pr['base']['ref'] == 'main' and pr['base']['repo']['full_name'] == repository and
                record.get('pr') == pr['number'] and
                record.get('head_sha') == pr['head']['sha'] == run.get('head_sha'))


def write_record():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    pr = event.get('pull_request', {})
    record = {'schema': 1, 'repository': os.environ['GITHUB_REPOSITORY'],
              'run_id': int(os.environ['GITHUB_RUN_ID']),
              'run_attempt': int(os.environ['GITHUB_RUN_ATTEMPT']),
              'event': os.environ['GITHUB_EVENT_NAME'], 'checked_sha': git('rev-parse', 'HEAD'),
              'tree': git('rev-parse', 'HEAD^{tree}'), 'pr': pr.get('number', 0),
              'head_sha': pr.get('head', {}).get('sha', ''),
              'base_sha': pr.get('base', {}).get('sha', '')}
    path = Path('.ubaa_local/ci/acceptance.json')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record))


def find_record(repository, sha, tree):
    prefix = f'repos/{repository}'
    prs = api(f'{prefix}/commits/{sha}/pulls')
    candidates = [(sha, 'workflow_dispatch', None)] + [
        (pr['head']['sha'], 'pull_request', pr) for pr in prs
        if pr.get('merged_at') and pr.get('merge_commit_sha') == sha and pr['base']['ref'] == 'main']
    for head, event, pr in candidates:
        query = urlencode({'head_sha': head, 'event': event, 'status': 'success', 'per_page': 20})
        runs = api(f'{prefix}/actions/workflows/ci.yml/runs?{query}')['workflow_runs']
        for run in runs:
            artifacts = api(f'{prefix}/actions/runs/{run["id"]}/artifacts')['artifacts']
            for artifact in artifacts:
                if artifact['name'] != 'merge-acceptance' or artifact['expired']:
                    continue
                archive = api(f'{prefix}/actions/artifacts/{artifact["id"]}/zip', binary=True)
                with zipfile.ZipFile(io.BytesIO(archive)) as zipped:
                    record = json.loads(zipped.read('acceptance.json'))
                if matches(record, run, repository, sha, tree, pr):
                    return record
    return None


def reuse():
    repository = os.environ['GITHUB_REPOSITORY']
    sha, tree = git('rev-parse', 'HEAD'), git('rev-parse', 'HEAD^{tree}')
    try:
        record = find_record(repository, sha, tree)
    except (subprocess.CalledProcessError, ValueError, KeyError, zipfile.BadZipFile):
        # 缺少可验证的记录时执行完整验收，不把 API 或旧格式错误视为通过。
        record = None
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        output.write(f'reused={str(record is not None).lower()}\n')
    if record:
        url = f'https://github.com/{repository}/actions/runs/{record["run_id"]}'
        print(f'复用完整验收：{url}；检出提交 {record["checked_sha"]}；发布提交 {sha}；相同 Git tree {tree}')
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as summary:
            summary.write(f'完整验收：{url}\n\n检出提交：`{record["checked_sha"]}`；发布提交：`{sha}`；源码树：`{tree}`。\n')
    else:
        print('没有与候选匹配的完整验收记录，本次重新运行完整验收。')


def ready(jobs, reused):
    expected = {'metadata', 'store-access', 'acceptance', 'verify'}
    return set(jobs) == expected and all(
        value['result'] == ('skipped' if name == 'verify' and reused else 'success')
        for name, value in jobs.items())


def check_ready():
    if not ready(json.loads(os.environ['NEEDS']), os.environ['REUSED'] == 'true'):
        raise SystemExit('发布候选尚未通过完整验收或商店访问检查')


if __name__ == '__main__':
    {'record': write_record, 'reuse': reuse, 'ready': check_ready}[sys.argv[1]]()
