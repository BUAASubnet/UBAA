import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { loadContent } from "../../check/app_service/content.mjs";

export async function runRelease(
  operation,
  { contentPaths, execute = spawnSync } = {},
) {
  if (!["publish", "deploy"].includes(operation))
    throw new Error("命令须为 publish 或 deploy");
  loadContent(contentPaths);
  // 渠道和公告从 dev 发布；应用代码只从 main 部署，且不改写已发布内容。
  const [workflow, branch, message] =
    operation === "publish"
      ? ["app-content.yml", "dev", "已触发 dev 内容发布，服务器只替换渠道和公告"]
      : ["worker.yml", "main", "已触发 main 应用服务部署，已发布的渠道和公告保持不变"];
  const result = execute("gh", ["workflow", "run", workflow, "--ref", branch], {
    stdio: "inherit",
  });
  if (result.status !== 0) throw new Error("无法触发应用服务部署工作流");
  console.log(message);
}
if (
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url
) {
  try {
    await runRelease(process.argv[2]);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
