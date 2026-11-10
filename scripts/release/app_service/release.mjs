import { spawnSync } from "node:child_process";
import {
  accessSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { loadContent } from "../../check/app_service/content.mjs";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const service = join(root, "services/app_service");
const baseConfig = join(service, "wrangler.json");
const cloudId = /^[a-f\d]{32}$/i;
const databaseId = /^[a-f\d]{8}-(?:[a-f\d]{4}-){3}[a-f\d]{12}$/i;
const hostnameLabel = "[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?";
const domainName = new RegExp(
  `^(?:${hostnameLabel}\\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$`,
  "i",
);
const targetFields = {
  account_id: cloudId,
  worker_name: /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/,
  database_id: databaseId,
  kv_namespace_id: cloudId,
  domain: domainName,
};

function readTarget(targetPath) {
  if (!targetPath?.trim())
    throw new Error("必须通过 --target 指定发布目标 JSON 文件");
  let target;
  try {
    target = JSON.parse(readFileSync(targetPath, "utf8"));
  } catch {
    throw new Error(`无法读取发布目标 JSON：${targetPath}`);
  }
  if (
    !target ||
    typeof target !== "object" ||
    Array.isArray(target) ||
    Object.keys(target).some((key) => !Object.hasOwn(targetFields, key))
  ) {
    throw new Error(
      "发布目标 JSON 仅接受 account_id、worker_name、database_id、kv_namespace_id、domain",
    );
  }
  for (const [key, format] of Object.entries(targetFields)) {
    if (
      typeof target[key] !== "string" ||
      !format.test(target[key]) ||
      /^0+(?:-0+)*$/.test(target[key])
    ) {
      throw new Error(`发布目标缺少有效的 ${key}`);
    }
  }
  return target;
}

function makeConfig(target, operation) {
  const base = JSON.parse(readFileSync(baseConfig, "utf8"));
  const db = base.d1_databases.find(({ binding }) => binding === "DB");
  const kv = base.kv_namespaces.find(({ binding }) => binding === "APP_CONFIG");
  return {
    ...base,
    $schema: resolve(service, base.$schema),
    account_id: target.account_id,
    name: target.worker_name,
    main: resolve(
      service,
      operation === "deploy" ? ".generated/build/index.js" : base.main,
    ),
    d1_databases: [
      {
        ...db,
        database_id: target.database_id,
        migrations_dir: resolve(service, db.migrations_dir),
      },
    ],
    kv_namespaces: [{ ...kv, id: target.kv_namespace_id }],
    routes: [{ pattern: target.domain, custom_domain: true }],
  };
}

function cleanEnvironment(env) {
  return Object.fromEntries(
    Object.entries(env).filter(
      ([key]) =>
        !/^(?:CLOUDFLARE_|CF_|WRANGLER_|WORKERS_CI_|USER_KEY_SECRET$)/i.test(
          key,
        ),
    ),
  );
}

function run(
  command,
  args,
  { env, label, capture = false, stdin = "inherit" },
) {
  const result = spawnSync(command, args, {
    cwd: service,
    env,
    stdio: [stdin, capture ? "pipe" : "inherit", "inherit"],
    encoding: "utf8",
  });
  if (result.error)
    throw new Error(`${label}无法启动：${result.error.message}`);
  if (result.status !== 0)
    throw new Error(`${label}失败（${result.status ?? result.signal}）`);
  return result.stdout;
}

function checkSecret(wrangler) {
  const output = wrangler(
    ["secret", "list", "--format", "json"],
    "读取 Worker Secret 名称",
    { capture: true },
  );
  let names;
  try {
    names = JSON.parse(output);
  } catch {
    throw new Error("无法解析 Worker Secret 名称；请核对目标 Worker 的配置");
  }
  if (
    !Array.isArray(names) ||
    !names.some(({ name }) => name === "USER_KEY_SECRET")
  ) {
    throw new Error("目标 Worker 缺少 USER_KEY_SECRET，请先按部署手册配置");
  }
}

export function runRelease(
  operation,
  {
    targetPath,
    contentPaths,
    env = process.env,
    tempParent = join(root, ".ubaa_local/app_service"),
    wranglerPath = join(service, "node_modules/wrangler/bin/wrangler.js"),
    checkCommand = ["npm", "run", "check"],
    interactive = Boolean(process.stdin.isTTY && process.stdout.isTTY),
  } = {},
) {
  if (!["publish", "deploy"].includes(operation))
    throw new Error("命令须为 publish 或 deploy");
  if (env.CI) throw new Error("CI 不运行应用服务远端发布或部署");
  const { channels, announcements } = loadContent(contentPaths);
  const target = readTarget(targetPath);
  const token = env.CLOUDFLARE_API_TOKEN?.trim();
  if (!token) throw new Error("必须从本机环境提供 CLOUDFLARE_API_TOKEN");
  // Wrangler 在非交互终端会自动覆盖自定义域名的 DNS 或 Worker 冲突。
  if (operation === "deploy" && !interactive)
    throw new Error("部署须在交互终端执行，保留 Wrangler 的域名冲突提示");
  try {
    accessSync(wranglerPath);
  } catch {
    throw new Error(
      "缺少锁定的 Wrangler，请先执行 npm --prefix services/app_service ci",
    );
  }
  const localEnv = cleanEnvironment(env);
  const config = makeConfig(target, operation);
  if (operation === "deploy") {
    const [command, ...args] = checkCommand;
    run(command, args, { env: localEnv, label: "本地 Worker 检查" });
  }

  mkdirSync(tempParent, { recursive: true, mode: 0o700 });
  const directory = mkdtempSync(join(tempParent, "release_"));
  try {
    const configPath = join(directory, "wrangler.json");
    const emptyEnv = join(directory, "empty.env");
    writeFileSync(configPath, JSON.stringify(config), { mode: 0o600 });
    writeFileSync(emptyEnv, "", { mode: 0o600 });
    const cloudEnv = {
      ...localEnv,
      CLOUDFLARE_ACCOUNT_ID: target.account_id,
      CLOUDFLARE_API_TOKEN: token,
    };
    const wrangler = (args, label, { capture, stdin } = {}) =>
      run(
        process.execPath,
        [wranglerPath, ...args, "--config", configPath, "--env-file", emptyEnv],
        { env: cloudEnv, label, capture, stdin },
      );
    console.log(
      `应用服务目标：账号 ${target.account_id}，Worker ${target.worker_name}，域名 ${target.domain}，D1 ${target.database_id}，KV ${target.kv_namespace_id}`,
    );
    if (operation === "publish") {
      const payloadPath = join(directory, "kv.json");
      const entries = [
        { key: "channels", value: JSON.stringify(channels) },
        {
          key: "announcements",
          value: JSON.stringify(
            announcements.filter(({ app }) => app === true),
          ),
        },
      ];
      writeFileSync(payloadPath, JSON.stringify(entries), { mode: 0o600 });
      wrangler(
        [
          "kv",
          "bulk",
          "put",
          payloadPath,
          "--namespace-id",
          target.kv_namespace_id,
          "--remote",
        ],
        "发布 KV 内容",
      );
    } else {
      checkSecret(wrangler);
      wrangler(
        ["d1", "migrations", "apply", "DB", "--remote"],
        "应用 D1 迁移",
        { stdin: "ignore" },
      );
      wrangler(
        [
          "deploy",
          "--no-bundle",
          "--autoconfig=false",
          "--experimental-auto-create=false",
        ],
        "部署 Worker",
      );
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

if (
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url
) {
  try {
    const [, , operation, ...args] = process.argv;
    const { values } = parseArgs({
      args,
      options: { target: { type: "string" } },
    });
    runRelease(operation, { targetPath: values.target });
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
