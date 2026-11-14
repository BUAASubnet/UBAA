import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { describe } from "../download.data.js";
import { handleDownload } from "../download_worker.js";
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
    assert.equal(init.redirect, "manual");
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

test("公开分享按协议解析并跳转到签名下载地址，每次请求重新获取", async () => {
  const mock = upstream();
  for (const method of ["GET", "HEAD"]) {
    const result = await handleDownload(request(method), {}, mock.send);
    assert.equal(result.status, 302);
    assert.equal(result.headers.get("Location"), address);
    assert.equal(result.headers.get("Cache-Control"), "no-store");
    assert.equal(result.headers.get("Set-Cookie"), null);
    assert.equal(await result.text(), "");
  }
  assert.equal(mock.calls.length, 10);
});

test("缺失文件、分享需密码和上游失败均不返回下载地址或授权数据", async () => {
  for (const options of [{ size: 1 }, { password: true }, { status: 403 }]) {
    const mock = upstream(options);
    const result = await handleDownload(request(), {}, mock.send);
    assert.equal(result.status, 502);
    assert.equal(result.headers.get("Location"), null);
    assert.ok(!(await result.text()).includes("synthetic-token"));
    assert.ok(mock.calls.length < 5);
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

test("备用下载保留发布清单中的全部 R2 地址", () => {
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
