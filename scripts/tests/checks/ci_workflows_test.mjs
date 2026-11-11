import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { parse } from "yaml";

const workflow = (name) => parse(readFileSync(`.github/workflows/${name}.yml`, "utf8"));
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
