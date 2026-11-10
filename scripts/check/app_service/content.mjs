import { readFileSync, readdirSync } from "node:fs";
import { basename, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import MarkdownIt from "markdown-it";
import { parse } from "yaml";
import { compareVersions } from "../../../services/app_service/src/version.mjs";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const contract = JSON.parse(
  readFileSync(resolve(root, "docs/contracts/app-service.schema.json"), "utf8"),
);
const ajv = new Ajv2020({ allErrors: true });
addFormats(ajv);
ajv.addSchema(contract);
const def = (name) => ({ $ref: `${contract.$id}#/$defs/${name}` });
const updateField = (name) => def(`update/properties/${name}`);

const announcementFields = Object.fromEntries(
  Object.keys(contract.$defs.announcement.properties).map((key) => [
    key,
    def(`announcement/properties/${key}`),
  ]),
);
const scope = (name) => ({
  type: "array",
  minItems: 1,
  uniqueItems: true,
  items: def(name),
});
const announcementSchema = ajv.compile({
  type: "object",
  properties: {
    ...announcementFields,
    app: { type: "boolean" },
    platforms: scope("platform"),
    channels: scope("channel"),
    min_version: def("appVersion"),
    max_version: def("appVersion"),
  },
  required: [...contract.$defs.announcement.required, "app"],
  additionalProperties: false,
});
const calendarDate = ajv.compile({ type: "string", format: "date" });

const channelFields = {
  latest_version: updateField("latest_version"),
  min_supported_version: updateField("min_supported_version"),
  release_notes: updateField("release_notes"),
  url: def("httpsUrl"),
};
const platformOverride = {
  type: "object",
  properties: channelFields,
  additionalProperties: false,
};
const channelConfig = {
  type: "object",
  properties: {
    ...channelFields,
    platforms: {
      type: "object",
      propertyNames: def("platform"),
      additionalProperties: platformOverride,
    },
  },
  required: ["url"],
  additionalProperties: false,
};
const channelSchema = ajv.compile({
  type: "object",
  propertyNames: def("channel"),
  additionalProperties: { anyOf: [channelConfig, { type: "null" }] },
});

const markdown = new MarkdownIt({ html: true, linkify: true });
// 这里只检查语法，不渲染链接；任何协议的链接语法都应报错。
markdown.validateLink = () => true;
const paragraphTokens = new Set([
  "paragraph_open",
  "inline",
  "paragraph_close",
]);
const textTokens = new Set(["text", "softbreak"]);

function checkPlainText(text, field) {
  const env = {};
  const tokens = markdown.parse(text, env);
  if (
    env.references ||
    tokens.some(
      ({ type, children }) =>
        !paragraphTokens.has(type) ||
        children?.some((child) => !textTokens.has(child.type)),
    )
  ) {
    throw new Error(`${field} 只允许纯文本段落`);
  }
}

function checkSchema(validator, data) {
  if (validator(data)) return;
  const details = validator.errors.map(({ instancePath, keyword, params }) => {
    const path = instancePath || "内容";
    switch (keyword) {
      case "additionalProperties":
        return `${path} 有未知字段 ${params.additionalProperty}`;
      case "required":
        return `${path} 缺少字段 ${params.missingProperty}`;
      case "propertyNames":
        return `${path} 有无效的字段名 ${params.propertyName}`;
      case "maxLength":
        return `${path} 不得超过 ${params.limit} 字符`;
      default:
        return `${path} 不符合字段格式或取值要求（${keyword}）`;
    }
  });
  throw new Error(details.join("；"));
}

const storeHosts = {
  app_store: ["apps.apple.com"],
  app_gallery: ["appgallery.huawei.com", "appgallery.cloud.huawei.com"],
};

function checkChannelFields(fields, label, channel) {
  const { url, latest_version, min_supported_version, release_notes } = fields;
  const target = new URL(url);
  const allowed = storeHosts[channel];
  if (
    target.username ||
    target.password ||
    (allowed && !allowed.includes(target.host))
  ) {
    throw new Error(`${label}.url 必须为对应分发渠道的 HTTPS 下载地址`);
  }
  if (
    latest_version &&
    min_supported_version &&
    compareVersions(min_supported_version, latest_version) > 0
  ) {
    throw new Error(`${label}.min_supported_version 不能高于 latest_version`);
  }
  if (release_notes != null)
    checkPlainText(release_notes, `${label}.release_notes`);
}

export function validateChannels(channels) {
  checkSchema(channelSchema, channels);
  for (const [channel, config] of Object.entries(channels)) {
    if (config === null) continue;
    const { platforms = {}, ...base } = config;
    checkChannelFields(base, channel, channel);
    for (const [platform, override] of Object.entries(platforms)) {
      checkChannelFields(
        { ...base, ...override },
        `${channel}.platforms.${platform}`,
        channel,
      );
    }
  }
}

const announcementName = /^(\d{4}-\d{2}-\d{2})-\d{3}\.md$/;
const navigationPages = new Set(["index.md", "history.md"]);

export function parseAnnouncement(filename, text) {
  const match = announcementName.exec(filename);
  if (!match || !calendarDate(match[1])) {
    throw new Error("公告文件名必须为有效日期与三位序号（YYYY-MM-DD-NNN.md）");
  }
  const parts =
    /^---[^\S\r\n]*\r?\n([\s\S]*?)\r?\n---[^\S\r\n]*(?:\r?\n|$)/.exec(text);
  if (!parts) throw new Error("公告缺少 frontmatter");
  let fields;
  try {
    fields = parse(parts[1]);
  } catch (error) {
    throw new Error(`frontmatter：${error.message}`, { cause: error });
  }
  if (!fields || typeof fields !== "object" || Array.isArray(fields)) {
    throw new Error("frontmatter 必须为字段映射");
  }
  if ("id" in fields || "body" in fields) {
    throw new Error("公告的 id 和 body 来自文件名和正文，不得写在 frontmatter");
  }
  const rawBody = text.slice(parts[0].length).replaceAll("\r\n", "\n");
  const announcement = {
    ...fields,
    id: filename.slice(0, -3),
    body: rawBody.trim(),
  };
  checkSchema(announcementSchema, announcement);
  if (!announcement.title.trim() || !announcement.body) {
    throw new Error("title 和 body 不能为空");
  }
  // 保留段内原始缩进，以便识别首段的缩进代码块。
  checkPlainText(rawBody, "body");
  for (const key of ["starts_at", "ends_at"]) {
    if (
      announcement[key] !== undefined &&
      !Number.isFinite(Date.parse(announcement[key]))
    ) {
      throw new Error(`${key} 必须为有效的带时区时间`);
    }
  }
  if (
    announcement.ends_at !== undefined &&
    Date.parse(announcement.ends_at) <= Date.parse(announcement.starts_at)
  ) {
    throw new Error("ends_at 必须晚于 starts_at");
  }
  if (
    announcement.min_version !== undefined &&
    announcement.max_version !== undefined &&
    compareVersions(announcement.min_version, announcement.max_version) > 0
  ) {
    throw new Error("max_version 不能低于 min_version");
  }
  return announcement;
}

function fromFile(path, parseFile) {
  try {
    return parseFile(readFileSync(path, "utf8"));
  } catch (error) {
    throw new Error(`${path}：${error.message}`, { cause: error });
  }
}

export function loadAnnouncements(paths) {
  return paths
    .filter(
      (path) => path.endsWith(".md") && !navigationPages.has(basename(path)),
    )
    .sort((a, b) => basename(b).localeCompare(basename(a), "en"))
    .map((path) =>
      fromFile(path, (text) => parseAnnouncement(basename(path), text)),
    );
}

export function loadContent({
  channelsPath = resolve(root, "services/app_service/config/channels.json"),
  announcementsDir = resolve(root, "docs/site/announcements"),
} = {}) {
  const channels = fromFile(channelsPath, (text) => {
    const data = JSON.parse(text);
    validateChannels(data);
    return data;
  });
  const paths = readdirSync(announcementsDir, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => resolve(announcementsDir, entry.name));
  return { channels, announcements: loadAnnouncements(paths) };
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    const { announcements } = loadContent();
    console.log(`应用服务渠道配置和 ${announcements.length} 条公告校验通过`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
