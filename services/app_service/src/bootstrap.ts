import type { WaitContext } from "./environment";
import type { Environment } from "./environment";
import {
  ANNOUNCEMENTS_KEY,
  type BootstrapQuery,
  CHANNELS_KEY,
  resolveUpdate,
  selectAnnouncements,
} from "./bootstrap_content";
import { invalidPayload } from "./request";
import { APP_SERVICE_SCHEMA_VERSION, validateBootstrapRequest } from "./schema";

export async function bootstrap(
  request: Request,
  env: Environment,
  ctx: WaitContext,
): Promise<Response> {
  const key = request.headers.get("X-Real-IP") ?? "unknown";
  if (!(await env.BOOTSTRAP_LIMIT.limit({ key })).success) {
    return new Response(null, { status: 429 });
  }

  const url = new URL(request.url);
  const params = [...url.searchParams];
  const query = Object.fromEntries(params);
  if (
    params.length !== 4 ||
    !validateBootstrapRequest(query) ||
    request.headers.has("Cookie") ||
    request.headers.has("Authorization")
  ) {
    return invalidPayload();
  }
  const parsed = query as BootstrapQuery;
  // 规范化编码和参数次序；缓存查找不使用原请求的 Cookie、Range 等请求头。
  url.search = new URLSearchParams({
    schema: parsed.schema,
    platform: parsed.platform,
    channel: parsed.channel,
    version: parsed.version,
  }).toString();
  const cacheKey = new Request(url.toString());
  const cache = env.CACHE;
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  const [channels, announcements] = await Promise.all([
    env.APP_CONFIG.get(CHANNELS_KEY, "json"),
    env.APP_CONFIG.get(ANNOUNCEMENTS_KEY, "json"),
  ]);
  const response = Response.json(
    {
      schema: APP_SERVICE_SCHEMA_VERSION,
      update: resolveUpdate(channels, parsed),
      announcements: selectAnnouncements(announcements, parsed, Date.now()),
    },
    { headers: { "Cache-Control": "public, max-age=300" } },
  );
  ctx.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}
