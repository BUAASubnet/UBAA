#!/usr/bin/env python3
"""检查必须在工具自身声明的版本镜像，避免出现第二套维护值。"""
from pathlib import Path
import re
import sys
import tomllib
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from environment import read_values
from repo import ROOT


def main():
    values = read_values(ROOT / 'scripts/tools/versions.env')
    edition = tomllib.loads((ROOT / 'Cargo.toml').read_text())['workspace']['package']['edition']
    rust = tomllib.loads((ROOT / 'rust-toolchain.toml').read_text())['toolchain']['channel']
    bridge = tomllib.loads((ROOT / 'crates/ubaa_flutter_bridge/Cargo.toml').read_text())
    frb = bridge['dependencies']['flutter_rust_bridge']
    if isinstance(frb, dict):
        frb = frb['version']
    mirrors = [('Rust edition', edition, values['RUST_EDITION']), ('Rust 工具链', rust, values['RUST_VERSION']),
               ('FRB Rust 依赖', frb.lstrip('='), values['FRB_VERSION'])]
    pubspec = (ROOT / 'packages/ubaa_bindings/pubspec.yaml').read_text()
    mirrors.append(('FRB Dart 依赖', re.search(r'^  flutter_rust_bridge: (.+)$', pubspec, re.M)[1], values['FRB_VERSION']))
    references = (ROOT / 'docs/migration/references.md').read_text()
    for key in ['UBAA_OLD_COMMIT', 'BUAA_API_COMMIT', 'UBAA_OLD_REMOTE', 'BUAA_API_REMOTE']:
        if values[key] not in references:
            raise ValueError(f'冻结参考说明未同步 {key}')
    for label, actual, expected in mirrors:
        if actual != expected:
            raise ValueError(f'{label} 未同步唯一版本清单')
    for path in (ROOT / '.github').rglob('*.yml'):
        for action in re.findall(r'\buses:\s*(\S+)', path.read_text()):
            if not action.startswith('./') and not re.fullmatch(r'[^@]+@[a-f0-9]{40}', action):
                raise ValueError(f'{path.relative_to(ROOT)} 的第三方 Action 未锁定 SHA')
    print('工具版本镜像与 Action SHA 检查通过')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from None
