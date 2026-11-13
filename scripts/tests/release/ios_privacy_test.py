"""在提交 Apple 前检查源配置和导出 IPA 的相册用途说明。"""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('ios_privacy', ROOT / 'scripts/release/platforms/ios_privacy.py')
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)


class PrivacyTest(unittest.TestCase):
    def setUp(self):
        parent = ROOT / '.ubaa_local/ios_privacy/tests'
        parent.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=parent)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def test_用途说明缺失或空白时拒绝(self):
        path = self.root / 'Info.plist'
        for info in [{}, {'NSPhotoLibraryUsageDescription': ''}, {'NSPhotoLibraryUsageDescription': '  '}]:
            path.write_bytes(plistlib.dumps(info))
            with self.assertRaisesRegex(ValueError, 'NSPhotoLibraryUsageDescription'):
                privacy.verify(path)

    def test_源配置支持XML和二进制plist(self):
        path = self.root / 'Info.plist'
        info = {'NSPhotoLibraryUsageDescription': '选择用户提交的图片'}
        for format in [plistlib.FMT_XML, plistlib.FMT_BINARY]:
            path.write_bytes(plistlib.dumps(info, fmt=format))
            self.assertEqual(privacy.verify(path), info)

    def test_导出IPA检查主应用的实际配置(self):
        path = self.root / 'app.ipa'
        for info in [{}, {'NSPhotoLibraryUsageDescription': '选择用户提交的图片'}]:
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
                archive.writestr('Payload/Runner.app/Frameworks/plugin.framework/Info.plist',
                                 plistlib.dumps({'NSPhotoLibraryUsageDescription': '插件描述不能代替应用描述'}))
            if info:
                self.assertEqual(privacy.verify(path), info)
            else:
                with self.assertRaisesRegex(ValueError, 'NSPhotoLibraryUsageDescription'):
                    privacy.verify(path)


if __name__ == '__main__':
    unittest.main()
