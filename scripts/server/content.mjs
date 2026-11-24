// 生成 dev 内容发布要传给服务器的渠道与公告，不包含应用代码。
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { serverContent } from "../check/app_service/content.mjs";

const directory = resolve("dist/app_service");
mkdirSync(directory, { recursive: true });
writeFileSync(
  resolve(directory, "app_content.json"),
  JSON.stringify(serverContent()),
);
