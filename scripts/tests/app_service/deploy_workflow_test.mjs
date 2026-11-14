import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { parse } from "yaml";
const workflow = parse(
  readFileSync(
    new URL("../../../.github/workflows/worker.yml", import.meta.url),
    "utf8",
  ),
);
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
