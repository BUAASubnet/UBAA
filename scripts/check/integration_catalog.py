#!/usr/bin/env python3
"""校验、列出并显式执行登记的 Flutter 集成测试；不隐式运行账号流程。"""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from dart_sources import SourceClosure, workspace_for
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from toolchain import load_environment


from repo import ROOT
APP = ROOT / "apps" / "ubaa_flutter"
TEST_ROOT = APP / "integration_test"
MANIFEST = ROOT / "scripts" / "integration-tests.json"
KINDS = {"synthetic", "platform", "live", "manual"}
PLATFORMS = {"macos", "ios", "android", "linux", "windows"}
LIVE_MARKERS = ("UBAA_LIVE_READONLY", "UBAA_VERIFY_WEBVPN", "UBAA_LIVE_MATERIAL_SCOPE")


def source_closure(path, root, seen=None):
    """包含跨根 helper、自有 package 和条件分支，不访问外部依赖正文。"""
    closure = SourceClosure(workspace_for(root))
    closure.add(path)
    return "\n".join(closure.sources.values())


def validate(entries, root=TEST_ROOT):
    """实际入口与清单双向一致，失效路径和未知条件均拒绝。"""
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*.dart")
              if p.name.endswith(("_test.dart", "_driver.dart"))
              or re.search(r"^(?:Future<void>|void) main\(", p.read_text(), re.M)}
    paths = [entry["path"] for entry in entries]
    if len(paths) != len(set(paths)):
        raise ValueError("集成清单存在重复入口")
    missing, stale = actual - set(paths), set(paths) - actual
    if missing or stale:
        raise ValueError(f"未登记入口：{sorted(missing)}；失效入口：{sorted(stale)}")
    for entry in entries:
        path = entry["path"]
        section = Path(path).parts[0]
        if section in KINDS and section != entry["kind"]:
            raise ValueError(f"目录与证据分类不符：{path}")
        if entry["kind"] not in KINDS or not entry["domain"]:
            raise ValueError(f"无效分类：{path}")
        if not entry["platforms"] or not set(entry["platforms"]) <= PLATFORMS:
            raise ValueError(f"无效平台：{path}")
        if entry["ci"] and entry["kind"] in {"live", "manual"}:
            raise ValueError(f"真实或人工入口不得进入 CI：{path}")
        runner = entry.get("runner", "test")
        if runner not in {"test", "run"} or (runner == "run" and entry["ci"]):
            raise ValueError(f"入口执行方式或 CI 归属不符：{path}")
        harness = entry.get("harness")
        if harness is not None and (harness != "startup-lock" or entry["kind"] != "synthetic"
                                    or not set(entry["platforms"]) <= {"macos", "linux"}):
            raise ValueError(f"未登记的外部合成夹具：{path}")
        source = source_closure(root / path, root)
        if any(marker in source for marker in LIVE_MARKERS) and entry["kind"] not in {"live", "manual"}:
            raise ValueError(f"真实账号标记与分类不符：{path}")
        if not isinstance(entry["inspection"], bool):
            raise ValueError(f"缺少人工巡检模式说明：{path}")
    return entries


def select(entries, suite, platform):
    if platform not in PLATFORMS:
        raise ValueError(f"未知平台：{platform}")
    if suite == "ci":
        selected = [e for e in entries if e["ci"] and platform in e["platforms"]]
    else:
        selected = [e for e in entries if e["path"] == suite]
        if not selected:
            raise ValueError(f"没有登记的入口：{suite}")
        if platform not in selected[0]["platforms"]:
            raise ValueError("入口与所选平台不匹配")
        if selected[0]["kind"] in {"live", "manual"}:
            raise ValueError("真实或人工入口必须使用显式专项命令，不能混入自动回归")
    if not selected:
        raise ValueError("当前平台没有可执行的测试")
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check", "list", "run"])
    parser.add_argument("--suite", default="ci", help="ci 或清单中的精确入口路径")
    parser.add_argument("--platform", default="macos", choices=sorted(PLATFORMS))
    parser.add_argument("--device", help="Flutter 的设备 ID；默认使用平台名")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    entries = validate(json.loads(MANIFEST.read_text())["tests"])
    if args.action == "check":
        print(f"集成清单通过：{len(entries)} 个入口，分类和路径完整")
        return
    if args.action == "list":
        for entry in entries:
            print(f'{entry["kind"]:9} {",".join(entry["platforms"]):24} '
                  f'CI={str(entry["ci"]):5} {entry["path"]}')
        return
    selected = select(entries, args.suite, args.platform)
    os.environ.update(load_environment(ROOT))
    flutter_root = os.environ.get("UBAA_FLUTTER_HOME", "")
    if not flutter_root or not Path(flutter_root).is_absolute():
        raise ValueError("请设置 UBAA_FLUTTER_HOME 为锁定官方 Flutter SDK 的绝对路径")
    flutter = Path(flutter_root) / "bin" / "flutter"
    environment = os.environ.copy()
    # 即使从带账号的终端发起，常规回归也不会继承真实配置入口。
    for name in ("UBAA_CONFIG_DIR", "UBAA_LIVE_MATERIAL_SCOPE", "UBAA_TEST_USERNAME",
                 "UBAA_TEST_PASSWORD", "UBAA_USERNAME", "UBAA_PASSWORD"):
        environment.pop(name, None)
    if not args.dry_run:
        subprocess.run(["bash", str(ROOT / "scripts/check/flutter-toolchains.sh"), "official"],
                       cwd=ROOT, env=environment, check=True)
    for entry in selected:
        command = [str(flutter), "test", f'integration_test/{entry["path"]}',
                   "-d", args.device or args.platform]
        if entry.get("harness") == "startup-lock":
            command = [sys.executable, str(ROOT / "scripts/tests/native/startup_lock_runner.py"), *command]
        print(shlex.join(command), flush=True)
        if not args.dry_run:
            subprocess.run(command, cwd=APP, env=environment, check=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
