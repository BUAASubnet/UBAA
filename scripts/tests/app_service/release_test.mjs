import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
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
  account_id: "1".repeat(32),
  worker_name: "fixture-app-service",
  database_id: "12345678-1234-1234-1234-123456789abc",
  kv_namespace_id: "2".repeat(32),
  domain: "app-service.example.invalid",
};
const channels = { github: null, app_store: null, app_gallery: null };
const fakeCli = `
import { appendFileSync, readFileSync } from "node:fs";
const args = process.argv.slice(2);
const command = args.slice(0, 3).join(" ").split(" --")[0];
const config = args.includes("--config")
  ? JSON.parse(readFileSync(args[args.indexOf("--config") + 1], "utf8"))
  : undefined;
const entries = command === "kv bulk put"
  ? JSON.parse(readFileSync(args[3], "utf8"))
  : undefined;
const stdin = command === "d1 migrations apply" && process.env.FAKE_READ_STDIN
  ? readFileSync(0, "utf8")
  : undefined;
appendFileSync(process.env.FAKE_LOG, JSON.stringify({
  args, command, config, entries, stdin,
  authenticated: Boolean(process.env.CLOUDFLARE_API_TOKEN),
  hasLegacyCredential: Boolean(process.env.CF_API_KEY),
  account: process.env.CLOUDFLARE_ACCOUNT_ID,
}) + "\\n");
if (command === "secret list") {
  console.log(JSON.stringify(process.env.FAKE_NO_SECRET ? [] : [{ name: "USER_KEY_SECRET", type: "secret_text" }]));
}
if (command === process.env.FAKE_FAIL) process.exit(7);
`;

function fixture(t) {
  const parent = resolve(".ubaa_local/app_service");
  mkdirSync(parent, { recursive: true, mode: 0o700 });
  const path = mkdtempSync(join(parent, "release_test_"));
  t.after(() => rmSync(path, { recursive: true, force: true }));
  const targetPath = join(path, "target.json");
  const channelsPath = join(path, "channels.json");
  const announcementsDir = join(path, "announcements");
  const log = join(path, "cli.log");
  const script = join(path, "fake.mjs");
  writeFileSync(targetPath, JSON.stringify(target));
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
    FAKE_LOG: log,
    CLOUDFLARE_API_TOKEN: "fixture-api-value",
    CLOUDFLARE_ACCOUNT_ID: "inherited-account-must-be-replaced",
    CF_API_KEY: "fixture-legacy-value",
    CI: "",
  };
  const options = {
    targetPath,
    contentPaths: { channelsPath, announcementsDir },
    tempParent: path,
    wranglerPath: script,
    checkCommand: [process.execPath, script, "check"],
    interactive: true,
  };
  return {
    targetPath,
    channelsPath,
    env,
    options,
    run(operation, overrides = {}) {
      return runRelease(operation, { ...options, env, ...overrides });
    },
    calls() {
      return readFileSync(log, "utf8")
        .trim()
        .split("\n")
        .filter(Boolean)
        .map(JSON.parse);
    },
  };
}

test("非交互部署在调用 CLI 前停止，避免自动接管冲突域名", (t) => {
  const f = fixture(t);
  assert.throws(() => f.run("deploy", { interactive: false }), /交互终端/);
  assert.deepEqual(f.calls(), []);
});

for (const operation of ["publish", "deploy"]) {
  test(`${operation}：内容非法、目标缺失或凭据缺失都不会调用 CLI`, (t) => {
    const f = fixture(t);
    assert.throws(() => f.run(operation, { targetPath: undefined }), /目标/);
    writeFileSync(f.targetPath, JSON.stringify({ ...target, database_id: "" }));
    assert.throws(() => f.run(operation), /database_id/);
    writeFileSync(f.targetPath, JSON.stringify(target));
    assert.throws(
      () => f.run(operation, { env: { ...f.env, CLOUDFLARE_API_TOKEN: " " } }),
      /CLOUDFLARE_API_TOKEN/,
    );
    assert.throws(
      () => f.run(operation, { env: { ...f.env, CI: "true" } }),
      /CI/,
    );
    writeFileSync(f.channelsPath, "{");
    assert.throws(() => f.run(operation), /channels\.json/);
    assert.deepEqual(f.calls(), []);
  });
}

test("发布只向指定命名空间写入通过验证的渠道和 App 公告", (t) => {
  const f = fixture(t);
  f.run("publish");
  const [put] = f.calls();
  assert.equal(f.calls().length, 1);
  assert.equal(put.command, "kv bulk put");
  assert(put.args.includes("--remote"));
  assert.equal(
    put.args[put.args.indexOf("--namespace-id") + 1],
    target.kv_namespace_id,
  );
  assert.equal(put.config.account_id, target.account_id);
  assert.equal(put.account, target.account_id);
  assert.equal(put.authenticated, true);
  assert.equal(put.hasLegacyCredential, false);
  const values = Object.fromEntries(
    put.entries.map(({ key, value }) => [key, JSON.parse(value)]),
  );
  assert.deepEqual(values.channels, channels);
  assert.deepEqual(
    values.announcements.map(({ id, body }) => [id, body]),
    [["2026-11-01-001", "测试正文。"]],
  );
});

test("部署先离线检查与核对 Secret，再迁移指定 D1，最后部署指定 Worker", (t) => {
  const f = fixture(t);
  f.run("deploy");
  const [check, secrets, migrate, deploy] = f.calls();
  assert.deepEqual(
    f.calls().map(({ command }) => command),
    ["check", "secret list", "d1 migrations apply", "deploy"],
  );
  assert.equal(check.authenticated, false);
  assert.equal(check.hasLegacyCredential, false);
  assert.equal(check.account, undefined);
  assert.equal(secrets.authenticated, true);
  assert(migrate.args.includes("DB"));
  assert(migrate.args.includes("--remote"));
  assert(deploy.args.includes("--no-bundle"));
  assert(deploy.args.includes("--experimental-auto-create=false"));
  assert.equal(
    deploy.config.main,
    resolve("services/app_service/.generated/build/index.js"),
  );
  assert.equal(deploy.config.name, target.worker_name);
  assert.equal(deploy.config.d1_databases[0].database_id, target.database_id);
  assert.equal(deploy.config.kv_namespaces[0].id, target.kv_namespace_id);
  assert.deepEqual(deploy.config.routes, [
    { pattern: target.domain, custom_domain: true },
  ]);
});

test("本地构建或 Secret 检查失败时不迁移；迁移失败时不部署", (t) => {
  const f = fixture(t);
  assert.throws(
    () => f.run("deploy", { env: { ...f.env, FAKE_FAIL: "check" } }),
    /检查/,
  );
  assert.deepEqual(
    f.calls().map(({ command }) => command),
    ["check"],
  );
  assert.throws(
    () => f.run("deploy", { env: { ...f.env, FAKE_NO_SECRET: "1" } }),
    /USER_KEY_SECRET/,
  );
  assert.deepEqual(
    f
      .calls()
      .slice(1)
      .map(({ command }) => command),
    ["check", "secret list"],
  );
  assert.throws(
    () =>
      f.run("deploy", { env: { ...f.env, FAKE_FAIL: "d1 migrations apply" } }),
    /迁移/,
  );
  assert.deepEqual(
    f
      .calls()
      .slice(3)
      .map(({ command }) => command),
    ["check", "secret list", "d1 migrations apply"],
  );
});

test("D1 迁移不继承外层命令的 stdin", (t) => {
  const f = fixture(t);
  const release = new URL(
    "../../release/app_service/release.mjs",
    import.meta.url,
  );
  const command = `import { runRelease } from ${JSON.stringify(release.href)}; runRelease("deploy", ${JSON.stringify(f.options)});`;
  const child = spawnSync(
    process.execPath,
    ["--input-type=module", "-e", command],
    {
      env: { ...f.env, FAKE_READ_STDIN: "1" },
      input: "n\n",
      encoding: "utf8",
    },
  );
  assert.equal(child.status, 0, child.stderr);
  assert.equal(
    f.calls().find(({ command }) => command === "d1 migrations apply").stdin,
    "",
  );
});
