import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { Readable } from "node:stream";
import { Database } from "./database";
import { RateLimit, ResponseCache, type Environment } from "./environment";
import app from "./index";

import { handleDownload } from "../../../docs/site/download_worker.js";
import { describe } from "../../../docs/site/download_model.js";

const db = new Database(process.env.DATABASE_URL!);
const secret = process.env.USER_KEY_SECRET;
if (!secret) throw new Error("缺少遥测用户标识密钥");
const configPath = process.env.APP_CONFIG_PATH ?? "/etc/ubaa/content.json";
const env: Environment = {
  DB: db,
  USER_KEY_SECRET: secret,
  TELEMETRY_LIMIT: new RateLimit(5),
  ERASE_LIMIT: new RateLimit(3),
  BOOTSTRAP_LIMIT: new RateLimit(600),
  CACHE: new ResponseCache(),
  APP_CONFIG: {
    async get(key) {
      return JSON.parse(await readFile(configPath, "utf8"))[key] ?? null;
    },
  },
};

if (process.argv.includes("--migrate")) {
  await db
    .prepare(
      "CREATE TABLE IF NOT EXISTS schema_versions (name TEXT PRIMARY KEY)",
    )
    .run();
  for (const name of ["0001_initial.sql", "0002_minute_counts.sql"]) {
    if (
      await db
        .prepare("SELECT name FROM schema_versions WHERE name = $1")
        .bind(name)
        .first()
    )
      continue;
    const sql = await readFile(
      new URL(`../../migrations/${name}`, import.meta.url),
      "utf8",
    );
    await db.batch([
      db.prepare(sql),
      db.prepare("INSERT INTO schema_versions VALUES ($1)").bind(name),
    ]);
  }
  await db.close();
} else if (process.argv.includes("--aggregate")) {
  await app.scheduled({ scheduledTime: Date.now(), noRetry() {} }, env);
  await db.close();
} else {
  const server = createServer(async (incoming, outgoing) => {
    try {
      const headers = new Headers();
      for (const [name, value] of Object.entries(incoming.headers)) {
        if (value !== undefined)
          headers.set(name, Array.isArray(value) ? value.join(", ") : value);
      }
      const request = new Request(
        `https://${headers.get("host")}${incoming.url}`,
        {
          method: incoming.method,
          headers,
          body: ["GET", "HEAD"].includes(incoming.method!)
            ? undefined
            : Readable.toWeb(incoming),
          duplex: "half",
        } as RequestInit,
      );
      const response =
        incoming.url === "/healthz"
          ? (await db.prepare("SELECT 1").first(), new Response("ok\n"))
          : incoming.url?.startsWith("/downloads/") ||
              incoming.url === "/release-data.json"
            ? await downloads(request)
            : await app.fetch(request, env);
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      if (response.body)
        Readable.fromWeb(
          response.body as import("node:stream/web").ReadableStream,
        ).pipe(outgoing);
      else outgoing.end();
    } catch {
      outgoing.writeHead(500);
      outgoing.end();
    }
  });
  server.requestTimeout = 30_000;
  server.listen(Number(process.env.PORT ?? 10080), "127.0.0.1", () => {
    console.log(
      `Ready on http://127.0.0.1:${(server.address() as import("node:net").AddressInfo).port}`,
    );
  });
  process.on("SIGTERM", () =>
    server.close(() => {
      void db.close();
    }),
  );
}

async function downloads(request: Request): Promise<Response> {
  try {
    const manifest = JSON.parse(
      await readFile("/var/lib/ubaa/published.json", "utf8"),
    );
    const source = {
      version: manifest.version,
      build: manifest.build,
      shareId: "AA61B7EDC6F2BC4AF5B040FAF0563AD160",
      directory: [`v${manifest.version}`, String(manifest.build)],
    };
    if (new URL(request.url).pathname === "/release-data.json")
      return Response.json(describe(manifest, source), {
        headers: { "Cache-Control": "no-store" },
      });
    return await handleDownload(
      request,
      { ASSETS: { fetch: async () => new Response(null, { status: 404 }) } },
      fetch,
      manifest,
      source,
    );
  } catch {
    return new Response(null, {
      status: 404,
      headers: { "Cache-Control": "no-store" },
    });
  }
}
