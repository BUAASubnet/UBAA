"""工具链入口只加载工具配置，并原样转发命令参数。"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'lib'))
import toolchain

ROOT = Path(__file__).resolve().parents[3]


class ToolchainEntryTest(unittest.TestCase):
    def test_Windows执行文件及Bash参数保留空格中文(self):
        environment = {'PATH': '测试进程的PATH'}
        script = r'D:\项目 空格\scripts\check.sh'
        with patch.object(toolchain.sys, 'platform', 'win32'), patch.object(
                toolchain.shutil, 'which', return_value=r'C:\Program Files\Git\bin\bash.exe') as which:
            self.assertEqual(toolchain.bash_command(script, 'official', environment=environment),
                             [r'C:\Program Files\Git\bin\bash.exe', 'D:/项目 空格/scripts/check.sh', 'official'])
            which.assert_called_with('bash', path=environment['PATH'])
            self.assertEqual(toolchain.sdk_executable(Path('/SDK 空格'), 'flutter').name, 'flutter.bat')
            self.assertEqual(toolchain.sdk_executable(Path('/SDK 空格'), 'dart').name, 'dart.bat')
            self.assertEqual(toolchain.venv_python(Path('/质量 工具')).parts[-2:], ('Scripts', 'python.exe'))
        with patch.object(toolchain.sys, 'platform', 'linux'):
            self.assertEqual(toolchain.sdk_executable(Path('/sdk'), 'flutter'), Path('/sdk/bin/flutter'))
            self.assertEqual(toolchain.venv_python(Path('/quality')), Path('/quality/bin/python'))
            self.assertEqual(toolchain.bash_command('/项目 空格/check.sh', environment={}),
                             ['bash', '/项目 空格/check.sh'])

    def test_setup与质量环境接受盘符路径并拒绝相对路径(self):
        self.configure()
        for name in ('scripts/bootstrap/setup.sh', 'scripts/lib/repo.sh', 'scripts/lib/versions.sh',
                     'scripts/tools/versions.env', 'scripts/tools/environment.sh', 'scripts/tools/requirements.txt'):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        fakebin = self.root / 'fakebin'
        fakebin.mkdir()
        for name, source in {
            'cygpath': '#!/bin/sh\nprintf "%s\\n" "$TEST_ABSOLUTE_ROOT"\n',
            'git': '#!/bin/sh\necho synthetic-wrong-commit\n',
        }.items():
            program = fakebin / name
            program.write_text(source)
            program.chmod(0o755)
        absolute = self.root / '工具 空格'
        absolute.mkdir()
        env = {**self.environment, 'PATH': str(fakebin) + os.pathsep + self.environment['PATH'],
               'TEST_ABSOLUTE_ROOT': str(absolute)}
        for root in ('D:/工具 空格', r'D:\工具 空格', str(absolute), 'relative/path', r'D:relative'):
            accepted = root not in ('relative/path', r'D:relative')
            with self.subTest(root=root):
                current = {**env, 'UBAA_FLUTTER_HOME': root, 'UBAA_QUALITY_TOOLS_DIR': root}
                result = subprocess.run(['bash', 'scripts/bootstrap/setup.sh'], cwd=self.root,
                                        env=current, capture_output=True, text=True)
                self.assertEqual(result.returncode, 1 if accepted else 2, result.stderr)
                if accepted:
                    self.assertIn('不会改写已有 SDK', result.stderr)
                result = subprocess.run(['bash', '-euc', 'source scripts/tools/environment.sh; printf %s "$quality_root"'],
                                        cwd=self.root, env=current, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0 if accepted else 2, result.stderr)
                if accepted:
                    self.assertEqual(result.stdout, str(absolute))

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'scripts/lib').mkdir(parents=True)
        (self.root / 'scripts/tests').mkdir()
        (self.root / 'scripts/tools').mkdir()
        shutil.copyfile(ROOT / 'scripts/tools/flutter-packages.json', self.root / 'scripts/tools/flutter-packages.json')
        shutil.copyfile(ROOT / 'justfile', self.root / 'justfile')
        for name in ('toolchain.py', 'environment.py', 'repo.py'):
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

    def test_flutter_ohos导出DevEco_SDK且外部环境优先(self):
        shutil.copyfile(ROOT / 'scripts/lib/deveco.sh', self.root / 'scripts/lib/deveco.sh')
        deveco = self.root / 'deveco'
        (deveco / 'sdk').mkdir(parents=True)
        program = self.sdk / 'bin' / 'flutter'
        program.write_text('#!/usr/bin/env python3\nimport json,os\n'
                           'print(json.dumps([os.environ.get("DEVECO_SDK_HOME"), os.environ.get("OHOS_SDK_HOME")]))\n')
        self.configure()
        with (self.root / '.env.toolchain').open('a') as stream:
            stream.write(f'UBAA_DEVECO_HOME="{deveco}"\n')
        result = self.run_entry('flutter-ohos', direct=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout),
                         [str(deveco / 'sdk'), str(deveco / 'sdk/default/openharmony/native')])
        self.environment['OHOS_SDK_HOME'] = '/external/native'
        result = self.run_entry('flutter-ohos', direct=True)
        self.assertEqual(json.loads(result.stdout)[1], '/external/native')
        program.write_text('#!/usr/bin/env python3\nimport json,os\n'
                           'print(json.dumps("DEVECO_SDK_HOME" in os.environ))\n')
        result = self.run_entry('flutter', direct=True)
        self.assertEqual(json.loads(result.stdout), False)

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

    def test_CI安装向Windows原生进程导出驱动器绝对路径(self):
        for name in ('scripts/bootstrap/flutter.sh', 'scripts/lib/repo.sh',
                     'scripts/lib/versions.sh', 'scripts/tools/versions.env'):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        checker = self.root / 'scripts/check/flutter-toolchains.sh'
        checker.parent.mkdir()
        checker.write_text('#!/bin/sh\nexit 0\n')
        fakebin = self.root / 'fakebin'
        fakebin.mkdir()
        for name, source in {
            'git': '#!/bin/sh\nexit 0\n',
            'cygpath': '#!/bin/sh\nif [ "$1" = -m ]; then echo C:/ci/flutter; else echo "$2"; fi\n',
        }.items():
            tool = fakebin / name
            tool.write_text(source)
            tool.chmod(0o755)
        output = self.root / 'github-env'
        result = subprocess.run(['bash', 'scripts/bootstrap/flutter.sh'], cwd=self.root,
                                env={**self.environment, 'PATH': str(fakebin) + os.pathsep + self.environment['PATH'],
                                     'RUNNER_TEMP': str(self.root), 'GITHUB_ENV': str(output)},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output.read_text(), 'UBAA_FLUTTER_HOME=C:/ci/flutter\n')

    def test_iOS模拟器只在多架构参数缺陷时回退且保留显式架构(self):
        self.configure()
        for name in ('scripts/build/flutter.sh', 'scripts/lib/repo.sh'):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        (self.root / 'apps/ubaa_flutter').mkdir(parents=True)
        checker = self.root / 'scripts/check/flutter-toolchains.sh'
        checker.parent.mkdir()
        checker.write_text('#!/bin/sh\nexit 0\n')
        checker.chmod(0o755)
        fakebin = self.root / 'fakebin'
        fakebin.mkdir()
        for name, source in {
            'lipo': '#!/bin/sh\nprintf "%s\\n" "$LIPO_ERROR" >&2\nexit "$LIPO_STATUS"\n',
            'uname': '#!/bin/sh\necho arm64\n',
        }.items():
            tool = fakebin / name
            tool.write_text(source)
            tool.chmod(0o755)
        (self.sdk / 'bin/flutter').write_text(
            '#!/usr/bin/env python3\nimport os,sys,json\n'
            'if sys.argv[1] == "build": print(json.dumps([sys.argv[2:], os.environ.get("FLUTTER_XCODE_ARCHS")]))\n')
        defect = 'lipo: -verify_arch requires exactly one input file'
        for platform, status, error, explicit, expected in [
            ('ios-simulator', 0, '', None, None),
            ('ios-simulator', 1, defect, None, 'arm64'),
            ('ios-simulator', 1, 'does not contain architecture arm64e', None, None),
            ('ios-simulator', 127, 'command not found', None, None),
            ('ios-simulator', 1, defect, 'x86_64', 'x86_64'),
            ('macos', 1, defect, None, None),
        ]:
            with self.subTest(platform=platform, error=error, explicit=explicit):
                env = {**self.environment, 'PATH': str(fakebin) + os.pathsep + self.environment['PATH'],
                       'LIPO_ERROR': error, 'LIPO_STATUS': str(status)}
                env.pop('FLUTTER_XCODE_ARCHS', None)
                if explicit is not None:
                    env['FLUTTER_XCODE_ARCHS'] = explicit
                result = subprocess.run(['bash', 'scripts/build/flutter.sh', platform, 'debug'],
                                        cwd=self.root, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                arguments, archs = json.loads(result.stdout)
                self.assertEqual(archs, expected)
                self.assertEqual(arguments, ['ios', '--simulator', '--debug', '--no-codesign']
                                 if platform == 'ios-simulator' else ['macos', '--debug'])

    def test_质量工具与发布脚本直接调用读取项目配置(self):
        self.configure()
        for name in ('scripts/tools/environment.sh', 'scripts/tools/requirements.txt',
                     'scripts/check/shell.sh', 'scripts/release/preflight.sh', 'scripts/lib/repo.sh', 'scripts/lib/versions.sh', 'scripts/tools/versions.env',
                     'scripts/lib/checksum.sh'):
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
