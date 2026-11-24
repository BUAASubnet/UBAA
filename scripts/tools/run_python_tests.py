#!/usr/bin/env python3
"""在一个进程中运行脚本测试目录下的全部 Python 测试。"""
import importlib.util
from pathlib import Path
import sys
import traceback
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
TEST_ROOT = REPO_ROOT / 'scripts/tests'
sys.path.insert(0, str(REPO_ROOT))


def main():
    loader = unittest.defaultTestLoader
    test_files = set(TEST_ROOT.rglob('*_test.py'))
    test_files.add(REPO_ROOT / 'scripts/live/offline_startup/analyze_test.py')
    failed = False
    for index, path in enumerate(sorted(test_files)):
        module_name = f'script_test_{index}'
        spec = importlib.util.spec_from_file_location(module_name, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        sys.path.insert(0, str(path.parent))
        try:
            spec.loader.exec_module(module)
        except Exception:
            print(f'加载测试失败：{path.relative_to(REPO_ROOT)}', file=sys.stderr)
            traceback.print_exc()
            failed = True
            continue
        finally:
            sys.path.remove(str(path.parent))
        suite = loader.loadTestsFromModule(module)
        print(f'测试文件：{path.relative_to(REPO_ROOT)}', flush=True)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        failed |= not result.wasSuccessful()
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
