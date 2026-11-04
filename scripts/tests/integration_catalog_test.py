"""集成清单必须完整，批量回归不能意外选择真实账号入口。"""

from contextlib import redirect_stdout
import importlib.util
import io
import json
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "check" / "integration_catalog.py"
spec = importlib.util.spec_from_file_location("catalog", SCRIPT)
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


ANDROID_SCRIPT = Path(__file__).parent / "platform/android_materials.py"
android_spec = importlib.util.spec_from_file_location("android_material_runner", ANDROID_SCRIPT)
android_runner = importlib.util.module_from_spec(android_spec)
android_spec.loader.exec_module(android_runner)


class CatalogTest(unittest.TestCase):
    def test_实际集成入口共用Bash及平台SDK执行文件(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entries = self.write_entries(root, self.entry())
            command = ['测试Bash', 'D:/项目 空格/check.sh', 'official']
            flutter = Path('/SDK 空格/bin/flutter.bat')
            with patch.object(catalog, 'bash_command', return_value=command) as bash, \
                    patch.object(catalog, 'sdk_executable', return_value=flutter) as sdk:
                _, run = self.run_main([], entries, root)
            sdk.assert_called_once_with('/sdk', 'flutter')
            self.assertEqual(run.call_args_list[0].args[0], command)
            self.assertEqual(run.call_args_list[1].args[0][0], str(flutter))
            self.assertEqual(bash.call_args.args, (catalog.ROOT / 'scripts/check/flutter-toolchains.sh', 'official'))

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

    def test_Android材料入口构建独立Debug身份(self):
        entry = self.entry(path="platform/credentials/material_test.dart")
        command = catalog.build_command(entry, Path("/sdk/bin/flutter"), "android", "fixture")
        self.assertTrue(command[1].endswith("scripts/tests/platform/android_materials.py"))
        self.assertEqual(command[-2:], ["--device", "fixture"])
        ordinary = catalog.build_command(entry, Path("/sdk/bin/flutter"), "macos")
        self.assertNotIn("--dart-define=UBAA_SYNTHETIC_ANDROID_MATERIALS=true", ordinary)

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


class MaterialDeviceRoutingTest(unittest.TestCase):
    """替换设备发现和子进程，真实 catalog 决策不得派发危险安装。"""

    def device(self, identity="emulator-5554", platform="android-arm64", **overrides):
        return dict(id=identity, name="合成设备", targetPlatform=platform,
                    isSupported=True, **overrides)

    def invoke(self, devices, platform=None, device="emulator-5554", reject=False,
               entry="platform/credentials/material_test.dart", dry_run=False):
        commands = []
        argv = [str(SCRIPT), "run", "--suite", entry]
        if platform is not None:
            argv += ["--platform", platform]
        if device is not None:
            argv += ["--device", device]
        if dry_run:
            argv += ["--dry-run"]

        def record(command, **kwargs):
            commands.append(command)
            if isinstance(devices, Exception):
                raise devices
            output = devices if isinstance(devices, str) else json.dumps(devices)
            return subprocess.CompletedProcess(command, 0, output, "")

        environment = {"UBAA_FLUTTER_HOME": "/sdk", "DBUS_SESSION_BUS_ADDRESS": "fixture-bus",
                       "UBAA_SYNTHETIC_SECRET_SERVICE_ROOT": "/fixture",
                       "XDG_DATA_HOME": "/fixture/data", "XDG_CONFIG_HOME": "/fixture/config",
                       "XDG_RUNTIME_DIR": "/fixture/runtime"}
        with patch.dict(catalog.os.environ, {}, clear=True), \
                patch.object(catalog, "load_environment", return_value=environment), \
                patch.object(catalog.sys, "argv", argv), \
                patch.object(catalog.subprocess, "run", side_effect=record), \
                redirect_stdout(io.StringIO()):
            if reject:
                try:
                    catalog.main()
                except ValueError:
                    pass
                else:
                    self.fail(f"设备身份未确认却继续派发：{commands}")
                self.assertEqual(len(commands), 1, commands)
                self.assertTrue(all(command[-2:] == ["devices", "--machine"]
                                    for command in commands), commands)
            else:
                catalog.main()
        return commands

    def test_默认macos不能把Android设备交给普通安装(self):
        self.invoke([self.device()], reject=True)

    def test_显式非Android声明同样不能绕过保护(self):
        for platform in ("macos", "ios", "linux", "windows"):
            with self.subTest(platform=platform):
                self.invoke([self.device()], platform=platform, reject=True)

    def test_未知歧义和无效设备身份均拒绝安装(self):
        for devices in ([], [self.device("other-device")],
                        [self.device(), self.device()], "无法解析", {},
                        [dict(id="emulator-5554", isSupported=True)],
                        [self.device(platform="unknown")],
                        [dict(self.device(), isSupported=False)],
                        [dict(self.device(), isSupported="true")], [None],
                        [self.device("")], [self.device(123)]):
            with self.subTest(devices=devices):
                self.invoke(devices, platform="android", reject=True)

    def test_发现失败和超时均不派发安装(self):
        for error in (subprocess.CalledProcessError(1, ["flutter", "devices"]),
                      subprocess.TimeoutExpired(["flutter", "devices"], 60),
                      OSError("合成发现失败")):
            with self.subTest(error=error):
                self.invoke(error, platform="android", reject=True)

    def test_Flutter按名称或大小写匹配产生歧义时拒绝(self):
        for conflicting in (self.device("EMULATOR-5554"),
                            dict(self.device("other-device"), name="EMULATOR-5554")):
            with self.subTest(conflicting=conflicting):
                self.invoke([self.device(), conflicting], platform="android", reject=True)

    def test_预览同样拒绝实际Android与默认平台冲突(self):
        self.invoke([self.device()], reject=True, dry_run=True)

    def test_设备名称前缀和all不能成为隐式安装目标(self):
        devices = [self.device()]
        for selector in ("emulator", "合成设备", "all"):
            with self.subTest(selector=selector):
                self.invoke(devices, platform="android", device=selector, reject=True)

    def test_Android实际身份匹配后才专用分派(self):
        for target in ("android", "android-arm", "android-arm64", "android-x64"):
            with self.subTest(target=target):
                commands = self.invoke([self.device(platform=target)], platform="android")
                self.assertEqual(commands[0][-2:], ["devices", "--machine"])
                self.assertTrue(commands[-1][1].endswith("platform/android_materials.py"))
                self.assertEqual(commands[-1][-2:], ["--device", "emulator-5554"])

    def test_正常非Android保留普通入口且绑定精确ID(self):
        for platform, target in (("macos", "darwin"), ("ios", "ios"),
                                 ("linux", "linux-arm64"), ("windows", "windows-x64")):
            with self.subTest(platform=platform):
                commands = self.invoke([self.device("fixture-id", target)],
                                       platform=platform, device="fixture-id")
                self.assertEqual(commands[0][-2:], ["devices", "--machine"])
                self.assertEqual(commands[-1][1], "test")
                self.assertEqual(commands[-1][-2:], ["-d", "fixture-id"])

    def test_省略设备只接受所选平台唯一实际设备(self):
        commands = self.invoke([self.device()], platform="android", device=None)
        self.assertEqual(commands[-1][-2:], ["--device", "emulator-5554"])
        self.invoke([self.device(), self.device("emulator-5556")],
                    platform="android", device=None, reject=True)
        commands = self.invoke([self.device("macos", "darwin")], device=None)
        self.assertEqual(commands[-1][-2:], ["-d", "macos"])

    def test_其他材料入口同样在安装前核对实际平台(self):
        for entry, platform in (("platform/credentials/plugin_test.dart", "macos"),
                                ("platform/credentials/linux_test.dart", "linux")):
            with self.subTest(entry=entry):
                self.invoke([self.device()], platform=platform, reject=True, entry=entry)


class AndroidMaterialsTest(unittest.TestCase):
    def invoke(self, badging):
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory)
            (sdk / "build-tools/36.0.0").mkdir(parents=True)
            (sdk / "build-tools/36.0.0/aapt").touch()
            with patch.object(android_runner, "load_environment", return_value={"ANDROID_HOME": str(sdk)}), \
                 patch.object(android_runner.sys, "argv", [str(ANDROID_SCRIPT), "--device", "synthetic-device", "--apk", "fixture.apk"]), \
                 patch.object(android_runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, badging, "")) as run:
                try:
                    android_runner.main()
                except ValueError:
                    self.assertEqual(run.call_count, 1, "拒绝后不得安装或运行Flutter")
                    raise
                return run.call_args_list

    def test_生产APK即使Debug也拒绝启动(self):
        with self.assertRaisesRegex(ValueError, "独立合成"):
            self.invoke("package: name='cn.edu.ubaa'\napplication-debuggable\n")

    def test_独立身份的Release也拒绝启动(self):
        with self.assertRaisesRegex(ValueError, "Debug"):
            self.invoke(f"package: name='{android_runner.APPLICATION_ID}'\n")

    def test_无法解析APK拒绝启动(self):
        with self.assertRaisesRegex(ValueError, "独立合成"):
            self.invoke("无法解析\n")

    def test_独立Debug才运行原生用例(self):
        calls = self.invoke(f"package: name='{android_runner.APPLICATION_ID}'\napplication-debuggable\n")
        self.assertEqual(len(calls), 2)
        command = calls[-1].args[0]
        self.assertIn(android_runner.ENTRY, command)
        self.assertIn(android_runner.DEFINE, command)
        self.assertIn("--use-application-binary=", " ".join(command))


if __name__ == "__main__":
    unittest.main()
