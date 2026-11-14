const origin = "https://bhpan.buaa.edu.cn";

// 分享授权只用于当前页面，不携带云盘 Cookie，也不写入浏览器存储。
export async function resolveBrowserDownload(asset, token, send = fetch) {
  async function request(path, body) {
    const headers = new Headers({ Authorization: `Bearer ${token}` });
    if (body) headers.set("Content-Type", "application/json");
    const response = await send(`${origin}${path}`, {
      method: body ? "POST" : "GET",
      headers,
      body: body ? JSON.stringify(body) : undefined,
      credentials: "omit",
      redirect: "error",
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error("云盘请求失败");
    return response;
  }
  const entries = await (await request("/api/efast/v1/entry-item")).json();
  if (entries.length !== 1 || typeof entries[0].id !== "string")
    throw new Error("分享根目录无效");
  const listing = await (
    await request("/api/efast/v1/dir/list", {
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
    await request("/api/efast/v1/file/osdownload", {
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

async function prepareDownload() {
  const status = document.getElementById("download-status");
  const session = document.getElementById("download-session");
  try {
    const { asset, token } = JSON.parse(session.textContent);
    session.remove();
    const address = await resolveBrowserDownload(asset, token);
    const link = document.getElementById("download-link");
    link.href = address;
    link.hidden = false;
    status.textContent = "下载即将开始。如果没有自动开始，请点击“开始下载”。";
    window.location.assign(address);
  } catch {
    status.textContent = "北航云盘下载暂时不可用，请重试或使用备用下载。";
  }
}

if (typeof document !== "undefined") void prepareDownload();
