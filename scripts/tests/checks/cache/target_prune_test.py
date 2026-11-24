#!/usr/bin/env python3
"""检查增量缓存清理仅移除七天未修改的 Cargo 子目录。"""
from contextlib import redirect_stdout
import importlib.util
from io import StringIO
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
spec = importlib.util.spec_from_file_location('build_cache', ROOT / 'scripts/build/cache.py')
pruner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pruner)


class IncrementalPruneTest(unittest.TestCase):
    def test_reports_then_removes_old_directories_and_preserves_recent_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / '.git/info/exclude').write_text('/target/\n')
            old = root / 'target/debug/incremental/old-unit'
            old.mkdir(parents=True)
            (old / 'object.o').write_bytes(b'old')
            recent = root / 'target/debug/incremental/recent-unit'
            recent.mkdir()
            (recent / 'object.o').write_bytes(b'new')
            unrelated = root / 'target/debug/deps/old-unit'
            unrelated.mkdir(parents=True)
            now = time.time()
            old_time = now - 9 * 24 * 60 * 60
            for path in (old / 'object.o', old, recent, unrelated):
                os.utime(path, (old_time, old_time))
            original = pruner.shutil.rmtree
            stream = StringIO()

            def remove_after_report(path):
                self.assertIn('target/debug/incremental/old-unit', stream.getvalue())
                self.assertIn('合计', stream.getvalue())
                self.assertTrue(path.exists())
                original(path)

            with redirect_stdout(stream), patch.object(pruner.shutil, 'rmtree', side_effect=remove_after_report):
                pruner.prune_target(root, now)
            self.assertFalse(old.exists())
            self.assertTrue(recent.exists())
            self.assertTrue(unrelated.exists())


if __name__ == '__main__':
    unittest.main()
