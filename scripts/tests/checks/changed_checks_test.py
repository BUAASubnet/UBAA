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
        self.assertIn(['just', 'contract-version-check'], gates.commands(plan))
        self.assertIn(['just', 'docs-link-check'], gates.commands(plan))

    def test_ui_implementation_includes_consumers(self):
        self.assertEqual(self.plan('packages/ubaa_ui/lib/src/app/home.dart')['packages'],
                         ['ubaa_app', 'ubaa_ui', 'ubaa_host', 'ubaa_flutter', 'ubaa_test_support'])

    def test_app_implementation_includes_ui_test_dependency(self):
        self.assertEqual(self.plan('packages/ubaa_app/lib/src/presentation/grades.dart')['packages'],
                         ['ubaa_app', 'ubaa_ui', 'ubaa_host', 'ubaa_flutter', 'ubaa_test_support'])

    def test_domain_reaches_all_consumers_but_not_unrelated_bindings(self):
        self.assertEqual(gates.dependents(ROOT, {'ubaa_domain'}),
                         {'ubaa_domain', 'ubaa_platform', 'ubaa_app', 'ubaa_ui', 'ubaa_host',
                          'ubaa_flutter', 'ubaa_test_support'})

    def test_tests_only_check_own_package(self):
        self.assertEqual(self.plan('packages/ubaa_ui/test/navigation/read_test.dart')['packages'], ['ubaa_ui'])

    def test_workspace测试辅助包进入清单和改动规划(self):
        self.assertEqual(gates.PACKAGES['ubaa_test_support'], 'packages/ubaa_test_support')
        package_list = subprocess.check_output(
            ['python3', str(ROOT / 'scripts/lib/packages.py')], text=True).splitlines()
        self.assertEqual(package_list[-1], 'packages/ubaa_test_support')
        self.assertEqual(
            self.plan('packages/ubaa_test_support/lib/recovery.dart')['packages'],
            ['ubaa_app', 'ubaa_ui', 'ubaa_host', 'ubaa_flutter', 'ubaa_test_support'],
        )

    def test_deleted_or_renamed_source_still_checks_old_owner(self):
        plan = self.plan('packages/ubaa_domain/lib/removed.dart', 'packages/ubaa_ui/lib/new.dart')
        self.assertIn('ubaa_domain', plan['packages'])
        self.assertIn('ubaa_flutter', plan['packages'])

    def test_root_documents_and_scripts_have_lightweight_tiers(self):
        for path in ['AGENTS.md', 'SECURITY.md', 'UBAA2.md', 'crates/ubaa_core/README.md',
                     'apps/ubaa_cli/README.md', 'packages/package_info_plus_ohos/README.md']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertFalse(plan['rust'])
                self.assertEqual(plan['packages'], [])
                self.assertIn(['just', 'cargo-lock-check'], gates.commands(plan))
        for path in ['justfile', 'scripts/check/changed_checks.py', '.github/workflows/ci.yml']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertFalse(plan['rust'])
                self.assertEqual(plan['packages'], [])
                self.assertEqual(plan['extra'], [])
                self.assertIn(['just', 'script-check'], gates.commands(plan))

    def test_unknown_paths_and_dependency_manifests_remain_conservative(self):
        for path in ['packages/ubaa_ui/pubspec.yaml', 'unexpected/file', 'crates/unknown/src/mod.rs',
                     'scripts/new_native.rs', 'packages/unknown/README.md',
                     'Cargo.toml', 'pubspec.lock', 'docs/contracts/cli.schema.json']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertTrue(plan['rust'])
                self.assertEqual(plan['packages'], list(gates.PACKAGES))
                self.assertIn(['just', 'check-strict'], gates.commands(plan))
                self.assertIn(['just', 'integration-test'], gates.commands(plan))

    def test_dependency_audit_entry_keeps_network_run_explicit(self):
        plan = self.plan('scripts/release/dependency-audit.sh')
        self.assertFalse(plan['rust'])
        self.assertEqual(plan['packages'], [])
        self.assertTrue(any('显式联网' in note for note in plan['notes']))
        self.assertNotIn(['just', 'dependency-audit'], gates.commands(plan))

    def test_rust_bridge_adds_codegen_and_all_flutter(self):
        plan = self.plan('crates/ubaa_flutter_bridge/src/api.rs')
        self.assertTrue(plan['rust'])
        self.assertEqual(plan['packages'], list(gates.PACKAGES))
        self.assertIn(gates.CODEGEN, plan['extra'])

    def test_core_storage_keeps_full_checks_without_redundant_codegen(self):
        plan = self.plan('crates/ubaa_core/src/session/mod.rs')
        self.assertTrue(plan['rust'])
        self.assertEqual(plan['packages'], list(gates.PACKAGES))
        self.assertNotIn(gates.CODEGEN, plan['extra'])

    def test_regular_rust_does_not_regenerate_bindings_or_run_flutter(self):
        plan = self.plan('apps/ubaa_cli/src/render/tables.rs')
        self.assertTrue(plan['rust'])
        self.assertEqual(plan['packages'], [])
        self.assertEqual(plan['extra'], [])
        self.assertIn(['just', 'check'], gates.commands(plan))
        self.assertNotIn(['just', 'integration-test'], gates.commands(plan))

    def test_security_protocol_concurrency_storage_and_ffi_require_full(self):
        for path in ['crates/ubaa_core/src/session/storage.rs',
                     'crates/ubaa_core/src/upstream/mod.rs',
                     'packages/ubaa_app/lib/src/controller/reads/lanes.dart',
                     'packages/ubaa_app/lib/src/controller/session/authentication.dart',
                     'packages/ubaa_app/lib/src/bridge/auth/session.dart',
                     'packages/ubaa_app/lib/src/bridge/cache/account.dart',
                     'packages/ubaa_app/lib/src/write/coordinator.dart',
                     'packages/ubaa_ui/lib/src/write_callbacks.dart',
                     'packages/ubaa_ui/lib/src/app/shell_write.dart',
                     'packages/ubaa_domain/lib/src/feature/cached_feature.dart',
                     'apps/ubaa_cli/src/io/input.rs',
                     'scripts/lib/environment.py',
                     'scripts/release/macos-entitlements.sh',
                     'apps/ubaa_flutter/macos/Runner/Release.entitlements',
                     'packages/ubaa_platform/lib/src/infrastructure/preferences.dart',
                     'packages/ubaa_bindings/lib/src/backend.dart',
                     'packages/ubaa_host/lib/src/lifecycle.dart']:
            with self.subTest(path=path):
                commands = gates.commands(self.plan(path))
                self.assertIn(['just', 'check-strict'], commands)
                self.assertIn(['just', 'integration-test'], commands)

    def test_codegen_is_selected_for_bridge_inputs_and_locks(self):
        for path in ['crates/ubaa_flutter_bridge/src/api/read/methods.rs',
                     'packages/ubaa_bindings/flutter_rust_bridge.yaml', 'Cargo.lock', 'pubspec.lock']:
            with self.subTest(path=path):
                self.assertEqual(gates.commands(self.plan(path)).count(gates.CODEGEN), 1)

    def test_bridge_tests_and_platform_glue_do_not_regenerate_api(self):
        for path in ['crates/ubaa_flutter_bridge/src/api/read/tests.rs',
                     'crates/ubaa_flutter_bridge/src/api/write/tests/lifecycle.rs',
                     'crates/ubaa_flutter_bridge/src/android_tls.rs',
                     'packages/ubaa_bindings/test/backend_test.dart']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertTrue(plan['full'])
                self.assertNotIn(gates.CODEGEN, plan['extra'])

    def test_push_expands_flutter_and_defers_native_until_needed(self):
        plan = gates.select_checks(ROOT, ['packages/ubaa_ui/test/navigation/read_test.dart'], mode='push')
        self.assertEqual(plan['packages'], list(gates.PACKAGES))
        self.assertNotIn(['just', 'integration-test'], gates.commands(plan))
        self.assertEqual(plan['extra'], [])
        for path in ['apps/ubaa_flutter/macos/Runner/AppDelegate.swift',
                     'apps/ubaa_flutter/integration_test/platform/network_test.dart']:
            with self.subTest(path=path):
                commit = self.plan(path)
                self.assertNotIn(['just', 'integration-test'], gates.commands(commit))
                push = gates.select_checks(ROOT, [path], mode='push')
                self.assertIn(['just', 'integration-test'], gates.commands(push))

    def test_full_mode_executes_each_heavy_gate_once(self):
        plan = gates.select_checks(ROOT, ['AGENTS.md'], mode='full')
        commands = gates.commands(plan)
        for recipe in ['check-strict', 'integration-test']:
            self.assertEqual(commands.count(['just', recipe]), 1)
        self.assertEqual(commands.count(gates.CODEGEN), 1)
        self.assertNotIn(['just', 'check'], commands)
        self.assertNotIn(['just', 'script-check'], commands)
        self.assertNotIn(['just', 'check-changed'], commands)
        self.assertNotIn(['just', 'docs-link-check'], commands)

    def test_mixed_paths_merge_without_repeating_common_checks(self):
        plan = self.plan('AGENTS.md', 'scripts/check/changed_checks.py',
                         'apps/ubaa_cli/src/render/tables.rs')
        commands = gates.commands(plan)
        self.assertEqual(commands.count(['just', 'check']), 1)
        self.assertNotIn(['just', 'script-check'], commands)
        self.assertNotIn(['just', 'cargo-lock-check'], commands)

    def test_ohos_changes_require_explicit_native_followup(self):
        plan = self.plan('packages/package_info_plus_ohos/lib/channel.dart')
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


LOCK = """version = 4

[[package]]
name = "ubaa_flutter_bridge"
version = "0.1.0"
dependencies = ["serde", "ubaa-core"]

[[package]]
name = "ubaa-core"
version = "0.1.0"
dependencies = ["serde"]

[[package]]
name = "ubaa-cli"
version = "0.1.0"
dependencies = ["clap", "ubaa-core"]

[[package]]
name = "serde"
version = "SERDE"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "aa"

[[package]]
name = "clap"
version = "CLAP"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "bb"
"""
MANIFEST = """[workspace]
members = ["apps/ubaa_cli", "crates/ubaa_core", "crates/ubaa_flutter_bridge"]

[workspace.dependencies]
clap = "CLAP"
serde = "SERDE"
renamed = { package = "serde", version = "SERDE" }

[profile.dev]
debug = "DEBUG"
"""


class RustManifestTierTest(unittest.TestCase):
    """只有能证明不触及 Bridge 依赖闭包的 Rust 清单改动才降为 Rust 严格检查。"""

    def plan(self, path, old, new):
        def fill(text, values):
            for key, value in values.items():
                text = text.replace(key, value)
            return text
        base = {'SERDE': '1.0.0', 'CLAP': '4.0.0', 'DEBUG': 'line-tables-only'}
        # 先套用本用例的替换，再补默认值。
        def render(text, values):
            return fill(fill(text, values), base)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Cargo.lock').write_text(render(LOCK, new))
            (root / 'Cargo.toml').write_text(render(MANIFEST, new))
            previous = {'Cargo.lock': render(LOCK, old), 'Cargo.toml': render(MANIFEST, old)}
            return gates.select_checks(root, [path], previous=previous.get)

    def assert_rust_only(self, plan):
        self.assertFalse(plan['full'])
        self.assertTrue(plan['rust'] and plan['strict'])
        self.assertFalse(plan['native'])
        self.assertEqual(plan['packages'], [])
        self.assertEqual(plan['extra'], [])
        self.assertIn(['just', 'check-strict'], gates.commands(plan))

    def assert_full(self, plan):
        self.assertTrue(plan['full'])
        self.assertIn(['just', 'integration-test'], gates.commands(plan))
        self.assertIn(gates.CODEGEN, plan['extra'])

    def test_CLI清单只做Rust严格检查(self):
        self.assert_rust_only(gates.select_checks(ROOT, ['apps/ubaa_cli/Cargo.toml']))

    def test_只升级CLI依赖的锁文件不运行原生检查(self):
        self.assert_rust_only(self.plan('Cargo.lock', {}, {'CLAP': '4.1.0'}))

    def test_升级Bridge闭包内依赖仍完整验收(self):
        self.assert_full(self.plan('Cargo.lock', {}, {'SERDE': '1.0.1'}))

    def test_根清单只改CLI工作区依赖时只做Rust严格检查(self):
        self.assert_rust_only(self.plan('Cargo.toml', {'CLAP': '4.0.0'}, {'CLAP': '4.1.0'}))

    def test_根清单改闭包内依赖或改名依赖仍完整验收(self):
        self.assert_full(self.plan('Cargo.toml', {}, {'"SERDE"': '"1.0.1"'}))
        self.assert_full(self.plan('Cargo.toml', {}, {'version = "SERDE"': 'version = "1.0.1"'}))

    def test_根清单其他字段影响所有crate时完整验收(self):
        self.assert_full(self.plan('Cargo.toml', {}, {'DEBUG': 'full'}))

    def test_缺少旧版本或无法解析时完整验收(self):
        self.assert_full(gates.select_checks(ROOT, ['Cargo.lock'], previous=lambda path: None))
        self.assert_full(self.plan('Cargo.lock', {}, {'"serde", "ubaa-core"]': '"serde", "serde", "ubaa-core", "missing"]'}))
        self.assert_full(self.plan('Cargo.lock', {}, {'version = 4': 'version = ['}))


if __name__ == '__main__':
    unittest.main()
