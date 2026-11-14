import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, openSync, rmSync } from "node:fs";
import { resolve, join } from "node:path";
import { createServer } from "node:net";
const candidates = [
  "/opt/homebrew/opt/postgresql@17/bin",
  "/usr/lib/postgresql/17/bin",
  "/usr/lib/postgresql/16/bin",
  "/usr/lib/postgresql/18/bin",
];
const bin = candidates.find((path) => existsSync(join(path, "initdb")));
if (!bin) throw new Error("请安装 PostgreSQL 17（测试也支持 16 或 18）");
const parent = resolve("../../.ubaa_local/postgres_tests");
mkdirSync(parent, { recursive: true, mode: 0o700 });
const dir = mkdtempSync(join(parent, "run_"));
const probe = createServer();
await new Promise((done) => probe.listen(0, "127.0.0.1", done));
const port = probe.address().port;
await new Promise((done) => probe.close(done));
const log = openSync(join(dir, "postgres.log"), "a", 0o600);
function run(name, args) {
  const result = spawnSync(join(bin, name), args, {
    stdio: ["ignore", log, log],
  });
  if (result.status !== 0)
    throw new Error(`PostgreSQL 测试启动失败，见 ${dir}/postgres.log`);
}
let started = false;
try {
  run("initdb", [
    "-D",
    join(dir, "data"),
    "-A",
    "trust",
    "-U",
    "postgres",
    "--no-locale",
    "-E",
    "UTF8",
  ]);
  run("pg_ctl", [
    "-D",
    join(dir, "data"),
    "-l",
    join(dir, "postgres.log"),
    "-o",
    `-h 127.0.0.1 -p ${port} -k ${dir}`,
    "-w",
    "start",
  ]);
  started = true;
  const result = spawnSync("npx", ["vitest", "run", ...process.argv.slice(2)], {
    stdio: "inherit",
    env: {
      ...process.env,
      TEST_DATABASE_URL: `postgresql://postgres@127.0.0.1:${port}/postgres`,
    },
  });
  process.exitCode = result.status ?? 1;
} finally {
  if (started)
    run("pg_ctl", ["-D", join(dir, "data"), "-m", "fast", "-w", "stop"]);
  if (!process.exitCode) rmSync(dir, { recursive: true, force: true });
}
