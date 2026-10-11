"""外部宿主持有合成文件锁；原生 App 保留 Sandbox 和原 FFI 路径。"""
import fcntl
from pathlib import Path
import subprocess
import sys
import tempfile
import threading


def run(command):
    parent = None
    if sys.platform == "darwin":
        parent = Path.home() / "Library/Containers/cn.edu.ubaa.ubaaFlutter/Data/tmp"
        parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ubaa-startup-lock-", dir=parent) as temporary:
        directory = Path(temporary)
        stop = threading.Event()

        def hold():
            while not stop.wait(0.02):
                if (directory / "request-lock").exists():
                    break
            if stop.is_set():
                return
            with (directory / ".session.lock").open("w+") as handle:
                fcntl.flock(handle, fcntl.LOCK_EX)
                (directory / "holder-ready").touch()
                print("外部持锁已就绪", flush=True)
                while not stop.wait(0.02):
                    if (directory / "release-request").exists():
                        fcntl.flock(handle, fcntl.LOCK_UN)
                        (directory / "holder-released").touch()
                        return

        holder = threading.Thread(target=hold)
        holder.start()
        print(f"持锁夹具：{directory.name}", flush=True)
        try:
            return subprocess.call([*command, f"--dart-define=UBAA_STARTUP_LOCK_DIR={directory}"])
        finally:
            stop.set()
            holder.join(timeout=5)


if __name__ == "__main__":
    raise SystemExit(run(sys.argv[1:]))
