import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { parse } from "yaml";
const load = (name) =>
  parse(
    readFileSync(
      new URL(`../../../.github/workflows/${name}`, import.meta.url),
      "utf8",
    ),
  );
const workflow = load("worker.yml");
const contentWorkflow = load("app-content.yml");
test("应用部署等待检查且只从主仓库 main 进入生产环境", () => {
  const job = workflow.jobs["app-service-deploy"];
  assert.deepEqual(job.needs, ["check"]);
  assert.equal(job.environment, "app-service-production");
  assert.match(job.if, /github.ref_name == 'main'/);
  assert.match(job.if, /github.repository == 'BUAASubnet\/UBAA'/);
  assert.equal(workflow.concurrency["cancel-in-progress"], false);
  const steps = job.steps;
  assert.equal(steps.at(-1).run, "python3 scripts/server/notify.py app");
  assert.deepEqual(Object.keys(steps.at(-1).env).sort(), [
    "GH_TOKEN",
    "UBAA_DEPLOY_HOST_KEYS",
    "UBAA_DEPLOY_KEY",
  ]);
});

test("服务器部署包必须实际上传，包含明确选择的隐藏目录下产物", () => {
  const upload = workflow.jobs.check.steps.find(step => step.with?.name === "app-service");
  assert.equal(upload.with["if-no-files-found"], "error");
  assert.equal(upload.with["include-hidden-files"], true);
  assert.deepEqual(upload.with.path.trim().split("\n"), [".ubaa_local/app_service.tar.gz", ".ubaa_local/bhpan-publish"]);
});

test("发布工具使用可在 Debian 13 运行的 glibc 基线构建", () => {
  assert.equal(workflow.jobs.check["runs-on"], "ubuntu-24.04");
});

test("渠道与公告只从主仓库 dev 发布，排队时不被应用部署取消", () => {
  assert.deepEqual(contentWorkflow.on.push.branches, ["dev"]);
  assert.equal(contentWorkflow.concurrency["cancel-in-progress"], false);
  assert.notEqual(contentWorkflow.concurrency.group, workflow.concurrency.group);
  const job = contentWorkflow.jobs["app-content-deploy"];
  assert.deepEqual(job.needs, ["check"]);
  assert.equal(job.environment, "docs-production");
  assert.match(job.if, /github.ref_name == 'dev'/);
  assert.match(job.if, /github.repository == 'BUAASubnet\/UBAA'/);
  assert.doesNotMatch(job.if, /pull_request/);
  const notify = job.steps.at(-1);
  assert.equal(notify.run, "python3 scripts/server/notify.py content");
  assert.deepEqual(Object.keys(notify.env).sort(), [
    "GH_TOKEN",
    "UBAA_DEPLOY_HOST_KEYS",
    "UBAA_DEPLOY_KEY",
  ]);
});

test("应用部署不再由公告改动触发", () => {
  assert.ok(!workflow.on.push.paths.includes("docs/site/announcements/**"));
});
