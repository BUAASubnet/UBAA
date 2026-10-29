#!/usr/bin/env python3
"""关键字与位置参数共用校验，路径和 Shell 元字符不拆分。"""
import importlib.util
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('recipe', ROOT / 'scripts/lib/recipe.py')
recipe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recipe)


class RecipeArgsTest(unittest.TestCase):
    def test_positional_and_named_forms_are_equivalent(self):
        self.assertEqual(recipe.values('flutter-build', ['linux', 'debug']),
                         recipe.values('flutter-build', ['mode=debug', 'platform=linux']))
        self.assertEqual(recipe.values('flutter-test', ['package=ubaa_ui', 'path=test/有 空格']),
                         ['ubaa_ui', 'test/有 空格'])
        self.assertEqual(recipe.values('release-preflight', ['report_dir=/tmp/a=b']), ['/tmp/a=b'])
        self.assertEqual(recipe.values('check-plan', []), [''])
        self.assertEqual(recipe.values('flutter-artifact-check', ['macos', '$(touch forbidden)']),
                         ['macos', '$(touch forbidden)'])

    def test_native_device_defaults_to_platform(self):
        self.assertEqual(recipe.values('integration-test', ['platform=linux']), ['ci', 'linux', ''])

    def test_missing_duplicate_unknown_and_extra_arguments_fail(self):
        for name, args in [('flutter-test', []), ('flutter-build', ['platform=linux', 'platform=macos']),
                           ('check-plan', ['unknown=value']), ('flutter-build', ['a','b','c'])]:
            with self.subTest(name=name, args=args), self.assertRaises(ValueError):
                recipe.values(name, args)


if __name__ == '__main__':
    unittest.main()
