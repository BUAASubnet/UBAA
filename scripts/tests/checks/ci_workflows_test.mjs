import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { parse } from "yaml";

const workflow = (name) => parse(readFileSync(`.github/workflows/${name}.yml`, "utf8"));
test("分发允许复用验收时跳过间接 verify，但要求所有直接依赖成功", () => {
  const job = workflow("release").jobs.distribute;
  const expression = job.if.slice(3, -2).replaceAll("needs.*.result", "Object.values(needs).map(job => job.result)");
  const evaluate = new Function("needs", "cancelled", "contains", `return ${expression}`);
  const needs = Object.fromEntries(job.needs.map(name => [name, { result: "success" }]));
  needs.verify = { result: "skipped" };
  const check = (cancelled = false) => evaluate(needs, () => cancelled, (values, value) => values.includes(value));
  assert.equal(check(), true);
  assert.equal(check(true), false);
  for (const name of job.needs) {
    for (const result of ["failure", "cancelled", "skipped"]) {
      needs[name].result = result;
      assert.equal(check(), false, `${name}: ${result}`);
    }
    needs[name].result = "success";
  }
});
test("Release 由手动构建生成草稿，发布草稿不会再次触发构建", () => {
  const release = workflow("release");
  assert.deepEqual(Object.keys(release.on), ["workflow_dispatch"]);
  for (const platform of ["android", "linux", "windows", "macos", "ios", "ohos"]) {
    assert.ok(release.jobs.distribute.needs.includes(platform));
  }
  // 留空 Tag 与显式 Tag 解析为同一版本，分组不能随输入形式变化，否则两次运行会并行写入同一草稿和 R2 路径。
  assert.equal(release.concurrency.group, "release");
  assert.equal(release.concurrency["cancel-in-progress"], false);
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
test("dev 的每次推送独立运行，同一个 PR 取消旧运行", () => {
  const { group, "cancel-in-progress": cancelInProgress } = workflow("dev").concurrency;
  const evaluate = (expression, github) => new Function("github", `return ${expression}`)(github);
  const groupFor = (github) => group.replace(/\$\{\{(.+?)\}\}/g, (_, expression) => evaluate(expression, github));
  const cancels = (github) => typeof cancelInProgress === "boolean"
    ? cancelInProgress
    : evaluate(cancelInProgress.slice(3, -2), github);
  const pushes = ["1", "2", "3"].map((run_id) => ({ event_name: "push", ref: "refs/heads/dev", run_id }));
  for (const push of pushes) assert.equal(cancels(push), false);
  assert.equal(new Set(pushes.map(groupFor)).size, pushes.length);
  const pr = { event_name: "pull_request", ref: "refs/pull/8/merge", run_id: "4" };
  assert.equal(cancels(pr), true);
  assert.equal(groupFor(pr), groupFor({ ...pr, run_id: "5" }));
  assert.notEqual(groupFor(pr), groupFor({ ...pr, ref: "refs/pull/9/merge", run_id: "6" }));
  const manual = { ...pushes[0], event_name: "workflow_dispatch", run_id: "7" };
  assert.equal(cancels(manual), false);
  assert.ok(!pushes.map(groupFor).includes(groupFor(manual)));
});
test("dev Rust 执行 Clippy、Core 合同及其余工作区测试", () => {
  const { steps } = workflow("dev").jobs.rust;
  assert.equal(steps.find((step) => step.uses === "./.github/actions/rust_cache").with.kind, "tests");
  const commands = steps.flatMap((step) => step.run?.split("\n") ?? []);
  assert.deepEqual(commands, [
    "cargo fmt --all -- --check",
    "cargo clippy --locked --workspace --all-targets -- -D warnings",
    "just core-test-contract",
    "cargo test --locked --workspace --exclude ubaa-core",
  ]);
});
test("dev Flutter 在静态分析后把选中的包传给非 golden 测试入口", () => {
  const { changes, flutter } = workflow("dev").jobs;
  assert.equal(flutter["runs-on"], "ubuntu-latest");
  assert.equal(flutter.needs, "changes");
  assert.equal(changes.outputs.flutter_packages, "${{ steps.paths.outputs.flutter_packages }}");
  const commands = flutter.steps.filter((step) => step.run);
  assert.deepEqual(commands.map(({ run }) => run), [
    "bash scripts/check/flutter-workspace.sh analyze",
    'bash scripts/check/flutter-workspace.sh test-non-golden "$FLUTTER_PACKAGES"',
  ]);
  assert.equal(commands[1].env.FLUTTER_PACKAGES, "${{ needs.changes.outputs.flutter_packages }}");
});
test("dev 夜间定时或手动运行，以只读权限复用 dev 的完整验收", () => {
  const nightly = workflow("dev-nightly");
  assert.deepEqual(Object.keys(nightly.on).sort(), ["schedule", "workflow_dispatch"]);
  assert.equal(nightly.on.schedule.length, 1);
  assert.match(nightly.on.schedule[0].cron, /^\d+ \d+ \* \* \*$/);
  assert.deepEqual(nightly.permissions, { contents: "read", actions: "read" });
  assert.doesNotMatch(JSON.stringify(nightly), /\bsecrets\b/);
  assert.deepEqual(Object.keys(nightly.jobs).sort(), ["prepare", "verify"]);
  assert.equal(nightly.jobs.prepare.steps[0].with.ref, "refs/heads/dev");
  assert.equal(nightly.jobs.prepare.steps[0].with["persist-credentials"], false);
  const verify = nightly.jobs.verify;
  assert.equal(verify.needs, "prepare");
  assert.equal(verify.if, "needs.prepare.outputs.accepted == 'false'");
  assert.equal(verify.uses, "BUAASubnet/UBAA/.github/workflows/ci.yml@dev");
  assert.deepEqual(verify.with, { checkout_ref: "${{ needs.prepare.outputs.sha }}", local_macos: false });
});
test("夜间候选传给完整验收及原生子流程，现有调用默认检出保持不变", () => {
  const full = workflow("ci");
  const native = workflow("flutter-platforms");
  for (const caller of [full, native]) {
    assert.equal(caller.on.workflow_call.inputs.checkout_ref.default, "");
    for (const job of Object.values(caller.jobs)) {
      for (const step of job.steps ?? []) {
        if (step.uses?.startsWith("actions/checkout@")) {
          assert.equal(step.with.ref, "${{ inputs.checkout_ref }}");
        }
      }
    }
  }
  assert.equal(full.jobs.native.with.checkout_ref, "${{ inputs.checkout_ref }}");
  assert.equal(workflow("release").jobs.verify.with.checkout_ref, undefined);
  const plan = full.jobs.plan.steps.find((step) => step.id === "plan");
  const sha = "a".repeat(40);
  for (const [checkoutRef, workflowSha, status] of [["", undefined, 0], [sha, sha, 0], [sha, "b".repeat(40), 1]]) {
    const result = spawnSync("bash", ["-euo", "pipefail", "-c", plan.run], {
      env: { ...process.env, BASE_SHA: "", CHECKOUT_REF: checkoutRef,
        WORKFLOW_JOB: JSON.stringify({ workflow_sha: workflowSha }), GITHUB_OUTPUT: "/dev/null" },
      encoding: "utf8",
    });
    assert.equal(result.status, status, result.stderr);
  }
});
test("商店上传只等待对应平台构建，失败或取消时不上传", () => {
  const release = workflow("release");
  for (const [store, platform] of [["app-store", "ios"], ["appgallery", "ohos"]]) {
    const job = release.jobs[store];
    assert.deepEqual(new Set(job.needs), new Set(["metadata", platform]));
    const condition = new Function("needs", "cancelled", `return ${job.if.slice(3, -2)}`);
    for (const result of ["success", "failure", "cancelled", "skipped"]) {
      const needs = { metadata: { result: "success" }, [platform]: { result } };
      assert.equal(condition(needs, () => false), result === "success");
      assert.equal(condition(needs, () => true), false);
    }
  }
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

const runnerFor = (job, local, os, event = "workflow_dispatch", ref = "refs/heads/main") => {
  const evaluate = new Function("inputs", "matrix", "github", `return ${job["runs-on"].slice(3, -2)}`);
  return evaluate({ local_macos: local }, { os }, { event_name: event, ref, workflow: "Release 构建与草稿" });
};
test("本机 Release 路由覆盖 Apple 构建与验收，普通 CI 保留托管 runner", () => {
  const release = workflow("release");
  assert.equal(release.on.workflow_dispatch.inputs.local_macos.default, false);
  assert.equal(release.jobs.verify.with.local_macos, "${{ inputs.local_macos }}");
  for (const [name, hosted] of [["macos", "macos-26-intel"], ["ios", "xcode-27"], ["app-store", "xcode-27"], ["store-access", "macos-26"]]) {
    assert.equal(runnerFor(release.jobs[name], true, hosted), "ubaa-release-macos");
    assert.equal(runnerFor(release.jobs[name], false, hosted), hosted);
  }
  const ci = workflow("ci");
  const native = workflow("flutter-platforms");
  assert.equal(ci.jobs.native.with.local_macos, "${{ inputs.local_macos || false }}");
  for (const job of [ci.jobs["rust-checks"], ci.jobs["rust-builds"], ci.jobs["rust-tests"], ci.jobs["flutter-tests"], native.jobs["native-debug"]]) {
    for (const os of ["macos-26", "xcode-27", "ubuntu-24.04", "windows-2025"]) {
      const apple = os === "macos-26" || os === "xcode-27";
      assert.equal(runnerFor(job, true, os), apple ? "ubaa-release-macos" : os);
      assert.equal(runnerFor(job, false, os), os);
      assert.equal(runnerFor(job, true, os, "pull_request", "refs/pull/1/merge"), os);
    }
  }
});

test("HarmonyOS 商店产物与公开安装包分别上传", () => {
  const uploads = workflow("release").jobs.ohos.steps.filter((step) => step.uses?.startsWith("actions/upload-artifact@"));
  assert.deepEqual(uploads.filter((step) => step.with.name.startsWith("public-")).map((step) => step.with.path), [".ubaa_local/release/public/*"]);
  assert.equal(uploads.find((step) => step.with.name === "store-harmonyos").with.path, ".ubaa_local/release/store/*.app");
  const recovery = workflow("release-distribute");
  assert.deepEqual(Object.keys(recovery.on), ["workflow_dispatch"]);
  assert.equal(recovery.concurrency.group, workflow("release").jobs.distribute.concurrency.group);
  const job = recovery.jobs.distribute;
  assert.equal(job.environment, "release-production");
  assert.equal(job.steps.find((step) => step.uses?.startsWith("actions/download-artifact@")).with["run-id"], "${{ inputs.source_run }}");
});
