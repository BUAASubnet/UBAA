"""目录规则覆盖自有目录、框架限定路径和冻结输入。"""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'check'))
from directory_names import find_violations


class DirectoryNamesTest(unittest.TestCase):
    def test_owned_directories_reject_hyphens_but_keep_filenames(self):
        self.assertEqual(find_violations([
            'crates/ubaa-core/src/lib.rs', 'crates/ubaa-core/README.md',
            'apps/ubaa_cli/src/lib.rs', 'docs/source-parity.md',
            'scripts/live/offline-startup/run.py',
        ]), ['crates/ubaa-core', 'scripts/live/offline-startup'])

    def test_frozen_and_framework_directories_keep_original_paths(self):
        self.assertEqual(find_violations([
            'examples/buaa-api/src/lib.rs',
            'packages/ubaa_bindings/cargokit/third-party/file.rs',
            'docs/design/evidence/ui-ux/old-p5-native/info.json',
            'apps/ubaa_flutter/android/app/src/main/res/mipmap-hdpi/icon.png',
            'apps/ubaa_ohos/ohos/entry/src/main/resources/zh_CN/string.json',
        ]), [])

    def test_exceptions_cannot_hide_owned_sibling_or_nested_directories(self):
        self.assertEqual(find_violations([
            'crates/new-package/src/lib.rs',
            'packages/ubaa_bindings/new-code/file.dart',
            'docs/design/evidence/new-batch/README.md',
            'apps/ubaa_flutter/android/app/src/main/res/drawable-v21/new-code/x.xml',
        ]), [
            'apps/ubaa_flutter/android/app/src/main/res/drawable-v21/new-code',
            'crates/new-package', 'docs/design/evidence/new-batch',
            'packages/ubaa_bindings/new-code',
        ])


if __name__ == '__main__':
    unittest.main()
