import { env } from "cloudflare:workers";
import { beforeAll, expect, it } from "vitest";
import { campusDay } from "../src/campus_time";
import { reportTelemetry } from "../src/telemetry";
import {
  createBatch,
  erase,
  migrate,
  postTelemetry,
  relativeDay,
  syntheticKey,
  uploadRequest,
} from "./telemetry_support";

beforeAll(migrate);

const detailTables = [
  "active_days",
  "counter_days",
  "error_days",
  "timing_days",
];
async function detailCounts(installId: string) {
  return Promise.all(
    detailTables.map((table) =>
      env.DB.prepare(
        `SELECT COUNT(*) AS rows FROM ${table} WHERE install_id = ?`,
      )
        .bind(installId)
        .first<number>("rows"),
    ),
  );
}

it.each(["顺序", "并发"])("%s重发同一批次只累加一次", async (order) => {
  const payload = createBatch();
  let statuses: number[];
  if (order === "顺序") {
    statuses = [
      (await postTelemetry(payload)).status,
      (await postTelemetry(payload)).status,
    ];
  } else {
    statuses = (
      await Promise.all([postTelemetry(payload), postTelemetry(payload)])
    ).map(({ status }) => status);
  }
  expect(statuses).toEqual([204, 204]);
  const counts = await Promise.all(
    detailTables
      .slice(1)
      .map((table) =>
        env.DB.prepare(`SELECT count FROM ${table} WHERE install_id = ?`)
          .bind(payload.install_id)
          .first<number>("count"),
      ),
  );
  expect(counts).toEqual([3, 1, 2]);
  expect(
    await env.DB.prepare("SELECT LENGTH(nonce) FROM batches WHERE batch_id = ?")
      .bind(payload.batch_id)
      .first<number>("LENGTH(nonce)"),
  ).toBe(36);
});

it("仅接受校园日期窗口中的条目，窗口两端均包含", async () => {
  const payload = createBatch();
  const [day] = payload.days;
  payload.days = [-8, -7, 0, 1, 2].map((offset) => ({
    ...day,
    day: relativeDay(offset),
  }));
  expect((await postTelemetry(payload)).status).toBe(204);
  const rows = await env.DB.prepare(
    "SELECT day FROM active_days WHERE install_id = ? ORDER BY day",
  )
    .bind(payload.install_id)
    .all<{ day: string }>();
  expect(rows.results.map(({ day }) => day)).toEqual(
    [-7, 0, 1].map(relativeDay),
  );
  expect(await detailCounts(payload.install_id)).toEqual([3, 3, 3, 3]);
});

it("只落库 HMAC 用户标识，保留版本和合并入口", async () => {
  const payload = createBatch();
  const [day] = payload.days;
  const key = await syntheticKey();
  day.users = [{ key, cohort_type: "undergrad", cohort_year: 2024 }];
  expect((await postTelemetry(payload)).status).toBe(204);
  const next = { ...day, surfaces: ["command"] };
  const upgrade = { ...next, app_version: "2.1.0" };
  expect(
    (
      await postTelemetry({
        ...payload,
        batch_id: crypto.randomUUID(),
        days: [next, upgrade],
      })
    ).status,
  ).toBe(204);

  const encoder = new TextEncoder();
  const secret = await crypto.subtle.importKey(
    "raw",
    encoder.encode(env.USER_KEY_SECRET),
    {
      name: "HMAC",
      hash: "SHA-256",
    },
    false,
    ["verify"],
  );
  const rows = await env.DB.prepare(
    "SELECT app_version, user_key, cohort_type, cohort_year, surface_mask FROM active_days WHERE install_id = ? ORDER BY app_version",
  )
    .bind(payload.install_id)
    .all<{
      app_version: string;
      user_key: string;
      cohort_type: string;
      cohort_year: number;
      surface_mask: number;
    }>();
  const safeRows = [];
  for (const { user_key, ...safe } of rows.results) {
    const digest = Uint8Array.from(user_key.match(/../g) ?? [], (hex) =>
      Number.parseInt(hex, 16),
    );
    expect(user_key !== key).toBe(true);
    expect(
      await crypto.subtle.verify("HMAC", secret, digest, encoder.encode(key)),
    ).toBe(true);
    safeRows.push(safe);
  }
  expect(safeRows).toEqual([
    {
      app_version: "2.0.0",
      cohort_type: "undergrad",
      cohort_year: 2024,
      surface_mask: 3,
    },
    {
      app_version: "2.1.0",
      cohort_type: "undergrad",
      cohort_year: 2024,
      surface_mask: 2,
    },
  ]);
});

it.each(["上报在先", "删除在先"])("%s均不保留旧安装明细", async (order) => {
  const payload = createBatch();
  if (order === "上报在先") {
    expect((await postTelemetry(payload)).status).toBe(204);
    expect(await detailCounts(payload.install_id)).toEqual([1, 1, 1, 1]);
  }
  expect((await erase(payload.install_id)).status).toBe(204);
  expect((await erase(payload.install_id)).status).toBe(204);
  const rejected = await postTelemetry({
    ...payload,
    batch_id: crypto.randomUUID(),
  });
  expect(rejected.status).toBe(410);
  expect(await rejected.json()).toBe("install_erased");
  expect(await detailCounts(payload.install_id)).toEqual([0, 0, 0, 0]);
});

it("明细写入失败回滚批次，故障消失后同一批次可以提交", async () => {
  const payload = createBatch();
  await env.DB.prepare(
    `CREATE TRIGGER step_three_abort_counter
    BEFORE INSERT ON counter_days
    BEGIN SELECT RAISE(ABORT, 'synthetic D1 failure'); END`,
  ).run();
  try {
    const failed = await postTelemetry(payload);
    expect(failed.status).toBe(500);
    expect(await failed.text()).toBe("");
    const recorded = await env.DB.prepare(
      "SELECT 1 FROM batches WHERE batch_id = ?",
    )
      .bind(payload.batch_id)
      .first();
    expect(recorded).toBeNull();
    expect(await detailCounts(payload.install_id)).toEqual([0, 0, 0, 0]);
  } finally {
    await env.DB.prepare("DROP TRIGGER step_three_abort_counter").run();
  }
  expect((await postTelemetry(payload)).status).toBe(204);
  expect(await detailCounts(payload.install_id)).toEqual([1, 1, 1, 1]);
});

it("预查未命中后删除先提交，迟到的上报返回 410 且不写入", async () => {
  const payload = createBatch();
  let erasedBeforeBatch = false;
  const db = new Proxy(env.DB, {
    get(target, key, receiver) {
      if (key === "batch") {
        return async (statements: D1PreparedStatement[]) => {
          expect((await erase(payload.install_id)).status).toBe(204);
          erasedBeforeBatch = true;
          return target.batch(statements);
        };
      }
      const value = Reflect.get(target, key, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const rejected = await reportTelemetry(uploadRequest(payload), {
    DB: db,
    USER_KEY_SECRET: env.USER_KEY_SECRET,
    TELEMETRY_LIMIT: env.TELEMETRY_LIMIT,
  });
  expect(erasedBeforeBatch).toBe(true);
  expect(rejected.status).toBe(410);
  expect(await rejected.json()).toBe("install_erased");
  expect(await detailCounts(payload.install_id)).toEqual([0, 0, 0, 0]);
  const recorded = await env.DB.prepare(
    "SELECT 1 FROM batches WHERE batch_id = ?",
  )
    .bind(payload.batch_id)
    .first();
  expect(recorded).toBeNull();
});

it("删除中途失败时保留原明细且不写入墓碑", async () => {
  const payload = createBatch();
  expect((await postTelemetry(payload)).status).toBe(204);
  await env.DB.prepare(
    `CREATE TRIGGER step_three_abort_timing
    BEFORE DELETE ON timing_days
    BEGIN SELECT RAISE(ABORT, 'synthetic D1 failure'); END`,
  ).run();
  try {
    expect((await erase(payload.install_id)).status).toBe(500);
    expect(await detailCounts(payload.install_id)).toEqual([1, 1, 1, 1]);
    const tombstone = await env.DB.prepare(
      "SELECT 1 FROM erased_installs WHERE install_id = ?",
    )
      .bind(payload.install_id)
      .first();
    expect(tombstone).toBeNull();
  } finally {
    await env.DB.prepare("DROP TRIGGER step_three_abort_timing").run();
  }
  expect((await erase(payload.install_id)).status).toBe(204);
  expect(await detailCounts(payload.install_id)).toEqual([0, 0, 0, 0]);
});

it("没有绑定账号时保留设备活跃，缺失维度写入空字符串", async () => {
  const payload = createBatch();
  expect((await postTelemetry(payload)).status).toBe(204);
  const device = await env.DB.prepare(
    "SELECT user_key, cohort_type, cohort_year, surface_mask FROM active_days WHERE install_id = ?",
  )
    .bind(payload.install_id)
    .first();
  expect(device).toEqual({
    user_key: "",
    cohort_type: "",
    cohort_year: "",
    surface_mask: 1,
  });
  const failure = await env.DB.prepare(
    "SELECT source, retryable FROM error_days WHERE install_id = ?",
  )
    .bind(payload.install_id)
    .first();
  expect(failure).toEqual({ source: "", retryable: 0 });
});

it("校园日期在北京时间午夜切换", () => {
  expect(campusDay(new Date("2026-12-31T15:59:59Z"))).toBe("2026-12-31");
  expect(campusDay(new Date("2026-12-31T16:00:00Z"))).toBe("2027-01-01");
});
