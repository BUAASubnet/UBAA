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
  const result = execute(
    "gh",
    ["workflow", "run", "worker.yml", "--ref", "main"],
    { stdio: "inherit" },
  );
  if (result.status !== 0) throw new Error("无法触发应用服务部署工作流");
  console.log("已触发 main 应用服务部署，构建和内容由服务器统一接收");
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
