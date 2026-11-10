import { validateTelemetryShape } from "../.generated/validators.mjs";

export {
  validateAnnouncement,
  validateBootstrapRequest,
  validateBootstrapResponse,
  validateEraseRequest,
  validateTelemetryErrorResponse,
} from "../.generated/validators.mjs";

export const APP_SERVICE_SCHEMA_VERSION = 1;
export const TELEMETRY_BODY_MAX_BYTES = 128 * 1024;

export function isTelemetryBodySizeAllowed(bytes: number): boolean {
  return bytes <= TELEMETRY_BODY_MAX_BYTES;
}

type TelemetryDays = {
  days: {
    day: string;
    app_version: string;
    users: { cohort_year: number | null }[];
  }[];
};

// Schema 校验单个字段；日期与版本组合、随校园年份变化的上限在这里判断。
export function validateTelemetryRequest(
  payload: unknown,
  campusYear: number,
): boolean {
  if (!validateTelemetryShape(payload)) {
    return false;
  }
  const { days } = payload as TelemetryDays;
  const seen = new Set<string>();
  for (const day of days) {
    const key = `${day.day}/${day.app_version}`;
    if (
      seen.has(key) ||
      day.users.some(
        ({ cohort_year }) =>
          cohort_year !== null && cohort_year > campusYear + 1,
      )
    ) {
      return false;
    }
    seen.add(key);
  }
  return true;
}
