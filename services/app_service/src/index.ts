import { eraseTelemetry } from "./erase";
import { reportTelemetry } from "./telemetry";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
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
        const key = request.headers.get("CF-Connecting-IP") ?? "unknown";
        if (!(await env.BOOTSTRAP_LIMIT.limit({ key })).success) {
          return new Response(null, { status: 429 });
        }
      }
      return new Response(null, { status: 404 });
    } catch {
      // 数据库或运行时错误可能包含输入信息，不记录或回显。
      return new Response(null, { status: 500 });
    }
  },
} satisfies ExportedHandler<Env>;
