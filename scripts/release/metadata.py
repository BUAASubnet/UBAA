#!/usr/bin/env python3
"""固定发布候选，并将统一版本提供给所有平台作业。"""
import os
from pathlib import Path
import subprocess
import tomllib

version = tomllib.loads(Path('version.toml').read_text())
tag = os.environ.get('RELEASE_TAG') or 'v' + version['version']
if tag != 'v' + version['version']:
    raise SystemExit('Release Tag 必须与 version.toml 一致')
subprocess.run(['git', 'merge-base', '--is-ancestor', 'HEAD', 'origin/main'], check=True)
sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
existing = subprocess.run(['git', 'rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}'], capture_output=True, text=True)
if existing.returncode == 0 and existing.stdout.strip() != sha:
    raise SystemExit('已有 Release Tag 指向其他提交')
with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
    for key, value in {'version': version['version'], 'build': version['build_number'], 'tag': tag, 'sha': sha}.items():
        output.write(f'{key}={value}\n')
print(f"发布候选：{tag}，构建号 {version['build_number']}，提交 {sha}")
