#!/usr/bin/env python3
"""按改动选择开发 CI 的检查。"""
import json
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from changed_checks import PACKAGES, dependents, git_paths
from repo import ROOT


FLUTTER_WORKSPACE_INPUTS = {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'}


def flutter_packages(paths, shared):
    if shared or FLUTTER_WORKSPACE_INPUTS.intersection(paths):
        return list(PACKAGES)
    seeds = {name for name, directory in PACKAGES.items()
             if any(path.startswith(directory + '/') for path in paths)}
    if not seeds:
        return []
    try:
        selected = dependents(ROOT, seeds)
    except (OSError, ValueError):
        return list(PACKAGES)
    return [name for name in PACKAGES if name in selected]


def select(paths):
    if paths is None:
        return {'rust': True, 'flutter': True, 'flutter_packages': list(PACKAGES), 'worker': True}
    shared = any(path.startswith(('.github/', 'scripts/')) or path == 'justfile' for path in paths)
    return {
        'rust': shared or any(path.startswith(('crates/', 'tools/', 'fixtures/')) or
                             path in {'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml'} for path in paths),
        'flutter': shared or any(path.startswith(('apps/', 'packages/')) or
                                path in FLUTTER_WORKSPACE_INPUTS for path in paths),
        'flutter_packages': flutter_packages(paths, shared),
        'worker': shared or any(path.startswith(('services/app_service/', 'docs/contracts/app-service',
                                                 'docs/site/announcements/')) or
                               path in {'package.json', 'package-lock.json'} for path in paths),
    }


def main():
    base = os.environ.get('BASE_SHA', '')
    paths = None
    if base and set(base) != {'0'}:
        paths = git_paths(ROOT, 'diff', '--name-only', '--no-renames', '-z', base, 'HEAD', '--')
    with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        for key, value in select(paths).items():
            output.write(f'{key}={json.dumps(value, separators=(",", ":"))}\n')


if __name__ == '__main__':
    main()
