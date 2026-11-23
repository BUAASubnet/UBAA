"""源码规模超限只告警，Dart 模块规则仍由独立门禁阻断。"""
from pathlib import Path
from shutil import copyfile
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from scripts.lib import layout

ROOT = Path(__file__).resolve().parents[3]
CHECKER = ROOT / 'scripts/check/layout.sh'


class LayoutGateTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.git('init', '-q')
        for path in (CHECKER, Path(layout.__file__).resolve()):
            target = self.root / path.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            copyfile(path, target)

    def git(self, *args):
        subprocess.run(['git', '-C', str(self.root), *args], check=True)

    def write_source(self, relative, contents):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    def run_checker(self):
        return subprocess.run(['bash', str(self.root / 'scripts/check/layout.sh')], cwd=ROOT,
                              text=True, capture_output=True, check=False)

    def test_overlong_source_and_crowded_directory_warn_without_failing(self):
        self.write_source('src/含 空格.rs', '// 行\n' * 1000)
        for number in range(16):
            self.write_source(f'crowded/source_{number}.dart', '')
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('warning', result.stdout)

        self.write_source('src/含 空格.rs', '// 行\n' * 1000 + '// 无尾换行')
        self.write_source('crowded/extra.dart', '')
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('layout warning: src/含 空格.rs：1001 行', result.stdout)
        self.assertIn('layout warning: crowded：17 个文件', result.stdout)

    def test_index_and_worktree_are_independent(self):
        for name, staged, worktree in [('index', 1001, 1000), ('worktree', 1000, 1001)]:
            relative = f'src/{name}.swift'
            self.write_source(relative, '// 行\n' * staged)
            self.git('add', '--', relative)
            self.write_source(relative, '// 行\n' * worktree)
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ('index', 'worktree'):
            self.assertIn(f'src/{name}.swift：1001 行', result.stdout)

    def test_generated_vendored_and_ignored_exclusions(self):
        header = '\n'.join(marker.decode() for marker in layout.GENERATED_HEADERS) + '\n'
        long = '// 行\n' * 1001
        self.write_source('.gitignore', 'ignored/\n')
        self.write_source('ignored/source.rs', long)
        self.write_source('crates/ubaa_flutter_bridge/src/frb_generated.rs', header + long)
        self.write_source('packages/ubaa_bindings/lib/src/rust/frb_generated.dart', header + long)
        self.write_source('packages/ubaa_bindings/cargokit/tool/src/large.cc', long)
        self.write_source('src/.rs', header + long)
        self.write_source('packages/ubaa_bindings/lib/src/rust/manual.dart', long)
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        warnings = [line for line in result.stdout.splitlines() if line.startswith('layout warning:')]
        self.assertEqual(len(warnings), 2, warnings)
        self.assertIn('src/.rs', result.stdout)
        self.assertIn('manual.dart', result.stdout)

    def test_source_extensions_are_scanned(self):
        for extension in ('rs dart kt kts ets ts tsx js cjs py java swift m mm c cc cpp h hpp sh').split():
            with self.subTest(extension=extension):
                self.assertTrue(layout.supported(f'src/source.{extension}', []))

    def test_source_symlink_is_rejected(self):
        self.write_source('target.txt', '')
        (self.root / 'linked.rs').symlink_to('target.txt')
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('源码符号链接不允许：linked.rs', result.stderr)

    def test_git_failures_keep_layout_failing(self):
        self.write_source('src/index.rs', '')
        self.git('add', '--', 'src/index.rs')
        run = subprocess.run
        for argument in ('--stage', '--others', '--batch'):
            with self.subTest(argument=argument):
                def fail_selected(command, **kwargs):
                    if argument in command:
                        return subprocess.CompletedProcess(command, 73)
                    return run(command, **kwargs)

                with patch.object(layout.subprocess, 'run', side_effect=fail_selected):
                    with self.assertRaisesRegex(ValueError, '退出码 73'):
                        layout.main(self.root)
