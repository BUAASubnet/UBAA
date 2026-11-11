import { constants, sign } from "node:crypto";
import { createReadStream, statSync, writeFileSync } from "node:fs";

const account = JSON.parse(process.env.APPGALLERY_SERVICE_ACCOUNT_JSON);
const appId = process.env.APPGALLERY_APP_ID;
const base = "https://connect-api.cloud.huawei.com/api";
function token() {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const payload = `${encode({ kid: account.key_id, typ: "JWT", alg: "PS256" })}.${encode({ aud: account.token_uri, iss: account.sub_account, iat: now, exp: now + 3600 })}`;
  const signature = sign("sha256", Buffer.from(payload), { key: account.private_key, padding: constants.RSA_PKCS1_PSS_PADDING, saltLength: 32 });
  return `${payload}.${signature.toString("base64url")}`;
}
async function api(path, { query = {}, method = "GET", body, headers = {} } = {}) {
  const url = new URL(base + path);
  url.search = new URLSearchParams(query).toString();
  const response = await fetch(url, { method, headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json", ...headers }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw Error(`AppGallery HTTP ${response.status}`);
  const result = await response.json();
  if (Number(result.ret?.code) !== 0) throw Error(`AppGallery ${result.ret?.code}: ${result.ret?.msg}`);
  return result;
}
const [operation, file] = process.argv.slice(2);
try {
  if (!appId) throw Error("缺少 APPGALLERY_APP_ID");
  if (operation === "probe") {
    const result = await api("/publish/v3/app-info", { query: { appId } });
    console.log(JSON.stringify({ status: "authorized", fields: Object.keys(result), app: result.appInfo && { packageName: result.appInfo.packageName, versionName: result.appInfo.versionName } }));
  } else if (operation === "upload" && file) {
    const fileName = file.split(/[\\/]/).at(-1);
    const size = statSync(file).size;
    const { urlInfo } = await api("/publish/v2/upload-url/for-obs", { query: { appId, fileName, contentLength: String(size) } });
    const response = await fetch(urlInfo.url, { method: urlInfo.method, headers: { ...urlInfo.headers, "Content-Length": String(size) }, body: createReadStream(file), duplex: "half", signal: AbortSignal.timeout(1800000) });
    if (!response.ok) throw Error(`AppGallery 文件上传 HTTP ${response.status}`);
    const result = await api("/publish/v3/app-package-info", { method: "PUT", query: { appId, releaseType: "1", releasePhase: "0" }, body: { fileName, objectId: urlInfo.objectId } });
    if (!result.packageId) throw Error("AppGallery 未返回软件包 ID");
    const packageId = result.packageId;
    console.log(`AppGallery 软件包已关联：${packageId}`);
    let ready = false;
    for (let attempt = 0; attempt < 120; attempt++) {
      const status = await api("/publish/v3/package/compile/status", { query: { appId, pkgIds: packageId } });
      const entry = status.pkgStateList?.find((item) => String(item.pkgId) === String(packageId));
      if (entry?.successStatus === 0) { ready = true; break; }
      if (entry?.successStatus === 2) throw Error("AppGallery 软件包解析失败");
      console.log("等待 AppGallery 软件包解析");
      await new Promise((resolve) => setTimeout(resolve, 30000));
    }
    if (!ready) throw Error("AppGallery 软件包仍在解析，请核对后续状态");
    writeFileSync(process.env.STORE_RESULT_FILE || ".ubaa_local/appgallery_result.json", JSON.stringify({ packageId, status: "ready_for_submission" }) + "\n");
    console.log("AppGallery 软件包处理完成，可提交审核");
  } else throw Error("用法：node scripts/release/stores/huawei.mjs probe|upload <APP文件>");
} catch (error) { console.error(error.message); process.exitCode = 1; }
