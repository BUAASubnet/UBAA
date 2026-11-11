// 将 CI Secrets 中的原始密码转换为 Hvigor 签名配置要求的密文。
// 格式依据锁定 SDK 6.26.4 的 hvigor-ohos-plugin/src/utils/decipher-util.js。
import { createCipheriv, pbkdf2Sync, randomBytes } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function encrypt(key, value) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-128-gcm", key, iv);
  const body = Buffer.concat([cipher.update(value), cipher.final(), cipher.getAuthTag()]);
  const size = Buffer.alloc(4);
  size.writeUInt32BE(body.length);
  return Buffer.concat([size, iv, body]);
}

export function preparePasswords(directory, passwords) {
  const material = join(directory, "material");
  mkdirSync(material, { mode: 0o700 });
  function write(name, data) {
    const folder = join(material, name);
    mkdirSync(folder, { recursive: true, mode: 0o700 });
    writeFileSync(join(folder, "value"), data, { mode: 0o600 });
  }
  const components = Array.from({ length: 3 }, () => randomBytes(16));
  components.forEach((value, index) => write(`fd/${index}`, value));
  const salt = randomBytes(16);
  write("ac", salt);
  // SDK 的固定公开组件；根密钥还依赖本次运行生成的三个随机组件和盐。
  const combined = Buffer.from([49, 243, 9, 115, 214, 175, 91, 184, 211, 190, 177, 88, 101, 131, 192, 119]);
  for (const component of components) {
    for (let i = 0; i < combined.length; i++) combined[i] ^= component[i];
  }
  const rootKey = pbkdf2Sync(combined.toString(), salt, 10000, 16, "sha256");
  const workKey = randomBytes(16);
  write("ce", encrypt(rootKey, workKey));
  return passwords.map((password) => encrypt(workKey, Buffer.from(password, "utf8")).toString("hex"));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const fields = ["OHOS_STORE_FILE", "OHOS_STORE_PASSWORD", "OHOS_KEY_PASSWORD"];
  for (const name of fields) {
    if (!process.env[name]) throw new Error(`签名配置缺少 ${name}`);
  }
  const values = preparePasswords(dirname(process.env.OHOS_STORE_FILE),
    [process.env.OHOS_STORE_PASSWORD, process.env.OHOS_KEY_PASSWORD]);
  // 由调用脚本捕获到内存；不把密码作为命令行参数或写进构建日志。
  process.stdout.write(values.join(" ") + "\n");
}
