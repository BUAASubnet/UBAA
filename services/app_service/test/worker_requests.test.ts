import { env, exports } from "./runtime";
import { createWaitContext, waitOnWaitContext } from "./runtime";
import { bootstrap as readBootstrap } from "../src/bootstrap";
import { beforeAll, expect, it } from "vitest";
import { createBatch, erase, migrate } from "./telemetry_support";

beforeAll(migrate);

function send(path: string, body: unknown, headers?: HeadersInit) {
  return exports.default.fetch(`https://app-service.invalid${path}`, {
    method: "POST",
    body: JSON.stringify(body),
    headers: headers ?? { "Content-Type": "application/json" },
  });
}

it("上报接口拒绝未知字段并只返回机器码", async () => {
  const response = await send("/v1/telemetry", {
    ...createBatch(),
    unexpected: "synthetic",
  });
  expect(response.status).toBe(400);
  expect(await response.json()).toBe("invalid_payload");
  expect(response.headers.has("Access-Control-Allow-Origin")).toBe(false);
});

it("对不存在的安装删除也返回 204", async () => {
  const response = await send("/v1/telemetry/erase", {
    schema: 1,
    install_id: crypto.randomUUID(),
  });
  expect(response.status).toBe(204);
  expect(await response.text()).toBe("");
});

it("上报入口拒绝非 JSON 正文", async () => {
  const response = await send(
    "/v1/telemetry",
    {},
    {
      "Content-Type": "text/plain",
    },
  );
  expect(response.status).toBe(415);
});

it("PostgreSQL 初始化应建立批次的 nonce 列和定时任务状态表", async () => {
  const batch = await env.DB.prepare(
    "SELECT column_name AS name FROM information_schema.columns WHERE table_name = 'batches' AND column_name = 'nonce'",
  ).first("name");
  const state = await env.DB.prepare(
    "SELECT column_name AS name FROM information_schema.columns WHERE table_name = 'job_state' AND column_name = 'last_success_day'",
  ).first("name");
  expect(batch).toBe("nonce");
  expect(state).toBe("last_success_day");
});

it("按 UTF-8 字节限制流式正文，接受恰好 128 KiB", async () => {
  const [exact, oversized] = [createBatch(), createBatch()];
  const limit = 128 * 1024;
  const valid = JSON.stringify(exact).padEnd(limit, " ");
  const multibyte = JSON.stringify({ ...oversized, unexpected: "字" }).padEnd(
    limit,
    " ",
  );
  for (const [body, expected] of [
    [valid, 204],
    [multibyte, 413],
  ] as const) {
    const bytes = new TextEncoder().encode(body);
    const response = await exports.default.fetch(
      "https://app-service.invalid/v1/telemetry",
      {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: new ReadableStream({
          start(controller) {
            controller.enqueue(bytes.subarray(0, 4096));
            controller.enqueue(bytes.subarray(4096));
            controller.close();
          },
        }),
      },
    );
    expect(response.status).toBe(expected);
  }
  const rejected = await env.DB.prepare(
    "SELECT 1 FROM batches WHERE batch_id = $1",
  )
    .bind(oversized.batch_id)
    .first();
  expect(rejected).toBeNull();
});

it("拒绝跨域上报与预检，不提供 CORS", async () => {
  const payload = createBatch();
  const crossOrigin = await send("/v1/telemetry", payload, {
    "Content-Type": "application/json",
    Origin: "https://different.invalid",
  });
  expect(crossOrigin.status).toBe(403);
  expect(crossOrigin.headers.has("Access-Control-Allow-Origin")).toBe(false);
  const preflight = await exports.default.fetch(
    "https://app-service.invalid/v1/telemetry",
    {
      method: "OPTIONS",
      headers: {
        Origin: "https://different.invalid",
        "Access-Control-Request-Method": "POST",
      },
    },
  );
  expect(preflight.headers.has("Access-Control-Allow-Origin")).toBe(false);
  const stored = await env.DB.prepare(
    "SELECT 1 FROM batches WHERE batch_id = $1",
  )
    .bind(payload.batch_id)
    .first();
  expect(stored).toBeNull();
});

it("上报按安装 ID 限流，删除使用独立的安装 ID 限流绑定", async () => {
  const payload = createBatch();
  for (let i = 0; i < 5; i++) {
    expect((await send("/v1/telemetry", payload)).status).toBe(204);
  }
  expect((await send("/v1/telemetry", payload)).status).toBe(429);
  expect((await send("/v1/telemetry", createBatch())).status).toBe(204);
  for (let i = 0; i < 3; i++) {
    expect((await erase(payload.install_id)).status).toBe(204);
  }
  expect((await erase(payload.install_id)).status).toBe(429);
});

it("启动配置按 IP 限流，其他 IP 不受影响", async () => {
  const requests = new Map<string, number>();
  const bindings = {
    ...env,
    BOOTSTRAP_LIMIT: {
      async limit({ key }: { key: string }) {
        const count = (requests.get(key) ?? 0) + 1;
        requests.set(key, count);
        return { success: count <= 2 };
      },
    },
  };
  async function bootstrap(ip: string) {
    const context = createWaitContext();
    const response = await readBootstrap(
      new Request(
        "https://app-service.invalid/v1/bootstrap?schema=1&platform=android&channel=github&version=2.0.0",
        { headers: { "X-Real-IP": ip } },
      ),
      bindings,
      context,
    );
    await waitOnWaitContext(context);
    return response;
  }
  expect((await bootstrap("192.0.2.25")).status).toBe(200);
  expect((await bootstrap("192.0.2.25")).status).toBe(200);
  expect((await bootstrap("192.0.2.25")).status).toBe(429);
  expect((await bootstrap("192.0.2.26")).status).toBe(200);
  expect([...requests.entries()]).toEqual([
    ["192.0.2.25", 3],
    ["192.0.2.26", 1],
  ]);
});
