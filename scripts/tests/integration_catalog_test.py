"""集成清单必须完整，批量回归不能意外选择真实账号入口。"""

from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "check" / "integration_catalog.py"
spec = importlib.util.spec_from_file_location("catalog", SCRIPT)
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class CatalogTest(unittest.TestCase):
    def test_执行预览也要求显式SDK路径(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(catalog, "ROOT", Path(directory)), patch.dict(catalog.os.environ, {}, clear=True), patch.object(
            catalog.sys, "argv", [str(SCRIPT), "run", "--dry-run"]
        ), patch.object(catalog, "validate", return_value=[self.entry()]):
            self.assertRaisesRegex(ValueError, "UBAA_FLUTTER_HOME", catalog.main)

    def entry(self, **overrides):
        entry = dict(path="sample_test.dart", kind="synthetic", domain="home",
                     platforms=["macos"], ci=True, inspection=False)
        entry.update(overrides)
        return entry

    def test_未登记入口必须失败(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("void main() {}")
            self.assertRaisesRegex(ValueError, "未登记", catalog.validate, [], root)

    def test_人工驱动入口也必须登记(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "inspection_driver.dart").write_text("void main() {}")
            self.assertRaisesRegex(ValueError, "未登记", catalog.validate, [], root)

    def test_不能通过辅助文件藏入真实账号入口(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("import 'support.dart';")
            (root / "support.dart").write_text("UBAA_LIVE_READONLY")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate,
                                   [self.entry()], root)

    def test_不能通过根外共享辅助隐藏账号入口(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            root = workspace / "integration_test"
            root.mkdir()
            (root / "sample_test.dart").write_text("import '../support.dart';")
            (workspace / "support.dart").write_text("const mode = 'UBAA_LIVE_READONLY';")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate,
                                   [self.entry()], root)

    def test_条件导入也必须检查真实标记(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text(
                "import 'stub.dart' if (dart.library.io) 'support.dart';")
            (root / "stub.dart").write_text("")
            (root / "support.dart").write_text("const mode = 'UBAA_LIVE_READONLY';")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate,
                                   [self.entry()], root)

    def test_本地辅助缺失不能宣称分类完整(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("import 'missing.dart';")
            self.assertRaisesRegex(ValueError, "不存在", catalog.validate,
                                   [self.entry()], root)

    def test_自有package辅助不能隐藏账号入口(self):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            root = workspace / "integration_test"
            root.mkdir()
            package = workspace / "packages/shared"
            (package / "lib").mkdir(parents=True)
            (package / "pubspec.yaml").write_text("name: shared\n")
            (package / "lib/support.dart").write_text("const mode = 'UBAA_LIVE_READONLY';")
            (root / "sample_test.dart").write_text("export 'package:shared/support.dart';")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate, [self.entry()], root)

    def test_URI编码不能选择不同于Dart的字面路径(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("import 'h%65lper.dart';")
            (root / "h%65lper.dart").write_text("const ordinary = true;")
            (root / "helper.dart").write_text("const mode = 'UBAA_LIVE_READONLY';")
            self.assertRaisesRegex(ValueError, "URI", catalog.validate, [self.entry()], root)

    def test_真实账号入口不能登记到CI(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("UBAA_LIVE_READONLY")
            entry = self.entry()
            entry["kind"] = "live"
            self.assertRaisesRegex(ValueError, "CI", catalog.validate, [entry], root)

    def test_真实标记不能伪装为合成测试(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("UBAA_LIVE_READONLY")
            self.assertRaisesRegex(ValueError, "真实", catalog.validate,
                                   [self.entry()], root)

    def test_重复入口必须失败(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("void main() {}")
            self.assertRaisesRegex(ValueError, "重复", catalog.validate,
                                   [self.entry(), self.entry()], root)

    def test_批量选择排除真实与人工入口(self):
        safe = self.entry()
        live = {**safe, "path": "live_test.dart", "kind": "live", "ci": False}
        manual = {**safe, "path": "manual_test.dart", "kind": "manual", "ci": False}
        self.assertEqual(catalog.select([safe, live, manual], "ci", "macos"), [safe])
        self.assertRaisesRegex(ValueError, "显式", catalog.select,
                               [live], "live_test.dart", "macos")

    def test_平台不匹配不能静默跳过(self):
        self.assertRaisesRegex(ValueError, "平台", catalog.select,
                               [self.entry()], "sample_test.dart", "linux")

    def test_入口环境变量缺失必须失败(self):
        entry = self.entry(environment=["DBUS_SESSION_BUS_ADDRESS"])
        with self.assertRaisesRegex(ValueError, "缺少必需环境变量"):
            catalog.environment_for_entry(entry, {})
        with self.assertRaisesRegex(ValueError, "缺少必需环境变量"):
            catalog.environment_for_entry(entry, {"DBUS_SESSION_BUS_ADDRESS": ""})

    def test_缺少后续入口配置时不启动任何Flutter命令(self):
        entries = [self.entry(), self.entry(path="second_test.dart", environment=["REQUIRED_CONFIG"])]
        with patch.dict(catalog.os.environ, {}, clear=True), \
                patch.object(catalog, "load_environment", return_value={"UBAA_FLUTTER_HOME": "/sdk"}), \
                patch.object(catalog, "validate", return_value=entries), \
                patch.object(catalog.sys, "argv", [str(SCRIPT), "run"]), \
                patch.object(catalog.subprocess, "run") as run, \
                redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ValueError, "缺少必需环境变量"):
                catalog.main()
        run.assert_not_called()

    def test_命令应用Dart_define和run执行方式(self):
        entry = self.entry(runner="run", defines=["FEATURE=true", "VALUE=a=b"])
        command = catalog.build_command(entry, Path("/sdk/bin/flutter"), "linux", "linux-device")
        self.assertEqual(command, [
            "/sdk/bin/flutter", "run", "integration_test/sample_test.dart",
            "-d", "linux-device", "--dart-define=FEATURE=true", "--dart-define=VALUE=a=b",
        ])

    def test_CI入口不能使用run(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("void main() {}")
            entry = self.entry(runner="run")
            with self.assertRaisesRegex(ValueError, "执行方式或 CI"):
                catalog.validate([entry], root)

    def test_命令预览显示清单中的Dart_define(self):
        output = io.StringIO()
        environment = {
            "UBAA_FLUTTER_HOME": "/sdk",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/tmp/bus",
        }
        entry = self.entry(
            platforms=["linux"], ci=False,
            environment=["DBUS_SESSION_BUS_ADDRESS"],
            defines=["UBAA_SECURE_STORAGE_AVAILABLE=true"],
        )
        with patch.dict(catalog.os.environ, {}, clear=True), \
                patch.object(catalog, "load_environment", return_value=environment), \
                patch.object(catalog, "validate", return_value=[entry]), \
                patch.object(catalog.sys, "argv", [
                    str(SCRIPT), "run", "--suite", "sample_test.dart",
                    "--platform", "linux", "--device", "linux-device", "--dry-run",
                ]), redirect_stdout(output):
            catalog.main()
        self.assertIn("--dart-define=UBAA_SECURE_STORAGE_AVAILABLE=true", output.getvalue())

    def test_入口环境变量传给Flutter(self):
        environment = {
            "UBAA_FLUTTER_HOME": "/sdk",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/tmp/bus",
        }
        entry = self.entry(
            platforms=["linux"], ci=False,
            environment=["DBUS_SESSION_BUS_ADDRESS"],
        )
        with patch.dict(catalog.os.environ, {}, clear=True), \
                patch.object(catalog, "load_environment", return_value=environment), \
                patch.object(catalog, "validate", return_value=[entry]), \
                patch.object(catalog.sys, "argv", [
                    str(SCRIPT), "run", "--suite", "sample_test.dart", "--platform", "linux",
                ]), patch.object(catalog.subprocess, "run") as run, \
                redirect_stdout(io.StringIO()):
            catalog.main()
        child_environment = run.call_args_list[-1].kwargs["env"]
        self.assertEqual(child_environment["DBUS_SESSION_BUS_ADDRESS"], "unix:path=/tmp/bus")

    def test_无效Dart_define必须失败(self):
        entry = self.entry(defines=["=missing-name"])
        with self.assertRaisesRegex(ValueError, "Dart define"):
            catalog.build_command(entry, Path("/sdk/bin/flutter"), "linux")


    def run_main(self, argv, entries, root, run=None):
        """在临时测试根目录执行 main，返回输出和 subprocess.run 的替身。"""
        output = io.StringIO()
        run = run or patch.object(catalog.subprocess, "run").start()
        self.addCleanup(patch.stopall)
        with patch.dict(catalog.os.environ, {}, clear=True), \
                patch.object(catalog, "load_environment", return_value={"UBAA_FLUTTER_HOME": "/sdk"}), \
                patch.object(catalog, "validate", return_value=entries), \
                patch.object(catalog, "TEST_ROOT", root), \
                patch.object(catalog.sys, "argv", [str(SCRIPT), "run", *argv]), \
                redirect_stdout(output):
            catalog.main()
        return output.getvalue(), run

    def write_entries(self, root, *entries):
        for entry in entries:
            path = root / entry["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("void main() {}\n")
        return list(entries)

    def test_默认集合只构建启动一次并合并define(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entries = self.write_entries(
                root, self.entry(path="a/first_test.dart", defines=["SHARED=1"]),
                self.entry(path="b/lock_test.dart", defines=["SHARED=1", "LOCK=on"]))
            seen = []
            def record(command, **kwargs):
                if command[0] != "bash":
                    seen.append((command, (root / ".ci_suite/suite_test.dart").read_text()))
            output, run = self.run_main([], entries, root, patch.object(
                catalog.subprocess, "run", side_effect=record).start())
            self.assertEqual(len(seen), 1, "多个入口只能启动一次 flutter test")
            command, source = seen[0]
            self.assertIn("integration_test/.ci_suite/suite_test.dart", command)
            self.assertEqual([c for c in command if c.startswith("--dart-define")],
                             ["--dart-define=SHARED=1", "--dart-define=LOCK=on"])
            self.assertIn("import '../a/first_test.dart' as entry0;", source)
            self.assertIn("group('b/lock_test.dart', entry1.main);", source)
            self.assertFalse((root / ".ci_suite").exists(), "运行后必须删除聚合入口")
            self.assertIn("聚合入口：a/first_test.dart、b/lock_test.dart", output)

    def test_运行失败也删除聚合入口(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entries = self.write_entries(root, self.entry(path="a_test.dart"), self.entry(path="b_test.dart"))
            def fail(command, **kwargs):
                if command[0] != "bash":
                    raise catalog.subprocess.CalledProcessError(1, command)
            with self.assertRaises(catalog.subprocess.CalledProcessError):
                self.run_main([], entries, root, patch.object(catalog.subprocess, "run", side_effect=fail).start())
            self.assertFalse((root / ".ci_suite").exists())

    def test_逐文件模式保留原有每入口一次运行(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entries = self.write_entries(root, self.entry(path="a_test.dart"), self.entry(path="b_test.dart"))
            output, run = self.run_main(["--suite", "ci-isolated"], entries, root)
            flutter = [call.args[0] for call in run.call_args_list if call.args[0][0] != "bash"]
            self.assertEqual([command[2] for command in flutter],
                             ["integration_test/a_test.dart", "integration_test/b_test.dart"])

    def test_聚合拒绝冲突define和异步入口(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first, second = self.write_entries(
                root, self.entry(path="a_test.dart", defines=["MODE=a"]),
                self.entry(path="b_test.dart", defines=["MODE=b"]))
            self.assertRaisesRegex(ValueError, "冲突", catalog.aggregate, [first, second], root)
            (root / "b_test.dart").write_text("Future<void> main() async {}\n")
            self.assertRaisesRegex(ValueError, "同步", catalog.aggregate,
                                   [first, self.entry(path="b_test.dart")], root)

    def test_残留聚合入口不计入登记(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sample_test.dart").write_text("void main() {}")
            (root / ".ci_suite").mkdir()
            (root / ".ci_suite/suite_test.dart").write_text("void main() {}")
            self.assertEqual(catalog.validate([self.entry()], root), [self.entry()])


if __name__ == "__main__":
    unittest.main()
