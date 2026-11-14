import manifest from "./download.json" with { type: "json" };
import source from "./download-source.json" with { type: "json" };

const origin = "https://bhpan.buaa.edu.cn";
const prefix = `/downloads/v${manifest.version}/${manifest.build}/`;

// 分享 Token 和下载签名只在一次请求内使用，不记录或持久化。
export async function resolveDownload(asset, send = fetch) {
  async function request(path, token, body, navigation = false) {
    const headers = new Headers();
    if (token) headers.set("Authorization", `Bearer ${token}`);
    if (body) headers.set("Content-Type", "application/json");
    const response = await send(`${origin}${path}`, {
      method: body ? "POST" : "GET",
      headers,
      body: body ? JSON.stringify(body) : undefined,
      redirect: "manual",
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok && !(navigation && response.status === 302))
      throw new Error("云盘请求失败");
    return response;
  }
  const info = await (
    await request(`/api/shared-link/v1/links/${source.shareId}`)
  ).json();
  if (info.password_required !== false) throw new Error("发布分享需要密码");
  const page = await request(
    `/link/${source.shareId}`,
    undefined,
    undefined,
    true,
  );
  const cookie = page.headers
    .getSetCookie()
    .find((value) => value.startsWith(`link_token:${source.shareId}=`));
  await page.body?.cancel();
  const token = cookie
    ?.split(";", 1)[0]
    .slice(`link_token:${source.shareId}=`.length);
  if (!token) throw new Error("分享授权缺失");
  const entries = await (
    await request("/api/efast/v1/entry-item", token)
  ).json();
  if (entries.length !== 1 || typeof entries[0].id !== "string")
    throw new Error("分享根目录无效");
  const listing = await (
    await request("/api/efast/v1/dir/list", token, {
      by: "name",
      docid: entries[0].id,
      sort: "asc",
    })
  ).json();
  const matches = listing.files.filter((item) => item.name === asset.name);
  const item = matches[0];
  if (
    matches.length !== 1 ||
    item.size !== asset.size ||
    typeof item.docid !== "string"
  ) {
    throw new Error("发布文件缺失或大小不符");
  }
  const download = await (
    await request("/api/efast/v1/file/osdownload", token, {
      docid: item.docid,
      authtype: "QUERY_STRING",
    })
  ).json();
  const [method, address] = download.authrequest;
  const url = new URL(address);
  if (method !== "GET" || url.protocol !== "https:")
    throw new Error("下载地址无效");
  return url.href;
}

export async function handleDownload(request, env, send = fetch) {
  const pathname = new URL(request.url).pathname;
  if (!pathname.startsWith("/downloads/")) return env.ASSETS.fetch(request);
  const headers = { "Cache-Control": "no-store" };
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response(null, {
      status: 405,
      headers: { ...headers, Allow: "GET, HEAD" },
    });
  }
  const asset = manifest.assets.find((item) => pathname === prefix + item.name);
  if (!asset) return new Response(null, { status: 404, headers });
  try {
    if (
      source.version !== manifest.version ||
      source.build !== manifest.build
    ) {
      throw new Error("分享配置与发布版本不符");
    }
    const location = await resolveDownload(asset, send);
    return new Response(null, {
      status: 302,
      headers: { ...headers, Location: location },
    });
  } catch {
    return new Response(
      request.method === "HEAD"
        ? null
        : "北航云盘下载暂时不可用，请返回下载页关闭“使用北航云盘下载”后重试。",
      {
        status: 502,
        headers: { ...headers, "Content-Type": "text/plain; charset=utf-8" },
      },
    );
  }
}

export default { fetch: (request, env) => handleDownload(request, env) };
