"""使用合成的解码结果检查 iOS 签名配置，不接触真实签名材料。"""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('apple_signing', ROOT / 'scripts/release/platforms/apple_signing.py')
signing = importlib.util.module_from_spec(spec)
with patch.dict('os.environ', {'RUNNER_TEMP': str(ROOT / 'target/test_tmp')}):
    spec.loader.exec_module(signing)


class AppleSigningTest(unittest.TestCase):
    def test_缺少组件配置时不接触临时文件或钥匙串(self):
        with patch.dict('os.environ', {'IOS_PROVISIONING_PROFILE_BASE64': 'fixture'}, clear=True), \
                patch.object(signing, 'PRIVATE') as private, \
                patch.object(signing, 'security') as security:
            with self.assertRaisesRegex(ValueError, '缺少.*IOS_WIDGET_PROVISIONING_PROFILE_BASE64'):
                signing.prepare('ios')
            private.mkdir.assert_not_called()
            security.assert_not_called()

    def test_两个Bundle均需匹配团队和AppGroup且只接受AppStore(self):
        for bundle in ['cn.edu.ubaa', 'cn.edu.ubaa.widget']:
            entitlements = {'application-identifier': 'TESTTEAM.' + bundle, 'get-task-allow': False,
                            'com.apple.security.application-groups': ['group.cn.edu.ubaa']}
            with self.subTest(bundle=bundle):
                signing.validate_ios_profile({'Entitlements': entitlements}, 'TESTTEAM', bundle)
                for changed, message in [
                    ({'Entitlements': dict(entitlements, **{'application-identifier': 'OTHER.' + bundle})}, 'Team'),
                    ({'Entitlements': dict(entitlements, **{'com.apple.security.application-groups': []})}, 'App Group'),
                    ({'Entitlements': dict(entitlements, **{'get-task-allow': True})}, 'App Store'),
                    ({'Entitlements': entitlements, 'ProvisionedDevices': []}, 'App Store'),
                    ({'Entitlements': entitlements, 'ProvisionsAllDevices': True}, 'App Store'),
                ]:
                    with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, message):
                        signing.validate_ios_profile(changed, 'TESTTEAM', bundle)


if __name__ == '__main__':
    unittest.main()
