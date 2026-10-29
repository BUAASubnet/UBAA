#!/usr/bin/env python3
"""在临时 Git 仓库中验证生成门禁的写入范围和漂移检测。"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class CodegenGateTest(unittest.TestCase):
    def run_gate(self, mode):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            shutil.copytree(ROOT / 'scripts', root / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
            binding = root / 'packages/ubaa_bindings'
            generated = binding / 'lib/src/rust'
            generated.mkdir(parents=True)
            (generated / 'existing.dart').write_text('原始生成物\n')
            (generated / 'frb_generated.dart').write_text("import 'frb_generated.io.dart';\n")
            rust = root / 'crates/ubaa_flutter_bridge/src'
            rust.mkdir(parents=True)
            (rust / 'frb_generated.rs').write_text('// 原始生成物\n')
            handwritten = root / 'handwritten.rs'
            handwritten.write_text('未格式化的手写内容')
            sdk = root / 'sdk/bin'
            sdk.mkdir(parents=True)
            (sdk / 'flutter').touch()
            (sdk / 'flutter').chmod(0o755)
            # 工具链版本另有完整合同，此处只隔离生成门禁自身。
            check = root / 'scripts/check/flutter-toolchains.sh'
            check.write_text('#!/usr/bin/env bash\nexit 0\n')
            check.chmod(0o755)
            codegen = root / 'generator'
            codegen.write_text('''#!/usr/bin/env python3
import os
from pathlib import Path
import sys
if '--version' in sys.argv:
    print('flutter_rust_bridge_codegen 2.13.0')
else:
    Path('lib/src/rust/frb_generated.dart').write_text("import 'frb_generated.io.dart' if (dart.library.js_interop) 'frb_generated.web.dart';" + chr(10))
if '--version' in sys.argv:
    pass
elif os.environ['CASE'] == 'untracked':
    Path('lib/src/rust/new.dart').write_text('新增生成物')
elif os.environ['CASE'] == 'tracked':
    Path('lib/src/rust/existing.dart').write_text('漂移')
elif os.environ['CASE'] == 'failure':
    raise SystemExit(7)
''')
            codegen.chmod(0o755)
            fakebin = root / 'bin'
            fakebin.mkdir()
            (fakebin / 'cargo').write_text('#!/bin/sh\nprintf 被改写 > "$TEST_ROOT/handwritten.rs"\n')
            (fakebin / 'cargo').chmod(0o755)
            (fakebin / 'rustfmt').write_text('#!/bin/sh\nexit 0\n')
            (fakebin / 'rustfmt').chmod(0o755)
            def git(*args):
                subprocess.run(['git', '-C', str(root), *args], check=True, capture_output=True)
            git('init', '-q')
            git('add', 'packages', 'crates', 'handwritten.rs')
            git('-c', 'user.name=测试', '-c', 'user.email=test@example.invalid', 'commit', '-qm', '初始')
            if mode == 'staged':
                (generated / 'existing.dart').write_text('暂存漂移')
                git('add', 'packages')
            env = {**os.environ, 'PATH': str(fakebin) + os.pathsep + os.environ['PATH'],
                   'UBAA_FLUTTER_HOME': str(sdk.parent), 'UBAA_FRB_CODEGEN': str(codegen),
                   'CASE': mode, 'TEST_ROOT': str(root)}
            result = subprocess.run(['bash', 'scripts/check/flutter-codegen.sh'], cwd=root,
                                    env=env, capture_output=True, text=True)
            self.assertEqual(handwritten.read_text(), '未格式化的手写内容')
            return result

    def test_clean_passes(self):
        result = self.run_gate('clean')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_all_drift_and_generator_failure_fail(self):
        for mode in ['untracked', 'tracked', 'staged', 'failure']:
            with self.subTest(mode=mode):
                self.assertNotEqual(self.run_gate(mode).returncode, 0)


if __name__ == '__main__':
    unittest.main()
