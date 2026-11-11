// 使用锁定 Hvigor SDK 的解密器验证 CI 生成的签名密码和材料。
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync, existsSync } from "node:fs";
import { delimiter, join, resolve } from "node:path";
import { test } from "node:test";
import { preparePasswords } from "../../release/platforms/ohos_signing.mjs";

test("Hvigor 可以用生成的材料解密两个原始签名密码", (t) => {
  const home = process.env.UBAA_DEVECO_HOME;
  assert.ok(home, "请设置 UBAA_DEVECO_HOME，使用锁定的 Hvigor SDK 运行测试");
  const sdk = join(home, existsSync(join(home, "tools")) ? "tools/hvigor" : "hvigor");
  const parent = resolve(".ubaa_local/tests");
  mkdirSync(parent, { recursive: true, mode: 0o700 });
  const directory = mkdtempSync(join(parent, "ohos_signing_"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const passwords = ["fixture123", "fixture key '$&!"];
  const encrypted = preparePasswords(directory, passwords);
  assert.equal(encrypted.length, 2);
  for (const value of encrypted) assert.match(value, /^[0-9a-f]{64,}$/);

  // Hvigor 的发行包以同级目录存放，在测试私有目录补充包名链接。
  const modules = join(directory, "node_modules");
  mkdirSync(join(modules, "@ohos"), { recursive: true });
  symlinkSync(join(sdk, "hvigor"), join(modules, "@ohos/hvigor"), "dir");
  const probe = join(directory, "probe.cjs");
  writeFileSync(probe, `
    const assert = require('node:assert/strict');
    const { DecipherUtil } = require(${JSON.stringify(join(sdk, "hvigor-ohos-plugin/src/utils/decipher-util.js"))});
    const passwords = ${JSON.stringify(passwords)};
    const encrypted = ${JSON.stringify(encrypted)};
    for (let i = 0; i < passwords.length; i++) {
      assert.equal(DecipherUtil.decryptPwd(${JSON.stringify(directory)}, encrypted[i], 'fixture'), passwords[i]);
    }
  `);
  const result = spawnSync(process.execPath, [probe], {
    encoding: "utf8",
    env: { ...process.env, NODE_PATH: [modules, join(sdk, "hvigor/node_modules"),
      join(sdk, "hvigor-ohos-plugin/node_modules")].join(delimiter) },
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
});
