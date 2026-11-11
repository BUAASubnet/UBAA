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
  accountId: ["UBAA_APP_SERVICE_ACCOUNT_ID", cloudId],
  zoneId: ["UBAA_APP_SERVICE_ZONE_ID", cloudId],
  workerName: [
    "UBAA_APP_SERVICE_WORKER_NAME",
    /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/,
  ],
  databaseId: ["UBAA_APP_SERVICE_D1_ID", databaseId],
  kvNamespaceId: ["UBAA_APP_SERVICE_KV_NAMESPACE_ID", cloudId],
  domain: ["UBAA_APP_SERVICE_DOMAIN", domainName],
};

function readTarget(env) {
  return Object.fromEntries(
    Object.entries(targetFields).map(([key, [variable, format]]) => {
      const value = env[variable]?.trim();
      if (!value || !format.test(value) || /^0+(?:-0+)*$/.test(value)) {
        throw new Error(`发布目标缺少有效的 ${variable}`);
      }
      return [key, key === "domain" ? value.toLowerCase() : value];
    }),
  );
}

function makeConfig(target) {
  const base = JSON.parse(readFileSync(baseConfig, "utf8"));
  const db = base.d1_databases.find(({ binding }) => binding === "DB");
  const kv = base.kv_namespaces.find(({ binding }) => binding === "APP_CONFIG");
  // CNAME 和 Worker Route 由维护者管理；部署只发布代码与资源绑定。
  delete base.route;
  delete base.routes;
  return {
    ...base,
    $schema: resolve(service, base.$schema),
    account_id: target.accountId,
    name: target.workerName,
    main: resolve(service, ".generated/build/index.js"),
    d1_databases: [
      {
        ...db,
        database_id: target.databaseId,
        migrations_dir: resolve(service, db.migrations_dir),
      },
    ],
    kv_namespaces: [{ ...kv, id: target.kvNamespaceId }],
  };
}

function cleanEnvironment(env) {
  return Object.fromEntries(
    Object.entries(env).filter(
      ([key]) =>
        !/^(?:CLOUDFLARE_|CF_|WRANGLER_|WORKERS_CI_|USER_KEY_SECRET$|UBAA_(?:TEST_)?(?:USERNAME|PASSWORD)$)/i.test(
          key,
        ),
    ),
  );
}

function run(command, args, { env, label, remote = false }) {
  const result = spawnSync(command, args, {
    cwd: service,
    env,
    // 远端 CLI 的输出可能包含请求或响应正文；只在内存中解析需要的结果。
    stdio: remote ? ["ignore", "pipe", "pipe"] : "inherit",
    encoding: "utf8",
  });
  if (result.error) {
    throw new Error(`${label}无法完成（${result.error.code ?? "子进程错误"}）`);
  }
  if (result.status !== 0) {
    throw new Error(`${label}失败（${result.status ?? result.signal}）`);
  }
  return result.stdout;
}

function checkSecret(wrangler) {
  const output = wrangler(
    ["secret", "list", "--format", "json"],
    "读取 Worker Secret 名称",
  );
  let names;
  try {
    names = JSON.parse(output);
  } catch {
    throw new Error("无法解析 Worker Secret 名称；请核对目标 Worker 的配置");
  }
  if (
    !Array.isArray(names) ||
    !names.some(
      (binding) =>
        binding?.name === "USER_KEY_SECRET" && binding.type === "secret_text",
    )
  ) {
    throw new Error("目标 Worker 缺少 USER_KEY_SECRET，请先按部署手册配置");
  }
}

function cloudClient({ accountId, zoneId }, token, fetchResponse) {
  return async (path, label, { method = "GET", data, zone = false } = {}) => {
    const url = new URL(
      `/client/v4/${zone ? `zones/${zoneId}` : `accounts/${accountId}`}${path}`,
      "https://api.cloudflare.com",
    );
    const headers = { Authorization: `Bearer ${token}` };
    if (data !== undefined) headers["Content-Type"] = "application/json";
    let response;
    try {
      response = await fetchResponse(url, {
        method,
        headers,
        body: data === undefined ? undefined : JSON.stringify(data),
        redirect: "error",
        signal: AbortSignal.timeout(30_000),
      });
    } catch {
      throw new Error(`${label}失败：无法连接 Cloudflare API`);
    }
    if (!response.ok) {
      throw new Error(`${label}失败：Cloudflare API 返回 HTTP ${response.status}`);
    }
    const payload = await response.json().catch(() => null);
    if (payload?.success !== true) {
      throw new Error(`${label}失败：Cloudflare API 未返回成功结果`);
    }
    return payload.result;
  };
}

async function checkRoute(cloud, target) {
  const routes = await cloud("/workers/routes", "读取 Worker Route", { zone: true });
  if (!Array.isArray(routes)) throw new Error("无法解析 Worker Route");
  const pattern = `${target.domain}/*`;
  const matches = routes.filter((route) => route?.pattern?.toLowerCase() === pattern);
  if (matches.length !== 1 || matches[0].script !== target.workerName) {
    throw new Error("Worker Route 未绑定到目标服务，请检查域名路由与 Worker 名称");
  }
}

async function publishContent(cloud, target, { channels, announcements }) {
  const namespace = `/storage/kv/namespaces/${target.kvNamespaceId}/bulk`;
  const entries = [
    { key: "channels", value: JSON.stringify(channels) },
    {
      key: "announcements",
      value: JSON.stringify(announcements.filter(({ app }) => app === true)),
    },
  ];
  const current = await cloud(`${namespace}/get`, "读取目标 KV 内容", {
    method: "POST",
    data: { keys: entries.map(({ key }) => key), type: "text" },
  });
  if (!current?.values || typeof current.values !== "object" || Array.isArray(current.values)) {
    throw new Error("无法解析目标 KV 内容");
  }
  const changed = entries.filter(({ key, value }) => current.values[key] !== value);
  if (changed.length === 0) {
    console.log("目标 KV 内容一致，跳过写入");
    return;
  }
  const result = await cloud(namespace, "发布 KV 内容", {
    method: "PUT",
    data: changed,
  });
  if (result?.unsuccessful_keys?.length || (
    result?.successful_key_count !== undefined &&
    result.successful_key_count !== changed.length
  )) {
    throw new Error("部分 KV 内容未写入，请重新运行发布以同步剩余内容");
  }
  console.log(`已同步 ${changed.length} 个 KV 键`);
}

export async function runRelease(
  operation,
  {
    contentPaths,
    env = process.env,
    tempParent = join(root, ".ubaa_local/app_service"),
    wranglerPath = join(service, "node_modules/wrangler/bin/wrangler.js"),
    checkCommand = ["npm", "run", "check"],
    fetchResponse = fetch,
  } = {},
) {
  if (!["publish", "deploy"].includes(operation)) {
    throw new Error("命令须为 publish 或 deploy");
  }
  const content = loadContent(contentPaths);
  const target = readTarget(env);
  const token = env.CLOUDFLARE_API_TOKEN?.trim();
  if (!token) throw new Error("缺少 CLOUDFLARE_API_TOKEN");
  const cloud = cloudClient(target, token, fetchResponse);
  if (operation === "publish") {
    await publishContent(cloud, target, content);
    return;
  }
  try {
    accessSync(wranglerPath);
  } catch {
    throw new Error(
      "缺少锁定的 Wrangler，请先执行 npm --prefix services/app_service ci",
    );
  }
  const localEnv = cleanEnvironment(env);
  const [command, ...args] = checkCommand;
  run(command, args, { env: localEnv, label: "本地 Worker 检查" });
  await checkRoute(cloud, target);

  mkdirSync(tempParent, { recursive: true, mode: 0o700 });
  const directory = mkdtempSync(join(tempParent, "release_"));
  try {
    const configPath = join(directory, "wrangler.json");
    const emptyEnv = join(directory, "empty.env");
    writeFileSync(configPath, JSON.stringify(makeConfig(target)), { mode: 0o600 });
    writeFileSync(emptyEnv, "", { mode: 0o600 });
    const cloudEnv = {
      ...localEnv,
      CLOUDFLARE_ACCOUNT_ID: target.accountId,
      CLOUDFLARE_API_TOKEN: token,
      WRANGLER_WRITE_LOGS: "false",
    };
    const wrangler = (args, label) =>
      run(
        process.execPath,
        [wranglerPath, ...args, "--config", configPath, "--env-file", emptyEnv],
        { env: cloudEnv, label, remote: true },
      );
    checkSecret(wrangler);
    const migrations = wrangler(
      ["d1", "migrations", "apply", "DB", "--remote"],
      "应用 D1 迁移",
    );
    // Wrangler 4.160.0 对没有错误说明的失败结果只标记 ❌，仍可能返回零。
    if (migrations.includes("❌")) {
      throw new Error("D1 迁移失败");
    }
    console.log("D1 迁移检查完成");
    wrangler(
      [
        "deploy",
        "--no-bundle",
        "--autoconfig=false",
        "--experimental-auto-create=false",
      ],
      "部署 Worker",
    );
    console.log(`已部署 Worker ${target.workerName}`);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

if (
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url
) {
  const [, , operation, ...args] = process.argv;
  if (args.length !== 0 || !["publish", "deploy"].includes(operation)) {
    console.error("用法：node scripts/release/app_service/release.mjs deploy|publish");
    process.exitCode = 1;
  } else {
    const result = spawnSync(
      "python3",
      [join(root, "scripts/lib/toolchain.py"), "release", operation],
      { cwd: root, stdio: "inherit" },
    );
    if (result.error) console.error("无法启动项目配置加载器");
    process.exitCode = result.status ?? 1;
  }
}
