#!/usr/bin/env python3
"""项目工具链配置的唯一回退解析器；不执行配置内容，不读取凭据文件。"""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
from environment import read_values
from repo import ROOT, hand_off


def bash_command(script, *arguments, environment):
    """Windows 按进程 PATH 选择 Bash，并保留脚本路径中的分隔符。"""
    bash = 'bash'
    path = str(script)
    if sys.platform == 'win32':
        bash = shutil.which('bash', path=environment.get('PATH'))
        if not bash:
            raise ValueError('请在进程 PATH 中配置 Git Bash')
        path = path.replace('\\', '/')
    return [bash, path, *arguments]


def sdk_executable(root, tool):
    suffix = '.bat' if sys.platform == 'win32' else ''
    return Path(root) / 'bin' / (tool + suffix)


def venv_python(root):
    layout = ('Scripts', 'python.exe') if sys.platform == 'win32' else ('bin', 'python')
    return Path(root).joinpath(*layout)


def load_environment(root=ROOT):
    config = root / '.env.toolchain'
    if not config.exists():
        return os.environ.copy()
    return read_values(config, environment=os.environ, expand=True)


def deveco_environment(environment):
    """OHOS Flutter 写入 local.properties 时需要 DevEco SDK；布局规则只在 deveco.sh 维护。"""
    if not environment.get('UBAA_DEVECO_HOME'):
        return environment
    result = subprocess.run(
        ['bash', '-euc', 'source "$1"; ubaa_deveco_layout; printf "%s\\n%s" "$hmos_sdk_home" "$ohos_native_home"',
         'deveco', str(ROOT / 'scripts/lib/deveco.sh')],
        env=environment, capture_output=True, text=True)
    if result.returncode:
        raise ValueError('无法从 UBAA_DEVECO_HOME 推出 DevEco SDK，请检查 .env.toolchain')
    hmos_sdk, native_sdk = result.stdout.split('\n')
    environment = environment.copy()
    environment.setdefault('DEVECO_SDK_HOME', hmos_sdk)
    environment.setdefault('OHOS_SDK_HOME', native_sdk)
    return environment


def main():
    environment = load_environment()
    if len(sys.argv) < 2:
        raise ValueError('需要 dart、flutter、flutter-ohos 或 shell 子命令')
    command = sys.argv[1]
    if command == 'venv-python':
        print(venv_python(sys.argv[2]).as_posix())
        return
    if command == 'shell':
        for key, value in environment.items():
            if key not in os.environ:
                print(f'export {key}={shlex.quote(value)}')
        return
    if command not in {'dart', 'flutter', 'flutter-ohos'}:
        raise ValueError('未知工具链子命令')
    variable = 'UBAA_OHOS_FLUTTER_HOME' if command == 'flutter-ohos' else 'UBAA_FLUTTER_HOME'
    root = environment.get(variable, '')
    tool = 'flutter' if command == 'flutter-ohos' else command
    executable = sdk_executable(root, tool)
    if not root or not Path(root).is_absolute() or not executable.is_file():
        raise ValueError(f'请在 .env.toolchain 中设置 {variable} 为包含 bin/{tool} 的 SDK 绝对路径')
    if command == 'flutter-ohos':
        environment = deveco_environment(environment)
    hand_off([str(executable), *sys.argv[2:]], environment)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
