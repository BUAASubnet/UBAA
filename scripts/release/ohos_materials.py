"""校验显式 OHOS 材料映射，区分仓库类型声明与原生产物。"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit

import json5


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_file(base, entry):
    path = base / entry['path']
    if not path.is_file() or not path.stat().st_size or digest(path) != entry['sha256']:
        raise ValueError('OHOS 材料缺失、为空或摘要不匹配')
    return path


def load_evidence(path, workspace, manifests, output):
    """材料属于显式输入声明；校验文件一致性，不推断二进制构建来源。"""
    if path is None:
        return {}
    data = json.loads(path.read_text())
    if data.get('schema') != 1 or not isinstance(data.get('artifacts'), list):
        raise ValueError('OHOS 材料清单格式无效')
    allowed = {p.relative_to(workspace).as_posix(): p for p in manifests}
    result = {}
    for entry in data['artifacts']:
        source = entry['source']
        url = urlsplit(source['repository'])
        if (url.scheme != 'https' or not url.hostname or url.username or url.password
                or url.query or url.fragment or not re.fullmatch(r'[0-9a-f]{40}', source['revision'])):
            raise ValueError('OHOS 来源必须包含公开 HTTPS 仓库与完整提交')
        if not isinstance(entry['version'], str) or not entry['version']:
            raise ValueError('OHOS 材料必须声明版本')
        artifact = checked_file(path.parent, entry['artifact'])
        if not entry['licenses'] or not entry['references']:
            raise ValueError('OHOS 材料必须包含许可证正文与使用方')
        files = []
        for item in entry['licenses']:
            license_path = checked_file(path.parent, item)
            relative = Path('licenses') / f'{digest(license_path)}.txt'
            (output / relative).parent.mkdir(parents=True, exist_ok=True)
            (output / relative).write_bytes(license_path.read_bytes())
            files.append({'name': license_path.name, 'sha256': digest(license_path),
                          'artifact': relative.as_posix()})
        record = {'ecosystem': 'ohos-dependency', 'name': entry['name'], 'version': entry['version'],
                  'scope': 'native-artifact', 'artifact_sha256': digest(artifact),
                  'source_url': source['repository'], 'revision': source['revision'],
                  'provenance': 'explicit-evidence', 'files': files, 'references': [],
                  'review_status': '材料映射为显式来源声明；未验证构建来源或进行法律审核',
                  'evidence_status': 'collected'}
        for reference in entry['references']:
            manifest = allowed.get(reference['manifest'])
            if manifest is None or digest(manifest) != reference['sha256']:
                raise ValueError('OHOS 材料使用方不存在或声明已变化')
            dependencies = json5.loads(manifest.read_text()).get('dependencies', {})
            key = (reference['manifest'], entry['name'])
            if entry['name'] not in dependencies or key in result:
                raise ValueError('OHOS 材料使用方依赖不存在或重复映射')
            record['references'].append(reference['manifest'])
            result[key] = record
    return result


def type_declarations(workspace, output, manifest, name, requested, inherit):
    """只有受 Git 跟踪的仓库内类型包才允许继承本项目许可证。"""
    if not requested.startswith('file:'):
        return None
    target = (manifest.parent / requested[5:]).resolve()
    if not target.is_relative_to(workspace.resolve()) or not target.is_dir():
        return None
    package = target / 'oh-package.json5'
    if not package.is_file():
        return None
    data = json5.loads(package.read_text())
    types = data.get('types')
    if data.get('name') != name or not types or data.get('dependencies'):
        return None
    type_file = (target / types).resolve()
    if not type_file.is_relative_to(target) or not type_file.name.endswith('.d.ts'):
        return None
    paths = subprocess.check_output(['git', '-C', str(workspace), 'ls-files', '-z', '--',
                                     target.relative_to(workspace.resolve()).as_posix()])
    tracked = [workspace / value.decode() for value in paths.split(b'\0') if value]
    if package not in [p.resolve() for p in tracked] or type_file not in [p.resolve() for p in tracked]:
        return None
    if any(p.is_symlink() or not p.is_file() or
           (p.name != 'oh-package.json5' and not p.name.endswith('.d.ts')) for p in tracked):
        return None
    files, source = inherit(target, workspace, output)
    return {'ecosystem': 'ohos-dependency', 'name': name, 'version': str(data['version']),
            'scope': 'type-declarations', 'manifest': manifest.relative_to(workspace).as_posix(),
            'references': [manifest.relative_to(workspace).as_posix()],
            'source_files': [{'path': p.relative_to(workspace).as_posix(), 'sha256': digest(p)} for p in tracked],
            'files': files, 'license_source': source,
            'review_status': '仅收集类型包；实际动态库由产物验收核对',
            'evidence_status': 'collected' if files else 'license_missing'}


def dependencies(workspace, output, manifests, evidence, inherit):
    mapped = load_evidence(evidence, workspace, manifests, output)
    records, identities = [], {}
    for manifest in manifests:
        for name, requested in sorted(json5.loads(manifest.read_text()).get('dependencies', {}).items()):
            relative = manifest.relative_to(workspace).as_posix()
            record = mapped.get((relative, name))
            if record is None:
                record = type_declarations(workspace, output, manifest, name, requested, inherit)
            if record is None:
                record = {'ecosystem': 'ohos-dependency', 'name': name, 'manifest': relative,
                          'references': [relative], 'files': [],
                          'material_input': '通过 --ohos-evidence 提供产物摘要、来源、使用方声明摘要与许可证正文',
                          'evidence_status': 'native_evidence_missing'}
            if record.get('artifact_sha256'):
                identity = (name, record['artifact_sha256'])
                previous = identities.get(identity)
                if previous is not None:
                    if any(previous[k] != record[k] for k in ['version', 'source_url', 'revision', 'files']):
                        raise ValueError('同一 OHOS 产物的来源或许可证材料相互冲突')
                    previous['references'] = sorted(set(previous['references'] + record['references']))
                    continue
                identities[identity] = record
            records.append(record)
    return records
