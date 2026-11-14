import { mkdirSync, cpSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { loadContent } from "../check/app_service/content.mjs";
const directory = resolve(".ubaa_local/server_package");
mkdirSync(directory, { recursive: true });
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
const { channels, announcements } = loadContent();
writeFileSync(
  `${directory}/content.json`,
  JSON.stringify({
    channels,
    announcements: announcements.filter((item) => item.app),
  }),
);
const result = spawnSync(
  "tar",
  ["-czf", resolve(".ubaa_local/app_service.tar.gz"), "-C", directory, "."],
  { stdio: "inherit" },
);
process.exitCode = result.status ?? 1;
