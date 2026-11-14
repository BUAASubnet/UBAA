import { env, exports } from "./runtime";
import { expect, it } from "vitest";

it("Worker 对未知路径返回空的 404", async () => {
  const response = await exports.default.fetch(
    "https://app-service.invalid/unknown",
  );
  expect(response.status).toBe(404);
  expect(await response.text()).toBe("");
});

it("测试运行时提供本地 D1、KV 和合成密钥", async () => {
  const result = await env.DB.prepare("SELECT 1 AS value").first("value");
  expect(result).toBe(1);

  await env.APP_CONFIG.put("binding-smoke", "local");
  expect(await env.APP_CONFIG.get("binding-smoke")).toBe("local");
  expect(typeof env.USER_KEY_SECRET).toBe("string");
});

it("启动配置提供可用的原生限流绑定", async () => {
  expect(await env.BOOTSTRAP_LIMIT.limit({ key: crypto.randomUUID() })).toEqual(
    {
      success: true,
    },
  );
});
