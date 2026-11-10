#!/usr/bin/env python3
"""显式联调控制器、Dart FFI、Core、本地 D1 与 KV；不进入 CI。"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import sys
import tempfile
from threading import Thread
from urllib.parse import urlsplit

sys.dont_write_bytecode = True
from http_e2e import (BOOTSTRAP, ERASE, LOOPBACK, QUERY, ROOT, SERVICE, UPLOAD,
                      WRANGLER, exchange, require, run, seed_bootstrap, worker)


def main():
    require(not os.environ.get("CI"), "本地 Bridge 联调不在 CI 运行")
    require(os.environ.get("UBAA_TELEMETRY") != "0", "遥测已硬关闭，不能联调")
    require(WRANGLER.is_file(), "缺少本地 Wrangler，请先运行 just app-service-check")
    run(["node", "scripts/compile-schema.mjs"], cwd=SERVICE)
    run(["cargo", "build", "--locked", "-p", "ubaa_flutter_bridge"], cwd=ROOT)
    filename = {"darwin": "libubaa_flutter_bridge.dylib", "linux": "libubaa_flutter_bridge.so",
                "win32": "ubaa_flutter_bridge.dll"}.get(sys.platform)
    require(filename is not None, "当前主机不支持 Bridge 联调")
    library = Path(os.environ.get("CARGO_TARGET_DIR", ROOT / "target")) / "debug" / filename
    require(library.is_file(), "找不到本机 Bridge 动态库")

    parent = ROOT / ".ubaa_local/app_service"
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bridge_e2e_", dir=parent) as temporary:
        directory = Path(temporary)
        vars_file = directory / ".env"
        vars_file.write_text(f"USER_KEY_SECRET={secrets.token_hex(32)}\n")
        env = dict(os.environ, WRANGLER_LOG_PATH=str(directory / "wrangler_logs"),
                   WRANGLER_HIDE_BANNER="true", WRANGLER_SEND_METRICS="false",
                   WRANGLER_SEND_ERROR_REPORTS="false", CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV="true")
        env.pop("USER_KEY_SECRET", None)
        env_file = ["--env-file", str(vars_file)]
        database = ["DB", "--local", "--persist-to", str(directory / "d1")]
        run([str(WRANGLER), "d1", "migrations", "apply", *database, *env_file], cwd=SERVICE, env=env)
        seed_bootstrap(directory, env_file, env)

        def query():
            response = run([str(WRANGLER), "d1", "execute", *database, "--json",
                            "--command", QUERY, *env_file], cwd=SERVICE, env=env, capture=True)
            return json.loads(response.stdout)[0]["results"][0]

        sent = {UPLOAD: 0, ERASE: 0, BOOTSTRAP: 0}
        observations = []
        with worker(env_file, env, directory) as port:
            class Relay(BaseHTTPRequestHandler):
                def log_message(self, *_args):
                    pass

                def do_GET(self):
                    if urlsplit(self.path).path == BOOTSTRAP and self.has_no_identity():
                        sent[BOOTSTRAP] += 1
                        status, body = exchange(port, self.path)
                    else:
                        status, body = 400, b""
                    self.reply(status, body)

                def has_no_identity(self):
                    return "Cookie" not in self.headers and "Authorization" not in self.headers

                def do_POST(self):
                    if self.path not in {UPLOAD, ERASE} or not self.has_no_identity():
                        status = 400
                    else:
                        sent[self.path] += 1
                        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                        if self.path == ERASE and sent[ERASE] == 1:
                            observations.append(query())
                            status = 503
                        else:
                            status, _ = exchange(port, self.path, body)
                    self.reply(status)

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
                               f"--dart-define=UBAA_APP_SERVICE_TEST_LIBRARY={library.resolve()}",
                               f"--dart-define=UBAA_APP_SERVICE_TEST_STATE={directory / 'state'}"]
                    test = "apps/ubaa_flutter/test/support/platform/app_service_bridge_smoke.dart"
                    run([*command, test], cwd=ROOT)
                    require(sent == {UPLOAD: 1, ERASE: 1, BOOTSTRAP: 1},
                            "首次进程的请求数与上报、删除及同意后刷新不符")
                    run([*command, "--dart-define=UBAA_APP_SERVICE_TEST_REOPEN=true", test], cwd=ROOT)
                finally:
                    server.shutdown()
                    thread.join()
            require(sent == {UPLOAD: 1, ERASE: 2, BOOTSTRAP: 1},
                    "应有一次启动配置刷新、一次上报、一次删除失败和一次成功重试")
            require(len(observations) == 1 and observations[0]["active"] == 1
                    and observations[0]["counters"] == 1 and observations[0]["tombstones"] == 0,
                    "删除前 D1 未收到 Dart Bridge 生成的实际计数")
            require(query() == dict(batches=1, tombstones=1, active=0, user_key=None,
                                    counters=0, errors=0, timings=0),
                    "删除重试成功后本地 D1 仍有明细")
    print("Dart Bridge 与本地 D1 联调通过：同意后真实上报，关闭共享开关，重启完成删除")
    print("Dart Bridge 与本地 KV 联调通过：同意后收到门控和公告，命令模式拦截认证，公告已读可重启恢复")


if __name__ == "__main__":
    main()
