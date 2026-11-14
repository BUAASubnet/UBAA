import { afterAll, beforeAll, expect, it } from "vitest";
import { Database } from "../src/database";

const db = new Database(process.env.TEST_DATABASE_URL!);
beforeAll(async () => {
  await db
    .prepare(
      "CREATE TABLE IF NOT EXISTS transaction_probe (id TEXT PRIMARY KEY)",
    )
    .run();
  await db.prepare("DELETE FROM transaction_probe").run();
});
afterAll(() => db.close());
it("批次后半段失败时 PostgreSQL 回滚前半段写入", async () => {
  await expect(
    db.batch([
      db.prepare("INSERT INTO transaction_probe VALUES ($1)").bind("same"),
      db.prepare("INSERT INTO transaction_probe VALUES ($1)").bind("same"),
    ]),
  ).rejects.toThrow();
  expect(
    await db
      .prepare("SELECT COUNT(*)::int AS n FROM transaction_probe")
      .first("n"),
  ).toBe(0);
});
