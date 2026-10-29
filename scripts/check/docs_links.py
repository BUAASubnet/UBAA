#!/usr/bin/env python3
"""只读检查受跟踪及新增 Markdown 的本地文件、站内路由和标题锚点。"""
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
from repo import ROOT


def prose(text):
    text = re.sub(r'^(`{3,}|~{3,}).*?^\1[^\n]*$', '', text, flags=re.M | re.S)
    return re.sub(r'(`+)[^`]*?\1', '', text)


def anchors(path):
    counts, result = {}, set()
    text = re.sub(r'(`+)(.*?)\1', r'\2', path.read_text())
    for heading in re.findall(r'^ {0,3}#{1,6}\s+(.+?)\s*#*$', text, re.M):
        explicit = re.search(r'\{#([^}]+)\}\s*$', heading)
        if explicit:
            result.add(explicit[1])
            continue
        name = re.sub(r'<[^>]*>', '', heading).lower()
        name = re.sub(r'[^\w\s\-\u4e00-\u9fff]', '', name)
        name = re.sub(r'\s', '-', name.strip())
        count = counts.get(name, 0)
        counts[name] = count + 1
        result.add(name + (f'-{count}' if count else ''))
    result.update(re.findall(r'(?:id|name)=[\"\']([^\"\']+)', text))
    return result


def check_file(root, page):
    text = prose(page.read_text())
    # 内联与引用式链接共用目标解析；嵌套括号允许常见的带括号文件名。
    pattern = r'!?\[[^\]\n]*\]\(\s*(<[^>]+>|(?:[^\s()]|\([^()]*\))+)'
    targets = re.findall(pattern, text)
    targets += re.findall(r'^ {0,3}\[[^\]]+\]:\s*(<[^>]+>|\S+)', text, re.M)
    errors = []
    site = root / 'docs/site'
    for raw in targets:
        target = raw.strip('<>')
        uri = urlsplit(target)
        if uri.scheme or uri.netloc:
            continue
        name = unquote(uri.path)
        if name.startswith('/') and page.is_relative_to(site):
            path = site / name.lstrip('/')
            if not path.exists() and (site / 'public' / name.lstrip('/')).exists():
                path = site / 'public' / name.lstrip('/')
        else:
            path = (root / name.lstrip('/')) if name.startswith('/') else page.parent / name
        path = path.resolve() if name else page.resolve()
        if not path.suffix and not path.exists() and page.is_relative_to(site):
            path = path.with_suffix('.md')
        if path.is_dir() and (path / 'index.md').exists():
            path = path / 'index.md'
        if not path.is_relative_to(root.resolve()) or not path.exists():
            errors.append(f'{page.relative_to(root)} → {target}：目标不存在或越出仓库')
        elif uri.fragment and path.suffix == '.md' and unquote(uri.fragment) not in anchors(path):
            errors.append(f'{page.relative_to(root)} → {target}：标题锚点不存在')
    return errors


def main():
    output = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '--cached', '--others',
                                      '--exclude-standard', '-z', '--', '*.md'])
    errors, count = [], 0
    for name in sorted(set(output.decode().split('\0')) - {''}):
        path = ROOT / name
        if not path.is_file() or name.startswith(('packages/ubaa_bindings/cargokit/',
                                                   'docs/migration/history/',
                                                   'docs/design/evidence/')):
            continue
        errors.extend(check_file(ROOT, path))
        count += 1
    for error in errors:
        print(error, file=sys.stderr)
    print(f'文档链接：检查 {count} 个 Markdown，发现 {len(errors)} 项错误')
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
