"""在临时 Git 仓库验证报告模式、发布阻断与失败报告的保留。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class ReleasePreflightTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "repo"
        self.root.mkdir()
        for name in ("scripts/release/preflight.sh", "scripts/lib/repo.py", "scripts/lib/repo.sh"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        for name in ("scripts/lib/toolchain.sh", "scripts/check/references.sh", "scripts/check/sensitive.sh"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("#!/usr/bin/env bash\nexit 0\n" if "/check/" in name else "# 合成工具链\n")
        (self.root / "scripts/tools").mkdir()
        (self.root / "scripts/tools/python.sh").write_text('#!/usr/bin/env bash\nexec python3 "$@"\n')
        (self.root / "scripts/release/dependency_report.py").write_text(
            "import argparse,json,os\nfrom pathlib import Path\n"
            "p=argparse.ArgumentParser();p.add_argument('--output',type=Path);"
            "p.add_argument('--report-only',action='store_true');a=p.parse_args()\n"
            "if os.environ.get('TEST_REPORT_FAILURE'): raise SystemExit(2)\n"
            "(a.output/'license-evidence.json').write_text(json.dumps({'material_status':'partial',"
            "'release_blockers':[{'name':'synthetic-native','reason':'license_missing'}]}))\n"
            "raise SystemExit(0 if a.report_only else 3)\n"
        )
        (self.root / "pubspec.lock").write_text("packages: {}\n")
        (self.root / "apps/sample").mkdir(parents=True)
        (self.root / "apps/sample/pubspec.lock").write_text("packages: {}\n")
        self.bin = self.base / "bin"
        self.bin.mkdir()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "add", "scripts", "pubspec.lock", "apps"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=测试", "-c",
                        "user.email=fixture@example.invalid", "commit", "-qm", "合成候选"], check=True)

    def run_preflight(self, mode="strict", **environment):
        output = self.base / "report"
        result = subprocess.run(["bash", "scripts/release/preflight.sh", str(output), mode], cwd=self.root,
                                env={**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                                     **environment}, capture_output=True, text=True)
        return result, output

    def test_默认严格模式返回发布阻断且保留完整报告(self):
        result, output = self.run_preflight()
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertFalse((output / "sbom.cdx.json").exists())
        self.assertIn("发布阻塞", (output / "summary.txt").read_text())

    def test_报告模式保留partial与阻断但不充当发布通过(self):
        result, output = self.run_preflight("report")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads((output / "license-evidence.json").read_text())
        self.assertEqual(report["material_status"], "partial")
        self.assertEqual(len(report["release_blockers"]), 1)
        summary = (output / "summary.txt").read_text()
        self.assertIn("仅报告", summary)
        self.assertIn("partial", summary)
        self.assertIn("发布阻塞：1", summary)

    def test_报告模式仍传播真实生成错误(self):
        result, _ = self.run_preflight("report", TEST_REPORT_FAILURE="1")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_未知模式拒绝执行(self):
        result, output = self.run_preflight("unknown")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
