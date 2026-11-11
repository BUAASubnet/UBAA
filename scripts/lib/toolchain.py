#!/usr/bin/env python3
"""按入口白名单加载项目根目录的 .env，不执行配置内容。"""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
from environment import credentials, read_values
from repo import ROOT, hand_off

TOOL_KEYS = frozenset({
    'UBAA_FLUTTER_HOME', 'UBAA_OHOS_FLUTTER_HOME', 'UBAA_DEVECO_HOME', 'UBAA_HMOS_SDK_HOME',
    'UBAA_OHOS_NODE_HOME', 'OHOS_SDK_HOME', 'UBAA_FRB_CODEGEN', 'UBAA_SHELLCHECK_BIN',
    'UBAA_QUALITY_TOOLS_DIR', 'UBAA_RELEASE_REPORT_DIR', 'UBAA_UI_EVIDENCE_DIR',
    'UBAA_FLUTTER_VERBOSE', 'UBAA_OHOS_NO_CODESIGN',
})
TARGET_KEYS = {
    'account_id': 'UBAA_APP_SERVICE_ACCOUNT_ID', 'worker_name': 'UBAA_APP_SERVICE_WORKER_NAME',
    'database_id': 'UBAA_APP_SERVICE_D1_ID', 'kv_namespace_id': 'UBAA_APP_SERVICE_KV_NAMESPACE_ID',
    'domain': 'UBAA_APP_SERVICE_DOMAIN',
}
PUBLIC_KEYS = TOOL_KEYS | set(TARGET_KEYS.values()) | {'UBAA_APP_SERVICE_ZONE_ID', 'UBAA_APP_SERVICE_URL', 'UBAA_DISTRIBUTION_CHANNEL'}
LIVE_KEYS = frozenset({'UBAA_TEST_USERNAME', 'UBAA_TEST_PASSWORD', 'UBAA_USERNAME', 'UBAA_PASSWORD'})
DEPLOY_KEYS = frozenset({'CLOUDFLARE_API_TOKEN'})
ANDROID_FIELDS = ('STORE_FILE', 'STORE_PASSWORD', 'KEY_ALIAS', 'KEY_PASSWORD')
OHOS_FIELDS = (*ANDROID_FIELDS, 'CERT_FILE', 'PROFILE_FILE')
SIGNING_GROUPS = {
    'android': ('ANDROID_', ANDROID_FIELDS),
    'ohos': ('OHOS_', OHOS_FIELDS),
    'ohos-debug': ('OHOS_DEBUG_', OHOS_FIELDS),
}
SIGNING_KEYS = frozenset(prefix + field for prefix, fields in SIGNING_GROUPS.values()
                         for field in fields) | {
    'OHOS_SIGN_ALG', 'OHOS_DEBUG_SIGN_ALG',
    'ANDROID_SIGNING_PROPERTIES', *('UBAA_RELEASE_' + field for field in ANDROID_FIELDS),
}
SECRET_KEYS = LIVE_KEYS | DEPLOY_KEYS | SIGNING_KEYS
LEGACY_FILES = {'.env.toolchain': TOOL_KEYS, '.env.local': LIVE_KEYS}


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


def load_environment(root=ROOT, *, scope='normal'):
    secret_keys = {'live': LIVE_KEYS, 'deploy': DEPLOY_KEYS}.get(scope, frozenset())
    if scope not in {'normal', 'live', 'deploy', *SIGNING_GROUPS}:
        raise ValueError('未知配置读取范围')
    # 公共配置的变量引用也只能看到公共环境，避免通过引用把机密转成公共键。
    environment = {key: value for key, value in os.environ.items() if key.upper() not in SECRET_KEYS}
    config = root / '.env'
    if not config.exists():
        legacy = [f'{name}（{"、".join(sorted(keys))}）' for name, keys in LEGACY_FILES.items()
                  if (root / name).exists()]
        if legacy:
            raise ValueError('缺少根目录 .env。请将旧配置中的键迁入 .env：' + '；'.join(legacy) +
                             '。迁移命令：python3 scripts/lib/toolchain.py migrate')
    else:
        environment = read_values(config, environment=environment, expand=True, keys=PUBLIC_KEYS)
    if secret_keys:
        secrets = {key: value for key, value in os.environ.items() if key in secret_keys}
        if config.exists():
            secrets = read_values(config, environment=secrets, keys=secret_keys)
        environment.update(secrets)
    if scope in SIGNING_GROUPS:
        environment.update(signing_environment(root, scope, environment))
    return environment


def signing_environment(root, scope, public):
    """进程和文件按整组选择签名材料，路径以仓库为基准，密码保持字面值。"""
    prefix, fields = SIGNING_GROUPS[scope]
    required = tuple(prefix + field for field in fields)
    keys = set(required)
    if scope.startswith('ohos'):
        keys.add(prefix + 'SIGN_ALG')
    supplied = {key: value for key, value in os.environ.items() if key in keys}
    if not supplied and (root / '.env').exists():
        supplied = read_values(root / '.env', keys=keys)
        paths = {key for key in keys if key.endswith('_FILE')}
        expanded = read_values(root / '.env', environment=public, expand=True, keys=paths)
        supplied.update({key: expanded[key] for key in paths if key in supplied})
    if any(supplied.values()):
        missing = [key for key in required if not supplied.get(key)]
        if missing:
            raise ValueError('签名配置缺少：' + '、'.join(missing))
        for key in required:
            if key.endswith('_FILE'):
                supplied[key] = os.path.abspath(root / supplied[key])
    if scope == 'android' and not supplied:
        # 保留原有原生工具入口；统一字段一旦提供便不混入旧字段。
        supplied = {key: value for key, value in os.environ.items()
                    if key == 'ANDROID_SIGNING_PROPERTIES'
                    or (key.startswith('UBAA_RELEASE_') and key in SIGNING_KEYS)}
    return supplied


def build_scope(command, arguments):
    """仅构建目标读取签名；依赖准备、分析、测试及无签名构建使用公共配置。"""
    if len(arguments) < 2 or arguments[0] != 'build' or '--no-codesign' in arguments:
        return 'normal'
    target = arguments[1]
    if command == 'flutter' and target in {'apk', 'appbundle'}:
        return 'normal' if '--debug' in arguments or '--profile' in arguments else 'android'
    if command == 'flutter-ohos' and target in {'hap', 'app'}:
        return 'ohos-debug' if '--debug' in arguments else 'ohos'
    return 'normal'


def migrate(root, target_path=None):
    """由维护者显式运行，保留现有键和旧文件，写入私有 .env。"""
    config = root / '.env'
    had_config = config.exists()
    existing = read_values(config) if had_config else {}
    additions = {}
    for name, keys in LEGACY_FILES.items():
        legacy = root / name
        if legacy.is_file():
            # 保留路径中的变量引用；凭据不展开，按字面值迁移。
            additions.update(read_values(legacy, keys=keys, keep_syntax=True))
    if target_path:
        try:
            target = json.loads(Path(target_path).read_text(encoding='utf-8'))
        except (OSError, ValueError):
            raise ValueError('无法读取旧部署目标 JSON') from None
        if not isinstance(target, dict) or set(target) != set(TARGET_KEYS) or any(
                not isinstance(value, str) or not value or any(c in value for c in '\x00\r\n')
                for value in target.values()):
            raise ValueError('旧部署目标 JSON 缺少有效字段：' + '、'.join(TARGET_KEYS))
        additions.update({TARGET_KEYS[key]: shlex.quote(value) for key, value in target.items()})
    additions = {key: value for key, value in additions.items() if key not in existing}
    if not additions and not had_config:
        raise ValueError('没有可迁移的键；请按 .env.example 创建根目录 .env')
    descriptor = os.open(config, os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, 'a', encoding='utf-8') as output:
        config.chmod(0o600)
        if additions:
            if had_config:
                output.write('\n')
            for key, value in additions.items():
                output.write(f'{key}={value}\n')
    print(f'已迁移 {len(additions)} 个键到 .env；保留现有键和旧文件。')


def deveco_environment(environment):
    """OHOS Flutter 写入 local.properties 时需要 DevEco SDK；布局规则只在 deveco.sh 维护。"""
    if not environment.get('UBAA_DEVECO_HOME'):
        return environment
    result = subprocess.run(
        ['bash', '-euc', 'source "$1"; ubaa_deveco_layout; printf "%s\\n%s" "$hmos_sdk_home" "$ohos_native_home"',
         'deveco', str(ROOT / 'scripts/lib/deveco.sh')],
        env=environment, capture_output=True, text=True)
    if result.returncode:
        raise ValueError('无法从 UBAA_DEVECO_HOME 推出 DevEco SDK，请检查 .env')
    hmos_sdk, native_sdk = result.stdout.split('\n')
    environment = environment.copy()
    environment.setdefault('DEVECO_SDK_HOME', hmos_sdk)
    environment.setdefault('OHOS_SDK_HOME', native_sdk)
    return environment


def main():
    if len(sys.argv) < 2:
        raise ValueError('需要 dart、flutter、flutter-ohos 或 shell 子命令')
    command, *arguments = sys.argv[1:]
    if command == 'venv-python':
        print(venv_python(arguments[0]).as_posix())
        return
    if command == 'migrate':
        if arguments and (len(arguments) != 2 or arguments[0] != '--target'):
            raise ValueError('用法：python3 scripts/lib/toolchain.py migrate [--target <旧目标 JSON>]')
        migrate(ROOT, arguments[1] if arguments else None)
        return
    if command == 'release':
        if arguments not in (['deploy'], ['publish']):
            raise ValueError('应用服务命令须为 deploy 或 publish，目标从 .env 或进程环境读取')
        os.chdir(ROOT)
        # 直接导入发布模块，避免递归调用 CLI，也不把 Token 写入参数或 stdout。
        entry = ("import {runRelease} from './scripts/release/app_service/release.mjs'; "
                 'try { await runRelease(process.argv[1]); } '
                 'catch (error) { console.error(error.message); process.exitCode = 1; }')
        hand_off(['node', '--input-type=module', '-e', entry, *arguments], load_environment(scope='deploy'))
        return
    if command == 'live':
        environment = load_environment(scope='live')
        material = credentials(environment)
        for key in LIVE_KEYS:
            environment.pop(key, None)
        raise SystemExit(subprocess.run(arguments, env=environment, input=material).returncode)
    environment = load_environment(scope=build_scope(command, arguments))
    if command == 'shell':
        if arguments not in ([], ['build']):
            raise ValueError('shell 只接受可选的 build 参数')
        for key in os.environ:
            if key.upper() in SECRET_KEYS and not (arguments == ['build'] and key.upper() in SIGNING_KEYS):
                print(f'unset {key}')
        for key, value in environment.items():
            if key not in os.environ:
                print(f'export {key}={shlex.quote(value)}')
        return
    if command == 'recipe-shell':
        hand_off(bash_command('-euo', 'pipefail', '-c', *arguments, environment=environment), environment)
        return
    if command not in {'dart', 'flutter', 'flutter-ohos'}:
        raise ValueError('未知工具链子命令')
    variable = 'UBAA_OHOS_FLUTTER_HOME' if command == 'flutter-ohos' else 'UBAA_FLUTTER_HOME'
    root = environment.get(variable, '')
    tool = 'flutter' if command == 'flutter-ohos' else command
    executable = sdk_executable(root, tool)
    if not root or not Path(root).is_absolute() or not executable.is_file():
        raise ValueError(f'请在 .env 中设置 {variable} 为包含 bin/{tool} 的 SDK 绝对路径')
    if command == 'flutter-ohos':
        environment = deveco_environment(environment)
    hand_off([str(executable), *arguments], environment)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from None
