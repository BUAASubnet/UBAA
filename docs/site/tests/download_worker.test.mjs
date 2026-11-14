import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { describe } from "../download.data.js";
import { handleDownload } from "../download_worker.js";
import { resolveBrowserDownload } from "../public/download_client.js";
import source from "../download-source.json" with { type: "json" };

const manifest = JSON.parse(
  readFileSync(new URL("../download.json", import.meta.url)),
);
test("下载页的安装包和许可证使用动态下载入口", () => {
  const data = describe(manifest);
  for (const item of [...Object.values(data.platforms).flat(), data.licenses]) {
    assert.equal(
      item.url,
      `/downloads/v${manifest.version}/${manifest.build}/${item.name}`,
    );
  }
});

const asset = manifest.assets[0];
const path = `/downloads/v${manifest.version}/${manifest.build}/${asset.name}`;
const address =
  "https://bhpan.buaa.edu.cn/storage/synthetic.apk?Expires=2000000000&Signature=synthetic";
function upstream({ size = asset.size, password = false, status = 200 } = {}) {
  const calls = [];
  const send = async (url, init) => {
    calls.push({ url, ...init });
    if (url.endsWith(`/links/${source.shareId}`))
      return Response.json({ password_required: password }, { status });
    if (url.endsWith(`/link/${source.shareId}`))
      return new Response(null, {
        status: 302,
        headers: [
          ["Set-Cookie", "INGRESSCOOKIE=synthetic; Path=/"],
          [
            "Set-Cookie",
            `link_token:${source.shareId}=synthetic-token; Path=/`,
          ],
        ],
      });
    assert.equal(init.headers.get("Authorization"), "Bearer synthetic-token");
    assert.equal(init.redirect, "error");
    assert.equal(init.credentials, "omit");
    if (url.endsWith("/entry-item"))
      return Response.json([{ id: "gns://synthetic-root" }]);
    assert.equal(init.method, "POST");
    assert.equal(init.headers.get("Content-Type"), "application/json");
    if (url.endsWith("/dir/list")) {
      assert.deepEqual(JSON.parse(init.body), {
        by: "name",
        docid: "gns://synthetic-root",
        sort: "asc",
      });
      return Response.json({
        dirs: [],
        files: [{ name: asset.name, docid: "gns://synthetic-file", size }],
      });
    }
    assert.ok(url.endsWith("/file/osdownload"));
    assert.deepEqual(JSON.parse(init.body), {
      docid: "gns://synthetic-file",
      authtype: "QUERY_STRING",
    });
    return Response.json({ authrequest: ["GET", address] });
  };
  return { send, calls };
}
const request = (method = "GET", pathname = path) =>
  new Request("https://www.ubaa.top" + pathname, { method });

test("Worker 只申请分享授权，并把下载准备页交给浏览器", async () => {
  const mock = upstream();
  const result = await handleDownload(request(), {}, mock.send);
  assert.equal(result.status, 200);
  assert.match(result.headers.get("Content-Type"), /text\/html/);
  assert.equal(result.headers.get("Cache-Control"), "no-store");
  assert.equal(result.headers.get("Set-Cookie"), null);
  const html = await result.text();
  const payload = JSON.parse(
    html.match(
      /<script id="download-session" type="application\/json">(.*?)<\/script>/s,
    )[1],
  );
  assert.equal(payload.token, "synthetic-token");
  assert.deepEqual(payload.asset, { ...asset, directory: [] });
  assert.equal(mock.calls.length, 2);
});

test("HEAD 不申请分享授权，分享需密码和上游失败时保留备用下载", async () => {
  const head = await handleDownload(request("HEAD"), {}, () =>
    assert.fail("HEAD 不请求云盘"),
  );
  assert.equal(head.status, 200);
  assert.equal(await head.text(), "");
  for (const options of [{ password: true }, { status: 403 }]) {
    const mock = upstream(options);
    const result = await handleDownload(request(), {}, mock.send);
    assert.equal(result.status, 502);
    const html = await result.text();
    assert.ok(html.includes(asset.url));
    assert.ok(!html.includes("synthetic-token"));
  }
});

test("未知文件和写方法不触发上游请求，其他页面交给静态资源", async () => {
  const send = () => assert.fail("不应请求云盘");
  assert.equal(
    (await handleDownload(request("GET", path + ".unknown"), {}, send)).status,
    404,
  );
  assert.equal((await handleDownload(request("POST"), {}, send)).status, 405);
  const result = await handleDownload(
    request("GET", "/guide/start"),
    {
      ASSETS: { fetch: () => new Response("静态页面") },
    },
    send,
  );
  assert.equal(await result.text(), "静态页面");
});

test("备用下载保留发布清单中的全部服务器地址", () => {
  const data = describe(manifest);
  for (const item of [...Object.values(data.platforms).flat(), data.licenses]) {
    assert.equal(
      item.mirrorUrl,
      manifest.assets.find((a) => a.name === item.name).url,
    );
  }
});

test("分享版本与发布清单不同则阻止构建", () => {
  assert.throws(
    () => describe(manifest, { ...source, build: "other" }),
    /分享版本/,
  );
});

test("浏览器使用分享 Token 直接查询目录和申请下载地址", async () => {
  const mock = upstream();
  assert.equal(
    await resolveBrowserDownload(asset, "synthetic-token", mock.send),
    address,
  );
  assert.equal(mock.calls.length, 3);
  assert.ok(
    mock.calls.every((call) =>
      call.url.startsWith("https://bhpan.buaa.edu.cn/api/efast/"),
    ),
  );
});

test("浏览器发现文件大小不符时不申请下载授权", async () => {
  const mock = upstream({ size: 1 });
  await assert.rejects(
    resolveBrowserDownload(asset, "synthetic-token", mock.send),
    /大小不符/,
  );
  assert.equal(mock.calls.length, 2);
});

test("浏览器网络失败时直接报告，不自动重试", async () => {
  let calls = 0;
  await assert.rejects(
    resolveBrowserDownload(asset, "synthetic-token", () => {
      calls += 1;
      throw new TypeError("Failed to fetch");
    }),
  );
  assert.equal(calls, 1);
});
