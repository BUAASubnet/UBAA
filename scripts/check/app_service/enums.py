#!/usr/bin/env python3
"""检查遥测 Schema 的枚举与客户端实际发送的名称一致。"""

import argparse
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[3]
FEATURES = 'packages/ubaa_domain/lib/src/feature/catalog.dart'
ERRORS = 'crates/ubaa_core/src/error/mod.rs'
SCHEMA = 'docs/contracts/app-service.schema.json'


def code(root, path):
    return re.sub(r'//[^\n]*', '', (root / path).read_text(encoding='utf-8'))


def comma_items(body):
    return [item.strip() for item in body.strip().removesuffix(',').split(',')]


def dart_features(root):
    source = code(root, FEATURES)
    variants = re.search(r'\benum FeatureId\s*\{([^{}]+)\}', source)
    switch = re.search(r'\bString get wireName\s*=>\s*switch\s*\(this\)\s*\{([^{}]+)\};', source)
    if variants is None or switch is None:
        raise ValueError(f'{FEATURES} 未找到 FeatureId 或 wireName switch')

    wire_names = {}
    for arm in comma_items(switch[1]):
        match = re.fullmatch(r'''FeatureId\.([A-Za-z][A-Za-z0-9_]*)\s*=>\s*(['"])([a-z0-9_]+)\2''', arm)
        if match is None or match[1] in wire_names:
            raise ValueError(f'{FEATURES} 的 wireName 必须逐项声明字符串值')
        wire_names[match[1]] = match[3]
    if set(comma_items(variants[1])) != wire_names.keys():
        raise ValueError(f'{FEATURES} 的 wireName 必须覆盖全部 FeatureId')
    return set(wire_names.values()) | {'app', 'auth'}


def rust_error_kinds(root):
    source = code(root, ERRORS)
    enum = re.search(r'(?m)^((?:#\[[^\n]+\]\n)+)pub enum ErrorKind\s*\{([^{}]+)\}', source)
    if enum is None:
        raise ValueError(f'{ERRORS} 未找到带 Serde 声明的 ErrorKind')
    attributes = enum[1].splitlines()
    serde = [attribute for attribute in attributes if attribute.startswith('#[serde')]
    if serde != ['#[serde(rename_all = "snake_case")]'] or not re.search(
        r'#\[derive\([^\n]*\bSerialize\b[^\n]*\)\]', enum[1],
    ):
        raise ValueError(f'{ERRORS} 的 ErrorKind 必须由 Serde 按 snake_case 序列化')

    variants = comma_items(enum[2])
    if any(re.fullmatch(r'[A-Z][A-Za-z0-9]*', variant) is None for variant in variants):
        raise ValueError(f'{ERRORS} 的 ErrorKind 必须使用无附加声明的枚举成员')
    # Serde 对枚举成员的 snake_case 规则在首字母以外的每个大写字母前加下划线。
    return {re.sub(r'(?<!^)[A-Z]', r'_\g<0>', variant).lower() for variant in variants}


def differences(definitions, key, field, expected):
    values = definitions[key]['enum']
    if not isinstance(values, list) or any(not isinstance(value, str) for value in values):
        raise ValueError(f'{SCHEMA} 的 {field} 必须声明字符串枚举')
    actual = set(values)
    if len(actual) != len(values):
        raise ValueError(f'{SCHEMA} 的 {field} 枚举含重复值')
    for label, delta in (('缺少', expected - actual), ('多出', actual - expected)):
        if delta:
            yield f'{field} {label}：{", ".join(sorted(delta))}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    root = parser.parse_args().root
    try:
        definitions = json.loads((root / SCHEMA).read_text(encoding='utf-8'))['$defs']
        errors = [
            *differences(definitions, 'feature', 'feature', dart_features(root)),
            *differences(definitions, 'errorKind', 'error_kind', rust_error_kinds(root)),
        ]
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise SystemExit(f'应用服务枚举检查失败：{error}') from None
    if errors:
        raise SystemExit(f'{SCHEMA} 枚举与客户端不一致：\n' + '\n'.join(errors))
    print('应用服务枚举检查通过：feature / error_kind')


if __name__ == '__main__':
    main()
