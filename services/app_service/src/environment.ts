import type { Database } from "./database";

export class RateLimit {
  private readonly windows = new Map<
    string,
    { start: number; count: number }
  >();
  constructor(
    private readonly maximum: number,
    private readonly period = 60_000,
  ) {}
  async limit({ key }: { key: string }) {
    const now = Date.now();
    for (const [id, entry] of this.windows) {
      if (entry.start + this.period <= now) this.windows.delete(id);
      else break;
    }
    let entry = this.windows.get(key);
    if (!entry || entry.start + this.period <= now) {
      entry = { start: now, count: 0 };
      this.windows.delete(key);
      this.windows.set(key, entry);
    }
    return { success: ++entry.count <= this.maximum };
  }
}

export class ResponseCache {
  private readonly entries = new Map<
    string,
    { expires: number; response: Response }
  >();
  async match(request: Request) {
    const entry = this.entries.get(request.url);
    return entry && entry.expires > Date.now()
      ? entry.response.clone()
      : undefined;
  }
  async put(request: Request, response: Response) {
    // 请求版本可以无限变化，限制进程内缓存占用。
    if (this.entries.size >= 1000)
      this.entries.delete(this.entries.keys().next().value!);
    this.entries.set(request.url, {
      expires: Date.now() + 300_000,
      response: response.clone(),
    });
  }
}

export interface Environment {
  DB: Database;
  USER_KEY_SECRET: string;
  TELEMETRY_LIMIT: Pick<RateLimit, "limit">;
  ERASE_LIMIT: Pick<RateLimit, "limit">;
  BOOTSTRAP_LIMIT: Pick<RateLimit, "limit">;
  APP_CONFIG: { get(key: string, type: "json"): Promise<unknown> };
  CACHE: ResponseCache;
}
export interface WaitContext {
  waitUntil(promise: Promise<unknown>): void;
}
