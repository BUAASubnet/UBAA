#!/usr/bin/env python3
"""只跳过已经通过夜间完整验收的 dev 提交。"""
import json
import os
from pathlib import Path
import subprocess


def api_pages(path):
    result = subprocess.check_output(['gh', 'api', '--paginate', '--slurp', path], text=True)
    return json.loads(result)


def previously_accepted(repository, sha):
    prefix = f'repos/{repository}/actions'
    workflow = f'{repository}/.github/workflows/ci.yml'
    for page in api_pages(f'{prefix}/workflows/dev-nightly.yml/runs?status=success&per_page=100'):
        for run in page['workflow_runs']:
            if run['conclusion'] != 'success' or not any(
                reference['sha'] == sha and reference['path'].split('@', 1)[0] == workflow
                for reference in run.get('referenced_workflows') or []
            ):
                continue
            jobs = api_pages(f'{prefix}/runs/{run["id"]}/jobs?filter=latest&per_page=100')
            if any(job['conclusion'] == 'success' and job['name'].rsplit(' / ', 1)[-1] == 'main-required'
                   for job_page in jobs for job in job_page['jobs']):
                return True
    return False


def main():
    sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    accepted = previously_accepted(os.environ['GITHUB_REPOSITORY'], sha)
    print(f'dev 候选 {sha}：' + ('已有成功的夜间验收' if accepted else '需要完整验收'))
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        output.write(f'sha={sha}\naccepted={json.dumps(accepted)}\n')


if __name__ == '__main__':
    main()
