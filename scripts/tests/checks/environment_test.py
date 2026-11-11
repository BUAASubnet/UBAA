#!/usr/bin/env python3
"""配置解析不执行 Shell，凭据不展开变量，重复键失败关闭。"""
from pathlib import Path
import json
import os
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'lib'))
from environment import read_values, credentials
from toolchain import load_environment, migrate


class EnvironmentTest(unittest.TestCase):
    def test_签名字段按平台隔离且密码不展开(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / '.env').write_text(
                'ANDROID_STORE_FILE=".sign/android/release.jks"\n'
                'ANDROID_STORE_PASSWORD="$literal !"\n'
                'ANDROID_KEY_ALIAS=release\nANDROID_KEY_PASSWORD=synthetic-key\n'
                'OHOS_STORE_FILE=.sign/ohos/release.p12\n'
                'OHOS_STORE_PASSWORD=synthetic-store\nOHOS_KEY_ALIAS=release\n'
                'OHOS_KEY_PASSWORD=synthetic-key\nOHOS_CERT_FILE=.sign/ohos/release.cer\n'
                'OHOS_PROFILE_FILE=.sign/ohos/release.p7b\n'
                'CLOUDFLARE_API_' + 'TOKEN=synthetic-cloud\nUBAA_TEST_' + 'PASSWORD=synthetic-school\n')
            with patch.dict(os.environ, {}, clear=True):
                android = load_environment(root, scope='android')
                self.assertEqual(android['ANDROID_STORE_PASSWORD'], '$literal !')
                self.assertEqual(android['ANDROID_STORE_FILE'], str(root / '.sign/android/release.jks'))
                ohos = load_environment(root, scope='ohos')
                self.assertEqual(ohos['OHOS_PROFILE_FILE'], str(root / '.sign/ohos/release.p7b'))
                for scope, prefix in [('normal', None), ('android', 'ANDROID_'), ('ohos', 'OHOS_')]:
                    result = load_environment(root, scope=scope)
                    self.assertNotIn('CLOUDFLARE_API_TOKEN', result)
                    self.assertNotIn('UBAA_TEST_PASSWORD', result)
                    for key in (*android, *ohos):
                        if prefix is None or not key.startswith(prefix):
                            self.assertNotIn(key, result)

    def test_进程签名整组覆盖且缺项不借用本机密码(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            keys = ['ANDROID_STORE_FILE', 'ANDROID_STORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD']
            (root / '.env').write_text('\n'.join(f'{key}=local-value' for key in keys))
            with patch.dict(os.environ, {'ANDROID_STORE_FILE': '/ci/release.jks'}, clear=True):
                with self.assertRaisesRegex(ValueError, 'ANDROID_STORE_PASSWORD'):
                    load_environment(root, scope='android')
                self.assertNotIn('ANDROID_STORE_FILE', load_environment(root))
            with patch.dict(os.environ, dict.fromkeys(keys, ''), clear=True):
                self.assertTrue(all(load_environment(root, scope='android')[key] == '' for key in keys))

    def parse(self, text, **kwargs):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'config'
            path.write_text(text)
            return read_values(path, **kwargs)

    def test_quotes_spaces_comments_and_inert_shell(self):
        values = self.parse('export A = "有 空格" # 注释\nB=\'$(touch forbidden)\'\nC="a=b"\nD=\n')
        self.assertEqual(values, {'A': '有 空格', 'B': '$(touch forbidden)', 'C': 'a=b', 'D': ''})

    def test_expansion_is_only_opt_in_and_environment_wins(self):
        text = "A=external\nB=\"${A}/sdk\"\nC='$A/literal'\n"
        self.assertEqual(self.parse(text)['B'], '${A}/sdk')
        self.assertEqual(self.parse(text, environment={'A': 'provided'}, expand=True),
                         {'A': 'provided', 'B': 'provided/sdk', 'C': '$A/literal'})

    def test_invalid_or_duplicate_values_do_not_expose_contents(self):
        for text in ['A=secret\nA=secret', 'A="secret', 'A=secret words', 'A="secret\x00"']:
            with self.subTest(text=text), self.assertRaises(ValueError) as caught:
                self.parse(text)
            self.assertNotIn('secret', str(caught.exception))

    def test_both_credential_names_and_primary_precedence(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'credentials'
            path.write_text('UBAA_USER' + 'NAME=alias\nUBAA_PASS' + 'WORD=\'$literal !\'\n')
            self.assertEqual(credentials(read_values(path)), b'alias\n$literal !\n')
            path.write_text(path.read_text() + 'UBAA_TEST_' + 'USERNAME=primary\nUBAA_TEST_' + 'PASSWORD="fixed"\n')
            self.assertEqual(credentials(read_values(path)), b'primary\nfixed\n')
            path.write_text('UBAA_USERNAME=\n')
            with self.assertRaises(ValueError):
                credentials(read_values(path))

    def test_缺少根配置时提示迁移但不读取旧文件(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ('.env.toolchain', '.env.local'):
                (root / name).write_text('这不是有效的配置行')
            for scope in ('normal', 'live', 'deploy'):
                with self.subTest(scope=scope), self.assertRaises(ValueError) as caught:
                    load_environment(root, scope=scope)
                for text in ('.env.toolchain', '.env.local', 'UBAA_FLUTTER_HOME',
                             'UBAA_TEST_USERNAME', 'migrate'):
                    self.assertIn(text, str(caught.exception))

    def test_迁移合并工具账号和目标且保留既有键和私有权限(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / '.env'
            config.write_text('UBAA_FLUTTER_HOME=/existing')
            toolchain = root / '.env.toolchain'
            toolchain.write_text('UBAA_FLUTTER_HOME=/old\nUBAA_OHOS_FLUTTER_HOME="$HOME/合成 sdk"\n')
            legacy_live = root / '.env.local'
            legacy_live.write_text('UBAA_USER' + 'NAME=synthetic-user\nUBAA_PASS' + 'WORD="$literal !"\n')
            target = root / 'target.json'
            target.write_text(json.dumps(dict(account_id='account', worker_name='worker', database_id='db',
                                              kv_namespace_id='kv', domain='service.example.invalid')))
            with patch.dict(os.environ, {'HOME': '/synthetic'}, clear=True):
                migrate(root, target)
                self.assertEqual(credentials(load_environment(root, scope='live')), b'synthetic-user\n$literal !\n')
                self.assertEqual(load_environment(root)['UBAA_FLUTTER_HOME'], '/existing')
                self.assertEqual(load_environment(root)['UBAA_OHOS_FLUTTER_HOME'], '/synthetic/合成 sdk')
                self.assertEqual(load_environment(root)['UBAA_APP_SERVICE_DOMAIN'], 'service.example.invalid')
                before = config.read_text()
                migrate(root, target)
                self.assertEqual(config.read_text(), before)
            self.assertTrue(toolchain.is_file())
            self.assertTrue(legacy_live.is_file())
            if os.name != 'nt':
                self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)


if __name__ == '__main__':
    unittest.main()
