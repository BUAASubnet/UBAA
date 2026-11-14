import type { WaitContext } from "./environment";
import type { Environment } from "./environment";
import { runAggregation } from "./aggregate";
import { bootstrap } from "./bootstrap";
import { eraseTelemetry } from "./erase";
import { reportTelemetry } from "./telemetry";

export default {
  async fetch(
    request: Request,
    env: Environment,
    ctx: WaitContext = {
      waitUntil: (promise) => {
        void promise;
      },
    },
  ): Promise<Response> {
    const { origin, pathname } = new URL(request.url);
    const requestOrigin = request.headers.get("Origin");
    if (requestOrigin !== null && requestOrigin !== origin) {
      return new Response(null, { status: 403 });
    }

    try {
      if (request.method === "POST") {
        if (pathname === "/v1/telemetry")
          return await reportTelemetry(request, env);
        if (pathname === "/v1/telemetry/erase")
          return await eraseTelemetry(request, env);
      }
      if (request.method === "GET" && pathname === "/v1/bootstrap") {
        return await bootstrap(request, env, ctx);
      }
      return new Response(null, { status: 404 });
    } catch {
      // 数据库或运行时错误可能包含输入信息，不记录或回显。
      return new Response(null, { status: 500 });
    }
  },
  async scheduled(
    controller: { scheduledTime: number; noRetry(): void },
    env: Environment,
  ): Promise<void> {
    controller.noRetry();
    try {
      await runAggregation(env.DB, controller.scheduledTime);
    } catch {
      throw new Error("统计汇总任务失败");
    }
  },
};
