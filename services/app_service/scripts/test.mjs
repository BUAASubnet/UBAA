import { spawnSync } from "node:child_process";
import { closeSync, existsSync, openSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { createServer } from "node:net";
import { createTestTempDirectory } from "../../../scripts/tests/test_tmp.cjs";
const candidates = [
  "/opt/homebrew/opt/postgresql@17/bin",
  "/usr/lib/postgresql/17/bin",
  "/usr/lib/postgresql/16/bin",
  "/usr/lib/postgresql/18/bin",
];
const bin = candidates.find((path) => existsSync(join(path, "initdb")));
if (!bin) throw new Error("请安装 PostgreSQL 17（测试也支持 16 或 18）");
const probe = createServer();
await new Promise((done) => probe.listen(0, "127.0.0.1", done));
const port = probe.address().port;
await new Promise((done) => probe.close(done));
const dir = createTestTempDirectory("postgres");
const logPath = join(dir, "postgres.log");
let log;
function run(name, args) {
  const result = spawnSync(join(bin, name), args, {
    stdio: ["ignore", log, log],
  });
  if (result.status !== 0)
    throw new Error(
      `PostgreSQL ${name} 失败：\n${readFileSync(logPath, "utf8")}`,
    );
}
let started = false;
try {
  log = openSync(logPath, "a", 0o600);
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
    logPath,
    "-o",
    `-h 127.0.0.1 -p ${port} -k ''`,
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
  try {
    if (started)
      run("pg_ctl", ["-D", join(dir, "data"), "-m", "fast", "-w", "stop"]);
  } finally {
    if (log !== undefined) closeSync(log);
    rmSync(dir, { recursive: true, force: true });
  }
}
