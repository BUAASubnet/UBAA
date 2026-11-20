import assert from "node:assert/strict";
import { test } from "node:test";
import { runRelease } from "../../release/app_service/release.mjs";

test("应用部署触发 main 工作流，内容发布触发 dev 工作流", async () => {
  for (const [operation, workflow, branch] of [
    ["deploy", "worker.yml", "main"],
    ["publish", "app-content.yml", "dev"],
  ]) {
    const calls = [];
    await runRelease(operation, {
      execute: (...args) => {
        calls.push(args);
        return { status: 0 };
      },
    });
    assert.deepEqual(calls[0].slice(0, 2), [
      "gh",
      ["workflow", "run", workflow, "--ref", branch],
    ]);
  }
});
test("非法操作、内容错误或触发失败不会报告部署成功", async () => {
  let called = false;
  const execute = () => {
    called = true;
    return { status: 1 };
  };
  await assert.rejects(runRelease("other", { execute }));
  assert.equal(called, false);
  await assert.rejects(
    runRelease("deploy", {
      contentPaths: { channelsPath: "missing.invalid" },
      execute,
    }),
  );
  assert.equal(called, false);
  await assert.rejects(runRelease("deploy", { execute }), /无法触发/);
});
