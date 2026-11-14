import defaultManifest from "./download.json" with { type: "json" };
import defaultSource from "./download-source.json" with { type: "json" };

const origin = "https://bhpan.buaa.edu.cn";


// 只取得公开发布分享的临时 Token，交给浏览器完成后续下载。
export async function getShareToken(send = fetch, shareId = defaultSource.shareId) {
  async function request(path, navigation = false) {
    const response = await send(`${origin}${path}`, {
      method: "GET",
      redirect: "manual",
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok && !(navigation && response.status === 302))
      throw new Error("云盘请求失败");
    return response;
  }
  const info = await (
    await request(`/api/shared-link/v1/links/${shareId}`)
  ).json();
  if (info.password_required !== false) throw new Error("发布分享需要密码");
  const page = await request(`/link/${shareId}`, true);
  const cookie = page.headers
    .getSetCookie()
    .find((value) => value.startsWith(`link_token:${shareId}=`));
  await page.body?.cancel();
  const token = cookie
    ?.split(";", 1)[0]
    .slice(`link_token:${shareId}=`.length);
  if (!token) throw new Error("分享授权缺失");
  return token;
}

export async function handleDownload(request, env, send = fetch, manifest = defaultManifest, source = defaultSource) {
  const prefix = `/downloads/v${manifest.version}/${manifest.build}/`;
  const pathname = new URL(request.url).pathname;
  if (!pathname.startsWith("/downloads/")) return env.ASSETS.fetch(request);
  const headers = {
    "Cache-Control": "no-store",
    "Content-Type": "text/html; charset=utf-8",
  };
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response(null, {
      status: 405,
      headers: { ...headers, Allow: "GET, HEAD" },
    });
  }
  const asset = manifest.assets.find((item) => pathname === prefix + item.name);
  if (!asset) return new Response(null, { status: 404, headers });
  if (request.method === "HEAD") return new Response(null, { headers });
  try {
    if (
      source.version !== manifest.version ||
      source.build !== manifest.build
    ) {
      throw new Error("分享配置与发布版本不符");
    }
    const token = await getShareToken(send, source.shareId);
    return new Response(downloadPage({ ...asset, directory: source.directory ?? [] }, token), { headers });
  } catch {
    return new Response(downloadPage(asset), { status: 502, headers });
  }
}

function downloadPage(asset, token) {
  const payload = token
    ? `<script id="download-session" type="application/json">${JSON.stringify({ token, asset }).replaceAll("<", "\\u003c")}</script><script type="module" src="/download_client.js"></script>`
    : "";
  return `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>下载 UBAA</title>
<style>body{font-family:system-ui,sans-serif;max-width:640px;margin:12vh auto;padding:0 24px;line-height:1.7;color:#243247;background:#f7f9fc}main{padding:28px;border:1px solid #dbe3ec;border-radius:16px;background:white}h1{font-size:24px;margin-top:0}p{overflow-wrap:anywhere}nav{display:flex;flex-wrap:wrap;gap:20px;margin-top:24px}a{color:#1976d2}#download-link{font-weight:600}</style></head>
<body><main><h1>下载 UBAA</h1><p>${asset.name}</p><p id="download-status" role="status">${token ? "正在获取下载地址，请稍候…" : "北航云盘暂时不可用，请重试或使用备用下载。"}</p><a id="download-link" hidden>开始下载</a><nav><a href="">重新尝试</a><a href="${asset.url}">备用下载</a><a href="/download">返回下载页</a></nav><noscript><p>使用北航云盘下载需要启用 JavaScript，也可以选择备用下载。</p></noscript></main>${payload}</body></html>`;
}

export default { fetch: (request, env) => handleDownload(request, env) };
