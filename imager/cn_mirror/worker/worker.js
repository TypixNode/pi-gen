/**
 * dl.typixnode.com 的下载入口。
 *
 * R2 里有对象就直接吐（快，且出网不计费）；还没同步上来的，就由 Cloudflare
 * 边缘代拉 GitHub Release 并流式转发 —— 用户始终走就近的 CF 节点，
 * 不会掉回直连 GitHub 那条 70 KB/s 的线，也永远不会看到 404。
 *
 * 路由：dl.typixnode.com/           → 302 到 /index.html
 *       dl.typixnode.com/images/*   → 本 Worker
 *       其余路径（repo.json、icons/**）仍由 R2 自定义域名直接服务
 */

const GITHUB_REPO = "TypixNode/pi-gen";

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }

    const url = new URL(request.url);

    // R2 自定义域名不做 index 文档解析，根路径自己跳
    if (url.pathname === "/") {
      return Response.redirect(`${url.origin}/index.html`, 302);
    }

    const key = decodeURIComponent(url.pathname.replace(/^\//, ""));   // images/<tag>/<file>
    const parts = key.split("/");
    if (parts[0] !== "images" || parts.length !== 3) {
      return new Response("Not Found", { status: 404 });
    }
    const [, tag, filename] = parts;

    // ---- 快路径：R2
    if (request.method === "HEAD") {
      const head = await env.BUCKET.head(key);
      if (head) {
        const headers = new Headers();
        head.writeHttpMetadata(headers);
        headers.set("etag", head.httpEtag);
        headers.set("content-length", String(head.size));
        headers.set("accept-ranges", "bytes");
        headers.set("cache-control", "public, max-age=31536000, immutable");
        headers.set("x-mirror-source", "r2");
        return new Response(null, { status: 200, headers });
      }
    }

    const object = await env.BUCKET.get(key, {
      range: request.headers,
      onlyIf: request.headers,
    });
    if (object) {
      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set("etag", object.httpEtag);
      headers.set("accept-ranges", "bytes");
      headers.set("cache-control", "public, max-age=31536000, immutable");
      headers.set("x-mirror-source", "r2");
      const body = "body" in object ? object.body : null;
      const status = body ? (request.headers.get("range") ? 206 : 200) : 304;
      if (object.range && body) {
        const { offset = 0, length = object.size - offset } = object.range;
        headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
        headers.set("content-length", String(length));
      } else if (body) {
        // R2 不会自动带 content-length，缺了它浏览器显示"未知大小"、也没法断点续传
        headers.set("content-length", String(object.size));
      }
      return new Response(request.method === "HEAD" ? null : body, { status, headers });
    }

    // ---- 兜底：边缘代拉 GitHub Release，流式转发
    const origin = `https://github.com/${GITHUB_REPO}/releases/download/${tag}/${filename}`;
    const upstream = await fetch(origin, {
      method: request.method,
      headers: pick(request.headers, ["range", "if-range", "accept-encoding"]),
      redirect: "follow",
    });
    const headers = new Headers(upstream.headers);
    headers.set("x-mirror-source", "github-origin");
    headers.set("cache-control", "public, max-age=31536000, immutable");
    headers.delete("set-cookie");
    return new Response(upstream.body, { status: upstream.status, headers });
  },
};

function pick(headers, names) {
  const out = new Headers();
  for (const n of names) {
    const v = headers.get(n);
    if (v) out.set(n, v);
  }
  return out;
}
