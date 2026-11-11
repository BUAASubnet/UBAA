#!/usr/bin/env python3
"""解析项目的 KEY=value 文件；按调用方指定的键和展开策略读取。"""
from pathlib import Path
import re
import shlex

VARIABLE = re.compile(r'\$(?:\{([A-Za-z_][A-Za-z_0-9]*)\}|([A-Za-z_][A-Za-z_0-9]*))')


def read_values(path, *, environment=None, expand=False, keys=None, keep_syntax=False):
    values = dict(environment or {})
    seen = set()
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r'(?:export\s+)?([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(.*)', line)
        if match is None:
            raise ValueError(f'配置第 {number} 行格式无效；请使用 KEY=value')
        key, raw = match.groups()
        if keys is not None and key not in keys:
            continue
        if key in seen:
            raise ValueError(f'配置第 {number} 行重复定义变量')
        seen.add(key)
        try:
            parts = shlex.split(raw, comments=True, posix=True)
        except ValueError:
            raise ValueError(f'配置第 {number} 行引号无效') from None
        if len(parts) > 1:
            raise ValueError(f'配置第 {number} 行包含未加引号的空格')
        value = parts[0] if parts else ''
        if any(c in value for c in '\x00\r\n'):
            raise ValueError(f'配置第 {number} 行包含控制字符')
        if expand and not raw.startswith("'"):
            value = VARIABLE.sub(lambda m: values.get(m[1] or m[2], ''), value)
        values.setdefault(key, raw if keep_syntax else value)
    return values


def credentials(values):
    username = values.get('UBAA_TEST_USERNAME') or values.get('UBAA_USERNAME')
    password = values.get('UBAA_TEST_PASSWORD') or values.get('UBAA_PASSWORD')
    if not username or not password:
        raise ValueError('请在 .env 或进程环境设置 UBAA_TEST_USERNAME、UBAA_TEST_PASSWORD（或兼容名称）')
    if any(c in username or c in password for c in '\x00\r\n'):
        raise ValueError('账号或密码不能包含换行符或空字符')
    return (username + '\n' + password + '\n').encode()
