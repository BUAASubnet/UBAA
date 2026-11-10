import { applyD1Migrations, type D1Migration } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";

declare global {
  namespace Cloudflare {
    interface Env {
      TEST_MIGRATIONS: D1Migration[];
    }
  }
}

export function migrate() {
  return applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
}

export function uploadRequest(payload: unknown) {
  return new Request("https://app-service.invalid/v1/telemetry", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export function postTelemetry(payload: unknown) {
  return exports.default.fetch(uploadRequest(payload));
}

export function erase(installId: string) {
  return exports.default.fetch(
    "https://app-service.invalid/v1/telemetry/erase",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ schema: 1, install_id: installId }),
    },
  );
}

export function relativeDay(offset: number) {
  return new Date(Date.now() + (offset * 24 + 8) * 3600000)
    .toISOString()
    .slice(0, 10);
}

export function createBatch() {
  return {
    schema: 1,
    batch_id: crypto.randomUUID(),
    install_id: crypto.randomUUID(),
    platform: "linux",
    channel: "github",
    days: [
      {
        day: relativeDay(0),
        app_version: "2.0.0",
        surfaces: ["gui"],
        users: [] as {
          key: string;
          cohort_type: string;
          cohort_year: number | null;
        }[],
        counters: [
          {
            event: "feature_loaded",
            feature: "schedule",
            route: "direct",
            result: "success",
            count: 3,
          },
        ],
        errors: [
          {
            event: "feature_failed",
            feature: "grades",
            route: "webvpn",
            error_code: "parse_error",
            error_kind: "upstream",
            retryable: false,
            count: 1,
          },
        ],
        timings: [
          {
            metric: "feature_load",
            feature: "schedule",
            route: "direct",
            bucket: "lt_1000",
            count: 2,
          },
        ],
      },
    ],
  };
}

export async function syntheticKey() {
  const bytes = new TextEncoder().encode(
    "ubaa-telemetry-user-v1:STEP-THREE-SYNTHETIC",
  );
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}
