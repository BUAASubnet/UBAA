import { execFileSync } from "node:child_process";
import { beforeAll, expect, it } from "vitest";
import { env, migrate } from "./runtime";
beforeAll(migrate);
interface Panel {
  title: string;
  panels?: Panel[];
  targets?: { rawSql: string }[];
}
const dashboard = JSON.parse(
  execFileSync("python3", ["../../scripts/release/app_service_dashboard.py"], {
    encoding: "utf8",
  }),
);
const panels: Panel[] = dashboard.panels.flatMap((panel: Panel) => [
  panel,
  ...(panel.panels ?? []),
]);
for (const panel of panels) {
  for (const target of panel.targets ?? []) {
    it(`PostgreSQL 看板查询可运行：${panel.title}`, async () => {
      const sql = target.rawSql
        .replaceAll(
          "${__from}",
          String(Date.parse("2026-11-01T00:00:00+08:00")),
        )
        .replaceAll("${__to}", String(Date.parse("2026-11-14T00:00:00+08:00")))
        .replaceAll("${platform:csv}", "linux")
        .replaceAll("${channel:csv}", "github");
      await expect(env.DB.prepare(sql).all()).resolves.toBeDefined();
    });
  }
}

function query(
  title: string,
  start: number,
  end: number,
  platform = "",
  channel = "",
) {
  return panels
    .find((panel) => panel.title === title)!
    .targets![0].rawSql.replaceAll("${__from}", String(start))
    .replaceAll("${__to}", String(end))
    .replaceAll("${platform:csv}", platform)
    .replaceAll("${channel:csv}", channel);
}
it("整月分钟曲线按小时分桶，补零并保留总量", async () => {
  await env.DB.prepare("TRUNCATE minute_counts").run();
  await env.DB.prepare(
    `INSERT INTO minute_counts
    SELECT to_char(t, 'YYYY-MM-DD"T"HH24:MI'), event, 'schedule', 'success', 'android', 'github', 1
    FROM generate_series('2025-01-01'::timestamp, '2025-01-01 23:59'::timestamp, interval '1 minute') t
    CROSS JOIN (VALUES ('feature_loaded'), ('auth_started')) e(event)`,
  ).run();
  const start = Date.parse("2025-01-01T00:00:00+08:00");
  for (const title of ["功能使用曲线", "登录曲线"]) {
    const { results } = await env.DB.prepare(
      query(title, start, start + 30 * 86400000),
    ).all<Record<string, number | Date>>();
    expect(results).toHaveLength(721);
    const totals = results.map((row) =>
      Object.entries(row)
        .filter(([key]) => key !== "time")
        .reduce((sum, [, value]) => sum + Number(value), 0),
    );
    expect(totals.reduce((a, b) => a + b, 0)).toBe(1440);
    expect(totals.slice(24).every((value) => value === 0)).toBe(true);
  }
});
it("分钟曲线跨日分桶与平台和渠道过滤", async () => {
  await env.DB.prepare("TRUNCATE minute_counts").run();
  const start = Date.parse("2025-01-01T23:57:00+08:00");
  for (const [minute, platform, channel, count] of [
    [0, "android", "github", 2],
    [3, "android", "github", 3],
    [4, "ios", "app_store", 7],
  ] as const) {
    const at = new Date(start + (minute + 480) * 60000)
      .toISOString()
      .slice(0, 16);
    await env.DB.prepare(
      "INSERT INTO minute_counts VALUES ($1, 'feature_loaded', 'schedule', 'success', $2, $3, $4)",
    )
      .bind(at, platform, channel, count)
      .run();
  }
  for (const [duration, bucket] of [
    [300, 1],
    [1440, 5],
    [4320, 10],
    [43200, 60],
    [57600, 1440],
  ]) {
    const end = start + duration * 60000;
    const { results } = await env.DB.prepare(
      query("功能使用曲线", start, end, "android", "github"),
    ).all<Record<string, number | Date>>();
    const width = bucket * 60000;
    const first = Math.floor((start + 28800000) / width) * width - 28800000;
    expect(results.map((row) => Number(row.time))).toEqual(
      Array.from({ length: results.length }, (_, i) => first + i * width),
    );
    expect(
      results.reduce(
        (sum, row) =>
          sum +
          Object.entries(row)
            .filter(([key]) => key !== "time")
            .reduce((n, [, v]) => n + Number(v), 0),
        0,
      ),
    ).toBe(5);
  }
});
