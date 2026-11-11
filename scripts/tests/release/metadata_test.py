"""发布入口必须拒绝非主线候选和与产品版本不一致的 Tag。"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class MetadataTest(unittest.TestCase):
    def test_发布候选与Tag(self):
        parent = ROOT / '.ubaa_local/release_metadata_tests'
        parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=parent) as folder:
            root = Path(folder)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL, text=True).strip()
            git('init', '-q')
            git('config', 'user.name', '合成测试')
            git('config', 'user.email', 'fixture@example.invalid')
            (root / 'version.toml').write_text('version="2.0.0"\nbuild_number=2003\n')
            git('add', 'version.toml')
            git('commit', '-qm', '合成候选')
            git('update-ref', 'refs/remotes/origin/main', 'HEAD')
            def run(tag):
                return subprocess.run(['python3', str(ROOT / 'scripts/release/metadata.py')], cwd=root,
                                      env={**os.environ, 'RELEASE_TAG': tag, 'GITHUB_OUTPUT': str(root / 'output')},
                                      capture_output=True, text=True)
            self.assertEqual(run('v2.0.0').returncode, 0)
            self.assertNotEqual(run('v2.0.1').returncode, 0)
            (root / 'next.txt').write_text('尚未合并')
            git('add', 'next.txt')
            git('commit', '-qm', '合成开发提交')
            self.assertNotEqual(run('v2.0.0').returncode, 0)


if __name__ == '__main__':
    unittest.main()
