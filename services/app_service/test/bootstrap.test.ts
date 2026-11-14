import { createWaitContext, env, waitOnWaitContext } from "./runtime";
import { beforeEach, expect, it } from "vitest";
import announcementVersions from "../../../fixtures/app_service/announcement_versions.json";
import worker from "../src/index";
import { validateBootstrapResponse } from "../src/schema";

const github = {
  latest_version: "2.1.0+15",
  min_supported_version: "2.0.0",
  url: "https://github.com/BUAASubnet/UBAA/releases/latest",
  release_notes: "更新说明",
};

const makeAnnouncement = (sequence: number, fields: object = {}) => ({
  id: `2026-11-11-${String(sequence).padStart(3, "0")}`,
  level: "banner",
  title: "公告标题",
  body: "公告正文\n\n第二段",
  starts_at: "2026-01-01T00:00:00+08:00",
  app: true,
  ...fields,
});

async function putConfig(channels: object, announcements: object[] = []) {
  await Promise.all([
    env.APP_CONFIG.put("channels", JSON.stringify(channels)),
    env.APP_CONFIG.put("announcements", JSON.stringify(announcements)),
  ]);
}

let origin: string;

beforeEach(() => {
  origin = `https://${crypto.randomUUID()}.invalid`;
});

async function send(
  query = "schema=1&platform=android&channel=github&version=2.0.0%2B12",
  headers?: HeadersInit,
) {
  const ctx = createWaitContext();
  const response = await worker.fetch(
    new Request(`${origin}/v1/bootstrap?${query}`, { headers }),
    env,
    ctx,
  );
  const payload: unknown = await response.json().catch(() => null);
  await waitOnWaitContext(ctx);
  return { response, payload };
}

it("无渠道配置返回 unknown，同时保留符合条件的公告", async () => {
  await env.APP_CONFIG.delete("channels");
  await env.APP_CONFIG.put(
    "announcements",
    JSON.stringify([makeAnnouncement(1)]),
  );
  const { response, payload } = await send();
  expect(response.status).toBe(200);
  expect(payload).toEqual({
    schema: 1,
    update: {
      status: "unknown",
      latest_version: null,
      min_supported_version: null,
      url: null,
      release_notes: null,
    },
    announcements: [expect.objectContaining({ id: "2026-11-11-001" })],
  });
  expect(validateBootstrapResponse(payload)).toBe(true);
});

it("按版本决定更新状态，并按平台覆盖渠道配置", async () => {
  await putConfig({
    github: {
      ...github,
      platforms: { android: { min_supported_version: "2.0.0+13" } },
    },
  });
  const cases = [
    ["android", "2.0.0%2B12", "update_required", "2.0.0+13", "更新说明"],
    ["ios", "2.0.0%2B12", "update_available", "2.0.0", "更新说明"],
    ["ios", "2.1.0-rc.1%2B30", "update_available", "2.0.0", "更新说明"],
    ["ios", "2.1.0%2B15", "up_to_date", "2.0.0", null],
  ];
  for (const [platform, version, status, minVersion, notes] of cases) {
    const { response, payload } = await send(
      `schema=1&platform=${platform}&channel=github&version=${version}`,
    );
    expect(response.status).toBe(200);
    expect(payload).toEqual({
      schema: 1,
      update: {
        ...github,
        status,
        min_supported_version: minVersion,
        release_notes: notes,
      },
      announcements: [],
    });
  }
});

it.each([
  ["app_store", "https://apps.apple.com/cn/app/id123456789"],
  ["app_gallery", "https://appgallery.huawei.com/app/detail?id=example.app"],
  [
    "app_gallery",
    "https://appgallery.cloud.huawei.com/appDetail?appId=example",
  ],
])("接受 %s 正式商店的 HTTPS 链接", async (channel, url) => {
  await putConfig({ [channel]: { ...github, url } });
  const { response, payload } = await send(
    `schema=1&platform=ohos&channel=${channel}&version=2.0.0`,
  );
  expect(response.status).toBe(200);
  expect(payload).toHaveProperty("update.url", url);
});

it.each([
  ["app_store", { url: github.url }],
  ["app_store", { url: "https://apps.apple.com.example.invalid/download" }],
  ["app_store", { url: "http://apps.apple.com/cn/app/id123456789" }],
  ["app_gallery", { url: "https://apps.apple.com/cn/app/id123456789" }],
  ["app_store", { latest_version: "2.1.0-rc.1" }],
  ["app_store", { min_supported_version: "2.0.0-rc.1" }],
  ["app_store", { platforms: { android: { latest_version: "2.2.0-rc.1" } } }],
])("拒绝 %s 非法配置且不返回可改变门控的响应", async (channel, fields) => {
  await putConfig({
    [channel]: {
      ...github,
      url: "https://apps.apple.com/cn/app/id123456789",
      ...fields,
    },
  });
  const { response } = await send(
    `schema=1&platform=android&channel=${channel}&version=2.0.0`,
  );
  expect(response.status).toBe(500);
  expect(response.headers.has("Cache-Control")).toBe(false);
});

it("依次筛选定向、生效时间、网站专属和非法公告，最多保留五条", async () => {
  await putConfig({ github: null }, [
    makeAnnouncement(1, { platforms: ["ios"] }),
    makeAnnouncement(2, { channels: ["app_store"] }),
    makeAnnouncement(3, { app: false }),
    makeAnnouncement(4, { starts_at: "2099-01-01T00:00:00+08:00" }),
    makeAnnouncement(5, { ends_at: "2026-01-02T00:00:00+08:00" }),
    makeAnnouncement(6, { min_version: "2.0.0+13" }),
    makeAnnouncement(7, { max_version: "2.0.0+11" }),
    makeAnnouncement(8, { link_url: "http://example.invalid/notice" }),
    makeAnnouncement(9, { level: "future" }),
    makeAnnouncement(10, { title: undefined }),
    makeAnnouncement(16, {
      level: "popup",
      link_url: "https://example.invalid/notice",
      link_text: "详情",
      confirm_text: "知道了",
    }),
    makeAnnouncement(14, {
      platforms: ["android"],
      channels: ["github"],
      min_version: "2.0.0+12",
      max_version: "2.0.0+12",
    }),
    ...[11, 12, 13, 15].map((number) => makeAnnouncement(number)),
  ]);
  const { response, payload } = await send();
  expect(response.status).toBe(200);
  const ids = [16, 14, 11, 12, 13].map((number) => makeAnnouncement(number).id);
  expect(payload).toHaveProperty(
    "announcements",
    ids.map((id) => expect.objectContaining({ id })),
  );
  expect(payload).toHaveProperty(
    "announcements.0.link_url",
    "https://example.invalid/notice",
  );
  expect(payload).not.toHaveProperty("announcements.0.app");
  expect(payload).not.toHaveProperty("announcements.1.min_version");
});

it.each(announcementVersions)("$name", async ({ min, max, versions }) => {
  const announcement = makeAnnouncement(1, {
    min_version: min,
    max_version: max,
  });
  await putConfig({ github: null }, [announcement]);
  for (const [version, expected] of versions) {
    const { response, payload } = await send(
      `schema=1&platform=android&channel=github&version=${encodeURIComponent(String(version))}`,
    );
    expect(response.status).toBe(200);
    expect(payload).toHaveProperty(
      "announcements",
      expected ? [expect.objectContaining({ id: announcement.id })] : [],
    );
  }
});

it("按同一组四参数共用 300 秒缓存；平台、渠道和版本各自隔离", async () => {
  await putConfig({ github });
  const first = await send();
  expect(first.response.status).toBe(200);
  expect(first.response.headers.get("Cache-Control")).toBe(
    "public, max-age=300",
  );
  await putConfig({ github: { ...github, latest_version: "2.2.0" } });
  const reordered = await send(
    "channel=github&version=2.0.0%2b12&platform=android&schema=1",
  );
  expect(reordered.payload).toEqual(first.payload);
  for (const [platform, channel, version, latest] of [
    ["ios", "github", "2.0.0%2B12", "2.2.0"],
    ["android", "app_store", "2.0.0%2B12", null],
    ["android", "github", "2.0.0%2B13", "2.2.0"],
  ]) {
    const { payload } = await send(
      `schema=1&platform=${platform}&channel=${channel}&version=${version}`,
    );
    expect(payload).toHaveProperty("update.latest_version", latest);
  }
});

it("拒绝额外参数、重复参数、学校 Cookie 与认证头", async () => {
  const valid = "schema=1&platform=android&channel=github&version=2.0.0";
  for (const query of [
    `${valid}&install_id=example`,
    `${valid}&version=2.1.0`,
    valid.replace("schema=1", "schema=2"),
    valid.replace("&version=2.0.0", ""),
  ]) {
    expect((await send(query)).response.status).toBe(400);
  }
  for (const headers of [
    new Headers({ Cookie: "synthetic=local" }),
    new Headers({ Authorization: "synthetic" }),
  ]) {
    expect((await send(valid, headers)).response.status).toBe(400);
  }
});
