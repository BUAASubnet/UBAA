import pg from "pg";

// 汇总计数使用 JavaScript 安全整数；写入计数由 API Schema 限制。
pg.types.setTypeParser(20, (value) => {
  const number = Number(value);
  if (!Number.isSafeInteger(number))
    throw new Error("统计计数超出安全整数范围");
  return number;
});

export class Statement {
  constructor(
    readonly db: Database,
    readonly sql: string,
    readonly values: unknown[] = [],
  ) {}
  bind(...values: unknown[]) {
    return new Statement(this.db, this.sql, values);
  }
  async all<T = Record<string, unknown>>() {
    const result = await this.db.pool.query(this.sql, this.values);
    return { results: result.rows as T[] };
  }
  async first<T = Record<string, unknown>>(column?: string): Promise<T | null> {
    const { results } = await this.all<Record<string, unknown>>();
    return ((column ? results[0]?.[column] : results[0]) as T) ?? null;
  }
  async run() {
    return this.all();
  }
}

export class Database {
  readonly pool: pg.Pool;
  constructor(connectionString: string) {
    if (!connectionString) throw new Error("缺少 PostgreSQL 连接配置");
    this.pool = new pg.Pool({ connectionString, max: 8 });
  }
  prepare(sql: string) {
    return new Statement(this, sql);
  }
  async batch<T = Record<string, unknown>>(
    statements: Statement[],
    installId?: string,
  ) {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      // 同一安装的删除和上报串行，避免 MVCC 快照跨过删除墓碑。
      if (installId)
        await client.query(
          "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
          [installId],
        );
      const results = [];
      for (const statement of statements) {
        const result = await client.query(statement.sql, statement.values);
        results.push({ results: result.rows as T[] });
      }
      await client.query("COMMIT");
      return results;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
  async close() {
    await this.pool.end();
  }
}
