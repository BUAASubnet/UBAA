import { spawnSync } from "node:child_process";
import {
  closeSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  rmSync,
} from "node:fs";
import { delimiter, resolve, join } from "node:path";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";

const windows = process.platform === "win32";
const programs = ["initdb", "pg_ctl", "postgres"];
const executable = (name) => (windows ? `${name}.exe` : name);
const versions = ["17", "16", "18"];
const programFiles = [
  process.env.ProgramW6432,
  process.env.ProgramFiles,
  process.env["ProgramFiles(x86)"],
].filter(Boolean);
const candidates = windows
  ? [...new Set(programFiles)].flatMap((root) =>
      versions.map((version) => join(root, "PostgreSQL", version, "bin")),
    )
  : [
      "/opt/homebrew/opt/postgresql@17/bin",
      ...versions.map((version) => `/usr/lib/postgresql/${version}/bin`),
    ];
candidates.push(...(process.env.PATH ?? "").split(delimiter).filter(Boolean));
const bin = candidates.find((path) =>
  programs.every((program) => existsSync(resolve(path, executable(program)))),
);
if (!bin) throw new Error("请安装 PostgreSQL 17（测试也支持 16 或 18）");

const service = fileURLToPath(new URL("../", import.meta.url));
const vitest = fileURLToPath(
  new URL("vitest.mjs", import.meta.resolve("vitest/package.json")),
);
const parent = resolve(service, "../../.ubaa_local/postgres_tests");
mkdirSync(parent, { recursive: true, mode: 0o700 });
const dir = mkdtempSync(join(parent, "run_"));
const probe = createServer();
await new Promise((done) => probe.listen(0, "127.0.0.1", done));
const port = probe.address().port;
await new Promise((done) => probe.close(done));
const data = join(dir, "data");
const serverLog = join(dir, "postgres.log");
// Windows 上 pg_ctl 不能重新打开作为 stdout/stderr 继承的日志文件。
const commandLog = join(dir, "commands.log");
const log = openSync(commandLog, "a", 0o600);
function run(name, args) {
  const result = spawnSync(resolve(bin, executable(name)), args, {
    stdio: ["ignore", log, log],
  });
  if (result.status !== 0)
    throw new Error(
      `PostgreSQL 测试命令 ${name} 失败，见 ${commandLog} 和 ${serverLog}`,
      { cause: result.error },
    );
}
let started = false;
let passed = false;
try {
  run("initdb", [
    "-D",
    data,
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
    data,
    "-l",
    serverLog,
    "-o",
    `-h 127.0.0.1 -p ${port} -c unix_socket_directories=`,
    "-w",
    "start",
  ]);
  started = true;
  const result = spawnSync(
    process.execPath,
    [vitest, "run", ...process.argv.slice(2)],
    {
      cwd: service,
      stdio: "inherit",
      env: {
        ...process.env,
        TEST_DATABASE_URL: `postgresql://postgres@127.0.0.1:${port}/postgres`,
      },
    },
  );
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
  passed = process.exitCode === 0;
} finally {
  try {
    if (started) run("pg_ctl", ["-D", data, "-m", "fast", "-w", "stop"]);
  } finally {
    closeSync(log);
  }
  if (passed) rmSync(dir, { recursive: true, force: true });
}
