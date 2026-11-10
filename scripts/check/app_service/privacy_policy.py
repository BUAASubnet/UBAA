"""从网站隐私政策生成或核对应用内的离线正文。"""

import argparse
import hashlib
from pathlib import Path
import re

import yaml


ROOT = Path(__file__).resolve().parents[3]
SOURCE = 'docs/site/tech/privacy-policy.md'
OUTPUT = 'packages/ubaa_domain/lib/src/privacy/bundled_policy.dart'


def split_policy(source):
    match = re.fullmatch(r'---\n(.*?)\n---\n(.*)', source, re.DOTALL)
    if not match:
        raise ValueError('隐私政策缺少 frontmatter 或正文')
    return match[1], match[2]


def strip_emphasis(text):
    for marker in ('`', '**', '~~', '*'):
        escaped = re.escape(marker)
        text = re.sub(rf'{escaped}(\S(?:.*?\S)?){escaped}', r'\1', text)
    for marker in ('__', '_'):
        text = re.sub(rf'(?<!\w){marker}(\S(?:.*?\S)?){marker}(?!\w)', r'\1', text)
    return text


def plain_text(text):
    if '![' in text:
        raise ValueError('应用内隐私政策不支持图片')
    pieces = re.split(r'\[([^\]\n]+)\]\(([^\s)]+)\)', text)
    out = [strip_emphasis(pieces[0])]
    for label, address, tail in zip(pieces[1::3], pieces[2::3], pieces[3::3], strict=True):
        out.append(strip_emphasis(label))
        if address.startswith(('https://', 'http://')):
            out.append(f'（{address}）')
        out.append(strip_emphasis(tail))
    return ''.join(out)


def policy_blocks(body):
    title = None
    blocks = []
    lines = []
    kind = 'paragraph'

    def flush():
        if lines:
            blocks.append((kind, 0, plain_text(' '.join(lines))))
            lines.clear()

    for line in body.splitlines():
        if not line.strip():
            flush()
            kind = 'paragraph'
            continue
        heading = re.fullmatch(r'(#{1,6}) +(.+?) *#* *', line)
        if title is None:
            if not heading or heading[1] != '#':
                raise ValueError('隐私政策正文必须从一级标题开始')
            title = plain_text(heading[2])
            continue
        bullet = re.fullmatch(r'[-*+] +(.+)', line)
        if heading:
            flush()
            blocks.append(('heading', len(heading[1]), plain_text(heading[2])))
            kind = 'paragraph'
        elif bullet:
            flush()
            kind = 'bullet'
            lines.append(bullet[1])
        elif re.match(r'\s*(?:>|```|~~~|\||(?:[-*_] *){3,}$|\d+[.)] +|[-*+] +|<\w)', line):
            raise ValueError('隐私政策只支持标题、段落和普通无序列表')
        else:
            lines.append(line.strip())
    flush()
    if not title or not blocks:
        raise ValueError('隐私政策缺少标题或正文块')
    return title, blocks


def dart_literal(text):
    escaped = text.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
    return f"'{escaped}'"


def render(source):
    frontmatter, body = split_policy(source)
    metadata = yaml.safe_load(frontmatter)
    if not isinstance(metadata, dict):
        raise ValueError('隐私政策 frontmatter 必须是映射')
    version = metadata.get('policy_version')
    if type(version) is not int or version <= 0:
        raise ValueError('policy_version 必须是正整数')
    changes = metadata.get('policy_changes')
    if not isinstance(changes, list) or not changes or any(
        not isinstance(change, str) or not change.strip() or len(change.splitlines()) != 1
        for change in changes
    ):
        raise ValueError('policy_changes 必须是非空纯文本字符串列表')
    digest = hashlib.sha256(body.encode('utf-8')).hexdigest()
    if metadata.get('policy_body_sha256') != digest:
        raise ValueError(f'policy_body_sha256 与正文不一致；当前正文摘要为 {digest}')

    title, blocks = policy_blocks(body)
    out = [
        f'// 由 {SOURCE} 生成。',
        "import 'policy.dart';",
        '',
        'const bundledPrivacyPolicy = PrivacyPolicyDocument(',
        f'  version: {version},',
        f'  title: {dart_literal(title)},',
        '  blocks: <PrivacyPolicyBlock>[',
    ]
    for kind, level, text in blocks:
        literal = dart_literal(text)
        text_field = f'      text: {literal},'
        if len(text_field) > 80:
            text_field = f'      text:\n          {literal},'
        out.extend(['    PrivacyPolicyBlock(', f'      kind: PrivacyPolicyBlockKind.{kind},',
                    f'      level: {level},', text_field, '    ),'])
    changes_text = ', '.join(dart_literal(change.strip()) for change in changes)
    short_changes = f'  changes: <String>[{changes_text}],'
    if len(short_changes) <= 80:
        out.extend(['  ],', short_changes, ');'])
    else:
        out.extend(['  ],', '  changes: <String>[',
                    *(f'    {dart_literal(change.strip())},' for change in changes), '  ],', ');'])
    return '\n'.join(out) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default=ROOT, type=Path, help='仓库根目录')
    parser.add_argument('--write', action='store_true', help='更新应用内嵌入的 Dart 文件')
    args = parser.parse_args()
    source, output = args.root / SOURCE, args.root / OUTPUT
    expected = render(source.read_text(encoding='utf-8'))
    if args.write:
        output.write_text(expected, encoding='utf-8', newline='\n')
    elif not output.is_file() or output.read_text(encoding='utf-8') != expected:
        raise ValueError('应用内隐私政策与来源不一致；请执行 just privacy-policy-generate')
    print('已核对隐私政策版本、正文摘要和应用内嵌入的内容')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, yaml.YAMLError) as error:
        raise SystemExit(str(error)) from None
