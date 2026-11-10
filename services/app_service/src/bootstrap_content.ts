import {
  validateAnnouncement,
  validateAppVersion,
  validateHttpsUrl,
  validateStableVersion,
} from "./schema";
import { compareVersions } from "./version.mjs";

export const CHANNELS_KEY = "channels";
export const ANNOUNCEMENTS_KEY = "announcements";

export type BootstrapQuery = {
  schema: "1";
  platform: string;
  channel: string;
  version: string;
};

const unknownUpdate = {
  status: "unknown",
  latest_version: null,
  min_supported_version: null,
  url: null,
  release_notes: null,
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) throw new Error("应用服务配置必须为对象");
  return value;
}

function validChannelUrl(url: unknown, channel: string): url is string {
  if (typeof url !== "string" || !validateHttpsUrl(url)) return false;
  const target = new URL(url);
  if (target.username || target.password) return false;
  switch (channel) {
    case "app_store":
      return target.host === "apps.apple.com";
    case "app_gallery":
      return (
        target.host === "appgallery.huawei.com" ||
        target.host === "appgallery.cloud.huawei.com"
      );
    default:
      return true;
  }
}

function optionalStable(value: unknown): value is string | null {
  return (
    value === null ||
    (typeof value === "string" && validateStableVersion(value))
  );
}

function channelFields(fields: Record<string, unknown>, channel: string) {
  const {
    latest_version = null,
    min_supported_version = null,
    url,
    release_notes = null,
  } = fields;
  if (
    !optionalStable(latest_version) ||
    !optionalStable(min_supported_version) ||
    !validChannelUrl(url, channel) ||
    (release_notes !== null &&
      (typeof release_notes !== "string" || [...release_notes].length > 2000))
  ) {
    throw new Error("渠道更新配置不符合应用服务合同");
  }
  return { latest_version, min_supported_version, url, release_notes };
}

export function resolveUpdate(channels: unknown, query: BootstrapQuery) {
  const { channel, platform, version } = query;
  const value = channels === null ? null : requireRecord(channels)[channel];
  if (value === undefined || value === null) return unknownUpdate;

  const config = requireRecord(value);
  const base = channelFields(config, channel);
  const override =
    config.platforms === undefined
      ? undefined
      : requireRecord(config.platforms)[platform];
  const fields =
    override === undefined
      ? base
      : channelFields({ ...base, ...requireRecord(override) }, channel);
  const { min_supported_version: min, latest_version: latest } = fields;
  if (min !== null && compareVersions(version, min) < 0) {
    return { ...fields, status: "update_required" };
  }
  if (latest !== null && compareVersions(version, latest) < 0) {
    return { ...fields, status: "update_available" };
  }
  return { ...fields, status: "up_to_date", release_notes: null };
}

type Announcement = {
  id: string;
  level: "banner" | "popup";
  title: string;
  body: string;
  starts_at: string;
  ends_at?: string;
  link_url?: string;
  link_text?: string;
  confirm_text?: string;
};

function matchesScope(scope: unknown, value: string): boolean {
  return scope === undefined || (Array.isArray(scope) && scope.includes(value));
}

function matchesVersionRange(
  min: unknown,
  max: unknown,
  version: string,
): boolean {
  return (
    (min === undefined ||
      (typeof min === "string" &&
        validateAppVersion(min) &&
        compareVersions(version, min) >= 0)) &&
    (max === undefined ||
      (typeof max === "string" &&
        validateAppVersion(max) &&
        compareVersions(version, max) <= 0))
  );
}

export function selectAnnouncements(
  value: unknown,
  query: BootstrapQuery,
  now: number,
): Announcement[] {
  if (value === null) return [];
  if (!Array.isArray(value)) throw new Error("公告配置必须为数组");
  const result: Announcement[] = [];
  for (const item of value as unknown[]) {
    if (!isRecord(item) || item.app !== true || !validateAnnouncement(item))
      continue;
    const {
      id,
      level,
      title,
      body,
      starts_at,
      ends_at,
      link_url,
      link_text,
      confirm_text,
    } = item as Announcement;
    if (
      !matchesScope(item.platforms, query.platform) ||
      !matchesScope(item.channels, query.channel) ||
      !matchesVersionRange(item.min_version, item.max_version, query.version) ||
      !(Date.parse(starts_at) <= now) ||
      (ends_at !== undefined && !(Date.parse(ends_at) > now))
    )
      continue;
    result.push({
      id,
      level,
      title,
      body,
      starts_at,
      ends_at,
      link_url,
      link_text,
      confirm_text,
    });
    if (result.length === 5) break;
  }
  return result;
}
