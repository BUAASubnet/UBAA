import type { Environment } from "./environment";
import { invalidPayload, readJson } from "./request";
import { validateEraseRequest } from "./schema";

const DETAIL_TABLES = [
  "active_days",
  "counter_days",
  "error_days",
  "timing_days",
];

export async function eraseTelemetry(
  request: Request,
  env: Environment,
): Promise<Response> {
  const payload = await readJson(request);
  if (payload instanceof Response) return payload;
  if (!validateEraseRequest(payload)) return invalidPayload();
  const { install_id } = payload;
  if (!(await env.ERASE_LIMIT.limit({ key: install_id })).success) {
    return new Response(null, { status: 429 });
  }

  await env.DB.batch(
    [
      env.DB.prepare(
        `
      INSERT INTO erased_installs (install_id, erased_at) VALUES ($1, $2)
      ON CONFLICT (install_id) DO UPDATE SET erased_at = excluded.erased_at
    `,
      ).bind(install_id, new Date().toISOString()),
      ...DETAIL_TABLES.map((table) =>
        env.DB.prepare(`DELETE FROM ${table} WHERE install_id = $1`).bind(
          install_id,
        ),
      ),
    ],
    install_id,
  );
  return new Response(null, { status: 204 });
}
