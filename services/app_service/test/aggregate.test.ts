import {
  createExecutionContext,
  createScheduledController,
} from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeAll, beforeEach, expect, it, vi } from "vitest";
import worker from "../src/index";
import { reportTelemetry } from "../src/telemetry";
import {
  createBatch,
  erase,
  migrate,
  uploadRequest,
} from "./telemetry_support";

const countTables = ["counter", "error", "timing"];
const detailTables = [
  "active_days",
  ...countTables.map((name) => `${name}_days`),
];
const outputTables = [
  "active_daily",
  "active_monthly",
  ...countTables.map((name) => `${name}_daily`),
];

beforeAll(migrate);
beforeEach(async () => {
  await env.DB.batch(
    [
      ...detailTables,
      ...outputTables,
      "job_state",
      "batches",
      "erased_installs",
      "minute_counts",
    ].map((table) => env.DB.prepare(`DELETE FROM ${table}`)),
  );
});

async function scheduled(instant: string) {
  const controller = createScheduledController({
    scheduledTime: Date.parse(instant),
    cron: "0 19 * * *",
  });
  const handler: ExportedHandler<Env> = worker;
  if (!handler.scheduled) throw new Error("Worker 未接线定时汇总");
  await handler.scheduled(controller, env, createExecutionContext());
}

function active(
  day: string,
  install: string,
  user = "",
  version = "2.0.0",
  platform = "linux",
  channel = "github",
) {
  return env.DB.prepare(
    "INSERT INTO active_days VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)",
  ).bind(
    day,
    install,
    user,
    version,
    platform,
    channel,
    user ? "undergrad" : "",
    user ? 2024 : "",
  );
}

function minute(minuteAt: string) {
  return env.DB.prepare(
    "INSERT INTO minute_counts VALUES (?, 'feature_loaded', 'schedule', 'success', 'linux', 'github', 1)",
  ).bind(minuteAt);
}

function lastSuccess() {
  return env.DB.prepare("SELECT last_success_day FROM job_state").first<string>(
    "last_success_day",
  );
}

async function groups(period: string) {
  const [table, key] =
    period.length === 7 ? ["active_monthly", "month"] : ["active_daily", "day"];
  const { results } = await env.DB.prepare(
    `SELECT dimension, value, users, devices FROM ${table} WHERE ${key} = ? ORDER BY dimension, value`,
  )
    .bind(period)
    .all<{
      dimension: string;
      value: string;
      users: number;
      devices: number;
    }>();
  return Object.fromEntries(
    results.map(({ dimension, value, users, devices }) => [
      `${dimension}/${value}`,
      [users, devices],
    ]),
  );
}

it("首次运行按计划时间覆盖十个校园日及相交月份，并独立去重各维度", async () => {
  await env.DB.batch([
    active("2025-11-21", "old"),
    active("2025-11-22", "first"),
    active("2025-12-02", "future"),
    active("2025-11-30", "device-a", "shared"),
    active("2025-11-30", "device-a", "shared", "2.1.0"),
    active("2025-11-30", "device-b", "shared", "2.0.0", "ios", "app_store"),
    active("2025-11-30", "device-c"),
    active("2025-12-01", "last"),
  ]);

  // UTC 29 日 19:00 是校园 30 日 03:00。
  await scheduled("2025-11-29T19:00:00Z");
  expect(await lastSuccess()).toBe("2025-11-30");
  expect(await groups("2025-11-21")).toEqual({});
  expect((await groups("2025-11-22"))["all/"]).toEqual([0, 1]);
  expect((await groups("2025-12-01"))["all/"]).toEqual([0, 1]);
  expect(await groups("2025-12-02")).toEqual({});
  const day = {
    "all/": [1, 3],
    "platform/ios": [1, 1],
    "platform/linux": [1, 2],
    "channel/app_store": [1, 1],
    "channel/github": [1, 2],
    "app_version/2.0.0": [1, 3],
    "app_version/2.1.0": [1, 1],
    "cohort/undergrad:2024": [1, 2],
    "cohort/": [0, 1],
  };
  expect(await groups("2025-11-30")).toEqual(day);
  expect((await groups("2025-11"))["all/"]).toEqual([1, 5]);
  expect((await groups("2025-12"))["all/"]).toEqual([0, 2]);

  await scheduled("2025-11-29T19:00:00Z");
  expect(await groups("2025-11-30")).toEqual(day);
});

it("月底第七天晚间上报进入日表和月表；八日定稿后删除不改写旧结果", async () => {
  await scheduled("2025-02-06T19:00:00Z");
  const batch = createBatch();
  batch.days[0].day = "2025-01-31";
  vi.setSystemTime(new Date("2025-02-07T15:45:00Z"));
  try {
    expect((await reportTelemetry(uploadRequest(batch), env)).status).toBe(204);
  } finally {
    vi.useRealTimers();
  }
  await scheduled("2025-02-07T19:00:00Z");
  expect((await groups("2025-01-31"))["all/"]).toEqual([0, 1]);
  expect((await groups("2025-01"))["all/"]).toEqual([0, 1]);

  expect((await erase(batch.install_id)).status).toBe(204);
  await scheduled("2025-02-07T19:00:00Z");
  await scheduled("2025-02-08T19:00:00Z");
  expect((await groups("2025-01-31"))["all/"]).toEqual([0, 1]);
  expect((await groups("2025-01"))["all/"]).toEqual([0, 1]);
});

it("漏跑一天补算错过的定稿日期和月份，忽略晚到的旧触发", async () => {
  await scheduled("2025-02-06T19:00:00Z");
  const batch = createBatch();
  batch.days[0].day = "2025-01-31";
  vi.setSystemTime(new Date("2025-02-07T15:45:00Z"));
  try {
    expect((await reportTelemetry(uploadRequest(batch), env)).status).toBe(204);
  } finally {
    vi.useRealTimers();
  }
  // 2 月 8 日漏跑；2 月 9 日正常窗口起点本应是 2 月 1 日。
  await scheduled("2025-02-08T19:00:00Z");
  expect((await groups("2025-01-31"))["all/"]).toEqual([0, 1]);
  expect((await groups("2025-01"))["all/"]).toEqual([0, 1]);
  await env.DB.prepare(
    "DELETE FROM active_days WHERE day = '2025-01-31'",
  ).run();
  await minute("2024-12-01T00:00").run();
  await scheduled("2025-02-07T19:00:00Z");
  expect(await lastSuccess()).toBe("2025-02-09");
  expect((await groups("2025-01"))["all/"]).toEqual([0, 1]);
  expect(await column("minute_counts", "minute_at")).toEqual([
    "2024-12-01T00:00",
  ]);
});

it("计数、错误和耗时按主键聚合；删除未定稿设备后旧分组消失", async () => {
  const first = createBatch();
  const second = createBatch();
  const other = createBatch();
  for (const batch of [first, second, other]) batch.days[0].day = "2025-05-01";
  other.days[0].app_version = "3.0.0";
  vi.setSystemTime(new Date("2025-05-01T05:00:00Z"));
  try {
    for (const batch of [first, second, other]) {
      expect((await reportTelemetry(uploadRequest(batch), env)).status).toBe(
        204,
      );
    }
  } finally {
    vi.useRealTimers();
  }
  await scheduled("2025-05-01T19:00:00Z");
  const summaries = () =>
    Promise.all(
      countTables.map(
        async (name) =>
          (
            await env.DB.prepare(
              `SELECT app_version, count, devices FROM ${name}_daily ORDER BY app_version`,
            ).all<{ app_version: string; count: number; devices: number }>()
          ).results,
      ),
    );
  const row = (version: string, count: number, devices: number) => ({
    app_version: version,
    count,
    devices,
  });
  expect(await summaries()).toEqual(
    [3, 1, 2].map((count) => [
      row("2.0.0", count * 2, 2),
      row("3.0.0", count, 1),
    ]),
  );

  expect((await erase(second.install_id)).status).toBe(204);
  expect((await erase(other.install_id)).status).toBe(204);
  await scheduled("2025-05-02T19:00:00Z");
  expect(await summaries()).toEqual(
    [3, 1, 2].map((count) => [row("2.0.0", count, 1)]),
  );
  expect((await groups("2025-05-01"))["all/"]).toEqual([0, 1]);
  expect((await groups("2025-05"))["all/"]).toEqual([0, 1]);
  expect((await groups("2025-05"))["app_version/3.0.0"]).toBeUndefined();
});

function insertCounters(day: string) {
  return [
    env.DB.prepare(
      "INSERT INTO counter_days VALUES (?, 'test', '2.0.0', 'feature_loaded', 'schedule', 'direct', 'success', 'linux', 'github', 3)",
    ).bind(day),
    env.DB.prepare(
      "INSERT INTO error_days VALUES (?, 'test', '2.0.0', 'feature_failed', 'grades', 'webvpn', 'parse_error', 'upstream', 0, '', 'linux', 'github', 1)",
    ).bind(day),
    env.DB.prepare(
      "INSERT INTO timing_days VALUES (?, 'test', '2.0.0', 'feature_load', 'schedule', 'direct', 'lt_1000', 'linux', 'github', 2)",
    ).bind(day),
  ];
}

async function column<T extends string | number = string>(
  table: string,
  name: string,
) {
  const { results } = await env.DB.prepare(
    `SELECT DISTINCT ${name} AS value FROM ${table} ORDER BY ${name}`,
  ).all<{ value: T }>();
  return results.map(({ value }) => value);
}

it("长期漏跑按各表保留期截断日表，清理前用完整月明细汇总", async () => {
  await scheduled("2024-01-31T19:00:00Z");
  await env.DB.batch([
    active("2024-01-31", "older-month"),
    active("2024-02-28", "expired-day"),
    active("2024-02-29", "boundary-day"),
    active("2024-12-31", "newer-day"),
    ...insertCounters("2024-12-30"),
    ...insertCounters("2024-12-31"),
    env.DB.prepare(
      "INSERT INTO active_daily VALUES ('2024-02-28', 'all', '', 0, 7)",
    ),
    env.DB.prepare(
      "INSERT INTO active_monthly VALUES ('2024-01', 'all', '', 0, 9)",
    ),
    env.DB.prepare(
      "INSERT INTO batches VALUES ('old', 'synthetic', '2025-03-16T18:59:59.999Z'), ('keep', 'synthetic', '2025-03-16T19:00:00.000Z')",
    ),
    env.DB.prepare(
      "INSERT INTO erased_installs VALUES ('old', '2025-02-28T18:59:59.999Z'), ('keep', '2025-02-28T19:00:00.000Z')",
    ),
    minute("2025-03-01T02:59"),
    minute("2025-03-01T03:00"),
    minute("2025-03-01T03:01"),
  ]);

  // 2025-03-31 向前 13 个自然月落在闰年 2 月最后一天。
  await scheduled("2025-03-30T19:00:00Z");
  expect(await lastSuccess()).toBe("2025-03-31");
  expect((await groups("2024-02-28"))["all/"]).toEqual([0, 7]);
  expect((await groups("2024-02-29"))["all/"]).toEqual([0, 1]);
  expect((await groups("2024-01"))["all/"]).toEqual([0, 9]);
  expect((await groups("2024-02"))["all/"]).toEqual([0, 2]);
  expect(await column("active_days", "day")).toEqual([
    "2024-02-29",
    "2024-12-31",
  ]);
  for (const name of countTables) {
    expect(await column(`${name}_days`, "day")).toEqual(["2024-12-31"]);
    expect(await column(`${name}_daily`, "day")).toEqual(["2024-12-31"]);
  }
  expect(await column("batches", "batch_id")).toEqual(["keep"]);
  expect(await column("erased_installs", "install_id")).toEqual(["keep"]);
  expect(await column("minute_counts", "minute_at")).toEqual([
    "2025-03-01T03:00",
    "2025-03-01T03:01",
  ]);
});

it.each([
  ["INSERT", "active_monthly"],
  ["DELETE", "batches"],
  ["DELETE", "minute_counts"],
  ["UPDATE", "job_state"],
])(
  "%s %s 失败保留已完成的汇总，跳过清理与成功日期更新，下一轮覆盖重算",
  async (operation, table) => {
    await scheduled("2025-04-30T19:00:00Z");
    await env.DB.batch([
      active("2025-04-30", "previous-month-device"),
      active("2025-05-01", "current-device"),
      active("2024-01-01", "expired-device"),
      ...insertCounters("2024-12-31"),
      ...insertCounters("2025-05-01"),
      env.DB.prepare(
        "INSERT INTO active_monthly VALUES ('2025-05', 'all', '', 0, 7)",
      ),
      env.DB.prepare(
        "INSERT INTO batches VALUES ('old', 'synthetic', '2025-01-01T00:00:00.000Z')",
      ),
      env.DB.prepare(
        "INSERT INTO erased_installs VALUES ('old', '2025-01-01T00:00:00.000Z')",
      ),
      minute("2025-01-01T00:00"),
      env.DB
        .prepare(`CREATE TRIGGER fail_aggregate BEFORE ${operation} ON ${table}
      ${table === "active_monthly" ? "WHEN NEW.month = '2025-05'" : ""}
      BEGIN SELECT RAISE(ABORT, '合成数据库故障'); END`),
    ]);
    try {
      await expect(scheduled("2025-05-01T19:00:00Z")).rejects.toThrow(
        "统计汇总任务失败",
      );
      expect(await lastSuccess()).toBe("2025-05-01");
      expect((await groups("2025-05-01"))["all/"]).toEqual([0, 1]);
      expect((await groups("2025-04"))["all/"]).toEqual([0, 1]);
      expect((await groups("2025-05"))["all/"]).toEqual([
        0,
        table === "active_monthly" ? 7 : 1,
      ]);
      expect(await column("active_days", "day")).toEqual([
        "2024-01-01",
        "2025-04-30",
        "2025-05-01",
      ]);
      for (const name of countTables) {
        expect(await column(`${name}_days`, "day")).toEqual([
          "2024-12-31",
          "2025-05-01",
        ]);
      }
      expect(await column("batches", "batch_id")).toEqual(["old"]);
      expect(await column("erased_installs", "install_id")).toEqual(["old"]);
      expect(await column("minute_counts", "minute_at")).toEqual([
        "2025-01-01T00:00",
      ]);
    } finally {
      await env.DB.prepare("DROP TRIGGER fail_aggregate").run();
    }
    await scheduled("2025-05-02T19:00:00Z");
    expect(await lastSuccess()).toBe("2025-05-03");
    expect((await groups("2025-05-01"))["all/"]).toEqual([0, 1]);
    expect((await groups("2025-05"))["all/"]).toEqual([0, 1]);
    expect(
      await Promise.all(
        countTables.map((name) => column<number>(`${name}_daily`, "count")),
      ),
    ).toEqual([[3], [1], [2]]);
    expect(await column("active_days", "day")).toEqual([
      "2025-04-30",
      "2025-05-01",
    ]);
    expect(await column("batches", "batch_id")).toEqual([]);
    expect(await column("erased_installs", "install_id")).toEqual([]);
    expect(await column("minute_counts", "minute_at")).toEqual([]);
  },
);
