#!/usr/bin/env python3
"""文档链接检查必须区分真实断链、代码样例和有效相对路径。"""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('docs_links', ROOT / 'scripts/check/docs_links.py')
links = importlib.util.module_from_spec(spec)
spec.loader.exec_module(links)


class DocsLinksTest(unittest.TestCase):
    def test_relative_encoded_reference_anchor_and_code_examples(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'docs').mkdir()
            (root / 'docs/有 空格.md').write_text('# 标题\n## 标题\n')
            page = root / 'README.md'
            page.write_text('[有效](docs/有%20空格.md#标题-1)\n'
                            '[引用][ref]\n[ref]: <docs/有 空格.md#标题>\n'
                            '`[代码](不存在.md)`\n```md\n[样例](不存在.md)\n```\n'
                            '[网络](https://example.invalid)\n')
            self.assertEqual(links.check_file(root, page), [])
            page.write_text('[文件](missing.md)\n[锚点](docs/有%20空格.md#missing)\n')
            self.assertEqual(len(links.check_file(root, page)), 2)

    def test_site_routes_assets_and_escaping_repository(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'docs/site/public').mkdir(parents=True)
            (root / 'docs/site/guide.md').write_text('# 指南')
            (root / 'docs/site/public/icon.svg').touch()
            page = root / 'docs/site/index.md'
            page.write_text('[页面](/guide)\n![图标](/icon.svg)\n[越界](../../../outside.md)')
            errors = links.check_file(root, page)
            self.assertEqual(len(errors), 1)
            self.assertIn('outside.md', errors[0])

    def test_removed_source_links_only_allow_historical_targets(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            (root / 'docs/protocol/parity').mkdir(parents=True)
            protocol = root / 'docs/protocol/parity/bhpan.md'
            source = '/'.join(('..', '..', '..', 'examples', 'ubaa_old', 'src', 'auth.kt'))
            protocol.write_text(f'[索引](../references.md)\n[来源]({source})\n[其他断链](missing.md)\n')
            agents = root / 'AGENTS.md'
            agents.write_text('[索引](docs/protocol/references.md)\n')
            readme = root / 'README.md'
            readme.write_text(agents.read_text())
            self.assertEqual(len(links.check_file(root, protocol)), 1)
            self.assertIn('missing.md', links.check_file(root, protocol)[0])
            self.assertEqual(links.check_file(root, agents), [])
            self.assertEqual(len(links.check_file(root, readme)), 1)

    def test_project_markdown_is_checked_in_former_archive_directories(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            pages = [Path('docs', 'archive', 'example.md'),
                     Path('docs', 'design', 'evidence', 'example.md'),
                     Path('packages/ubaa_bindings/cargokit/README.md')]
            for page in pages:
                path = root / page
                path.parent.mkdir(parents=True)
                path.write_text('[断链](missing.md)\n')
            tracked = '\0'.join(map(str, pages)).encode()
            with patch.object(links, 'ROOT', root), patch.object(links.subprocess, 'check_output', return_value=tracked), \
                 patch('builtins.print') as output:
                self.assertTrue(links.main())
            self.assertEqual(output.call_count, 3)
            self.assertIn('2 项错误', output.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
