import { mkdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import standalone from "ajv/dist/standalone/index.js";
import { build } from "esbuild";

const service = new URL("../", import.meta.url);
const output = new URL(".generated/", service);
const schema = JSON.parse(
  await readFile(
    new URL("../../docs/contracts/app-service.schema.json", service),
    "utf8",
  ),
);

const ajv = new Ajv2020({ code: { source: true, esm: true } });
addFormats(ajv);
ajv.addSchema(schema);

const definitions = {
  validateTelemetryShape: "telemetryRequest",
  validateEraseRequest: "eraseRequest",
  validateBootstrapRequest: "bootstrapRequest",
  validateBootstrapResponse: "bootstrapResponse",
  validateAnnouncement: "announcement",
  validateTelemetryErrorResponse: "telemetryErrorResponse",
};
const references = Object.fromEntries(
  Object.entries(definitions).map(([validator, definition]) => [
    validator,
    `${schema.$id}#/$defs/${definition}`,
  ]),
);

await mkdir(output, { recursive: true });
// 将格式和比较函数打包进静态模块；Worker 无需加载 Ajv 编译器。
await build({
  stdin: {
    contents: standalone(ajv, references),
    resolveDir: fileURLToPath(service),
  },
  outfile: fileURLToPath(new URL("validators.mjs", output)),
  bundle: true,
  platform: "browser",
  format: "esm",
  target: "es2022",
});
await writeFile(
  new URL("validators.d.mts", output),
  Object.keys(definitions)
    .map((name) => `export function ${name}(payload: unknown): boolean;\n`)
    .join(""),
);
