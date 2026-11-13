// Credential/egress boundary. No upstream credential is ever returned to a job.
import http from "node:http";
import https from "node:https";
import net from "node:net";
import dns from "node:dns/promises";
import { readFile, writeFile, rename, chown, stat } from "node:fs/promises";
import { pipeline } from "node:stream";
import { fileURLToPath } from "node:url";

const blocked = new net.BlockList();
for (const [address, prefix] of [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["100.64.0.0", 10],
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.0.2.0", 24],
  ["192.88.99.0", 24],
  ["198.51.100.0", 24],
  ["203.0.113.0", 24],
  ["192.168.0.0", 16],
  ["198.18.0.0", 15],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
])
  blocked.addSubnet(address, prefix, "ipv4");
export async function publicAddress(hostname, resolve = dns.lookup) {
  // IPv4-only egress deliberately avoids IPv6 transition/address-mapping bypasses.
  if (net.isIPv6(hostname)) throw new Error("Denied address");
  const { address } = await resolve(hostname, { family: 4 });
  if (!net.isIPv4(address) || blocked.check(address, "ipv4"))
    throw new Error("Denied address");
  return address;
}
const allowedModelPaths = new Set([
  "/model/responses",
  "/model/responses/compact",
  "/model/models",
]);
export function createProxy({ authFile }) {
  let refresh;
  async function credentials() {
    let value = JSON.parse(await readFile(authFile, "utf8"));
    const token = value.tokens?.access_token;
    if (!token) throw new Error("Missing model credential");
    const expiry = JSON.parse(
      Buffer.from(token.split(".")[1], "base64url"),
    ).exp;
    if (expiry * 1000 < Date.now() + 60000) {
      refresh ??= (async () => {
        const response = await fetch("https://auth.openai.com/oauth/token", {
          method: "POST",
          redirect: "error",
          signal: AbortSignal.timeout(20000),
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            grant_type: "refresh_token",
            refresh_token: value.tokens.refresh_token,
            client_id: "app_EMoamEEZ73f0CkXaXp7hrann",
          }),
        });
        if (!response.ok) throw new Error("Model refresh failed");
        const tokens = await response.json();
        value.tokens = { ...value.tokens, ...tokens };
        value.last_refresh = new Date().toISOString();
        const info = await stat(authFile);
        await writeFile(authFile + ".proxy-tmp", JSON.stringify(value), {
          mode: 0o600,
        });
        await chown(authFile + ".proxy-tmp", info.uid, info.gid);
        await rename(authFile + ".proxy-tmp", authFile);
      })().finally(() => {
        refresh = null;
      });
      await refresh;
      value = JSON.parse(await readFile(authFile, "utf8"));
    }
    return value.tokens;
  }
  const server = http.createServer(async (request, response) => {
    try {
      if (request.url === "/health" && request.method === "GET") {
        await credentials();
        response.writeHead(200, { "content-type": "application/json" });
        response.end('{"ready":true}');
        return;
      }
      let target, address, headers;
      if (request.url.startsWith("/model/")) {
        const path = request.url.split("?")[0];
        if (
          !allowedModelPaths.has(path) ||
          !["GET", "POST"].includes(request.method)
        )
          throw new Error("Denied model request");
        const tokens = await credentials();
        target = new URL(
          "https://chatgpt.com/backend-api/codex/" +
            request.url.slice("/model/".length),
        );
        headers = {
          "content-type": "application/json",
          accept: "text/event-stream",
          authorization: "Bearer " + tokens.access_token,
          "chatgpt-account-id": tokens.account_id,
        };
      } else {
        target = new URL(request.url);
        if (
          target.protocol !== "http:" ||
          target.username ||
          target.password ||
          (target.port && target.port !== "80")
        )
          throw new Error("Denied HTTP request");
        address = await publicAddress(target.hostname);
        // Jobs may use their own public-service headers; host credentials never
        // enter this path and DNS is pinned to the validated public address.
        headers = { ...request.headers, host: target.host };
        delete headers["proxy-authorization"];
        delete headers["proxy-connection"];
      }
      const transport = target.protocol === "https:" ? https : http;
      const upstream = transport.request(
        target,
        {
          method: request.method,
          headers,
          ...(address ? { lookup: (_h, _o, cb) => cb(null, address, 4) } : {}),
          timeout: 300000,
        },
        (reply) => {
          const responseHeaders = { ...reply.headers };
          // A host upstream must never echo credentials or cookies into the job.
          for (const key of [
            "authorization",
            "set-cookie",
            "proxy-authenticate",
          ])
            delete responseHeaders[key];
          response.writeHead(reply.statusCode, responseHeaders);
          pipeline(reply, response, () => {});
        },
      );
      upstream.on("timeout", () => upstream.destroy());
      upstream.on("error", () => {
        if (!response.headersSent) response.writeHead(502);
        response.end();
      });
      request.on("aborted", () => upstream.destroy());
      response.on("close", () => upstream.destroy());
      pipeline(request, upstream, () => {});
    } catch {
      response.writeHead(403);
      response.end();
    }
  });
  server.on("connect", async (request, client, head) => {
    try {
      const target = new URL("https://" + request.url);
      if (
        target.username ||
        target.password ||
        target.pathname !== "/" ||
        (target.port && target.port !== "443")
      )
        throw new Error("Denied tunnel");
      const address = await publicAddress(target.hostname);
      const upstream = net.connect({ host: address, port: 443 });
      upstream.once("connect", () => {
        client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
        if (head.length) upstream.write(head);
        client.pipe(upstream);
        upstream.pipe(client);
      });
      upstream.on("error", () => client.destroy());
      client.on("error", () => upstream.destroy());
      client.on("close", () => upstream.destroy());
      upstream.setTimeout(300000, () => upstream.destroy());
    } catch {
      client.end("HTTP/1.1 403 Forbidden\r\n\r\n");
    }
  });
  server.maxConnections = 32;
  server.headersTimeout = 10000;
  server.requestTimeout = 60000;
  return server;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const proxy = createProxy({ authFile: process.argv[2] });
  proxy.listen(process.env.LISTEN_FDS === "1" ? { fd: 3 } : process.argv[3]);
}
