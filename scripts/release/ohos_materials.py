"""OHOS 原生依赖材料：Flutter embedding HAR 由锁定 SDK 推导，仓库类型声明单独记录。"""
import hashlib
from pathlib import Path
import subprocess

import json5

FLUTTER_HAR = '@ohos/flutter_ohos'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sdk_material(sdk, pins, output):
    """HAR 与许可证都来自锁定的 OHOS Flutter SDK；提交不符时不收集，避免错配许可证。"""
    if not sdk or not Path(sdk).is_dir():
        return None, '配置 UBAA_OHOS_FLUTTER_HOME 为锁定的 OHOS Flutter SDK'
    sdk = Path(sdk)
    head = subprocess.run(['git', '-C', str(sdk), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    if head.returncode or head.stdout.strip() != pins['OHOS_FLUTTER_COMMIT']:
        return None, 'UBAA_OHOS_FLUTTER_HOME 不是锁定提交 OHOS_FLUTTER_COMMIT'
    # SDK 根许可证与 engine 目录中 HAR 附带的许可说明一并收集。
    licenses = sorted(path for pattern in ('LICENSE*', 'bin/cache/artifacts/engine/ohos-arm64/LICENSE*')
                      for path in sdk.glob(pattern) if path.is_file() and path.stat().st_size)
    if not licenses:
        return None, '锁定 SDK 缺少许可证正文'
    files = []
    for path in licenses:
        relative = Path('licenses') / f'{digest(path)}.txt'
        (output / relative).parent.mkdir(parents=True, exist_ok=True)
        (output / relative).write_bytes(path.read_bytes())
        files.append({'name': path.name, 'sha256': digest(path), 'artifact': relative.as_posix()})
    return {'ecosystem': 'ohos-dependency', 'name': FLUTTER_HAR, 'version': pins['OHOS_FLUTTER_VERSION'],
            'scope': 'native-artifact', 'source_url': pins['OHOS_FLUTTER_REMOTE'],
            'revision': pins['OHOS_FLUTTER_COMMIT'], 'provenance': 'locked-sdk', 'files': files,
            'references': [], 'review_status': '许可证取自锁定 SDK；未进行法律审核',
            'evidence_status': 'collected'}, None


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


def dependencies(workspace, output, manifests, sdk, pins, inherit):
    shared, reason = sdk_material(sdk, pins, output)
    records = []
    for manifest in manifests:
        relative = manifest.relative_to(workspace).as_posix()
        for name, requested in sorted(json5.loads(manifest.read_text()).get('dependencies', {}).items()):
            if name == FLUTTER_HAR and shared is not None:
                if not shared['references']:
                    records.append(shared)
                shared['references'] = sorted(set(shared['references'] + [relative]))
                continue
            record = type_declarations(workspace, output, manifest, name, requested, inherit)
            if record is None:
                record = {'ecosystem': 'ohos-dependency', 'name': name, 'manifest': relative,
                          'references': [relative], 'files': [],
                          'material_input': reason if name == FLUTTER_HAR else '未知原生依赖，需要补充来源与许可证',
                          'evidence_status': 'native_evidence_missing'}
            records.append(record)
    return records
