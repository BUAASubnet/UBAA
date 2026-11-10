import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import test from "node:test";
import { isCurrentAnnouncement } from "../../../docs/site/announcements/announcement_time.js";
import {
  loadContent,
  parseAnnouncement,
  validateChannels,
} from "../../check/app_service/content.mjs";

const root = resolve(import.meta.dirname, "../../..");
const fixtures = join(root, "fixtures/app_service/announcements");
const filename = "2000-01-03-001.md";
const source = readFileSync(join(fixtures, filename), "utf8");
const parse = (input, name = filename) => parseAnnouncement(name, input);
const announcementVersions = JSON.parse(
  readFileSync(join(fixtures, "../announcement_versions.json"), "utf8"),
);
const config = {
  latest_version: "2.0.0+12",
  min_supported_version: "2.0.0",
  url: "https://example.invalid/release",
  release_notes: "纯文本更新说明",
};

test("加载的公告以文件名为 ID，保留文本段落、定向和网站专用公告", () => {
  const { announcements } = loadContent({ announcementsDir: fixtures });
  assert.equal(announcements.length, 4);
  const app = announcements.find(({ id }) => id === "2000-01-03-001");
  assert.deepEqual(app.platforms, ["android", "ios"]);
  assert.equal(
    app.body,
    "这是测试夹具中的第一段。\n\n这是测试夹具中的第二段。",
  );
  assert.ok(announcements.some(({ app }) => app === false));
  assert.ok(loadContent().announcements.every(({ id }) => /^\d{4}-/.test(id)));
});

test("公告生效区间包含开始时刻但不包含结束时刻", () => {
  const note = parse(
    source.replace(
      "link_url:",
      "ends_at: 2000-01-04T08:00:00+08:00\nlink_url:",
    ),
  );
  assert.ok(!isCurrentAnnouncement(note, Date.parse(note.starts_at) - 1));
  assert.ok(isCurrentAnnouncement(note, Date.parse(note.starts_at)));
  assert.ok(!isCurrentAnnouncement(note, Date.parse(note.ends_at)));
});

for (const { name, min, max, validRange } of announcementVersions) {
  test(name, () => {
    const input = source
      .replace(/^min_version: .+$/m, `min_version: ${min}`)
      .replace(/^max_version: .+$/m, `max_version: ${max}`);
    if (validRange) {
      const announcement = parse(input);
      assert.equal(announcement.min_version, min);
      assert.equal(announcement.max_version, max);
    } else {
      assert.throws(() => parse(input), /max_version/);
    }
  });
}

test("公告文件名、字符限制、定向和时间错误均拒绝发布", () => {
  assert.throws(() => parse(source, "2000-02-30-001.md"), /文件名/);
  assert.throws(() => parse(source, "2000-01-03-1.md"), /文件名/);
  const cases = [
    [source.replace("app: true", "app: 'true'"), /app/],
    [source.replace("app: true", "app: true\napp: false"), /frontmatter/],
    [source.replace("level: popup", "level: alert"), /level/],
    [source.replace("channels: [github]", "channel: github"), /channel/],
    [source.replace("[android, ios]", "[unknown]"), /platforms/],
    [source.replace("[github]", "[]"), /channels/],
    [source.replace("2.1.0-rc.10", "2.1.0-rc.1"), /max_version/],
    [source.replace("2.1.0-rc.10", "bad"), /max_version/],
    [source.replace("2000-01-03T", "2000-02-30T"), /starts_at/],
    [source.replace("08:00:00+08:00", "08:00:00"), /starts_at/],
    [
      source.replace(
        "link_url:",
        "ends_at: 2000-01-02T08:00:00+08:00\nlink_url:",
      ),
      /ends_at/,
    ],
    [source.replace("https://", "http://"), /link_url/],
    [source.replace(/title: .*/, "title: " + "中".repeat(41)), /title/],
    [source.replace("这是测试夹具中的第一段。", "𠮷".repeat(1001)), /body/],
  ];
  for (const [input, error] of cases) assert.throws(() => parse(input), error);
  assert.doesNotThrow(() =>
    parse(source.replace(/title: .*/, "title: " + "𠮷".repeat(40))),
  );
});

test("公告正文拒绝标题、列表、引用、链接、图片、代码、HTML 和其他格式", () => {
  const frontmatter = source.split("\n---\n")[0] + "\n---\n";
  for (const body of [
    "## 标题",
    "标题\n====",
    "1. 列表",
    "- 列表",
    "> 引用",
    "---",
    "[链接](https://example.invalid)",
    "<https://example.invalid>",
    "![图片](test.png)",
    "[链接]: https://example.invalid\n\n没有引用",
    "一段`代码`",
    "```js\n代码\n```",
    "    代码",
    "<div>HTML</div>",
    "段落中有 <span>HTML</span>",
    "段落中有 **加粗**",
  ]) {
    assert.throws(() => parse(frontmatter + "\n" + body + "\n"), /纯文本/);
  }
});

test("渠道与平台覆盖使用正式版本、对应商店 URL 及纯文本说明", () => {
  assert.doesNotThrow(() =>
    validateChannels({
      github: { ...config, platforms: { windows: { release_notes: null } } },
      app_store: { ...config, url: "https://apps.apple.com/cn/app/id123" },
      app_gallery: null,
    }),
  );
  const invalid = [
    { unknown: null },
    { github: { ...config, latest_version: "2.0.1-rc.1" } },
    { github: { ...config, min_supported_version: "2.0.1" } },
    { github: { ...config, release_notes: "中".repeat(2001) } },
    { github: { ...config, release_notes: "# 更新说明" } },
    { github: { ...config, url: "http://example.invalid" } },
    { github: { ...config, platforms: { unknown: {} } } },
    { github: { ...config, platforms: { ios: { typo: true } } } },
    { app_store: config },
    {
      app_gallery: {
        ...config,
        url: "https://appgallery.huawei.com.example.invalid",
      },
    },
    {
      app_store: {
        ...config,
        url: "https://apps.apple.com/cn/app/id123",
        platforms: { ios: { url: "https://example.invalid" } },
      },
    },
  ];
  for (const channels of invalid)
    assert.throws(() => validateChannels(channels));
});
