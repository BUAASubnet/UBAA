import { describe, expect, it } from "vitest";
import bootstrap from "../../../fixtures/app_service/bootstrap.json";
import erase from "../../../fixtures/app_service/erase.json";
import {
  validateAnnouncement,
  validateBootstrapRequest,
  validateBootstrapResponse,
  validateEraseRequest,
} from "../src/schema";

describe("删除接口", () => {
  it.each(erase.cases)("$name", ({ payload, valid }) => {
    expect(validateEraseRequest(payload)).toBe(valid);
  });
});

describe("启动配置接口", () => {
  it.each(bootstrap.cases)(
    "$name",
    ({ schema, payload, valid, acceptedAnnouncementIds }) => {
      switch (schema) {
        case "bootstrapRequest":
          expect(validateBootstrapRequest(payload)).toBe(valid);
          break;
        case "bootstrapResponse": {
          expect(validateBootstrapResponse(payload)).toBe(valid);
          if (acceptedAnnouncementIds) {
            expect(
              payload.announcements
                ?.filter(validateAnnouncement)
                .map(({ id }) => id),
            ).toEqual(acceptedAnnouncementIds);
          }
          break;
        }
        default:
          throw new Error(`未知 Schema 样例：${schema}`);
      }
    },
  );
});
