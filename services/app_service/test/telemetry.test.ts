import { describe, expect, it } from "vitest";
import fixtures from "../../../fixtures/app_service/telemetry.json";
import {
  isTelemetryBodySizeAllowed,
  validateTelemetryErrorResponse,
  validateTelemetryRequest,
} from "../src/schema";

interface UserFixture {
  key: string | null;
}

interface TelemetryFixture {
  days: { users?: UserFixture[] }[];
}

type MutationTarget = Record<string | number, unknown>;

async function withSyntheticKeys(payload: unknown): Promise<unknown> {
  if (typeof payload !== "object" || payload === null) {
    return payload;
  }
  const data = structuredClone(payload) as TelemetryFixture;
  for (const day of data.days) {
    for (const user of day.users ?? []) {
      if (user.key === null) {
        const bytes = new TextEncoder().encode(
          "ubaa-telemetry-user-v1:STEP-ONE-SYNTHETIC",
        );
        const digest = await crypto.subtle.digest("SHA-256", bytes);
        user.key = Array.from(new Uint8Array(digest), (byte) =>
          byte.toString(16).padStart(2, "0"),
        ).join("");
      }
    }
  }
  return data;
}

describe("遥测载荷", () => {
  it.each(fixtures.cases)("$name", async ({ schema, payload, valid }) => {
    switch (schema) {
      case "telemetryRequest":
        expect(
          validateTelemetryRequest(await withSyntheticKeys(payload), 2026),
        ).toBe(valid);
        break;
      case "telemetryErrorResponse":
        expect(validateTelemetryErrorResponse(payload)).toBe(valid);
        break;
      default:
        throw new Error(`未知 Schema 样例：${schema}`);
    }
  });

  it.each(fixtures.mutations)("$name", async ({ caseIndex, path, value }) => {
    const data = await withSyntheticKeys(fixtures.cases[caseIndex].payload);
    let target = data as MutationTarget;
    for (const key of path.slice(0, -1)) {
      target = target[key] as MutationTarget;
    }
    target[path[path.length - 1]] = value;
    expect(validateTelemetryRequest(data, 2026)).toBe(false);
  });
});

describe("遥测关联约束", () => {
  const base = fixtures.cases[0].payload;
  if (typeof base === "string" || !base) {
    throw new Error("最小遥测夹具必须是遥测请求");
  }

  it.each(fixtures.constraints)("$name", async (fixture) => {
    const [day] = base.days;
    const { kind, payload, bytes, campusYear, valid } = fixture;
    if (kind === "bodyBytes" && bytes !== undefined) {
      const body = JSON.stringify(base).padEnd(bytes, " ");
      expect(
        isTelemetryBodySizeAllowed(new TextEncoder().encode(body).byteLength),
      ).toBe(valid);
    } else if (
      kind === "campusYear" &&
      payload &&
      !Array.isArray(payload) &&
      campusYear !== undefined
    ) {
      const users = [{ ...payload, key: null }];
      const data = await withSyntheticKeys({
        ...base,
        days: [{ ...day, users }],
      });
      expect(validateTelemetryRequest(data, campusYear)).toBe(valid);
    } else if (kind === "dayVersionUnique" && Array.isArray(payload)) {
      const days = payload.map((part) => ({ ...day, ...part }));
      expect(validateTelemetryRequest({ ...base, days }, 2026)).toBe(valid);
    } else {
      throw new Error(`非法约束样例：${kind}`);
    }
  });

  it("正文上限按 UTF-8 字节计算", () => {
    const json = JSON.stringify({ unexpected: "字" });
    const body = json.padEnd(128 * 1024, " ");
    expect(
      isTelemetryBodySizeAllowed(new TextEncoder().encode(body).byteLength),
    ).toBe(false);
  });
});
