"""读取 Cargo 工作区成员及其本地依赖关系。"""
import json
from pathlib import Path
import subprocess


def members(root):
    metadata = json.loads(subprocess.check_output(
        ['cargo', 'metadata', '--locked', '--offline', '--no-deps', '--format-version', '1'], cwd=root,
    ))
    identities = set(metadata['workspace_members'])
    return {package['name']: package for package in metadata['packages'] if package['id'] in identities}


def affected(packages, seeds):
    affected_names = set(seeds)
    if unknown := affected_names - packages.keys():
        raise ValueError('未登记的 Rust crate：' + '、'.join(sorted(unknown)))
    owners = {Path(package['manifest_path']).parent.resolve(): name for name, package in packages.items()}
    dependencies = {
        name: {owners.get(Path(dependency['path']).resolve()) for dependency in package['dependencies']
               if dependency.get('path')}
        for name, package in packages.items()
    }
    while True:
        expanded = affected_names | {name for name, deps in dependencies.items() if deps & affected_names}
        if expanded == affected_names:
            return sorted(expanded)
        affected_names = expanded
