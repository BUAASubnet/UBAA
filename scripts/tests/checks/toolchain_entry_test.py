"""工具链入口只加载工具配置，并原样转发命令参数。"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ToolchainEntryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'scripts/lib').mkdir(parents=True)
        (self.root / 'scripts/tests').mkdir()
        shutil.copyfile(ROOT / 'justfile', self.root / 'justfile')
        for name in ('toolchain.py',):
            source = ROOT / 'scripts/lib' / name
            if source.exists():
                shutil.copyfile(source, self.root / 'scripts/lib' / name)
        shutil.copyfile(ROOT / 'scripts/lib/toolchain.sh', self.root / 'scripts/lib/toolchain.sh')
        self.environment = {key: value for key, value in os.environ.items()
                            if not key.startswith('UBAA_')}
        self.sdk = self.root / 'sdk with spaces'
        (self.sdk / 'bin').mkdir(parents=True)
        for name in ('dart', 'flutter'):
            program = self.sdk / 'bin' / name
            program.write_text('#!/usr/bin/env python3\nimport json,sys,os\n'
                               'print(json.dumps([sys.argv[1:], "UBAA_TEST_PASSWORD" in os.environ]))\n')
            program.chmod(0o755)

    def run_entry(self, *arguments, direct=False):
        command = (['python3', 'scripts/lib/toolchain.py'] if direct else ['just'])
        return subprocess.run([*command, *arguments], cwd=self.root,
                              env=self.environment, capture_output=True, text=True)

    def configure(self):
        (self.root / '.env.toolchain').write_text(
            f'UBAA_FLUTTER_HOME="{self.sdk}"\nUBAA_OHOS_FLUTTER_HOME="{self.sdk}"\n')
        for name in ('.env.local', '.env'):
            (self.root / name).write_text('UBAA_TEST_' + 'PASSWORD=synthetic-only\n')

    def test_配置缺失仍可列出配方且SDK命令明确报错(self):
        result = self.run_entry('--list')
        self.assertEqual(result.returncode, 0, result.stderr)
        for command, variable in [('dart', 'UBAA_FLUTTER_HOME'), ('flutter', 'UBAA_FLUTTER_HOME'),
                                  ('flutter-ohos', 'UBAA_OHOS_FLUTTER_HOME')]:
            for direct in (False, True):
                with self.subTest(command=command, direct=direct):
                    result = self.run_entry(command, '--version', direct=direct)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(variable, result.stderr)
                    self.assertIn('.env.toolchain', result.stderr)

    def test_参数原样透传且不读取凭据文件(self):
        self.configure()
        arguments = ['--flag', 'has spaces', '', '"quote"', '$(touch forbidden)', '*.dart', '$HOME']
        for command in ('dart', 'flutter', 'flutter-ohos'):
            for direct in (False, True):
                result = self.run_entry(command, *arguments, direct=direct)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), [arguments, False])
                self.assertEqual(result.stderr, '')
        self.assertFalse((self.root / 'forbidden').exists())

    def test_外部环境优先且配置不执行shell(self):
        self.configure()
        (self.root / '.env.toolchain').write_text('UBAA_FLUTTER_HOME="/absent-sdk"\n')
        with (self.root / '.env.toolchain').open('a') as stream:
            stream.write('UBAA_FRB_CODEGEN="$(touch forbidden)"\n')
        self.environment['UBAA_FLUTTER_HOME'] = str(self.sdk)
        result = self.run_entry('dart', '--version', direct=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'forbidden').exists())

    def test_直接脚本回退支持HOME与空格(self):
        # 使用现有环境变量模拟 HOME 以外的自定义 SDK 根。
        self.environment['SDK_TEST_ROOT'] = str(self.root)
        (self.root / '.env.toolchain').write_text('UBAA_FLUTTER_HOME="${SDK_TEST_ROOT}/sdk with spaces"\n')
        for direct in (False, True):
            result = self.run_entry('dart', '--version', direct=direct)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_从子目录调用保留工作目录(self):
        self.configure()
        child = self.root / 'app'
        child.mkdir()
        (self.sdk / 'bin/dart').write_text('#!/usr/bin/env python3\nimport os\nprint(os.getcwd())\n')
        result = subprocess.run(['just', 'dart'], cwd=child, env=self.environment,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(result.stdout.strip()), child.resolve())

    def test_Shell脚本共用回退且不执行配置内容(self):
        self.configure()
        with (self.root / '.env.toolchain').open('a') as stream:
            stream.write('UBAA_FRB_CODEGEN="$(touch forbidden)"\n')
        result = subprocess.run(
            ['bash', '-euc', 'source scripts/lib/toolchain.sh; exec "$UBAA_FLUTTER_HOME/bin/dart" "has spaces" ""'],
            cwd=self.root, env=self.environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [['has spaces', ''], False])
        self.assertFalse((self.root / 'forbidden').exists())

    def test_质量工具与发布脚本直接调用读取项目配置(self):
        self.configure()
        for name in ('scripts/tools/environment.sh', 'scripts/tools/requirements.txt',
                     'scripts/check/shell.sh', 'scripts/release/preflight.sh', 'scripts/lib/repo.sh'):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        subprocess.run(['git', 'init', '-q'], cwd=self.root, check=True)
        quality = self.root / 'quality tools'
        with (self.root / '.env.toolchain').open('a') as stream:
            stream.write(f'UBAA_QUALITY_TOOLS_DIR="{quality}"\n'
                         f'UBAA_SHELLCHECK_BIN="{self.root}/missing-shellcheck"\n'
                         'UBAA_RELEASE_REPORT_DIR="relative-report"\n')
        commands = [
            (['bash', '-euc', 'source scripts/tools/environment.sh; printf %s "$quality_root"'],
             0, str(quality)),
            (['bash', 'scripts/check/shell.sh', 'strict'], 1, '严格门禁要求 ShellCheck'),
            (['bash', 'scripts/release/preflight.sh'], 2, '报告目录必须是绝对路径'),
        ]
        for command, status, expected in commands:
            with self.subTest(command=command):
                result = subprocess.run(command, cwd=self.root, env=self.environment,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                self.assertIn(expected, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
