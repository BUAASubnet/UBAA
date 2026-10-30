#!/usr/bin/env python3
"""校验、列出并显式执行登记的 Flutter 集成测试；不隐式运行账号流程。"""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
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
ENVIRONMENT_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
# 默认集合在此生成一次构建、一次启动的聚合入口，运行结束即删除。
# Flutter 只把 integration_test/ 下的文件当作集成测试；点目录不参与登记、格式化和分析。
AGGREGATE_DIR = ".ci_suite"
AGGREGATE_PATH = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_/]*\.dart$")


def source_closure(path, root, seen=None):
    """包含跨根 helper、自有 package 和条件分支，不访问外部依赖正文。"""
    closure = SourceClosure(workspace_for(root))
    closure.add(path)
    return "\n".join(closure.sources.values())


def _entry_values(entry, name):
    values = entry.get(name, [])
    if not isinstance(values, list) or any(not isinstance(value, str) for value in values):
        raise ValueError(f"入口 {entry.get('path', '<unknown>')} 的 {name} 必须是字符串数组")
    return values


def environment_for_entry(entry, base_environment):
    """校验入口声明的前提，并返回传给 Flutter 的环境副本。"""
    environment = dict(base_environment)
    required = _entry_values(entry, "environment")
    invalid = [name for name in required if not ENVIRONMENT_NAME.fullmatch(name)]
    if invalid:
        raise ValueError(f"入口 {entry['path']} 的环境变量名无效：{invalid}")
    missing = [name for name in required if not environment.get(name)]
    if missing:
        raise ValueError(f"入口 {entry['path']} 缺少必需环境变量：{missing}")
    return environment


def build_command(entry, flutter, platform, device=None):
    """根据清单组装 Flutter 命令，不拼接 Shell 字符串。"""
    runner = entry.get("runner", "test")
    if runner not in {"test", "run"}:
        raise ValueError(f"入口 {entry['path']} 的执行方式无效：{runner}")
    command = [str(flutter), runner, f"integration_test/{entry['path']}",
               "-d", device or platform]
    for define in _entry_values(entry, "defines"):
        key, separator, _ = define.partition("=")
        if not separator or not key or any(character in define for character in "\x00\r\n"):
            raise ValueError(f"入口 {entry['path']} 的 Dart define 无效：{define!r}")
        command.append(f"--dart-define={define}")
    return command


def validate(entries, root=TEST_ROOT):
    """实际入口与清单双向一致，失效路径和未知条件均拒绝。"""
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*.dart")
              if p.relative_to(root).parts[0] != AGGREGATE_DIR
              and (p.name.endswith(("_test.dart", "_driver.dart"))
                   or re.search(r"^(?:Future<void>|void) main\(", p.read_text(), re.M))}
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
        _entry_values(entry, "environment")
        _entry_values(entry, "defines")
        for name in entry.get("environment", []):
            if not ENVIRONMENT_NAME.fullmatch(name):
                raise ValueError(f"入口环境变量名无效：{path}")
        for define in entry.get("defines", []):
            key, separator, _ = define.partition("=")
            if not separator or not key or any(character in define for character in "\x00\r\n"):
                raise ValueError(f"入口 Dart define 无效：{path}")
        if "harness" in entry:
            raise ValueError(f"未登记的外部合成夹具：{path}")
        source = source_closure(root / path, root)
        if any(marker in source for marker in LIVE_MARKERS) and entry["kind"] not in {"live", "manual"}:
            raise ValueError(f"真实账号标记与分类不符：{path}")
        if not isinstance(entry["inspection"], bool):
            raise ValueError(f"缺少人工巡检模式说明：{path}")
    return entries


def aggregate(entries, root):
    """把多个入口合成一个清单项与 Dart 源码；前提冲突或无法合并时拒绝，不静默拆分。"""
    defines = {}
    for entry in entries:
        path = entry["path"]
        if entry.get("runner", "test") != "test":
            raise ValueError(f"聚合入口只接受 flutter test：{path}")
        if not AGGREGATE_PATH.fullmatch(path) or path.split("/")[0] == AGGREGATE_DIR:
            raise ValueError(f"入口路径不能安全写入聚合源码：{path}")
        # group 回调必须同步；异步 main 的顶层 await 无法在 group 内等待。
        if not re.search(r"^void main\(\)", (root / path).read_text(), re.M):
            raise ValueError(f"聚合入口要求同步 void main()：{path}")
        for define in _entry_values(entry, "defines"):
            key, _, value = define.partition("=")
            if defines.setdefault(key, value) != value:
                raise ValueError(f"入口 Dart define 冲突，不能合并：{key}")
    merged = {
        "path": f"{AGGREGATE_DIR}/suite_test.dart",
        "runner": "test",
        "environment": sorted({name for entry in entries for name in _entry_values(entry, "environment")}),
        "defines": [f"{key}={value}" for key, value in defines.items()],
    }
    lines = ["// 由 scripts/check/integration_catalog.py 按清单生成，运行结束即删除。",
             "import 'package:flutter_test/flutter_test.dart';", ""]
    lines += [f"import '../{entry['path']}' as entry{index};" for index, entry in enumerate(entries)]
    lines += ["", "void main() {"]
    lines += [f"  group('{entry['path']}', entry{index}.main);" for index, entry in enumerate(entries)]
    lines += ["}", ""]
    return merged, "\n".join(lines)


def select(entries, suite, platform):
    if platform not in PLATFORMS:
        raise ValueError(f"未知平台：{platform}")
    if suite in {"ci", "ci-isolated"}:
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
    parser.add_argument("--suite", default="ci",
                        help="ci（一次构建运行全部默认入口）、ci-isolated（逐个文件构建运行）或清单中的精确入口路径")
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
    # 任一入口前提缺失时不启动任何命令，也不生成聚合入口。
    for entry in selected:
        environment_for_entry(entry, environment)
    runs, generated = selected, None
    if args.suite == "ci" and len(selected) > 1:
        # 每个入口文件都会触发一次原生构建和应用启动，默认集合合并为一次。
        merged, generated = aggregate(selected, TEST_ROOT)
        runs = [merged]
        print("聚合入口：" + "、".join(entry["path"] for entry in selected), flush=True)
    commands = []
    for entry in runs:
        entry_environment = environment_for_entry(entry, environment)
        command = build_command(entry, flutter, args.platform, args.device)
        commands.append((command, entry_environment))
    if not args.dry_run:
        subprocess.run(["bash", str(ROOT / "scripts/check/flutter-toolchains.sh"), "official"],
                       cwd=ROOT, env=environment, check=True)
    aggregate_dir = TEST_ROOT / AGGREGATE_DIR
    try:
        if generated is not None and not args.dry_run:
            shutil.rmtree(aggregate_dir, ignore_errors=True)
            aggregate_dir.mkdir()
            (TEST_ROOT / runs[0]["path"]).write_text(generated)
        for command, entry_environment in commands:
            print(shlex.join(command), flush=True)
            if not args.dry_run:
                subprocess.run(command, cwd=APP, env=entry_environment, check=True)
    finally:
        if generated is not None and not args.dry_run:
            shutil.rmtree(aggregate_dir, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
