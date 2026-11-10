#!/usr/bin/env python3
"""显式联调宿主接线、Dart FFI、Core、本地 D1 与 KV；不进入 CI。"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import sys
from threading import Thread
from urllib.parse import urlsplit

sys.dont_write_bytecode = True
from http_e2e import (BOOTSTRAP, EMPTY, ERASE, ERASED, LOOPBACK, ROOT, UPLOAD,
                      exchange, local_worker, prepare, require, run)


UPLOADED = dict(EMPTY, batches=1, active=1, counters=1)


def main():
    filename = {"darwin": "libubaa_flutter_bridge.dylib", "linux": "libubaa_flutter_bridge.so",
                "win32": "ubaa_flutter_bridge.dll"}.get(sys.platform)
    require(filename is not None, "当前主机不支持 Bridge 联调")
    run(["cargo", "build", "--locked", "-p", "ubaa_flutter_bridge"], cwd=ROOT, timeout=1200)
    library = ROOT / os.environ.get("CARGO_TARGET_DIR", "target") / "debug" / filename
    require(library.is_file(), "找不到本机 Bridge 动态库")

    sent = {UPLOAD: 0, ERASE: 0, BOOTSTRAP: 0}
    with local_worker("bridge") as (directory, port, query, _secret):
        class Relay(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def has_no_identity(self):
                return "Cookie" not in self.headers and "Authorization" not in self.headers

            def do_GET(self):
                if urlsplit(self.path).path == BOOTSTRAP and self.has_no_identity():
                    sent[BOOTSTRAP] += 1
                    status, body = exchange(port, self.path)
                    self.reply(status, body)
                else:
                    self.reply(400)

            def do_POST(self):
                if self.path not in {UPLOAD, ERASE} or not self.has_no_identity():
                    self.reply(400)
                    return
                sent[self.path] += 1
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                if ((self.path == UPLOAD and sent[UPLOAD] == 2)
                        or (self.path == ERASE and sent[ERASE] == 1)):
                    # 拒绝第二次上传以留下重试批次；拒绝首次删除以留下重启标记。
                    self.reply(503)
                    return
                status, response = exchange(port, self.path, body)
                self.reply(status, response)

            def reply(self, status, body=b""):
                self.send_response(status)
                if body:
                    self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if body:
                    self.wfile.write(body)

        with ThreadingHTTPServer((LOOPBACK, 0), Relay) as server:
            thread = Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                command = ["just", "flutter", "test", "--no-pub",
                           f"--dart-define=UBAA_APP_SERVICE_URL=http://{LOOPBACK}:{server.server_port}",
                           "--dart-define=UBAA_DISTRIBUTION_CHANNEL=github",
                           f"--dart-define=UBAA_APP_SERVICE_TEST_LIBRARY={library.resolve()}"]
                env = dict(os.environ, UBAA_CONFIG_DIR=str(directory / "state"))
                test = "apps/ubaa_flutter/test/support/platform/app_service_bridge_smoke.dart"
                run([*command, test], cwd=ROOT, env=env, timeout=600)
                require(sent == {UPLOAD: 2, ERASE: 1, BOOTSTRAP: 1},
                        "首次进程的请求数不符；可能未真实上传，或重新开启后发送了已清理批次")
                require(query() == UPLOADED,
                        "D1 未收到实际宿主计数，或关闭清理、门控、公告、失败删除产生了额外写入")
                run([*command, "--dart-define=UBAA_APP_SERVICE_TEST_REOPEN=true", test],
                    cwd=ROOT, env=env, timeout=600)
                require(sent == {UPLOAD: 2, ERASE: 2, BOOTSTRAP: 1},
                        "基础模式重启只允许 GUI 重试删除，命令模式不得发请求")
                require(query() == ERASED, "重启删除成功后 D1 仍有旧明细，或发生了额外写入")
            finally:
                server.shutdown()
                thread.join()
    print("宿主与本地 D1 联调通过：正常上报，关闭清除待重试批次，基础模式重启只重试删除")
    print("宿主与本地 KV 联调通过：命令模式共享门控，公告已读可跨进程恢复")


if __name__ == "__main__":
    try:
        prepare()
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from None
