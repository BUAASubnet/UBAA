#!/usr/bin/env python3
"""关键字与位置参数共用校验，路径和 Shell 元字符不拆分。"""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('recipe', ROOT / 'scripts/lib/recipe.py')
recipe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recipe)


class RecipeArgsTest(unittest.TestCase):
    def test_single_argument_recipe_still_dispatches(self):
        with patch.object(recipe.sys, 'argv', ['recipe.py', 'ohos-check']), \
                patch.object(recipe.os, 'chdir'), patch.object(recipe.os, 'execvpe') as execute:
            recipe.main()
        self.assertEqual(execute.call_args.args[1], ['bash', 'scripts/build/ohos.sh', 'release'])

    def test_positional_and_named_forms_are_equivalent(self):
        self.assertEqual(recipe.values('flutter-build', ['linux', 'debug']),
                         recipe.values('flutter-build', ['mode=debug', 'platform=linux']))
        self.assertEqual(recipe.values('flutter-test', ['package=ubaa_ui', 'path=test/有 空格']),
                         ['ubaa_ui', 'test/有 空格'])
        self.assertEqual(recipe.values('release-preflight', ['report_dir=/tmp/a=b']), ['/tmp/a=b', 'strict'])
        self.assertEqual(recipe.values('check-plan', []), ['', 'commit'])
        self.assertEqual(recipe.values('check-changed', ['mode=full', 'base=HEAD~2']), ['HEAD~2', 'full'])
        self.assertEqual(recipe.values('flutter-artifact-check', ['macos', '$(touch forbidden)']),
                         ['macos', '$(touch forbidden)'])

    def test_native_device_defaults_to_platform(self):
        self.assertEqual(recipe.values('integration-test', ['platform=linux']), ['ci', 'linux', ''])

    def test_发布报告模式必须显式选择(self):
        self.assertEqual(recipe.values('release-preflight', []), ['', 'strict'])
        self.assertEqual(recipe.values('release-preflight', ['mode=report', 'report_dir=/tmp/report']),
                         ['/tmp/report', 'report'])

    def test_missing_duplicate_unknown_and_extra_arguments_fail(self):
        for name, args in [('flutter-test', []), ('flutter-build', ['platform=linux', 'platform=macos']),
                           ('check-plan', ['unknown=value']), ('flutter-build', ['a','b','c'])]:
            with self.subTest(name=name, args=args), self.assertRaises(ValueError):
                recipe.values(name, args)


if __name__ == '__main__':
    unittest.main()
