#!/usr/bin/env python3
"""构建独立Android合成材料Debug包，核对APK身份后才安装运行真实插件。"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
from repo import ROOT
from toolchain import load_environment

APP = ROOT / "apps/ubaa_flutter"
APPLICATION_ID = "cn.edu.ubaa.synthetic.materials"
ENTRY = "integration_test/platform/credentials/material_test.dart"
DEFINE = "--dart-define=UBAA_SYNTHETIC_ANDROID_MATERIALS=true"


def verify_apk(aapt, apk, environment):
    result = subprocess.run([str(aapt), "dump", "badging", str(apk)],
                            env=environment, check=True, capture_output=True, text=True)
    package = re.search(r"^package: name='([^']+)'", result.stdout, re.M)
    if not package or package.group(1) != APPLICATION_ID:
        raise ValueError("APK不是独立合成材料应用，拒绝安装和启动")
    if not re.search(r"^application-debuggable(?:\s|$)", result.stdout, re.M):
        raise ValueError("合成材料入口只接受Debug APK，拒绝安装和启动")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="明确指定Android设备或模拟器ID")
    parser.add_argument("--apk", type=Path, help="复用已有APK，仍强制检查实际包名及Debug属性")
    args = parser.parse_args()
    environment = load_environment(ROOT)
    sdk = environment.get("ANDROID_HOME") or environment.get("ANDROID_SDK_ROOT")
    if not sdk:
        properties = APP / "android/local.properties"
        if properties.is_file():
            sdk = next((line.removeprefix("sdk.dir=") for line in properties.read_text().splitlines()
                        if line.startswith("sdk.dir=")), None)
    if not sdk or not Path(sdk).is_absolute():
        raise ValueError("需要Android SDK绝对目录和build-tools中的aapt")
    tools = sorted((Path(sdk) / "build-tools").glob("*/aapt"),
                   key=lambda p: tuple(int(x) for x in p.parent.name.split(".") if x.isdigit()))
    if not tools:
        raise ValueError("Android SDK缺少build-tools/aapt")
    # 不继承真实账号输入；此入口仅运行独立Debug包。
    for name in ("UBAA_CONFIG_DIR", "UBAA_LIVE_MATERIAL_SCOPE", "UBAA_TEST_USERNAME",
                 "UBAA_TEST_PASSWORD", "UBAA_USERNAME", "UBAA_PASSWORD"):
        environment.pop(name, None)
    flutter = ["just", "--justfile", str(ROOT / "justfile"), "flutter"]
    apk = args.apk.resolve() if args.apk else APP / "build/app/outputs/flutter-apk/app-debug.apk"
    if args.apk is None:
        subprocess.run([*flutter, "build", "apk", "--debug", "--target", ENTRY, DEFINE],
                       cwd=APP, env=environment, check=True)
    verify_apk(tools[-1], apk, environment)
    print(f"已核对独立Debug应用：{APPLICATION_ID}", flush=True)
    subprocess.run([*flutter, "drive", "--no-pub", "--target", ENTRY,
                    "--driver", "test_driver/native_materials.dart", "-d", args.device,
                    "--debug", DEFINE, f"--use-application-binary={apk}"],
                   cwd=APP, env=environment, check=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
