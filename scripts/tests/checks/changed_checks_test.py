#!/usr/bin/env python3
"""按改动选择门禁的行为测试，覆盖漏选和 Git 路径边界。"""
from contextlib import redirect_stdout
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('changed_checks', ROOT / 'scripts/check/changed_checks.py')
gates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gates)


class ChangedChecksTest(unittest.TestCase):
    def plan(self, *paths):
        return gates.select_checks(ROOT, paths)

    def test_core_parsers_and_dtos_use_l1(self):
        for path in ['crates/ubaa_core/src/features/cgyy/parser.rs',
                     'crates/ubaa_core/src/domain/agenda/projection.rs']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertFalse(plan['full'])
                self.assertFalse(plan['risk'])
                self.assertEqual(plan['packages'], [])
                self.assertTrue(any(command[:2] == ['just', 'check'] and 'ubaa-core' in command
                                    for command in gates.commands(plan)))
                self.assertEqual(plan['native'], [])

    def test_auth_storage_and_bridge_api_use_l1_plus(self):
        for path in ['crates/ubaa_core/src/auth/automatic.rs',
                     'crates/ubaa_core/src/session/file_store.rs',
                     'crates/ubaa_flutter_bridge/src/api/read/mod.rs']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertFalse(plan['full'])
                self.assertTrue(plan['risk'])
                self.assertEqual(plan['packages'], [])
                self.assertTrue(any(command[:2] == ['just', 'check-risk'] for command in gates.commands(plan)))

    def test_plain_docs_and_scripts_select_only_relevant_checks(self):
        common = [['just', 'check-sensitive'], ['git', 'diff', '--check']]
        for path, command in [('docs/project/status.md', ['just', 'docs-link-check']),
                              ('scripts/check/docs_links.py', ['just', 'script-check', 'scoped'])]:
            with self.subTest(path=path):
                self.assertEqual(gates.commands(self.plan(path)), common + [command, ['just', 'cargo-lock-check']])

    def test_cargo_lock_gate_is_selected_for_scripts_but_not_rust(self):
        for path in ('scripts/check/example.py', 'justfile', '.github/workflows/ci.yml', 'README.md'):
            with self.subTest(path=path):
                self.assertIn(['just', 'cargo-lock-check'], gates.commands(self.plan(path)))
        rust_commands = gates.commands(self.plan('crates/ubaa_core/src/domain/projection.rs'))
        self.assertNotIn(['just', 'cargo-lock-check'], rust_commands)

    def test_l1_dart_runs_module_graph_gate(self):
        commands = gates.commands(self.plan('packages/ubaa_ui/lib/src/example.dart'))
        self.assertIn(['just', 'module-check'], commands)

    def test_maintenance_gate_follows_artifact_and_permission_inputs(self):
        command = ['bash', './scripts/tests/maintenance-gates.sh']
        for path in ('scripts/release/verify-flutter-artifact.sh',
                     'apps/ubaa_flutter/macos/Runner/Release.entitlements',
                     'scripts/release/platforms/apple_signing.py'):
            with self.subTest(path=path):
                self.assertIn(command, gates.commands(self.plan(path)))
        self.assertNotIn(command, gates.commands(self.plan('scripts/check/example.py')))

    def test_unknown_path_keeps_full_mode(self):
        self.assertTrue(self.plan('unexpected/file')['full'])

    def test_full_mode_command_snapshot(self):
        snapshot = [
            ['just', 'check-sensitive'], ['git', 'diff', '--check'],
            ['just', 'app-service-content-check'], ['just', 'app-service-check'], ['just', 'check-strict'],
            ['bash', 'scripts/check/flutter-workspace.sh', 'check', 'ubaa_domain', 'ubaa_platform', 'ubaa_app',
             'ubaa_ui', 'ubaa_bindings', 'ubaa_host', 'ubaa_flutter', 'ubaa_test_support'],
            ['just', 'integration-test'],
            ['env', 'CARGO_INCREMENTAL=0', 'CARGO_BUILD_JOBS=1', 'just', 'flutter-codegen-check'],
        ]
        for paths, extras in [((), []), (('docs/site/index.md',), [['npm', 'run', 'docs:build']])]:
            with self.subTest(paths=paths):
                self.assertEqual(gates.commands(gates.select_checks(ROOT, paths, mode='full')), snapshot + extras)

    def test_docs_do_not_trigger_language_suites(self):
        plan = self.plan('docs/project/status.md', 'README.md', 'docs/project/goal.md', 'scripts/README.md', 'packages/ubaa_ui/README.md')
        self.assertFalse(plan['rust'])
        self.assertEqual(plan['packages'], [])
        self.assertEqual(plan['extra'], [])
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
        for path in ['AGENTS.md', 'SECURITY.md', 'docs/project/roadmap.md', 'crates/ubaa_core/README.md',
                     'crates/ubaa_command/README.md', 'packages/package_info_plus_ohos/README.md']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertFalse(plan['rust'])
                self.assertEqual(plan['packages'], [])
                self.assertIn(['just', 'docs-link-check'], gates.commands(plan))
        for path in ['justfile', 'scripts/check/changed_checks.py', '.github/workflows/ci.yml']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertFalse(plan['rust'])
                self.assertEqual(plan['packages'], [])
                self.assertEqual(plan['extra'], [])
                self.assertIn(['just', 'script-check', 'scoped'], gates.commands(plan))

    def test_unknown_paths_and_dependency_manifests_remain_conservative(self):
        for path in ['unexpected/file', 'crates/unknown/src/mod.rs', 'scripts/new_native.rs',
                     'packages/unknown/README.md', 'docs/contracts/cli.schema.json']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertTrue(plan['rust'])
                self.assertEqual(plan['packages'], list(gates.PACKAGES))
                self.assertIn(['just', 'check-strict'], gates.commands(plan))
                self.assertIn(['just', 'integration-test'], gates.commands(plan))
        for path in ['packages/ubaa_ui/pubspec.yaml', 'Cargo.toml', 'pubspec.lock']:
            with self.subTest(path=path):
                self.assertFalse(self.plan(path)['full'])

    def test_dependency_audit_entry_keeps_network_run_explicit(self):
        plan = self.plan('scripts/release/dependency-audit.sh')
        self.assertFalse(plan['rust'])
        self.assertEqual(plan['packages'], [])
        self.assertTrue(any('显式联网' in note for note in plan['notes']))
        self.assertNotIn(['just', 'dependency-audit'], gates.commands(plan))

    def test_rust_bridge_adds_codegen_and_targeted_native_tests(self):
        plan = self.plan('crates/ubaa_flutter_bridge/src/api.rs')
        self.assertTrue(plan['rust'])
        self.assertEqual(plan['packages'], [])
        self.assertTrue(plan['risk'])
        self.assertIn(gates.CODEGEN, plan['extra'])
        self.assertEqual([command[2] for command in plan['native']],
                         ['suite=synthetic/app/smoke_test.dart', 'suite=synthetic/cache/bridge_test.dart'])

    def test_generated_bindings_keep_codegen_without_high_risk_native_tests(self):
        plan = self.plan('packages/ubaa_bindings/lib/src/rust/frb_generated.dart')
        self.assertFalse(plan['risk'])
        self.assertIn(gates.CODEGEN, plan['extra'])
        self.assertEqual(plan['native'], [])

    def test_core_storage_keeps_full_checks_without_redundant_codegen(self):
        plan = self.plan('crates/ubaa_core/src/session/mod.rs')
        self.assertTrue(plan['rust'])
        self.assertEqual(plan['packages'], [])
        self.assertTrue(plan['risk'])
        self.assertTrue(any(command[:2] == ['just', 'check-risk'] for command in gates.commands(plan)))
        self.assertNotIn(gates.CODEGEN, plan['extra'])

    def test_regular_rust_does_not_regenerate_bindings_or_run_flutter(self):
        plan = self.plan('crates/ubaa_command/src/render/tables.rs')
        self.assertTrue(plan['rust'])
        self.assertEqual(plan['packages'], [])
        self.assertEqual(plan['extra'], [])
        self.assertTrue(any(command[:2] == ['just', 'check'] and 'ubaa-command' in command
                            for command in gates.commands(plan)))
        self.assertNotIn(['just', 'integration-test'], gates.commands(plan))

    def test_high_risk_paths_use_l1_plus_and_approved_l1_paths_stay_light(self):
        high_risk = ['crates/ubaa_core/src/session/storage.rs', 'crates/ubaa_core/src/upstream/mod.rs',
                     'packages/ubaa_app/lib/src/controller/session/authentication.dart',
                     'packages/ubaa_app/lib/src/bridge/auth/session.dart',
                     'packages/ubaa_app/lib/src/bridge/cache/account.dart',
                     'packages/ubaa_app/lib/src/write/coordinator.dart',
                     'packages/ubaa_ui/lib/src/app/shell_write.dart',
                     'packages/ubaa_ui/lib/src/write_callbacks.dart',
                     'crates/ubaa_command/src/io/input.rs', 'scripts/lib/environment.py',
                     'scripts/release/macos-entitlements.sh',
                     'apps/ubaa_flutter/macos/Runner/Release.entitlements',
                     'packages/ubaa_platform/lib/src/secure_material.dart',
                     'packages/ubaa_bindings/lib/ubaa_bindings.dart']
        for path in high_risk:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertFalse(plan['full'])
                self.assertTrue(plan['risk'])
                self.assertTrue(any(command[:2] == ['just', 'check-risk']
                                    for command in gates.commands(plan)))
        for path in ['packages/ubaa_app/lib/src/controller/reads/lanes.dart',
                     'packages/ubaa_domain/lib/src/feature/cached_feature.dart',
                     'packages/ubaa_platform/lib/src/infrastructure/preferences.dart',
                     'packages/ubaa_host/lib/src/lifecycle.dart']:
            with self.subTest(path=path):
                plan = self.plan(path)
                self.assertFalse(plan['full'])
                self.assertFalse(plan['risk'])

    def test_facade_boundary_paths_use_l1_plus_without_promoting_read_models(self):
        for path in ['client/app_service.rs', 'client/observation.rs', 'offline/grade_baseline.rs',
                     'offline/refresh.rs', 'read/write_readback.rs']:
            with self.subTest(path=path):
                self.assertTrue(self.plan('crates/ubaa_core/src/facade/' + path)['risk'])
        for path in ['types.rs', 'agenda/export.rs', 'read/academic.rs', 'bhpan/pagination.rs']:
            with self.subTest(path=path):
                self.assertFalse(self.plan('crates/ubaa_core/src/facade/' + path)['risk'])

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
                self.assertFalse(plan['full'])
                if path.endswith(('tests.rs', 'android_tls.rs')):
                    self.assertTrue(plan['risk'])
                self.assertNotIn(gates.CODEGEN, plan['extra'])

    def test_push_mode_is_removed_and_native_tests_are_selected_by_platform(self):
        with self.assertRaises(ValueError):
            gates.select_checks(ROOT, ['packages/ubaa_ui/test/navigation/read_test.dart'], mode='push')
        host = {'darwin': 'macos', 'win32': 'windows'}.get(sys.platform, 'linux')
        for path, platform in [('apps/ubaa_flutter/macos/Runner/AppDelegate.swift', 'macos'),
                               ('apps/ubaa_flutter/integration_test/platform/network_test.dart', host)]:
            with self.subTest(path=path):
                self.assertIn(['just', 'integration-test', 'suite=ci', f'platform={platform}'],
                              gates.commands(self.plan(path)))

    def test_full_mode_executes_each_heavy_gate_once(self):
        plan = gates.select_checks(ROOT, ['AGENTS.md'], mode='full')
        commands = gates.commands(plan)
        for recipe in ['check-strict', 'integration-test', 'app-service-check',
                       'app-service-content-check']:
            self.assertEqual(commands.count(['just', recipe]), 1)
        self.assertEqual(commands.count(gates.CODEGEN), 1)
        self.assertNotIn(['just', 'check'], commands)
        self.assertNotIn(['just', 'script-check'], commands)
        self.assertNotIn(['just', 'check-changed'], commands)
        self.assertNotIn(['just', 'docs-link-check'], commands)

    def test_policy_only_changes_select_policy_check(self):
        plan = self.plan('docs/site/tech/privacy-policy.md')
        self.assertIn(['just', 'privacy-policy-check'], gates.commands(plan))
        self.assertIn(['npm', 'run', 'docs:build'], gates.commands(plan))
        self.assertNotIn(['just', 'app-service-check'], gates.commands(plan))

    def test_app_service_content_and_release_changes_select_only_local_checks(self):
        for path in [
                'docs/site/announcements/2026-11-10-001.md',
                'docs/site/announcements/history.md',
                'services/app_service/config/channels.json',
                'services/app_service/src/version.mjs',
                'scripts/check/app_service/content.mjs',
                'scripts/tests/app_service/content_test.mjs',
                'scripts/tests/app_service/announcements_site_test.mjs',
                'scripts/tests/app_service/release_test.mjs',
                'scripts/release/app_service/release.mjs',
                'package-lock.json']:
            with self.subTest(path=path):
                commands = gates.commands(self.plan(path))
                self.assertIn(['just', 'app-service-content-check'], commands)
                self.assertNotIn(['just', 'app-service-publish'], commands)
                self.assertNotIn(['just', 'app-service-deploy'], commands)
        for path in ['scripts/check/app_service/content.mjs', 'services/app_service/src/version.mjs']:
            self.assertIn(['npm', 'run', 'docs:build'], gates.commands(self.plan(path)))
        self.assertNotIn(['just', 'app-service-content-check'],
                         gates.commands(self.plan('services/app_service/src/aggregate.ts')))

    def test_app_service_only_changes_propagate_worker_check_failure(self):
        for path in ['services/app_service/src/index.ts', 'fixtures/app_service/bootstrap.json']:
            with self.subTest(path=path), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                subprocess.run(['git', 'init', '-q', str(root)], check=True)
                subprocess.run(['git', '-C', str(root), '-c', 'user.name=测试',
                                '-c', 'user.email=test@example.invalid', 'commit', '-qm', '基线',
                                '--allow-empty'], check=True)
                target = root / path
                target.parent.mkdir(parents=True)
                target.write_text('合成改动\n')
                bin_dir = root / '.git' / 'bin'
                bin_dir.mkdir()
                just = bin_dir / 'just'
                just.write_text('#!/bin/sh\nif [ "$1" = app-service-check ]; then exit 23; fi\n')
                just.chmod(0o700)
                with patch.object(gates, 'ROOT', root), patch.object(gates.sys, 'argv', ['check', '--run']), \
                        patch.dict(os.environ, {'PATH': f'{bin_dir}{os.pathsep}{os.environ["PATH"]}'}), \
                        redirect_stdout(io.StringIO()):
                    with self.assertRaises(subprocess.CalledProcessError) as failure:
                        gates.main()
                self.assertEqual(failure.exception.cmd, ['just', 'app-service-check'])
                self.assertEqual(failure.exception.returncode, 23)

    def test_mixed_paths_merge_without_repeating_common_checks(self):
        plan = self.plan('AGENTS.md', 'scripts/check/changed_checks.py',
                         'crates/ubaa_command/src/render/tables.rs')
        commands = gates.commands(plan)
        self.assertEqual(sum(command[:2] == ['just', 'check'] for command in commands), 1)
        self.assertIn(['just', 'script-check', 'scoped'], commands)
        self.assertEqual(commands.count(['just', 'cargo-lock-check']), 1)

    def test_ohos_changes_require_explicit_native_followup(self):
        plan = self.plan('packages/package_info_plus_ohos/lib/channel.dart')
        self.assertFalse(plan['rust'])
        self.assertFalse(plan['full'])
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


class RustManifestTierTest(unittest.TestCase):
    def test_manifest_changes_use_default_feature_l1(self):
        for path in ['Cargo.toml', 'tools/core_live/Cargo.toml', 'crates/ubaa_command/Cargo.toml']:
            with self.subTest(path=path):
                plan = gates.select_checks(ROOT, [path])
                self.assertFalse(plan['full'])
                self.assertFalse(plan['risk'])
                self.assertTrue(plan['rust'])
                self.assertTrue(any(command[:2] == ['just', 'check']
                                    for command in gates.commands(plan)))

    def test_bridge_codegen_is_skipped_for_unchanged_dependency_closure(self):
        plan = gates.select_checks(ROOT, ['Cargo.lock'], previous=gates.previous_reader(ROOT))
        self.assertTrue(plan['risk'])
        self.assertNotIn(gates.CODEGEN, gates.commands(plan))

    def test_manifest_parse_failure_keeps_full_fallback(self):
        plan = gates.select_checks(ROOT, ['Cargo.lock'], previous=lambda path: 'invalid lock data')
        self.assertTrue(plan['full'])
        self.assertIn(['just', 'check-strict'], gates.commands(plan))

    def test_lock_changes_are_l1_plus_and_keep_codegen(self):
        for path in ['Cargo.lock', 'pubspec.lock']:
            with self.subTest(path=path):
                plan = gates.select_checks(ROOT, [path])
                self.assertFalse(plan['full'])
                self.assertTrue(plan['risk'])
                self.assertEqual(gates.commands(plan).count(gates.CODEGEN), 1)

    def test_rust_metadata_failure_keeps_full_fallback(self):
        with patch.object(gates.rust_workspace, 'members',
                          side_effect=subprocess.CalledProcessError(1, 'cargo')):
            plan = gates.select_checks(ROOT, ['crates/ubaa_core/src/domain/agenda/projection.rs'])
        self.assertTrue(plan['full'])
        self.assertIn(['just', 'check-strict'], gates.commands(plan))


if __name__ == '__main__':
    unittest.main()
