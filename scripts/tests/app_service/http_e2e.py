#!/usr/bin/env python3
"""显式联调 Core 与 Wrangler 本地 Worker、D1 和 KV，不进入 CI。"""

from contextlib import contextmanager
import hashlib
import hmac
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
from socketserver import BaseRequestHandler, TCPServer
import ssl
import subprocess
import sys
import tempfile
from threading import Event, Thread
import time
from urllib.parse import parse_qsl, urlsplit

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
from environment import read_values
from repo import ROOT


SERVICE = ROOT / "services/app_service"
WRANGLER = SERVICE / "node_modules/.bin/wrangler"
LOOPBACK = "127.0.0.1"
UPLOAD = "/v1/telemetry"
ERASE = "/v1/telemetry/erase"
BOOTSTRAP = "/v1/bootstrap"
QUERY = """
SELECT (SELECT count(*) FROM batches) AS batches,
       (SELECT count(*) FROM erased_installs) AS tombstones,
       (SELECT count(*) FROM active_days) AS active,
       (SELECT user_key FROM active_days WHERE platform = 'macos' AND channel = 'github'
         AND app_version = '2.1.0-rc.1+15' AND cohort_type = 'TQ'
         AND cohort_year = 2024 AND surface_mask = 1) AS user_key,
       (SELECT coalesce(sum(count), 0) FROM counter_days) AS counters,
       (SELECT coalesce(sum(count), 0) FROM error_days) AS errors,
       (SELECT coalesce(sum(count), 0) FROM timing_days) AS timings,
       (SELECT coalesce(sum(count), 0) FROM minute_counts) AS minutes
"""
EMPTY = dict(batches=0, tombstones=0, active=0, user_key=None, counters=0, errors=0, timings=0,
             minutes=0)
ERASED = dict(EMPTY, batches=1, tombstones=1)
ERASED_WITH_MINUTES = dict(ERASED, minutes=2)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(command, *, cwd, env=None, capture=False, timeout=240):
    return subprocess.run(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                          check=True, capture_output=capture, text=True, timeout=timeout)


@contextmanager
def worker(env_file, env, directory):
    log = directory / "worker.log"
    with log.open("wb") as output, subprocess.Popen(
        [str(WRANGLER), "dev", "--local", "--ip", LOOPBACK, "--port", "0",
         "--inspector-port", "0", "--persist-to", str(directory / "d1"), *env_file],
        cwd=SERVICE, env=env, stdin=subprocess.DEVNULL, stdout=output,
        stderr=subprocess.STDOUT,
    ) as process:
        try:
            deadline = time.monotonic() + 20
            while process.poll() is None and time.monotonic() < deadline:
                match = re.search(r"Ready on http://127\.0\.0\.1:(\d+)", log.read_text())
                if match:
                    yield int(match[1])
                    return
                time.sleep(0.05)
            # 此时还没有发送任何联调载荷。
            print(log.read_text(), file=sys.stderr)
            raise ValueError("本地 Wrangler 没有启动")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def exchange(port, path, body=None):
    connection = HTTPConnection(LOOPBACK, port, timeout=8)
    try:
        if body is None:
            connection.request("GET", path)
        else:
            connection.request("POST", path, body, {"Content-Type": "application/json"})
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


@contextmanager
def untrusted_tls_listener(directory):
    certificate = directory / "tls.crt"
    key = directory / "tls.key"
    config = directory / "openssl.cnf"
    config.write_text("[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=san\n"
                      f"[dn]\nCN=localhost\n[san]\nsubjectAltName=IP:{LOOPBACK}\n")
    run(["openssl", "req", "-new", "-x509", "-nodes", "-newkey", "rsa:2048", "-days", "1",
         "-config", str(config), "-keyout", str(key), "-out", str(certificate)],
        cwd=directory, capture=True)
    # 临时以该证书为信任锚核对期限与 IP，不修改系统信任库。
    run(["openssl", "verify", "-CAfile", str(certificate), "-verify_ip", LOOPBACK,
         str(certificate)], cwd=directory, capture=True)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certificate, key)
    handshake = []

    class Probe(BaseRequestHandler):
        def handle(self):
            self.request.settimeout(5)
            try:
                with context.wrap_socket(self.request, server_side=True):
                    handshake.append("客户端接受了证书")
            except ssl.SSLError as error:
                handshake.append(error.reason)

    with TCPServer((LOOPBACK, 0), Probe) as server:
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield server.server_address[1]
        finally:
            server.shutdown()
            thread.join()
    require(len(handshake) == 1 and handshake[0] in {
        "TLSV1_ALERT_UNKNOWN_CA", "SSLV3_ALERT_CERTIFICATE_UNKNOWN",
    },
            f"本地 TLS 未观察到唯一一次不受信任证书拒绝：{handshake}")
    print("本地 TLS 握手拒绝不受信任证书，未发送 HTTP 载荷")


def relay(port, query, secret):
    sent = {UPLOAD: 0, ERASE: 0, BOOTSTRAP: 0}
    errors = []
    inflight, erased = Event(), Event()
    first_body = b""

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def reply(self, status, body=b""):
            self.send_response(status)
            if body:
                self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if body:
                self.wfile.write(body)

        def do_GET(self):
            if self.path == "/inflight":
                self.reply(204 if inflight.wait(8) else 500)
                return
            try:
                target = urlsplit(self.path)
                require(target.path == BOOTSTRAP, "Core 访问了非预期 GET 路径")
                sent[BOOTSTRAP] += 1
                params = parse_qsl(target.query, strict_parsing=True)
                require(len(params) == 4 and dict(params) == {
                    "schema": "1", "platform": "macos", "channel": "github",
                    "version": "2.1.0-rc.1+15",
                }, "启动配置请求没有严格使用约定的四个参数")
                require(set(name.lower() for name in self.headers) <= {
                    "host", "accept", "accept-encoding", "user-agent", "content-length",
                } and self.headers.get("Content-Length", "0") == "0",
                        "启动配置请求带有协议外请求头或正文")
                status, response = exchange(port, self.path)
                require(status == 200, "本地 Worker 没有返回成功的启动配置")
                self.reply(status, response)
            except ValueError as error:
                errors.append(str(error))
                self.reply(500)
            except Exception:
                errors.append("联调中继启动配置转发失败")
                self.reply(500)

        def do_POST(self):
            nonlocal first_body
            try:
                require(self.path in {UPLOAD, ERASE}, "Core 访问了非预期 POST 路径")
                require(self.headers.get("Content-Type") == "application/json",
                        "Core 未发送 JSON 内容类型")
                require("Cookie" not in self.headers and "Authorization" not in self.headers,
                        "Core 发出了 Cookie 或认证头")
                body = self.rfile.read(int(self.headers["Content-Length"]))
                sent[self.path] += 1
                attempt = sent[self.path]
                if self.path == UPLOAD:
                    minutes = [item for day in json.loads(body)["days"]
                               for item in day.get("minutes", [])]
                    require(all((item["event"], item["feature"], item["result"]) ==
                                ("feature_loaded", "schedule", "success") for item in minutes)
                            and sum(item["count"] for item in minutes) == (1 if attempt == 3 else 2),
                            "Rust 上报的功能加载分钟计数不符")
                if self.path == UPLOAD and attempt == 1:
                    first_body = body
                if self.path == UPLOAD and attempt == 2:
                    require(body == first_body, "重试修改了冻结的 Rust 正文")
                if self.path == UPLOAD and attempt == 3:
                    inflight.set()
                    require(erased.wait(8), "旧批次等待删除提交超时")
                if self.path == ERASE:
                    original = json.loads(first_body)
                    require(json.loads(body) == {"schema": 1, "install_id": original["install_id"]},
                            "Rust 删除正文与先前上报的安装 ID 不符")

                status, response = exchange(port, self.path, body)
                if self.path == UPLOAD and attempt == 3:
                    require(status == 410 and json.loads(response) == "install_erased",
                            "Worker 没有按合同拒收晚到批次")
                    require(query() == ERASED_WITH_MINUTES, "晚到批次改变了删除后的 D1 数据")
                else:
                    require(status == 204 and not response,
                            f"本地 Worker 返回了 {status}，预期为空的 204")

                if self.path == UPLOAD and attempt < 3:
                    user = json.loads(body)["days"][0]["users"][0]
                    expected = hmac.new(secret.encode(), user["key"].encode(), hashlib.sha256)
                    row = query()
                    stored = row.pop("user_key")
                    require(isinstance(stored, str) and hmac.compare_digest(stored, expected.hexdigest()),
                            "D1 没有保存经过 HMAC 转换的 Rust 用户标识")
                    require(row == dict(batches=1, tombstones=0, active=1,
                                        counters=2, errors=1, timings=1, minutes=2),
                            "D1 明细或分钟计数与 Rust 批次不符，或重复累加")
                if self.path == ERASE and attempt == 1:
                    require(query() == ERASED_WITH_MINUTES, "删除未清除明细或改变了匿名分钟计数")
                    erased.set()
                # 确认 Worker 已完成提交，只断开客户端一侧的连接。
                if attempt == 1:
                    self.close_connection = True
                    return
                self.reply(status, response)
            except ValueError as error:
                errors.append(str(error))
                self.reply(500)
            except Exception:
                errors.append("联调中继或本地 D1 查询失败")
                self.reply(500)

    return ThreadingHTTPServer((LOOPBACK, 0), Handler), sent, errors


def seed_bootstrap(directory, env_file, env):
    values = {
        "channels": {"github": {
            "latest_version": "2.2.0+17",
            "min_supported_version": "2.1.0",
            "url": "https://example.invalid/download",
            "release_notes": "本地联调的更新说明",
        }},
        "announcements": [{
            "id": "2026-11-11-001",
            "level": "popup",
            "title": "本地联调公告",
            "body": "合成公告正文",
            "starts_at": "2020-01-01T00:00:00+08:00",
            "app": True,
            "platforms": ["macos", "linux", "windows"],
            "channels": ["github"],
        }],
    }
    for key, value in values.items():
        path = directory / f"{key}.json"
        path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
        run([str(WRANGLER), "kv", "key", "put", key, "--path", str(path),
             "--binding", "APP_CONFIG", "--local", "--persist-to", str(directory / "d1"),
             *env_file], cwd=SERVICE, env=env)


def prepare():
    require(not os.environ.get("CI"), "本地应用服务联调不在 CI 运行")
    require(os.environ.get("UBAA_TELEMETRY") != "0", "遥测已硬关闭，不能联调")
    locked = read_values(ROOT / "scripts/tools/versions.env")["NODE_VERSION"]
    node = run(["node", "--version"], cwd=ROOT, capture=True).stdout.strip()
    require(node.startswith(f"v{locked}."), f"请切换到仓库锁定的 Node {locked}")
    require(WRANGLER.is_file(), "缺少本地 Wrangler，请先运行 just app-service-check")
    run(["node", "scripts/compile-schema.mjs"], cwd=SERVICE)


@contextmanager
def local_worker(name):
    parent = Path(os.environ.get("UBAA_APP_SERVICE_E2E_DIR", ROOT / ".ubaa_local/app_service"))
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f"{name}_e2e_", dir=parent) as temporary:
        directory = Path(temporary)
        secret = secrets.token_hex(32)
        vars_file = directory / ".env"
        vars_file.write_text(f"USER_KEY_SECRET={secret}\n")
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("CLOUDFLARE_", "CF_", "WRANGLER_"))
               and key != "USER_KEY_SECRET"}
        env.update(WRANGLER_LOG_PATH=str(directory / "wrangler_logs"),
                   WRANGLER_HIDE_BANNER="true", WRANGLER_SEND_METRICS="false",
                   WRANGLER_SEND_ERROR_REPORTS="false", CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV="true")
        # 开发服务和查询只使用隔离目录中的本地 KV、D1 和合成配置。
        env_file = ["--config", str(SERVICE / "wrangler.json"), "--env-file", str(vars_file)]
        database = ["DB", "--local", "--persist-to", str(directory / "d1")]
        run([str(WRANGLER), "d1", "migrations", "apply", *database, *env_file], cwd=SERVICE, env=env)
        seed_bootstrap(directory, env_file, env)

        def query():
            result = run([str(WRANGLER), "d1", "execute", *database, "--json", "--command", QUERY,
                          *env_file],
                         cwd=SERVICE, env=env, capture=True)
            return json.loads(result.stdout)[0]["results"][0]

        require(query() == EMPTY, "联调开始前隔离 D1 已有数据")
        with worker(env_file, env, directory) as port:
            yield directory, port, query, secret


def main():
    with local_worker("http") as (directory, port, query, secret):
        core = directory / "core"
        core.mkdir()
        with untrusted_tls_listener(directory) as tls_port:
            server, sent, errors = relay(port, query, secret)
            thread = Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                command = ["cargo", "test", "--locked", "-p", "ubaa-core", "--features",
                           "test-contract", "--test", "app_service_http", "--", "--ignored", "--exact"]
                env = dict(os.environ, UBAA_APP_SERVICE_TEST_PORT=str(server.server_port),
                           UBAA_APP_SERVICE_TEST_TLS_PORT=str(tls_port),
                           UBAA_APP_SERVICE_TEST_STATE=str(core))
                run([*command, "bootstrap_and_gate_over_http"], cwd=ROOT, env=env, timeout=1200)
                require(sent == {UPLOAD: 0, ERASE: 0, BOOTSTRAP: 1} and query() == EMPTY,
                        "更新门控或公告已读期间发生了额外请求或 D1 写入")
                run([*command, "upload_retry_and_erase_over_http"], cwd=ROOT, env=env)
            finally:
                server.shutdown()
                server.server_close()
                thread.join()
                if errors:
                    raise ValueError("；".join(errors))
            require(sent == {UPLOAD: 3, ERASE: 2, BOOTSTRAP: 1},
                    "实际 HTTP 请求数与重试、GUI 刷新及命令模式约定不符")
            require(query() == ERASED_WITH_MINUTES,
                    "删除后明细、匿名分钟计数或去重记录不符")
    print("本地 HTTP 与 D1 联调通过：重发未重复计数，删除保留匿名分钟计数，晚到批次返回 410")
    print("本地 HTTP 与 KV 联调通过：启动配置仅发送四个参数，命令模式共享门控且未请求启动配置")


if __name__ == "__main__":
    try:
        prepare()
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from None
