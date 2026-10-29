#!/usr/bin/env python3
"""另一进程实际持锁，释放和父进程断开后均可重新取得 OS 锁。"""
import fcntl
from pathlib import Path
import subprocess
import tempfile
import unittest

HOLDER = Path(__file__).with_name('lock_holder.pl')


class LockHolderTest(unittest.TestCase):
    def test_other_process_owns_lock_until_release(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / '.session.lock'
            with subprocess.Popen(['perl', str(HOLDER), str(path)],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as child:
                self.assertEqual(child.stdout.readline().strip(), f'locked:{child.pid}')
                with path.open('a') as lock:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    child.stdin.write('release\n')
                    child.stdin.flush()
                    self.assertEqual(child.stdout.readline().strip(), 'released')
                    self.assertEqual(child.wait(timeout=5), 0)
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_parent_disconnect_releases_lock(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / '.session.lock'
            with subprocess.Popen(['perl', str(HOLDER), str(path)],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as child:
                self.assertEqual(child.stdout.readline().strip(), f'locked:{child.pid}')
                child.stdin.close()
                self.assertEqual(child.wait(timeout=5), 0)
                with path.open('a') as lock:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)


if __name__ == '__main__':
    unittest.main()
