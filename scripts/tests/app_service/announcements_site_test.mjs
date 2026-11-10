import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";
import test from "node:test";
const root = resolve(import.meta.dirname, "../../..");
const fixtures = join(root, "fixtures/app_service/announcements");
const filename = "2000-01-03-001.md";
const source = readFileSync(join(fixtures, filename), "utf8");

function buildSite(site, out) {
  return spawnSync(
    process.execPath,
    [
      join(root, "node_modules/vitepress/bin/vitepress.js"),
      "build",
      site,
      "--outDir",
      out,
    ],
    {
      cwd: root,
      env: { ...process.env, DOCS_BASE: "/ubaa-test/" },
      encoding: "utf8",
    },
  );
}

test("VitePress 构建的两页显示真实夹具正文并按时间筛选", () => {
  const parent = join(root, ".ubaa_local/app_service");
  mkdirSync(parent, { recursive: true, mode: 0o700 });
  const work = mkdtempSync(join(parent, "content-test-"));
  try {
    const site = join(work, "docs/site");
    mkdirSync(site, { recursive: true });
    cpSync(join(root, "docs/site"), site, {
      recursive: true,
      filter: (path) => !/\/\.vitepress\/(dist|cache)(\/|$)/.test(path),
    });
    symlinkSync(join(root, "scripts"), join(work, "scripts"), "dir");
    symlinkSync(join(root, "node_modules"), join(work, "node_modules"), "dir");
    for (const file of readdirSync(fixtures)) {
      cpSync(join(fixtures, file), join(site, "announcements", file));
    }
    const out = join(work, "out");
    const valid = buildSite(site, out);
    assert.equal(valid.status, 0, valid.stdout + valid.stderr);
    const center = readFileSync(join(out, "announcements/index.html"), "utf8");
    const history = readFileSync(
      join(out, "announcements/history.html"),
      "utf8",
    );
    for (const html of [center, history]) {
      assert.match(html, /合成样例：当前 App 公告/);
      assert.match(html, /合成样例：网站专用公告/);
      assert.match(html, /<p>这是测试夹具中的第二段。<\/p>/);
    }
    for (const title of ["合成样例：已过期公告", "合成样例：尚未开始公告"]) {
      assert.ok(!center.includes(title), title);
      assert.ok(history.includes(title), title);
    }
    assert.match(center, /href="\/ubaa-test\/announcements\/history"/);

    writeFileSync(
      join(site, "announcements", filename),
      source + "\n## 非法标题",
    );
    const invalid = buildSite(site, out);
    assert.equal(invalid.status, 1);
    assert.match(invalid.stderr, /纯文本/);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
