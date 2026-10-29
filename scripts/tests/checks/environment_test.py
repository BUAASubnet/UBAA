#!/usr/bin/env python3
"""配置解析不执行 Shell，凭据不展开变量，重复键失败关闭。"""
from pathlib import Path
import sys
import tempfile
import unittest
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'lib'))
from environment import read_values, credentials


class EnvironmentTest(unittest.TestCase):
    def parse(self, text, **kwargs):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'config'
            path.write_text(text)
            return read_values(path, **kwargs)

    def test_quotes_spaces_comments_and_inert_shell(self):
        values = self.parse('export A = "有 空格" # 注释\nB=\'$(touch forbidden)\'\nC="a=b"\nD=\n')
        self.assertEqual(values, {'A': '有 空格', 'B': '$(touch forbidden)', 'C': 'a=b', 'D': ''})

    def test_expansion_is_only_opt_in_and_environment_wins(self):
        text = "A=external\nB=\"${A}/sdk\"\nC='$A/literal'\n"
        self.assertEqual(self.parse(text)['B'], '${A}/sdk')
        self.assertEqual(self.parse(text, environment={'A': 'provided'}, expand=True),
                         {'A': 'provided', 'B': 'provided/sdk', 'C': '$A/literal'})

    def test_invalid_or_duplicate_values_do_not_expose_contents(self):
        for text in ['A=secret\nA=secret', 'A="secret', 'A=secret words', 'A="secret\x00"']:
            with self.subTest(text=text), self.assertRaises(ValueError) as caught:
                self.parse(text)
            self.assertNotIn('secret', str(caught.exception))

    def test_both_credential_names_and_primary_precedence(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'credentials'
            path.write_text('UBAA_USERNAME=alias\nUBAA_PASSWORD=\'$literal !\'\n')
            self.assertEqual(credentials(path), b'alias\n$literal !\n')
            path.write_text(path.read_text() + 'UBAA_TEST_' + 'USERNAME=primary\nUBAA_TEST_' + 'PASSWORD="fixed"\n')
            self.assertEqual(credentials(path), b'primary\nfixed\n')
            path.write_text('UBAA_USERNAME=\n')
            with self.assertRaises(ValueError):
                credentials(path)


if __name__ == '__main__':
    unittest.main()
