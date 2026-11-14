"""工具链入口只加载工具配置，并原样转发命令参数。"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'lib'))
import toolchain

ROOT = Path(__file__).resolve().parents[3]


class ToolchainEntryTest(unittest.TestCase):
    def test_Gradle准备仅重试下载且保留最后一次失败(self):
        workflow = (ROOT / '.github/workflows/flutter-platforms.yml').read_text()
        step = workflow.split('      - name: 准备 Gradle Wrapper\n', 1)[1]
        step = step.split('\n      - name:', 1)[0]
        command = textwrap.dedent(step.split('        run: |\n', 1)[1])
        fakebin = self.root / 'gradle-bin'
        fakebin.mkdir()
        sleeper = fakebin / 'sleep'
        sleeper.write_text('#!/bin/sh\nexit 0\n')
        sleeper.chmod(0o755)
        precache = fakebin / 'just'
        precache.write_text('#!/bin/sh\ntest "$*" = "flutter precache --android"\n')
        precache.chmod(0o755)
        sdk = self.root / 'sdk'
        template = sdk / 'bin/cache/artifacts/gradle_wrapper'
        (template / 'gradle/wrapper').mkdir(parents=True)
        (template / 'gradle/wrapper/gradle-wrapper.jar').write_text('合成 Wrapper')
        (self.root / 'gradle/wrapper').mkdir(parents=True)
        wrapper = template / 'gradlew'
        wrapper.write_text('''#!/bin/sh
test "$#" -eq 1 && test "$1" = --version || exit 99
count=0
test ! -f attempts || count=$(cat attempts)
count=$((count + 1))
printf '%s' "$count" > attempts
test "$count" -gt "$FAILURES" && exit 0
exit 73
''')
        wrapper.chmod(0o755)
        for failures, status, attempts in [(0, 0, 1), (2, 0, 3), (9, 73, 3)]:
            with self.subTest(failures=failures):
                counter = self.root / 'attempts'
                counter.unlink(missing_ok=True)
                (self.root / 'gradlew').unlink(missing_ok=True)
                environment = {**self.environment, 'FAILURES': str(failures),
                               'UBAA_FLUTTER_HOME': str(sdk),
                               'PATH': str(fakebin) + os.pathsep + os.environ['PATH']}
                result = subprocess.run(['bash', '-euo', 'pipefail', '-c', command],
                                        cwd=self.root, env=environment,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                self.assertEqual(int(counter.read_text()), attempts)

    def test_Cargokit所有模式必须与Rust锁定文件一致(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('tool_versions', ROOT / 'scripts/check/tool_versions.py')
        versions = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(versions)
        config = self.root / 'crates/ubaa_flutter_bridge/cargokit.yaml'
        config.parent.mkdir(parents=True)
        valid = {'cargo': {mode: {'toolchain': '1.95.0', 'extra_flags': ['--locked']}
                           for mode in ('debug', 'profile', 'release')}}
        config.write_text(json.dumps(valid))
        versions.check_cargokit_toolchains(self.root, '1.95.0')
        for mode in ('debug', 'profile', 'release'):
            for invalid in ('stable', '1.99.1', None):
                with self.subTest(mode=mode, invalid=invalid):
                    changed = json.loads(json.dumps(valid))
                    if invalid is None:
                        del changed['cargo'][mode]
                    else:
                        changed['cargo'][mode]['toolchain'] = invalid
                    config.write_text(json.dumps(changed))
                    with self.assertRaises(ValueError):
                        versions.check_cargokit_toolchains(self.root, '1.95.0')

    def test_POSIX无转换器时盘符在安装前被拒绝(self):
        self.configure()
        for name in ('scripts/bootstrap/setup.sh', 'scripts/bootstrap/quality-tools.sh',
                     'scripts/lib/repo.sh', 'scripts/lib/versions.sh', 'scripts/tools/versions.env',
                     'scripts/tools/environment.sh', 'scripts/tools/requirements.txt'):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        fakebin = self.root / 'isolated-bin'
        fakebin.mkdir()
        for name in ('bash', 'dirname'):
            (fakebin / name).symlink_to(shutil.which(name))
        marker = self.root / 'installation-calls'
        (fakebin / 'git').write_text('#!/bin/sh\nprintf git >> "$INSTALLATION_CALLS"\nexit 73\n')
        (fakebin / 'python3').write_text(
            f'#!{sys.executable}\nimport os,sys\nfrom pathlib import Path\n'
            'if sys.argv[1:3] == ["-m", "venv"]:\n'
            '    Path(os.environ["INSTALLATION_CALLS"]).write_text("venv")\n'
            '    sys.exit(73)\n'
            'os.execv(sys.executable, [sys.executable, *sys.argv[1:]])\n')
        for name in ('git', 'python3'):
            (fakebin / name).chmod(0o755)
        environment = {**self.environment, 'PATH': str(fakebin), 'INSTALLATION_CALLS': str(marker)}
        self.assertIsNone(shutil.which('cygpath', path=environment['PATH']))
        self.assertFalse((Path.home() / '.cargo/bin/cygpath').exists())
        for root in ('Z:/工具 空格', r'Z:\工具 空格'):
            for script in ('setup.sh', 'quality-tools.sh'):
                with self.subTest(root=root, script=script):
                    marker.unlink(missing_ok=True)
                    result = subprocess.run(['bash', f'scripts/bootstrap/{script}'], cwd=self.root,
                                            env={**environment, 'UBAA_FLUTTER_HOME': root,
                                                 'UBAA_QUALITY_TOOLS_DIR': root},
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertFalse(marker.exists(), '拒绝盘符路径前不得调用 Git 或创建 venv')

    def test_绝对路径转换结果必须可供POSIX消费者使用(self):
        fakebin = self.root / 'converter-bin'
        fakebin.mkdir()
        converter = fakebin / 'cygpath'
        converter.write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_CONVERTED_PATH"\nexit "$TEST_CONVERT_EXIT"\n')
        converter.chmod(0o755)
        command = ['bash', '-euc', 'source scripts/lib/toolchain.sh; ubaa_toolchain_absolute_path "$1"', 'probe']
        environment = {**self.environment, 'PATH': str(fakebin) + os.pathsep + self.environment['PATH']}
        for converted, converter_status, expected in [
            ('/d/工具 空格', 0, 0), ('//server/share/工具 空格', 0, 0),
            ('relative/path', 0, 2), ('D:/工具 空格', 0, 2), ('', 0, 2),
            ('/d/工具 空格', 73, 73),
        ]:
            with self.subTest(converted=converted, converter_status=converter_status):
                result = subprocess.run([*command, r'D:\工具 空格'], cwd=self.root,
                                        env={**environment, 'TEST_CONVERTED_PATH': converted,
                                             'TEST_CONVERT_EXIT': str(converter_status)},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual(result.stdout, converted + '\n' if expected == 0 else '')
        converter.unlink()
        self.assertIsNone(shutil.which('cygpath', path=environment['PATH']))
        for root in ('/工具 空格', '/d/工具 空格', '//server/share/工具 空格'):
            with self.subTest(root=root):
                result = subprocess.run([*command, root], cwd=self.root, env=environment,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, root + '\n')

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
        for name in ('toolchain.py', 'environment.py', 'repo.py', 'recipe.py'):
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
        (self.root / '.env').write_text(
            f'UBAA_FLUTTER_HOME="{self.sdk}"\nUBAA_OHOS_FLUTTER_HOME="{self.sdk}"\n'
            'UBAA_TEST_' + 'PASSWORD=synthetic-only\n')

    def test_仅目标构建接收签名且公共配置不引用签名密码(self):
        self.configure()
        with (self.root / '.env').open('a') as output:
            output.write('ANDROID_STORE_FILE=.sign/release.jks\n'
                         'ANDROID_STORE_PASSWORD=synthetic-store\nANDROID_KEY_ALIAS=release\n'
                         'ANDROID_KEY_PASSWORD=synthetic-key\n'
                         'UBAA_APP_SERVICE_URL="${ANDROID_KEY_PASSWORD}"\n')
        (self.sdk / 'bin/flutter').write_text(
            '#!/usr/bin/env python3\nimport json,os\n'
            'print(json.dumps([os.environ.get("ANDROID_KEY_PASSWORD"), os.environ.get("UBAA_APP_SERVICE_URL")]))\n')
        for arguments, expected in [(('pub', 'get'), None), (('test',), None),
                                    (('build', 'apk', '--debug'), None),
                                    (('build', 'apk', '--release'), 'synthetic-key'),
                                    (('build', 'appbundle'), 'synthetic-key'),
                                    (('build', 'ios', '--release'), None)]:
            with self.subTest(arguments=arguments):
                result = self.run_entry('flutter', *arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), [expected, ''])

    def test_构建脚本保留CI签名覆盖且准备步骤不取得密码(self):
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
        (self.sdk / 'bin/flutter').write_text(
            '#!/usr/bin/env python3\nimport json,os,sys\n'
            'print(json.dumps([sys.argv[1], os.environ.get("ANDROID_KEY_PASSWORD"), '
            'os.environ.get("OHOS_KEY_PASSWORD"), os.environ.get("CLOUDFLARE_API_TOKEN")]))\n')
        self.environment.update({'ANDROID_STORE_FILE': '/ci/release.jks',
                                 'ANDROID_STORE_PASSWORD': 'synthetic-store', 'ANDROID_KEY_ALIAS': 'release',
                                 'ANDROID_KEY_PASSWORD': 'synthetic-ci', 'OHOS_KEY_PASSWORD': 'synthetic-other',
                                 'CLOUDFLARE_API_TOKEN': 'synthetic-cloud'})
        for direct in (False, True):
            command = ['bash', 'scripts/build/flutter.sh'] if direct else ['just', 'flutter-build']
            result = subprocess.run([*command, 'android-apk', 'release'], cwd=self.root,
                                    env=self.environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual([json.loads(line) for line in result.stdout.splitlines()],
                             [['pub', None, None, None], ['build', 'synthetic-ci', None, None]])

    def test_OHOS按模式读取签名且无签名构建不取得材料(self):
        self.configure()
        with (self.root / '.env').open('a') as output:
            for prefix in ('OHOS_', 'OHOS_DEBUG_'):
                for suffix in ('STORE_FILE', 'STORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD', 'CERT_FILE', 'PROFILE_FILE'):
                    output.write(f'{prefix}{suffix}=synthetic-{prefix}\n')
        (self.sdk / 'bin/flutter').write_text(
            '#!/usr/bin/env python3\nimport json,os\n'
            'print(json.dumps([os.environ.get("OHOS_KEY_PASSWORD"), os.environ.get("OHOS_DEBUG_KEY_PASSWORD")]))\n')
        for arguments, expected in [(('pub', 'get'), [None, None]),
                                    (('build', 'hap', '--debug'), [None, 'synthetic-OHOS_DEBUG_']),
                                    (('build', 'hap', '--release'), ['synthetic-OHOS_', None]),
                                    (('build', 'hap', '--debug', '--no-codesign'), [None, None])]:
            result = self.run_entry('flutter-ohos', *arguments)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), expected)



    def test_普通配方及直接SDK入口过滤文件和进程中的机密键(self):
        (self.root / '.env').write_text(
            f'UBAA_FLUTTER_HOME="{self.sdk}"\n'
            'UBAA_APP_SERVICE_URL=https://service.example.invalid\n'
            'UBAA_DISTRIBUTION_CHANNEL="${CLOUDFLARE_API_TOKEN}${UBAA_TEST_USERNAME}"\n'
            'UBAA_TEST_' + 'USERNAME=synthetic-user\n'
            'CLOUDFLARE_API_' + 'TOKEN=synthetic-token\n'
            'IGNORED_FILE_KEY=synthetic-unknown\n')
        self.environment.update({'UBAA_TEST_USERNAME': 'external-user', 'UBAA_PASSWORD': 'external-password',
                                 'CLOUDFLARE_API_TOKEN': 'external-token',
                                 'UBAA_APP_SERVICE_URL': 'https://override.example.invalid'})
        probe = ('#!/usr/bin/env python3\nimport json,os\n'
                 'keys = ("UBAA_TEST_USERNAME", "UBAA_TEST_PASSWORD", "UBAA_USERNAME", "UBAA_PASSWORD", '
                 '"CLOUDFLARE_API_TOKEN", "IGNORED_FILE_KEY", "UBAA_APP_SERVICE_URL", "UBAA_DISTRIBUTION_CHANNEL")\n'
                 'print(json.dumps([os.environ.get(k) for k in keys]))\n')
        cargo = self.root / 'cargo'
        cargo.write_text(probe)
        cargo.chmod(0o755)
        (self.sdk / 'bin/dart').write_text(probe)
        self.environment['PATH'] = str(self.root) + os.pathsep + self.environment['PATH']
        for command, direct in [('fmt', False), ('dart', False), ('dart', True)]:
            with self.subTest(command=command, direct=direct):
                result = self.run_entry(command, direct=direct)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout),
                                 [None] * 6 + ['https://override.example.invalid', ''])

    def test_部署配方不再传递Cloudflare或学校凭据(self):
        (self.root / '.env').write_text(
            'UBAA_APP_SERVICE_WORKER_NAME=synthetic-worker\n'
            'UBAA_TEST_' + 'PASSWORD=synthetic-password\n'
            'CLOUDFLARE_API_' + 'TOKEN=synthetic-token\n')
        self.environment.update({'UBAA_TEST_USERNAME': 'external-user', 'UBAA_USERNAME': 'external-old-user'})
        node = self.root / 'node'
        node.write_text('#!/usr/bin/env python3\nimport json,os,sys\n'
                        'keys = ("UBAA_TEST_USERNAME", "UBAA_TEST_PASSWORD", "UBAA_USERNAME", "UBAA_PASSWORD", '
                        '"CLOUDFLARE_API_TOKEN", "UBAA_APP_SERVICE_WORKER_NAME")\n'
                        'print(json.dumps([sys.argv[-1], [os.environ.get(k) for k in keys]]))\n')
        node.chmod(0o755)
        self.environment['PATH'] = str(self.root) + os.pathsep + self.environment['PATH']
        for operation in ('deploy', 'publish'):
            with self.subTest(operation=operation):
                result = self.run_entry(f'app-service-{operation}')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout),
                                 [operation, [None] * 5 + ['synthetic-worker']])

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
                    self.assertIn('.env', result.stderr)

    def test_flutter_ohos导出DevEco_SDK且外部环境优先(self):
        shutil.copyfile(ROOT / 'scripts/lib/deveco.sh', self.root / 'scripts/lib/deveco.sh')
        deveco = self.root / 'deveco'
        (deveco / 'sdk').mkdir(parents=True)
        program = self.sdk / 'bin' / 'flutter'
        program.write_text('#!/usr/bin/env python3\nimport json,os\n'
                           'print(json.dumps([os.environ.get("DEVECO_SDK_HOME"), os.environ.get("OHOS_SDK_HOME")]))\n')
        self.configure()
        with (self.root / '.env').open('a') as stream:
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
        (self.root / '.env').write_text('UBAA_FLUTTER_HOME="/absent-sdk"\n')
        with (self.root / '.env').open('a') as stream:
            stream.write('UBAA_FRB_CODEGEN="$(touch forbidden)"\n')
        self.environment['UBAA_FLUTTER_HOME'] = str(self.sdk)
        result = self.run_entry('dart', '--version', direct=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'forbidden').exists())

    def test_直接脚本回退支持HOME与空格(self):
        # 使用现有环境变量模拟 HOME 以外的自定义 SDK 根。
        self.environment['SDK_TEST_ROOT'] = str(self.root)
        (self.root / '.env').write_text('UBAA_FLUTTER_HOME="${SDK_TEST_ROOT}/sdk with spaces"\n')
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
        with (self.root / '.env').open('a') as stream:
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

    def test_Android构建明确目标架构且保留默认全部架构(self):
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
        (self.sdk / 'bin/flutter').write_text(
            '#!/usr/bin/env python3\nimport sys,json\n'
            'if sys.argv[1] == "build": print(json.dumps(sys.argv[2:]))\n')
        for target in ('', 'android-arm', 'android-arm64', 'android-x64', 'unknown'):
            with self.subTest(target=target):
                result = subprocess.run(['bash', 'scripts/build/flutter.sh', 'android-apk', 'debug'],
                                        cwd=self.root, env={**self.environment, 'ANDROID_TARGET': target},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 2 if target == 'unknown' else 0, result.stderr)
                if target != 'unknown':
                    expected = ['apk', '--debug'] + ([f'--target-platform={target}'] if target else [])
                    self.assertEqual(json.loads(result.stdout), expected)

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
        with (self.root / '.env').open('a') as stream:
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
