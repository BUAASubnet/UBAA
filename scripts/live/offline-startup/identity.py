"""记录候选与宿主指纹；不读取本机账号材料或运行会话。"""
import hashlib
import json
from pathlib import Path
import subprocess


def run(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def file_set_digest(root, names):
    digest = hashlib.sha256()
    for name in sorted(names):
        path = root / name
        if not path.is_file():
            continue
        digest.update(str(name).encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def identity(repo, app, kind, device):
    # 只对构建输入求摘要；输出不含源码、路径内的个人数据或环境变量。
    roots = ["crates", "packages", "apps/ubaa_flutter/lib",
             "apps/ubaa_flutter/integration_test/live/performance",
             "apps/ubaa_flutter/macos", "apps/ubaa_flutter/ios",
             "scripts/live/offline-startup", "Cargo.toml", "Cargo.lock"]
    tracked = run(["git", "ls-files", "-z", "--cached", "--others",
                   "--exclude-standard", "--", *roots], cwd=repo).split("\0")
    source = file_set_digest(repo, [Path(x) for x in set(tracked) if x])
    files = [p.relative_to(app) for p in app.rglob("*") if p.is_file()]
    host = {"os": run(["sw_vers", "-productVersion"]),
            "os_build": run(["sw_vers", "-buildVersion"]),
            "architecture": run(["uname", "-m"]),
            "model": run(["sysctl", "-n", "hw.model"]),
            "memory_bytes": int(run(["sysctl", "-n", "hw.memsize"]))}
    simulator = None
    if kind == "ios":
        inventory = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"]))
        for runtime, devices in inventory["devices"].items():
            for value in devices:
                if value["udid"] == device:
                    simulator = {"name": value["name"], "runtime": runtime,
                                 "physical_device": False}
        if simulator is None:
            raise RuntimeError("测量目标不在当前模拟器清单")
    return {"source_sha256": source, "app_sha256": file_set_digest(app, files),
            "host": host, "simulator": simulator,
            "disk_condition": "warm_os_cache_fixed_encrypted_business_snapshot",
            "process_condition": "new_kernel_process_each_sample"}
