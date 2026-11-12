import { campusDay, campusMinute, shiftDay } from "./campus_time";

const JOB = "aggregate";
const DAY_MS = 24 * 60 * 60 * 1000;
const DAILY_BATCH_DAYS = 10;
const LAST_SUCCESS = `(SELECT last_success_day FROM job_state WHERE job = '${JOB}')`;

// L−8 已定稿，L−7 是上次成功之后第一个仍可能变化的日期。
// 首次运行从 D−8 开始；同日重跑保留已定稿结果；更旧的触发不执行写入。
const BOUNDS = `
  WITH bounds AS (
    SELECT MAX(?3, COALESCE(DATE(${LAST_SUCCESS}, '-7 days'), ?2)) AS first_day,
           ?4 AS last_day
    WHERE COALESCE(${LAST_SUCCESS}, ?1) <= ?1
  )
`;
const DAILY_RANGE =
  "day BETWEEN (SELECT first_day FROM bounds) AND (SELECT last_day FROM bounds)";
const MONTHLY_RANGE =
  "month BETWEEN (SELECT SUBSTR(first_day, 1, 7) FROM bounds) AND (SELECT SUBSTR(last_day, 1, 7) FROM bounds)";
const MONTHLY_DETAIL_RANGE = `
  day >= (SELECT DATE(first_day, 'start of month') FROM bounds)
  AND day < (SELECT DATE(last_day, 'start of month', '+1 month') FROM bounds)
`;

const COUNT_KEYS = {
  counter: "day, app_version, event, feature, route, result",
  error:
    "day, app_version, event, feature, route, error_code, error_kind, retryable, source",
  timing: "day, app_version, metric, feature, route, bucket",
};

type Prepare = (sql: string) => D1PreparedStatement;

function activeStatements(prepare: Prepare, monthly: boolean) {
  const period = monthly ? "month" : "day";
  const table = monthly ? "active_monthly" : "active_daily";
  const periodValue = monthly ? "SUBSTR(day, 1, 7)" : "day";
  const detailRange = monthly ? MONTHLY_DETAIL_RANGE : DAILY_RANGE;
  return [
    prepare(
      `DELETE FROM ${table} WHERE ${monthly ? MONTHLY_RANGE : DAILY_RANGE}`,
    ),
    prepare(`
      , dimensions(dimension) AS (
        VALUES ('all'), ('platform'), ('channel'), ('app_version'), ('cohort')
      )
      INSERT INTO ${table} (${period}, dimension, value, users, devices)
      SELECT ${periodValue} AS period, dimension,
        CASE dimension
          WHEN 'platform' THEN platform
          WHEN 'channel' THEN channel
          WHEN 'app_version' THEN app_version
          WHEN 'cohort' THEN CASE WHEN cohort_type = '' THEN ''
                                  ELSE cohort_type || ':' || cohort_year END
          ELSE ''
        END AS value,
        COUNT(DISTINCT NULLIF(user_key, '')),
        COUNT(DISTINCT install_id)
      FROM active_days CROSS JOIN dimensions
      WHERE ${detailRange}
      GROUP BY period, dimension, value
    `),
  ];
}

function countStatements(prepare: Prepare, name: string, key: string) {
  return [
    prepare(`DELETE FROM ${name}_daily WHERE ${DAILY_RANGE}`),
    prepare(`
      INSERT INTO ${name}_daily (${key}, count, devices)
      SELECT ${key}, SUM(count), COUNT(DISTINCT install_id)
      FROM ${name}_days WHERE ${DAILY_RANGE} GROUP BY ${key}
    `),
  ];
}

function* dailyWindows(first: string, last: string) {
  for (let start = first; start <= last;) {
    const end = shiftDay(start, DAILY_BATCH_DAYS - 1);
    yield [start, end < last ? end : last] as const;
    start = shiftDay(end, 1);
  }
}

function nextMonthStart(day: string): string {
  const date = new Date(`${day.slice(0, 7)}-01T00:00:00Z`);
  date.setUTCMonth(date.getUTCMonth() + 1);
  return date.toISOString().slice(0, 10);
}

function activeRetentionStart(day: string): string {
  const date = new Date(`${day}T00:00:00Z`);
  const dayOfMonth = date.getUTCDate();
  date.setUTCMonth(date.getUTCMonth() - 13, 1);
  const lastOfMonth = new Date(date);
  lastOfMonth.setUTCMonth(lastOfMonth.getUTCMonth() + 1, 0);
  date.setUTCDate(Math.min(dayOfMonth, lastOfMonth.getUTCDate()));
  return date.toISOString().slice(0, 10);
}

export async function runAggregation(
  db: D1Database,
  scheduledTime: number,
): Promise<void> {
  const day = campusDay(new Date(scheduledTime));
  const firstDay = shiftDay(day, -8);
  const lastDay = shiftDay(day, 1);
  const activeCutoff = activeRetentionStart(day);
  const countCutoff = shiftDay(day, -90);
  const lastSuccess = await db
    .prepare("SELECT last_success_day FROM job_state WHERE job = ?")
    .bind(JOB)
    .first<string>("last_success_day");
  if (lastSuccess !== null && lastSuccess > day) return;
  const firstUnfinalized =
    lastSuccess === null ? firstDay : shiftDay(lastSuccess, -7);
  const activeFirst =
    activeCutoff > firstUnfinalized ? activeCutoff : firstUnfinalized;
  const countFirst =
    countCutoff > firstUnfinalized ? countCutoff : firstUnfinalized;
  // 用 L 规划批次范围；每批 SQL 再检查 L，较旧的触发不会改写已定稿结果。
  const prepare =
    (start: string, end: string): Prepare =>
    (sql) =>
      db.prepare(BOUNDS + sql).bind(day, firstDay, start, end);
  const timestampCutoff = (days: number) =>
    new Date(scheduledTime - days * DAY_MS);
  const thirtyDayCutoff = timestampCutoff(30);
  const cleanup = (
    table: string,
    column: string,
    cutoff: string,
  ): D1PreparedStatement =>
    db
      .prepare(
        `
        DELETE FROM ${table} WHERE ${column} < ?
          AND COALESCE(${LAST_SUCCESS}, ?) <= ?
      `,
      )
      .bind(cutoff, day, day);

  // 每批只覆盖一张表的有限日期范围，避免漏跑时整个汇总超过 D1 批次时限。
  for (const [start, end] of dailyWindows(activeFirst, lastDay)) {
    await db.batch(activeStatements(prepare(start, end), false));
  }
  for (const [name, key] of Object.entries(COUNT_KEYS)) {
    for (const [start, end] of dailyWindows(countFirst, lastDay)) {
      await db.batch(countStatements(prepare(start, end), name, key));
    }
  }
  for (let start = activeFirst; start <= lastDay;) {
    const next = nextMonthStart(start);
    const end = shiftDay(next, -1);
    await db.batch(
      activeStatements(prepare(start, end < lastDay ? end : lastDay), true),
    );
    start = next;
  }

  // 已写入的聚合可覆盖重算；只有全部汇总成功，才原子地清理和推进 L。
  await db.batch([
    cleanup("active_days", "day", activeCutoff),
    ...Object.keys(COUNT_KEYS).map((name) =>
      cleanup(`${name}_days`, "day", countCutoff),
    ),
    cleanup("batches", "received_at", timestampCutoff(14).toISOString()),
    cleanup("erased_installs", "erased_at", thirtyDayCutoff.toISOString()),
    cleanup("minute_counts", "minute_at", campusMinute(thirtyDayCutoff)),
    db
      .prepare(
        `
        INSERT INTO job_state (job, last_success_day) VALUES (?, ?)
        ON CONFLICT (job) DO UPDATE SET last_success_day = excluded.last_success_day
        WHERE job_state.last_success_day < excluded.last_success_day
      `,
      )
      .bind(JOB, day),
  ]);
}
