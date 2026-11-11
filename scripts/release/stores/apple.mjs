import { sign } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";

function privateKey() {
  const key = process.env.APPSTORE_PRIVATE_KEY;
  return key?.includes("BEGIN PRIVATE KEY") ? key : Buffer.from(key || "", "base64").toString();
}
function token() {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const value = `${encode({ alg: "ES256", kid: process.env.APPSTORE_KEY_ID, typ: "JWT" })}.${encode({ iss: process.env.APPSTORE_ISSUER_ID, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" })}`;
  return `${value}.${sign("sha256", Buffer.from(value), { key: privateKey(), dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}
async function api(path) {
  const response = await fetch("https://api.appstoreconnect.apple.com/v1" + path, { headers: { Authorization: `Bearer ${token()}` }, signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw Error(`App Store Connect HTTP ${response.status}`);
  return response.json();
}
try {
  const apps = await api("/apps?filter[bundleId]=cn.edu.ubaa");
  const app = apps.data?.[0];
  if (!app) throw Error("App Store Connect 找不到 cn.edu.ubaa");
  console.log(`App Store Connect 应用访问成功：${app.id}`);
  const [operation, file] = process.argv.slice(2);
  if (operation === "probe") {
    if (process.platform === "darwin") {
      const directory = resolve(".ubaa_local/release/apple_api");
      mkdirSync(directory, { recursive: true, mode: 0o700 });
      const keyPath = `${directory}/AuthKey_${process.env.APPSTORE_KEY_ID}.p8`;
      writeFileSync(keyPath, privateKey(), { mode: 0o600 });
      const history = spawnSync("xcrun", ["notarytool", "history", "--key", keyPath, "--key-id", process.env.APPSTORE_KEY_ID, "--issuer", process.env.APPSTORE_ISSUER_ID, "--output-format", "json"], { encoding: "utf8" });
      if (history.status !== 0) throw Error("Apple API 密钥不能访问公证服务");
      console.log("Apple 公证服务访问成功");
    }
    const builds = await api(`/builds?filter[app]=${app.id}&sort=-uploadedDate&limit=5`);
    console.log(JSON.stringify(builds.data.map((entry) => ({ build: entry.attributes.version, processing: entry.attributes.processingState }))));
  } else if (operation === "upload" && file) {
    const version = process.env.RELEASE_VERSION;
    const buildNumber = process.env.RELEASE_BUILD;
    const lookup = async () => {
      const result = await api(`/builds?filter[app]=${app.id}&filter[version]=${buildNumber}&include=preReleaseVersion`);
      return result.data.find((entry) => result.included?.some((included) => included.id === entry.relationships.preReleaseVersion.data.id && included.attributes.version === version));
    };
    let build = await lookup();
    if (!build) {
      const directory = resolve(".ubaa_local/release/apple_api");
      mkdirSync(directory, { recursive: true, mode: 0o700 });
      writeFileSync(`${directory}/AuthKey_${process.env.APPSTORE_KEY_ID}.p8`, privateKey(), { mode: 0o600 });
      const upload = spawnSync("xcrun", ["altool", "--upload-app", "--type", "ios", "--file", file, "--apiKey", process.env.APPSTORE_KEY_ID, "--apiIssuer", process.env.APPSTORE_ISSUER_ID], { env: { ...process.env, API_PRIVATE_KEYS_DIR: directory }, stdio: "inherit" });
      if (upload.status !== 0) throw Error("App Store Connect 上传失败");
    }
    for (let attempt = 0; attempt < 120; attempt++) {
      build = await lookup();
      if (build?.attributes.processingState === "VALID") break;
      if (["FAILED", "INVALID"].includes(build?.attributes.processingState)) throw Error("Apple 构建处理失败");
      console.log("等待 Apple 处理构建");
      await new Promise((resolve) => setTimeout(resolve, 30000));
    }
    if (build?.attributes.processingState !== "VALID") throw Error("Apple 构建仍未处理完成，请核对后续状态");
    writeFileSync(process.env.STORE_RESULT_FILE || ".ubaa_local/appstore_result.json", JSON.stringify({ appId: app.id, buildId: build.id, version, build: buildNumber, status: "ready_for_submission" }) + "\n");
    console.log("Apple 构建处理完成，可选择并提交审核");
  } else throw Error("用法：node scripts/release/stores/apple.mjs probe|upload <IPA文件>");
} catch (error) { console.error(error.message); process.exitCode = 1; }
