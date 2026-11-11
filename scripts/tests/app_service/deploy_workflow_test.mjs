import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const ci = parse(readFileSync(join(root, ".github/workflows/worker.yml"), "utf8"));
const sha = "a".repeat(40);
const github = {
  event_name: "push",
  event: { deleted: false },
  repository: "BUAASubnet/UBAA",
  ref_name: "main",
};

// 只模拟本工作流使用的 GitHub 表达式子集。遇到新运算时显式更新测试。
function evaluate(expression, contexts, success) {
  if (typeof expression === "boolean") return expression;
  const source = expression.trim().replace(/^\$\{\{\s*|\s*\}\}$/g, "");
  function value(text) {
    if (text === "success()") return success;
    if (text === "false") return false;
    if (/^'[^']*'$/.test(text)) return text.slice(1, -1);
    assert.match(text, /^[\w-]+(?:\.[\w-]+)+$/);
    return text.split(".").reduce((entry, key) => {
      assert.ok(Object.hasOwn(entry, key), `未知测试上下文：${text}`);
      return entry[key];
    }, contexts);
  }
  return source.split(/\s*\|\|\s*/).some((part) =>
    part.split(/\s*&&\s*/).every((clause) => {
      const comparison = clause.match(/^(.+?)\s+(==|!=)\s+(.+)$/);
      if (!comparison) return Boolean(value(clause));
      const [, left, op, right] = comparison;
      const same =
        String(value(left)).toLowerCase() ===
        String(value(right)).toLowerCase();
      return op === "==" ? same : !same;
    }),
  );
}

function exercise({
  branch = "main",
  event = github,
  failedJob,
  head = sha,
  headExit = 0,
  deployExit = 0,
} = {}) {
  const job = ci.jobs["app-service-deploy"];
  assert.ok(job, "未配置 Worker 部署作业");
  const checks = Object.keys(ci.jobs).filter(
    (id) => id !== "app-service-deploy",
  );
  assert.deepEqual([...job.needs].sort(), checks.sort());
  const contexts = {
    github: event,
    vars: { APP_SERVICE_DEPLOY_BRANCH: branch },
  };
  if (!evaluate(job.if, contexts, !job.needs.includes(failedJob))) return [];

  const candidate = job.steps.find((step) => step.id === "candidate");
  const write = job.steps.find((step) => step.env?.CLOUDFLARE_API_TOKEN);
  assert.ok(candidate && write, "部署作业必须分离分支检查和远端写入");
  const tempParent = join(root, ".ubaa_local/app_service");
  mkdirSync(tempParent, { recursive: true, mode: 0o700 });
  const temp = mkdtempSync(join(tempParent, "workflow_test_"));
  const output = join(temp, "github_output");
  const env = {
    PATH: process.env.PATH,
    GITHUB_SHA: sha,
    GITHUB_REF: `refs/heads/${event.ref_name}`,
    GITHUB_OUTPUT: output,
    TEST_BIN: join(temp, "empty_bin"),
    TEST_HEAD: head,
    TEST_HEAD_EXIT: String(headExit),
    TEST_DEPLOY_EXIT: String(deployExit),
  };
  const fakeCli = `
PATH="$TEST_BIN"
git() {
  [[ "$*" == "ls-remote --exit-code --refs origin $GITHUB_REF" ]] || return 64
  printf 'git ls-remote\\n' >&2
  [[ "$TEST_HEAD_EXIT" == 0 ]] || return "$TEST_HEAD_EXIT"
  printf '%s\\t%s\\n' "$TEST_HEAD" "$GITHUB_REF"
}
just() {
  printf 'just %s\\n' "$*" >&2
  if [[ "$1" == 'app-service-deploy' ]]; then return "$TEST_DEPLOY_EXIT"; fi
}
`;
  const run = (step) =>
    spawnSync(
      "bash",
      [
        "--noprofile",
        "--norc",
        "-e",
        "-o",
        "pipefail",
        "-c",
        `${fakeCli}\n${step.run}`,
      ],
      {
        cwd: root,
        env,
        encoding: "utf8",
      },
    );
  try {
    const result = run(candidate);
    assert.equal(result.status, headExit, result.stderr);
    const calls = result.stderr.trim().split("\n");
    if (result.status !== 0) return calls;
    const deploy = readFileSync(output, "utf8").trim().split("=")[1];
    if (
      evaluate(
        write.if,
        { steps: { candidate: { outputs: { deploy } } } },
        true,
      )
    ) {
      const released = run(write);
      assert.equal(released.status, deployExit, released.stderr);
      calls.push(...released.stderr.trim().split("\n"));
    }
    return calls;
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

test("其他分支、PR、fork、分支删除均不调用发布命令", () => {
  assert.deepEqual(exercise({ event: { ...github, ref_name: "dev" } }), []);
  assert.deepEqual(
    exercise({ event: { ...github, event_name: "pull_request" } }),
    [],
  );
  assert.deepEqual(
    exercise({ event: { ...github, repository: "fork/UBAA" } }),
    [],
  );
  assert.deepEqual(
    exercise({ event: { ...github, event: { deleted: true } } }),
    [],
  );
});

test("任一 CI 检查失败时不调用发布命令", () => {
  const checks = Object.keys(ci.jobs).filter(
    (id) => id !== "app-service-deploy",
  );
  for (const failedJob of checks)
    assert.deepEqual(exercise({ failedJob }), [], failedJob);
});

test("候选提交仍是分支头时先部署再发布内容", () => {
  assert.deepEqual(exercise({ event: { ...github, event_name: "workflow_dispatch" } }), ["git ls-remote", "just app-service-deploy", "just app-service-publish"]);
  assert.deepEqual(exercise(), [
    "git ls-remote",
    "just app-service-deploy",
    "just app-service-publish",
  ]);
  assert.deepEqual(exercise({ head: "b".repeat(40) }), ["git ls-remote"]);
  assert.deepEqual(exercise({ headExit: 2 }), ["git ls-remote"]);
  assert.deepEqual(exercise({ deployExit: 19 }), [
    "git ls-remote",
    "just app-service-deploy",
  ]);
});

test("部署期间新提交不会取消生产作业", () => {
  const vars = { APP_SERVICE_DEPLOY_BRANCH: "main" };
  assert.equal(
    evaluate(ci.concurrency["cancel-in-progress"], { github, vars }),
    false,
  );
  assert.equal(
    evaluate(ci.concurrency["cancel-in-progress"], {
      github: { ...github, event_name: "pull_request" },
      vars,
    }),
    false,
  );
  assert.notEqual(
    ci.jobs["app-service-deploy"].concurrency?.group,
    ci.concurrency.group,
    "作业不能再次获取工作流已经占用的生产并发组",
  );
});

test("生产作业检出同一提交，只有远端写入步骤引用部署 Token", () => {
  const job = ci.jobs["app-service-deploy"];
  assert.equal(job.environment, "app-service-production");
  assert.equal(
    job.steps.find((step) => step.uses?.startsWith("actions/checkout@")).with
      .ref,
    "${{ github.sha }}",
  );
  const secretReferences = JSON.stringify(ci).match(
    /secrets\.CLOUDFLARE_API_TOKEN/g,
  );
  assert.equal(secretReferences?.length, 1);
  const write = job.steps.at(-1);
  assert.equal(
    write.env.CLOUDFLARE_API_TOKEN,
    "${{ secrets.CLOUDFLARE_API_TOKEN }}",
  );
  assert.match(write.run, /^just app-service-deploy\n/);
});
