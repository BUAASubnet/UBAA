import { describe, expect, it } from "vitest";
import cases from "../../../fixtures/app_service/version_order.json";
import { compareVersions } from "../src/version";

describe("应用服务版本比较共用样例", () => {
  it.each(cases)(
    "$left 与 $right 的比较结果为 $order",
    ({ left, right, order }) => {
      expect(compareVersions(left, right)).toBe(order);
      expect(compareVersions(right, left)).toBe(Math.sign(-order) || 0);
    },
  );
});
