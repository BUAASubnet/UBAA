#!/usr/bin/env python3
"""离线生成可追溯的 Dart/OHOS 许可材料清单；Rust 依赖许可由 cargo-deny 检查。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urljoin, urlsplit

import json5
import yaml

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from repo import ROOT
sys.path.insert(0, str(Path(__file__).resolve().parent))
from ohos_materials import dependencies as ohos_dependencies

RELEASE_BLOCKED_EXIT = 3
DART_LOCK_PATTERNS = ('pubspec.lock', 'apps/**/pubspec.lock', 'packages/**/pubspec.lock')


def read_json(path):
    return json.loads(path.read_text())


def tracked(root, *patterns):
    result = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--', *patterns],
                            capture_output=True, check=True)
    return [root / item.decode() for item in result.stdout.split(b'\0') if item]


def dart_lockfiles(workspace):
    """返回官方 workspace 与独立宿主的全部 Git 跟踪 Pub 锁文件。"""
    return tracked(workspace, *DART_LOCK_PATTERNS)


def license_files(directory):
    if not directory.is_dir():
        return []
    return [path for path in sorted(directory.iterdir())
            if path.is_file() and not path.is_symlink()
            and re.match(r'^(LICENSE|LICENCE|COPYING|NOTICE)([._-].*)?$', path.name, re.I)]


def collect_license_files(directory, output):
    files = []
    for path in license_files(directory):
        body = path.read_bytes()
        digest = hashlib.sha256(body).hexdigest()
        relative = Path('licenses') / f'{digest}.txt'
        (output / relative).parent.mkdir(parents=True, exist_ok=True)
        (output / relative).write_bytes(body)
        files.append({'name': path.name, 'sha256': digest, 'artifact': relative.as_posix()})
    return files


def collect_workspace_license(directory, workspace, output):
    """为仓库内自有路径包寻找最近的项目许可证。"""
    try:
        directory = directory.resolve()
        workspace = workspace.resolve()
        directory.relative_to(workspace)
    except ValueError:
        return [], None
    for parent in (directory, *directory.parents):
        if not parent.is_relative_to(workspace):
            break
        files = collect_license_files(parent, output)
        if files:
            return files, parent.relative_to(workspace).as_posix() or "."
        if parent == workspace:
            break
    return [], None


def package_roots(project):
    configuration = project / '.dart_tool/package_config.json'
    if not configuration.is_file():
        return {}
    result = {}
    for package in read_json(configuration)['packages']:
        uri = urlsplit(urljoin(configuration.as_uri(), package['rootUri']))
        if uri.scheme == 'file' and not uri.netloc:
            result[package['name']] = Path(unquote(uri.path))
    return result


def package_record(lockfile, name, package, roots, workspace, output):
    version, source = str(package['version']), package['source']
    record = {'ecosystem': 'dart', 'name': name, 'version': version,
              'source_type': source, 'lockfile': lockfile.relative_to(workspace).as_posix(),
              'dependency_kind': package.get('dependency', 'unknown'),
              'review_status': '未进行法律审核', 'files': []}
    description = package['description']
    if isinstance(description, dict):
        origin = description.get('url')
        if origin:
            parsed = urlsplit(origin)
            if parsed.scheme not in {'https', 'http'} or parsed.username or parsed.password or parsed.query:
                raise ValueError('锁文件依赖来源包含非公开 URL；拒绝写入材料清单')
            record['source_url'] = origin
        if 'sha256' in description:
            record['archive_sha256'] = description['sha256']
        if source == 'git':
            repository_path = description.get('path', '.')
            if Path(repository_path).is_absolute() or '..' in Path(repository_path).parts:
                raise ValueError('Git 包路径必须位于对应源码仓库内')
            record['repository_path'] = repository_path
            record['revision'] = description.get('resolved-ref')
    directory = roots.get(name)
    if source == 'path':
        directory = (lockfile.parent / package['description']['path']).resolve()
        if directory.is_relative_to(workspace):
            record['repository_path'] = directory.relative_to(workspace).as_posix()
    if source == 'hosted' and directory is None:
        cache = Path(os.environ.get('PUB_CACHE', str(Path.home() / '.pub-cache')))
        directory = cache / 'hosted' / urlsplit(description['url']).netloc / f'{name}-{version}'
    if directory is None or not directory.is_dir():
        record['evidence_status'] = 'source_unavailable'
        return record
    manifest_path = directory / 'pubspec.yaml'
    manifest = yaml.safe_load(manifest_path.read_text()) if manifest_path.is_file() else {}
    # SDK 包的 pubspec 版本由工具链控制，不一定等于 lock 中的 0.0.0。
    if manifest.get('name') != name or (source != 'sdk' and str(manifest.get('version')) != version):
        record['evidence_status'] = 'lock_mismatch'
        return record
    if source == 'git':
        revision = subprocess.run(['git', '-C', str(directory), 'rev-parse', 'HEAD'],
                                  capture_output=True, text=True)
        expected = package['description'].get('resolved-ref')
        if revision.returncode or not expected or revision.stdout.strip() != expected:
            record['evidence_status'] = 'lock_mismatch'
            return record
        record['revision'] = expected
    if source == 'hosted':
        archive_hash = directory.parent.parent.parent / 'hosted-hashes' / directory.parent.name / f'{name}-{version}.sha256'
        if not archive_hash.is_file() or archive_hash.read_text().strip() != description.get('sha256'):
            record['evidence_status'] = 'source_checksum_unverified'
            return record
    record['files'] = collect_license_files(directory, output)
    record['license_scope'] = 'package'
    if not record['files'] and source == 'path':
        files, source_path = collect_workspace_license(directory, workspace, output)
        if files:
            record['files'] = files
            record['license_scope'] = 'workspace-ancestor'
            record['license_source'] = source_path
    if not record['files'] and source in {'sdk', 'git'}:
        top = subprocess.run(['git', '-C', str(directory), 'rev-parse', '--show-toplevel'],
                             capture_output=True, text=True)
        if top.returncode == 0:
            repository_root = Path(top.stdout.strip()).resolve()
            # Flutter 与社区 monorepo 的子包可共享祖先许可；只在同一源码仓库内上溯。
            for parent in directory.parents:
                if not parent.is_relative_to(repository_root):
                    break
                record['files'] = collect_license_files(parent, output)
                if record['files']:
                    record['license_scope'] = 'source-repository-ancestor'
                    record['license_source'] = parent.relative_to(repository_root).as_posix()
                    break
    record['evidence_status'] = 'collected' if record['files'] else 'license_missing'
    return record


def dart_evidence(workspace, output, lockfiles=None):
    records = []
    lockfiles = lockfiles if lockfiles is not None else dart_lockfiles(workspace)
    for lockfile in lockfiles:
        lock = yaml.safe_load(lockfile.read_text())
        roots = package_roots(lockfile.parent)
        for name, package in sorted(lock['packages'].items()):
            records.append(package_record(lockfile, name, package, roots, workspace, output))
    return records


def release_blockers(records):
    return [
        {'ecosystem': record['ecosystem'], 'name': record['name'],
         'version': record.get('version'), 'reason': record['evidence_status'],
         'source': record.get('lockfile', record.get('manifest')),
         'references': record.get('references', [])}
        for record in records if record['evidence_status'] != 'collected'
    ]


def release_exit_code(records, report_only=False):
    """材料缺口默认阻止发布；显式报告模式只生成材料。"""
    return 0 if report_only or not release_blockers(records) else RELEASE_BLOCKED_EXIT


def ohos_evidence(workspace, output, manifests=None, evidence=None):
    """原生分发与其依赖单列；本机 SDK 路径不写入报告。"""
    records = []
    manifests = manifests if manifests is not None else tracked(workspace, '**/oh-package.json5')
    for manifest in manifests:
        data = json5.loads(manifest.read_text())
        package_root = manifest.parent
        if package_root.name == 'ohos':
            package_root = package_root.parent
        files = collect_license_files(package_root, output)
        license_scope = 'package'
        license_source = None
        if not files:
            files, license_source = collect_workspace_license(package_root, workspace, output)
            if files:
                license_scope = 'workspace-ancestor'
        record = {'ecosystem': 'ohos', 'name': data['name'], 'version': data['version'],
                  'manifest': manifest.relative_to(workspace).as_posix(),
                  'declared_license': data.get('license'), 'files': files,
                  'license_scope': license_scope, 'license_source': license_source,
                  'review_status': '未进行法律审核',
                  'evidence_status': 'collected' if files else 'license_missing'}
        records.append(record)
    records.extend(ohos_dependencies(workspace, output, manifests, evidence, collect_workspace_license))
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ohos-evidence', type=Path, help='显式 OHOS 来源与许可证材料清单')
    parser.add_argument('--report-only', action='store_true',
                        help='保留报告并允许材料缺口；不作为发布前置通过')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    records = dart_evidence(ROOT, args.output) + ohos_evidence(ROOT, args.output, evidence=args.ohos_evidence)
    missing = sum(record['evidence_status'] != 'collected' for record in records)
    blockers = release_blockers(records)
    report = {'schema': 1, 'material_status': 'partial' if missing else 'collected',
              'review_status': '未进行法律审核；材料收集不等同正式发布批准',
              'incomplete_records': missing, 'records': records,
              'ohos_evidence_sha256': hashlib.sha256(args.ohos_evidence.read_bytes()).hexdigest() if args.ohos_evidence else None,
              'release_blockers': blockers}
    (args.output / 'license-evidence.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    lines = ['Dart/OHOS 许可证材料清单（名称、锁定版本、来源及正文摘要）',
             f'材料状态：{report["material_status"]}；未完整收集：{missing}/{len(records)}',
             report['review_status']]
    for record in records:
        lines.append(f'{record["ecosystem"]} {record["name"]} '
                     f'{record.get("version", record.get("requested", ""))}：{record["evidence_status"]}')
    (args.output / 'dependency-audit.txt').write_text('\n'.join(lines) + '\n')
    print(f'许可材料状态={report["material_status"]}，缺口={missing}/{len(records)}；未进行法律审核')
    if release_exit_code(records, args.report_only):
        print(f'依赖材料存在 {len(blockers)} 项发布阻塞；报告已生成但不能作为发布通过。',
              file=sys.stderr)
        raise SystemExit(RELEASE_BLOCKED_EXIT)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'依赖材料生成失败：{type(error).__name__}；请检查输入与固定工具') from error
