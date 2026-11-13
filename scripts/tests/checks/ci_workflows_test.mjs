import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { parse } from "yaml";

const workflow = (name) => parse(readFileSync(`.github/workflows/${name}.yml`, "utf8"));
test("Release 由手动构建生成草稿，发布草稿不会再次触发构建", () => {
  const release = workflow("release");
  assert.deepEqual(Object.keys(release.on), ["workflow_dispatch"]);
  for (const platform of ["android", "linux", "windows", "macos", "ios", "ohos"]) {
    assert.ok(release.jobs.distribute.needs.includes(platform));
  }
});
test("开发提交不会触发完整验收和原生矩阵", () => {
  const full = workflow("ci");
  assert.deepEqual(full.on.pull_request.branches, ["main"]);
  assert.equal(full.on.push, undefined);
  const native = workflow("flutter-platforms");
  assert.equal(native.on.push, undefined);
  assert.equal(native.on.pull_request, undefined);
  assert.ok(Object.hasOwn(native.on, "workflow_call"));
});
test("main 必需检查拒绝失败、取消和被跳过的验收", () => {
  const full = workflow("ci");
  const required = full.jobs["main-required"];
  assert.ok(required);
  assert.deepEqual([...required.needs].sort(), Object.keys(full.jobs).filter((key) => key !== "main-required").sort());
  for (const result of ["success", "failure", "cancelled", "skipped"]) {
    const needs = Object.fromEntries(required.needs.map((key) => [key, { result: "success" }]));
    needs[required.needs[0]].result = result;
    const execution = spawnSync("bash", ["-euo", "pipefail", "-c", required.steps.find((step) => step.name === "确认全部验收成功").run], {
      env: { ...process.env, NEEDS: JSON.stringify(needs), CODEGEN_REQUIRED: "true" }, encoding: "utf8",
    });
    assert.equal(execution.status, result === "success" ? 0 : 1, execution.stderr);
  }
});
test("Android 并行作业覆盖三个 ABI 且产物名称互不覆盖", () => {
  const job = workflow("flutter-platforms").jobs["native-debug"];
  const android = job.strategy.matrix.include.filter((entry) => entry.platform === "android-apk");
  assert.deepEqual(android.map(({ abi, android_target }) => [abi, android_target]).sort(), [
    ["arm64-v8a", "android-arm64"], ["armeabi-v7a", "android-arm"], ["x86_64", "android-x64"],
  ].sort());
  assert.equal(new Set(android.map((entry) => entry.artifact_id)).size, 3);
  assert.equal(job.strategy["fail-fast"], false);
});
