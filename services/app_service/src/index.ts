import { bootstrap } from "./bootstrap";
import { eraseTelemetry } from "./erase";
import { reportTelemetry } from "./telemetry";

export default {
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext,
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
} satisfies ExportedHandler<Env>;
