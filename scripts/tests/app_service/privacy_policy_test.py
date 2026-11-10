"""从 Markdown 到应用内政策的失败反例和生成检查。"""

import hashlib
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest


ROOT = Path(__file__).resolve().parents[3]
CHECKER = ROOT / 'scripts/check/app_service/privacy_policy.py'
SOURCE = 'docs/site/tech/privacy-policy.md'
OUTPUT = 'packages/ubaa_domain/lib/src/privacy/bundled_policy.dart'
BODY = '''
# 合成隐私政策

## 目的

支持 **缺陷定位**、*改进*和 `离线阅读`。

- 通过 [GitHub](https://example.invalid/contact) 反馈。
'''


class PrivacyPolicyTest(unittest.TestCase):
    def setUp(self):
        workspace = TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        self.root = Path(workspace.name)
        self.source = self.root / SOURCE
        self.source.parent.mkdir(parents=True)
        self.output = self.root / OUTPUT
        self.output.parent.mkdir(parents=True)
        self.digest = hashlib.sha256(BODY.encode()).hexdigest()
        self.write_source()

    def write_source(self, *, body=BODY, changes='\n  - 首次发布', digest=None):
        self.source.write_text(
            f'---\npolicy_version: 2\npolicy_body_sha256: {digest or self.digest}\n'
            f'policy_changes:{changes}\n---\n{body}',
            encoding='utf-8',
        )

    def run_checker(self, *args):
        return subprocess.run(
            [sys.executable, str(CHECKER), '--root', str(self.root), *args],
            capture_output=True, text=True, check=False,
        )

    def assert_generation_succeeds(self):
        generated = self.run_checker('--write')
        self.assertEqual(generated.returncode, 0, generated.stderr)

    def test_changed_body_requires_updated_digest(self):
        self.write_source(body=BODY.replace('离线阅读', '数据删除'))
        result = self.run_checker('--write')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('policy_body_sha256 与正文不一致', result.stderr)
        self.assertFalse(self.output.exists())

    def test_changed_source_or_edited_output_fails_read_only_check(self):
        self.assert_generation_succeeds()
        previous = self.output.read_bytes()
        self.write_source(changes='\n  - 更新保留期')
        result = self.run_checker()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('应用内隐私政策与来源不一致', result.stderr)
        self.assertEqual(self.output.read_bytes(), previous)
        self.assert_generation_succeeds()
        self.output.write_bytes(previous)
        self.assertEqual(self.run_checker().returncode, 1)

    def test_rejects_changes_that_are_not_plain_string_lists(self):
        for changes in [' 首次发布', '\n  - 12', '\n  - {title: 首次发布}', '\n  - " "']:
            with self.subTest(changes=changes):
                self.write_source(changes=changes)
                result = self.run_checker('--write')
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn('policy_changes 必须是非空纯文本字符串列表', result.stderr)

    def test_embeds_version_changes_and_readable_markdown(self):
        self.assert_generation_succeeds()
        output = self.output.read_text(encoding='utf-8')
        for value in ['version: 2', "title: '合成隐私政策'", 'PrivacyPolicyBlockKind.heading',
                      'level: 2', 'PrivacyPolicyBlockKind.paragraph', 'PrivacyPolicyBlockKind.bullet',
                      '支持 缺陷定位、改进和 离线阅读。', 'GitHub（https://example.invalid/contact）',
                      "changes: <String>['首次发布']"]:
            self.assertIn(value, output)
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
