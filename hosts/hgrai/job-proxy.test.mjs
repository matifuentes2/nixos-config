import test from "node:test";
import assert from "node:assert/strict";
import { publicAddress, createProxy } from "./job-proxy.mjs";
import http from "node:http";

test("public egress rejects loopback, private, link-local, CGNAT and transition addresses", async () => {
  for (const address of [
    "0.0.0.0",
    "127.0.0.1",
    "10.1.2.3",
    "172.16.2.3",
    "192.168.1.2",
    "169.254.169.254",
    "100.100.100.100",
    "224.0.0.1",
    "::1",
    "::ffff:127.0.0.1",
  ]) {
    await assert.rejects(() =>
      publicAddress("host", async () => ({ address })),
    );
  }
  assert.equal(
    await publicAddress("public", async () => ({ address: "93.184.216.34" })),
    "93.184.216.34",
  );
});
test("DNS answers are validated and non-allowlisted model paths never read credentials", async (t) => {
  const proxy = createProxy({ authFile: "/does/not/exist" });
  await new Promise((r) => proxy.listen(0, "127.0.0.1", r));
  t.after(() => new Promise((r) => proxy.close(r)));
  for (const path of [
    "/model/oauth/token",
    "http://127.0.0.1/",
    "http://169.254.169.254/latest/meta-data/",
    "http://100.100.100.100/",
  ]) {
    const status = await new Promise((resolve, reject) => {
      const req = http.get(
        { host: "127.0.0.1", port: proxy.address().port, path },
        (res) => {
          res.resume();
          resolve(res.statusCode);
        },
      );
      req.on("error", reject);
    });
    assert.equal(status, 403);
  }
});
