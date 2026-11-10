import { isTelemetryBodySizeAllowed } from "./schema";

export function invalidPayload(): Response {
  return Response.json("invalid_payload", { status: 400 });
}

export async function readJson(request: Request): Promise<unknown> {
  const type = request.headers.get("Content-Type")?.split(";", 1)[0];
  if (type?.trim().toLowerCase() !== "application/json") {
    return new Response(null, { status: 415 });
  }
  if (request.headers.has("Cookie") || request.headers.has("Authorization")) {
    return invalidPayload();
  }
  if (
    !isTelemetryBodySizeAllowed(
      Number(request.headers.get("Content-Length") ?? 0),
    )
  ) {
    return new Response(null, { status: 413 });
  }
  if (!request.body) return invalidPayload();

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (!isTelemetryBodySizeAllowed(size)) {
        await reader.cancel();
        return new Response(null, { status: 413 });
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(
      new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes),
    );
  } catch {
    return invalidPayload();
  }
}
