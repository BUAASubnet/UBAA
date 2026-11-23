import { mkdirSync, cpSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { serverContent } from "../check/app_service/content.mjs";
const directory = resolve("target/server_package");
const output = resolve("dist/app_service");
mkdirSync(directory, { recursive: true });
mkdirSync(output, { recursive: true });
for (const name of [
  "package.json",
  "package-lock.json",
  "migrations",
  ".generated/build",
]) {
  cpSync(`services/app_service/${name}`, `${directory}/${name}`, {
    recursive: true,
  });
}
cpSync("scripts/server/deploy.py", `${directory}/deploy.py`);
writeFileSync(`${directory}/content.json`, JSON.stringify(serverContent()));
const result = spawnSync(
  "tar",
  ["-czf", resolve(output, "app_service.tar.gz"), "-C", directory, "."],
  { stdio: "inherit" },
);
process.exitCode = result.status ?? 1;
