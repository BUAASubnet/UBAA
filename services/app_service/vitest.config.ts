import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { URL, fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import worker from "./wrangler.json" with { type: "json" };

const migrations = await readD1Migrations(
  fileURLToPath(
    new URL(worker.d1_databases[0].migrations_dir, import.meta.url),
  ),
);

export default defineConfig({
  envDir: false,
  plugins: [
    cloudflareTest({
      remoteBindings: false,
      // 只复用运行时配置，不加载 Wrangler 的本地密钥或资源。
      main: worker.main,
      miniflare: {
        compatibilityDate: worker.compatibility_date,
        compatibilityFlags: worker.compatibility_flags,
        d1Databases: worker.d1_databases.map(({ binding }) => binding),
        kvNamespaces: worker.kv_namespaces.map(({ binding }) => binding),
        ratelimits: Object.fromEntries(
          worker.ratelimits.map(({ name, namespace_id, simple }) => {
            const { period } = simple;
            if (period !== 10 && period !== 60) {
              throw new Error("无效的限流窗口");
            }
            return [
              name,
              { namespace_id, simple: { limit: simple.limit, period } },
            ];
          }),
        ),
        bindings: {
          USER_KEY_SECRET: "synthetic-app-service-test",
          TEST_MIGRATIONS: migrations,
        },
      },
    }),
  ],
});
