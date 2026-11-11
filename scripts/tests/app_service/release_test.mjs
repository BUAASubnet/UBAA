import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  appendFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { test } from "node:test";
import { runRelease } from "../../release/app_service/release.mjs";

const target = {
  UBAA_APP_SERVICE_ACCOUNT_ID: "1".repeat(32),
  UBAA_APP_SERVICE_ZONE_ID: "3".repeat(32),
  UBAA_APP_SERVICE_WORKER_NAME: "fixture-app-service",
  UBAA_APP_SERVICE_D1_ID: "12345678-1234-1234-1234-123456789abc",
  UBAA_APP_SERVICE_KV_NAMESPACE_ID: "2".repeat(32),
  UBAA_APP_SERVICE_DOMAIN: "app-service.example.invalid",
};
const channels = { github: null, app_store: null, app_gallery: null };
const route = {
  pattern: `${target.UBAA_APP_SERVICE_DOMAIN}/*`,
  script: target.UBAA_APP_SERVICE_WORKER_NAME,
};

const fakeCli = `
import { appendFileSync, readFileSync } from "node:fs";
const args = process.argv.slice(2);
const command = args.slice(0, 3).join(" ").split(" --")[0];
const config = args.includes("--config")
  ? JSON.parse(readFileSync(args[args.indexOf("--config") + 1], "utf8"))
  : undefined;
const stdin = command === "d1 migrations apply" && process.env.FAKE_READ_STDIN
  ? readFileSync(0, "utf8")
  : undefined;
appendFileSync(process.env.FAKE_LOG, JSON.stringify({
  args, command, config, stdin,
  authenticated: Boolean(process.env.CLOUDFLARE_API_TOKEN),
  hasLegacyCredential: Boolean(process.env.CF_API_KEY),
  hasSchoolCredential: ["UBAA_USERNAME", "UBAA_TEST_PASSWORD"].some(
    (key) => Object.hasOwn(process.env, key),
  ),
  account: process.env.CLOUDFLARE_ACCOUNT_ID,
  logs: process.env.WRANGLER_WRITE_LOGS,
}) + "\\n");
if (command === "secret list") {
  console.log(JSON.stringify(process.env.FAKE_NO_SECRET
    ? [] : [{ name: "USER_KEY_SECRET", type: process.env.FAKE_SECRET_TYPE || "secret_text" }]));
}
if (command === "d1 migrations apply" && process.env.FAKE_MIGRATION_ERROR) {
  console.log("0001_init.sql ❌");
}
if (process.env.FAKE_WRITE_REMOTE_OUTPUT && command !== "check") {
  console.error("合成远端错误正文：正文和认证信息不能进入部署日志");
  if (command !== "secret list") console.log("合成请求正文");
}
if (command === process.env.FAKE_FAIL) process.exit(7);
`;

function fixture(t) {
  const parent = resolve(".ubaa_local/app_service");
  mkdirSync(parent, { recursive: true, mode: 0o700 });
  const path = mkdtempSync(join(parent, "release_test_"));
  t.after(() => rmSync(path, { recursive: true, force: true }));
  const channelsPath = join(path, "channels.json");
  const announcementsDir = join(path, "announcements");
  const log = join(path, "cli.log");
  const script = join(path, "fake.mjs");
  writeFileSync(channelsPath, JSON.stringify(channels));
  writeFileSync(log, "");
  writeFileSync(script, fakeCli);
  mkdirSync(announcementsDir);
  writeFileSync(join(announcementsDir, "index.md"), "# 导航页\n");
  for (const [number, app] of [
    [1, true],
    [2, false],
  ]) {
    writeFileSync(
      join(announcementsDir, `2026-11-01-00${number}.md`),
      `---\ntitle: 测试公告\nlevel: banner\napp: ${app}\nstarts_at: 2026-11-01T03:00:00+08:00\n---\n\n测试正文。\n`,
    );
  }
  const env = {
    ...process.env,
    ...target,
    FAKE_LOG: log,
    CLOUDFLARE_API_TOKEN: "fixture-api-value",
    CLOUDFLARE_ACCOUNT_ID: "inherited-account-must-be-replaced",
    CF_API_KEY: "fixture-legacy-value",
    UBAA_USERNAME: "fixture-school-name",
    UBAA_TEST_PASSWORD: "fixture-school-password",
    CI: "true",
  };
  const options = {
    contentPaths: { channelsPath, announcementsDir },
    tempParent: path,
    wranglerPath: script,
    checkCommand: [process.execPath, script, "check"],
  };
  const remote = { routes: [route], values: {}, putResult: {} };
  const fetchResponse = async (url, request) => {
    const account = `/client/v4/accounts/${target.UBAA_APP_SERVICE_ACCOUNT_ID}`;
    assert.equal(url.origin, "https://api.cloudflare.com");
    assert.equal(
      request.headers.Authorization,
      `Bearer ${env.CLOUDFLARE_API_TOKEN}`,
    );
    assert.equal(request.redirect, "error");
    if (url.pathname === `/client/v4/zones/${target.UBAA_APP_SERVICE_ZONE_ID}/workers/routes`) {
      assert.equal(request.method ?? "GET", "GET");
      assert.deepEqual(
        [...url.searchParams],
        [],
      );
      appendFileSync(log, JSON.stringify({ command: "routes get" }) + "\n");
      return Response.json({ success: true, result: remote.routes });
    }
    const namespace = `${account}/storage/kv/namespaces/${target.UBAA_APP_SERVICE_KV_NAMESPACE_ID}/bulk`;
    const body = JSON.parse(request.body);
    assert.equal(request.headers["Content-Type"], "application/json");
    if (url.pathname === `${namespace}/get`) {
      assert.equal(request.method, "POST");
      assert.deepEqual(body, {
        keys: ["channels", "announcements"],
        type: "text",
      });
      appendFileSync(log, JSON.stringify({ command: "kv bulk get" }) + "\n");
      return Response.json({ success: true, result: { values: remote.values } });
    }
    assert.equal(url.pathname, namespace);
    assert.equal(request.method, "PUT");
    appendFileSync(log, JSON.stringify({ command: "kv bulk put", entries: body }) + "\n");
    return Response.json({ success: true, result: remote.putResult });
  };
  return {
    channelsPath,
    env,
    options,
    remote,
    run(operation, overrides = {}) {
      return runRelease(operation, { ...options, env, fetchResponse, ...overrides });
    },
    calls() {
      return readFileSync(log, "utf8")
        .trim()
        .split("\n")
        .filter(Boolean)
        .map(JSON.parse);
    },
    commands(from = 0) {
      return this.calls().slice(from).map(({ command }) => command);
    },
  };
}

for (const operation of ["publish", "deploy"]) {
  test(`${operation}：内容非法、目标缺失或凭据缺失都不会调用 CLI`, async (t) => {
    const f = fixture(t);
    await assert.rejects(
      async () => f.run(operation, { env: { ...f.env, UBAA_APP_SERVICE_D1_ID: "" } }),
      /UBAA_APP_SERVICE_D1_ID/,
    );
    await assert.rejects(
      async () => f.run(operation, { env: { ...f.env, CLOUDFLARE_API_TOKEN: " " } }),
      /CLOUDFLARE_API_TOKEN/,
    );
    writeFileSync(f.channelsPath, "{");
    await assert.rejects(async () => f.run(operation), /channels\.json/);
    assert.deepEqual(f.calls(), []);
  });
}

test("发布比较目标 KV，并只批量写入通过验证且不同的渠道与 App 公告", async (t) => {
  const f = fixture(t);
  await f.run("publish");
  const [, put] = f.calls();
  assert.deepEqual(f.commands(), ["kv bulk get", "kv bulk put"]);
  const values = Object.fromEntries(
    put.entries.map(({ key, value }) => [key, JSON.parse(value)]),
  );
  assert.deepEqual(values.channels, channels);
  assert.deepEqual(
    values.announcements.map(({ id, body }) => [id, body]),
    [["2026-11-01-001", "测试正文。"]],
  );

  f.remote.values = Object.fromEntries(put.entries.map(({ key, value }) => [key, value]));
  await f.run("publish");
  assert.deepEqual(f.commands(2), ["kv bulk get"]);

  f.remote.values.announcements = "[]";
  await f.run("publish");
  assert.deepEqual(f.commands(3), ["kv bulk get", "kv bulk put"]);
  assert.deepEqual(f.calls().at(-1).entries, [put.entries[1]]);
});

test("读取远端 KV 失败时不写入", async (t) => {
  const f = fixture(t);
  await assert.rejects(
    async () => f.run("publish", {
      fetchResponse: async () => Response.json({ success: false }, { status: 403 }),
    }),
    /读取目标 KV 内容.*403/,
  );
  assert.deepEqual(f.calls(), []);
});

test("KV 批量请求报告部分成功时返回失败", async (t) => {
  const f = fixture(t);
  f.remote.putResult = { successful_key_count: 1, unsuccessful_keys: ["announcements"] };
  await assert.rejects(async () => f.run("publish"), /部分 KV 内容未写入/);
  assert.deepEqual(f.commands(), ["kv bulk get", "kv bulk put"]);
});

test("非交互部署先离线检查与核对域名和 Secret，再迁移 D1，最后部署 Worker", async (t) => {
  const f = fixture(t);
  await f.run("deploy");
  const [check, , secrets, migrate, deploy] = f.calls();
  assert.deepEqual(
    f.commands(),
    ["check", "routes get", "secret list", "d1 migrations apply", "deploy"],
  );
  assert.equal(check.authenticated, false);
  assert.equal(check.hasLegacyCredential, false);
  assert.equal(check.hasSchoolCredential, false);
  assert.equal(check.account, undefined);
  assert.equal(secrets.authenticated, true);
  assert.equal(secrets.hasLegacyCredential, false);
  assert.equal(secrets.hasSchoolCredential, false);
  assert.equal(secrets.account, target.UBAA_APP_SERVICE_ACCOUNT_ID);
  assert.equal(secrets.logs, "false");
  assert(migrate.args.includes("DB"));
  assert(migrate.args.includes("--remote"));
  assert(deploy.args.includes("--no-bundle"));
  assert(deploy.args.includes("--experimental-auto-create=false"));
  assert.equal(
    deploy.config.main,
    resolve("services/app_service/.generated/build/index.js"),
  );
  assert.equal(deploy.config.name, target.UBAA_APP_SERVICE_WORKER_NAME);
  assert.equal(deploy.config.d1_databases[0].database_id, target.UBAA_APP_SERVICE_D1_ID);
  assert.equal(deploy.config.kv_namespaces[0].id, target.UBAA_APP_SERVICE_KV_NAMESPACE_ID);
  assert.equal(deploy.config.route, undefined);
  assert.equal(deploy.config.routes, undefined);
  assert.deepEqual(deploy.config.triggers.crons, ["0 19 * * *"]);
  assert.equal(deploy.config.workers_dev, false);
  assert.equal(deploy.config.preview_urls, false);
});

test("路由缺失、指向其他 Worker 或被停用时不迁移或部署", async (t) => {
  const f = fixture(t);
  for (const routes of [
    [{ ...route, script: "other-worker" }],
    [],
    [{ ...route, pattern: "other.example.invalid/*" }],
    [{ ...route, script: null }],
  ]) {
    f.remote.routes = routes;
    const from = f.calls().length;
    await assert.rejects(async () => f.run("deploy"), /Worker Route/);
    assert.deepEqual(f.commands(from), ["check", "routes get"]);
  }
});

test("本地构建或 Secret 检查失败时不迁移；迁移失败时不部署", async (t) => {
  const f = fixture(t);
  await assert.rejects(
    async () => f.run("deploy", { env: { ...f.env, FAKE_FAIL: "check" } }),
    /检查/,
  );
  assert.deepEqual(f.commands(), ["check"]);

  for (const secretEnv of [{ FAKE_NO_SECRET: "1" }, { FAKE_SECRET_TYPE: "plain_text" }]) {
    const from = f.calls().length;
    await assert.rejects(
      async () => f.run("deploy", { env: { ...f.env, ...secretEnv } }),
      /USER_KEY_SECRET/,
    );
    assert.deepEqual(f.commands(from), ["check", "routes get", "secret list"]);
  }

  for (const failure of [{ FAKE_FAIL: "d1 migrations apply" }, { FAKE_MIGRATION_ERROR: "1" }]) {
    const from = f.calls().length;
    await assert.rejects(
      async () => f.run("deploy", { env: { ...f.env, ...failure } }),
      /迁移/,
    );
    assert.deepEqual(f.commands(from), ["check", "routes get", "secret list", "d1 migrations apply"]);
  }
});

test("远端 CLI 不继承 stdin，部署日志不转发远端响应或请求正文", (t) => {
  const f = fixture(t);
  const release = new URL("../../release/app_service/release.mjs", import.meta.url);
  const command = `
    import { runRelease } from ${JSON.stringify(release.href)};
    await runRelease("deploy", {
      ...${JSON.stringify(f.options)},
      fetchResponse: async () => Response.json({ success: true, result: ${JSON.stringify([route])} }),
    });
  `;
  const child = spawnSync(
    process.execPath,
    ["--input-type=module", "-e", command],
    {
      env: { ...f.env, FAKE_READ_STDIN: "1", FAKE_WRITE_REMOTE_OUTPUT: "1" },
      input: "n\n",
      encoding: "utf8",
    },
  );
  assert.equal(child.status, 0, child.stderr);
  assert.equal(
    f.calls().find(({ command }) => command === "d1 migrations apply").stdin,
    "",
  );
  assert.doesNotMatch(child.stdout + child.stderr, /USER_KEY_SECRET|合成远端错误正文|合成请求正文|fixture-api-value/);
});
