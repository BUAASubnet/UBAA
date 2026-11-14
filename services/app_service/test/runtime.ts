import { readFile } from "node:fs/promises";
import { Database } from "../src/database";
import { RateLimit, ResponseCache } from "../src/environment";
import app from "../src/index";
const values = new Map<string, string>();
export const env = {
  DB: new Database(process.env.TEST_DATABASE_URL!),
  USER_KEY_SECRET: "synthetic-app-service-test",
  TELEMETRY_LIMIT: new RateLimit(5),
  ERASE_LIMIT: new RateLimit(3),
  BOOTSTRAP_LIMIT: new RateLimit(600),
  CACHE: new ResponseCache(),
  APP_CONFIG: {
    async get(key: string, type?: string) {
      const value = values.get(key);
      return value === undefined
        ? null
        : type === "json"
          ? JSON.parse(value)
          : value;
    },
    async put(key: string, value: string) {
      values.set(key, value);
    },
    async delete(key: string) {
      values.delete(key);
    },
  },
};
export const exports = {
  default: {
    fetch(input: Request | string, init?: RequestInit) {
      return app.fetch(
        new Request(input, { ...init, duplex: "half" } as RequestInit),
        env,
      );
    },
  },
};
export function createWaitContext() {
  const pending: Promise<unknown>[] = [];
  return {
    pending,
    waitUntil(promise: Promise<unknown>) {
      pending.push(promise);
    },
  };
}
export async function waitOnWaitContext(
  ctx: ReturnType<typeof createWaitContext>,
) {
  await Promise.all(ctx.pending);
}
export function createScheduledController(options: {
  scheduledTime: number;
  cron: string;
}) {
  return { ...options, noRetry() {} };
}
export async function migrate() {
  await env.DB.prepare(
    "DROP SCHEMA public CASCADE; CREATE SCHEMA public",
  ).run();
  for (const file of ["0001_initial.sql", "0002_minute_counts.sql"]) {
    await env.DB.prepare(
      await readFile(new URL(`../migrations/${file}`, import.meta.url), "utf8"),
    ).run();
  }
  await env.DB.prepare(
    "CREATE FUNCTION synthetic_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION '合成数据库故障'; END $$",
  ).run();
}
