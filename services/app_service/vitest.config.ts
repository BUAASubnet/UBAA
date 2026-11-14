import { defineConfig } from "vitest/config";
export default defineConfig({
  envDir: false,
  test: { fileParallelism: false, setupFiles: ["./test/setup.ts"] },
});
