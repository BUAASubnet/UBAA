import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import worker from "./wrangler.json" with { type: "json" };

export default defineConfig({
  envDir: false,
  plugins: [
    cloudflareTest({
      remoteBindings: false,
      // 只复用运行时兼容设置，不加载 Wrangler 的本地密钥或资源。
      main: worker.main,
      miniflare: {
        compatibilityDate: worker.compatibility_date,
        compatibilityFlags: worker.compatibility_flags,
        d1Databases: ["DB"],
        kvNamespaces: ["APP_CONFIG"],
        bindings: { USER_KEY_SECRET: "synthetic-app-service-test" },
      },
    }),
  ],
});
