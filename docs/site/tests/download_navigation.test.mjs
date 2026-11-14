import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { createServer } from "vite";
import { parse as parseSfc } from "@vue/compiler-sfc";
import { baseParse } from "@vue/compiler-dom";

// 用当前 VitePress 的路由判断验证真实模板中的下载链接。
test("安装包下载交给浏览器，不进入 VitePress 页面路由", async () => {
  const server = await createServer({
    configFile: false,
    server: { middlewareMode: true },
    plugins: [
      {
        name: "测试站点数据",
        resolveId(id) {
          if (id === "@siteData") return "\0site-data";
        },
        load(id) {
          if (id === "\0site-data") return "export default {}";
        },
      },
    ],
  });
  const previousLocation = globalThis.location;
  const previousSvg = globalThis.SVGElement;
  globalThis.location = new URL("https://www.ubaa.top/download");
  globalThis.SVGElement = class {};
  try {
    const { getRoutableLinkUrl } = await server.ssrLoadModule(
      "/node_modules/vitepress/dist/client/app/router.js",
    );
    for (const name of ["DownloadOptions.vue", "DownloadSuggest.vue"]) {
      const source = readFileSync(
        new URL(`../components/${name}`, import.meta.url),
        "utf8",
      );
      const ast = baseParse(parseSfc(source).descriptor.template.content);
      const visit = (node) => {
        if (
          node.tag === "a" &&
          node.props.some((prop) => prop.exp?.content.includes("row.url"))
        ) {
          const attrs = new Map(
            node.props
              .filter((prop) => prop.type === 6)
              .map((prop) => [prop.name, prop.value?.content ?? ""]),
          );
          for (const extension of ["apk", "dmg", "exe", "tar.gz"]) {
            const href = `/downloads/v2.0.0/2004/UBAA.${extension}`;
            const link = {
              baseURI: "https://www.ubaa.top/download",
              closest: () =>
                attrs.get("class")?.split(" ").includes("vp-raw") ? {} : null,
              hasAttribute: (key) => attrs.has(key),
              getAttribute: (key) =>
                key === "href" ? href : (attrs.get(key) ?? null),
            };
            assert.equal(
              getRoutableLinkUrl(link),
              null,
              `${name} 的 ${extension} 下载被页面路由接管`,
            );
          }
        }
        for (const child of node.children ?? []) visit(child);
      };
      visit(ast);
    }
  } finally {
    globalThis.location = previousLocation;
    globalThis.SVGElement = previousSvg;
    await server.close();
  }
});
