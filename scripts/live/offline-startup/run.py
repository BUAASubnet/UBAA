"""在已构建的独立只读入口上逐次创建进程，保留全部样本和原始计时。

不改学校协议、不复制会话；每次只从加密业务快照恢复相同的内容规模。
所有账号材料留在本轮专用目录/系统安全材料层，汇总不含业务正文。
"""
import argparse
from contextlib import ExitStack
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time
import uuid
from analyze import summarize
from identity import identity

REPO = Path(__file__).resolve().parents[3]


def command(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    path.chmod(0o600)


def credentials(path):
    values = {}
    for line in path.read_text().splitlines():
        key, separator, value = line.partition("=")
        if separator and key.strip() in {"UBAA_TEST_USERNAME", "UBAA_TEST_PASSWORD", "UBAA_USERNAME", "UBAA_PASSWORD"}:
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            values[key.strip()] = value
    username = values.get("UBAA_TEST_USERNAME") or values.get("UBAA_USERNAME")
    password = values.get("UBAA_TEST_PASSWORD") or values.get("UBAA_PASSWORD")
    if not username or not password:
        raise RuntimeError("缺少只读验证的账号材料")
    return (username + "\n" + password + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=["macos", "ios"], required=True)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--device")
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--env-file", type=Path, required=True)
    parser.add_argument("--route", choices=["direct", "webvpn"], default="webvpn")
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--scenario", choices=["online", "recoveryHeld", "recoveryFailed"], default="online")
    parser.add_argument("--timeout", type=int, default=660)
    args = parser.parse_args()
    os.umask(0o077)
    root = args.run_dir.resolve()
    if root.is_relative_to(REPO) or args.samples < 1 or args.timeout < 1:
        raise RuntimeError("测量证据必须保存在仓库外私有目录，样本与超时必须为正数")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    plist = args.app / ("Contents/Info.plist" if args.kind == "macos" else "Info.plist")
    info = plistlib.loads(plist.read_bytes())
    bundle = info["CFBundleIdentifier"]
    candidate = identity(REPO, args.app.resolve(), args.kind, args.device)
    if (root / "aborted.json").exists():
        raise RuntimeError("已中止轮次仅保留证据，请用新目录重新测量")
    manifest_file = root / "run.json"
    if manifest_file.exists():
        manifest = json.loads(manifest_file.read_text())
        if (manifest["kind"] != args.kind or manifest["route"] != args.route
                or manifest["device"] != args.device or manifest["scenario"] != args.scenario):
            raise RuntimeError("不能将不同设备或路线混入已有测量目录")
        if manifest.get("candidate") != candidate:
            raise RuntimeError("构建、源码或宿主指纹已变化，请保留旧轮次并使用新目录")
    else:
        token = uuid.uuid4().hex
        if args.kind == "ios":
            if not args.device:
                raise RuntimeError("iOS模拟器必须指定设备")
            subprocess.run(["xcrun", "simctl", "install", args.device, str(args.app.resolve())], check=True)
            container = Path(command(["xcrun", "simctl", "get_app_container", args.device, bundle, "data"]))
            config = container / "Library/Application Support" / ("UBAA-ui-readonly-offline-" + token)
        else:
            container = Path.home() / "Library/Containers" / bundle / "Data"
            if not container.is_dir():
                raise RuntimeError("macOS App私有容器尚未建立，请先运行本轮原生准备")
            config = container / "Library/Application Support" / ("UBAA-ui-readonly-offline-" + token)
        config.mkdir(parents=True, mode=0o700)
        manifest = {"kind": args.kind, "device": args.device, "route": args.route,
                    "config": str(config), "scope": "offline-live-" + token,
                    "head": command(["git", "rev-parse", "HEAD"], cwd=REPO),
                    "scenario": args.scenario, "candidate": candidate}
        save(manifest_file, manifest)
    config = Path(manifest["config"])
    launch_marker = config.parent / "UBAA" / "startup-measurement.json"
    helper = root / "process-start"
    subprocess.run(["xcrun", "clang", "-Wall", "-Wextra", "-Werror",
                    str(Path(__file__).with_name("process_start.c")), "-o", str(helper)], check=True)

    def launch(mode, name):
        output = config / (root.name + "-" + name + ".json")
        if output.exists():
            raise RuntimeError("拒绝覆盖已有样本；请使用新的样本名称")
        env = dict(os.environ)
        values = {"UBAA_CONFIG_DIR": str(config), "UBAA_LIVE_MATERIAL_SCOPE": manifest["scope"],
                  "UBAA_STARTUP_OUTPUT": str(output), "UBAA_STARTUP_MODE": mode,
                  "UBAA_EXPECTED_ROUTE": args.route, "UBAA_STARTUP_SCENARIO": args.scenario if mode == "sample" else "online"}
        launch_marker.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        # 独占标记，不能覆盖另一轮仍在使用的入口；失败也只清理自己创建的文件。
        with launch_marker.open("x") as marker:
            json.dump(values, marker, ensure_ascii=False)
        marker_inode = launch_marker.stat().st_ino

        def remove_own_marker():
            if launch_marker.exists() and launch_marker.stat().st_ino == marker_inode:
                launch_marker.unlink()

        with ExitStack() as cleanup:
            cleanup.callback(remove_own_marker)
            log = cleanup.enter_context((root / (name + ".log")).open("wb"))
            process = None
            pid = started = None
            try:
                if args.kind == "macos":
                    env.update(values)
                    binary = args.app / "Contents/MacOS" / info["CFBundleExecutable"]
                    process = subprocess.Popen([str(binary.resolve())], env=env, stdout=log, stderr=log)
                    pid = process.pid
                else:
                    env.update({"SIMCTL_CHILD_" + key: value for key, value in values.items()})
                    launch_output = command(["xcrun", "simctl", "launch", "--terminate-running-process",
                                             "--stdout=" + str(root / (name + "-app.log")),
                                             "--stderr=" + str(root / (name + "-app-error.log")),
                                             args.device, bundle], env=env, stderr=log)
                    match = re.search(r": (\d+)\s*$", launch_output)
                    if not match:
                        raise RuntimeError("模拟器未返回可验证PID")
                    pid = int(match[1])
                started = int(command([str(helper), str(pid)]))
                deadline = time.monotonic() + args.timeout
                while not output.exists() and time.monotonic() < deadline:
                    if process is not None and process.poll() is not None:
                        break
                    time.sleep(0.1)
                if output.exists():
                    result = json.loads(output.read_text())
                    if result["pid"] != pid:
                        raise RuntimeError("进程PID与样本不匹配")
                else:
                    result = {"status": "process_exited" if process is not None and process.poll() is not None else "driver_timeout",
                              "pid": pid, "times": {}, "business_writes": None}
                result["process_start_us"] = started
                result["sample_name"] = name
                save(root / (name + ".json"), result)
                return result
            finally:
                if process is not None:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=10)
                elif pid is not None and started is not None:
                    birth = subprocess.run([str(helper), str(pid)], capture_output=True, text=True)
                    if birth.returncode == 0 and int(birth.stdout.strip()) == started:
                        subprocess.run(["xcrun", "simctl", "terminate", args.device, bundle],
                                       stdout=log, stderr=log, check=False)
                    stop_deadline = time.monotonic() + 10
                    while time.monotonic() < stop_deadline:
                        birth = subprocess.run([str(helper), str(pid)], capture_output=True, text=True)
                        if birth.returncode or int(birth.stdout.strip()) != started:
                            break
                        time.sleep(0.1)
                    else:
                        raise RuntimeError("原模拟器进程尚未结束，拒绝恢复业务快照")

    prepared = root / "prepared.json"
    if not prepared.exists():
        with (root / "login.log").open("wb") as log:
            subprocess.run([str(REPO / "target/debug/core-live"), "--route", args.route,
                            "--feature", "schedule", "--config-dir", str(config),
                            "--date", time.strftime("%Y-%m-%d"), "--campus-id", "1",
                            "--username-stdin", "--password-stdin"], input=credentials(args.env_file),
                           stdout=log, stderr=log, check=True)
        result = launch("prepare", "prepare-" + uuid.uuid4().hex[:8])
        if result["status"] != "prepared":
            raise RuntimeError("只读准备失败；保留安全摘要和日志，不开始统计")
        shutil.copytree(config / "business-cache", root / "seed-business-cache")
        save(prepared, {"cache_bytes": sum(p.stat().st_size for p in (root / "seed-business-cache").rglob("*") if p.is_file()),
                        "outcomes": result.get("outcomes"), "encrypted_snapshot": True})
    samples = sorted(root.glob("sample-*.json"))
    values = [json.loads(p.read_text()) for p in samples]
    for index in range(len(values), args.samples):
        live = config / "business-cache"
        if live.exists():
            live.rename(root / ("after-" + str(index).zfill(3) + "-" + uuid.uuid4().hex[:8]))
        shutil.copytree(root / "seed-business-cache", live)
        value = launch("sample", "sample-" + str(index).zfill(3))
        values.append(value)
        save(root / "summary.json", summarize(values, planned=args.samples))
        print(f"样本 {index + 1}/{args.samples}：{value['status']}", flush=True)
    print(json.dumps(summarize(values, planned=args.samples), ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
