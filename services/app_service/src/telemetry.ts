import { campusDay, shiftDay } from "./campus_time";
import { invalidPayload, readJson } from "./request";
import { validateTelemetryRequest, type TelemetryDay } from "./schema";

const NO_TOMBSTONE =
  "NOT EXISTS (SELECT 1 FROM erased_installs WHERE install_id = ?)";
const CHECK_TOMBSTONE =
  "SELECT EXISTS (SELECT 1 FROM erased_installs WHERE install_id = ?) AS erased";
const ACCEPTED_BATCH = `${NO_TOMBSTONE}
  AND EXISTS (SELECT 1 FROM batches WHERE batch_id = ? AND nonce = ?)`;

function installErased(): Response {
  return Response.json("install_erased", { status: 410 });
}

function detailUpsert(
  db: D1Database,
  table: string,
  key: string[],
  columns: string[],
  update: string,
): D1PreparedStatement {
  const names = [...key, ...columns];
  return db.prepare(`
    INSERT INTO ${table} (${names.join(", ")})
    SELECT ${names.map(() => "?").join(", ")}
    WHERE ${ACCEPTED_BATCH}
    ON CONFLICT (${key.join(", ")}) DO UPDATE SET ${update}
  `);
}

function detailUpserts(db: D1Database) {
  const keyedByVersion = ["day", "install_id", "app_version"];
  const eventDimensions = ["event", "feature", "route"];
  const updateCount = "count = count + excluded.count";
  const countColumns = ["platform", "channel", "count"];
  return {
    active: detailUpsert(
      db,
      "active_days",
      ["day", "install_id", "user_key", "app_version"],
      ["platform", "channel", "cohort_type", "cohort_year", "surface_mask"],
      "surface_mask = surface_mask | excluded.surface_mask",
    ),
    counter: detailUpsert(
      db,
      "counter_days",
      [...keyedByVersion, ...eventDimensions, "result"],
      countColumns,
      updateCount,
    ),
    error: detailUpsert(
      db,
      "error_days",
      [
        ...keyedByVersion,
        ...eventDimensions,
        "error_code",
        "error_kind",
        "retryable",
        "source",
      ],
      countColumns,
      updateCount,
    ),
    timing: detailUpsert(
      db,
      "timing_days",
      [...keyedByVersion, "metric", "feature", "route", "bucket"],
      countColumns,
      updateCount,
    ),
    // 每个日期版本组合只占一条语句，分钟数组作为一个 JSON 参数传入。
    minute: db.prepare(`
      INSERT INTO minute_counts (minute_at, event, feature, result, platform, channel, count)
      SELECT printf('%sT%02d:%02d', ?, (value ->> '$.minute') / 60, (value ->> '$.minute') % 60),
             value ->> '$.event', value ->> '$.feature', value ->> '$.result',
             ?, ?, value ->> '$.count'
      FROM json_each(?)
      WHERE ${ACCEPTED_BATCH}
      ON CONFLICT (minute_at, event, feature, result, platform, channel)
      DO UPDATE SET ${updateCount}
    `),
  };
}

async function userKeys(days: TelemetryDay[], secret: string) {
  const keys = new Set(
    days.flatMap(({ users }) => users.map(({ key }) => key)),
  );
  const mapped = new Map<string, string>();
  if (keys.size === 0) return mapped;
  const encoder = new TextEncoder();
  const hmac = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  for (const key of keys) {
    const digest = await crypto.subtle.sign("HMAC", hmac, encoder.encode(key));
    mapped.set(
      key,
      Array.from(new Uint8Array(digest), (byte) =>
        byte.toString(16).padStart(2, "0"),
      ).join(""),
    );
  }
  return mapped;
}

export async function reportTelemetry(
  request: Request,
  env: Pick<Env, "DB" | "TELEMETRY_LIMIT" | "USER_KEY_SECRET">,
): Promise<Response> {
  const now = new Date();
  const today = campusDay(now);
  const payload = await readJson(request);
  if (payload instanceof Response) return payload;
  if (!validateTelemetryRequest(payload, Number(today.slice(0, 4)))) {
    return invalidPayload();
  }

  const { install_id, batch_id, platform, channel } = payload;
  if (!(await env.TELEMETRY_LIMIT.limit({ key: install_id })).success) {
    return new Response(null, { status: 429 });
  }

  const db = env.DB;
  const tombstone = db.prepare(CHECK_TOMBSTONE).bind(install_id);
  if (await tombstone.first<number>("erased")) return installErased();

  const firstDay = shiftDay(today, -7);
  const lastDay = shiftDay(today, 1);
  const days = payload.days.filter(
    ({ day }) => firstDay <= day && day <= lastDay,
  );
  const keys = await userKeys(days, env.USER_KEY_SECRET);
  const nonce = crypto.randomUUID();
  const gate = [install_id, batch_id, nonce];
  const statements = [
    db
      .prepare(
        `
      INSERT OR IGNORE INTO batches (batch_id, nonce, received_at)
      SELECT ?, ?, ? WHERE ${NO_TOMBSTONE}
    `,
      )
      .bind(batch_id, nonce, now.toISOString(), install_id),
  ];
  const upserts = detailUpserts(db);
  for (const {
    day,
    app_version,
    surfaces,
    users,
    counters,
    errors,
    timings,
    minutes,
  } of days) {
    const surfaceMask =
      (surfaces.includes("gui") ? 1 : 0) |
      (surfaces.includes("command") ? 2 : 0);
    const dimensions = [day, install_id, app_version];
    const hasDailyCounts = counters.length || errors.length || timings.length;
    // 纯分钟续批没有新的按天活跃记录。
    if (users.length === 0 && (!minutes?.length || hasDailyCounts)) {
      statements.push(
        upserts.active.bind(
          day,
          install_id,
          "",
          app_version,
          platform,
          channel,
          "",
          "",
          surfaceMask,
          ...gate,
        ),
      );
    } else {
      for (const { key, cohort_type, cohort_year } of users) {
        const userKey = keys.get(key);
        if (userKey === undefined) throw new Error("缺少用户标识转换结果");
        statements.push(
          upserts.active.bind(
            day,
            install_id,
            userKey,
            app_version,
            platform,
            channel,
            cohort_type,
            cohort_year ?? "",
            surfaceMask,
            ...gate,
          ),
        );
      }
    }
    for (const { event, feature, route, result, count } of counters) {
      statements.push(
        upserts.counter.bind(
          ...dimensions,
          event,
          feature,
          route,
          result,
          platform,
          channel,
          count,
          ...gate,
        ),
      );
    }
    for (const {
      event,
      feature,
      route,
      error_code,
      error_kind,
      retryable,
      source,
      count,
    } of errors) {
      statements.push(
        upserts.error.bind(
          ...dimensions,
          event,
          feature,
          route,
          error_code,
          error_kind,
          Number(retryable),
          source ?? "",
          platform,
          channel,
          count,
          ...gate,
        ),
      );
    }
    for (const { metric, feature, route, bucket, count } of timings) {
      statements.push(
        upserts.timing.bind(
          ...dimensions,
          metric,
          feature,
          route,
          bucket,
          platform,
          channel,
          count,
          ...gate,
        ),
      );
    }
    if (minutes?.length) {
      statements.push(
        upserts.minute.bind(
          day,
          platform,
          channel,
          JSON.stringify(minutes),
          ...gate,
        ),
      );
    }
  }

  // 事务内读出拒收结果，覆盖预查后到达的删除。
  statements.push(tombstone);
  const results = await db.batch<{ erased: number }>(statements);
  if (results.at(-1)?.results[0]?.erased) return installErased();
  return new Response(null, { status: 204 });
}
