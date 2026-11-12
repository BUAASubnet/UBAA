import {
  validateEraseRequest as validateEraseShape,
  validateTelemetryShape,
} from "../.generated/validators.mjs";

export {
  validateAnnouncement,
  validateAppVersion,
  validateBootstrapRequest,
  validateBootstrapResponse,
  validateHttpsUrl,
  validateStableVersion,
  validateTelemetryErrorResponse,
} from "../.generated/validators.mjs";

export const APP_SERVICE_SCHEMA_VERSION = 1;
export const TELEMETRY_BODY_MAX_BYTES = 128 * 1024;

export function isTelemetryBodySizeAllowed(bytes: number): boolean {
  return bytes <= TELEMETRY_BODY_MAX_BYTES;
}

export type EraseRequest = {
  schema: 1;
  install_id: string;
};

export function validateEraseRequest(
  payload: unknown,
): payload is EraseRequest {
  return validateEraseShape(payload);
}

export type TelemetryUser = {
  key: string;
  cohort_type: string;
  cohort_year: number | null;
};

type FeatureCount = {
  feature: string;
  route: string;
  count: number;
};

export type TelemetryDay = {
  day: string;
  app_version: string;
  surfaces: ("gui" | "command")[];
  users: TelemetryUser[];
  counters: (FeatureCount & { event: string; result: string })[];
  errors: (FeatureCount & {
    event: string;
    error_code: string;
    error_kind: string;
    retryable: boolean;
    source?: string;
  })[];
  timings: (FeatureCount & { metric: string; bucket: string })[];
  minutes?: {
    minute: number;
    event: string;
    feature: string;
    result: string;
    count: number;
  }[];
};

export type TelemetryRequest = EraseRequest & {
  batch_id: string;
  platform: string;
  channel: string;
  days: TelemetryDay[];
};

// Schema 校验单个字段；组合唯一性和随校园年份变化的上限在这里判断。
export function validateTelemetryRequest(
  payload: unknown,
  campusYear: number,
): payload is TelemetryRequest {
  if (!validateTelemetryShape(payload)) {
    return false;
  }
  const { days } = payload as TelemetryRequest;
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
    const minuteKeys = new Set<string>();
    for (const { minute, event, feature, result } of day.minutes ?? []) {
      const minuteKey = `${minute}/${event}/${feature}/${result}`;
      if (minuteKeys.has(minuteKey)) return false;
      minuteKeys.add(minuteKey);
    }
  }
  return true;
}
