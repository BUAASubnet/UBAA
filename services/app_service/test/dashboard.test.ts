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

it("维护看板按版本和错误维度筛选，样本不改变失败次数", async () => {
  const maintenance = JSON.parse(
    execFileSync(
      "python3",
      ["../../scripts/release/app_service_dashboard.py", "--maintenance"],
      { encoding: "utf8" },
    ),
  );
  const start = Date.parse("2026-11-01T00:00:00+08:00");
  const variables = {
    "${__from}": String(start),
    "${__to}": String(start + 86400000),
    "${app_version:sqlstring}": "'2.0.0+2008'",
    "${feature:sqlstring}": "'cgyy'",
    "${route:sqlstring}": "'webvpn'",
    "${error_code:sqlstring}": "'business_rejected'",
  };
  function sql(title: string) {
    const panel = (maintenance.panels as Panel[]).find(
      (item) => item.title === title,
    )!;
    return Object.entries(variables).reduce(
      (raw, [key, value]) => raw.replaceAll(key, value),
      panel.targets![0].rawSql,
    );
  }

  await env.DB.prepare(
    `
    INSERT INTO error_days
      (day, install_id, app_version, event, feature, route, error_code, error_kind, retryable, source, platform, channel, count)
    VALUES
      ('2026-11-01','a','2.0.0+2008','feature_failed','cgyy','webvpn','business_rejected','upstream',0,'core-a','ios','app_store',7),
      ('2026-11-01','a','2.0.0+2008','feature_failed','cgyy','webvpn','business_rejected','upstream',1,'core-a','ios','app_store',2),
      ('2026-11-01','b','2.0.0+2008','feature_failed','cgyy','webvpn','business_rejected','upstream',0,'','ios','app_store',3),
      ('2026-11-01','c','2.0.0+2007','feature_failed','cgyy','webvpn','business_rejected','upstream',0,'','ios','app_store',20),
      ('2026-11-01','d','2.0.0+2008','feature_failed','cgyy','direct','business_rejected','upstream',0,'','ios','app_store',10),
      ('2026-11-01','a','2.0.0+2008','ui_error_shown','cgyy','webvpn','business_rejected','upstream',0,'core-a','ios','app_store',7);
    INSERT INTO error_samples VALUES
      ('2026-11-01','a','2.0.0+2008','feature_failed','cgyy','webvpn','business_rejected','core-a',
       '{"stage":"response","reason":"business_rejected","status":200,"upstream_code":42}');
    INSERT INTO counter_days
      (day,install_id,app_version,event,feature,route,result,platform,channel,count)
    VALUES
      ('2026-11-01','a','2.0.0+2008','write_completed','cgyy','webvpn','success','ios','app_store',5),
      ('2026-11-01','a','2.0.0+2008','write_completed','cgyy','webvpn','failure','ios','app_store',2),
      ('2026-11-01','a','2.0.0+2007','write_completed','cgyy','webvpn','failure','ios','app_store',9)
  `,
  ).run();
  const counts = await env.DB.prepare(sql("错误明细")).all<
    Record<string, string>
  >();
  expect(counts.results.reduce((n, row) => n + Number(row["次数"]), 0)).toBe(
    12,
  );
  const writes = await env.DB.prepare(sql("写入结果")).all<
    Record<string, number>
  >();
  expect(writes.results).toHaveLength(1);
  expect(Number(writes.results[0]["操作次数"])).toBe(7);
  expect(Number(writes.results[0]["失败次数"])).toBe(2);
  const samples = await env.DB.prepare(sql("安全诊断样本")).all();
  expect(samples.results).toHaveLength(1);
  expect(samples.results[0]).toMatchObject({
    阶段: "response",
    原因: "business_rejected",
    "HTTP 状态": "200",
    上游业务码: "42",
  });
  expect(samples.results[0]).not.toHaveProperty("install_id");
  expect(
    panels
      .flatMap((panel) => panel.targets ?? [])
      .map((item) => item.rawSql)
      .join(" "),
  ).not.toContain("error_samples");
  const absent = await env.DB.prepare(
    sql("安全诊断样本").replaceAll("'2.0.0+2008'", "'2.0.0+2007'"),
  ).all();
  expect(absent.results).toEqual([]);
});
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
it("功能热度和去重设备只取主动打开，功能加载成功率只取读取", async () => {
  await env.DB.prepare(
    `INSERT INTO counter_days VALUES
    ('2025-03-03','a','2.0.0','feature_opened','schedule','none','success','linux','github',3),
    ('2025-03-03','a','2.0.1','feature_opened','schedule','none','success','linux','github',1),
    ('2025-03-03','b','2.0.0','feature_loaded','schedule','direct','failure','linux','github',6),
    ('2025-03-03','b','2.0.0','feature_loaded','schedule','direct','empty','linux','github',2)`,
  ).run();
  const start = Date.parse("2025-03-03T00:00:00+08:00");
  const rows = async (title: string) =>
    (await env.DB.prepare(query(title, start, start + 86399999)).all()).results;
  expect(await rows("功能热度")).toMatchObject([{ 打开次数: 4 }]);
  expect(await rows("功能明细")).toMatchObject([
    { 使用设备: 1, 打开次数: 4, 功能加载成功率: 0.25, 失败: 6 },
  ]);
});

it("整月分钟曲线按小时分桶，补零并保留总量", async () => {
  await env.DB.prepare("TRUNCATE minute_counts").run();
  await env.DB.prepare(
    `INSERT INTO minute_counts
    SELECT to_char(t, 'YYYY-MM-DD"T"HH24:MI'), event, 'schedule', 'success', 'android', 'github', 1
    FROM generate_series('2025-01-01'::timestamp, '2025-01-01 23:59'::timestamp, interval '1 minute') t
    CROSS JOIN (VALUES ('feature_opened'), ('auth_started')) e(event)`,
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
      "INSERT INTO minute_counts VALUES ($1, 'feature_opened', 'schedule', 'success', $2, $3, $4)",
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
