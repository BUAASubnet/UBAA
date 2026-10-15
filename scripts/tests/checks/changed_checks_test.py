#!/usr/bin/env python3
"""按改动选择门禁的行为测试，覆盖漏选和 Git 路径边界。"""
import importlib.util
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('changed_checks', ROOT / 'scripts/check/changed_checks.py')
gates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gates)


class ChangedChecksTest(unittest.TestCase):
    def plan(self, *paths):
        return gates.select_checks(ROOT, paths)

    def test_docs_do_not_trigger_language_suites(self):
        plan = self.plan('docs/migration/status.md', 'README.md', 'goal.md', 'scripts/README.md', 'packages/ubaa_ui/README.md')
        self.assertFalse(plan['rust'])
        self.assertEqual(plan['packages'], [])
        self.assertEqual(plan['extra'], [])

    def test_ui_implementation_includes_consumers(self):
        self.assertEqual(self.plan('packages/ubaa_ui/lib/src/app/home.dart')['packages'],
                         ['ubaa_ui', 'ubaa_host', 'ubaa_flutter'])

    def test_app_implementation_includes_ui_test_dependency(self):
        self.assertEqual(self.plan('packages/ubaa_app/lib/src/write/coordinator.dart')['packages'],
                         ['ubaa_app', 'ubaa_ui', 'ubaa_host', 'ubaa_flutter'])

    def test_domain_reaches_all_consumers_but_not_unrelated_bindings(self):
        plan = self.plan('packages/ubaa_domain/lib/src/models.dart')
        self.assertEqual(plan['packages'],
                         ['ubaa_domain', 'ubaa_platform', 'ubaa_app', 'ubaa_ui', 'ubaa_host', 'ubaa_flutter'])

    def test_tests_only_check_own_package(self):
        self.assertEqual(self.plan('packages/ubaa_ui/test/navigation/read_test.dart')['packages'], ['ubaa_ui'])

    def test_deleted_or_renamed_source_still_checks_old_owner(self):
        plan = self.plan('packages/ubaa_domain/lib/removed.dart', 'packages/ubaa_ui/lib/new.dart')
        self.assertIn('ubaa_domain', plan['packages'])
        self.assertIn('ubaa_flutter', plan['packages'])

    def test_manifest_or_tool_changes_fall_back_to_complete_checks(self):
        for path in ['packages/ubaa_ui/pubspec.yaml', 'AGENTS.md', 'justfile',
                     'scripts/check/changed_checks.py', '.github/workflows/ci.yml', 'unexpected/file']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertTrue(plan['rust'])
                self.assertEqual(plan['packages'], list(gates.PACKAGES))

    def test_rust_bridge_adds_codegen_and_all_flutter(self):
        plan = self.plan('crates/ubaa-flutter-bridge/src/api.rs')
        self.assertTrue(plan['rust'])
        self.assertEqual(plan['packages'], list(gates.PACKAGES))
        self.assertIn(['just', 'flutter-codegen-check'], plan['extra'])

    def test_core_requires_cross_language_checks(self):
        plan = self.plan('crates/ubaa-core/src/session/mod.rs')
        self.assertTrue(plan['rust'])
        self.assertEqual(plan['packages'], list(gates.PACKAGES))
        self.assertIn(['just', 'flutter-codegen-check'], plan['extra'])

    def test_ohos_changes_require_explicit_native_followup(self):
        plan = self.plan('packages/connectivity_plus_ohos/lib/channel.dart')
        self.assertTrue(plan['rust'])
        self.assertTrue(any('ohos-check' in note for note in plan['notes']))

    def test_unknown_local_dependency_syntax_falls_back(self):
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            for path in gates.PACKAGES.values():
                target = repo / path
                target.mkdir(parents=True)
                shutil.copyfile(ROOT / path / 'pubspec.yaml', target / 'pubspec.yaml')
            manifest = repo / 'packages/ubaa_ui/pubspec.yaml'
            manifest.write_text(manifest.read_text() + '\n  new_package: {path: ../new_package}\n')
            plan = gates.select_checks(repo, ['packages/ubaa_ui/lib/widget.dart'])
            self.assertTrue(plan['rust'])
            self.assertEqual(plan['packages'], list(gates.PACKAGES))

    def test_git_collects_committed_staged_unstaged_untracked_and_deleted(self):
        with tempfile.TemporaryDirectory() as folder:
            repo = Path(folder)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()
            git('init', '-q')
            git('config', 'user.email', 'test@example.invalid')
            git('config', 'user.name', '测试')
            (repo / 'old.dart').write_text('old')
            git('add', '.')
            git('commit', '-qm', '初始')
            base = git('rev-parse', 'HEAD')
            git('mv', 'old.dart', 'new name.dart')
            git('commit', '-qm', '移动')
            (repo / 'staged.dart').write_text('staged')
            git('add', 'staged.dart')
            (repo / 'new name.dart').write_text('changed')
            (repo / '中文\n未跟踪.dart').write_text('new')
            self.assertEqual(set(gates.changed_paths(repo, base)),
                             {'old.dart', 'new name.dart', 'staged.dart', '中文\n未跟踪.dart'})
            self.assertEqual(gates.changed_paths(repo, 'base=' + base), gates.changed_paths(repo, base))
            # 暂存改动被工作区反向覆盖时，净差异为零仍必须检查暂存内容。
            git('add', 'new name.dart')
            (repo / 'new name.dart').write_text('old')
            self.assertIn('new name.dart', gates.changed_paths(repo))
            with self.assertRaises(subprocess.CalledProcessError):
                gates.changed_paths(repo, 'missing-ref')


if __name__ == '__main__':
    unittest.main()
