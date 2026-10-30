"""标准 SBOM 与许可证材料必须拒绝无效格式，并保留缺失证据。"""
import importlib.util
import hashlib
import json
from pathlib import Path
import subprocess
import os
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


spec = importlib.util.spec_from_file_location("dependency_report", ROOT / "scripts/release/dependency_report.py")
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)
build = report.build_sbom


class ReleaseMetadataTest(unittest.TestCase):
    def test_默认Dart锁文件清单包含根workspace锁(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            nested = root / "apps/sample"
            nested.mkdir(parents=True)
            (root / "pubspec.lock").write_text("root")
            (nested / "pubspec.lock").write_text("nested")
            subprocess.run(["git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(["git", "-C", str(root), "add", "pubspec.lock", "apps/sample/pubspec.lock"], check=True)
            self.assertEqual(
                [path.relative_to(root).as_posix() for path in report.dart_lockfiles(root)],
                ["apps/sample/pubspec.lock", "pubspec.lock"],
            )

    def test_材料缺口默认阻止发布但报告模式允许保留(self):
        records = [
            {"ecosystem": "dart", "name": "ok", "evidence_status": "collected"},
            {"ecosystem": "dart", "name": "missing", "evidence_status": "source_unavailable"},
        ]
        self.assertEqual(report.release_exit_code(records), report.RELEASE_BLOCKED_EXIT)
        self.assertEqual(report.release_exit_code(records, report_only=True), 0)
        self.assertEqual(report.release_exit_code(records[:1]), 0)

    def test_发布前置清单也包含根锁文件(self):
        source = (ROOT / "scripts/release/preflight.sh").read_text()
        self.assertIn("'pubspec.lock'", source)
        self.assertIn("preserve_output=1", source)

    def test_复合许可证不能放在单一ID字段(self):
        document = build({"packages": [{"name": "sample", "version": "1.0.0",
                                        "license": "MIT OR Apache-2.0"}]})
        self.assertEqual(document["components"][0]["licenses"],
                         [{"expression": "MIT OR Apache-2.0"}])

    def test_非标准声明保留名称并显式待核对(self):
        document = build({"packages": [{"name": "sample", "version": "1.0.0",
                                        "license": "Custom-Project-License"}]})
        component = document["components"][0]
        self.assertEqual(component["licenses"], [{"license": {"name": "Custom-Project-License"}}])
        self.assertIn({"name": "ubaa:license-evidence", "value": "需人工核对声明"}, component["properties"])

    def test_无效license_id被离线schema拒绝(self):
        document = build({"packages": [{"name": "sample", "version": "1", "license": "MIT"}]})
        document["components"][0]["licenses"][0]["license"]["id"] = "MIT OR Apache-2.0"
        self.assertRaisesRegex(ValueError, "schema", report.validate_sbom, document)

    def test_未闭合表达式不冒充标准SPDX(self):
        document = build({"packages": [{"name": "sample", "version": "1", "license": "(MIT OR)"}]})
        self.assertEqual(document["components"][0]["licenses"], [{"license": {"name": "(MIT OR)"}}])

    def test_缺少许可证可见且不是通过许可审核(self):
        document = build({"packages": [{"name": "sample", "version": "1", "license": None}]})
        component = document["components"][0]
        self.assertNotIn("licenses", component)
        self.assertIn("缺少", component["properties"][0]["value"])

    def test_Dart材料来自锁定包正文并保留摘要(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "vendor"
            package.mkdir()
            (package / "pubspec.yaml").write_text("name: sample\nversion: 1.0.0\n")
            body = b"Synthetic license evidence"
            (package / "LICENSE").write_bytes(body)
            lock = root / "pubspec.lock"
            lock.write_text("packages:\n  sample:\n    version: 1.0.0\n    source: path\n    description:\n      path: vendor\n")
            output = root / "output"
            records = report.dart_evidence(root, output, [lock])
            self.assertEqual(records[0]["evidence_status"], "collected")
            evidence = records[0]["files"][0]
            self.assertEqual(evidence["sha256"], hashlib.sha256(body).hexdigest())
            self.assertEqual((output / evidence["artifact"]).read_bytes(), body)
            self.assertNotIn(str(root), json.dumps(records))

    def test_Dart缺源或版本漂移明确标记(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = root / "pubspec.lock"
            lock.write_text("packages:\n  sample:\n    version: 1.0.0\n    source: path\n    description:\n      path: vendor\n")
            self.assertEqual(report.dart_evidence(root, root / "output", [lock])[0]["evidence_status"],
                             "source_unavailable")
            (root / "vendor").mkdir()
            (root / "vendor/pubspec.yaml").write_text("name: sample\nversion: 2.0.0\n")
            (root / "vendor/LICENSE").write_text("不可当成锁定版本证据")
            self.assertEqual(report.dart_evidence(root, root / "output", [lock])[0]["evidence_status"],
                             "lock_mismatch")

    def test_OHOS实际许可证与原生依赖缺口分开(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "plugin"
            (package / "ohos").mkdir(parents=True)
            (package / "LICENSE").write_text("插件实际许可")
            (package / "LICENSE-BSD").write_text("保留上游许可")
            manifest = package / "ohos/oh-package.json5"
            manifest.write_text('{name:"plugin",version:"1",dependencies:{flutter:"file:/private/sdk/flutter.har",},}')
            records = report.ohos_evidence(root, root / "output", [manifest])
            self.assertEqual(records[0]["evidence_status"], "collected")
            self.assertEqual(len(records[0]["files"]), 2)
            self.assertEqual(records[1]["evidence_status"], "native_dependency_requires_artifact_review")
            self.assertNotIn("/private/sdk", json.dumps(records))

    def test_工具未准备时失败且不自动安装(self):
        with tempfile.TemporaryDirectory() as directory:
            absent = Path(directory) / "missing"
            result = subprocess.run(["bash", str(ROOT / "scripts/tools/python.sh"), "-c", "pass"],
                                    env=dict(os.environ, UBAA_QUALITY_TOOLS_DIR=str(absent)),
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("quality-tools-bootstrap", result.stderr)
            self.assertFalse(absent.exists())


if __name__ == "__main__":
    unittest.main()
