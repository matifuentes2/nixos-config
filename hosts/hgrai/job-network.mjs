// Inside PrivateNetwork: expose only the host's constrained HTTP proxy socket.
import net from "node:net";
const server = net.createServer((client) => {
  const host = net.createConnection("/run/model-proxy.sock");
  client.pipe(host);
  host.pipe(client);
  host.on("error", () => client.destroy());
  client.on("error", () => host.destroy());
});
server.listen(8000, "127.0.0.1");
