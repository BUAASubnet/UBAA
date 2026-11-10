import { campusDay, shiftDay } from "./campus_time";

const JOB = "aggregate";
const DAY_MS = 24 * 60 * 60 * 1000;
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

function countStatements(prepare: Prepare) {
  return Object.entries(COUNT_KEYS).flatMap(([name, key]) => [
    prepare(`DELETE FROM ${name}_daily WHERE ${DAILY_RANGE}`),
    prepare(`
      INSERT INTO ${name}_daily (${key}, count, devices)
      SELECT ${key}, SUM(count), COUNT(DISTINCT install_id)
      FROM ${name}_days WHERE ${DAILY_RANGE} GROUP BY ${key}
    `),
  ]);
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
  const prepare =
    (cutoff: string): Prepare =>
    (sql) =>
      db.prepare(BOUNDS + sql).bind(day, firstDay, cutoff, lastDay);
  const prepareActive = prepare(activeCutoff);
  const timestampCutoff = (days: number) =>
    new Date(scheduledTime - days * DAY_MS).toISOString();
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

  // 先覆盖整段聚合，再清理其明细。任一语句失败时，D1 回滚整个 batch。
  await db.batch([
    ...activeStatements(prepareActive, false),
    ...countStatements(prepare(countCutoff)),
    ...activeStatements(prepareActive, true),
    cleanup("active_days", "day", activeCutoff),
    ...Object.keys(COUNT_KEYS).map((name) =>
      cleanup(`${name}_days`, "day", countCutoff),
    ),
    cleanup("batches", "received_at", timestampCutoff(14)),
    cleanup("erased_installs", "erased_at", timestampCutoff(30)),
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
