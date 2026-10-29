#!/usr/bin/env python3
"""离线生成标准 Cargo SBOM 与可追溯的 Dart/OHOS 许可材料清单。"""
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
import jsonschema
from referencing import Registry, Resource
import yaml

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from repo import ROOT

SCHEMAS = ROOT / 'scripts/tools/cyclonedx-1.5'


def read_json(path):
    return json.loads(path.read_text())


def schema_resources():
    provenance = read_json(SCHEMAS / 'UPSTREAM.json')
    resources, schemas = [], {}
    for entry in provenance['files']:
        path = SCHEMAS / entry['file']
        body = path.read_bytes()
        if hashlib.sha256(body).hexdigest() != entry['sha256']:
            raise ValueError(f'固定 schema/许可摘要不符：{path.name}')
        if path.suffix == '.json':
            schema = json.loads(body)
            schemas[path.name] = schema
            resource = Resource.from_contents(schema)
            resources.append((f'http://cyclonedx.org/schema/{path.name}', resource))
            resources.append((f'https://cyclonedx.org/schema/{path.name}', resource))
            if '$id' in schema:
                resources.append((schema['$id'], resource))
    def refuse_remote(uri):
        raise ValueError('schema 引用了未登记资源；离线校验拒绝网络访问')
    return schemas, Registry(retrieve=refuse_remote).with_resources(resources)


def validate_sbom(document):
    schemas, registry = schema_resources()
    validator = jsonschema.Draft7Validator(schemas['bom-1.5.schema.json'], registry=registry)
    errors = list(validator.iter_errors(document))
    if errors:
        location = '/'.join(map(str, errors[0].absolute_path))
        raise ValueError(f'CycloneDX 1.5 schema 校验失败：{location}；无效值不输出')
    refs = [component['bom-ref'] for component in document.get('components', [])]
    if len(set(refs)) != len(refs):
        raise ValueError('SBOM bom-ref 不唯一')


def is_expression(value, identifiers):
    """只接受已知 SPDX ID 的 AND/OR/括号；其他声明保留为自定义名称待核对。"""
    tokens = re.findall(r'[A-Za-z0-9.+-]+|\S', value)
    position = 0
    def operand():
        nonlocal position
        if position == len(tokens):
            return False
        token = tokens[position]
        position += 1
        if token == '(':
            if not expression() or position == len(tokens) or tokens[position] != ')':
                return False
            position += 1
            return True
        return token in identifiers
    def expression():
        nonlocal position
        if not operand():
            return False
        while position < len(tokens) and tokens[position] in {'AND', 'OR'}:
            position += 1
            if not operand():
                return False
        return True
    return expression() and position == len(tokens)


def build_sbom(metadata):
    schemas, _ = schema_resources()
    identifiers = set(schemas['spdx.schema.json']['enum'])
    components, identities = [], {}
    for package in metadata['packages']:
        identity = package.get('id', f"{package['name']}@{package['version']}")
        reference = f"cargo:{package['name']}@{package['version']}:{hashlib.sha256(identity.encode()).hexdigest()[:16]}"
        identities[identity] = reference
        component = {'type': 'library', 'bom-ref': reference,
                     'name': package['name'], 'version': package['version']}
        license_text = package.get('license')
        if license_text in identifiers:
            component['licenses'] = [{'license': {'id': license_text}}]
            status = 'Cargo SPDX 声明；未进行法律审核'
        elif license_text and is_expression(license_text, identifiers):
            component['licenses'] = [{'expression': license_text}]
            status = 'Cargo SPDX 表达式声明；未进行法律审核'
        elif license_text:
            component['licenses'] = [{'license': {'name': license_text}}]
            status = '需人工核对声明'
        else:
            status = '缺少许可证声明；需核对 license_file 或上游材料'
        component['properties'] = [{'name': 'ubaa:license-evidence', 'value': status}]
        components.append(component)
    document = {
        'bomFormat': 'CycloneDX', 'specVersion': '1.5', 'version': 1,
        'metadata': {'tools': [{'vendor': 'UBAA', 'name': 'release-preflight'}],
                     'lifecycles': [{'phase': 'pre-build'}],
                     'properties': [{'name': 'ubaa:inventory-scope',
                                     'value': 'Cargo metadata 全图；不等同单平台最终产物'}]},
        'components': components,
    }
    if metadata.get('resolve'):
        document['dependencies'] = [
            {'ref': identities[node['id']],
             'dependsOn': [identities[dependency] for dependency in node['dependencies']]}
            for node in metadata['resolve']['nodes']]
    validate_sbom(document)
    return document


def tracked(root, *patterns):
    result = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--', *patterns],
                            capture_output=True, check=True)
    return [root / item.decode() for item in result.stdout.split(b'\0') if item]


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
    lockfiles = lockfiles if lockfiles is not None else tracked(
        workspace, 'apps/**/pubspec.lock', 'packages/**/pubspec.lock')
    for lockfile in lockfiles:
        lock = yaml.safe_load(lockfile.read_text())
        roots = package_roots(lockfile.parent)
        for name, package in sorted(lock['packages'].items()):
            records.append(package_record(lockfile, name, package, roots, workspace, output))
    return records


def ohos_evidence(workspace, output, manifests=None):
    """原生分发与其依赖单列；本机 SDK 路径不写入报告。"""
    records = []
    manifests = manifests if manifests is not None else tracked(workspace, '**/oh-package.json5')
    for manifest in manifests:
        data = json5.loads(manifest.read_text())
        package_root = manifest.parent
        if package_root.name == 'ohos':
            package_root = package_root.parent
        files = collect_license_files(package_root, output)
        record = {'ecosystem': 'ohos', 'name': data['name'], 'version': data['version'],
                  'manifest': manifest.relative_to(workspace).as_posix(),
                  'declared_license': data.get('license'), 'files': files,
                  'review_status': '未进行法律审核',
                  'evidence_status': 'collected' if files else 'license_missing'}
        records.append(record)
        for name, requested in sorted(data.get('dependencies', {}).items()):
            local = requested.startswith(('file:', '.', '/'))
            records.append({'ecosystem': 'ohos-dependency', 'name': name,
                            'requested': '本地路径依赖' if local else requested,
                            'manifest': manifest.relative_to(workspace).as_posix(),
                            'review_status': '未进行法律审核', 'files': [],
                            'evidence_status': 'native_dependency_requires_artifact_review'})
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    document = build_sbom(read_json(args.metadata))
    (args.output / 'sbom.cdx.json').write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n')
    records = dart_evidence(ROOT, args.output) + ohos_evidence(ROOT, args.output)
    missing = sum(record['evidence_status'] != 'collected' for record in records)
    report = {'schema': 1, 'material_status': 'partial' if missing else 'collected',
              'review_status': '未进行法律审核；材料收集不等同正式发布批准',
              'incomplete_records': missing, 'records': records,
              'release_blockers': [
                  {'ecosystem': r['ecosystem'], 'name': r['name'],
                   'version': r.get('version'), 'reason': r['evidence_status'],
                   'source': r.get('lockfile', r.get('manifest'))}
                  for r in records if r['evidence_status'] != 'collected']}
    (args.output / 'license-evidence.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    lines = ['Dart/OHOS 许可证材料清单（名称、锁定版本、来源及正文摘要）',
             f'材料状态：{report["material_status"]}；未完整收集：{missing}/{len(records)}',
             report['review_status']]
    for record in records:
        lines.append(f'{record["ecosystem"]} {record["name"]} '
                     f'{record.get("version", record.get("requested", ""))}：{record["evidence_status"]}')
    (args.output / 'dependency-audit.txt').write_text('\n'.join(lines) + '\n')
    print(f'CycloneDX 1.5 离线 schema 通过；许可材料状态={report["material_status"]}，缺口={missing}/{len(records)}；未进行法律审核')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'依赖材料生成失败：{type(error).__name__}；请检查输入与固定工具') from error
